import 'package:borland_dart/models/debugger_models.dart';
import 'package:borland_dart/services/c_debugger.dart';
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

/// Unit tests for [CDebugger].
///
/// `FLUTTER_TEST` keeps clang and lldb out of the loop, so the tests drive the
/// lldb stop protocol through [CDebugger.handleStdoutLine] and exercise the line
/// parsers directly.
void main() {
  group('CDebugger', () {
    late CDebugger debugger;

    setUp(() => debugger = CDebugger());
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

      await debugger.startDebugging('/tmp/main.c', content: 'int main(){}');

      expect(debugger.state, DebugState.running);
      expect(output, contains('[Debugging main.c]'));
    });

    test('parses lldb breakpoint ids and exit codes', () {
      expect(CDebugger.parseBreakpointId('Breakpoint 3: where = main'), 3);
      expect(CDebugger.parseBreakpointId('Process 1 launched'), isNull);
      expect(CDebugger.parseExitCode('Process 1 exited with status = 0'), 0);
      expect(CDebugger.parseExitCode('Breakpoint 3: where = main'), isNull);
    });

    test('a snapshot populates locals, frames and the paused line', () async {
      await debugger.startDebugging('/tmp/main.c', content: 'int main(){}');
      final output = capture(debugger.output);

      debugger.handleStdoutLine(
        '${CDebugger.snapshotMarker}'
        '{"file":"main.c","line":12,"reason":"breakpoint 1.1",'
        '"vars":[{"name":"i","value":"0","type":"int"}],'
        '"stack":[{"name":"main","file":"main.c","line":12}]}',
      );
      await flushOutput();

      expect(debugger.state, DebugState.paused);
      expect(debugger.currentPausedLine, 12);
      expect(debugger.variables.single.name, 'i');
      expect(debugger.callStack.single.name, 'main');
      expect(output, contains('[Paused at main.c:12 (breakpoint 1.1)]'));
    });

    test('a stop without debug info (line 0) is ignored', () async {
      await debugger.startDebugging('/tmp/main.c', content: 'int main(){}');

      debugger.handleStdoutLine(
        '${CDebugger.snapshotMarker}'
        '{"file":"dyld","line":0,"reason":"stop"}',
      );

      expect(debugger.state, DebugState.running);
      expect(debugger.currentPausedLine, isNull);
    });

    test('a malformed stop payload is reported rather than thrown', () async {
      await debugger.startDebugging('/tmp/main.c', content: 'int main(){}');
      final output = capture(debugger.output);

      debugger.handleStdoutLine('${CDebugger.snapshotMarker}{oops');
      await flushOutput();

      expect(debugger.state, DebugState.running);
      expect(
        output,
        contains('[C debugger received a malformed stop payload]'),
      );
    });

    test('plain lldb lines are forwarded to the console', () async {
      await debugger.startDebugging('/tmp/main.c', content: 'int main(){}');
      final output = capture(debugger.output);

      debugger.handleStdoutLine('Breakpoint 1: where = main`main + 20');
      await flushOutput();

      expect(output, contains('Breakpoint 1: where = main`main + 20'));
    });

    test('an inferior exit line finalises the session', () async {
      await debugger.startDebugging('/tmp/main.c', content: 'int main(){}');
      final output = capture(debugger.output);

      debugger.handleStdoutLine('Process 1 exited with status = 0');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(output, contains('[C program exited with code 0]'));
      expect(debugger.state, DebugState.inactive);
    });

    test('resume commands are ignored unless the session is paused', () async {
      await debugger.continueExecution();
      await debugger.stepOver();
      await debugger.stepInto();
      await debugger.stepOut();

      expect(debugger.state, DebugState.inactive);
    });

    test(
      'resume commands are dropped when no lldb process is attached',
      () async {
        await debugger.startDebugging('/tmp/main.c', content: 'int main(){}');
        debugger.handleStdoutLine(
          '${CDebugger.snapshotMarker}'
          '{"file":"main.c","line":7,"reason":"step"}',
        );
        expect(debugger.state, DebugState.paused);

        // Under FLUTTER_TEST there is no lldb to drive, so the command must be
        // dropped rather than queued for a later, unrelated stop.
        await debugger.stepInto();

        expect(debugger.state, DebugState.paused);
        expect(debugger.currentPausedLine, 7);
      },
    );

    test('stop clears the paused line and captured data', () async {
      await debugger.startDebugging('/tmp/main.c', content: 'int main(){}');
      debugger.handleStdoutLine(
        '${CDebugger.snapshotMarker}'
        '{"file":"main.c","line":12,"reason":"breakpoint 1.1",'
        '"vars":[{"name":"i","value":"0","type":"int"}],'
        '"stack":[{"name":"main","file":"main.c","line":12}]}',
      );

      await debugger.stopDebugging();

      expect(debugger.state, DebugState.inactive);
      expect(debugger.currentPausedLine, isNull);
      expect(debugger.variables, isEmpty);
      expect(debugger.callStack, isEmpty);
    });

    test('breakpoints are added, removed and cleared per file', () {
      debugger.setBreakpoint('/tmp/main.c', 4);
      debugger.setBreakpoint('/tmp/other.c', 9);
      expect(debugger.breakpoints, hasLength(2));

      debugger.removeBreakpoint('/tmp/main.c', 4);
      expect(debugger.breakpoints.single.line, 9);

      debugger.clearBreakpointsForFile('/tmp/other.c');
      expect(debugger.breakpoints, isEmpty);
    });
  });
}
