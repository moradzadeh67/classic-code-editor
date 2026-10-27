import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/autocomplete_popup.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A server that is still warming up: not connected at first, then a real
/// `print` item (kind 3, detail) once it is.
class _WarmingLspService extends LspService {
  bool connected = false;
  int requests = 0;

  @override
  bool get isConnected => connected;

  @override
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column, {
    String? triggerCharacter,
    int? triggerKind,
  }) async {
    requests++;
    if (!connected) return const <CompletionItem>[];
    return const <CompletionItem>[
      CompletionItem(
        label: 'print',
        kind: 'method',
        kindInt: 3,
        detail: 'void print(Object? object)',
      ),
    ];
  }

  @override
  Future<HoverInfo?> requestHover(String filePath, int line, int column) async {
    return null;
  }
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 900, height: 600, child: child)),
);

Finder _suggestion(String label) => find.byWidgetPredicate((widget) {
  if (widget is RichText) return widget.text.toPlainText() == label;
  if (widget is Text) return widget.data == label;
  return false;
}, description: 'suggestion "$label"');

void main() {
  late FileService fileService;
  late _WarmingLspService lspService;

  setUp(() {
    fileService = FileService();
    fileService.openFilePath('/tmp/main.dart', '');
    lspService = _WarmingLspService();
  });

  tearDown(() {
    lspService.dispose();
    fileService.dispose();
  });

  testWidgets('the open popup upgrades itself when the server wakes up', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lspService)),
    );

    await tester.enterText(find.byType(TextField), 'pri');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    // Server not ready: the local keyword list is shown, and the word being
    // typed is not one of the candidates.
    expect(find.byType(AutocompletePopup), findsOneWidget);
    expect(_suggestion('print'), findsOneWidget);
    expect(_suggestion('pri'), findsNothing);
    // Nothing was asked of the server while it was down: the upgrade below can
    // only come from the retry, not from an early request.
    expect(lspService.requests, 0);
    final localBadge = tester
        .widgetList<CompletionBadgeChip>(find.byType(CompletionBadgeChip))
        .first;
    expect(localBadge.letter, 'K');

    // The server finishes `initialize`; the popup is still open on "pri".
    lspService.connected = true;
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(lspService.requests, greaterThan(0));
    expect(find.byType(AutocompletePopup), findsOneWidget);
    expect(_suggestion('print'), findsOneWidget);
    // The server's own item: M badge and the signature as detail.
    final badges = tester
        .widgetList<CompletionBadgeChip>(find.byType(CompletionBadgeChip))
        .toList();
    expect(badges.first.letter, 'M');
    expect(find.text('void print(Object? object)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
