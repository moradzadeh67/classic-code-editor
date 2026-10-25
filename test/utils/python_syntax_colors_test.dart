import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classic_code_editor/services/theme_service.dart';
import 'package:classic_code_editor/ui/retro/syntax_colors.dart';
import 'package:classic_code_editor/utils/multi_language_highlighter.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_code_editor/src/code_field/span_builder.dart';
import 'package:highlight/highlight.dart' show Node;

/// A representative Python sample: every construct the editor must color.
const String sample = '''
from functools import wraps

@decorator
class Greeter:
    def greet(self, name="world"):
        # say hello
        message = f"Hello, {name}!"
        count = 42
        print(message)
        if count > 0 and True:
            return name
        return None
''';

/// The default editor text color (every retro theme paints code in black).
const Color defaultTextColor = Color(0xFF000000);

/// Flattened `(text, effective style)` pairs exactly as `SpanBuilder` resolves
/// them: the style of a node, or the inherited one from its ancestor.
List<({String text, TextStyle? style})> _flatten(
  TextSpan span,
  TextStyle? inherited,
) {
  final effective = span.style ?? inherited;
  final out = <({String text, TextStyle? style})>[];
  final text = span.text;
  if (text != null && text.isNotEmpty) {
    out.add((text: text, style: effective));
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) out.addAll(_flatten(child, effective));
  }
  return out;
}

/// The style the editor would give [token] in [filePath], using the exact code
/// path of `CodeEditorPanel` (controller → Code → SpanBuilder + CodeThemeData).
TextStyle? styleFor(
  String token, {
  required String filePath,
  String text = sample,
  String? sourcePath,
}) {
  final controller = MultiLanguageHighlighter.createController(
    text: text,
    filePath: sourcePath ?? filePath,
  );
  addTearDown(controller.dispose);

  final theme = CodeThemeData(
    styles: MultiLanguageHighlighter.getThemeStyles(),
  );
  final spans = SpanBuilder(
    code: controller.code,
    theme: theme,
    rootStyle: const TextStyle(color: defaultTextColor),
  ).build();

  final flat = _flatten(spans, const TextStyle(color: defaultTextColor));

  // Exact span first (a token usually owns its span), then a containing one.
  for (final entry in flat) {
    if (entry.text.trim() == token) return entry.style;
  }
  for (final entry in flat) {
    if (entry.text.contains(token)) return entry.style;
  }
  return null;
}

/// Every class name the Python grammar produced — used to explain a failure.
Set<String> pythonClasses() {
  final controller = MultiLanguageHighlighter.createController(
    text: sample,
    filePath: 'demo.py',
  );
  addTearDown(controller.dispose);
  final classes = <String>{};
  void walk(List<Node>? nodes) {
    for (final n in nodes ?? const <Node>[]) {
      if (n.className != null) classes.add(n.className!);
      walk(n.children);
    }
  }

  walk(controller.code.highlighted?.nodes);
  return classes;
}

bool isColored(TextStyle? style, {Color fallback = defaultTextColor}) {
  if (style == null) return false;
  final color = style.color;
  return color != null && color != fallback;
}

void main() {
  group('Python syntax coloring through the real editor path', () {
    test('.py file colors every kind of Python token', () {
      final expectations = <String, String>{
        'def': 'keyword',
        'class': 'keyword',
        'if': 'keyword',
        'return': 'keyword',
        'import': 'keyword',
        'from': 'keyword',
        'True': 'literal',
        'None': 'literal',
        '# say hello': 'comment',
        '"world"': 'string',
        'Hello, ': 'f-string literal part',
        '{name}': 'f-string interpolation',
        '42': 'number',
        'print': 'builtin',
        '@decorator': 'decorator',
      };

      final failures = <String>[];
      for (final token in expectations.keys) {
        final style = styleFor(token, filePath: 'demo.py');
        if (!isColored(style)) {
          failures.add(
            '$token (${expectations[token]}) → '
            '${style?.color?.toString() ?? 'null'}',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'tokens rendered with the default text color: ${failures.join(' | ')} '
            '— classes emitted by the python grammar: ${pythonClasses()}',
      );
    });

    test('untitled Python tab gets the same coloring', () {
      // An unsaved tab has no real path: the editor has to sniff the content
      // for `fileService.fileName` instead of falling back to Dart.
      for (final path in ['Untitled', 'Untitled-1', 'Untitled-1.py']) {
        final style = styleFor('def', filePath: path);
        expect(
          isColored(style),
          isTrue,
          reason: 'untitled path "$path" rendered ${style?.color} ',
        );
      }
    });

    test('sniffing keeps Dart and C buffers on their own grammar', () {
      const dartSample = '''
void main() {
  print("hi");
  final count = 42;
}
''';
      const cSample = '''
#include <stdio.h>
int main(void) { printf("hi"); return 0; }
''';

      expect(
        isColored(styleFor('void', filePath: 'Untitled', text: dartSample)),
        isTrue,
      );
      expect(
        isColored(styleFor('include', filePath: 'Untitled', text: cSample)),
        isTrue,
      );
    });
  });

  // The renderer resolves classes through one shared palette
  // (`MultiLanguageHighlighter.getThemeStyles()`), so a theme switch cannot
  // reintroduce the black fallback. One test per shipped theme makes that
  // explicit: keyword / string / comment must differ from that theme's default
  // editor text color.
  for (final theme in ThemeType.values) {
    test(
      '${theme.name}: keyword, string and comment are not the default text',
      () {
        final palette = SyntaxColors.forTheme(theme);
        final defaultColor = ThemeService.instance.colors.editorText;

        final keyword = styleFor('def', filePath: 'demo.py');
        final string = styleFor('"world"', filePath: 'demo.py');
        final comment = styleFor('# say hello', filePath: 'demo.py');

        expect(palette.keywords, isNot(defaultColor));
        expect(palette.strings, isNot(defaultColor));
        expect(palette.comments, isNot(defaultColor));
        expect(
          isColored(keyword, fallback: defaultColor),
          isTrue,
          reason: 'keyword ${keyword?.color}',
        );
        expect(
          isColored(string, fallback: defaultColor),
          isTrue,
          reason: 'string ${string?.color}',
        );
        expect(
          isColored(comment, fallback: defaultColor),
          isTrue,
          reason: 'comment ${comment?.color}',
        );
      },
    );
  }
}
