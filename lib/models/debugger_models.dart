/// Represents a breakpoint in the debugger.
class Breakpoint {
  final String filePath;
  final int line;
  final bool verified;

  Breakpoint({
    required this.filePath,
    required this.line,
    this.verified = false,
  });

  @override
  String toString() => 'Breakpoint($filePath:$line, verified: $verified)';
}

/// Represents a variable in the debugger's scope.
class Variable {
  final String name;
  final String value;
  final String type;
  final List<Variable> children;

  Variable({
    required this.name,
    required this.value,
    required this.type,
    this.children = const [],
  });

  @override
  String toString() {
    final prefix = '  $type [$name]';
    if (children.isEmpty) {
      return '$prefix = "$value"';
    }
    return '$prefix {\n'
        '  ${children.map((c) => c.toString()).join('\n')}\n'
        '}';
  }
}

/// Represents a stack frame in the call stack.
class StackFrame {
  final String name;
  final String filePath;
  final int line;
  final int column;

  StackFrame({
    required this.name,
    required this.filePath,
    required this.line,
    required this.column,
  });

  @override
  String toString() => 'StackFrame($name at $filePath:$line:$column)';
}

/// The current state of the debugger.
enum DebugState { inactive, running, paused, stopped }

/// Represents an event from the debugger.
class DebugEvent {
  final String type;
  final String message;

  DebugEvent({required this.type, required this.message});

  @override
  String toString() => 'DebugEvent($type: $message)';
}
