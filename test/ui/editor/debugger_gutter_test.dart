import 'package:borland_dart/models/debugger_models.dart';
import 'package:borland_dart/models/lsp_models.dart';
import 'package:borland_dart/services/dart_debugger.dart';
import 'package:borland_dart/services/file_service.dart';
import 'package:borland_dart/services/lsp_service.dart';
import 'package:borland_dart/ui/editor/code_editor_panel.dart';
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
  testWidgets('gutter marks the current paused line while debugging', (
    tester,
  ) async {
    final fileService = FileService();
    addTearDown(fileService.dispose);
    fileService.openFilePath(
      '/tmp/main.dart',
      'void main() {\n  final x = 1;\n}\n',
    );

    final lsp = _OfflineLspService();
    addTearDown(lsp.dispose);

    final debugger = DartDebugger();
    addTearDown(debugger.dispose);

    CodeEditorPanel build() => CodeEditorPanel(
      fileService: fileService,
      lspService: lsp,
      debugger: debugger,
    );

    await tester.pumpWidget(_wrap(build()));
    await tester.pumpAndSettle();

    // No paused line while the debugger is inactive.
    debugger.state = DebugState.paused;
    debugger.currentPausedLine = 2;

    // Rebuild the panel so it observes the new debugger state.
    await tester.pumpWidget(_wrap(build()));
    await tester.pump();

    expect(find.text('▶'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
