import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide StackFrame;

import '../models/debugger_models.dart';
import 'base_debugger.dart';
import 'debugger_environment.dart';
import 'debugger_snapshot.dart';

/// A debugger for Python 3 programs.
///
/// Technique: a generated `sys.settrace` driver. Rather than trying to drive
/// `pdb` (whose prompts are fragile to parse and buffer badly), the user's
/// source is executed by a small wrapper script that installs a line tracer,
/// pauses on breakpoints or while single-stepping, and speaks a tiny
/// line-oriented protocol with the IDE over stdin/stdout:
///
///     driver -> IDE : @@BORLAND_PAUSED <json>   (paused, with locals & stack)
///     IDE -> driver : BPS <csv> | CONT | STEP | OUT | QUIT
///
/// Everything crossing the boundary is JSON, so no value has to be quoted by
/// hand, and program output is forwarded verbatim to [output].
///
/// Known limitations, documented deliberately:
///  * a script that reads stdin shares the control pipe with the debugger, so
///    interactive input is not supported while stepping;
///  * step-over and step-into both advance a single line (Python's tracer has
///    no "step over a call" primitive); step-out runs until the caller's line.
class PythonDebugger extends BaseDebugger {
  PythonDebugger({this.executablePath = 'python3'});

  /// Prefix the driver uses for its structured pause notifications.
  static const String pauseMarker = '@@BORLAND_PAUSED ';

  /// Python 3 executable used to run the tracer driver (overridable for tests).
  final String executablePath;
  Process? _process;
  final List<String> _tempDirectories = [];
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  bool _disposed = false;

  /// The path the caller supplied, used to match gutter breakpoints.
  String? _sourcePath;

  @override
  Future<void> startDebugging(String filePath, {String? content}) async {
    if (state != DebugState.inactive) return;

    // Tests never spawn a real interpreter.
    if (DebuggerEnvironment.shouldShortCircuit) {
      state = DebugState.running;
      emitOutput('[Debugging Python: ${_basename(filePath)}]');
      notifyListeners();
      return;
    }

    _sourcePath = filePath;
    try {
      final target = await _prepareScript(filePath, content);
      if (target == null) {
        emitOutput(
          '[Python debugging failed: no source available for "$filePath"]',
        );
        state = DebugState.stopped;
        notifyListeners();
        return;
      }
      final driverDir = await _newTempDirectory('borland_py_debug_');
      final driverFile = File(
        '${driverDir.path}${Platform.pathSeparator}borland_py_driver.py',
      );
      await driverFile.writeAsString(_driverSource);

      final breakpointFile = File(
        '${driverDir.path}${Platform.pathSeparator}borland_py_breakpoints.json',
      );
      await breakpointFile.writeAsString(_encodeBreakpoints());

      final process = await Process.start(executablePath, <String>[
        '-u',
        driverFile.path,
        target,
        breakpointFile.path,
      ], workingDirectory: File(target).parent.path);

      _process = process;
      state = DebugState.running;
      currentPausedLine = null;
      emitOutput('[Debugging Python 3: ${_basename(target)}]');
      notifyListeners();

      _watchStreams(process);
      _watchExit(process);
    } catch (e) {
      emitOutput('[Failed to start Python debug session: $e]');
      state = DebugState.stopped;
      notifyListeners();
    }
  }

  Future<String?> _prepareScript(String filePath, String? content) async {
    final file = File(filePath);
    if (await file.exists()) return file.absolute.path;
    if (content == null || content.trim().isEmpty) return null;

    final dir = await _newTempDirectory('borland_py_source_');
    // Untitled buffers carry no extension; keep the temp copy recognisably
    // Python so tracebacks and banners read sensibly.
    final name = _basename(filePath);
    final fileName = name.endsWith('.py') ? name : '$name.py';
    final target = File('${dir.path}${Platform.pathSeparator}$fileName');
    await target.writeAsString(content);
    return target.path;
  }

  Future<Directory> _newTempDirectory(String prefix) async {
    final dir = await Directory.systemTemp.createTemp(prefix);
    _tempDirectories.add(dir.path);
    return dir;
  }

