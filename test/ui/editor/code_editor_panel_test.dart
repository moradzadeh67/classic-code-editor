import 'dart:async';

import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/autocomplete_popup.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/completion_doc_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
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
    int column, {
    String? triggerCharacter,
    int? triggerKind,
  }) async {
    return completions;
  }

  @override
  Future<HoverInfo?> requestHover(String filePath, int line, int column) async {
    return null;
  }
}

/// LSP service that records the arguments passed to requestCompletion,
/// used by triggerCompletion tests.
class _TrackingLspService extends LspService {
  _TrackingLspService({required this.completions, required this.onRequest});

  final List<CompletionItem> completions;
  final void Function(int? triggerKind, int line, int column) onRequest;

  @override
  bool get isConnected => true;

  @override
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column, {
    String? triggerCharacter,
    int? triggerKind,
  }) async {
    onRequest(triggerKind, line, column);
    return completions;
  }

  @override
  Future<HoverInfo?> requestHover(String filePath, int line, int column) async {
    return null;
  }
}

/// LSP service that can resolve items, used by the documentation-panel tests.
class _DocsLspService extends LspService {
  _DocsLspService({required this.completions, required this.resolve});

  final List<CompletionItem> completions;
  final Future<ResolvedCompletionItem?> Function(CompletionItem item) resolve;

  @override
  bool get isConnected => true;

  @override
  bool get supportsCompletionResolve => true;

  @override
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column, {
    String? triggerCharacter,
    int? triggerKind,
  }) async {
    return completions;
  }

  @override
  Future<ResolvedCompletionItem?> resolveCompletionItem(
    CompletionItem item, {
    String? filePath,
  }) {
    return resolve(item);
  }

  @override
  Future<HoverInfo?> requestHover(String filePath, int line, int column) async {
    return null;
  }
}

/// LSP service that has an Untitled buffer open under a virtual path, like the
/// shell does for unsaved tabs.
class _UntitledLspService extends LspService {
  _UntitledLspService({
    required this.virtualPath,
    required this.completions,
    required this.onRequest,
  });

  final String virtualPath;
  final List<CompletionItem> completions;
  final void Function(String path) onRequest;

  @override
  bool get isConnected => true;

  @override
  String? get activeDocumentPath => virtualPath;

  @override
  bool get supportsCompletionResolve => true;

