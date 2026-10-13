import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:classic_code_editor/utils/multi_language_highlighter.dart';
import 'package:highlight/highlight.dart' show Highlight, Mode, Node;
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

    test('operators are green and brackets are blue', () {
      final styles = MultiLanguageHighlighter.getThemeStyles();
      expect(styles['operator']!.color, MultiLanguageHighlighter.operatorColor);
      expect(styles['operator']!.color, const Color(0xFF0B6E00));
      expect(styles['symbol']!.color, MultiLanguageHighlighter.operatorColor);
      expect(
        styles['punctuation']!.color,
        MultiLanguageHighlighter.bracketColor,
      );
      expect(styles['punctuation']!.color, const Color(0xFF031CFC));
    });

    test('all grammars carry the operator / punctuation rules', () {
      for (final lang in ['dart', 'python', 'c', 'cpp']) {
        final mode = MultiLanguageHighlighter.getModeForLanguage(lang);
        final classes = (mode.contains ?? const <Mode>[])
            .whereType<Mode>()
            .map((m) => m.className)
            .toSet();
        expect(classes.contains('operator'), true, reason: lang);
        expect(classes.contains('punctuation'), true, reason: lang);
      }
    });

    test('real parse tags operators and brackets with colored classes', () {
      MultiLanguageHighlighter.patchSymbolModes();
      final highlighter = Highlight()..registerLanguage('probe', hl_dart.dart);
      final result = highlighter.parse(
        'void main() { final x = 1 + 2 >= 3; print(x); }',
        language: 'probe',
      );

      final classes = <String>{};
      void walk(List<Node>? nodes) {
        for (final n in nodes ?? const <Node>[]) {
          if (n.className != null) classes.add(n.className!);
          walk(n.children);
        }
      }

      walk(result.nodes);
      expect(classes.contains('operator'), true);
      expect(classes.contains('punctuation'), true);
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
