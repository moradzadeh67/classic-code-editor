import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end check of the real editor widget stack (the shell hands
/// `CodeEditorPanel` a bare `CodeController()`; the panel has to apply the
/// grammar itself), not just the highlighter in isolation.
const String pythonSource = '''
def greet(name="world"):
    # say hello
    count = 42
    print(name, count)
    return None
''';

const Color defaultTextColor = Color(0xFF000000);

/// `(text, effective color)` pairs of the paragraph the editor really paints.
List<({String text, Color? color})> _painted(WidgetTester tester) {
  final editable = tester.allRenderObjects.whereType<RenderEditable>().first;
  final out = <({String text, Color? color})>[];
  void walk(InlineSpan span, TextStyle? inherited) {
    if (span is! TextSpan) return;
    final effective = span.style ?? inherited;
    final text = span.text;
    if (text != null && text.isNotEmpty) {
      out.add((text: text, color: effective?.color));
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, effective);
    }
  }

  final span = editable.text;
  if (span != null) walk(span, null);
  return out;
}

Color? _colorOf(WidgetTester tester, String token) {
  final painted = _painted(tester);
  for (final entry in painted) {
    if (entry.text.trim() == token) return entry.color;
  }
  for (final entry in painted) {
    if (entry.text.contains(token)) return entry.color;
  }
  return null;
}

void _expectColored(WidgetTester tester, List<String> tokens) {
  for (final token in tokens) {
    final color = _colorOf(tester, token);
    expect(color, isNotNull, reason: '"$token" was not painted at all');
    expect(
      color,
      isNot(defaultTextColor),
      reason: '"$token" is painted in the default text color',
    );
  }
}

Future<FileService> _pumpPanel(WidgetTester tester) async {
  final fileService = FileService();
  addTearDown(fileService.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 600,
          child: CodeEditorPanel(
            fileService: fileService,
            lspService: LspService(),
            controller: CodeController(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fileService;
}

void main() {
  testWidgets('opening a .py file paints colored Python tokens', (
    tester,
  ) async {
    final fileService = await _pumpPanel(tester);
    fileService.openFilePath('/tmp/demo.py', pythonSource);
    await tester.pumpAndSettle();

    _expectColored(tester, [
      'def',
      '"world"',
      '# say hello',
      '42',
      'print',
      'return',
    ]);
  });

  testWidgets('an untitled Python tab paints colored tokens', (tester) async {
    final fileService = await _pumpPanel(tester);
    // No extension at all: the grammar has to come from the buffer content.
    fileService.openFilePath('/tmp/Untitled', pythonSource);
    await tester.pumpAndSettle();

    _expectColored(tester, [
      'def',
      '"world"',
      '# say hello',
      '42',
      'print',
      'return',
    ]);
  });
}
