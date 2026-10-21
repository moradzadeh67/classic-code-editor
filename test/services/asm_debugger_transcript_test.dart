import 'dart:convert';
import 'dart:io';

import 'package:classic_code_editor/models/debugger_models.dart';
import 'package:classic_code_editor/services/asm_debugger.dart';
import 'package:classic_code_editor/services/c_debugger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Everything below is a transcript copied from a real lldb session on
/// `samples/array_sum_arm64.s` (Apple Silicon). The real run of that sample
/// prints `main` at 0x1000004d0 and `_sum_array` 40 bytes earlier, which is why
/// `add x2, x2, x3` lives at `main - 20`.
const int mainAddress = 0x1000004d0;
const int addLineAddress = 0x1000004bc; // add x2, x2, x3  ->  main - 20

List<Map<String, String>> registers({String pc = '0x1000004d0'}) {
  final names = <String>[
    for (var i = 0; i <= 28; i++) 'x$i',
    'fp',
    'lr',
    'sp',
    'pc',
    'cpsr',
  ];
  return [
    for (final name in names)
      {
        'name': name,
        'value': name == 'pc' ? pc : '0x0000000000000000',
        'type': 'register',
      },
  ];
}

String snapshot({
  required String pc,
  required String reason,
  required String frameName,
  String disasm = '',
  List<Map<String, String>>? vars,
}) {
  return CDebugger.snapshotMarker +
      jsonEncode({
        'file': '',
        'line': 0,
        'pc': pc,
        'reason': reason,
        'vars': vars ?? registers(pc: pc),
        'stack': [
          {'name': frameName, 'file': '', 'line': 0},
        ],
        'disasm': disasm,
      });
}

List<String> capture(Stream<String> stream) {
  final lines = <String>[];
  final subscription = stream.listen(lines.add);
  addTearDown(subscription.cancel);
  return lines;
}

Future<void> flushOutput() => Future<void>.delayed(Duration.zero);

