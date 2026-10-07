import 'package:borland_dart/models/lsp_models.dart';
import 'package:borland_dart/services/file_service.dart';
import 'package:borland_dart/services/lsp_service.dart';
import 'package:borland_dart/ui/editor/autocomplete_popup.dart';
import 'package:borland_dart/ui/editor/code_editor_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the `'child != this'` focus-tree crash.
///
/// The crash was caused by a single `FocusNode` being attached to three
/// nested widgets at once (`Focus` -> `KeyboardListener` -> `TextField`).
/// Flutter's `FocusNode._reparent` asserts `child != this` when that happens.
///
/// These tests pump the real editor subtree and open the autocomplete popup,
/// which is what surfaced the crash on device.

/// An [LspService] that reports itself as connected and returns fixed
/// completion results without spawning a language server process.
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

/// The popup renders each label through a [RichText] (so the typed prefix can
/// be emphasised), which means `find.text` alone does not match it. Search the
/// rendered text spans instead.
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
    // Opening a file is what used to trigger the red error screen.
    fileService.openFilePath('/tmp/main.dart', 'void main() {}\n');
    completions = const [
      CompletionItem(label: 'forEach', kind: 'method', detail: 'void'),
      CompletionItem(label: 'fold', kind: 'method', detail: 'T'),
      // Deliberately irrelevant to what we type below, to prove the popup
      // filters client-side instead of dumping the server's whole list.
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
    // The popup must not be visible until a completion request completes.
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

      // Type to arm the 300ms completion debounce. 'for' is a prefix of
      // forEach, and long enough (>= 3) to pass the visibility gate.
      await tester.enterText(find.byType(TextField), 'for');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // This is the assertion that used to fail with `child != this`.
      expect(tester.takeException(), isNull);

      expect(find.byType(AutocompletePopup), findsOneWidget);
      expect(_suggestion('forEach'), findsOneWidget);
      // 'fold' does not start with 'for', so the filter excludes it.
      expect(_suggestion('fold'), findsNothing);
    },
  );

  testWidgets('stays closed for prefixes shorter than the trigger length', (
    tester,
  ) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );

    // Just opening a file must not pop the list open.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsNothing);

    // 'fo' is only two characters, so nothing is requested or shown even
    // though 'forEach' would otherwise match.
    await tester.enterText(find.byType(TextField), 'fo');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsNothing);
  });

  testWidgets('closes the popup when the word is deleted back below the gate', (
    tester,
  ) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );

    await tester.enterText(find.byType(TextField), 'for');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsOneWidget);

    // Deleting back to 'fo' drops below the gate, so the popup must go away.
    await tester.enterText(find.byType(TextField), 'fo');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsNothing);

    // Deleting everything closes it too.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 350));
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

    // The server always returns forEach/fold/pragma/Pattern. Typing 'for'
    // must hide everything except 'forEach'.
    await tester.enterText(find.byType(TextField), 'for');
    await tester.pump(const Duration(milliseconds: 350));
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

    // 'zzz' matches none of the candidates, so no popup should be shown.
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.byType(AutocompletePopup), findsNothing);
  });

  testWidgets('shows the bare identifier for signature labels via filterText', (
    tester,
  ) async {
    // Mirrors the real `dart language-server` response for "prin":
    //   label: "print(...)", filterText: "print", textEdit: {newText: print}
    // plus unrelated keywords the server also returns.
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
    await tester.pumpAndSettle();

    // Only `print` survives, and it is shown without the signature noise.
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

    // The TextField's focus node must have no focus parent above it inside
    // the editor: the ancestor `Focus` widget only listens for key events and
    // deliberately does not share the node.
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.focusNode, isNotNull);
    expect(textField.focusNode!.parent, isNull);

    expect(tester.takeException(), isNull);
  });
}
