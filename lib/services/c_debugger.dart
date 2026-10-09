import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide StackFrame;

import '../models/debugger_models.dart';
import 'base_debugger.dart';
import 'debugger_environment.dart';
import 'debugger_snapshot.dart';
import 'language_runner_service.dart';

/// A debugger for C and C++ programs.
///
/// Technique: compile with `clang -g -O0` and drive `lldb` over stdio. This is
/// the native-debugger route (as opposed to source instrumentation) because it
/// yields real variable values and call stacks instead of printf breadcrumbs.
///
/// Rather than scraping lldb's interactive output - whose prompt and framing
/// are unstable across versions - the debugger installs its own small lldb
/// command which a target stop-hook runs after *every* stop:
///
///     lldb <- command script import <helper>     (registers `borland_snapshot`)
///     lldb <- target stop-hook add -o borland_snapshot
///     lldb -> @@BORLAND_SNAP <json>              (stopped: file/line/vars/stack)
///
/// That JSON uses the same shape [DebugSnapshot] already understands, so the
/// parse path is shared with the Python debugger and is unit-testable without
/// launching anything.
///
/// Known limitations, documented deliberately:
///  * requires `clang`/`clang++` and `lldb` on the PATH (the same toolchain the
///    runner already relies on for compiling);
///  * a program that reads stdin shares the command pipe with lldb;
///  * breakpoints are set by source basename + line, matching how lldb resolves
///    locations from debug info.
class CDebugger extends BaseDebugger {
  CDebugger({
    this.clangPath = 'clang',
    this.clangPlusPlusPath = 'clang++',
    this.lldbPath = 'lldb',
  });

  /// Prefix the lldb helper uses for its structured stop notifications.
  static const String snapshotMarker = '@@BORLAND_SNAP ';

  /// Compilers and debugger used for a session (overridable for tests).
  final String clangPath;
  final String clangPlusPlusPath;
  final String lldbPath;

  Process? _lldb;
  final List<String> _tempDirectories = [];
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final List<int> _lldbBreakpointIds = [];
  bool _disposed = false;
  bool _exitHandled = false;

  /// lldb's `LLDB_INVALID_LINE_NUMBER`. Stops with no debug information report
  /// this instead of a real line, and such a stop happens at the dynamic-loader
  /// entry (`_dyld_start`) at the start of *every* session, before `main`.
  static const int invalidLineNumber = 0xFFFFFFFF;

  /// Breakpoint id of the implicit `main` breakpoint that makes Debug pause
  /// immediately. Tracked apart from [_lldbBreakpointIds] so that editing the
  /// gutter breakpoints mid-session cannot delete it.
  int? _entryBreakpointId;
  bool _awaitingEntryBreakpointId = false;

  /// The path the caller supplied, used to match gutter breakpoints.
  String? _sourcePath;

  /// The source file actually compiled (a temp copy for unsaved buffers).
  String? _compiledSource;

  bool _isCpp = false;

  /// Whether this session is compiling/debugging C++ (as opposed to C).
  bool get isCpp => _isCpp;

  @override
  Future<void> startDebugging(String filePath, {String? content}) async {
    if (state != DebugState.inactive) return;

    // Tests never shell out to clang or lldb.
    if (DebuggerEnvironment.shouldShortCircuit) {
      state = DebugState.running;
      emitOutput('[Debugging ${_basename(filePath)}]');
      notifyListeners();
      return;
    }

    _sourcePath = filePath;
    _isCpp =
        LanguageRunnerService.resolveLanguage(
          filePath,
          content ?? '',
        ).extension ==
        '.cpp';

    try {
      final source = await _prepareSource(filePath, content);
      if (source == null) {
        emitOutput('[C debugging failed: no source available for "$filePath"]');
        state = DebugState.stopped;
        notifyListeners();
        return;
      }
      _compiledSource = source;

      final executable = await _compile(source);
      if (executable == null) {
        state = DebugState.stopped;
        notifyListeners();
        return;
      }

      final process = await Process.start(lldbPath, <String>[executable]);
      _lldb = process;
      _exitHandled = false;
      state = DebugState.running;
      currentPausedLine = null;
      emitOutput('[Debugging ${_isCpp ? 'C++' : 'C'}: ${_basename(source)}]');
      notifyListeners();

      _watchStreams(process);
      _watchExit(process);
      await _configure(source);
    } catch (e) {
      emitOutput('[Failed to start C debug session: $e]');
      state = DebugState.stopped;
      notifyListeners();
    }
  }

