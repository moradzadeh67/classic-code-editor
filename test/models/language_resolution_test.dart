import 'dart:io';

import 'package:classic_code_editor/models/language_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Dart program saved under a `.s` name — the exact case from TASK-054.
const _dartProgram = '''
import 'dart:io';

void main(List<String> args) {
  print('hello ' + args.length.toString());
}
''';

const _asmProgram = '''
.globl _main
_main:
  mov x0, #1
  ret
''';

void main() {
  group('LanguageConfig.resolve', () {
    test('Dart text in /tmp/main.s reports a Dart mismatch', () {
      final result = LanguageConfig.resolve('/tmp/main.s', _dartProgram);

      expect(result.language.displayName, 'ARM64 Assembly');
      expect(result.hasMismatch, isTrue);
      expect(result.mismatch!.displayName, 'Dart');
      expect(
        result.mismatchMessage(fileName: 'main.s'),
        'main.s looks like Dart, not ARM64 Assembly. Use Save As with a .dart '
        'extension, or choose Dart in the language dropdown.',
      );
    });

    test('a real assembly file reports no mismatch', () {
      final result = LanguageConfig.resolve('/tmp/main.s', _asmProgram);
      expect(result.language.displayName, 'ARM64 Assembly');
      expect(result.hasMismatch, isFalse);
    });

    test('preprocessed assembly with a quoted #include is not a mismatch', () {
      final result = LanguageConfig.resolve(
        '/tmp/main.s',
        '#include "macros.h"\n.globl _main\n_main:\n  ret\n',
      );
      expect(result.language.displayName, 'ARM64 Assembly');
      expect(result.hasMismatch, isFalse);
    });

    test('a C++ program in a .s file reports C++', () {
      final result = LanguageConfig.resolve(
        '/tmp/main.s',
        '#include <iostream>\nint main() {\n  std::cout << "hi";\n}\n',
      );
      expect(result.language.displayName, 'ARM64 Assembly');
      expect(result.mismatch?.displayName, 'C++');
    });

    test('a C++ marker alone (using namespace) reports C++', () {
      final result = LanguageConfig.resolve(
        '/tmp/main.S',
        '#include <cstdio>\nusing namespace std;\nint main() { return 0; }\n',
      );
      expect(result.mismatch?.displayName, 'C++');
    });

    test('a C program in a .S file reports C', () {
      final result = LanguageConfig.resolve(
        '/tmp/main.S',
        '#include <stdio.h>\nint main() { printf("hi"); return 0; }\n',
      );
      expect(result.language.displayName, 'ARM64 Assembly');
      expect(result.mismatch?.displayName, 'C');
    });

    test('a real assembly sample reports no mismatch', () {
      final sample = File('samples/array_sum_arm64.s').readAsStringSync();
      final result = LanguageConfig.resolve('samples/array_sum_arm64.s', sample);
      expect(result.language.displayName, 'ARM64 Assembly');
      expect(result.hasMismatch, isFalse);
    });

    test('an explicit selection wins and never reports a mismatch', () {
      final result = LanguageConfig.resolve(
        '/tmp/main.s',
        _dartProgram,
        preferredLanguage: 'Dart',
      );
      expect(result.language.displayName, 'Dart');
      expect(result.hasMismatch, isFalse);
    });

    test('a buffer with no recognised extension keeps sniffing', () {
      final dart = LanguageConfig.resolve('Untitled', _dartProgram);
      expect(dart.language.displayName, 'Dart');
      expect(dart.hasMismatch, isFalse);

      final asm = LanguageConfig.resolve('Untitled', _asmProgram);
      expect(asm.language.displayName, 'ARM64 Assembly');
      expect(asm.hasMismatch, isFalse);
    });

    test('other clear mismatches are reported, plausible ones are not', () {
      // Dart file holding Python.
      final dartPath = LanguageConfig.resolve(
        '/tmp/tool.dart',
        'import os\n\ndef main():\n    print(os.getcwd())\n',
      );
      expect(dartPath.mismatch?.displayName, 'Python');

      // A .c file with C++-only markers is the same toolchain: no mismatch.
      final cPath = LanguageConfig.resolve(
        '/tmp/main.c',
        '#include <iostream>\nint main() { std::cout << 1; }\n',
      );
      expect(cPath.hasMismatch, isFalse);

      // Braces/semicolons disqualify the Python signal.
      final bracey = LanguageConfig.resolve(
        '/tmp/main.dart',
        'def f();\nimport os;\n',
      );
      expect(bracey.hasMismatch, isFalse);
    });
  });
}
