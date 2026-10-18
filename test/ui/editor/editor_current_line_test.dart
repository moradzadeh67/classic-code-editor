import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/services/theme_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The editor panel with no live language server attached.
class _QuietLspService extends LspService {
  @override
  bool get isConnected => true;

  @override
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column,
  ) async => const [];

  @override
  Future<HoverInfo?> requestHover(
    String filePath,
    int line,
    int column,
  ) async => null;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 900, height: 600, child: child)),
  );
}

/// Fill colour of the band painted behind the caret's row.
Color get _bandFill =>
    ThemeService.instance.colors.selection.withValues(alpha: 0.14);

/// The band painted behind the caret's row.
Finder _currentLineBand() => find.byWidgetPredicate(
  (widget) =>
      widget is DecoratedBox &&
      widget.decoration is BoxDecoration &&
      (widget.decoration as BoxDecoration).color == _bandFill,
  description: 'current-line band',
);

/// The hairline the band draws around itself (`lineHighlightBorder`).
Border? _bandBorder(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(_currentLineBand());
  return (box.decoration as BoxDecoration).border as Border?;
}

/// The tint painted on the caret's row inside the gutter.
Finder _gutterCaretTint() => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.color ==
          ThemeService.instance.colors.selection.withValues(alpha: 0.10),
  description: 'gutter caret tint',
);

/// Vertical offset of the band, relative to the top of the editor text area.
double _bandTop(WidgetTester tester) {
  final positioned = tester.widget<Positioned>(
    find
        .ancestor(of: _currentLineBand(), matching: find.byType(Positioned))
        .first,
  );
  return positioned.top!;
}

void main() {
  late FileService fileService;
  late LspService lspService;

  setUp(() {
    fileService = FileService();
    fileService.openFilePath('/tmp/main.dart', 'line1\nline2\nline3');
    lspService = _QuietLspService();
  });

  tearDown(() {
    fileService.dispose();
    lspService.dispose();
  });

  /// Taps [row] (zero based) far to the right of the code, where the line has
  /// no characters at all.
  Future<void> tapEmptyTail(WidgetTester tester, int row) async {
    final lineHeight = EditorMetrics.forFontSize(
      EditorSettingsService.instance.fontSize,
    ).lineHeight;
    // 8px is the panel padding; the editor area starts after the gutter.
    await tester.tapAt(Offset(700, 8 + row * lineHeight + lineHeight / 2));
    await tester.pump();
  }

  testWidgets('clicking past the end of a line highlights that whole row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lspService)),
    );
    await tester.pump();

    final lineHeight = EditorMetrics.forFontSize(
      EditorSettingsService.instance.fontSize,
    ).lineHeight;

    await tapEmptyTail(tester, 2);
    expect(_currentLineBand(), findsOneWidget);
    expect(_bandTop(tester), closeTo(2 * lineHeight, 0.01));

    // The band carries a 1px outline on all four sides.
    final border = _bandBorder(tester);
    expect(border, isNotNull);
    expect(border!.top.width, 1);
    expect(border.bottom.width, 1);
    expect(border.left.width, 1);
    expect(border.right.width, 1);

    // A click on another row moves the band with the caret.
    await tapEmptyTail(tester, 0);
    expect(_bandTop(tester), closeTo(0, 0.01));

    expect(tester.takeException(), isNull);
  });

  testWidgets('the gutter emphasises the caret line like desktop editors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lspService)),
    );
    await tester.pump();

    final accent = ThemeService.instance.colors.selection;

    // Nothing tapped yet: the caret sits on line 1.
    expect(tester.widget<Text>(find.text('1')).style!.color, accent);
    expect(tester.widget<Text>(find.text('2')).style!.color, isNot(accent));

    await tapEmptyTail(tester, 1);

    expect(tester.widget<Text>(find.text('2')).style!.color, accent);
    expect(tester.widget<Text>(find.text('1')).style!.color, isNot(accent));

    // Exactly one gutter row carries the caret tint - the caret's own row.
    expect(_gutterCaretTint(), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
