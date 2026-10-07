import 'package:flutter/foundation.dart' hide StackFrame;

import '../models/debugger_models.dart';

abstract class BaseDebugger extends ChangeNotifier {
  DebugState state = DebugState.inactive;
  final List<Breakpoint> breakpoints = [];
  final List<Variable> variables = [];
  final List<StackFrame> callStack = [];

  // Abstract methods that each language debugger must implement
  Future<void> startDebugging(String filePath);
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
}
