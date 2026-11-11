import 'package:classic_code_editor/models/git_models.dart';
import 'package:classic_code_editor/services/analyzer_service.dart';
import 'package:classic_code_editor/services/dart_runner_service.dart';
import 'package:classic_code_editor/services/file_explorer_service.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/git_controller.dart';
import 'package:classic_code_editor/services/git_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/services/terminal_service.dart';
import 'package:classic_code_editor/ui/git/source_control_panel.dart';
import 'package:classic_code_editor/ui/shell/panel_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGitService extends GitService {
  _FakeGitService({this.changes = const <GitChange>[]});

  List<GitChange> changes;

  @override
  Future<GitAvailability> gitAvailability({GitCancelToken? cancel}) async =>
      const GitAvailability.available('/fake/bin/git');

  @override
  Future<String?> findRepoRoot(
    String directory, {
    GitCancelToken? cancel,
  }) async => '/repo';

  @override
  Future<GitRepoInfo?> repoInfo(String root, {GitCancelToken? cancel}) async =>
      GitRepoInfo(
        root: root,
        branch: 'main',
        isDetached: false,
        hasCommits: true,
        ahead: 0,
        behind: 0,
        remotes: const <GitRemote>[],
      );

  @override
  Future<List<GitChange>> status(String root, {GitCancelToken? cancel}) async =>
      changes;

  /// The panel fetches once when it opens; nothing network-shaped may run here.
  @override
  Future<GitResult> fetch(
    String root, {
    GitCancelToken? cancel,
    Duration timeout = GitService.fetchTimeout,
  }) async => const GitResult(0, '', '', false, false);
}

void main() {
  late DartRunnerService runner;
  late LspService lspService;
  late FileService fileService;
  late GitController gitController;

  setUp(() {
    runner = DartRunnerService();
    lspService = LspService();
    fileService = FileService();
    gitController = GitController(
      service: _FakeGitService(
        changes: <GitChange>[
          GitChange(path: 'draft.txt', indexStatus: '?', worktreeStatus: '?'),
        ],
      ),
      debounce: Duration.zero,
    );
    gitController.setExplorerFolder('/repo');
  });

  tearDown(() {
    runner.dispose();
    lspService.dispose();
    fileService.dispose();
    gitController.dispose();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await gitController.refreshNow();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
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
              gitController: gitController,
              activeFilePath: fileService.currentFilePath,
              onOpenFile: (_) {},
              onOpenFolder: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the bottom strip offers a Source Control tab', (tester) async {
    await pumpPanel(tester);

    expect(find.text('Source Control'), findsOneWidget);
    // Console is the default tab, so the panel is not on screen yet.
    expect(find.byKey(const Key('source-control-panel')), findsNothing);
  });

  testWidgets('tapping the Source Control tab shows the panel', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('Source Control'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-control-panel')), findsOneWidget);
    expect(find.byType(SourceControlPanel), findsOneWidget);
    expect(find.text('draft.txt'), findsOneWidget);
    expect(find.byKey(const Key('git-branch-header')), findsOneWidget);
  });

  testWidgets('selectBottomTab(4) selects Source Control from outside', (
    tester,
  ) async {
    final key = GlobalKey<PanelLayoutState>();
    await gitController.refreshNow();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 700,
            child: PanelLayout(
              key: key,
              showFileExplorer: false,
              showConsole: true,
              showDiagnostics: true,
              dartRunnerService: runner,
              analyzerService: AnalyzerService(),
              lspService: lspService,
              fileService: fileService,
              explorerService: FileExplorerService(),
              terminalService: TerminalService(),
              gitController: gitController,
              activeFilePath: fileService.currentFilePath,
              onOpenFile: (_) {},
              onOpenFolder: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    key.currentState!.selectBottomTab(4);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-control-panel')), findsOneWidget);
  });
}
