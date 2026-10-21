import 'dart:io';

import 'package:classic_code_editor/models/debugger_models.dart';
import 'package:classic_code_editor/services/asm_debugger.dart';
import 'package:classic_code_editor/services/debugger_environment.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end proof that a gutter breakpoint in a hand-written `.s` file stops
/// on exactly the line it was set on - something no unit test can show, because
/// it needs a real `clang` + `lldb` round trip.
///
/// The sample sums a 5-element array through `_sum_array`, which is assembled
/// *before* `_main`. Line 33 is `add x2, x2, x3` inside `sum_loop`, i.e.
/// 20 bytes before the entry symbol, so it only works when the offset base is
/// the entry symbol and not the top of the file.
///
/// Opt-in (it compiles and runs a binary):
///
///     BORLAND_REAL_ASM_TEST=1 flutter test test/integration/arm64_asm_breakpoint_test.dart
void main() {
  final enabled = Platform.environment['BORLAND_REAL_ASM_TEST'] == '1';

  /// 1-indexed line of `add x2, x2, x3` in `samples/array_sum_arm64.s`.
  const addLine = 33;

  /// 1-indexed line of the `_main:` label.
  const entryLine = 42;

  /// Value of `x2` on entry to the 5 iterations, i.e. *before* the add runs.
  const expectedX2 = <int>[0, 10, 30, 60, 100];

  /// Value of `x3` (the loaded element) on entry to the 5 iterations.
  const expectedX3 = <int>[10, 20, 30, 40, 50];

  group('AsmDebugger real lldb breakpoints', () {
    late String samplePath;

    setUp(() {
      DebuggerEnvironment.allowRealProcesses = true;
      samplePath = File('samples/array_sum_arm64.s').absolute.path;
    });

    test('stops five times on the add line with the expected registers', () async {
      final debugger = AsmDebugger();
      addTearDown(debugger.dispose);

      final console = <String>[];
      final subscription = debugger.output.listen(console.add);
      addTearDown(subscription.cancel);

      debugger.setBreakpoint(samplePath, addLine);

      await debugger.startDebugging(samplePath);

      if (!await _waitForPause(debugger)) {
        fail('never reached the entry stop\nConsole:\n${console.join('\n')}');
      }

      // A1: the entry stop paints the arrow inside `_main` and shows registers.
      expect(debugger.mainAddress, isNotNull);
      expect(
        debugger.currentPausedLine,
        anyOf(entryLine, entryLine + 1),
        reason: 'entry stop must land on _main or its first instruction',
      );
      expect(debugger.variables, hasLength(34));
      expect(
        console.where((line) => line.startsWith('pc=0x')),
        hasLength(1),
        reason: 'exactly one pc=… disassembly line at the entry stop',
      );

      // A2: five hits, each one *before* `add x2, x2, x3` executes.
      final x2Values = <int>[];
      final x3Values = <int>[];
      final lines = <int?>[];

      for (var hit = 0; hit < expectedX2.length; hit++) {
        await debugger.continueExecution();
        if (!await _waitForPause(debugger)) {
          fail(
            'breakpoint did not hit ${expectedX2.length} times '
            '(hit ${hit + 1} never arrived)\n'
            'Console:\n${console.join('\n')}',
          );
        }
        expect(debugger.currentPausedLine, addLine, reason: 'hit ${hit + 1}');
        x2Values.add(_register(debugger, 'x2'));
        x3Values.add(_register(debugger, 'x3'));
        lines.add(debugger.currentPausedLine);
      }

      expect(x2Values, expectedX2, reason: 'x2 before each add');
      expect(x3Values, expectedX3, reason: 'x3 is the loaded array element');
      expect(lines, List<int?>.filled(expectedX2.length, addLine));

      await debugger.stopDebugging();

      // Diagnostics so a failure shows the real Console transcript.
      // ignore: avoid_print
      print(
        'ARM64 lldb transcript:\n${console.join('\n')}\n'
        'x2=$x2Values x3=$x3Values arrows=$lines',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, skip: enabled ? null : 'set BORLAND_REAL_ASM_TEST=1 to run this test');
}

/// Reads a register as an int out of the paused [AsmDebugger] snapshot.
int _register(AsmDebugger debugger, String name) {
  final variable = debugger.variables.firstWhere((v) => v.name == name);
  return int.parse(variable.value.replaceFirst('0x', ''), radix: 16);
}

/// Polls [debugger] until it reports [DebugState.paused] or ~20s elapse.
Future<bool> _waitForPause(AsmDebugger debugger) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (debugger.state == DebugState.paused) return true;
    if (debugger.state == DebugState.inactive) return false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}
