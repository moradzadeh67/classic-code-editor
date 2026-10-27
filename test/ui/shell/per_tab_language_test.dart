import 'package:classic_code_editor/models/language_config.dart';
import 'package:classic_code_editor/services/analyzer_service.dart';
import 'package:classic_code_editor/services/dart_runner_service.dart';
import 'package:classic_code_editor/services/file_explorer_service.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/services/terminal_service.dart';
import 'package:classic_code_editor/ui/retro/language_logo.dart';
import 'package:classic_code_editor/ui/shell/panel_layout.dart';
import 'package:classic_code_editor/utils/multi_language_highlighter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the language the toolbar's Run path would use, without spawning a
/// compiler.
class _RecordingRunner extends DartRunnerService {
  String? seenPath;
  String? seenLanguage;

  @override
  Future<void> runCode(
    String? filePath,
    String content, {
    String? preferredLanguage,
  }) async {
    seenPath = filePath;
    seenLanguage = preferredLanguage;
  }
}

String _dropdownValue(WidgetTester tester) => tester
    .widget<Text>(find.byKey(kLanguageDropdownLabelKey))
    .data!;

Future<void> _chooseLanguage(WidgetTester tester, String language) async {
  await tester.tap(find.byKey(kLanguageDropdownKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(language).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late FileService fileService;
  late _RecordingRunner runner;
  late LspService lspService;
  late CodeController controller;

  setUp(() {
    fileService = FileService();
    runner = _RecordingRunner();
    lspService = LspService();
    controller = CodeController();
  });

  tearDown(() {
    runner.dispose();
    lspService.dispose();
    fileService.dispose();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 700,
            child: PanelLayout(
              showFileExplorer: false,
              showConsole: true,
              showDiagnostics: true,
              dartRunnerService: runner,
              analyzerService: AnalyzerService(),
              lspService: lspService,
              fileService: fileService,
              explorerService: FileExplorerService(),
              terminalService: TerminalService(),
              activeFilePath: fileService.currentFilePath,
              onOpenFile: (_) {},
              onOpenFolder: () {},
              codeEditorController: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the selection belongs to the tab: B stays Auto and runs C', (
    tester,
  ) async {
    fileService.openFilePath('/tmp/a.py', 'print("a")');
    fileService.switchTab(0);
    fileService.setActiveLanguage('Python');
    // B is Auto on a .c file; opening it makes it active.
    fileService.openFilePath('/tmp/b.c', 'int main() { return 0; }');

    await pumpPanel(tester);
    expect(_dropdownValue(tester), 'Auto');

    await runner.runActiveFile(fileService);
    expect(runner.seenPath, '/tmp/b.c');
    expect(runner.seenLanguage, 'Auto');
    final effective = LanguageConfig.resolve(
      runner.seenPath,
      fileService.activeTab!.content,
      preferredLanguage: runner.seenLanguage ?? 'Auto',
    );
    expect(effective.language.displayName, 'C');

    // Back to A: its own selection is restored, not B's.
    fileService.switchTab(0);
    await tester.pump();
    expect(_dropdownValue(tester), 'Python');
    await runner.runActiveFile(fileService);
    expect(runner.seenLanguage, 'Python');
  });

  testWidgets('selecting Dart on a .s tab recolors and relabels immediately', (
    tester,
  ) async {
    fileService.openFilePath('/tmp/main.s', '.globl _main\n_main:\n  ret\n');
    await pumpPanel(tester);

    expect(
      controller.language,
      equals(MultiLanguageHighlighter.getModeForLanguage('armasm')),
    );
    expect(
      tester.widget<LanguageLogo>(find.byType(LanguageLogo)).language,
      'asm',
    );
    final before = controller.text;
    final selection = controller.selection;

    await _chooseLanguage(tester, 'Dart');

    expect(
      controller.language,
      equals(MultiLanguageHighlighter.getModeForLanguage('dart')),
    );
    expect(
      tester.widget<LanguageLogo>(find.byType(LanguageLogo)).language,
      'dart',
    );
    // Text and caret survived the re-highlight.
    expect(controller.text, before);
    expect(controller.selection, selection);

    // Auto goes back to the extension's assembly grammar.
    await _chooseLanguage(tester, 'Auto');
    expect(
      controller.language,
      equals(MultiLanguageHighlighter.getModeForLanguage('armasm')),
    );
    expect(
      tester.widget<LanguageLogo>(find.byType(LanguageLogo)).language,
      'asm',
    );
  });
}
