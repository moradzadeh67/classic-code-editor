import 'dart:io';

import 'package:classic_code_editor/models/debugger_models.dart';
import 'package:classic_code_editor/services/c_debugger.dart';
import 'package:classic_code_editor/services/debugger_environment.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in end-to-end test of the C and C++ lldb sessions: breakpoint, step,
/// run to exit - and, crucially, **no surviving processes**.
///
/// lldb used to be SIGKILLed without taking the inferior with it, so a session
/// that was stopped (or that crashed a test) left `borland_c_exec` running. The
/// kill order is now `process kill`, `quit`, wait up to 2 s, SIGKILL lldb, then
/// SIGKILL the parsed inferior pid.
///
///     BORLAND_REAL_ASM_TEST=1 flutter test test/integration/lldb_session_lifecycle_test.dart
void main() {
  final enabled = Platform.environment['BORLAND_REAL_ASM_TEST'] == '1';

  const cSource =
      '#include <stdio.h>\n'
      'int main(void) {\n'
      '  int x = 1;\n'
      '  int y = 2;\n'
      '  printf("x=%d y=%d\\n", x, y);\n'
      '  return 0;\n'
      '}\n';

  const cppSource =
      '#include <iostream>\n'
      'int main() {\n'
      '  int x = 1;\n'
      '  int y = 2;\n'
      '  std::cout << "x=" << x << " y=" << y << std::endl;\n'
      '  return 0;\n'
      '}\n';

  group('lldb session lifecycle', () {
    late bool previousAllowRealProcesses;
    late Directory tempDir;

    setUp(() async {
      previousAllowRealProcesses = DebuggerEnvironment.allowRealProcesses;
      DebuggerEnvironment.allowRealProcesses = true;
      tempDir = await Directory.systemTemp.createTemp('borland_lldb_it_');
    });

    tearDown(() async {
      DebuggerEnvironment.allowRealProcesses = previousAllowRealProcesses;
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<String> write(String name, String source) async {
      final file = File('${tempDir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(source);
      return file.path;
    }

    test('C: breakpoint, step, exit, and no leftover processes', () async {
      final path = await write('main.c', cSource);
      final debugger = CDebugger();
      addTearDown(() async {
        await debugger.stopDebugging();
        debugger.dispose();
      });
      final console = <String>[];
      final subscription = debugger.output.listen(console.add);
      addTearDown(subscription.cancel);

      debugger.setBreakpoint(path, 4); // int y = 2;
      await debugger.startDebugging(path, content: cSource);
      if (!await _waitForPause(debugger)) {
        fail('never reached the entry stop\nConsole:\n${console.join('\n')}');
      }
      expect(debugger.state, DebugState.paused);

      await debugger.continueExecution();
      if (!await _waitForPause(debugger)) {
        fail(
          'the breakpoint on line 4 never hit\n'
          'Console:\n${console.join('\n')}',
        );
      }
      expect(debugger.currentPausedLine, 4);
      expect(debugger.variables, isNotEmpty);

      await debugger.stepOver();
      if (!await _waitForPause(debugger)) {
        fail('step did not stop\nConsole:\n${console.join('\n')}');
      }
      expect(debugger.state, DebugState.paused);

      await debugger.continueExecution();
      if (!await _waitForExit(debugger)) {
        fail('never exited\nConsole:\n${console.join('\n')}');
      }
      expect(
        console.any((line) => line.contains('x=1 y=2')),
        isTrue,
        reason: 'the program must run to completion\n${console.join('\n')}',
      );

      await _expectNoOrphans(console);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('C++: the same path compiles and debugs', () async {
      final path = await write('main.cpp', cppSource);
      final debugger = CDebugger();
      addTearDown(() async {
        await debugger.stopDebugging();
        debugger.dispose();
      });
      final console = <String>[];
      final subscription = debugger.output.listen(console.add);
      addTearDown(subscription.cancel);

      debugger.setBreakpoint(path, 4);
      await debugger.startDebugging(path, content: cppSource);
      if (!await _waitForPause(debugger)) {
        fail('never reached the entry stop\nConsole:\n${console.join('\n')}');
      }
      await debugger.continueExecution();
      if (!await _waitForPause(debugger)) {
        fail(
          'the C++ breakpoint on line 4 never hit\n'
          'Console:\n${console.join('\n')}',
        );
      }
      expect(debugger.currentPausedLine, 4);

      await debugger.continueExecution();
      expect(await _waitForExit(debugger), isTrue);
      expect(console.any((line) => line.contains('x=1 y=2')), isTrue);
      await _expectNoOrphans(console);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Stop while paused leaves nothing behind', () async {
      final path = await write('main.c', cSource);
      final debugger = CDebugger();
      final console = <String>[];
      final subscription = debugger.output.listen(console.add);
      addTearDown(subscription.cancel);

      await debugger.startDebugging(path, content: cSource);
      if (!await _waitForPause(debugger)) {
        fail('never reached the entry stop\nConsole:\n${console.join('\n')}');
      }
      await debugger.stopDebugging();
      debugger.dispose();

      expect(debugger.state, DebugState.inactive);
      await _expectNoOrphans(console);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, skip: enabled ? null : 'set BORLAND_REAL_ASM_TEST=1 to run this test');
}

/// A paused session may take a moment to tear down; poll, do not sleep blindly.
Future<bool> _waitForPause(CDebugger debugger) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (debugger.state == DebugState.paused) return true;
    if (debugger.state == DebugState.inactive) return false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

Future<bool> _waitForExit(CDebugger debugger) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (debugger.state == DebugState.inactive) return true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

/// No lldb and no inferior may survive a finished or stopped session.
Future<void> _expectNoOrphans(List<String> console) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final lldb = Process.runSync('pgrep', <String>['-x', 'lldb']);
    final inferior = Process.runSync('pgrep', <String>[
      '-f',
      'borland_(c|asm)_exec',
    ]);
    final lldbLeft = (lldb.stdout as String).trim();
    final inferiorLeft = (inferior.stdout as String).trim();
    if (lldbLeft.isEmpty && inferiorLeft.isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  final lldb = Process.runSync('pgrep', <String>['-fl', '-x', 'lldb']);
  final inferior = Process.runSync('pgrep', <String>[
    '-fl',
    '-f',
    'borland_(c|asm)_exec',
  ]);
  fail(
    'processes survived the session:\n'
    'lldb: ${(lldb.stdout as String).trim()}\n'
    'inferior: ${(inferior.stdout as String).trim()}\n'
    'Console:\n${console.join('\n')}',
  );
}
