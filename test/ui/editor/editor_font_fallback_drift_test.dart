import 'dart:io';
import 'dart:typed_data';

import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// R1 of the Phase 22 follow-up: the **editor's own** row height must equal
/// `metrics.lineHeight` for every family, size and text kind, so the gutter, the
/// current-line band, scrolling and click-to-line mapping stay aligned over
/// thousands of lines.
///
/// Why this is a widget test and not a `TextPainter` one: a painter and the
/// editor round differently. `TextPainter.height` floors the strut's ascent and
/// descent halves separately, so it can report a forced row 1-3 px shorter than
/// `lineHeight`, while the editor's `RenderEditable` rounds `fontSize * height`
/// and renders it exactly. An earlier "fix" was validated against the painter and
/// was wrong in the app; the caret rects of a real `EditableText` are the ground
/// truth.
///
/// The Persian lines are the point: an unforced strut lets the fallback font of
/// a Persian glyph set the row height, which drifts the code by 1 px per such
/// line (2 px at size 32).
class _OfflineLspService extends LspService {
  @override
  bool get isConnected => false;

  @override
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column,
    {String? triggerCharacter, int? triggerKind}) async => const <CompletionItem>[];

  @override
  Future<HoverInfo?> requestHover(
    String filePath,
    int line,
    int column,
  ) async => null;
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 9000, height: 700, child: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Registers [path] under [family]; false when the host cannot provide it.
  Future<bool> register(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return false;
    final bytes = await file.readAsBytes();
    try {
      await (FontLoader(family)..addFont(
            Future<ByteData>.value(
              ByteData.sublistView(Uint8List.fromList(bytes)),
            ),
          ))
          .load();
      return true;
    } catch (_) {
      return false;
    }
  }

  setUpAll(() async {
    await register('Menlo', '/System/Library/Fonts/Menlo.ttc');
    await register(
      'RecursiveMonoCasual',
      'assets/fonts/RecursiveMonoCslSt-Regular.ttf',
    );
  });

  tearDown(() {
    EditorSettingsService.instance.setFontSize(
      EditorSettingsService.defaultFontSize,
    );
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);
  });

  String line(String kind, int i) => switch (kind) {
    'ascii' => 'final value$i = $i;',
    'persian' => '// سلام دنیا شماره $i - متن آزمایشی فارسی',
    _ => 'final s$i = "متن فارسی $i"; // ascii',
  };

  /// A 1000-line document with [kind] lines and every 10th line of [other], so
  /// the fallback path is exercised in both directions.
  String document(String kind, String other, {int lines = 1000}) =>
      List<String>.generate(
        lines,
        (i) => line(i % 10 == 9 ? other : kind, i + 1),
      ).join('\n');

  int offsetOfLine(String text, int oneBasedLine) {
    var offset = 0;
    for (var i = 1; i < oneBasedLine; i++) {
      final nl = text.indexOf('\n', offset);
      if (nl < 0) return 0;
      offset = nl + 1;
    }
    return offset;
  }

  /// Pumps the real editor and returns the caret top of each requested line.
  Future<Map<int, double>> caretTops(
    WidgetTester tester, {
    required String text,
    required List<int> lines,
  }) async {
    // A wide surface so one logical line is exactly one row at every size: the
    // default 800px test surface would wrap the Persian lines at size 32 and
    // make this a wrapping test by accident.
    tester.view.physicalSize = const Size(4000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fileService = FileService();
    addTearDown(fileService.dispose);
    fileService.openFilePath('/tmp/font_drift.dart', text);

    final lsp = _OfflineLspService();
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.pumpAndSettle();

    final renderEditable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;

    final tops = <int, double>{};
    for (final n in lines) {
      final rect = renderEditable.getLocalRectForCaret(
        TextPosition(offset: offsetOfLine(text, n)),
      );
      tops[n] = renderEditable.localToGlobal(rect.topLeft).dy;
    }
    return tops;
  }

  for (final size in <double>[8, 13, 32]) {
    for (final family in EditorFontFamily.values) {
      testWidgets(
        '${family.id}@$size keeps a 1000-line grid with Persian text',
        (tester) async {
          EditorSettingsService.instance.setFontSize(size);
          EditorSettingsService.instance.setFontFamily(family);
          final metrics = EditorMetrics.forFontSize(size, family: family);

          // The strut must be forced, or a fallback glyph sets the row.
          expect(metrics.strutStyle.forceStrutHeight, isTrue);
          expect(
            metrics.strutStyle.height,
            closeTo(metrics.lineHeightFactor, 1e-9),
          );
          expect(
            metrics.textStyle.height,
            closeTo(metrics.lineHeightFactor, 1e-9),
          );

          // The panel is 9000px wide, so one logical line is exactly one row and
          // the caret of line n must sit on row n - 1.
          const lines = <int>[1, 100, 400, 1000];
          for (final pair in const <List<String>>[
            ['ascii', 'persian'],
            ['persian', 'ascii'],
            ['persian', 'mixed'],
          ]) {
            final text = document(pair[0], pair[1]);
            final tops = await caretTops(tester, text: text, lines: lines);

            // Relative to line 1: the text field adds a constant padding that
            // has nothing to do with the row grid.
            final origin = tops[1]!;
            for (final n in lines) {
              expect(
                tops[n]! - origin,
                closeTo((n - 1) * metrics.lineHeight, 0.5),
                reason:
                    '${family.id}@$size ${pair[0]}/${pair[1]}: the caret of '
                    'line $n is ${tops[n]! - origin} below line 1, but the '
                    'gutter reserved ${(n - 1) * metrics.lineHeight} - a '
                    'fallback glyph must never change the row height',
              );
            }

            // Scrolling, click-to-line and the band all derive from this one
            // number, so prove the *step* is uniform too.
            final step = (tops[1000]! - tops[1]!) / 999;
            expect(
              step,
              closeTo(metrics.lineHeight, 0.01),
              reason:
                  '${family.id}@$size ${pair[0]}/${pair[1]}: rows advance by '
                  '$step px, not ${metrics.lineHeight}',
            );

            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  testWidgets('a wrapped 200-line document still advances one row per row', (
    tester,
  ) async {
    for (final family in EditorFontFamily.values) {
      EditorSettingsService.instance.setFontFamily(family);
      EditorSettingsService.instance.setFontSize(13);
      final metrics = EditorMetrics.forFontSize(13, family: family);

      // Long Persian lines in a 320px-wide editor wrap several times.
      final text = List<String>.generate(
        200,
        (i) => '// سلام دنیا $i ${'متن ' * 20}',
      ).join('\n');

      final fileService = FileService();
      addTearDown(fileService.dispose);
      fileService.openFilePath('/tmp/wrapped.dart', text);
      final lsp = _OfflineLspService();
      addTearDown(lsp.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 700,
              child: CodeEditorPanel(fileService: fileService, lspService: lsp),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final renderEditable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;

      // Two adjacent carets: one at the end of a wrapped line, one at the start
      // of the next. Their delta must be one row, never one row plus a remnant
      // of the taller fallback line.
      final firstEnd = renderEditable.localToGlobal(
        renderEditable.getLocalRectForCaret(TextPosition(offset: 40)).topLeft,
      );
      final nextLine = renderEditable.localToGlobal(
        renderEditable.getLocalRectForCaret(TextPosition(offset: 41)).topLeft,
      );
      final delta = (nextLine.dy - firstEnd.dy).abs();
      expect(
        delta % metrics.lineHeight,
        anyOf(closeTo(0, 0.01), closeTo(metrics.lineHeight, 0.01)),
        reason:
            '${family.id}: carets must sit on the same row grid in a wrapped '
            'document (delta $delta vs lineHeight ${metrics.lineHeight})',
      );
      expect(tester.takeException(), isNull);
    }
  });
}
