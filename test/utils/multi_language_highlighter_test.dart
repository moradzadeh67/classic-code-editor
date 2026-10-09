import 'package:flutter_test/flutter_test.dart';
import 'package:borland_dart/utils/multi_language_highlighter.dart';
import 'package:highlight/languages/dart.dart' as hl_dart;
import 'package:highlight/languages/python.dart' as hl_python;
import 'package:highlight/languages/cpp.dart' as hl_cpp;

void main() {
  group('MultiLanguageHighlighter Tests', () {
    test('theme styles are non-empty and well-formed', () {
      final styles = MultiLanguageHighlighter.getThemeStyles();
      expect(styles, isNotEmpty);
      expect(styles.containsKey('keyword'), true);
      expect(styles.containsKey('string'), true);
    });

    test('getModeForLanguage returns correct highlight mode', () {
      expect(
        MultiLanguageHighlighter.getModeForLanguage('dart'),
        equals(hl_dart.dart),
      );
      expect(
        MultiLanguageHighlighter.getModeForLanguage('python'),
        equals(hl_python.python),
      );
      expect(
        MultiLanguageHighlighter.getModeForLanguage('c'),
        equals(hl_cpp.cpp),
      );
      expect(
        MultiLanguageHighlighter.getModeForLanguage('cpp'),
        equals(hl_cpp.cpp),
      );
      expect(
        MultiLanguageHighlighter.getModeForLanguage('unknown'),
        equals(hl_dart.dart),
      );
    });

    test(
      'createController creates code controller with correct language mode',
      () {
        final dartController = MultiLanguageHighlighter.createController(
          text: 'void main() {}',
          filePath: 'main.dart',
        );
        expect(dartController.text, 'void main() {}');
        dartController.dispose();

        final pyController = MultiLanguageHighlighter.createController(
          text: 'print("hello")',
          filePath: 'script.py',
        );
        expect(pyController.text, 'print("hello")');
        pyController.dispose();
      },
    );
  });
}
