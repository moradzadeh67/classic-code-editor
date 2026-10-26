import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classic_code_editor/models/syntax_scheme.dart';
import 'package:classic_code_editor/utils/multi_language_highlighter.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_code_editor/src/code_field/span_builder.dart';

const Color defaultTextColor = Color(0xFF000000);

/// Every `(text, effective color)` pair the editor really paints, through the
/// exact `SpanBuilder` + `CodeThemeData` path `CodeEditorPanel` uses.
List<({String text, Color? color})> _painted(
  String source,
  String filePath,
  SyntaxScheme scheme,
) {
  final controller = MultiLanguageHighlighter.createController(
    text: source,
    filePath: filePath,
  );
  addTearDown(controller.dispose);

  final root = SpanBuilder(
    code: controller.code,
    theme: CodeThemeData(
      styles: MultiLanguageHighlighter.getThemeStyles(scheme),
    ),
    rootStyle: const TextStyle(color: defaultTextColor),
  ).build();

  final out = <({String text, Color? color})>[];
  void walk(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) return;
    final effective = span.style ?? inherited;
    final text = span.text;
    if (text != null && text.trim().isNotEmpty) {
      out.add((text: text.trim(), color: effective?.color));
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, effective);
    }
  }

  walk(root, const TextStyle(color: defaultTextColor));
  return out;
}

/// Colors of the characters of [source] as the editor paints them, in order.
List<({String char, Color? color})> _chars(
  String source,
  String filePath,
  SyntaxScheme scheme,
) => [
  for (final entry in _painted(source, filePath, scheme))
    for (final rune in entry.text.runes)
      (char: String.fromCharCode(rune), color: entry.color),
];

/// The color of the n-th occurrence of [char] in the painted paragraph.
Color? _nthColor(
  String source,
  String filePath,
  String char,
  int n, {
  SyntaxScheme scheme = SyntaxScheme.colorful,
}) {
  var seen = 0;
  for (final entry in _chars(source, filePath, scheme)) {
    if (entry.char == char) {
      if (seen == n) return entry.color;
      seen++;
    }
  }
  return null;
}

void main() {
  group('Colorful scheme: operators, braces and brackets', () {
    test('the accents are declared once', () {
      expect(colorfulOperatorColor, const Color(0xFFd6026c));
      expect(colorfulCurlyBraceColor, const Color(0xFF1e64d8));
      expect(colorfulSquareBracketColor, const Color(0xFF00796f));
    });

    test('Dart: operators, braces, square brackets and plain parentheses', () {
      const source = "final x = list[0] + map['a'] ?? {1: 2}[1];";
      final painted = _painted(source, 'demo.dart', SyntaxScheme.colorful);

      final operatorColors = <Color?>{
        for (final entry in painted)
          if (entry.text == '=' || entry.text == '+')
            entry.color,
      };
      expect(operatorColors, contains(colorfulOperatorColor));

      final style = MultiLanguageHighlighter.getThemeStyles(
        SyntaxScheme.colorful,
      );
      expect(style['operator']!.color, colorfulOperatorColor);
      expect(style['operator']!.fontWeight, FontWeight.bold);
      expect(style['curlyBrace']!.color, colorfulCurlyBraceColor);
      expect(style['squareBracket']!.color, colorfulSquareBracketColor);
      expect(style['punctuation']!.color, const Color(0xFF031CFC));

      // Braces and square brackets are actually painted apart (this line has
      // no parentheses).
      final paintedColors = _chars(source, 'demo.dart', SyntaxScheme.colorful)
          .map((e) => e.color)
          .toSet();
      expect(paintedColors, contains(colorfulCurlyBraceColor));
      expect(paintedColors, contains(colorfulSquareBracketColor));
      expect(paintedColors, isNot(contains(const Color(0xFF031CFC))));
      expect(paintedColors, contains(colorfulOperatorColor));

      // Parentheses keep the old Colorful bracket color.
      const call = 'f(g[0]);';
      final callColors = _chars(call, 'demo.dart', SyntaxScheme.colorful)
          .map((e) => e.color)
          .toSet();
      expect(callColors, contains(const Color(0xFF031CFC)));
      expect(callColors, contains(colorfulSquareBracketColor));
    });

    test('Python: dict braces and list brackets are their own colors', () {
      const source = 'd = {"k": [1, 2]}';
      final colors = _chars(source, 'demo.py', SyntaxScheme.colorful)
          .map((e) => e.color)
          .toSet();
      expect(colors, contains(colorfulCurlyBraceColor));
      expect(colors, contains(colorfulSquareBracketColor));
      expect(
        colors,
        isNot(contains(const Color(0xFF031CFC))),
        reason: 'no parentheses in this line',
      );
    });

    test('C: brackets, braces and parentheses each get their color', () {
      const source = 'a[i] += (b - c) * 2;';
      expect(
        _nthColor(source, 'demo.c', '{', 0, scheme: SyntaxScheme.colorful),
        isNull,
        reason: 'no braces in this line',
      );
      final colors = _chars(source, 'demo.c', SyntaxScheme.colorful)
          .map((e) => e.color)
          .toSet();
      expect(colors, contains(colorfulSquareBracketColor));
      expect(colors, contains(const Color(0xFF031CFC)));
      expect(colors, contains(colorfulOperatorColor));
    });

    test('Standard is unchanged: braces and brackets keep the bracket color', () {
      final standard = MultiLanguageHighlighter.getThemeStyles(
        SyntaxScheme.standard,
      );
      expect(standard['curlyBrace']!.color, const Color(0xFF031CFC));
      expect(standard['squareBracket']!.color, const Color(0xFF031CFC));
      expect(standard['punctuation']!.color, const Color(0xFF031CFC));
      expect(standard['operator']!.color, const Color(0xFF00BF69));

      final colors = _chars(
        'final x = list[0] + map["a"] ?? {1: 2}[1];',
        'demo.dart',
        SyntaxScheme.standard,
      ).map((e) => e.color).toSet();
      expect(colors, isNot(contains(colorfulCurlyBraceColor)));
      expect(colors, isNot(contains(colorfulSquareBracketColor)));
      expect(colors, isNot(contains(colorfulOperatorColor)));
    });

    test('text inside plain strings and comments is never recolored', () {
      final colors = _chars(
        "// { } [ ] + =\nfinal s = '{ } [ ] + =';",
        'demo.dart',
        SyntaxScheme.colorful,
      );
      expect(colors, isNot(contains(colorfulCurlyBraceColor)));
      expect(colors, isNot(contains(colorfulSquareBracketColor)));
      expect(colors, isNot(contains(colorfulOperatorColor)));
    });
  });
}
