import 'dart:io';
import 'dart:typed_data';

import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/c_debugger.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// Narrowing the editor must not break the gutter.
///
/// The rows used to be *predicted* (monospace advance × line length, then a
/// `TextPainter` at an assumed width). Persian text is set in the fallback font,
/// where a glyph is wider than that advance, so a line counted as one row could
/// render as two: every number below it sat one row too high, and the second
/// (wrapped) row of such a line had no number and looked unselectable.
///
/// The rows now come from the renderer, so these three things must hold at any
/// width: numbers sit exactly on their code row, a wrapped row has no number of
/// its own, and clicking a wrapped row selects the line it belongs to.
class _QuietLspService extends LspService {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> register(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    await (FontLoader(family)..addFont(
          Future<ByteData>.value(
            ByteData.sublistView(Uint8List.fromList(bytes)),
          ),
        ))
        .load();
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

  /// 60 lines; every 7th is a long Persian line, which is the case a monospace
  /// character-count prediction gets wrong.
  String document() => <String>[
    for (var i = 1; i <= 60; i++)
      i % 7 == 0
          ? '// ${'متن آزمایشی فارسی برای شکستن خط ' * 2}$i'
          : 'std::cout << "$i";',
  ].join('\n');

  int offsetOfLine(String text, int oneBased) {
    var offset = 0;
    for (var i = 1; i < oneBased; i++) {
      final nl = text.indexOf('\n', offset);
      if (nl < 0) return 0;
      offset = nl + 1;
    }
    return offset;
  }

  /// The first paint after a large pasted document used to keep the *predicted*
  /// rows: the renderer was not measurable on that frame, the rebuild gave up
  /// without rescheduling, and only a resize ever corrected the numbers.
  testWidgets('a big paste at first open still numbers every row correctly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    EditorSettingsService.instance.setFontSize(13);
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.recursive);

    final fileService = FileService();
    addTearDown(fileService.dispose);
    final lsp = _QuietLspService();
    addTearDown(lsp.dispose);

    // Open with a short buffer first, then "paste" 120 wrapping lines into the
    // already mounted editor - the sequence that failed in the app.
    fileService.openFilePath('/tmp/paste.cpp', 'int main() {}\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditorPanel(fileService: fileService, lspService: lsp),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = <String>[
      for (var i = 1; i <= 120; i++)
        i % 5 == 0
            ? '// ${'متن آزمایشی فارسی برای شکستن خط ' * 2}$i'
            : 'std::cout << "$i";',
    ].join('\n');

    final controller = tester
        .widget<EditableText>(find.byType(EditableText))
        .controller;
    controller.text = text;
    // Only a couple of frames: this is the window where the old code froze the
    // predicted rows.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final metrics = EditorMetrics.forFontSize(13);

    var checked = 0;
    for (var line = 1; line <= 40; line++) {
      final finder = find.text('$line');
      if (finder.evaluate().isEmpty) continue;
      final start = offsetOfLine(text, line);
      final caretTop = editable
          .getLocalRectForCaret(TextPosition(offset: start))
          .top;
      expect(
        tester.getRect(finder).center.dy,
        closeTo(caretTop + metrics.lineHeight / 2, metrics.lineHeight / 2),
        reason:
            'after a big paste on first open, number $line must sit on its own '
            'code row (no resize allowed to be the fix)',
      );
      checked++;
    }
    expect(checked, greaterThan(10), reason: 'the paste must be on screen');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a continuation row never sets a breakpoint on line 0', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    EditorSettingsService.instance.setFontSize(13);
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);

    final text = <String>[
      for (var i = 1; i <= 20; i++)
        i == 3
            ? '// ${'متن آزمایشی فارسی برای شکستن خط ' * 2}x'
            : 'std::cout << "$i";',
    ].join('\n');

