import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The caret, the gutter number and the current-line band must always agree.
///
/// They are three different code paths - the renderer's hit test, the gutter's
/// wrap-aware row list and the band's pixel position - and a regression in any
/// of them shows up as "I clicked line 400 and line 396 got selected" while the
/// numbers still look aligned. The band is now positioned from the renderer's
/// caret rect, so it cannot lag behind even when the row cache is stale.
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

void main() {
  tearDown(() {
    EditorSettingsService.instance.setFontSize(
      EditorSettingsService.defaultFontSize,
    );
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);
  });

  /// 400 lines; every 50th is long enough to wrap, so the visual rows above the
  /// target are greater than the logical line numbers (the case that exposes a
  /// band placed from the row cache).
  String document({required bool persian}) => <String>[
    for (var i = 1; i <= 400; i++)
      i % 50 == 0
          ? (persian ? '// ${'متن فارسی ' * 14}$i' : '// ${'long ' * 60}$i')
          : 'std::cout << "$i";',
  ].join('\n');

  Future<CodeEditorPanelState> pumpPanel(
    WidgetTester tester,
    String text, {
    void Function(int line, int column)? onCaretChanged,
  }) async {
    // A narrow surface like the real shell, so long lines really wrap.
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fileService = FileService();
    addTearDown(fileService.dispose);
    fileService.openFilePath('/tmp/click_line.cpp', text);
    final lsp = _OfflineLspService();
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditorPanel(
            fileService: fileService,
            lspService: lsp,
            onCaretChanged: onCaretChanged,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<CodeEditorPanelState>(find.byType(CodeEditorPanel));
  }

  RenderEditable renderEditable(WidgetTester tester) =>
      tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;

  int offsetOfLine(String text, int oneBased) {
    var offset = 0;
    for (var i = 1; i < oneBased; i++) {
      final nl = text.indexOf('\n', offset);
      if (nl < 0) return 0;
      offset = nl + 1;
    }
    return offset;
  }

  /// The band, found by its translucent selection fill (the only DecoratedBox
  /// in the editor using that colour at ~14% opacity).
  Rect bandRect(WidgetTester tester) {
    final band = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .where((box) {
          final decoration = box.decoration;
          if (decoration is! BoxDecoration) return false;
          final color = decoration.color;
          return color != null && (color.a - 0.14).abs() < 0.01;
        })
        .toList(growable: false);
    expect(band, isNotEmpty, reason: 'the current-line band must be painted');
    final renderObject = tester.renderObject<RenderBox>(
      find.byWidget(band.first),
    );
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  for (final persian in <bool>[false, true]) {
    testWidgets('clicking a row selects that line and moves the band (persian: '
        '$persian)', (tester) async {
      final text = document(persian: persian);
      final reported = <(int, int)>[];
      final panel = await pumpPanel(
        tester,
        text,
        onCaretChanged: (line, column) => reported.add((line, column)),
      );

      final metrics = EditorMetrics.standard;

      for (final line in <int>[50, 200, 400]) {
        // Scroll the row into view first: a tap can only land on a visible row.
        panel.goToLine(line);
        await tester.pumpAndSettle();
        final editable = renderEditable(tester);

        final caretRect = editable.getLocalRectForCaret(
          TextPosition(offset: offsetOfLine(text, line)),
        );
        final target = editable.localToGlobal(
          caretRect.topLeft + Offset(40, caretRect.height / 2),
        );

        await tester.tapAt(target);
        await tester.pumpAndSettle();

        // 1. The renderer's hit test landed on the clicked line.
        final selection = tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .selection;
        final selectedLine =
            '\n'.allMatches(text.substring(0, selection.extentOffset)).length +
            1;
        expect(
          selectedLine,
          line,
          reason: 'a click on row $line must select line $line',
        );

        // 2. The panel reported the same line - and a sensible column - to the
        //    shell, which is what the status bar shows.
        expect(reported.last.$1, line);
        expect(
          reported.last.$2,
          greaterThan(1),
          reason: 'the click was 40px into the row, not at column 1',
        );

        // 3. The band is painted exactly over the row the gutter numbers, and
        //    within a pixel of the caret rect (Flutter's caret rect is inflated
        //    ~1px above the line box, which is why the band is snapped to the
        //    row grid instead of using the rect's own top).
        final band = bandRect(tester);
        final caretTop = editable.localToGlobal(caretRect.topLeft).dy;
        final numberRect = tester.getRect(find.text('$line'));
        expect(
          band.top,
          closeTo(numberRect.top, 0.01),
          reason:
              'the band must start exactly on the number row of line $line '
              '(measured mismatch: ${band.top - numberRect.top}px)',
        );
        expect(
          (band.top - caretTop).abs(),
          lessThanOrEqualTo(1.5),
          reason: 'the band must sit on the caret of line $line',
        );
        // Its height is one row per visual row of the logical line: a wrapped
        // line is highlighted as a whole (line 50/200/400 in this document can
        // be wrapped at this width).
        final lineStart = offsetOfLine(text, line);
        final newline = text.indexOf('\n', lineStart);
        final endTop = editable
            .getLocalRectForCaret(
              TextPosition(offset: newline < 0 ? text.length : newline + 1),
            )
            .top;
        final span = ((endTop - caretRect.top) / metrics.lineHeight)
            .round()
            .clamp(1, 100);
        expect(
          band.height,
          closeTo(span * metrics.lineHeight, 0.01),
          reason: 'the band must cover all $span row(s) of line $line',
        );

        // 4. The gutter shows that same line at that height.
        expect(
          numberRect.center.dy,
          closeTo(caretTop + metrics.lineHeight / 2, metrics.lineHeight / 2),
          reason: 'the gutter number $line must be on the same row',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('goToLine reports the caret position and moves the band', (
    tester,
  ) async {
    final text = document(persian: true);
    final reported = <(int, int)>[];
    final panel = await pumpPanel(
      tester,
      text,
      onCaretChanged: (line, column) => reported.add((line, column)),
    );

    panel.goToLine(120);
    await tester.pumpAndSettle();

    expect(reported.last.$1, 120);
    expect(reported.last.$2, 1, reason: 'goToLine puts the caret at column 1');

    final editable = renderEditable(tester);
    final caretTop = editable
        .localToGlobal(
          editable
              .getLocalRectForCaret(
                TextPosition(offset: offsetOfLine(text, 120)),
              )
              .topLeft,
        )
        .dy;
    // The target line is scrolled into view, so only assert the band matches
    // the caret (not that it is inside the viewport).
    final band = bandRect(tester);
    expect(band.top, closeTo(caretTop, 1.0));
  });

  testWidgets('the band follows the caret after an edit above it', (
    tester,
  ) async {
    // The edit adds two wrapped rows above the caret; the gutter's row cache
    // must be rebuilt, and the band must still be on the caret.
    final text = document(persian: false);
    final panel = await pumpPanel(tester, text);

    panel.goToLine(300);
    await tester.pumpAndSettle();

    // Slip in a long line at the very top, which wraps into two rows.
    final controller = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;
    controller.text = '// ${'inserted ' * 40}\n$text';
    controller.selection = TextSelection.collapsed(
      offset: offsetOfLine(controller.text, 300),
    );
    await tester.pumpAndSettle();

    final editable = renderEditable(tester);

    // Whatever the controller ended up with (CodeController rewrites its spans
    // on a text change and may re-set the selection), the band must sit on the
    // live caret - that is the invariant, not a fixed line number.
    final liveOffset = controller.selection.extentOffset;
    final liveLine =
        '\n'.allMatches(controller.text.substring(0, liveOffset)).length + 1;
    final caretTop = editable
        .localToGlobal(
          editable
              .getLocalRectForCaret(TextPosition(offset: liveOffset))
              .topLeft,
        )
        .dy;
    expect(
      bandRect(tester).top,
      closeTo(caretTop, 1.0),
      reason:
          'a stale row cache must not move the band off the caret (caret is on '
          'line $liveLine at $caretTop)',
    );
    expect(tester.takeException(), isNull);
  });
}
