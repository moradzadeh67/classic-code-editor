import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A language server that never connects, keeping the widget test offline.
class _OfflineLspService extends LspService {
  @override
  bool get isConnected => false;

  @override
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column,
  ) async => const <CompletionItem>[];

  @override
  Future<HoverInfo?> requestHover(
    String filePath,
    int line,
    int column,
  ) async => null;
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 900, height: 600, child: child)),
);

/// Byte offset of the start of [oneBasedLine].
int _offsetOfLine(String text, int oneBasedLine) {
  var offset = 0;
  var current = 1;
  while (current < oneBasedLine) {
    final nl = text.indexOf('\n', offset);
    if (nl < 0) return -1;
    offset = nl + 1;
    current++;
  }
  return offset;
}

void main() {
  /// The gutter used to be driven by the nominal `13 * 1.45 = 18.85`, while
  /// Flutter rounds a rendered line to 19.0. The 0.15px error accumulated per
  /// line, so the numbers detached from their code on longer files. This test
  /// measures the gutter against the editor's own text layout, not against the
  /// constant, so it would have caught the original bug.
  testWidgets('line numbers stay aligned with their code on a long file', (
    tester,
  ) async {
    final fileService = FileService();
    addTearDown(fileService.dispose);

    // Long enough that the old 0.15px-per-line drift became unmissable.
    final buffer = StringBuffer();
    for (var i = 1; i <= 120; i++) {
      buffer.writeln('final value$i = $i;');
    }
    final text = buffer.toString();
    fileService.openFilePath('/tmp/long.dart', text);

    final lsp = _OfflineLspService();
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.pumpAndSettle();

    final renderEditable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;

    for (final line in [1, 2, 3, 4, 10, 20, 30]) {
      final offset = _offsetOfLine(text, line);
      expect(offset, greaterThanOrEqualTo(0));

      // Where the code line really starts vs. where the gutter row sits.
      final caret = renderEditable.getLocalRectForCaret(
        TextPosition(offset: offset),
      );
      final codeTop = renderEditable.localToGlobal(caret.topLeft).dy;

      final gutterLabel = find.text('$line');
      expect(gutterLabel, findsOneWidget, reason: 'gutter row for line $line');

      final codeRowCentre = codeTop + editorLineHeight / 2;
      final gutterCentre = tester.getRect(gutterLabel).center.dy;

      // Sub-pixel tolerance: the point is that there is no *accumulating* error.
      expect(
        gutterCentre,
        closeTo(codeRowCentre, 0.05),
        reason: 'line $line gutter row must centre on its code line',
      );
    }

    expect(tester.takeException(), isNull);
  });

  /// The row height the gutter uses must equal what a text painter really
  /// renders, so the two can never drift apart again.
  test('editorLineHeight matches the rendered line height', () {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      strutStyle: const StrutStyle(
        fontFamily: 'Menlo',
        fontSize: editorFontSize,
        height: editorLineHeightFactor,
        forceStrutHeight: true,
      ),
    );
    painter.text = const TextSpan(
      text: 'a\nb',
      style: TextStyle(
        fontFamily: 'Menlo',
        fontSize: editorFontSize,
        height: editorLineHeightFactor,
      ),
    );
    painter.layout();

    final metrics = painter.computeLineMetrics();
    expect(metrics.length, 2);
    final renderedStep = metrics[1].baseline - metrics[0].baseline;

    expect(
      editorLineHeight,
      renderedStep,
      reason: 'the gutter row height must equal the rendered line height',
    );

    painter.dispose();
  });
}
