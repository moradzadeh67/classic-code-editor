import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// TASK-083: the editor owns the keyboard from the first frame.
///
/// A release build does not focus a text field by itself. Without an explicit
/// request the custom caret is not painted (it requires `hasFocus`) and typing
/// goes nowhere, which is exactly what the owner saw after the switch to
/// "always start empty".
void main() {
  late FileService fileService;
  late LspService lspService;

  setUp(() {
    fileService = FileService();
    fileService.createNewFile();
    lspService = LspService();
  });

  tearDown(() {
    lspService.dispose();
    fileService.dispose();
  });

  Widget wrap() => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: CodeEditorPanel(
          fileService: fileService,
          lspService: lspService,
        ),
      ),
    ),
  );

  FocusNode editorFocusNode(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).focusNode!;

  testWidgets('the active editor has primary focus after the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    final node = editorFocusNode(tester);
    expect(node.hasFocus, isTrue);
    expect(FocusManager.instance.primaryFocus, same(node));
    expect(find.byKey(const ValueKey<String>('editor-caret-overlay')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching tabs focuses the editor again', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();
    expect(editorFocusNode(tester).hasFocus, isTrue);

    // Something else takes the keyboard (e.g. the Console input), then a tab
    // is opened (a click on "+"), the editor must take it back.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(editorFocusNode(tester).hasFocus, isFalse);

    fileService.createNewFile();
    await tester.pump();
    await tester.pump();

    expect(editorFocusNode(tester).hasFocus, isTrue);
  });
}