  Future<String?> _prepareSource(String filePath, String? content) async {
    final file = File(filePath);
    if (await file.exists()) return file.absolute.path;
    if (content == null || content.trim().isEmpty) return null;

    final dir = await _newTempDirectory('borland_c_source_');
    final name = _isCpp ? 'main.cpp' : 'main.c';
    final source = File('${dir.path}${Platform.pathSeparator}$name');
    await source.writeAsString(content);
    return source.path;
  }

  Future<String?> _compile(String source) async {
    final dir = await _newTempDirectory('borland_c_build_');
    final executable = '${dir.path}${Platform.pathSeparator}borland_c_exec';
    final compiler = _isCpp ? clangPlusPlusPath : clangPath;
    final arguments = <String>[
      '-g',
      '-O0',
      if (_isCpp) '-std=c++17',
      '-o',
      executable,
      source,
    ];

    emitOutput('[Compiling with ${_basename(compiler)}...]');

    final ProcessResult result;
    try {
      result = await Process.run(compiler, arguments);
    } catch (e) {
      emitOutput('[Compiler not found ($e). Please install clang/GCC.]');
      return null;
    }

    _emitBlock(result.stdout is String ? result.stdout as String : '');
    _emitBlock(result.stderr is String ? result.stderr as String : '');

    if (result.exitCode != 0) {
      emitOutput('[Compilation failed with code ${result.exitCode}]');
      return null;
    }
    return executable;
  }

  Future<void> _configure(String source) async {
    final scriptDir = await _newTempDirectory('borland_lldb_');
    final scriptFile = File(
      '${scriptDir.path}${Platform.pathSeparator}borland_lldb.py',
    );
    await scriptFile.writeAsString(_lldbHelperSource);

    _write('command script import "${scriptFile.path}"');
    _write(
      'command script add -f borland_lldb.borland_snapshot borland_snapshot',
    );
    _write('target stop-hook add -o borland_snapshot');
    _resyncBreakpoints();
    // Stop at `main` so pressing Debug pauses immediately, the same way the
    // Dart VM (`--pause-isolates-on-start`) and the Python tracer do. Without
    // it lldb only stops at the loader entry - which carries no source line -
    // and then runs the program straight to completion, so no marker appears.
    _awaitingEntryBreakpointId = true;
    _write('breakpoint set --name main');
    _write('run');
  }

  void _watchStreams(Process process) {
    _stdoutSubscription = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          _onStdoutLine,
          onError: (Object error) =>
              debugPrint('[CDebugger] stdout error: $error'),
        );

