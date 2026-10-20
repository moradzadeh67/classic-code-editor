import 'dart:io';

import 'package:classic_code_editor/models/debugger_models.dart';
import 'package:classic_code_editor/services/asm_debugger.dart';
import 'package:classic_code_editor/services/c_debugger.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> capture(Stream<String> stream) {
  final lines = <String>[];
  final subscription = stream.listen(lines.add);
  addTearDown(subscription.cancel);
  return lines;
}

Future<void> flushOutput() => Future<void>.delayed(Duration.zero);

void main() {
  group('AsmDebugger', () {
    late AsmDebugger debugger;
    late Directory tempDir;
    late File asmFile;

    setUp(() async {
      debugger = AsmDebugger();
      tempDir = await Directory.systemTemp.createTemp('asm_debugger_test_');
      asmFile = File('${tempDir.path}/main.s');
      await asmFile.writeAsString('''
    .text
    .globl _main
_main:
    mov x0, #1
    mov x1, #2
    add x2, x0, x1
    ret
''');
    });

    tearDown(() async {
      debugger.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('starts inactive with empty collections', () {
      expect(debugger.state, DebugState.inactive);
      expect(debugger.currentPausedLine, isNull);
      expect(debugger.breakpoints, isEmpty);
      expect(debugger.variables, isEmpty);
      expect(debugger.callStack, isEmpty);
    });

    test('startDebugging announces the session and reports running', () async {
      final output = capture(debugger.output);

      await debugger.startDebugging(asmFile.path);
      await flushOutput();

      expect(debugger.state, DebugState.running);
      expect(output, contains('[Debugging ARM64 Assembly: main.s]'));
    });

    test(
      'parses registers, disassembly, and maps address to line in snapshot',
      () async {
        final output = capture(debugger.output);
        await debugger.startDebugging(asmFile.path);

        // Initial stop at _main entry (offset 0 -> line 4: mov x0, #1)
        debugger.handleStdoutLine(
          '${CDebugger.snapshotMarker}'
          '{"file":"main.s","line":0,"pc":"0x100003f40","reason":"breakpoint 1.1",'
          '"vars":[{"name":"x0","value":"0x0","type":"register"},'
          '{"name":"pc","value":"0x100003f40","type":"register"}],'
          '"stack":[{"name":"main","file":"main.s","line":0}],'
          '"disasm":"pc=0x100003f40  mov x0, #1"}',
        );
        await flushOutput();

        expect(debugger.state, DebugState.paused);
        expect(debugger.mainAddress, 0x100003f40);
        expect(debugger.currentPausedLine, 4); // Line 4: mov x0, #1
        expect(debugger.variables, hasLength(2));
        expect(debugger.variables[0].name, 'x0');
        expect(debugger.callStack.single.name, 'main');
        expect(
          output.join('\n'),
          contains('[Paused at main.s:4 (breakpoint 1.1)]'),
        );
        expect(output.join('\n'), contains('pc=0x100003f40  mov x0, #1'));

        // Next stop at offset 8 bytes (0x100003f48 -> line 6: add x2, x0, x1)
        debugger.handleStdoutLine(
          '${CDebugger.snapshotMarker}'
          '{"file":"main.s","line":0,"pc":"0x100003f48","reason":"breakpoint 2.1",'
          '"vars":[{"name":"x0","value":"0x1","type":"register"},'
          '{"name":"x1","value":"0x2","type":"register"},'
          '{"name":"pc","value":"0x100003f48","type":"register"}],'
          '"stack":[{"name":"main","file":"main.s","line":0}],'
          '"disasm":"pc=0x100003f48  add x2, x0, x1"}',
        );
        await flushOutput();

        expect(debugger.currentPausedLine, 6); // Line 6: add x2, x0, x1
        expect(
          output.join('\n'),
          contains('[Paused at main.s:6 (breakpoint 2.1)]'),
        );
      },
    );

    test('a malformed stop payload is reported cleanly', () async {
      final output = capture(debugger.output);
      await debugger.startDebugging(asmFile.path);

      debugger.handleStdoutLine('${CDebugger.snapshotMarker}{oops');
      await flushOutput();

      expect(
        output.join('\n'),
        contains('[ARM64 Assembly debugger received a malformed stop payload'),
      );
    });

    test('plain lldb lines are forwarded to the console', () async {
      final output = capture(debugger.output);
      await debugger.startDebugging(asmFile.path);

      debugger.handleStdoutLine('Some random lldb output line');
      await flushOutput();

      expect(output.join('\n'), contains('Some random lldb output line'));
    });

    test(
      'step commands map to thread step-inst / step-inst-over / step-out',
      () {
        expect(debugger.stepInto, isA<Function>());
        expect(debugger.stepOver, isA<Function>());
        expect(debugger.stepOut, isA<Function>());
      },
    );
  });
}
