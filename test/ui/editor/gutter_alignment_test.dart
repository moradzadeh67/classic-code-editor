import 'dart:io';

import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  /// Boxes can match while the *glyphs* do not: a baseline is placed from the
  /// line box and the strut, not from the box height. This measures the real
  /// baseline of line 1's digit and of line 1's code, in screen space.
  for (final platform in <TargetPlatform>[
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    testWidgets('line number glyphs sit on the code baseline on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pumpSized(tester, 900);

        final renderEditable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        // The code's baseline is the *strut's* ascent: with
        // `forceStrutHeight` the line box is `lineHeight` tall and its ascent
        // is `ascentRatio * lineHeight`. Do NOT use
        // `RenderEditable.computeDistanceToActualBaseline` here - under a
        // forced strut it reports ~1px less than where the glyphs are painted,
        // which is exactly how a digit that visibly floats above the code kept
        // this test green.
        final metrics = EditorMetrics.forFontSize(
          EditorSettingsService.instance.fontSize,
        );
        final codePainter = TextPainter(
          textDirection: TextDirection.ltr,
          strutStyle: metrics.strutStyle,
        )..text = TextSpan(text: 'line 1', style: metrics.textStyle);
        codePainter.layout();
        final codeBaseline =
            renderEditable.localToGlobal(Offset.zero).dy +
            codePainter.computeDistanceToActualBaseline(
              TextBaseline.alphabetic,
            );
        codePainter.dispose();

        final numberParagraph = tester.renderObject<RenderParagraph>(
          find.text('1'),
        );
        final numberBaseline =
            numberParagraph.localToGlobal(Offset.zero).dy +
            numberParagraph.computeDistanceToActualBaseline(
              TextBaseline.alphabetic,
            );

        expect(
          numberBaseline,
          closeTo(codeBaseline, 0.5),
          reason:
              'the digit baseline is ${numberBaseline.toStringAsFixed(2)} but '
              'the code baseline is ${codeBaseline.toStringAsFixed(2)}.',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  /// The gutter once *guessed* the character advance as `fontSize * 0.62`
  /// (8.06px) while the editor really paints 8.33px, so a line that just
  /// exceeded the real capacity was assumed to fit on one row. The gutter then
  /// reserved one row too few and every number below it sat a full row high.
  for (final platform in <TargetPlatform>[
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    for (final width in <double>[420, 520, 640, 800, 1000, 1200, 1600]) {
      testWidgets(
        'gutter reserves a row per wrapped row at ${width}px on $platform',
        (tester) async {
          // Overriding the platform reproduces the typography the app really
          // runs with; ThemeData(platform:) alone does not.
          debugDefaultTargetPlatformOverride = platform;
          try {
            await _pumpSized(tester, width);

            // Offsets must come from the text the controller lays out, because
            // it expands tabs to spaces before the editor ever sees them.
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
                  'at ${width}px the editor painted $editorRows visual rows '
                  'but the gutter reserved $gutterRows.',
            );
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );

      testWidgets('line numbers share the code rows at ${width}px on $platform', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await _pumpSized(tester, width);

          final lines = _laidOutText(tester).split('\n');
          final renderEditable = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;

          var offset = 0;
          for (var i = 0; i < lines.length; i++) {
            final label = find.text('${i + 1}');
            expect(
              label,
              findsOneWidget,
              reason: 'gutter row for line ${i + 1}',
            );

            final caret = renderEditable.getLocalRectForCaret(
              TextPosition(offset: offset),
            );
            final caretCentre = renderEditable.localToGlobal(caret.center).dy;
            final numberBox = tester.getRect(label);

            // A line number must occupy exactly one code row. Matching the
            // height is what puts the digits on the code's baseline: a
            // baseline is placed from the line box, not from the glyph size,
            // so an 11px number in a 13px box floats 1.7px above the code.
            expect(
              numberBox.height,
              closeTo(editorLineHeight, 0.5),
              reason:
                  'line ${i + 1} at ${width}px: the number occupied a '
                  '${numberBox.height.toStringAsFixed(1)}px row but a code '
                  'line is ${editorLineHeight}px tall.',
            );
            // Compare centres rather than tops: the caret rect is taller than
            // its line on macOS (21px caret on a 19px line), so only its
            // centre marks where the row actually sits.
            expect(
              numberBox.center.dy,
              closeTo(caretCentre, 0.5),
              reason:
                  'line ${i + 1} at ${width}px: the number sat '
                  '${(numberBox.center.dy - caretCentre).toStringAsFixed(1)}px '
                  'away from the row it labels.',
            );
            offset += lines[i].length + 1;
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  group('editor zoom sizes {8, 13, 20, 32}', () {
    tearDown(() {
      EditorSettingsService.instance.setFontSize(13);
    });

    for (final size in <int>[8, 13, 20, 32]) {
      testWidgets('gutter stays aligned at font size $size', (tester) async {
        EditorSettingsService.instance.setFontSize(size.toDouble());
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 900,
                height: 700,
                child: CodeEditorPanel(
                  fileService: FileService()
                    ..openFilePath(
                      '/tmp/zoom.dart',
                      'final value1 = 1;\nfinal value2 = 2;\n',
                    ),
                  lspService: _OfflineLspService(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('font size change 13 -> 24 keeps numbering aligned', (
      tester,
    ) async {
      EditorSettingsService.instance.setFontSize(13);
      final fileService = FileService();
      addTearDown(fileService.dispose);
      fileService.openFilePath('/tmp/zoom_change.dart', _fileContents);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: CodeEditorPanel(
                fileService: fileService,
                lspService: _OfflineLspService(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change size after initial render (simulates user zoom).
      EditorSettingsService.instance.setFontSize(24);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '1200-line file at all four sizes shows no RenderFlex overflow',
      (tester) async {
        final buffer = StringBuffer();
        for (var i = 1; i <= 1200; i++) {
          buffer.writeln('final value$i = $i;');
        }
        final longText = buffer.toString();

        for (final size in <int>[8, 13, 20, 32]) {
          EditorSettingsService.instance.setFontSize(size.toDouble());
          final fileService = FileService();
          addTearDown(fileService.dispose);
          fileService.openFilePath('/tmp/long_1200.dart', longText);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 900,
                  height: 700,
                  child: CodeEditorPanel(
                    fileService: fileService,
                    lspService: _OfflineLspService(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'no overflow at size $size for 1200 lines',
          );
        }
      },
    );
  });
}