  void _watchStreams(Process process) {
    _stdoutSubscription = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          _onStdoutLine,
          onError: (Object error) =>
              debugPrint('[PythonDebugger] stdout error: $error'),
        );

    _stderrSubscription = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.trim().isNotEmpty) emitOutput(line);
          },
          onError: (Object error) =>
              debugPrint('[PythonDebugger] stderr error: $error'),
        );
  }

  /// Feeds a raw stdout [line] through the pause/console handler.
  ///
  /// Exposed so the pause protocol can be exercised without spawning a real
  /// `python3` process.
  @visibleForTesting
  void handleStdoutLine(String line) => _onStdoutLine(line);

  void _onStdoutLine(String line) {
    if (line.startsWith(pauseMarker)) {
      _handlePause(line.substring(pauseMarker.length));
      return;
    }
    if (line.trim().isEmpty) return;
    emitOutput(line);
  }

  void _handlePause(String jsonPayload) {
    final snapshot = DebugSnapshot.tryParse(jsonPayload);
    if (snapshot == null) {
      emitOutput('[Python debugger received a malformed pause payload]');
      return;
    }

    callStack
      ..clear()
      ..addAll(snapshot.stack);
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
    _resumeWith('CONT');
  }

  @override
  Future<void> stepOver() async {
    _resumeWith('STEP');
  }

  @override
  Future<void> stepInto() async {
    _resumeWith('STEP');
  }

  @override
  Future<void> stepOut() async {
    _resumeWith('OUT');
  }

  void _resumeWith(String command) {
    if (state != DebugState.paused) return;
    // Flush gutter edits made while paused before asking the tracer to move on.
    _pushBreakpoints();
    _writeCommand(command);
    state = DebugState.running;
    currentPausedLine = null;
    notifyListeners();
  }

  void _writeCommand(String command) {
    final process = _process;
    if (process == null) return;
    try {
      process.stdin.writeln(command);
    } catch (e) {
      debugPrint('[PythonDebugger] Failed to send "$command": $e');
    }
  }

  void _pushBreakpoints() {
    if (state != DebugState.paused || _process == null) return;
    _writeCommand('BPS ${_encodeBreakpoints()}');
  }

  @override
  void setBreakpoint(String filePath, int line) {
    super.setBreakpoint(filePath, line);
    _pushBreakpoints();
  }

  @override
  void removeBreakpoint(String filePath, int line) {
    super.removeBreakpoint(filePath, line);
    _pushBreakpoints();
  }

  @override
  void clearBreakpoints() {
    super.clearBreakpoints();
    _pushBreakpoints();
  }

  @override
  void clearBreakpointsForFile(String filePath) {
    super.clearBreakpointsForFile(filePath);
    _pushBreakpoints();
  }

  String _encodeBreakpoints() {
    final path = _sourcePath;
    final lines =
        breakpoints
            .where((bp) => path == null || _pathsMatch(bp.filePath, path))
            .map((bp) => bp.line)
            .toSet()
            .toList()
          ..sort();
    return lines.join(',');
  }

  void _watchExit(Process process) {
    unawaited(
      process.exitCode.then((int code) async {
        if (_disposed || _process != process) return;
        _process = null;
        await _cleanupTemp();
        state = DebugState.inactive;
        currentPausedLine = null;
        variables.clear();
        callStack.clear();
        emitOutput('[Python debugging session ended (exit code $code)]');
        if (!_disposed) notifyListeners();
      }),
    );
  }

  @override
  Future<void> stopDebugging() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    final process = _process;
    _process = null;
    final wasActive = state != DebugState.inactive;
    if (process != null) {
      try {
        process.stdin.writeln('QUIT');
      } catch (e) {
        debugPrint('[PythonDebugger] Failed to send QUIT: $e');
      }
      process.kill(ProcessSignal.sigkill);
    }

    await _cleanupTemp();

    state = DebugState.inactive;
    currentPausedLine = null;
    variables.clear();
    callStack.clear();
    if (wasActive) emitOutput('[Python debugging stopped]');
    if (!_disposed) notifyListeners();
  }

  Future<void> _cleanupTemp() async {
    final directories = List<String>.from(_tempDirectories);
    _tempDirectories.clear();
    for (final path in directories) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (e) {
        debugPrint('[PythonDebugger] Failed to clean temp dir $path: $e');
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(stopDebugging());
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

/// The `sys.settrace` driver the debugger writes next to a temporary copy of
/// the script under debug. It is embedded (rather than shipped as an asset) so
/// a debug session needs no extra files on disk.
const String _driverSource = r'''import json
import os
import sys

PAUSE_MARKER = "@@BORLAND_PAUSED "

_TARGET = None
_DRIVER_FILE = os.path.abspath(__file__)
_breakpoints = set()
_step_mode = "none"
_step_depth = 0
_entered = False


def _emit(payload):
    sys.stdout.write(PAUSE_MARKER + json.dumps(payload) + "\n")
    sys.stdout.flush()


def _read_command():
    line = sys.stdin.readline()
    if not line:
        return "QUIT"
    return line.strip().upper()


def _load_breakpoints(raw):
    global _breakpoints
    lines = set()
    for entry in raw.split(","):
        entry = entry.strip()
        if entry.isdigit():
            lines.add(int(entry))
    _breakpoints = lines


def _collect_variables(frame, limit=200):
    result = []
    for name in sorted(frame.f_locals):
        if name.startswith("__"):
            continue
        value = frame.f_locals[name]
        if callable(value) or isinstance(value, type):
            continue
        try:
            text = repr(value)
        except Exception:
            text = "<unrepresentable>"
        if len(text) > limit:
            text = text[: limit - 3] + "..."
        result.append({
            "name": name,
            "value": text,
            "type": type(value).__name__,
        })
    return result


def _collect_stack(frame, limit=32):
    result = []
    current = frame
    while current is not None and len(result) < limit:
        code = current.f_code
        if os.path.abspath(code.co_filename) == _DRIVER_FILE:
            break
        result.append({
            "name": code.co_name,
            "file": code.co_filename,
            "line": current.f_lineno,
        })
        current = current.f_back
    return result


def _depth(frame):
    count = 0
    current = frame
    while current is not None:
        if current.f_code.co_filename == _TARGET:
            count += 1
        current = current.f_back
    return count


def _pause(frame, reason):
    global _step_mode, _step_depth
    _emit({
        "file": _TARGET,
        "line": frame.f_lineno,
        "reason": reason,
        "vars": _collect_variables(frame),
        "stack": _collect_stack(frame),
    })
    while True:
        command = _read_command()
        if command == "QUIT":
            os._exit(0)
        if command == "CONT":
            _step_mode = "none"
            return
        if command == "STEP":
            _step_mode = "step"
            return
        if command == "OUT":
            _step_mode = "out"
            _step_depth = _depth(frame)
            return
        if command.startswith("BPS "):
            _load_breakpoints(command[4:])
            continue


def _trace(frame, event, arg):
    global _entered
    if frame.f_code.co_filename != _TARGET:
        return None
    if event != "line":
        return _trace
    if frame.f_code.co_name == "<module>" and not _entered:
        _entered = True
        _pause(frame, "entry")
    elif _step_mode == "step":
        _pause(frame, "step")
    elif _step_mode == "out" and _depth(frame) < _step_depth:
        _pause(frame, "step")
    elif frame.f_lineno in _breakpoints:
        _pause(frame, "breakpoint")
    return _trace


def main():
    global _TARGET
    if len(sys.argv) < 2:
        sys.stderr.write("borland debug driver: missing target script\n")
        return
    _TARGET = sys.argv[1]
    if len(sys.argv) > 2:
        try:
            with open(sys.argv[2], "r") as handle:
                _load_breakpoints(handle.read().strip())
        except OSError:
            pass
    try:
        with open(_TARGET, "r") as handle:
            source = handle.read()
    except OSError as error:
        sys.stderr.write("borland debug driver: %s\n" % error)
        return
    namespace = {"__name__": "__main__", "__file__": _TARGET}
    code = compile(source, _TARGET, "exec")
    sys.settrace(_trace)
    try:
        exec(code, namespace)
    finally:
        sys.settrace(None)


if __name__ == "__main__":
    main()
''';