    _stderrSubscription = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.trim().isNotEmpty) emitOutput(line);
          },
          onError: (Object error) =>
              debugPrint('[CDebugger] stderr error: $error'),
        );
  }

  /// Feeds a raw lldb stdout [line] through the stop/console handler.
  ///
  /// Exposed so the stop protocol can be exercised without launching lldb.
  @visibleForTesting
  void handleStdoutLine(String line) => _onStdoutLine(line);

  void _onStdoutLine(String line) {
    if (line.startsWith(snapshotMarker)) {
      _handleSnapshot(line.substring(snapshotMarker.length));
      return;
    }

    final breakpointId = parseBreakpointId(line);
    if (breakpointId != null) {
      if (_awaitingEntryBreakpointId) {
        _entryBreakpointId = breakpointId;
        _awaitingEntryBreakpointId = false;
      } else {
        _lldbBreakpointIds.add(breakpointId);
      }
      emitOutput(line);
      return;
    }

    final exitCode = parseExitCode(line);
    if (exitCode != null) {
      emitOutput(line);
      unawaited(_handleInferiorExit(exitCode));
      return;
    }

    if (line.trim().isEmpty) return;
    if (_isLldbChatter(line)) return;
    emitOutput(line);
  }

  /// lldb echoes every command it is fed and prints a thread/frame/source block
  /// on each stop. Our own `[Paused at ...]` report already covers that, so the
  /// raw block is dropped to keep the Console readable.
  static bool _isLldbChatter(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('(lldb)')) return true;
    if (trimmed.startsWith('* thread #')) return true;
    if (trimmed.startsWith('frame #')) return true;
    // lldb's source listing and its caret marker, e.g. "   9  \t  int x = 1;"
    // and "      ^".
    if (RegExp(r'^\d+\s+\t').hasMatch(trimmed)) return true;
    if (trimmed.startsWith('^')) return true;
    if (RegExp(r'^Target \d+: \(.*\) stopped\.$').hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^Process \d+ stopped$').hasMatch(trimmed)) return true;
    return false;
  }

  /// Parses the numeric id from an lldb `Breakpoint 3: ...` line.
  ///
  /// Returns `null` for any other line so the caller can keep forwarding output.
  @visibleForTesting
  static int? parseBreakpointId(String line) {
    final match = RegExp(r'^Breakpoint (\d+):').firstMatch(line.trim());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// Parses the exit code from an lldb `exited with status = 0` line.
  ///
  /// Returns `null` when the line is not an inferior-exit notification.
  @visibleForTesting
  static int? parseExitCode(String line) {
    final match = RegExp(r'exited with status = (-?\d+)').firstMatch(line);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  void _handleSnapshot(String jsonPayload) {
    final snapshot = DebugSnapshot.tryParse(jsonPayload);
    if (snapshot == null) {
      emitOutput('[C debugger received a malformed stop payload]');
      return;
    }
    // Stops without debug info - the dynamic-loader entry and shared-library
    // events - report LLDB_INVALID_LINE_NUMBER and no file. They fire at the
    // start of every session, so skipping them is what keeps the gutter from
    // being asked to highlight a line that does not exist.
    if (snapshot.filePath.isEmpty ||
        snapshot.line <= 0 ||
        snapshot.line == invalidLineNumber) {
      return;
    }

    // The same bogus location also shows up as an outer frame (the C runtime's
    // `start`), so drop any frame that has no usable source location.
    final frames = snapshot.stack
        .where(
          (frame) =>
              frame.filePath.isNotEmpty &&
              frame.line > 0 &&
              frame.line != invalidLineNumber,
        )
        .toList();

    callStack
      ..clear()
      ..addAll(frames);
    variables
      ..clear()
      ..addAll(snapshot.variables);
    currentPausedLine = snapshot.line;
    state = DebugState.paused;
    emitOutput(
      '[Paused at ${_basename(snapshot.filePath)}:${snapshot.line}'
      ' (${snapshot.reason})]',
    );
    notifyListeners();
  }

  @override
  Future<void> continueExecution() async {
    _resumeWith('continue');
  }

  @override
  Future<void> stepOver() async {
    _resumeWith('next');
  }

  @override
  Future<void> stepInto() async {
    _resumeWith('step');
  }

  @override
  Future<void> stepOut() async {
    _resumeWith('finish');
  }

  void _resumeWith(String command) {
    // Only meaningful while paused; queuing a command while lldb is already
    // running would fire it at the *next* unrelated stop.
    if (state != DebugState.paused || _lldb == null) return;
    _write(command);
    state = DebugState.running;
    currentPausedLine = null;
    notifyListeners();
  }

  void _write(String command) {
    final process = _lldb;
    if (process == null) return;
    try {
      process.stdin.writeln(command);
    } catch (e) {
      debugPrint('[CDebugger] Failed to send "$command": $e');
    }
  }

  void _resyncBreakpoints() {
    if (_lldb == null) return;
    final entryId = _entryBreakpointId;
    for (final id in _lldbBreakpointIds) {
      // Defensive: the implicit `main` breakpoint must outlive a resync.
      if (id == entryId) continue;
      _write('breakpoint delete $id');
    }
    _lldbBreakpointIds.clear();

    final source = _compiledSource;
    if (source == null) return;
    for (final line in _linesFor(source)) {
      _write('breakpoint set --file "${_basename(source)}" --line $line');
    }
  }

  @override
  void setBreakpoint(String filePath, int line) {
    super.setBreakpoint(filePath, line);
    _resyncBreakpoints();
  }

  @override
  void removeBreakpoint(String filePath, int line) {
    super.removeBreakpoint(filePath, line);
    _resyncBreakpoints();
  }

  @override
  void clearBreakpoints() {
    super.clearBreakpoints();
    _resyncBreakpoints();
  }

  @override
  void clearBreakpointsForFile(String filePath) {
    super.clearBreakpointsForFile(filePath);
    _resyncBreakpoints();
  }

  List<int> _linesFor(String source) {
    final path = _sourcePath;
    final lines =
        breakpoints
            .where((bp) => path == null || _pathsMatch(bp.filePath, path))
            .map((bp) => bp.line)
            .toSet()
            .toList()
          ..sort();
    return lines;
  }

  Future<void> _handleInferiorExit(int exitCode) async {
    if (_exitHandled) return;
    _exitHandled = true;
    emitOutput('[${_isCpp ? 'C++' : 'C'} program exited with code $exitCode]');
    await _finalize();
  }

  void _watchExit(Process process) {
    unawaited(
      process.exitCode.then((int code) async {
        if (_disposed || _lldb != process) return;
        emitOutput('[lldb session ended (exit code $code)]');
        await _finalize();
      }),
    );
  }

  @override
  Future<void> stopDebugging() async {
    final wasActive = state != DebugState.inactive;
    await _finalize();
    if (wasActive) {
      emitOutput('[${_isCpp ? 'C++' : 'C'} debugging stopped]');
    }
  }

  Future<void> _finalize() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    final process = _lldb;
    _lldb = null;
    if (process != null) {
      try {
        process.stdin.writeln('quit');
      } catch (e) {
        debugPrint('[CDebugger] Failed to send quit: $e');
      }
      process.kill(ProcessSignal.sigkill);
    }

    await _cleanupTemp();

    state = DebugState.inactive;
    currentPausedLine = null;
    variables.clear();
    callStack.clear();
    _entryBreakpointId = null;
    _awaitingEntryBreakpointId = false;
    if (!_disposed) notifyListeners();
  }

  Future<Directory> _newTempDirectory(String prefix) async {
    final dir = await Directory.systemTemp.createTemp(prefix);
    _tempDirectories.add(dir.path);
    return dir;
  }

  Future<void> _cleanupTemp() async {
    final directories = List<String>.from(_tempDirectories);
    _tempDirectories.clear();
    for (final path in directories) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (e) {
        debugPrint('[CDebugger] Failed to clean temp dir $path: $e');
      }
    }
  }

  void _emitBlock(String block) {
    for (final line in const LineSplitter().convert(block)) {
      if (line.trim().isNotEmpty) emitOutput(line);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_finalize());
    super.dispose();
  }

  static bool _pathsMatch(String a, String b) =>
      a == b || a.endsWith(b) || b.endsWith(a);

  static String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }
}

