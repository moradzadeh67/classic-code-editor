import 'dart:io';

import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Lines sitting all around the one-row/two-row wrap boundary, including a
/// tab-indented line (flutter_code_editor renders a tab as two spaces).
///
/// The 90- and 95-character lines are the interesting ones: the gutter's old
/// `fontSize * 0.62` estimate said 90 characters fitted on one row at 800px,
/// but the editor had already wrapped them onto two.
final _boundaryLines = <String>[
  'short = 1;',
  'a' * 60,
  'b' * 90,
  'c' * 95,
  'd' * 100,
  'e' * 105,
  'f' * 120,
  'g' * 200,
  '\tindented_call(arg1, arg2, arg3, arg4, arg5);',
  'final x = 42;',
];

final _fileContents = '${_boundaryLines.join('\n')}\n';

/// Pumps the editor at a specific width so wrapping can be exercised across
/// the range of window sizes the app supports.
Future<void> _pumpSized(WidgetTester tester, double width) async {
  final fileService = FileService();
  addTearDown(fileService.dispose);
  fileService.openFilePath('/tmp/gutter_alignment.dart', _fileContents);

  final lsp = _OfflineLspService();
  addTearDown(lsp.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 700,
          child: CodeEditorPanel(fileService: fileService, lspService: lsp),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The text the editor and the gutter actually lay out. The controller expands
/// tabs to spaces, so this is *not* always the raw file on disk.
String _laidOutText(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

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
  setUpAll(() async {
    // Loading the real font keeps the measurements honest. It is optional:
    // the gutter measures the actual font too, so the tests hold either way.
    final font = File('/System/Library/Fonts/Menlo.ttc');
    if (font.existsSync()) {
      final bytes = await font.readAsBytes();
      await (FontLoader(
        'Menlo',
      )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
    }
  });

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

    // The engine computes `fontSize * height` in floating point, so the real
    // step can differ from the constant in the last bits. What matters is that
    // the difference is far too small to accumulate over a long file.
    expect(
      renderedStep,
      closeTo(editorLineHeight, 0.01),
      reason: 'the gutter row height must equal the rendered line height',
    );

    painter.dispose();
  });

  /// The gutter once *guessed* the character advance as `fontSize * 0.62`
  /// (8.06px) while the editor really paints 8.33px, so a line that just
  /// exceeded the real capacity was assumed to fit on one row. The gutter then
  /// reserved one row too few and every number below it sat a full row high.
  for (final width in <double>[420, 520, 640, 800, 1000, 1200, 1600]) {
    testWidgets('gutter reserves a row per wrapped row at ${width}px', (
      tester,
    ) async {
      await _pumpSized(tester, width);

      // Offsets must come from the text the controller lays out, because it
      // expands tabs to spaces before the editor ever sees them.
      final text = _laidOutText(tester);
      final renderEditable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final first = renderEditable.getLocalRectForCaret(
        const TextPosition(offset: 0),
      );
      final last = renderEditable.getLocalRectForCaret(
        TextPosition(offset: text.length),
      );
      // The editor's own row count, read back from its caret positions.
      final editorRows =
          ((last.top - first.top) / editorLineHeight).round() + 1;

      final gutterRows = tester
          .widget<ListView>(find.byType(ListView))
          .childrenDelegate
          .estimatedChildCount;

      expect(
        gutterRows,
        editorRows,
        reason:
            'at ${width}px the editor painted $editorRows visual rows but the '
            'gutter reserved $gutterRows.',
      );
    });

    testWidgets('line numbers stay beside their line at ${width}px', (
      tester,
    ) async {
      await _pumpSized(tester, width);

      final lines = _laidOutText(tester).split('\n');
      final renderEditable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;

      var offset = 0;
      for (var i = 0; i < lines.length; i++) {
        final label = find.text('${i + 1}');
        expect(label, findsOneWidget, reason: 'gutter row for line ${i + 1}');

        final caret = renderEditable.getLocalRectForCaret(
          TextPosition(offset: offset),
        );
        final codeCentre =
            renderEditable.localToGlobal(caret.topLeft).dy +
            editorLineHeight / 2;
        final numberCentre = tester.getRect(label).center.dy;

        // A whole row is the failure mode, so half a row of tolerance catches
        // real drift without being brittle about sub-pixel centring.
        expect(
          (numberCentre - codeCentre).abs(),
          lessThan(editorLineHeight / 2),
          reason:
              'line ${i + 1} at ${width}px: the number sat '
              '${(numberCentre - codeCentre).toStringAsFixed(1)}px away from '
              'the line it labels.',
        );
        offset += lines[i].length + 1;
      }
    });
  }
}
