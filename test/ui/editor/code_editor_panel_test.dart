import 'package:borland_dart/models/lsp_models.dart';
import 'package:borland_dart/services/file_service.dart';
import 'package:borland_dart/services/lsp_service.dart';
import 'package:borland_dart/ui/editor/autocomplete_popup.dart';
import 'package:borland_dart/ui/editor/code_editor_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the `'child != this'` focus-tree crash.
class _FakeLspService extends LspService {
  _FakeLspService({required this.completions});

  final List<CompletionItem> completions;

  @override
  bool get isConnected => true;

  @override
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column,
  ) async {
    return completions;
  }

  @override
  Future<HoverInfo?> requestHover(String filePath, int line, int column) async {
    return null;
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 800, height: 600, child: child)),
  );
}

Finder _suggestion(String label) => find.byWidgetPredicate((widget) {
  if (widget is RichText) {
    return widget.text.toPlainText() == label;
  }
  if (widget is Text) {
    return widget.data == label;
  }
  return false;
}, description: 'suggestion "$label"');

void main() {
  late FileService fileService;
  late List<CompletionItem> completions;

  setUp(() {
    fileService = FileService();
    fileService.openFilePath('/tmp/main.dart', '');
    completions = const [
      CompletionItem(label: 'forEach', kind: 'method', detail: 'void'),
      CompletionItem(label: 'fold', kind: 'method', detail: 'T'),
      CompletionItem(label: 'pragma', kind: 'keyword'),
      CompletionItem(label: 'Pattern', kind: 'class'),
    ];
  });

  tearDown(() {
    fileService.dispose();
  });

  testWidgets('renders the editor after opening a file (no focus crash)', (
    tester,
  ) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(AutocompletePopup), findsNothing);
  });

  testWidgets(
    'opens the autocomplete popup without creating a focus-tree cycle',
    (tester) async {
      final lsp = _FakeLspService(completions: completions);
      addTearDown(lsp.dispose);

      await tester.pumpWidget(
        _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
      );

      await tester.enterText(find.byType(TextField), 'for');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      expect(find.byType(AutocompletePopup), findsOneWidget);
      expect(_suggestion('forEach'), findsOneWidget);
      expect(_suggestion('fold'), findsNothing);
    },
  );

  testWidgets('stays closed when text is empty', (tester) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsNothing);
  });

  testWidgets('closes the popup when the word is deleted back to empty', (
    tester,
  ) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );

    await tester.enterText(find.byType(TextField), 'for');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsNothing);
  });

  testWidgets('Escape dismisses the popup', (tester) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );

    await tester.enterText(find.byType(TextField), 'for');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsNothing);
  });

  testWidgets('filters out suggestions that do not match what was typed', (
    tester,
  ) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );

    await tester.enterText(find.byType(TextField), 'for');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(AutocompletePopup), findsOneWidget);
    expect(_suggestion('forEach'), findsOneWidget);
    expect(_suggestion('fold'), findsNothing);
    expect(_suggestion('pragma'), findsNothing);
    expect(_suggestion('Pattern'), findsNothing);
  });

  testWidgets('keeps the popup closed when nothing matches the typed prefix', (
    tester,
  ) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(AutocompletePopup), findsNothing);
  });

  testWidgets('shows the bare identifier for signature labels via filterText', (
    tester,
  ) async {
    final lsp = _FakeLspService(
      completions: const [
        CompletionItem(label: 'pragma', kind: 'keyword'),
        CompletionItem(label: 'Pattern', kind: 'class'),
        CompletionItem(
          label: 'print(...)',
          kind: 'method',
          detail: '(Object? object) \u2192 void',
          filterText: 'print',
          textEditNewText: 'print',
        ),
      ],
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );

    await tester.enterText(find.byType(TextField), 'prin');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(AutocompletePopup), findsOneWidget);
    expect(_suggestion('print'), findsOneWidget);
    expect(_suggestion('print(...)'), findsNothing);
    expect(_suggestion('pragma'), findsNothing);
    expect(_suggestion('Pattern'), findsNothing);
  });

  testWidgets('the text field owns the one and only focus node', (
    tester,
  ) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.focusNode, isNotNull);
    expect(textField.focusNode!.parent, isNotNull);

    expect(tester.takeException(), isNull);
  });
}
