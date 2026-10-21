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
/// the entry symbol and not the top of the file. Line 57 is `bl _printf`,
/// *after* `_main`, which proves the mapping is not a fixed offset either.
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

  /// 1-indexed line of `bl _printf`, i.e. after the entry symbol.
  const printfLine = 57;

  /// Value of `x2` on entry to the 5 iterations, i.e. *before* the add runs.
  const expectedX2 = <int>[0, 10, 30, 60, 100];

  /// Value of `x3` (the loaded element) on entry to the 5 iterations.
  const expectedX3 = <int>[10, 20, 30, 40, 50];

  group('AsmDebugger real lldb breakpoints', () {
    late String samplePath;
    late bool previousAllowRealProcesses;

    setUp(() {
      previousAllowRealProcesses = DebuggerEnvironment.allowRealProcesses;
      // Without this every debugger short-circuits under `flutter test`, and the
      // assertions below could only ever see `state == running`.
      DebuggerEnvironment.allowRealProcesses = true;
      samplePath = File('samples/array_sum_arm64.s').absolute.path;
    });

    tearDown(() {
      DebuggerEnvironment.allowRealProcesses = previousAllowRealProcesses;
    });

    /// A debugger that is always stopped (and disposed) after the test, so no
    /// lldb process can survive a failure.
    AsmDebugger newDebugger() {
      final debugger = AsmDebugger();
      addTearDown(() async {
        await debugger.stopDebugging();
        debugger.dispose();
      });
      return debugger;
    }

    test('stops five times on the add line with the expected registers', () async {
      final debugger = newDebugger();

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

      // A3: the last Continue runs the program to completion.
      await debugger.continueExecution();
      if (!await _waitForExit(debugger)) {
        fail(
          'the program never finished after the last hit '
          '(state=${debugger.state})\n'
          'Console:\n${console.join('\n')}',
        );
      }
      expect(
        console,
        contains('Sum = 150'),
        reason: 'the program must print its sum after the loop',
      );

      // Diagnostics so a failure shows the real Console transcript.
      // ignore: avoid_print
      print(
        'ARM64 lldb transcript:\n${console.join('\n')}\n'
        'x2=$x2Values x3=$x3Values arrows=$lines',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a breakpoint after _main stops on its exact line', () async {
      final debugger = newDebugger();

      final console = <String>[];
      final subscription = debugger.output.listen(console.add);
      addTearDown(subscription.cancel);

      // `bl _printf` lives *after* `_main`, so a line mapping that only ever
      // applied a constant offset (or that worked from the top of the file)
      // would stop on the wrong instruction here.
      debugger.setBreakpoint(samplePath, printfLine);

      await debugger.startDebugging(samplePath);
      if (!await _waitForPause(debugger)) {
        fail('never reached the entry stop\nConsole:\n${console.join('\n')}');
      }
      expect(
        debugger.currentPausedLine,
        anyOf(entryLine, entryLine + 1),
        reason: 'the first stop is the entry breakpoint, not the gutter one',
      );

      await debugger.continueExecution();
      if (!await _waitForPause(debugger)) {
        fail(
          'the breakpoint on line $printfLine never hit\n'
          'Console:\n${console.join('\n')}',
        );
      }
      expect(
        debugger.currentPausedLine,
        printfLine,
        reason: 'a breakpoint after _main must stop on its own line',
      );
      expect(debugger.variables, isNotEmpty);

      await debugger.continueExecution();
      expect(
        await _waitForExit(debugger),
        isTrue,
        reason: 'the program must exit after the printf breakpoint',
      );
      expect(console, contains('Sum = 150'));

      // ignore: avoid_print
      print('ARM64 post-entry breakpoint transcript:\n${console.join('\n')}');
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

/// Polls [debugger] until the session is over (inactive) or ~20s elapse.
Future<bool> _waitForExit(AsmDebugger debugger) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (debugger.state == DebugState.inactive) return true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}
