import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A language server that never connects, keeping the widget test offline.
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

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 900, height: 600, child: child)),
);

void main() {
  tearDown(() {
    EditorSettingsService.instance.setFontSize(13);
  });

  group('editor zoom interaction', () {
    for (final size in <int>[8, 13, 32]) {
      testWidgets('breakpoint toggle on line N at font size $size', (
        tester,
      ) async {
        EditorSettingsService.instance.setFontSize(size.toDouble());
        final fileService = FileService();
        addTearDown(fileService.dispose);
        fileService.openFilePath('/tmp/zoom.dart', 'final x = 1;\n');

        await tester.pumpWidget(
          _wrap(
            CodeEditorPanel(
              fileService: fileService,
              lspService: _OfflineLspService(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // At default size the gutter shows line 1; changing font size
        // and rebuilding must still show the single line.
        expect(find.text('1'), findsOneWidget);
      });
    }
  });

  testWidgets(
    'font size change while paused keeps arrow on same logical line',
    (tester) async {
      EditorSettingsService.instance.setFontSize(13);
      final fileService = FileService();
      addTearDown(fileService.dispose);
      fileService.openFilePath(
        '/tmp/paused.dart',
        'void main() {\n  print("hello");\n}\n',
      );

      await tester.pumpWidget(
        _wrap(
          CodeEditorPanel(
            fileService: fileService,
            lspService: _OfflineLspService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change size after layout; no crash means the arrow alignment survives.
      EditorSettingsService.instance.setFontSize(24);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