/// The lldb helper script the debugger writes before starting a session.
///
/// It defines the `borland_snapshot` command that a target stop-hook runs after
/// every stop, printing one `@@BORLAND_SNAP <json>` line the Dart side decodes.
const String _lldbHelperSource = r'''import json
import sys


def _location(entity):
    entry = entity.GetLineEntry()
    return {
        "file": entry.GetFileSpec().GetFilename(),
        "line": entry.GetLine(),
    }


def borland_snapshot(debugger, command, result, internal_dict):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess() if target else None
    if process is None:
        return
    thread = process.GetSelectedThread()
    if thread is None:
        return
    frame = thread.GetSelectedFrame()

    variables = []
    if frame is not None:
        for var in frame.GetVariables(True, True, False, True):
            name = var.GetName()
            if not name or name.startswith("__"):
                continue
            variables.append({
                "name": name,
                "value": var.GetValue() or "",
                "type": var.GetTypeName() or "",
            })

    stack = []
    for index in range(thread.GetNumFrames()):
        item = thread.GetFrameAtIndex(index)
        entry = item.GetLineEntry()
        stack.append({
            "name": item.GetFunctionName() or "<unknown>",
            "file": entry.GetFileSpec().GetFilename(),
            "line": entry.GetLine(),
        })

    location = _location(frame) if frame is not None else {"file": "", "line": 0}
    payload = {
        "file": location["file"],
        "line": location["line"],
        "reason": str(thread.GetStopReason()),
        "vars": variables,
        "stack": stack,
    }
    sys.stdout.write("@@BORLAND_SNAP " + json.dumps(payload) + "\n")
    sys.stdout.flush()
''';
