import 'dart:async';

import 'package:borland_dart/models/debugger_models.dart';
import 'package:borland_dart/models/language_config.dart';
import 'package:borland_dart/services/c_debugger.dart';
import 'package:borland_dart/services/dart_debugger.dart';
import 'package:borland_dart/services/debugger_factory.dart';
import 'package:borland_dart/services/debugger_manager.dart';
import 'package:borland_dart/services/file_service.dart';
import 'package:borland_dart/services/language_runner_service.dart';
import 'package:borland_dart/services/python_debugger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dispatch tests for the debugger layer.
///
/// They pin down that each of the four supported languages resolves to the
/// debugger that can actually drive it - including Untitled buffers, which carry
/// no extension and must be recognised from their content - and that every
/// debugger's output reaches the shared Console stream.
void main() {
  group('DebuggerFactory', () {
    late DebuggerFactory factory;

    setUp(() => factory = DebuggerFactory());
    tearDown(() => factory.dispose());

    test('maps every supported extension to its language debugger', () {
      expect(
        factory.forLanguage(LanguageConfig.fromExtension('a.dart')),
        isA<DartDebugger>(),
      );
      expect(
        factory.forLanguage(LanguageConfig.fromExtension('a.py')),
        isA<PythonDebugger>(),
      );
      expect(
        factory.forLanguage(LanguageConfig.fromExtension('a.c')),
        isA<CDebugger>(),
      );
      expect(
        factory.forLanguage(LanguageConfig.fromExtension('a.cpp')),
        isA<CDebugger>(),
      );
    });

    test('resolves saved files by extension', () {
      expect(factory.forCode('/tmp/main.py', 'x = 1'), isA<PythonDebugger>());
      expect(factory.forCode('/tmp/main.c', ''), isA<CDebugger>());
      expect(factory.forCode('/tmp/main.cpp', ''), isA<CDebugger>());
      expect(factory.forCode('/tmp/main.dart', ''), isA<DartDebugger>());
    });

    test('sniffs the language of an Untitled Python buffer', () {
      const source = 'import sys\ndef main():\n    print("hi")\n';
      expect(factory.forCode('Untitled', source), isA<PythonDebugger>());
    });

    test('sniffs the language of an Untitled C/C++ buffer', () {
      expect(
        factory.forCode('Untitled', '#include <stdio.h>\nint main() {}\n'),
        isA<CDebugger>(),
      );
      expect(
        factory.forCode('Untitled', 'std::cout << "hi";'),
        isA<CDebugger>(),
      );
    });

    test('falls back to Dart for an Untitled Dart buffer', () {
      expect(
        factory.forCode('Untitled', 'void main() {\n  print(1);\n}'),
        isA<DartDebugger>(),
      );
    });

    test('honours the manual language dropdown over the extension', () {
      expect(
        factory.forCode(
          '/tmp/main.dart',
          'void main() {}',
          preferredLanguage: 'Python',
        ),
        isA<PythonDebugger>(),
      );
    });

    test('reuses one instance per language so breakpoints survive', () {
      expect(
        factory.forCode('/tmp/a.py', ''),
        same(factory.forCode('/tmp/b.py', '')),
      );
    });

    test('all exposes each debugger exactly once', () {
      expect(factory.all, hasLength(3));
      expect(factory.all.toSet(), hasLength(3));
    });
  });

  group('DebuggerManager', () {
    late FileService fileService;
    late DebuggerManager manager;

    setUp(() {
      fileService = FileService();
      manager = DebuggerManager(fileService);
    });

    tearDown(() {
      manager.dispose();
      fileService.dispose();
    });

    test('starts on the debugger for the first opened file', () {
      fileService.openFilePath('/tmp/main.py', 'print("hi")');
      expect(manager.activeDebugger, isA<PythonDebugger>());
    });

    test('swaps the active debugger when the tab language changes', () {
      fileService.openFilePath('/tmp/main.py', 'print("hi")');
      final python = manager.activeDebugger;
      expect(python, isA<PythonDebugger>());

      fileService.openFilePath('/tmp/main.c', 'int main() {}');
      expect(manager.activeDebugger, isA<CDebugger>());
      expect(manager.activeDebugger, isNot(same(python)));

      fileService.openFilePath('/tmp/main.dart', 'void main() {}');
      expect(manager.activeDebugger, isA<DartDebugger>());
    });

    test('notifies listeners only when the language really changes', () {
      fileService.openFilePath('/tmp/main.py', 'print("hi")');
      var notifications = 0;
      manager.addListener(() => notifications++);

      fileService.updateContent('print("changed")');
      expect(notifications, 0);

      fileService.openFilePath('/tmp/main.dart', 'void main() {}');
      expect(notifications, 1);
    });

    test('re-resolves an Untitled buffer as its content changes', () {
      fileService.createNewFile();
      expect(manager.activeDebugger, isA<DartDebugger>());

      fileService.updateContent('import sys\nprint("hi")');
      expect(manager.activeDebugger, isA<PythonDebugger>());
    });

    test('stops a running session when the language changes', () async {
      fileService.openFilePath('/tmp/main.py', 'print("hi")');
      final python = manager.activeDebugger as PythonDebugger;
      await python.startDebugging('/tmp/main.py', content: 'print("hi")');
      expect(python.state, DebugState.running);

      fileService.openFilePath('/tmp/main.dart', 'void main() {}');
      // The manager stops the previous session asynchronously.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(python.state, DebugState.inactive);
      expect(python.currentPausedLine, isNull);
    });

    test('keeps breakpoints on the debugger that owns the language', () {
      fileService.openFilePath('/tmp/main.py', 'print("hi")');
      final python = manager.activeDebugger as PythonDebugger;
      python.setBreakpoint('/tmp/main.py', 2);

      fileService.openFilePath('/tmp/main.dart', 'void main() {}');
      fileService.openFilePath('/tmp/main.py', 'print("hi")');

      expect(manager.activeDebugger, same(python));
      expect(manager.activeDebugger.breakpoints.single.line, 2);
    });
  });

  group('Debugger output bridge', () {
    test('forwards every debugger line to the shared Console stream', () async {
      final runner = LanguageRunnerService();
      addTearDown(runner.dispose);
      final factory = DebuggerFactory();
      addTearDown(factory.dispose);

      final received = <String>[];
      final subscriptions = <StreamSubscription<String>>[
        runner.outputStream.listen(received.add),
      ];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      });

      // Exactly what IDEShell wires up: every debugger feeds the runner, and the
      // Console panel listens to the runner.
      for (final debugger in factory.all) {
        subscriptions.add(debugger.output.listen(runner.emitOutput));
      }

      await factory.pythonDebugger.startDebugging(
        '/tmp/main.py',
        content: 'print("hi")',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, contains('[Debugging Python: main.py]'));
    });
  });
}
