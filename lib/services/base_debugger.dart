import 'dart:async';

import 'package:flutter/foundation.dart' hide StackFrame;

import '../models/debugger_models.dart';

/// Shared base class for every language-specific debugger.
///
/// Each concrete debugger (Dart, Python, C/C++) drives a different runtime but
/// exposes the same surface to the IDE: a [state], the [breakpoints] the user
/// toggled in the gutter, the [variables]/[callStack] captured while paused and
/// a stream of human-readable [output] lines.
///
/// [output] is the single channel through which debugging activity becomes
/// visible in the Console panel. Concrete debuggers only describe *what*
/// happened; they never touch the UI or the runner service directly.
abstract class BaseDebugger extends ChangeNotifier {
  DebugState state = DebugState.inactive;
  int? currentPausedLine;
  final List<Breakpoint> breakpoints = [];
  final List<Variable> variables = [];
  final List<StackFrame> callStack = [];

  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  /// Broadcast stream of debugger output lines (session banners, pause
  /// notices, compiler/runtime errors and exit codes).
  ///
  /// Consumers such as the IDE shell subscribe once and forward every line to
  /// the Console so debugging is no longer silent.
  Stream<String> get output => _outputController.stream;

  /// Publishes a single line of debugger output to [output].
  ///
  /// Lines sent after [dispose] are dropped, so debuggers may call this from
  /// asynchronous callbacks without extra lifetime checks. Callers are expected
  /// to pass plain single-line text (no trailing newline).
  @protected
  void emitOutput(String line) {
    if (!_outputController.isClosed) {
      _outputController.add(line);
    }
  }

  // Abstract methods that each language debugger must implement
  Future<void> startDebugging(String filePath, {String? content});
  Future<void> stopDebugging();
  Future<void> stepOver();
  Future<void> stepInto();
  Future<void> stepOut();
  Future<void> continueExecution();

  // Common methods
  void setBreakpoint(String filePath, int line) {
    final bp = Breakpoint(filePath: filePath, line: line, verified: true);
    breakpoints.add(bp);
    notifyListeners();
  }

  void removeBreakpoint(String filePath, int line) {
    breakpoints.removeWhere((bp) => bp.filePath == filePath && bp.line == line);
    notifyListeners();
  }

  void clearBreakpoints() {
    breakpoints.clear();
    notifyListeners();
  }

  void clearBreakpointsForFile(String filePath) {
    breakpoints.removeWhere(
      (bp) =>
          bp.filePath == filePath ||
          bp.filePath.endsWith(filePath) ||
          filePath.endsWith(bp.filePath),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _outputController.close();
    super.dispose();
  }
}
