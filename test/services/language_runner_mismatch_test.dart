import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/language_runner_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Dart program saved under a `.s` name (TASK-054's report).
const _dartProgram = '''
import 'dart:io';

void main() {
  print('hello');
}
''';

void main() {
  late LanguageRunnerService runner;
  late FileService fileService;
  late List<String> output;

  setUp(() {
    runner = LanguageRunnerService();
    fileService = FileService();
    output = <String>[];
    runner.outputStream.listen(output.add);
  });

  tearDown(() {
    runner.dispose();
    fileService.dispose();
  });

  test('Run on a mismatch prints one line and starts no process', () async {
    await runner.runCode('/tmp/main.s', _dartProgram);
    await Future<void>.delayed(Duration.zero);

    expect(output, hasLength(1));
    expect(
      output.single,
      'main.s looks like Dart, not ARM64 Assembly. Use Save As with a .dart '
      'extension, or choose Dart in the language dropdown.',
    );
    // The button is not stuck in "running", and nothing ran.
    expect(runner.isRunning, isFalse);
    expect(runner.exitCode, isNull);
  });
}