void main() {
  group('AsmDebugger real lldb transcript', () {
    late AsmDebugger debugger;
    late String samplePath;

    setUp(() {
      debugger = AsmDebugger();
      samplePath = File('samples/array_sum_arm64.s').absolute.path;
    });

    tearDown(() async {
      debugger.dispose();
    });

    /// Runs `startDebugging` under the unit-test short circuit (the real
    /// lldb process is never spawned) and stops the loader/entry prelude that
    /// every session produces, so the map and the base address are loaded.
    Future<List<String>> startAndReachEntry() async {
      final output = capture(debugger.output);
      await debugger.startDebugging(samplePath);
      await flushOutput();
      return output;
    }

    test(
      'the dynamic-loader stop is ignored, the entry stop is reported',
      () async {
        final output = await startAndReachEntry();

        // 1. `_dyld_start` — every session stops here first; no source line.
        debugger.handleStdoutLine(
          snapshot(
            pc: '0x100014bf0',
            reason: 'signal SIGSTOP',
            frameName: '_dyld_start',
            disasm: 'pc=0x100014bf0  mov x0, sp',
          ),
        );
        await flushOutput();

        expect(debugger.state, DebugState.running);
        expect(debugger.currentPausedLine, isNull);
        expect(debugger.variables, isEmpty);
        expect(debugger.mainAddress, isNull);
        expect(output.join('\n'), isNot(contains('_dyld_start')));

        // 2. The real entry stop on `main`.
        debugger.handleStdoutLine(
          snapshot(
            pc: '0x1000004d0',
            reason: 'breakpoint 1.1',
            frameName: 'main',
            disasm: 'pc=0x1000004d0  stp x29, x30, [sp, #-0x20]!',
          ),
        );
        await flushOutput();

        expect(debugger.state, DebugState.paused);
        expect(debugger.mainAddress, mainAddress);
        // ▶ lands on the first instruction of `_main` (line 43).
        expect(debugger.currentPausedLine, 43);

        // A1: registers x0..x28, fp, lr, sp, pc, cpsr.
        expect(debugger.variables, hasLength(34));
        expect(
          debugger.variables.map((v) => v.name),
          containsAll(<String>['x0', 'x28', 'fp', 'lr', 'sp', 'pc', 'cpsr']),
        );
        expect(debugger.callStack.single.name, 'main');

        // Exactly one `pc=0x…  <instruction>` console line.
        final pcLines = output
            .where((line) => line.startsWith('pc=0x'))
            .toList();
        expect(pcLines, hasLength(1));
        expect(pcLines.single, 'pc=0x1000004d0  stp x29, x30, [sp, #-0x20]!');
        expect(
          output.join('\n'),
          contains('[Paused at array_sum_arm64.s:43 (breakpoint 1.1)]'),
        );
      },
    );

    test('a gutter breakpoint stops on the exact line before _main', () async {
      final output = await startAndReachEntry();

      debugger.setBreakpoint(samplePath, 33); // add x2, x2, x3

      // Entry stop first: the base address is only known from this snapshot.
      debugger.handleStdoutLine(
        snapshot(
          pc: '0x1000004d0',
          reason: 'breakpoint 1.1',
          frameName: 'main',
        ),
      );
      await flushOutput();

      expect(debugger.plannedBreakpointAddresses, <int>[addLineAddress]);

      debugger.handleStdoutLine(
        snapshot(
          pc: '0x1000004bc',
          reason: 'breakpoint 2.1',
          frameName: 'sum_array',
          disasm: 'pc=0x1000004bc  add x2, x2, x3',
        ),
      );
      await flushOutput();

      expect(debugger.currentPausedLine, 33);
      expect(
        output.join('\n'),
        contains('[Paused at array_sum_arm64.s:33 (breakpoint 2.1)]'),
      );
    });

    test('offsets are applied relative to main, signed', () async {
      await startAndReachEntry();

      // 33 is 20 bytes *before* main; 43 is main itself; 57 is main + 48.
      debugger
        ..setBreakpoint(samplePath, 33)
        ..setBreakpoint(samplePath, 43)
        ..setBreakpoint(samplePath, 57);

      debugger.handleStdoutLine(
        snapshot(
          pc: '0x1000004d0',
          reason: 'breakpoint 1.1',
          frameName: 'main',
        ),
      );
      await flushOutput();

      expect(debugger.plannedBreakpointAddresses, <int>[
        0x1000004bc, // main - 20
        0x1000004d0, // main + 0
        0x100000500, // main + 48
      ]);
    });

    test('a step stop moves the arrow to the next instruction', () async {
      await startAndReachEntry();

      debugger.handleStdoutLine(
        snapshot(
          pc: '0x1000004d0',
          reason: 'breakpoint 1.1',
          frameName: 'main',
        ),
      );
      await flushOutput();

      debugger.handleStdoutLine(
        snapshot(
          pc: '0x1000004d4',
          reason: 'instruction step into',
          frameName: 'main',
        ),
      );
      await flushOutput();

      expect(debugger.currentPausedLine, 44);
    });

    test('lldb disassembly and warning noise is dropped', () async {
      final output = await startAndReachEntry();

      debugger
        ..handleStdoutLine(
          '->  0x1000004d0 <+0>:  stp    x29, x30, [sp, #-0x20]!',
        )
        ..handleStdoutLine(
          '    0x1000004d4 <+4>:  stp    x19, x20, [sp, #0x10]',
        )
        ..handleStdoutLine('array_sum`main:')
        ..handleStdoutLine('warning: unable to find any locations for this')
        ..handleStdoutLine('Breakpoint 2: no locations (pending).');
      await flushOutput();

      final text = output.join('\n');
      expect(text, isNot(contains('<+0>')));
      expect(text, isNot(contains('<+4>')));
      expect(text, isNot(contains('array_sum`main:')));
      expect(text, isNot(contains('warning:')));
      expect(text, isNot(contains('no locations')));
    });

    test('restarting clears the previous session breakpoint ids', () async {
      await startAndReachEntry();

      // In production `configureAsm` arms the entry-breakpoint id. Under the
      // test short circuit no lldb is spawned, so arm it explicitly; writing
      // commands without a process is a no-op.
      await debugger.configureAsm(samplePath);

      debugger.handleStdoutLine(
        'Breakpoint 1: where = array_sum`main, address = 0x00000001000004d0',
      );
      await flushOutput();
      expect(debugger.entryBreakpointLldbId, 1);

      // End the first session the way the Debug button does, then start again.
      await debugger.stopDebugging();
      await debugger.startDebugging(samplePath);
      await flushOutput();

      // None of the first session's lldb state survives, so the second session
      // cannot emit `error: No breakpoints exist to be deleted.`.
      expect(debugger.entryBreakpointLldbId, isNull);
      expect(debugger.mainAddress, isNull);
      expect(debugger.plannedBreakpointAddresses, isEmpty);
    });

    test('console messages name the engine as ARM64 Assembly', () async {
      final output = await startAndReachEntry();

      await debugger.stopDebugging();
      await flushOutput();

      expect(output.join('\n'), contains('[ARM64 Assembly debugging stopped]'));
      expect(output.join('\n'), isNot(contains('[C debugging stopped]')));
    });
  });
}
