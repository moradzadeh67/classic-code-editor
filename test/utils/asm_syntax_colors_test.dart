import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classic_code_editor/models/language_config.dart';
import 'package:classic_code_editor/utils/multi_language_highlighter.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_code_editor/src/code_field/span_builder.dart';

/// A realistic Apple Silicon file: directives, labels, writes-back, literals.
const String asmSample = '''
// hello_arm64.s - macOS Apple Silicon
.section __TEXT,__cstring,cstring_literals
msg:
    .asciz "Hello from ARM64 assembly"

.text
.globl _main
.p2align 2
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adrp    x0, msg@PAGE
    add     x0, x0, msg@PAGEOFF
    bl      _printf
    mov     w0, #0
    ldp     x29, x30, [sp], #16
    ret
''';

const Color defaultTextColor = Color(0xFF000000);

/// `(token, effective color)` for the paragraph the editor really paints, using
/// the same `SpanBuilder` + `getThemeStyles()` path as `CodeEditorPanel`.
List<({String text, Color? color})> _painted() {
  final controller = MultiLanguageHighlighter.createController(
    text: asmSample,
    filePath: 'hello.s',
  );
  addTearDown(controller.dispose);

  final root = SpanBuilder(
    code: controller.code,
    theme: CodeThemeData(styles: MultiLanguageHighlighter.getThemeStyles()),
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

Color? colorOf(String token) {
  final painted = _painted();
  for (final entry in painted) {
    if (entry.text == token) return entry.color;
  }
  for (final entry in painted) {
    if (entry.text.contains(token)) return entry.color;
  }
  return null;
}

void main() {
  group('ARM64 Assembly colors', () {
    test('a label is the label/function color, not the operator color', () {
      // Regression: labels were tagged `symbol`, which resolves to the
      // operator green, so `_main:` looked like an operator and read as if the
      // palette had been swapped.
      expect(colorOf('_main:'), MultiLanguageHighlighter.methodColor);
      expect(colorOf('msg:'), MultiLanguageHighlighter.methodColor);
      expect(colorOf('_main:'), isNot(MultiLanguageHighlighter.operatorColor));
    });

    test('mnemonics, registers, directives and literals keep their colors', () {
      expect(colorOf('stp'), MultiLanguageHighlighter.keywordColor);
      expect(colorOf('mov'), MultiLanguageHighlighter.keywordColor);
      expect(colorOf('ret'), MultiLanguageHighlighter.keywordColor);

      expect(colorOf('x29'), MultiLanguageHighlighter.typeColor);
      expect(colorOf('sp'), MultiLanguageHighlighter.typeColor);

      expect(colorOf('.section'), MultiLanguageHighlighter.preprocessorColor);
      expect(colorOf('.globl'), MultiLanguageHighlighter.preprocessorColor);

      expect(colorOf('#-16'), MultiLanguageHighlighter.numberColor);
      expect(
        colorOf('"Hello from ARM64 assembly"'),
        MultiLanguageHighlighter.stringColor,
      );
      expect(
        colorOf('// hello_arm64.s'),
        MultiLanguageHighlighter.commentColor,
      );
    });

    test('separators are colored instead of falling back to black', () {
      for (final token in [',', '[', ']', '!']) {
        expect(
          colorOf(token),
          isNot(defaultTextColor),
          reason: '"$token" is painted in the default text color',
        );
      }
      expect(colorOf(','), MultiLanguageHighlighter.operatorColor);
      expect(colorOf('['), MultiLanguageHighlighter.bracketColor);
    });

    test('an untitled assembly buffer is sniffed to the ARM64 grammar', () {
      // No extension to go on: `.globl` / `.section` / `_main:` must be enough.
      final config = LanguageConfig.fromPathOrContent('Untitled', asmSample);
      expect(config.highlightLanguage, 'armasm');
      expect(colorOf('mov'), MultiLanguageHighlighter.keywordColor);
    });
  });
}
