import 'package:classic_code_editor/models/git_models.dart';
import 'package:classic_code_editor/services/dart_runner_service.dart';
import 'package:classic_code_editor/services/file_explorer_service.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/git_controller.dart';
import 'package:classic_code_editor/services/git_service.dart';
import 'package:classic_code_editor/ui/git/source_control_panel.dart';
import 'package:classic_code_editor/ui/retro/retro_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGitService extends GitService {
  _FakeGitService({
    String? root,
    String? branch,
    bool? isDetached,
    bool? hasCommits,
    List<GitChange>? changes,
    String? upstream,
    bool hasUpstream = true,
    int? ahead,
    int? behind,
    List<GitRemote>? remotes,
  }) : _root = root ?? '/repo',
       _branch = branch ?? 'main',
       _isDetached = isDetached ?? false,
       _hasCommits = hasCommits ?? true,
       _changes = changes ?? <GitChange>[],
       _upstream = hasUpstream ? (upstream ?? 'origin/main') : null,
       _ahead = ahead ?? 0,
       _behind = behind ?? 0,
       _remotes =
           remotes ??
           const <GitRemote>[
             GitRemote('origin', 'https://github.com/user/repo.git'),
           ];

  final String? _root;
  final String _branch;
  final bool _isDetached;
  final bool _hasCommits;
  final List<GitChange> _changes;
  final String? _upstream;
  final int _ahead;
  final int _behind;
  final List<GitRemote> _remotes;

  GitResult pullResult = const GitResult(
    0,
    'Already up to date.\n',
    '',
    false,
    false,
  );

  int pullCalls = 0;
  List<GitCancelToken> pullCancelTokens = <GitCancelToken>[];

  @override
  Future<GitAvailability> gitAvailability({GitCancelToken? cancel}) async {
    return const GitAvailability.available('/fake/bin/git');
  }

  @override
  Future<String?> findRepoRoot(
    String directory, {
    GitCancelToken? cancel,
  }) async {
    return _root;
  }

  @override
  Future<GitRepoInfo?> repoInfo(String root, {GitCancelToken? cancel}) async {
    if (_root == null) return null;
    return GitRepoInfo(
      root: _root,
      branch: _branch,
      isDetached: _isDetached,
      hasCommits: _hasCommits,
      upstream: _upstream,
      ahead: _ahead,
      behind: behindOverride ?? _behind,
      remotes: _remotes,
    );
  }

  @override
  Future<List<GitChange>> status(String root, {GitCancelToken? cancel}) async {
    return _changes;
  }

  @override
  Future<GitResult> pull(
    String root, {
    GitCancelToken? cancel,
    Duration timeout = GitService.pullTimeout,
  }) async {
    pullCalls++;
    if (cancel != null) pullCancelTokens.add(cancel);
    return pullResult;
  }

  /// The panel fetches when it opens and on Refresh; nothing network-shaped may
  /// run here, so every call is faked and counted.
  GitResult fetchResult = const GitResult(0, '', '', false, false);
  int fetchCalls = 0;

  /// Lets a test move the remote ahead, as a real fetch would reveal.
  int? behindOverride;

  @override
  Future<GitResult> fetch(
    String root, {
    GitCancelToken? cancel,
    Duration timeout = GitService.fetchTimeout,
  }) async {
    fetchCalls++;
    return fetchResult;
  }
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required GitController gitController,
  required DartRunnerService runnerService,
  FileService? fileService,
  FileExplorerService? explorerService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SourceControlPanel(
          gitController: gitController,
          dartRunnerService: runnerService,
          fileService: fileService,
          explorerService: explorerService,
          onOpenFile: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Pull button label and enablement', (tester) async {
    final service = _FakeGitService(behind: 3);
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    final pullButtonFinder = find.byKey(const Key('git-pull-button'));
    expect(pullButtonFinder, findsOneWidget);

    final buttonWidget = tester.widget<RetroButton>(pullButtonFinder);
    expect(buttonWidget.onPressed, isNotNull);

    expect(find.text('Pull ↓3'), findsOneWidget);
  });

  testWidgets('Pull button is disabled when behind is 0', (tester) async {
    final service = _FakeGitService(behind: 0);
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    final buttonWidget = tester.widget<RetroButton>(
      find.byKey(const Key('git-pull-button')),
    );
    expect(buttonWidget.onPressed, isNull);
    expect(find.text('Pull'), findsOneWidget);
  });

  testWidgets('Pull button is disabled when upstream is null', (tester) async {
    final service = _FakeGitService(behind: 2, hasUpstream: false);
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    final buttonWidget = tester.widget<RetroButton>(
      find.byKey(const Key('git-pull-button')),
    );
    expect(buttonWidget.onPressed, isNull);
  });

  testWidgets('Pull refuses when uncommitted tracked changes exist', (
    tester,
  ) async {
    final service = _FakeGitService(
      behind: 2,
      changes: <GitChange>[
        GitChange(path: 'lib/main.dart', indexStatus: ' ', worktreeStatus: 'M'),
      ],
    );
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    await tester.tap(find.byKey(const Key('git-pull-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('git-pull-dialog')), findsNothing);
    expect(find.text('Commit or stash your changes first.'), findsOneWidget);
    expect(service.pullCalls, equals(0));
  });

  testWidgets('Pull confirm dialog details and cancel action', (tester) async {
    final service = _FakeGitService(behind: 4, upstream: 'origin/main');
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    await tester.tap(find.byKey(const Key('git-pull-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('git-pull-dialog')), findsOneWidget);
    expect(find.text('Upstream: origin/main'), findsOneWidget);
    expect(find.text('https://github.com/user/repo.git'), findsOneWidget);
    expect(find.text('4 commits will be pulled.'), findsOneWidget);
    expect(find.text('will run: git pull --ff-only'), findsOneWidget);

    await tester.tap(find.byKey(const Key('git-pull-dialog-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('git-pull-dialog')), findsNothing);
    expect(service.pullCalls, equals(0));
  });

  testWidgets('Confirming pull dialog runs git pull and logs to console', (
    tester,
  ) async {
    final service = _FakeGitService(behind: 1);
    service.pullResult = const GitResult(
      0,
      'Updating abc123..def456\nFast-forward\n',
      '',
      false,
      false,
    );
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    final outputLines = <String>[];
    runner.outputStream.listen(outputLines.add);

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    await tester.tap(find.byKey(const Key('git-pull-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('git-pull-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(service.pullCalls, equals(1));
    expect(outputLines, contains('[Git pull]'));
    expect(outputLines, contains('Updating abc123..def456'));
    expect(outputLines, contains('Fast-forward'));
    expect(find.text('Pulled'), findsOneWidget);
  });

  testWidgets('Diverged branches pull failure shows clear message', (
    tester,
  ) async {
    final service = _FakeGitService(behind: 1);
    service.pullResult = const GitResult(
      1,
      '',
      'fatal: Not possible to fast-forward, aborting.',
      false,
      false,
    );
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    await tester.tap(find.byKey(const Key('git-pull-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('git-pull-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Branches have diverged. Resolve this in a terminal (merge or rebase).',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Post-pull reloads unmodified tab and warns on modified tab', (
    tester,
  ) async {
    // The "disk" is a map: real file I/O inside testWidgets leaves its future
    // pending on the fake clock and hangs the test.
    final disk = <String, String>{
      '/repo/clean.txt': 'initial content\n',
      '/repo/dirty.txt': 'initial content\n',
    };
    final fileService = FileService(
      readTabFromDisk: (path) async => disk[path],
    );
    fileService.openFilePath('/repo/clean.txt', 'initial content\n');
    fileService.openFilePath('/repo/dirty.txt', 'initial content\n');

    // The editor holds an unsaved edit in dirty.txt.
    fileService.updateContent('modified in editor\n');

    // The pull rewrites both files on disk.
    disk['/repo/clean.txt'] = 'remote clean content\n';
    disk['/repo/dirty.txt'] = 'remote dirty content\n';

    final service = _FakeGitService(behind: 1);
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    final outputLines = <String>[];
    runner.outputStream.listen(outputLines.add);

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(
      tester,
      gitController: controller,
      runnerService: runner,
      fileService: fileService,
    );

    await tester.tap(find.byKey(const Key('git-pull-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('git-pull-dialog-confirm')));
    await tester.pumpAndSettle();

    // The tab without unsaved edits took the content found on disk.
    expect(fileService.openTabs[0].content, equals('remote clean content\n'));
    expect(fileService.openTabs[0].isModified, isFalse);

    // The tab with unsaved edits kept them, and the panel warned.
    expect(fileService.openTabs[1].content, equals('modified in editor\n'));
    expect(fileService.openTabs[1].isModified, isTrue);
    expect(
      outputLines,
      contains(
        '/repo/dirty.txt changed on disk but has unsaved edits; not reloaded',
      ),
    );
  });

  testWidgets('opening the panel fetches once per mount', (tester) async {
    // `behind` is only as fresh as the remote-tracking refs, so the panel is the
    // one place that fetches. Without it the Pull button could never enable.
    final service = _FakeGitService(behind: 2);
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    expect(service.fetchCalls, equals(1));

    // A rebuild reuses the State: no second fetch, and no network on every frame.
    await _pumpPanel(tester, gitController: controller, runnerService: runner);
    expect(service.fetchCalls, equals(1));
  });

  testWidgets('Refresh fetches, so behind updates without remounting', (
    tester,
  ) async {
    // The panel mounts with nothing behind, which is also the state after a
    // successful pull. Without a fetch on Refresh the button would stay dead
    // for as long as the panel stays open.
    final service = _FakeGitService();
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    expect(service.fetchCalls, equals(1));
    expect(
      tester
          .widget<RetroButton>(find.byKey(const Key('git-pull-button')))
          .onPressed,
      isNull,
    );

    // The remote moves on and the fetch that Refresh runs reveals it.
    service.behindOverride = 1;
    await tester.tap(find.byKey(const Key('git-refresh-button')));
    await tester.pumpAndSettle();

    expect(service.fetchCalls, equals(2));
    expect(find.text('Pull ↓1'), findsOneWidget);
    expect(
      tester
          .widget<RetroButton>(find.byKey(const Key('git-pull-button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('a Refresh whose fetch fails still refreshes the panel', (
    tester,
  ) async {
    final service = _FakeGitService(behind: 1);
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();
    final outputLines = <String>[];
    runner.outputStream.listen(outputLines.add);

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    outputLines.clear();
    service.fetchResult = const GitResult(
      1,
      '',
      'fatal: Could not resolve host: github.com',
      false,
      false,
    );
    await tester.tap(find.byKey(const Key('git-refresh-button')));
    await tester.pumpAndSettle();

    // The stale-but-known state is still drawn, and the failure is a Console
    // line rather than a banner about something the user did not press.
    expect(find.text('Pull ↓1'), findsOneWidget);
    expect(
      outputLines,
      contains(
        '[Git fetch] Could not reach the remote. Check the network and the '
        'remote URL.',
      ),
    );
  });

  testWidgets('a repo with no remote never fetches', (tester) async {
    final service = _FakeGitService(remotes: const <GitRemote>[]);
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    expect(service.fetchCalls, equals(0));
  });

  testWidgets('a failed fetch goes to the Console, not the panel banner', (
    tester,
  ) async {
    final service = _FakeGitService(behind: 1)
      ..fetchResult = const GitResult(
        128,
        '',
        'fatal: unable to access: Could not resolve host: github.com',
        false,
        false,
      );
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();
    final outputLines = <String>[];
    runner.outputStream.listen(outputLines.add);

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    expect(
      outputLines,
      contains(
        '[Git fetch] Could not reach the remote. Check the network and the '
        'remote URL.',
      ),
    );
    // The user did not press anything, so nothing is claimed about a pull.
    expect(find.textContaining('Fetch timed out'), findsNothing);
  });

  testWidgets('a disabled Pull explains that there is no upstream', (
    tester,
  ) async {
    final service = _FakeGitService(behind: 2, hasUpstream: false);
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('git-pull-button')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, SourceControlPanel.noUpstreamHint);
  });

  testWidgets('an up-to-date Pull says so and names the upstream', (
    tester,
  ) async {
    final service = _FakeGitService(behind: 0);
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('git-pull-button')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, 'Already up to date with origin/main.');
  });

  testWidgets('an enabled Pull carries no tooltip', (tester) async {
    final service = _FakeGitService(behind: 1);
    final controller = GitController(service: service, debounce: Duration.zero);
    final runner = DartRunnerService();

    controller.setExplorerFolder('/repo');
    await controller.refreshNow();
    await _pumpPanel(tester, gitController: controller, runnerService: runner);

    expect(
      find.ancestor(
        of: find.byKey(const Key('git-pull-button')),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
  });
}
