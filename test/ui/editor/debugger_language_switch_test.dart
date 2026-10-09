import 'package:borland_dart/models/debugger_models.dart';
import 'package:borland_dart/models/lsp_models.dart';
import 'package:borland_dart/services/base_debugger.dart';
import 'package:borland_dart/services/debugger_factory.dart';
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
  testWidgets('gutter follows the debugger the shell swaps in', (tester) async {
    final fileService = FileService();
    addTearDown(fileService.dispose);
    fileService.openFilePath(
      '/tmp/main.dart',
      'void main() {\n  final x = 1;\n  return;\n}\n',
    );

    final lsp = _OfflineLspService();
    addTearDown(lsp.dispose);

    final factory = DebuggerFactory();
    addTearDown(factory.dispose);

    final dart = factory.dartDebugger;
    final python = factory.pythonDebugger;

    CodeEditorPanel build(BaseDebugger debugger) => CodeEditorPanel(
      fileService: fileService,
      lspService: lsp,
      debugger: debugger,
    );

    await tester.pumpWidget(_wrap(build(dart)));
    await tester.pumpAndSettle();

    // Dart paused on line 2: the marker sits on the second gutter row.
    dart.state = DebugState.paused;
    dart.currentPausedLine = 2;
    await tester.pumpWidget(_wrap(build(dart)));
    await tester.pump();

    expect(find.text('▶'), findsOneWidget);
    final dartMarkerY = tester.getCenter(find.text('▶')).dy;

    // The shell hands the panel the Python debugger when the active tab
    // language changes; the gutter must follow the new debugger.
    python.state = DebugState.paused;
    python.currentPausedLine = 3;
    await tester.pumpWidget(_wrap(build(python)));
    await tester.pump();

    // Still exactly one marker - and it moved down to the Python line.
    expect(find.text('▶'), findsOneWidget);
    expect(tester.getCenter(find.text('▶')).dy, greaterThan(dartMarkerY));
    expect(tester.takeException(), isNull);
  });
}