  @override
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column, {
    String? triggerCharacter,
    int? triggerKind,
  }) async {
    onRequest(filePath);
    return completions;
  }

  @override
  Future<ResolvedCompletionItem?> resolveCompletionItem(
    CompletionItem item, {
    String? filePath,
  }) async {
    onRequest('resolve:$filePath');
    return const ResolvedCompletionItem(documentation: 'Virtual docs.');
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

Widget _wrapSized({
  required double width,
  required double height,
  required Widget child,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: width, height: height, child: child),
    ),
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

  testWidgets(
    'triggerCompletion() opens popup with empty prefix (manual trigger)',
    (tester) async {
      // Track whether requestCompletion was called and with what args
      int callCount = 0;
      int? lastTriggerKind;
      int? lastLine;
      int? lastColumn;

      final lsp = _TrackingLspService(
        completions: const [
          CompletionItem(label: 'forEach', kind: 'method', detail: 'void'),
          CompletionItem(
            label: 'print',
            kind: 'function',
            detail: '(Object?) -> void',
          ),
        ],
        onRequest: (kind, line, column) {
          callCount++;
          lastTriggerKind = kind;
          lastLine = line;
          lastColumn = column;
        },
      );
      addTearDown(lsp.dispose);

      await tester.pumpWidget(
        _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
      );
      await tester.pumpAndSettle();

      // Call triggerCompletion() directly on the state
      final editorState = tester.state<CodeEditorPanelState>(
        find.byType(CodeEditorPanel),
      );
      editorState.triggerCompletion();

      // Allow the async request to complete
      await tester.pump();
      await tester.pumpAndSettle();

      // Should have called requestCompletion with triggerKind=1 (Invoked)
      expect(callCount, equals(1));
      expect(lastTriggerKind, equals(1));
      // Caret should be at line 1, column 1 (empty file)
      expect(lastLine, equals(1));
      expect(lastColumn, equals(1));

      // Popup should be open showing all completions (empty prefix matches everything)
      expect(find.byType(AutocompletePopup), findsOneWidget);
      expect(find.text('forEach'), findsOneWidget);
      expect(find.text('print'), findsOneWidget);
    },
  );

  testWidgets('the popup opens with no row highlighted', (tester) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'for');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsOneWidget);

    final state = tester.state<CodeEditorPanelState>(
      find.byType(CodeEditorPanel),
    );
    expect(
      state.debugSelectedCompletionIndex,
      -1,
      reason: 'nothing is pre-selected, so Enter/Tab cannot accept by accident',
    );
  });

  testWidgets('Enter dismisses the popup instead of accepting when nothing is '
      'highlighted', (tester) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'for');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsOneWidget);

    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(AutocompletePopup), findsNothing);
    expect(
      controller.text,
      'for\n',
      reason: 'the prefix stays as typed and Enter inserts a newline',
    );
  });

  testWidgets('ArrowDown selects the first row, then Tab moves on', (
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

    final state = tester.state<CodeEditorPanelState>(
      find.byType(CodeEditorPanel),
    );

    // Down: -1 → 0 (the first suggestion).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(state.debugSelectedCompletionIndex, 0);

    // Tab never accepts: it only moves the highlight.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsOneWidget);
    expect(state.debugSelectedCompletionIndex, isNot(0));
  });

  testWidgets('repeated Tab cycles through the suggestions in order', (
    tester,
  ) async {
    final lsp = _FakeLspService(
      completions: const [
        CompletionItem(label: 'alpha', kind: 'function'),
        CompletionItem(label: 'alphabet', kind: 'function'),
        CompletionItem(label: 'alpine', kind: 'function'),
      ],
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'alp');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsOneWidget);

    final state = tester.state<CodeEditorPanelState>(
      find.byType(CodeEditorPanel),
    );
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;

    for (final expected in [0, 1, 2, 0]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(state.debugSelectedCompletionIndex, expected);
      expect(find.byType(AutocompletePopup), findsOneWidget);
      expect(controller.text, 'alp', reason: 'Tab must not insert anything');
    }
  });

  testWidgets('Tab highlights the first row when nothing is selected yet', (
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

    final state = tester.state<CodeEditorPanelState>(
      find.byType(CodeEditorPanel),
    );

    // First Tab only moves the highlight: nothing is inserted yet.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(state.debugSelectedCompletionIndex, 0);
    expect(find.byType(AutocompletePopup), findsOneWidget);
  });

  testWidgets('Tab keeps current behavior (indent) when popup is hidden', (
    tester,
  ) async {
    final lsp = _FakeLspService(completions: completions);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsNothing);

    await tester.enterText(find.byType(TextField), 'x');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    // Popup should remain hidden; no exception thrown.
    expect(find.byType(AutocompletePopup), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'accepting a callable method inserts paren pair with caret inside',
    (tester) async {
      final lsp = _FakeLspService(
        completions: const [
          CompletionItem(label: 'forEach', kind: 'method', detail: 'void'),
        ],
      );
      addTearDown(lsp.dispose);

      await tester.pumpWidget(
        _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
      );
      await tester.enterText(find.byType(TextField), 'forE');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.byType(AutocompletePopup), findsOneWidget);

      // Nothing is selected yet: pick the row explicitly, as a user would.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      // Accept it (simulated by pressing Enter)
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // After accepting callable method, text should contain '()' with caret inside.
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      final text = controller.text;
      // The inserted callable text should have parentheses and caret between them.
      expect(text.contains('('), isTrue);
    },
  );

  testWidgets(
    'typing stless and pressing Enter inserts a StatelessWidget snippet',
    (tester) async {
      final lsp = _FakeLspService(completions: completions);
      addTearDown(lsp.dispose);

      await tester.pumpWidget(
        _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
      );
      await tester.enterText(find.byType(TextField), 'stless');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.byType(AutocompletePopup), findsOneWidget);
      expect(_suggestion('stless'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      final text = controller.text;
      expect(text, contains('class MyWidget extends StatelessWidget {'));
      expect(text, contains('const MyWidget({super.key});'));
      expect(text, contains('Widget build(BuildContext context) {'));
      // The caret landed on the class name (right after `class `).
      expect(controller.selection.baseOffset, equals('class '.length));
    },
  );

  testWidgets('documentation panel waits for the 2 s idle delay', (
    tester,
  ) async {
    final lsp = _DocsLspService(
      completions: const [
        CompletionItem(label: 'alpha', kind: 'function'),
        CompletionItem(label: 'alphabet', kind: 'variable'),
      ],
      resolve: (item) async => ResolvedCompletionItem(
        documentation: item.label == 'alpha'
            ? 'Alpha documentation.'
            : 'Alphabet documentation.',
      ),
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    // 150 ms completion debounce, then one frame for the popup.
    await tester.enterText(find.byType(TextField), 'alp');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.byType(AutocompletePopup), findsOneWidget);

    // The popup opens with no row highlighted, so no docs are fetched yet.
    await tester.pump(kCompletionDocPanelDelay);
    await tester.pump();
    expect(find.byType(CompletionDocPanel), findsNothing);

    // Highlighting the first row starts the 2 s doc clock.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // 1.9 s idle: still hidden (resolve has already happened in the cache).
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.byType(CompletionDocPanel), findsNothing);

    // 2.0 s idle: the panel appears.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byType(CompletionDocPanel), findsOneWidget);
    expect(find.text('Alpha documentation.'), findsOneWidget);

    // Moving to the next row hides it at once and restarts the 2 s clock.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byType(CompletionDocPanel), findsNothing);

    await tester.pump(kCompletionDocPanelDelay);
    await tester.pump();
    expect(find.text('Alphabet documentation.'), findsOneWidget);
    expect(find.text('Alpha documentation.'), findsNothing);
  });

  testWidgets('a key press hides the panel and restarts the idle clock', (
    tester,
  ) async {
    final lsp = _DocsLspService(
      completions: const [CompletionItem(label: 'alpha', kind: 'function')],
      resolve: (item) async =>
          const ResolvedCompletionItem(documentation: 'Alpha documentation.'),
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'alp');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    // Highlight the single row, then let the 2 s doc clock elapse.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(kCompletionDocPanelDelay);
    await tester.pump();
    expect(find.byType(CompletionDocPanel), findsOneWidget);

    // A key press (an arrow that keeps the same row) hides it immediately.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.byType(CompletionDocPanel), findsNothing);

    await tester.pump(const Duration(milliseconds: 1900));
    expect(
      find.byType(CompletionDocPanel),
      findsNothing,
      reason: 'the 2 s idle clock restarted at the key press',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.byType(CompletionDocPanel), findsOneWidget);
  });

  testWidgets('documentation falls back to the resolved detail', (
    tester,
  ) async {
    final lsp = _DocsLspService(
      completions: const [CompletionItem(label: 'alpha', kind: 'function')],
      resolve: (item) async =>
          const ResolvedCompletionItem(detail: 'Alpha detail text.'),
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'alp');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(kCompletionDocPanelDelay);
    await tester.pump();

    expect(find.byType(CompletionDocPanel), findsOneWidget);
    expect(find.text('Alpha detail text.'), findsOneWidget);
  });

  testWidgets('ignores a resolve answer for a row that is no longer selected', (
    tester,
  ) async {
    final pending = <String, Completer<ResolvedCompletionItem?>>{
      'alpha': Completer<ResolvedCompletionItem?>(),
      'alphabet': Completer<ResolvedCompletionItem?>(),
    };
    final lsp = _DocsLspService(
      completions: const [
        CompletionItem(label: 'alpha', kind: 'function'),
        CompletionItem(label: 'alphabet', kind: 'variable'),
      ],
      resolve: (item) => pending[item.label]!.future,
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'alp');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    // Highlight `alpha`, then let its fast resolve start (still pending)...
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // ...then the selection moves to `alphabet` before alpha answers.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    pending['alphabet']!.complete(
      const ResolvedCompletionItem(documentation: 'Alphabet documentation.'),
    );
    pending['alpha']!.complete(
      const ResolvedCompletionItem(documentation: 'Alpha documentation.'),
    );
    await tester.pump();

    // Only the row that stayed selected for 2 s may show its docs.
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.byType(CompletionDocPanel), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.byType(CompletionDocPanel), findsOneWidget);
    expect(find.text('Alphabet documentation.'), findsOneWidget);
    expect(find.text('Alpha documentation.'), findsNothing);
  });

  testWidgets('accepting an auto-import item inserts the import above', (
    tester,
  ) async {
    final lsp = _DocsLspService(
      completions: const [
        CompletionItem(
          label: 'Timer',
          kind: 'class',
          raw: <String, dynamic>{
            'label': 'Timer',
            'data': <String, dynamic>{'ref': 'dart:async;Timer'},
          },
        ),
      ],
      resolve: (item) async => const ResolvedCompletionItem(
        documentation: 'A countdown timer.',
        additionalTextEdits: [
          CompletionTextEdit(
            startLine: 0,
            startCharacter: 0,
            endLine: 0,
            endCharacter: 0,
            newText: "import 'dart:async';\n\n",
          ),
        ],
      ),
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'Tim');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(AutocompletePopup), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    const importLine = "import 'dart:async';\n\n";
    expect(
      controller.text,
      '$importLine'
      'Timer',
    );
    expect(controller.selection.baseOffset, importLine.length + 'Timer'.length);
  });

  testWidgets('shows no documentation panel when resolve yields nothing', (
    tester,
  ) async {
    final lsp = _DocsLspService(
      completions: const [CompletionItem(label: 'alpha', kind: 'function')],
      resolve: (item) async => null,
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'alp');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.byType(AutocompletePopup), findsOneWidget);
    expect(find.byType(CompletionDocPanel), findsNothing);
  });

  testWidgets('falls back to the item documentation when resolve is off', (
    tester,
  ) async {
    final lsp = _FakeLspService(
      completions: const [
        CompletionItem(
          label: 'alpha',
          kind: 'function',
          documentation: 'Inline **docs**.',
        ),
      ],
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'alp');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(kCompletionDocPanelDelay);
    await tester.pumpAndSettle();

    expect(find.byType(CompletionDocPanel), findsOneWidget);
    expect(find.text('Inline docs.'), findsOneWidget);
  });

  testWidgets(
    'Tab inserts two spaces and never moves focus out of the editor',
    (tester) async {
      final lsp = _FakeLspService(completions: const []);
      addTearDown(lsp.dispose);
      // A plain-text buffer: no offline keyword list, so Tab is the only thing
      // that can change the text.
      fileService.openFilePath('/tmp/notes.txt', '');

      await tester.pumpWidget(
        _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
      );
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pumpAndSettle();
      // Dismiss the offline keyword list so Tab inserts indentation.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final focusNode = tester
          .widget<TextField>(find.byType(TextField))
          .focusNode!;
      expect(focusNode.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      expect(controller.text, 'ab  ');
      expect(controller.selection.baseOffset, 4);
      expect(
        focusNode.hasPrimaryFocus,
        isTrue,
        reason: 'Tab must be handled by the editor, not by focus traversal',
      );
    },
  );

  testWidgets('Shift+Tab outdents the caret line by up to two spaces', (
    tester,
  ) async {
    final lsp = _FakeLspService(completions: const []);
    addTearDown(lsp.dispose);
    fileService.openFilePath('/tmp/notes.txt', '');

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), '    four');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    expect(controller.text, '  four');
    final focusNode = tester
        .widget<TextField>(find.byType(TextField))
        .focusNode!;
    expect(focusNode.hasPrimaryFocus, isTrue);
  });

  testWidgets('Tab indents every line of a multi-line selection', (
    tester,
  ) async {
    final lsp = _FakeLspService(completions: const []);
    addTearDown(lsp.dispose);
    fileService.openFilePath('/tmp/notes.txt', '');

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'one\ntwo');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(controller.text, '  one\n  two');
  });

  testWidgets('completion popup near the bottom flips above the caret', (
    tester,
  ) async {
    final lsp = _FakeLspService(
      completions: const [
        CompletionItem(label: 'alp', kind: 'function'),
        CompletionItem(label: 'alpha', kind: 'function'),
        CompletionItem(label: 'alphabet', kind: 'function'),
      ],
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrapSized(
        width: 420,
        height: 160,
        child: CodeEditorPanel(fileService: fileService, lspService: lsp),
      ),
    );
    await tester.enterText(find.byType(TextField), '\n\n\n\n\n\nalp');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    final popupFinder = find.byKey(AutocompletePopup.listKey);
    expect(popupFinder, findsOneWidget);

    final panelRect = tester.getRect(find.byType(CodeEditorPanel));
    final popupRect = tester.getRect(popupFinder);

    final editable = tester.allRenderObjects.whereType<RenderEditable>().first;
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    final caret = editable.localToGlobal(
      editable
          .getLocalRectForCaret(
            TextPosition(offset: controller.selection.baseOffset),
          )
          .topLeft,
    );

    expect(popupRect.top, greaterThanOrEqualTo(panelRect.top - 0.5));
    expect(popupRect.bottom, lessThanOrEqualTo(panelRect.bottom + 0.5));
    expect(
      popupRect.bottom,
      lessThanOrEqualTo(caret.dy + 2),
      reason: 'no room below the caret, so the list must flip above it',
    );
  });

  testWidgets('doc panel near the right edge moves left and stays in bounds', (
    tester,
  ) async {
    final lsp = _DocsLspService(
      completions: const [CompletionItem(label: 'alpha', kind: 'function')],
      resolve: (item) async =>
          const ResolvedCompletionItem(documentation: 'Alpha documentation.'),
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrapSized(
        width: 700,
        height: 400,
        child: CodeEditorPanel(fileService: fileService, lspService: lsp),
      ),
    );
    await tester.enterText(find.byType(TextField), '${'x ' * 40}alp');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(kCompletionDocPanelDelay);
    await tester.pumpAndSettle();

    final listRect = tester.getRect(find.byKey(AutocompletePopup.listKey));
    final docRect = tester.getRect(find.byType(CompletionDocPanel));
    final panelRect = tester.getRect(find.byType(CodeEditorPanel));

    expect(docRect.right, lessThanOrEqualTo(panelRect.right + 0.5));
    expect(docRect.left, greaterThanOrEqualTo(panelRect.left - 0.5));
    expect(
      docRect.left,
      lessThan(listRect.left),
      reason: 'no room right of the list, so the panel goes to its left',
    );
  });

  testWidgets('the menu command refocuses the editor and opens the popup', (
    tester,
  ) async {
    final requests = <int?>[];
    final lsp = _TrackingLspService(
      completions: const [CompletionItem(label: 'print', kind: 'function')],
      onRequest: (triggerKind, line, column) => requests.add(triggerKind),
    );
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'pri');
    await tester.pumpAndSettle();

    // A menu (or any other widget) takes the focus away before the callback
    // runs.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final focusNode = tester
        .widget<TextField>(find.byType(TextField))
        .focusNode!;
    expect(focusNode.hasPrimaryFocus, isFalse);

    final state = tester.state<CodeEditorPanelState>(
      find.byType(CodeEditorPanel),
    );
    state.triggerCompletionFromCommand();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(AutocompletePopup), findsOneWidget);
    expect(focusNode.hasPrimaryFocus, isTrue);
    expect(requests.last, 1, reason: 'manual trigger uses triggerKind 1');
  });

  testWidgets('an empty server answer shows nothing and no error', (
    tester,
  ) async {
    final lsp = _FakeLspService(completions: const []);
    addTearDown(lsp.dispose);

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'pri');
    await tester.pumpAndSettle();

    final state = tester.state<CodeEditorPanelState>(
      find.byType(CodeEditorPanel),
    );
    state.triggerCompletionFromCommand();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(AutocompletePopup), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("an Untitled buffer uses the server's virtual document path", (
    tester,
  ) async {
    const virtualPath = '/tmp/cce_unsaved/untitled.dart';
    final paths = <String>[];
    final lsp = _UntitledLspService(
      virtualPath: virtualPath,
      completions: const [CompletionItem(label: 'print', kind: 'function')],
      onRequest: paths.add,
    );
    addTearDown(lsp.dispose);

    // A real Untitled tab: no path, display name "Untitled".
    fileService.createNewFile();

    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
    );
    await tester.enterText(find.byType(TextField), 'pri');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(kCompletionDocPanelDelay);
    await tester.pumpAndSettle();

    // Completion and resolve must both address the document the server has
    // open; asking for "Untitled" returned nothing and is why the doc panel
    // never appeared.
    expect(paths, contains(virtualPath));
    expect(paths, contains('resolve:$virtualPath'));
    expect(paths, isNot(contains('Untitled')));
    expect(paths, isNot(contains('resolve:Untitled')));

    expect(find.byType(CompletionDocPanel), findsOneWidget);
    expect(find.text('Virtual docs.'), findsOneWidget);
  });

  group('line shortcuts', () {
    Future<TextEditingController> pumpEditor(
      WidgetTester tester,
      String text, {
      required int caret,
    }) async {
      final lsp = _FakeLspService(completions: const []);
      addTearDown(lsp.dispose);
      await tester.pumpWidget(
        _wrap(CodeEditorPanel(fileService: fileService, lspService: lsp)),
      );
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.selection = TextSelection.collapsed(offset: caret);
      await tester.pump();
      return controller;
    }

    /// Presses J and K together (K still held when J goes down).
    Future<void> pressChord(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+D duplicates the caret line', (tester) async {
      final controller = await pumpEditor(tester, 'a\nbc\nd', caret: 4);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, 'a\nbc\nbc\nd');
      expect(fileService.fileContent, 'a\nbc\nbc\nd');
    });

    testWidgets('J+K together ends the statement in Dart', (tester) async {
      final controller = await pumpEditor(tester, "print('hi')\nx", caret: 3);

      await pressChord(tester);

      expect(controller.text, "print('hi');\nx");
      expect(controller.selection, const TextSelection.collapsed(offset: 12));
      expect(fileService.fileContent, "print('hi');\nx");
    });

    testWidgets('K then J typed one after the other is not a chord', (
      tester,
    ) async {
      final controller = await pumpEditor(tester, 'foo()', caret: 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();

      expect(controller.text, isNot(contains(';')));
    });

    testWidgets('toolbar edit commands run the editor\'s own actions', (
      tester,
    ) async {
      // A fake system clipboard.
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          } else if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': clipboard};
          } else if (call.method == 'Clipboard.hasStrings') {
            return <String, dynamic>{'value': clipboard != null};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final controller = await pumpEditor(tester, 'hello world', caret: 0);
      final editor = tester.state<CodeEditorPanelState>(
        find.byType(CodeEditorPanel),
      );
      Future<void> run(EditorCommand command) async {
        editor.runEditCommand(command);
        await tester.pumpAndSettle();
      }

      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();
      await run(EditorCommand.copy);
      expect(clipboard, 'hello');

      await run(EditorCommand.cut);
      expect(controller.text, ' world');
      expect(clipboard, 'hello');

      // Flutter's undo history merges changes made within ~500 ms into one
      // step; a person is slower than that between a cut and a paste.
      await tester.pump(const Duration(seconds: 1));
      controller.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();
      await run(EditorCommand.paste);
      expect(controller.text, ' worldhello');

      // Undo walks back through the same history Cmd+Z uses.
      await tester.pump(const Duration(seconds: 1));
      await run(EditorCommand.undo);
      expect(controller.text, ' world');
      await run(EditorCommand.redo);
      expect(controller.text, ' worldhello');
    });

    testWidgets('J+K does nothing in Python', (tester) async {
      fileService.openFilePath('/tmp/script.py', '');
      final controller = await pumpEditor(tester, 'print(1)', caret: 2);

      await pressChord(tester);

      expect(controller.text, isNot(contains(';')));
    });
  });
}
