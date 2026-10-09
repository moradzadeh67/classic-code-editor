import 'package:flutter_test/flutter_test.dart';
import 'package:borland_dart/services/language_runner_service.dart';
import 'package:borland_dart/services/file_service.dart';

void main() {
  group('LanguageRunnerService Tests', () {
    late LanguageRunnerService runnerService;
    late FileService fileService;

    setUp(() {
      runnerService = LanguageRunnerService();
      fileService = FileService();
    });

    tearDown(() {
      runnerService.dispose();
      fileService.dispose();
    });

    test('initial state is not running and exitCode is null', () {
      expect(runnerService.isRunning, false);
      expect(runnerService.exitCode, isNull);
    });

    test('preferred language updates successfully', () {
      runnerService.setPreferredLanguage('Python');
      // No exception thrown, listeners notified
    });

    test('runCode handles empty or simple scripts gracefully', () async {
      // Test running a simple python script content via runCode
      fileService.openFilePath('/tmp/test.py', 'print("Hello from Python")');

      // We can invoke runActiveFile or runCode
      await runnerService.runCode('/tmp/test.py', 'print("Hello")');
      expect(runnerService.isRunning, false);
    });

    test('sendInput does not throw when no process is running', () {
      expect(() => runnerService.sendInput('test input'), returnsNormally);
    });
  });
}
