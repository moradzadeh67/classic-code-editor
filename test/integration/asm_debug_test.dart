import 'dart:io';

import 'package:classic_code_editor/models/debugger_models.dart';
import 'package:classic_code_editor/services/asm_debugger.dart';
import 'package:classic_code_editor/services/debugger_environment.dart';
import 'package:classic_code_editor/services/language_runner_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in end-to-end test of the real ARM64 debug chain.
///
/// Two things are needed for this to mean anything under `flutter test`:
/// * the `BORLAND_REAL_ASM_TEST=1` gate (it compiles a binary and drives lldb);
/// * `DebuggerEnvironment.allowRealProcesses = true`, because every debugger
///   short-circuits while `FLUTTER_TEST` is set, and the short-circuit branch
///   returns with `state == running` after printing a single banner - which is
///   exactly what made this test fail for reasons that had nothing to do with
///   the entry stop.
///
///     BORLAND_REAL_ASM_TEST=1 flutter test test/integration/asm_debug_test.dart
void main() {
  final enabled = Platform.environment['BORLAND_REAL_ASM_TEST'] == '1';
  if (!enabled) return;

  group('ARM64 Assembly Real Integration', () {
    late bool previousAllowRealProcesses;

    setUp(() {
      previousAllowRealProcesses = DebuggerEnvironment.allowRealProcesses;
      // Real lldb, even though we are running under flutter_test.
      DebuggerEnvironment.allowRealProcesses = true;
    });

    tearDown(() {
      // Never leak the switch into another test file in the same process.
      DebuggerEnvironment.allowRealProcesses = previousAllowRealProcesses;
    });

    test('compiles and runs hello_arm64.s', () async {
      final runner = LanguageRunnerService();
      addTearDown(runner.dispose);

      final source = File('samples/hello_arm64.s').readAsStringSync();
      await runner.runCode('samples/hello_arm64.s', source);

      // Wait for execution to complete
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(runner.isRunning, false);
    });

    test('debugs hello_arm64.s and hits the entry stop', () async {
      final debugger = AsmDebugger();
      addTearDown(() async {
        await debugger.stopDebugging();
        debugger.dispose();
      });

      final console = <String>[];
      final subscription = debugger.output.listen(console.add);
      addTearDown(subscription.cancel);

      final source = File('samples/hello_arm64.s').readAsStringSync();
      await debugger.startDebugging('samples/hello_arm64.s', content: source);

      // The stop arrives on the lldb stdout stream, so `startDebugging`
      // returning says nothing about it: poll instead of asserting.
      if (!await _waitForPause(debugger)) {
        fail(
          'The debugger never published the entry stop '
          '(state=${debugger.state}).\n'
          'Console:\n${console.join('\n')}',
        );
      }

      // Strong assertions: a pause the IDE can actually draw.
      expect(debugger.state, DebugState.paused);
      expect(
        debugger.currentPausedLine,
        isNotNull,
        reason: 'the entry stop must know which line it is on',
      );
      expect(
        debugger.mainAddress,
        isNotNull,
        reason: 'the entry stop must learn where _main was loaded',
      );

      final names = debugger.variables.map((v) => v.name).toSet();
      expect(
        names,
        containsAll(<String>[for (var i = 0; i <= 28; i++) 'x$i']),
        reason: 'x0..x28 must be captured at the entry stop',
      );
      expect(names, containsAll(<String>['fp', 'lr', 'sp', 'pc', 'cpsr']));
      expect(
        console.where((line) => line.startsWith('pc=0x')),
        isNotEmpty,
        reason: 'the disassembly line of the stop must reach the Console',
      );

      // ignore: avoid_print
      print(
        'ARM64 entry-stop transcript:\n${console.join('\n')}\n'
        'line=${debugger.currentPausedLine} '
        'main=${debugger.mainAddress?.toRadixString(16)} '
        'registers=${debugger.variables.length}',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

/// Polls [debugger] until it reports [DebugState.paused] or ~20 s elapse.
Future<bool> _waitForPause(AsmDebugger debugger) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (debugger.state == DebugState.paused) return true;
    if (debugger.state == DebugState.inactive) return false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}
