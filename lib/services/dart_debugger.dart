import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide StackFrame;

import '../models/debugger_models.dart';
import '../utils/vm_service_client.dart';
import 'base_debugger.dart';
import 'debugger_environment.dart';

/// A debugger for Dart programs, driven by the official Dart VM Service
/// protocol.
///
/// The program is launched with the VM service enabled and the isolate paused
/// on start. As soon as the service endpoint is printed, the debugger attaches
/// to it over its WebSocket API (see [VmServiceClient]), mirrors the user's
/// breakpoints into the running isolate, and translates VM pause events
/// (breakpoints, stepping, uncaught exceptions) into [DebugState] transitions,
/// populating [variables] and [callStack] from the real isolate state.
///
/// All process management lives in the services layer, honouring the project's
/// architecture rule that UI widgets never touch `Process` directly.
class DartDebugger extends BaseDebugger {
  DartDebugger({String executablePath = 'dart'})
    : _dartExecutable = executablePath;

  final String _dartExecutable;

  Process? _process;
  VmServiceClient? _client;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  String? _isolateId;
  String? _tempDirectory;
  bool _disposed = false;

  /// VM breakpoint ids keyed by `<filePath>:<line>` so they can be removed.
  final Map<String, String> _vmBreakpointIds = {};

  /// Absolute path of the script handed to the VM, used to pick the entry
  /// script out of the root library's script list while attaching.
  String? _debuggedScriptPath;

  /// VM breakpoint id of the implicit `main` entry breakpoint that makes Debug
  /// pause inside the user's program. Tracked apart from [_vmBreakpointIds] so
  /// that editing or clearing the gutter breakpoints mid-session cannot delete
  /// it - mirroring the C/C++ debugger's entry-breakpoint handling.
  String? _entryBreakpointId;

  @override
  Future<void> startDebugging(String filePath, {String? content}) async {
    if (state != DebugState.inactive) return;

    // Unit tests must never spawn a real process.
    if (DebuggerEnvironment.shouldShortCircuit) {
      state = DebugState.running;
      emitOutput('[Debugging Dart: ${_basename(filePath)}]');
      notifyListeners();
      return;
    }

    try {
      final scriptPath = await _prepareScript(filePath, content);
      if (scriptPath == null) {
        debugPrint('[DartDebugger] No debuggable script for "$filePath"');
        emitOutput(
          '[Dart debugging failed: no debuggable script for "$filePath"]',
        );
        state = DebugState.stopped;
        notifyListeners();
        return;
      }

      _debuggedScriptPath = File(scriptPath).absolute.path;

      final process = await Process.start(_dartExecutable, <String>[
        '--enable-vm-service=0',
        '--disable-service-auth-codes',
        '--pause-isolates-on-start',
        '--enable-asserts',
        scriptPath,
      ]);
      _process = process;

      state = DebugState.running;
      currentPausedLine = null;
      emitOutput('[Debugging Dart: ${_basename(scriptPath)}]');
      notifyListeners();

      _watchOutput(process);
      _watchExit(process);
    } catch (e) {
      debugPrint('[DartDebugger] Error starting debug session: $e');
      emitOutput('[Failed to start Dart debug session: $e]');
      state = DebugState.stopped;
      notifyListeners();
    }
  }

  /// Resolves the script to debug: the file on disk when it exists, otherwise
  /// a temporary copy of the in-memory [content] (unsaved / untitled buffers).
  Future<String?> _prepareScript(String filePath, String? content) async {
    final file = File(filePath);
    if (await file.exists()) return filePath;
    if (content == null || content.trim().isEmpty) return null;

    final dir = await Directory.systemTemp.createTemp('borland_dart_debug_');
    _tempDirectory = dir.path;
    // Untitled buffers carry no extension, but the VM expects a .dart path.
    final name = _basename(filePath);
    final fileName = name.endsWith('.dart') ? name : '$name.dart';
    final target = File('${dir.path}${Platform.pathSeparator}$fileName');
    await target.writeAsString(content);
    return target.path;
  }

