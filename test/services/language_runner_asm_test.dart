import 'package:classic_code_editor/services/language_runner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LanguageRunnerService ARM64 Assembly resolution', () {
    test('the manual dropdown value selects the ARM64 config', () {
      final config = LanguageRunnerService.resolveLanguage(
        '/tmp/anything.dart',
        'void main() {}',
        preferredLanguage: 'ARM64 Assembly',
      );

      expect(config.displayName, 'ARM64 Assembly');
      expect(config.extension, '.s');
      expect(config.highlightLanguage, 'armasm');
      expect(config.runCommand, contains('-arch arm64'));
    });

    test('every ARM64 alias the UI can send resolves the same config', () {
      for (final alias in ['ARM64 Assembly', 'Assembly', 'asm']) {
        final config = LanguageRunnerService.resolveLanguage(
          null,
          '',
          preferredLanguage: alias,
        );
        expect(config.displayName, 'ARM64 Assembly', reason: alias);
      }
    });

    test('a .s path resolves to ARM64 without any manual selection', () {
      final config = LanguageRunnerService.resolveLanguage(
        '/tmp/hello_arm64.s',
        '',
      );

      expect(config.displayName, 'ARM64 Assembly');
    });

    test('an unsaved buffer with assembly directives is sniffed as ARM64', () {
      final config = LanguageRunnerService.resolveLanguage(
        null,
        '.text\n.globl _main\n_main:\n    mov x0, #0\n    ret\n',
      );

      expect(config.displayName, 'ARM64 Assembly');
    });

    test(
      'the selection beats the file extension, like the other languages',
      () {
        final config = LanguageRunnerService.resolveLanguage(
          '/tmp/main.py',
          'print("hi")',
          preferredLanguage: 'ARM64 Assembly',
        );

        expect(config.displayName, 'ARM64 Assembly');
      },
    );
  });
}
