import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    {String? triggerCharacter, int? triggerKind}) async => const [];

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

/// The `Positioned` that carries the custom caret.
Positioned _caret(WidgetTester tester) => tester.widget<Positioned>(
  find.ancestor(of: find.byKey(kEditorCaretKey), matching: find.byType(Positioned)).first,
);

/// Whether the caret bar paints anything right now.
bool _caretVisible(WidgetTester tester) {
  final positioned = _caret(tester);
  return positioned.width! > 0 && positioned.height! > 0;
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

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lspService)),
    );
    await tester.pump();
  }

  /// Focuses the editor by clicking inside the code area.
  Future<void> focusEditor(WidgetTester tester) async {
    await tester.tapAt(const Offset(400, 20));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the caret blinks 300 ms on / 300 ms off and is 2.5 px wide', (
    tester,
  ) async {
    await pumpEditor(tester);
    await focusEditor(tester);

    expect(_caretVisible(tester), isTrue);
    expect(_caret(tester).width, 2.5);

    // 300 ms later the bar is off...
    await tester.pump(const Duration(milliseconds: 300));
    expect(_caretVisible(tester), isFalse);

    // ...and 600 ms after the reset it is painted again.
    await tester.pump(const Duration(milliseconds: 300));
    expect(_caretVisible(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a key press makes the caret solid again right away', (
    tester,
  ) async {
    await pumpEditor(tester);
    await focusEditor(tester);

    // Let it blink off.
    await tester.pump(const Duration(milliseconds: 300));
    expect(_caretVisible(tester), isFalse);

    // Moving the caret with the keyboard restarts the blink, visible.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_caretVisible(tester), isTrue);

    // The restarted clock then runs from that moment.
    await tester.pump(const Duration(milliseconds: 300));
    expect(_caretVisible(tester), isFalse);
    expect(tester.takeException(), isNull);
  });
}
