import 'package:borland_dart/models/debugger_models.dart';
import 'package:borland_dart/services/python_debugger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Subscribes to [stream] and records every line until the test completes.
List<String> capture(Stream<String> stream) {
  final lines = <String>[];
  final subscription = stream.listen(lines.add);
  addTearDown(subscription.cancel);
  return lines;
}

/// Yields so queued broadcast-stream events are delivered before asserting.
Future<void> flushOutput() => Future<void>.delayed(Duration.zero);

/// Unit tests for [PythonDebugger].
///
/// The `FLUTTER_TEST` guard means no `python3` process is ever spawned, so the
/// tests drive the tracer driver's stdout protocol directly through
/// [PythonDebugger.handleStdoutLine].
void main() {
  group('PythonDebugger', () {
    late PythonDebugger debugger;

    setUp(() => debugger = PythonDebugger());
    tearDown(() => debugger.dispose());

    test('starts inactive with empty collections', () {
      expect(debugger.state, DebugState.inactive);
      expect(debugger.currentPausedLine, isNull);
      expect(debugger.breakpoints, isEmpty);
      expect(debugger.variables, isEmpty);
      expect(debugger.callStack, isEmpty);
    });

    test('startDebugging announces the session and reports running', () async {
      final output = capture(debugger.output);

      await debugger.startDebugging('/tmp/main.py', content: 'print("hi")');

      expect(debugger.state, DebugState.running);
      expect(output, contains('[Debugging Python: main.py]'));
    });

    test('a pause payload populates locals and the call stack', () async {
      await debugger.startDebugging('/tmp/main.py', content: 'x = 1');
      final output = capture(debugger.output);

      debugger.handleStdoutLine(
        '${PythonDebugger.pauseMarker}'
        '{"file":"/tmp/main.py","line":4,"reason":"breakpoint",'
        '"vars":[{"name":"x","value":"1","type":"int"}],'
        '"stack":[{"name":"<module>","file":"/tmp/main.py","line":4}]}',
      );
      await flushOutput();

      expect(debugger.state, DebugState.paused);
      expect(debugger.currentPausedLine, 4);
      expect(debugger.variables.single.name, 'x');
      expect(debugger.variables.single.value, '1');
      expect(debugger.callStack.single.line, 4);
      expect(output, contains('[Paused at main.py:4 (breakpoint)]'));
    });

    test('a malformed pause payload is reported rather than thrown', () async {
      await debugger.startDebugging('/tmp/main.py', content: 'x = 1');
      final output = capture(debugger.output);

      debugger.handleStdoutLine('${PythonDebugger.pauseMarker}{not json');
      await flushOutput();

      expect(debugger.state, DebugState.running);
      expect(debugger.currentPausedLine, isNull);
      expect(
        output,
        contains('[Python debugger received a malformed pause payload]'),
      );
    });

    test('resuming clears the paused line and returns to running', () async {
      await debugger.startDebugging('/tmp/main.py', content: 'x = 1');
      debugger.handleStdoutLine(
        '${PythonDebugger.pauseMarker}'
        '{"file":"/tmp/main.py","line":2,"reason":"step"}',
      );
      expect(debugger.state, DebugState.paused);

      debugger.stepOver();

      expect(debugger.state, DebugState.running);
      expect(debugger.currentPausedLine, isNull);
    });

    test('resume commands are ignored unless the session is paused', () async {
      await debugger.continueExecution();
      await debugger.stepInto();
      await debugger.stepOut();

      expect(debugger.state, DebugState.inactive);
    });

    test('plain stdout lines are forwarded to the console', () async {
      await debugger.startDebugging('/tmp/main.py', content: 'x = 1');
      final output = capture(debugger.output);

      debugger.handleStdoutLine('hello from the program');
      await flushOutput();

      expect(output, contains('hello from the program'));
    });

    test('stop clears the paused line, variables and call stack', () async {
      await debugger.startDebugging('/tmp/main.py', content: 'x = 1');
      debugger.handleStdoutLine(
        '${PythonDebugger.pauseMarker}'
        '{"file":"/tmp/main.py","line":1,"reason":"breakpoint",'
        '"vars":[{"name":"x","value":"1","type":"int"}],'
        '"stack":[{"name":"<module>","file":"/tmp/main.py","line":1}]}',
      );

      await debugger.stopDebugging();

      expect(debugger.state, DebugState.inactive);
      expect(debugger.currentPausedLine, isNull);
      expect(debugger.variables, isEmpty);
      expect(debugger.callStack, isEmpty);
    });

    test('breakpoints are added, removed and cleared per file', () {
      debugger.setBreakpoint('/tmp/main.py', 3);
      debugger.setBreakpoint('/tmp/other.py', 7);
      expect(debugger.breakpoints, hasLength(2));

      debugger.removeBreakpoint('/tmp/main.py', 3);
      expect(debugger.breakpoints.single.line, 7);

      debugger.clearBreakpointsForFile('/tmp/other.py');
      expect(debugger.breakpoints, isEmpty);
    });

    test('start, pause and stop all notify listeners', () async {
      var notifications = 0;
      debugger.addListener(() => notifications++);

      await debugger.startDebugging('/tmp/main.py', content: 'x = 1');
      debugger.handleStdoutLine(
        '${PythonDebugger.pauseMarker}'
        '{"file":"/tmp/main.py","line":1,"reason":"breakpoint"}',
      );
      await debugger.stopDebugging();

      expect(notifications, greaterThanOrEqualTo(3));
    });
  });
}
