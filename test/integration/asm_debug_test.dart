import 'dart:io';

import 'package:classic_code_editor/models/debugger_models.dart';
import 'package:classic_code_editor/services/asm_debugger.dart';
import 'package:classic_code_editor/services/language_runner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Opt-in real integration test. Skipped unless BORLAND_REAL_ASM_TEST=1.
  const envVar = 'BORLAND_REAL_ASM_TEST';
  if (Platform.environment[envVar] != '1') {
    return;
  }

  group('ARM64 Assembly Real Integration', () {
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
      addTearDown(debugger.dispose);

      final source = File('samples/hello_arm64.s').readAsStringSync();
      await debugger.startDebugging('samples/hello_arm64.s', content: source);

      expect(debugger.state, DebugState.paused);
      expect(debugger.currentPausedLine, isNotNull);
    });
  });
}
