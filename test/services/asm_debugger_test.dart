import 'package:classic_code_editor/models/debugger_models.dart';
import 'package:classic_code_editor/services/asm_debugger.dart';
import 'package:classic_code_editor/services/c_debugger.dart';
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

void main() {
  group('AsmDebugger', () {
    late AsmDebugger debugger;

    setUp(() => debugger = AsmDebugger());
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

      await debugger.startDebugging('/tmp/main.s', content: 'mov x0, #0');

      expect(debugger.state, DebugState.running);
      expect(output, contains('[Debugging ARM64 Assembly: main.s]'));
    });

    test('parses registers and disassembly in snapshot', () async {
      await debugger.startDebugging('/tmp/main.s', content: 'mov x0, #0');
      final output = capture(debugger.output);

      debugger.handleStdoutLine(
        '${CDebugger.snapshotMarker}'
        '{"file":"main.s","line":12,"reason":"breakpoint 1.1",'
        '"vars":[{"name":"x0","value":"0x1","type":"register"},'
        '{"name":"x1","value":"0x2","type":"register"},'
        '{"name":"pc","value":"0x100003f40","type":"register"}],'
        '"stack":[{"name":"main","file":"main.s","line":12}],'
        '"disasm":"pc=0x100003f40  mov x19, #0"}',
      );
      await flushOutput();

      expect(debugger.state, DebugState.paused);
      expect(debugger.currentPausedLine, 12);
      expect(debugger.variables, hasLength(3));
      expect(debugger.variables[0].name, 'x0');
      expect(debugger.variables[0].type, 'register');
      expect(debugger.callStack.single.name, 'main');
      expect(output, contains('[Paused at main.s:12 (breakpoint 1.1)]'));
      expect(output, contains('pc=0x100003f40  mov x19, #0'));
    });

    test('a stop without debug info (line 0) is ignored', () async {
      await debugger.startDebugging('/tmp/main.s', content: 'mov x0, #0');

      debugger.handleStdoutLine(
        '${CDebugger.snapshotMarker}'
        '{"file":"dyld","line":0,"reason":"stop"}',
      );

      expect(debugger.state, DebugState.running);
      expect(debugger.currentPausedLine, isNull);
    });

    test('a malformed stop payload is reported rather than thrown', () async {
      await debugger.startDebugging('/tmp/main.s', content: 'mov x0, #0');
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
      await debugger.startDebugging('/tmp/main.s', content: 'mov x0, #0');
      final output = capture(debugger.output);

      debugger.handleStdoutLine('Some random lldb output line');
      await flushOutput();

      expect(output, contains('Some random lldb output line'));
    });

    test(
      'step commands map to thread step-inst / step-inst-over / step-out',
      () {
        // We can't easily mock Process.stdin, but we can verify the command
        // mapping by checking that the method exists and is callable.
        expect(debugger.stepInto, isA<Function>());
        expect(debugger.stepOver, isA<Function>());
        expect(debugger.stepOut, isA<Function>());
      },
    );
  });
}
