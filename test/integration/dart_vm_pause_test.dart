import 'dart:io';

import 'package:borland_dart/models/debugger_models.dart';
import 'package:borland_dart/services/debugger_environment.dart';
import 'package:borland_dart/services/dart_debugger.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end test of the Dart debugger's *real* pause behaviour.
///
/// Unlike the unit tests (which run under `FLUTTER_TEST` and never spawn a
/// process), this test drives the exact production entry point -
/// [DartDebugger.startDebugging] - which launches a real
/// `dart --pause-isolates-on-start` VM, attaches to its service, installs the
/// implicit `main` entry breakpoint and resumes into it. It asserts that the
/// debugger actually reports [DebugState.paused] with a user frame, i.e. that
/// pressing Debug in the IDE paints the gutter arrow.
///
/// It is opt-in (it binds a port and spawns a VM) and is skipped by default:
///
///     BORLAND_REAL_VM_TEST=1 flutter test test/integration/dart_vm_pause_test.dart
void main() {
  final enabled = Platform.environment['BORLAND_REAL_VM_TEST'] == '1';

  // Sample program: `main` on line 1, its first statement on line 2. This is
  // the canonical buffer the IDE ships with, so the reported line must be the
  // `main` declaration (1) or its first body statement (2).
  const sampleSource =
      'void main() {\n'
      '  String greeting = "Hello from Classic Code Editor (Dart)!";\n'
      '  int version = 1;\n'
      '  print(greeting);\n'
      '  print("Version: \$version");\n'
      '}\n';

  group('DartDebugger real VM pause', () {
    late Directory tempDir;
    late String scriptPath;

    setUp(() async {
      // Allow the real process to launch even though we run under flutter_test.
      DebuggerEnvironment.allowRealProcesses = true;
      tempDir = await Directory.systemTemp.createTemp('borland_dart_it_');
      scriptPath = '${tempDir.path}${Platform.pathSeparator}main.dart';
      await File(scriptPath).writeAsString(sampleSource);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('startDebugging pauses at main and paints the gutter arrow', () async {
      final debugger = DartDebugger();
      addTearDown(debugger.dispose);

      final console = <String>[];
      final subscription = debugger.output.listen(console.add);
      addTearDown(subscription.cancel);

      await debugger.startDebugging(scriptPath);

      // Poll until the debugger reports a pause (or times out). The whole
      // attach + entry-breakpoint + resume round trip runs on real IO.
      final paused = await _waitForPause(debugger);
      if (!paused) {
        fail(
          'The debugger never published a pause.\n'
          'Console:\n${console.join('\n')}',
        );
      }

      final observedLine = debugger.currentPausedLine;
      expect(debugger.state, DebugState.paused);
      expect(
        observedLine,
        anyOf(1, 2),
        reason:
            'observed currentPausedLine=$observedLine '
            '(sample: main on line 1, first statement on line 2)',
      );
      expect(debugger.callStack, isNotEmpty);
      expect(debugger.callStack.first.name, 'main');
      expect(
        File(debugger.callStack.first.filePath).absolute.path,
        File(scriptPath).absolute.path,
        reason: 'the top frame points at the file being debugged',
      );
      expect(
        debugger.callStack.where(
          (f) => f.filePath.isEmpty || f.filePath.startsWith('dart:'),
        ),
        isEmpty,
        reason: 'internal/empty frames must be filtered out of the call stack',
      );

      // Diagnostics so a failure shows the real Console transcript.
      // ignore: avoid_print
      print('Console transcript:\n${console.join('\n')}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, skip: enabled ? null : 'set BORLAND_REAL_VM_TEST=1 to run this test');
}

/// Polls [debugger] until it reports [DebugState.paused] or ~20s elapse.
Future<bool> _waitForPause(DartDebugger debugger) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (debugger.state == DebugState.paused) return true;
    if (debugger.state == DebugState.inactive) return false;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return debugger.state == DebugState.paused;
}