  void _watchOutput(Process process) {
    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          (line) {
            debugPrint('[DartDebugger] $line');
            if (line.trim().isNotEmpty) emitOutput(line);
            final uri = _extractServiceUri(line);
            if (uri != null && _client == null && !_disposed) {
              unawaited(_attach(uri));
            }
          },
          onError: (Object e) {
            debugPrint('[DartDebugger] stdout error: $e');
            emitOutput('[Dart debugger stdout error: $e]');
          },
        );

    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.trim().isNotEmpty) {
              debugPrint('[DartDebugger] $line');
              emitOutput(line);
            }
          },
          onError: (Object e) {
            debugPrint('[DartDebugger] stderr error: $e');
            emitOutput('[Dart debugger stderr error: $e]');
          },
        );
  }

  void _watchExit(Process process) {
    process.exitCode.then((code) {
      if (_disposed) return;
      _process = null;
      if (state != DebugState.inactive) {
        state = DebugState.inactive;
        currentPausedLine = null;
        variables.clear();
        callStack.clear();
        emitOutput('[Dart debugging session ended (exit code $code)]');
        notifyListeners();
      }
    });
  }

  /// Extracts the VM Service HTTP URI from a VM stdout line. Handles both the
  /// modern ("The Dart VM service is listening on ...") and legacy
  /// ("Observatory listening on ...") wording.
  String? _extractServiceUri(String line) {
    final match = RegExp(r'listening on (https?://\S+)').firstMatch(line);
    return match?.group(1);
  }

  Future<void> _attach(String httpUri) async {
    try {
      final client = await VmServiceClient.connect(httpUri);
      if (_disposed) {
        await client.dispose();
        return;
      }
      _client = client;
      _eventSubscription = client.events.listen(_onDebugEvent);
      emitOutput('[Attached to the Dart VM service]');

      await client.call('streamListen', <String, dynamic>{'streamId': 'Debug'});
      await client.call('streamListen', <String, dynamic>{
        'streamId': 'Isolate',
      });

      final vm = await client.call('getVM');
      final isolates = vm?['isolates'];
      if (isolates is List && isolates.isNotEmpty) {
        final first = isolates.first;
        if (first is Map && first['id'] is String) {
          _isolateId = first['id'] as String;
        }
      }
      if (_isolateId == null) {
        debugPrint('[DartDebugger] No isolate found in VM service');
        emitOutput('[No Dart isolate found in the VM service]');
        return;
      }

      // Mirror breakpoints that were set before the session started.
      for (final bp in List<Breakpoint>.from(breakpoints)) {
        await _registerBreakpoint(bp);
      }

      // The isolate is paused *before* its Dart entrypoint
      // (--pause-isolates-on-start), so its stack holds only VM-internal
      // `dart:` frames - there is no user frame to surface yet. Install a
      // breakpoint on the root script's top-level `main` and let the isolate
      // run into it, mirroring the C/C++ debugger's implicit
      // `breakpoint set --name main`. The id is tracked separately so clearing
      // gutter breakpoints mid-session cannot delete it.
      await _installEntryBreakpointAndResume();
    } catch (e) {
      debugPrint('[DartDebugger] Failed to attach to the VM service: $e');
      emitOutput('[Failed to attach to the Dart VM service: $e]');
    }
  }

  /// Resolves the isolate's root script, sets a breakpoint on its top-level
  /// `main`, then resumes the isolate so it runs into that breakpoint.
  ///
  /// Best-effort throughout: if the script or `main` cannot be found we log to
  /// the Console and still resume, so the program runs to completion instead of
  /// hanging forever paused before its entrypoint.
  Future<void> _installEntryBreakpointAndResume() async {
    final client = _client;
    final isolateId = _isolateId;
    if (client == null || isolateId == null || _disposed) return;

    await _installEntryBreakpoint();
    if (_disposed) return;
    await client.call('resume', <String, dynamic>{'isolateId': isolateId});
  }

  /// Installs (and remembers) the implicit `main` entry breakpoint.
  Future<void> _installEntryBreakpoint() async {
    final client = _client;
    final isolateId = _isolateId;
    final target = _debuggedScriptPath;
    if (client == null || isolateId == null || target == null) return;

    // 1. The root library lists every script reachable from the entrypoint.
    //    `getVM` can hand back the isolate before it has finished being created,
    //    in which case `getIsolate` reports a null `rootLib` and no entry
    //    breakpoint can be resolved. Wait for the isolate to reach its
    //    `--pause-isolates-on-start` stop before reading it.
    final isolate = await _awaitIsolateReady(client, isolateId);
    final rootLib = isolate?['rootLib'];
    final rootLibId = rootLib is Map ? rootLib['id'] : null;
    if (rootLibId is! String) {
      _reportNoEntryBreakpoint('the isolate has no root library');
      return;
    }

    final library = await client.call('getObject', <String, dynamic>{
      'isolateId': isolateId,
      'objectId': rootLibId,
    });
    final scripts = library?['scripts'];
    if (scripts is! List) {
      _reportNoEntryBreakpoint('the root library exposes no scripts');
      return;
    }

    // 2. Pick the script that is the file being debugged.
    Map<String, dynamic>? script;
    for (final candidate in scripts) {
      if (candidate is! Map<String, dynamic>) continue;
      final uri = candidate['uri'];
      if (uri is String && _scriptMatches(uri, target)) {
        script = candidate;
        break;
      }
    }
    final scriptId = script?['id'];
    final scriptUri = script?['uri'];
    if (scriptId is! String || scriptUri is! String) {
      _reportNoEntryBreakpoint('no loaded script matches "$target"');
      return;
    }

    // 3. Read its source to locate the top-level `main` declaration.
    final sourceObject = await client.call('getObject', <String, dynamic>{
      'isolateId': isolateId,
      'objectId': scriptId,
    });
    final source = sourceObject?['source'];
    if (source is! String) {
      _reportNoEntryBreakpoint('the entry script has no source');
      return;
    }
    final mainLine = findMainLine(source);
    if (mainLine == null) {
      _reportNoEntryBreakpoint('no `main` declaration in ${_basename(target)}');
      return;
    }

    // 4. Install the entry breakpoint and remember its id out of band.
    final result = await client.call(
      'addBreakpointWithScriptUri',
      <String, dynamic>{
        'isolateId': isolateId,
        'scriptUri': scriptUri,
        'line': mainLine,
      },
    );
    final id = result?['id'];
    if (id is String) {
      _entryBreakpointId = id;
    } else {
      _reportNoEntryBreakpoint('the VM rejected the `main` breakpoint');
    }
  }

  void _reportNoEntryBreakpoint(String reason) {
    debugPrint('[DartDebugger] No entry breakpoint: $reason');
    emitOutput(
      '[Dart debugger could not pause at main ($reason); '
      'the program will run to completion]',
    );
  }

  /// Waits until the isolate has finished starting and exposes its root
  /// library, then returns its `getIsolate` record.
  ///
  /// `getVM` can report the isolate before it has been fully created, so an
  /// immediate `getIsolate` returns a null `rootLib`. The isolate is launched
  /// with `--pause-isolates-on-start`, so it stays stopped until we resume it:
  /// poll until `rootLib` is populated (or the isolate has reached its
  /// `PauseStart` stop) instead of racing the start-up, which would leave no
  /// entry breakpoint and let the program run to completion without a pause.
  ///
  /// Best-effort: after the retries it returns the last observed record (which
  /// the caller validates), never throwing.
  Future<Map<String, dynamic>?> _awaitIsolateReady(
    VmServiceClient client,
    String isolateId,
  ) async {
    Map<String, dynamic>? isolate;
    for (var attempt = 0; attempt < 100; attempt++) {
      if (_disposed) return null;
      isolate = await client.call('getIsolate', <String, dynamic>{
        'isolateId': isolateId,
      });
      final rootLib = isolate?['rootLib'];
      final pauseEvent = isolate?['pauseEvent'];
      final ready =
          (rootLib is Map && rootLib['id'] is String) ||
          (pauseEvent is Map && pauseEvent['kind'] == 'PauseStart');
      if (ready) return isolate;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return isolate;
  }

  /// Whether a VM script [uri] refers to the file being debugged at [target].
  bool _scriptMatches(String uri, String target) {
    final path = _uriToPath(uri);
    if (path.isEmpty) return false;
    final candidate = File(path).absolute.path;
    final wanted = File(target).absolute.path;
    return candidate == wanted || _basename(candidate) == _basename(wanted);
  }

  void _onDebugEvent(Map<String, dynamic> event) {
    if (_disposed) return;

    final isolate = event['isolate'];
    if (isolate is Map && isolate['id'] is String) {
      _isolateId = isolate['id'] as String;
    }

    final kind = event['kind'] as String? ?? '';
    switch (kind) {
      case 'PauseBreakpoint':
      case 'PauseInterrupted':
      case 'PauseException':
      case 'PausePostRequest':
        unawaited(_refreshPausedState());
      case 'PauseExit':
      case 'IsolateExit':
        state = DebugState.inactive;
        currentPausedLine = null;
        variables.clear();
        callStack.clear();
        notifyListeners();
      case 'Resume':
        state = DebugState.running;
        currentPausedLine = null;
        notifyListeners();
      case 'IsolateStart':
        break;
    }
  }

  /// Pulls the current top-of-stack frame, variables and call stack from the
  /// paused isolate and publishes them as [DebugState.paused].
  Future<void> _refreshPausedState() async {
    final client = _client;
    final isolateId = _isolateId;
    if (client == null || isolateId == null || _disposed) return;

    final stack = await client.call('getStack', <String, dynamic>{
      'isolateId': isolateId,
    });
    if (_disposed) return;

    applyStackSnapshot(stack);
  }

  /// Maps a `getStack` response onto [callStack], [variables],
  /// [currentPausedLine] and [DebugState.paused].
  ///
  /// A pause is only published when the *top* frame points at real user code:
  /// frames with an empty path (no source information) or a `dart:` URI
  /// (`dart:isolate-patch/...`, `dart:core`, ...) are VM/runtime internals. The
  /// isolate reports such a stack when it is paused on start, before the Dart
  /// entrypoint runs - publishing that would make the gutter highlight a line
  /// that does not exist. In that case we stay running and emit nothing.
  ///
  /// Exposed so the paused-line mapping can be unit tested without a live VM
  /// Service - attaching to a real VM needs a spawned `dart` process.
  @visibleForTesting
  void applyStackSnapshot(Map<String, dynamic>? stack) {
    final frames = stack?['frames'];
    final newStack = <StackFrame>[];
    final newVars = <Variable>[];
    Map<String, dynamic>? topRaw;

    if (frames is List) {
      for (final raw in frames) {
        if (raw is! Map<String, dynamic>) continue;

        final location = raw['location'];
        var line = 0;
        var column = 0;
        var filePath = '';
        if (location is Map<String, dynamic>) {
          line = location['line'] as int? ?? 0;
          column = location['column'] as int? ?? 0;
          filePath = _scriptPath(location['script']);
        }

        newStack.add(
          StackFrame(
            name: _refName(raw['function']) ?? '<anonymous>',
            filePath: filePath,
            line: line,
            column: column,
          ),
        );
        topRaw ??= raw;
      }
    }

    final top = newStack.isEmpty ? null : newStack.first;
    if (top == null || !_isUserFrame(top)) {
      // No usable user frame: never fabricate a pause. Stay running and make
      // sure no stale gutter arrow survives.
      debugPrint(
        '[DartDebugger] Ignoring stack with no user frame '
        '(${newStack.length} internal/empty frame(s))',
      );
      callStack.clear();
      variables.clear();
      currentPausedLine = null;
      state = DebugState.running;
      notifyListeners();
      return;
    }

    // Keep only real user frames, in order, so the call stack the UI shows is
    // never polluted by `dart:` internals.
    final userFrames = newStack.where(_isUserFrame).toList();
    if (topRaw != null) {
      final vars = topRaw['vars'];
      if (vars is List) {
        for (final v in vars) {
          if (v is Map<String, dynamic>) newVars.add(_toVariable(v));
        }
      }
    }

    callStack
      ..clear()
      ..addAll(userFrames);
    variables
      ..clear()
      ..addAll(newVars);
    currentPausedLine = top.line;
    state = DebugState.paused;
    emitOutput('[Paused at ${_basename(top.filePath)}:${top.line}]');
    notifyListeners();
  }

  Variable _toVariable(Map<String, dynamic> bound) {
    final name = bound['name'] as String? ?? '?';
    final value = bound['value'];
    if (value is Map<String, dynamic>) {
      final type =
          _refName(value['class']) ?? (value['kind'] as String? ?? 'dynamic');
      final display =
          value['valueAsString'] as String? ?? _instanceLabel(value);
      return Variable(name: name, value: display, type: type);
    }
    return Variable(
      name: name,
      value: value?.toString() ?? 'null',
      type: 'dynamic',
    );
  }

  String _instanceLabel(Map<String, dynamic> value) {
    final kind = value['kind'] as String?;
    if (kind == 'Null') return 'null';
    return _refName(value['class']) ?? kind ?? '…';
  }

  String? _refName(Object? ref) {
    if (ref is Map && ref['name'] is String) return ref['name'] as String;
    return null;
  }

  String _scriptPath(Object? script) {
    if (script is Map && script['uri'] is String) {
      return _uriToPath(script['uri'] as String);
    }
    return '';
  }

  /// Converts a VM script URI to a filesystem path, leaving non-file URIs
  /// (`dart:core`, `package:foo/bar.dart`) untouched.
  String _uriToPath(String uri) {
    if (uri.startsWith('file://')) {
      try {
        return Uri.parse(uri).toFilePath();
      } catch (_) {
        return uri;
      }
    }
    return uri;
  }

  Future<void> _resume({required String step}) async {
    final client = _client;
    final isolateId = _isolateId;
    if (client == null || isolateId == null || _disposed) return;

    state = DebugState.running;
    currentPausedLine = null;
    notifyListeners();

    await client.call('resume', <String, dynamic>{
      'isolateId': isolateId,
      'step': step,
    });
  }

  @override
  Future<void> stepOver() => _resume(step: 'Over');

  @override
  Future<void> stepInto() => _resume(step: 'Into');

  @override
  Future<void> stepOut() => _resume(step: 'Out');

  @override
  Future<void> continueExecution() => _resume(step: 'None');

  @override
  void setBreakpoint(String filePath, int line) {
    super.setBreakpoint(filePath, line);
    final bp = breakpoints.isEmpty ? null : breakpoints.last;
    if (bp != null) unawaited(_registerBreakpoint(bp));
  }

  @override
  void removeBreakpoint(String filePath, int line) {
    super.removeBreakpoint(filePath, line);
    _detachVmBreakpoint(_breakpointKey(filePath, line));
  }

  @override
  void clearBreakpoints() {
    final keys = _vmBreakpointIds.keys.toList();
    super.clearBreakpoints();
    for (final key in keys) {
      _detachVmBreakpoint(key);
    }
  }

  @override
  void clearBreakpointsForFile(String filePath) {
    final keys = breakpoints
        .where(
          (bp) =>
              bp.filePath == filePath ||
              bp.filePath.endsWith(filePath) ||
              filePath.endsWith(bp.filePath),
        )
        .map((bp) => _breakpointKey(bp.filePath, bp.line))
        .toList();
    super.clearBreakpointsForFile(filePath);
    for (final key in keys) {
      _detachVmBreakpoint(key);
    }
  }

  Future<void> _registerBreakpoint(Breakpoint bp) async {
    final client = _client;
    final isolateId = _isolateId;
    if (client == null || isolateId == null || _disposed) return;

    final scriptUri = Uri.file(File(bp.filePath).absolute.path).toString();
    final result = await client.call(
      'addBreakpointWithScriptUri',
      <String, dynamic>{
        'isolateId': isolateId,
        'scriptUri': scriptUri,
        'line': bp.line,
      },
    );
    final id = result?['id'];
    if (id is String) {
      _vmBreakpointIds[_breakpointKey(bp.filePath, bp.line)] = id;
    }
  }

  void _detachVmBreakpoint(String key) {
    final id = _vmBreakpointIds.remove(key);
    final client = _client;
    final isolateId = _isolateId;
    if (id == null || client == null || isolateId == null) return;
    unawaited(
      client.call('removeBreakpoint', <String, dynamic>{
        'isolateId': isolateId,
        'breakpointId': id,
      }),
    );
  }

  String _breakpointKey(String filePath, int line) => '$filePath:$line';

  /// Matches a top-level `main` declaration on a Dart source line:
  /// `void main() {`, `Future<void> main() async {`, `main() {`,
  /// `void main() => ...` and the same forms with the body on the next line.
  static final RegExp _mainDeclaration = RegExp(
    r'^[ \t]*(?:[\w<>,?\[\]\s]+\s+)?main\s*\([^)]*\)\s*(?:async\s*)?(?:=>|\{|$)',
  );

  /// Returns the 1-based line of the first top-level `main` declaration in
  /// [source], or `null` when there is none.
  ///
  /// This is a best-effort textual heuristic (no Dart parser is available
  /// without new dependencies): it recognises the common declaration shapes and
  /// rejects indented calls such as `x.main()` or `runApp(main)`. A `main`
  /// declared in an unusual layout (e.g. the `{` on its own line, or extra
  /// annotations) can be missed, in which case no entry breakpoint is installed
  /// and the program simply runs to completion.
  @visibleForTesting
  static int? findMainLine(String source) {
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (_mainDeclaration.hasMatch(lines[i])) return i + 1;
    }
    return null;
  }

  /// Whether [frame] points at real user code rather than a VM/runtime internal
  /// (`dart:` URIs such as `dart:isolate-patch/...`) or a location the VM could
  /// not resolve (no source path, or line 0).
  static bool _isUserFrame(StackFrame frame) {
    final path = frame.filePath;
    return path.isNotEmpty && !path.startsWith('dart:') && frame.line > 0;
  }

  /// VM id of the implicit `main` entry breakpoint, or `null` when none is
  /// installed. Exposed so tests can verify it survives gutter edits/clears.
  @visibleForTesting
  String? get entryBreakpointId => _entryBreakpointId;

  @visibleForTesting
  set entryBreakpointId(String? id) => _entryBreakpointId = id;

  /// Last path segment of [path], used for compact Console banners.
  static String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }

  @override
  Future<void> stopDebugging() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    await _client?.dispose();
    _client = null;
    _isolateId = null;
    _vmBreakpointIds.clear();
    _entryBreakpointId = null;
    _debuggedScriptPath = null;

    final process = _process;
    _process = null;
    process?.kill(ProcessSignal.sigkill);

    await _cleanupTemp();

    final wasActive = state != DebugState.inactive;
    state = DebugState.inactive;
    currentPausedLine = null;
    variables.clear();
    callStack.clear();
    if (wasActive) emitOutput('[Dart debugging stopped]');
    if (!_disposed) notifyListeners();
  }

  Future<void> _cleanupTemp() async {
    final dir = _tempDirectory;
    _tempDirectory = null;
    if (dir == null) return;
    try {
      final directory = Directory(dir);
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (e) {
      debugPrint('[DartDebugger] Failed to clean temp dir: $e');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(stopDebugging());
    super.dispose();
  }
}