    final debugger = CDebugger();
    addTearDown(debugger.dispose);
    final fileService = FileService();
    addTearDown(fileService.dispose);
    fileService.openFilePath('/tmp/bp.cpp', text);
    final lsp = _QuietLspService();
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditorPanel(
            fileService: fileService,
            lspService: lsp,
            debugger: debugger,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final metrics = EditorMetrics.forFontSize(13);
    final numberRect = tester.getRect(find.text('3'));

    // The second visual row of the wrapped line 3: its gutter row has no
    // number, so it must be inert.
    final continuationY = numberRect.center.dy + metrics.lineHeight;
    await tester.tapAt(Offset(numberRect.center.dx, continuationY));
    await tester.pumpAndSettle();
    expect(
      debugger.breakpoints,
      isEmpty,
      reason:
          'a continuation row has no line number, so it must not create a '
          'breakpoint (was line 0)',
    );

    // The real row still toggles.
    await tester.tapAt(numberRect.center);
    await tester.pumpAndSettle();
    expect(debugger.breakpoints.single.line, 3);
    expect(tester.takeException(), isNull);
  });

  for (final family in EditorFontFamily.values) {
    for (final width in <double>[520, 400]) {
      testWidgets('${family.id} at ${width.toInt()}px: wrapped rows keep the '
          'gutter honest', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        EditorSettingsService.instance.setFontSize(13);
        EditorSettingsService.instance.setFontFamily(family);

        final text = document();
        final fileService = FileService();
        addTearDown(fileService.dispose);
        fileService.openFilePath('/tmp/wrapped.cpp', text);
        final lsp = _QuietLspService();
        addTearDown(lsp.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CodeEditorPanel(fileService: fileService, lspService: lsp),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final metrics = EditorMetrics.forFontSize(13, family: family);
        final editable = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;

        double caretTop(int line) => editable
            .localToGlobal(
              editable
                  .getLocalRectForCaret(
                    TextPosition(offset: offsetOfLine(text, line)),
                  )
                  .topLeft,
            )
            .dy;

        // The document really wraps at this width, otherwise the test proves
        // nothing.
        final wrapped = <int>[
          for (var line = 1; line <= 60; line++)
            if (line < 60 &&
                (caretTop(line + 1) - caretTop(line)).abs() >
                    metrics.lineHeight * 1.5)
              line,
        ];
        expect(
          wrapped,
          isNotEmpty,
          reason:
              'a ${width.toInt()}px editor must wrap the long Persian lines',
        );

        // 1. Every painted number sits on its own code row.
        for (var line = 1; line <= 60; line++) {
          final finder = find.text('$line');
          if (finder.evaluate().isEmpty) continue;
          final numberRect = tester.getRect(finder);
          expect(
            numberRect.center.dy,
            closeTo(
              caretTop(line) + metrics.lineHeight / 2,
              metrics.lineHeight / 2,
            ),
            reason: 'the number $line must be on its code row',
          );
        }

        // 2. A wrapped row has no number of its own: the row after a wrapped
        //    line must not carry the next line's number.
        for (final line in wrapped.take(2)) {
          final nextRowTop = caretTop(line) + metrics.lineHeight;
          final numbersOnRow = <int>[];
          for (final widget in tester.widgetList<Text>(find.byType(Text))) {
            final number = int.tryParse(widget.data ?? '');
            if (number == null) continue;
            final matches = find.text('$number');
            if (matches.evaluate().isEmpty) continue;
            final top = tester.getRect(matches.first).top;
            if ((top - nextRowTop).abs() <= 2) numbersOnRow.add(number);
          }
          expect(
            numbersOnRow,
            isEmpty,
            reason:
                'the continuation row of line $line must be blank, but it '
                'shows $numbersOnRow',
          );
        }

        // 3. Clicking the continuation row selects the line it belongs to.
        final line = wrapped.first;
        final lineStart = offsetOfLine(text, line);
        final lineEnd = text.indexOf('\n', lineStart);
        // The tail of the line lives on its last visual row.
        final tailRect = editable.getLocalRectForCaret(
          TextPosition(offset: lineEnd - 1),
        );
        await tester.tapAt(
          editable.localToGlobal(
            tailRect.topLeft + Offset(tailRect.width / 2, tailRect.height / 2),
          ),
        );
        await tester.pumpAndSettle();

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
          reason:
              'clicking the wrapped (second) row of line $line must select '
              'line $line, not a neighbour',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the band covers every row of a wrapped line', (tester) async {
    tester.view.physicalSize = const Size(520, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    EditorSettingsService.instance.setFontSize(13);
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);

    final text = <String>[
      for (var i = 1; i <= 20; i++)
        i == 3
            ? '// ${'متن آزمایشی فارسی برای شکستن خط ' * 2}x'
            : 'std::cout << "$i";',
    ].join('\n');

    final fileService = FileService();
    addTearDown(fileService.dispose);
    fileService.openFilePath('/tmp/band.cpp', text);
    final lsp = _QuietLspService();
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditorPanel(fileService: fileService, lspService: lsp),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final metrics = EditorMetrics.forFontSize(13);
    final state = tester.state<CodeEditorPanelState>(
      find.byType(CodeEditorPanel),
    );

    Rect band() {
      for (final element in find.byType(DecoratedBox).evaluate()) {
        final decoration = (element.widget as DecoratedBox).decoration;
        if (decoration is! BoxDecoration) continue;
        final color = decoration.color;
        if (color == null || (color.a - 0.14).abs() > 0.01) continue;
        final box = element.renderObject! as RenderBox;
        return box.localToGlobal(Offset.zero) & box.size;
      }
      fail('the current-line band must be painted');
    }

    // A wrapped line: the band spans both of its rows, starting on the row the
    // gutter numbers.
    state.goToLine(3);
    await tester.pumpAndSettle();
    expect(band().top, closeTo(tester.getRect(find.text('3')).top, 0.01));
    expect(
      band().height,
      closeTo(2 * metrics.lineHeight, 0.01),
      reason: 'line 3 wraps onto two rows, so the band must cover both',
    );

    // A normal line: exactly one row, right on its number.
    state.goToLine(5);
    await tester.pumpAndSettle();
    expect(band().top, closeTo(tester.getRect(find.text('5')).top, 0.01));
    expect(band().height, closeTo(metrics.lineHeight, 0.01));
    expect(tester.takeException(), isNull);
  });
}
