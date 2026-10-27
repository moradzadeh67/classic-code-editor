import 'package:classic_code_editor/models/diagnostic.dart';
import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A language server that only carries a diagnostics list the test can change,
/// exactly as the real per-URI map would after `publishDiagnostics`.
class _FakeDiagnosticsLspService extends LspService {
  List<Diagnostic> _list = const [];

  @override
  bool get isConnected => true;

  @override
  List<Diagnostic> get activeDiagnostics => _list;

  /// Replaces the published diagnostics and notifies like the server does.
  void publish(List<Diagnostic> diagnostics) {
    _list = diagnostics;
    notifyListeners();
  }

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

Diagnostic _diagnostic(int line, String severity, String message) => Diagnostic(
  file: '/tmp/main.dart',
  line: line,
  column: 1,
  severity: severity,
  message: message,
  code: 'test',
);

Color? _markerColor(WidgetTester tester, int line) {
  final finder = find.byKey(gutterMarkerKey(line));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Container>(finder).color;
}

void main() {
  late FileService fileService;
  late _FakeDiagnosticsLspService lspService;

  setUp(() {
    fileService = FileService();
    // Line 4 is long enough to wrap at this width; lines 1-3 do not.
    fileService.openFilePath(
      '/tmp/main.dart',
      'line1\nline2\nline3\n${'x' * 600}\nline5\n',
    );
    lspService = _FakeDiagnosticsLspService();
  });

  tearDown(() {
    fileService.dispose();
    lspService.dispose();
  });

  testWidgets('gutter markers follow diagnostics, per logical line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(CodeEditorPanel(fileService: fileService, lspService: lspService)),
    );
    await tester.pump();
    await tester.pump();

    // No diagnostics: no markers at all.
    expect(_markerColor(tester, 1), isNull);
    expect(_markerColor(tester, 2), isNull);

    // Line 4 really wraps, so there are continuation rows below it: line 5's
    // number sits below the row line 4 alone would occupy.
    final lineHeight = EditorMetrics.forFontSize(
      EditorSettingsService.instance.fontSize,
    ).lineHeight;
    expect(
      tester.getTopLeft(find.text('5')).dy,
      greaterThan(8 + 4 * lineHeight),
      reason: 'line 4 must wrap for the continuation-row case to be covered',
    );

    lspService.publish([
      _diagnostic(2, 'error', 'Undefined name'),
      _diagnostic(3, 'warning', 'Unused variable'),
      _diagnostic(4, 'error', 'A very long message'),
    ]);
    await tester.pump();
    await tester.pump();

    // Error row: red. Warning row: amber. Clean row: nothing.
    expect(_markerColor(tester, 2), const Color(0xFFD32F2F));
    expect(_markerColor(tester, 3), const Color(0xFFF9A825));
    expect(_markerColor(tester, 1), isNull);

    // A wrapped line paints its marker once, on its first row only: the
    // continuation row carries no marker, so there is exactly one per line.
    expect(_markerColor(tester, 4), const Color(0xFFD32F2F));
    expect(
      find.byKey(gutterMarkerKey(4)),
      findsOneWidget,
      reason: 'a wrapped logical line gets a single marker',
    );

    // An empty publish clears the markers.
    lspService.publish(const []);
    await tester.pump();
    expect(_markerColor(tester, 2), isNull);
    expect(_markerColor(tester, 3), isNull);
    expect(_markerColor(tester, 4), isNull);
    expect(tester.takeException(), isNull);
  });
}
