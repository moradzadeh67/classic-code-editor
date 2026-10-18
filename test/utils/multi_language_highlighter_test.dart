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

    test('operators, keywords and comments have the expected new colors', () {
      final styles = MultiLanguageHighlighter.getThemeStyles();
      expect(styles['operator']!.color, MultiLanguageHighlighter.operatorColor);
      expect(styles['operator']!.color, const Color(0xFF00BF69));
      expect(styles['operator']!.fontWeight, FontWeight.bold);

      expect(styles['keyword']!.color, MultiLanguageHighlighter.keywordColor);
      expect(styles['keyword']!.color, const Color(0xFFC842F5));
      expect(styles['keyword']!.fontWeight, FontWeight.bold);

      expect(styles['comment']!.color, MultiLanguageHighlighter.commentColor);
      expect(styles['comment']!.color, const Color(0xFF596E48));
      expect(styles['comment']!.fontStyle, FontStyle.italic);

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

    test('real-parse assertions for Dart, Python, C and C++', () {
      MultiLanguageHighlighter.patchSymbolModes();
      final hl = Highlight()
        ..registerLanguage('dart', hl_dart.dart)
        ..registerLanguage('python', hl_python.python)
        ..registerLanguage('cpp', hl_cpp.cpp);

      // Helper to collect all (value, className) pairs in node tree
      List<({String? value, String? className})> collectNodes(
        List<Node>? nodes,
      ) {
        final list = <({String? value, String? className})>[];
        void walk(List<Node>? listNodes, String? currentClass) {
          for (final n in listNodes ?? const <Node>[]) {
            final effectiveClass = n.className ?? currentClass;
            if (n.value != null) {
              list.add((value: n.value, className: effectiveClass));
            }
            if (n.children != null && n.children!.isNotEmpty) {
              walk(n.children, effectiveClass);
            }
          }
        }

        walk(nodes, null);
        return list;
      }

      // 1. Dart
      final dartNodes = collectNodes(
        hl
            .parse(
              'int _controller = 3.14 + -1; String my_var = "a+b_c"; bool flag = x < y ? !z : false;',
              language: 'dart',
            )
            .nodes,
      );

      // Operators +, <, ?, ! get 'operator' class
      expect(
        dartNodes.any((n) => n.value == '+' && n.className == 'operator'),
        true,
      );
      expect(
        dartNodes.any((n) => n.value == '<' && n.className == 'operator'),
        true,
      );
      expect(
        dartNodes.any((n) => n.value == '?' && n.className == 'operator'),
        true,
      );
      expect(
        dartNodes.any((n) => n.value == '!' && n.className == 'operator'),
        true,
      );

      // _controller and my_var do NOT get 'operator' class on underscore
      expect(
        dartNodes.any(
          (n) =>
              (n.value?.contains('_controller') ?? false) &&
              n.className == 'operator',
        ),
        false,
      );
      expect(
        dartNodes.any(
          (n) =>
              (n.value?.contains('my_var') ?? false) &&
              n.className == 'operator',
        ),
        false,
      );

      // 3.14 gets number class (dot inside float is not operator)
      expect(
        dartNodes.any(
          (n) =>
              (n.value?.contains('3.14') ?? false) && n.className == 'number',
        ),
        true,
      );

      // Strings with + or _ inside stay string-colored
      expect(
        dartNodes.any(
          (n) =>
              (n.value?.contains('a+b_c') ?? false) && n.className == 'string',
        ),
        true,
      );

      // 2. Python
      final pyNodes = collectNodes(
        hl
            .parse(
              '# comment with + and _\nmy_var = 3.14 + -1\nif x < y:\n    pass',
              language: 'python',
            )
            .nodes,
      );

      // Python # comment keeps comment class
      expect(
        pyNodes.any(
          (n) =>
              (n.value?.contains('# comment with + and _') ?? false) &&
              n.className == 'comment',
        ),
        true,
      );
      expect(
        pyNodes.any((n) => n.value == '+' && n.className == 'operator'),
        true,
      );
      expect(
        pyNodes.any((n) => n.value == '<' && n.className == 'operator'),
        true,
      );
      expect(
        pyNodes.any(
          (n) =>
              (n.value?.contains('my_var') ?? false) &&
              n.className == 'operator',
        ),
        false,
      );

      // 3. C & C++
      for (final lang in ['c', 'cpp']) {
        final cNodes = collectNodes(
          hl
              .parse(
                '/* comment */ #include <stdio.h>\nint main() { double _controller = 3.14 + -1; if (x < y ? !z : 0) return 0; }',
                language: lang == 'c' ? 'cpp' : 'cpp',
              )
              .nodes,
        );

        // #include keeps meta / meta-keyword class (not operator)
        expect(
          cNodes.any(
            (n) =>
                (n.value == '#' && n.className == 'meta') ||
                (n.value == 'include' && n.className == 'meta-keyword'),
          ),
          true,
          reason: lang,
        );
        // comment keeps comment class
        expect(
          cNodes.any(
            (n) =>
                (n.value?.contains('/* comment */') ?? false) &&
                n.className == 'comment',
          ),
          true,
          reason: lang,
        );
        expect(
          cNodes.any((n) => n.value == '+' && n.className == 'operator'),
          true,
          reason: lang,
        );
        expect(
          cNodes.any((n) => n.value == '<' && n.className == 'operator'),
          true,
          reason: lang,
        );
        expect(
          cNodes.any((n) => n.value == '?' && n.className == 'operator'),
          true,
          reason: lang,
        );
        expect(
          cNodes.any((n) => n.value == '!' && n.className == 'operator'),
          true,
          reason: lang,
        );
        expect(
          cNodes.any(
            (n) =>
                (n.value?.contains('_controller') ?? false) &&
                n.className == 'operator',
          ),
          false,
          reason: lang,
        );
      }
    });
  });
}
