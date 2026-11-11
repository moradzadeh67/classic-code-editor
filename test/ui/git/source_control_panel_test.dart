import 'dart:async';
import 'dart:io';

import 'package:classic_code_editor/models/git_models.dart';
import 'package:classic_code_editor/services/dart_runner_service.dart';
import 'package:classic_code_editor/services/git_controller.dart';
import 'package:classic_code_editor/services/git_service.dart';
import 'package:classic_code_editor/ui/git/source_control_panel.dart';
import 'package:classic_code_editor/ui/retro/retro_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGitService extends GitService {
  _FakeGitService({
    this.available = true,
    this.root = '/repo',
    this.hasCommits = true,
    this.changes = const <GitChange>[],
    this.stageResult = const GitResult(0, '', '', false, false),
    this.unstageResult = const GitResult(0, '', '', false, false),
    this.upstream,
    this.ahead = 0,
    this.remotes = const <GitRemote>[],
  });

  bool available;
  String? root;
  bool hasCommits;
  List<GitChange> changes;

  /// What [stage] answers; a failure value exercises the error path.
  GitResult stageResult;
  GitResult unstageResult;

  /// What [commit] answers; a failure value exercises the error path.
  GitResult commitResult = const GitResult(0, '', '', false, false);

  /// The effective `git config` values the identity check reads.
  String? identityName = 'Test User';
  String? identityEmail = 'test@example.com';

  /// The short SHA [headShortSha] answers with.
  String? shortSha = 'abc1234';

  /// When non-null, [commit] waits until the cancel token fires (or the
  /// completer is completed manually) — simulating a long-running process.
  bool holdCommit = false;

  /// The repository shape [repoInfo] reports.
  String? upstream;
  int ahead;
  List<GitRemote> remotes;

  /// What [push] answers; a failure value exercises the error path.
  GitResult pushResult = const GitResult(0, '', '', false, false);

  /// When non-null, [push] waits until the cancel token fires — simulating a
  /// slow remote.
  bool holdPush = false;

  final List<String> stagedPaths = <String>[];
  final List<String> unstagedPaths = <String>[];
  final List<String> commitMessages = <String>[];
  final List<String> localConfigKeys = <String>[];
  final List<String> localConfigValues = <String>[];
  final List<GitCancelToken> commitCancelTokens = <GitCancelToken>[];
  final List<({String remote, String branch, bool setUpstream})> pushCalls =
      <({String remote, String branch, bool setUpstream})>[];
  final List<GitCancelToken> pushCancelTokens = <GitCancelToken>[];
  int statusCalls = 0;

  /// Whether the last [unstage] was told the branch was unborn.
  bool? lastUnstageHasCommits;

  @override
  Future<GitAvailability> gitAvailability({GitCancelToken? cancel}) async {
    return available
        ? const GitAvailability.available('/fake/bin/git')
        : const GitAvailability.unavailable('not installed');
  }

  @override
  Future<String?> findRepoRoot(
    String directory, {
    GitCancelToken? cancel,
  }) async {
    return root;
  }

  @override
  Future<GitRepoInfo?> repoInfo(String root, {GitCancelToken? cancel}) async {
    return GitRepoInfo(
      root: root,
      branch: 'main',
      isDetached: false,
      hasCommits: hasCommits,
      upstream: upstream,
      ahead: ahead,
      behind: 0,
      remotes: remotes,
    );
  }

  @override
  Future<List<GitChange>> status(String root, {GitCancelToken? cancel}) async {
    statusCalls++;
    return changes;
  }

  /// The panel fetches once when it opens; nothing network-shaped may run here.
  int fetchCalls = 0;

  @override
  Future<GitResult> fetch(
    String root, {
    GitCancelToken? cancel,
    Duration timeout = GitService.fetchTimeout,
  }) async {
    fetchCalls++;
    return const GitResult(0, '', '', false, false);
  }

  @override
  Future<GitResult> stage(
    String root,
    List<String> paths, {
    GitCancelToken? cancel,
  }) async {
    stagedPaths.addAll(paths);
    return stageResult;
  }

  @override
  Future<GitResult> unstage(
    String root,
    List<String> paths, {
    required bool hasCommits,
    GitCancelToken? cancel,
  }) async {
    unstagedPaths.addAll(paths);
    lastUnstageHasCommits = hasCommits;
    return unstageResult;
  }

  @override
  Future<GitResult> commit(
    String root,
    String message, {
    GitCancelToken? cancel,
    Duration timeout = GitService.commitTimeout,
  }) async {
    commitMessages.add(message);
    if (cancel != null) commitCancelTokens.add(cancel);
    if (holdCommit) {
      final completer = Completer<GitResult>();
      cancel?.addListener(
        () => completer.complete(
          const GitResult(-1, '', 'Cancelled', false, true),
        ),
      );
      return completer.future;
    }
    return commitResult;
  }

  @override
  Future<GitResult> push(
    String root, {
    required String remote,
    required String branch,
    bool setUpstream = false,
    GitCancelToken? cancel,
    Duration timeout = GitService.pushTimeout,
  }) async {
    pushCalls.add((remote: remote, branch: branch, setUpstream: setUpstream));
    if (cancel != null) pushCancelTokens.add(cancel);
    if (holdPush) {
      final completer = Completer<GitResult>();
      cancel?.addListener(
        () => completer.complete(
          const GitResult(-1, '', 'Cancelled', false, true),
        ),
      );
      return completer.future;
    }
    return pushResult;
  }

  @override
  Future<String?> configValue(
    String root,
    String key, {
    GitCancelToken? cancel,
  }) async {
    if (key == 'user.name') return identityName;
    if (key == 'user.email') return identityEmail;
    return null;
  }

  @override
  Future<GitResult> setLocalConfig(
    String root,
    String key,
    String value, {
    GitCancelToken? cancel,
  }) async {
    localConfigKeys.add(key);
    localConfigValues.add(value);
    return const GitResult(0, '', '', false, false);
  }

  @override
  Future<String?> headShortSha(String root, {GitCancelToken? cancel}) async {
    return shortSha;
  }
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 800, height: 400, child: child)),
  );
}

void main() {
  testWidgets(
    'displays "Git is not installed" empty state when Git is unavailable',
    (tester) async {
      final service = _FakeGitService(available: false);
      final controller = GitController(
        service: service,
        debounce: Duration.zero,
      );
      controller.setExplorerFolder('/repo');
      await controller.refreshNow();

      await tester.pumpWidget(
        _wrap(
          SourceControlPanel(
            gitController: controller,
            dartRunnerService: DartRunnerService(),
            onOpenFile: (_) {},
          ),
        ),
      );

      expect(
        find.byKey(const Key('empty-state-git-not-installed')),
        findsOneWidget,
      );
      expect(find.text('Git is not installed'), findsOneWidget);
    },
  );

  testWidgets('displays "No folder open" empty state when no folder is set', (
    tester,
  ) async {
    final service = _FakeGitService();
    final controller = GitController(service: service, debounce: Duration.zero);
    await controller.refreshNow();

    await tester.pumpWidget(
      _wrap(
        SourceControlPanel(
          gitController: controller,
          dartRunnerService: DartRunnerService(),
          onOpenFile: (_) {},
        ),
      ),
    );

    expect(find.byKey(const Key('empty-state-no-folder')), findsOneWidget);
    expect(find.text('No folder open'), findsOneWidget);
  });

  testWidgets(
    'displays "Not a Git repository" empty state when folder is not a repo',
    (tester) async {
      final service = _FakeGitService(root: null);
      final controller = GitController(
        service: service,
        debounce: Duration.zero,
      );
      controller.setExplorerFolder('/plain_folder');
      await controller.refreshNow();

      await tester.pumpWidget(
        _wrap(
          SourceControlPanel(
            gitController: controller,
            dartRunnerService: DartRunnerService(),
            onOpenFile: (_) {},
          ),
        ),
      );

      expect(find.byKey(const Key('empty-state-not-repo')), findsOneWidget);
      expect(find.text('Not a Git repository'), findsOneWidget);
    },
  );

  testWidgets('the header survives a very narrow panel without overflowing', (
    tester,
  ) async {
    final service = _FakeGitService(
      changes: [
        GitChange(
          path: 'a_very_long_file_name_that_will_not_fit.txt',
          indexStatus: 'M',
          worktreeStatus: ' ',
        ),
      ],
    );
    final controller = GitController(service: service, debounce: Duration.zero);
    controller.setExplorerFolder('/repo');
    await controller.refreshNow();

    // Narrower than the branch label plus the three header buttons.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 300,
            child: SourceControlPanel(
              gitController: controller,
              dartRunnerService: DartRunnerService(),
              onOpenFile: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('git-branch-header')), findsOneWidget);
    expect(find.byKey(const Key('git-stage-all-button')), findsOneWidget);
  });

  testWidgets('displays "No changes" empty state when working tree is clean', (
    tester,
  ) async {
    final service = _FakeGitService(changes: const []);
    final controller = GitController(service: service, debounce: Duration.zero);
    controller.setExplorerFolder('/repo');
    await controller.refreshNow();

    await tester.pumpWidget(
      _wrap(
        SourceControlPanel(
          gitController: controller,
          dartRunnerService: DartRunnerService(),
          onOpenFile: (_) {},
        ),
      ),
    );

    expect(find.byKey(const Key('empty-state-no-changes')), findsOneWidget);
    expect(find.text('No changes'), findsOneWidget);
    expect(find.byKey(const Key('git-branch-header')), findsOneWidget);
  });

  testWidgets(
    'renders Staged Changes and Changes sections with buttons and status letters',
    (tester) async {
      final service = _FakeGitService(
        changes: [
          GitChange(path: 'staged.txt', indexStatus: 'M', worktreeStatus: ' '),
          GitChange(
            path: 'unstaged.txt',
            indexStatus: ' ',
            worktreeStatus: 'M',
          ),
          GitChange(
            path: 'untracked.txt',
            indexStatus: '?',
            worktreeStatus: '?',
          ),
          GitChange(
            path: 'conflicted.txt',
            indexStatus: 'U',
            worktreeStatus: 'U',
          ),
        ],
      );
      final controller = GitController(
        service: service,
        debounce: Duration.zero,
      );
      controller.setExplorerFolder('/repo');
      await controller.refreshNow();

      await tester.pumpWidget(
        _wrap(
          SourceControlPanel(
            gitController: controller,
            dartRunnerService: DartRunnerService(),
            onOpenFile: (_) {},
          ),
        ),
      );

      expect(find.byKey(const Key('staged-changes-header')), findsOneWidget);
      expect(find.byKey(const Key('changes-header')), findsOneWidget);

      expect(find.text('staged.txt'), findsOneWidget);
      expect(find.text('unstaged.txt'), findsOneWidget);
      expect(find.text('untracked.txt'), findsOneWidget);
      expect(find.text('conflicted.txt'), findsOneWidget);

      // Status letters: 'M', 'U', '!'
      expect(find.text('M'), findsNWidgets(2)); // staged.txt & unstaged.txt
      expect(find.text('U'), findsOneWidget); // untracked.txt
      expect(find.text('!'), findsOneWidget); // conflicted.txt

      // Stage / Unstage individual buttons
      await tester.tap(find.byKey(const Key('git-stage-button-unstaged.txt')));
      await tester.pumpAndSettle();
      expect(service.stagedPaths, contains('unstaged.txt'));

      await tester.tap(find.byKey(const Key('git-unstage-button-staged.txt')));
      await tester.pumpAndSettle();
      expect(service.unstagedPaths, contains('staged.txt'));
    },
  );

  testWidgets(
    'Stage All and Unstage All buttons stage/unstage expected paths',
    (tester) async {
      final service = _FakeGitService(
        changes: [
          GitChange(path: 'staged.txt', indexStatus: 'M', worktreeStatus: ' '),
          GitChange(
            path: 'unstaged.txt',
            indexStatus: ' ',
            worktreeStatus: 'M',
          ),
          GitChange(
            path: 'untracked.txt',
            indexStatus: '?',
            worktreeStatus: '?',
          ),
          GitChange(
            path: 'conflicted.txt',
            indexStatus: 'U',
            worktreeStatus: 'U',
          ),
        ],
      );
      final controller = GitController(
        service: service,
        debounce: Duration.zero,
      );
      controller.setExplorerFolder('/repo');
      await controller.refreshNow();

      await tester.pumpWidget(
        _wrap(
          SourceControlPanel(
            gitController: controller,
            dartRunnerService: DartRunnerService(),
            onOpenFile: (_) {},
          ),
        ),
      );

      // Stage All
      await tester.tap(find.byKey(const Key('git-stage-all-button')));
      await tester.pumpAndSettle();
      expect(
        service.stagedPaths,
        containsAll(['unstaged.txt', 'untracked.txt']),
      );
      expect(service.stagedPaths, isNot(contains('conflicted.txt')));

      // Unstage All
      await tester.tap(find.byKey(const Key('git-unstage-all-button')));
      await tester.pumpAndSettle();
      expect(service.unstagedPaths, contains('staged.txt'));
    },
  );

  testWidgets('conflicted row cannot be staged', (tester) async {
    final service = _FakeGitService(
      changes: [
        GitChange(
          path: 'conflicted.txt',
          indexStatus: 'U',
          worktreeStatus: 'U',
        ),
      ],
    );
    final controller = GitController(service: service, debounce: Duration.zero);
    controller.setExplorerFolder('/repo');
    await controller.refreshNow();

    await tester.pumpWidget(
      _wrap(
        SourceControlPanel(
          gitController: controller,
          dartRunnerService: DartRunnerService(),
          onOpenFile: (_) {},
        ),
      ),
    );

    final buttonFinder = find.byKey(
      const Key('git-stage-button-conflicted.txt'),
    );
    expect(buttonFinder, findsOneWidget);

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: buttonFinder, matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, 'Resolve conflicts in a terminal');

    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();
    expect(service.stagedPaths, isEmpty);
  });

  group('double-click opens the file', () {
    late Directory tempDir;
    late File stagedFile;

    // Real filesystem work must happen outside `testWidgets`: inside the fake
    // async zone a genuine `dart:io` future never completes.
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cce_sc_test_');
      stagedFile = File('${tempDir.path}/staged.txt');
      await stagedFile.writeAsString('hello');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    testWidgets(
      'double-clicking a row calls onOpenFile when file exists on disk',
      (tester) async {
        final service = _FakeGitService(
          root: tempDir.path,
          changes: [
            GitChange(
              path: 'staged.txt',
              indexStatus: 'M',
              worktreeStatus: ' ',
            ),
          ],
        );
        final controller = GitController(
          service: service,
          debounce: Duration.zero,
        );
        controller.setExplorerFolder(tempDir.path);
        await controller.refreshNow();

        String? openedPath;
        await tester.pumpWidget(
          _wrap(
            SourceControlPanel(
              gitController: controller,
              dartRunnerService: DartRunnerService(),
              onOpenFile: (path) => openedPath = path,
            ),
          ),
        );

        final pathFinder = find.text('staged.txt');
        expect(pathFinder, findsOneWidget);

        await tester.tap(pathFinder);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(pathFinder);
        await tester.pumpAndSettle();

        expect(openedPath, equals(stagedFile.path));
      },
    );
  });

  testWidgets('a failing stage prints the real git message to the Console and one line '
      'in the panel', (tester) async {
    final service = _FakeGitService(
      changes: [
        GitChange(path: 'locked.txt', indexStatus: ' ', worktreeStatus: 'M'),
      ],
      stageResult: const GitResult(
        1,
        '',
        "error: unable to index file 'locked.txt'\nfatal: adding files failed",
        false,
        false,
      ),
    );
    final controller = GitController(service: service, debounce: Duration.zero);
    controller.setExplorerFolder('/repo');
    await controller.refreshNow();

    final runner = DartRunnerService();
    addTearDown(runner.dispose);
    final console = <String>[];
    final subscription = runner.outputStream.listen(console.add);
    addTearDown(subscription.cancel);

    await tester.pumpWidget(
      _wrap(
        SourceControlPanel(
          gitController: controller,
          dartRunnerService: runner,
          onOpenFile: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('git-stage-button-locked.txt')));
    await tester.pumpAndSettle();

    // The panel shows a single line...
    final banner = tester.widget<Text>(
      find.byKey(const Key('git-error-banner')),
    );
    expect(banner.data, "error: unable to index file 'locked.txt'");
    expect(banner.data, isNot(contains('fatal:')));

    // ...while the Console gets the whole message.
    expect(console.join('\n'), contains('fatal: adding files failed'));
  });

  testWidgets('unstage tells the service whether the branch is unborn', (
    tester,
  ) async {
    final service = _FakeGitService(
      hasCommits: false,
      changes: [
        GitChange(path: 'first.txt', indexStatus: 'A', worktreeStatus: ' '),
      ],
    );
    final controller = GitController(service: service, debounce: Duration.zero);
    controller.setExplorerFolder('/repo');
    await controller.refreshNow();

    await tester.pumpWidget(
      _wrap(
        SourceControlPanel(
          gitController: controller,
          dartRunnerService: DartRunnerService(),
          onOpenFile: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('git-unstage-button-first.txt')));
    await tester.pumpAndSettle();

    expect(service.unstagedPaths, contains('first.txt'));
    expect(
      service.lastUnstageHasCommits,
      isFalse,
      reason: 'an unborn branch must take the git rm --cached path',
    );
  });

  testWidgets(
    'a failing unstage is reported too, and leaves the buttons usable',
    (tester) async {
      final service = _FakeGitService(
        changes: [
          GitChange(path: 'staged.txt', indexStatus: 'M', worktreeStatus: ' '),
        ],
        unstageResult: const GitResult(
          1,
          '',
          'fatal: could not resolve HEAD',
          false,
          false,
        ),
      );
      final controller = GitController(
        service: service,
        debounce: Duration.zero,
      );
      controller.setExplorerFolder('/repo');
      await controller.refreshNow();

      await tester.pumpWidget(
        _wrap(
          SourceControlPanel(
            gitController: controller,
            dartRunnerService: DartRunnerService(),
            onOpenFile: (_) {},
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('git-unstage-button-staged.txt')));
      await tester.pumpAndSettle();

      final banner = tester.widget<Text>(
        find.byKey(const Key('git-error-banner')),
      );
      expect(banner.data, 'fatal: could not resolve HEAD');

      // The failure must not leave the panel stuck in its busy state: the
      // "Unstage All" action is enabled again because the staged row is still
      // there and no operation is in flight.
      final button = tester.widget<RetroButton>(
        find.byKey(const Key('git-unstage-all-button')),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  group('commit area (Git G4)', () {
    final stagedFile = GitChange(
      path: 'staged.txt',
      indexStatus: 'M',
      worktreeStatus: ' ',
    );

    Future<GitController> pumpPanel(
      WidgetTester tester,
      _FakeGitService service, {
      DartRunnerService? runner,
    }) async {
      final controller = GitController(
        service: service,
        debounce: Duration.zero,
      );
      controller.setExplorerFolder('/repo');
      await controller.refreshNow();
      await tester.pumpWidget(
        _wrap(
          SourceControlPanel(
            gitController: controller,
            dartRunnerService: runner ?? DartRunnerService(),
            onOpenFile: (_) {},
          ),
        ),
      );
      return controller;
    }

    RetroButton commitButton(WidgetTester tester) =>
        tester.widget<RetroButton>(find.byKey(const Key('git-commit-button')));

    testWidgets('the button is enabled only with staged files and a message', (
      tester,
    ) async {
      // Nothing staged + message: disabled.
      final unstagedOnly = _FakeGitService(
        changes: [
          GitChange(
            path: 'unstaged.txt',
            indexStatus: ' ',
            worktreeStatus: 'M',
          ),
        ],
      );
      await pumpPanel(tester, unstagedOnly);
      await tester.enterText(
        find.byKey(const Key('git-commit-message-field')),
        'a message',
      );
      await tester.pump();
      expect(commitButton(tester).onPressed, isNull);

      // Staged file + blank message: disabled.
      final blankMessage = _FakeGitService(changes: [stagedFile]);
      await pumpPanel(tester, blankMessage);
      await tester.enterText(
        find.byKey(const Key('git-commit-message-field')),
        '   \n  ',
      );
      await tester.pump();
      expect(commitButton(tester).onPressed, isNull);

      // Staged file + a real message: enabled.
      final ready = _FakeGitService(changes: [stagedFile]);
      await pumpPanel(tester, ready);
      await tester.enterText(
        find.byKey(const Key('git-commit-message-field')),
        'a message',
      );
      await tester.pump();
      expect(commitButton(tester).onPressed, isNotNull);
    });

    testWidgets('a successful commit clears the box, shows the sha and '
        'refreshes', (tester) async {
      final service = _FakeGitService(changes: [stagedFile]);
      await pumpPanel(tester, service);

      await tester.enterText(
        find.byKey(const Key('git-commit-message-field')),
        'the subject\n\nthe body',
      );
      await tester.pump();
      final statusCallsBefore = service.statusCalls;

      await tester.tap(find.byKey(const Key('git-commit-button')));
      await tester.pumpAndSettle();

      expect(service.commitMessages, ['the subject\n\nthe body']);
      expect(
        tester.widget<Text>(find.byKey(const Key('git-success-line'))).data,
        'Committed abc1234',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('git-commit-message-field')),
            )
            .controller!
            .text,
        isEmpty,
        reason: 'the message box is cleared after a successful commit',
      );
      expect(
        service.statusCalls,
        greaterThan(statusCallsBefore),
        reason: 'the panel must refresh the status after committing',
      );
    });

    testWidgets('a missing identity shows the inline form and saves it '
        'repository-locally before committing', (tester) async {
      final service = _FakeGitService(changes: [stagedFile])
        ..identityName = null
        ..identityEmail = null;
      await pumpPanel(tester, service);

      await tester.enterText(
        find.byKey(const Key('git-commit-message-field')),
        'a message',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('git-commit-button')));
      await tester.pumpAndSettle();

      // The form appears with the "stored only in this repository"
      // explanation, and no commit was attempted yet.
      expect(find.byKey(const Key('git-identity-form')), findsOneWidget);
      expect(
        find.textContaining('stored only in this repository'),
        findsOneWidget,
      );
      expect(service.commitMessages, isEmpty);

      await tester.enterText(
        find.byKey(const Key('git-identity-name')),
        'Reza Test',
      );
      await tester.enterText(
        find.byKey(const Key('git-identity-email')),
        'reza@example.com',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('git-identity-save-button')));
      await tester.pumpAndSettle();

      // Saved repository-locally (user.name / user.email only), then the
      // commit ran.
      expect(service.localConfigKeys, ['user.name', 'user.email']);
      expect(service.localConfigValues, ['Reza Test', 'reza@example.com']);
      expect(service.commitMessages, ['a message']);
      expect(find.byKey(const Key('git-identity-form')), findsNothing);
    });

    testWidgets('a failing pre-commit hook keeps the message, shows one line '
        'and sends the full output to the Console', (tester) async {
      final service = _FakeGitService(changes: [stagedFile])
        ..commitResult = const GitResult(
          1,
          '',
          'hook says: nope\nmore detail\n',
          false,
          false,
        );
      final runner = DartRunnerService();
      addTearDown(runner.dispose);
      final console = <String>[];
      final subscription = runner.outputStream.listen(console.add);
      addTearDown(subscription.cancel);

      await pumpPanel(tester, service, runner: runner);
      await tester.enterText(
        find.byKey(const Key('git-commit-message-field')),
        'kept message',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('git-commit-button')));
      await tester.pumpAndSettle();

      final banner = tester.widget<Text>(
        find.byKey(const Key('git-error-banner')),
      );
      expect(banner.data, 'hook says: nope');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('git-commit-message-field')),
            )
            .controller!
            .text,
        'kept message',
        reason: 'a failed commit must not lose the typed message',
      );
      // The real git output is in the Console.
      expect(console, contains('hook says: nope'));
      expect(console, contains('more detail'));
      // The staged file is still listed (the fake status is unchanged).
      expect(find.text('staged.txt'), findsOneWidget);
      // The buttons are usable again.
      expect(commitButton(tester).onPressed, isNotNull);
    });

    testWidgets('the Cancel button kills a running commit', (tester) async {
      final service = _FakeGitService(changes: [stagedFile])..holdCommit = true;
      await pumpPanel(tester, service);

      await tester.enterText(
        find.byKey(const Key('git-commit-message-field')),
        'slow hook\n',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('git-commit-button')));
      await tester.pump();

      // While running: the commit button is disabled and a Cancel button
      // appeared.
      expect(commitButton(tester).onPressed, isNull);
      expect(find.byKey(const Key('git-commit-cancel-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('git-commit-cancel-button')));
      await tester.pumpAndSettle();

      final banner = tester.widget<Text>(
        find.byKey(const Key('git-error-banner')),
      );
      expect(banner.data, 'Commit cancelled.');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('git-commit-message-field')),
            )
            .controller!
            .text,
        'slow hook\n',
        reason: 'a cancelled commit must not lose the typed message',
      );
      expect(find.byKey(const Key('git-commit-cancel-button')), findsNothing);
      expect(commitButton(tester).onPressed, isNotNull);
    });

    testWidgets('Cmd+Enter inside the message box commits', (tester) async {
      final service = _FakeGitService(changes: [stagedFile]);
      await pumpPanel(tester, service);

      await tester.enterText(
        find.byKey(const Key('git-commit-message-field')),
        'from the keyboard\n',
      );
      await tester.pump();

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.enter,
        platform: 'macos',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter, platform: 'macos');
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.pumpAndSettle();

      expect(service.commitMessages, ['from the keyboard\n']);
    });

    testWidgets('a subject longer than 72 characters shows a soft, '
        'non-blocking hint', (tester) async {
      final service = _FakeGitService(changes: [stagedFile]);
      await pumpPanel(tester, service);

      final longSubject = 's' * 73;
      await tester.enterText(
        find.byKey(const Key('git-commit-message-field')),
        '$longSubject\nbody',
      );
      await tester.pump();

      expect(find.byKey(const Key('git-commit-subject-hint')), findsOneWidget);
      // The hint does not block: the button stays enabled.
      expect(commitButton(tester).onPressed, isNotNull);

      // 72 characters exactly: no hint.
      await tester.enterText(
        find.byKey(const Key('git-commit-message-field')),
        's' * 72,
      );
      await tester.pump();
      expect(find.byKey(const Key('git-commit-subject-hint')), findsNothing);
    });
  });

  group('push (Git G5)', () {
    const origin = GitRemote('origin', 'https://github.com/user/repo.git');
    const credentialed = GitRemote(
      'origin',
      'https://user:secret@github.com/user/repo.git',
    );

    Future<GitController> pumpPanel(
      WidgetTester tester,
      _FakeGitService service, {
      DartRunnerService? runner,
    }) async {
      final controller = GitController(
        service: service,
        debounce: Duration.zero,
      );
      controller.setExplorerFolder('/repo');
      await controller.refreshNow();
      await tester.pumpWidget(
        _wrap(
          SourceControlPanel(
            gitController: controller,
            dartRunnerService: runner ?? DartRunnerService(),
            onOpenFile: (_) {},
          ),
        ),
      );
      return controller;
    }

    RetroButton pushButton(WidgetTester tester) =>
        tester.widget<RetroButton>(find.byKey(const Key('git-push-button')));

    testWidgets('the label shows the ahead count', (tester) async {
      final service = _FakeGitService(
        upstream: 'origin/main',
        ahead: 2,
        remotes: [origin],
      );
      await pumpPanel(tester, service);

      expect(find.text('Push ↑2'), findsOneWidget);
      // Ahead of the upstream: enabled.
      expect(pushButton(tester).onPressed, isNotNull);
    });

    testWidgets('the button is disabled when there is nothing to push and an '
        'upstream exists', (tester) async {
      final service = _FakeGitService(
        upstream: 'origin/main',
        ahead: 0,
        remotes: [origin],
      );
      await pumpPanel(tester, service);

      expect(find.text('Push'), findsOneWidget);
      expect(pushButton(tester).onPressed, isNull);
    });

    testWidgets('a branch with no upstream can push even with nothing ahead', (
      tester,
    ) async {
      final service = _FakeGitService(remotes: [origin]);
      await pumpPanel(tester, service);

      expect(pushButton(tester).onPressed, isNotNull);
    });

    testWidgets('no remote disables the button and carries the hint tooltip', (
      tester,
    ) async {
      final service = _FakeGitService(remotes: const <GitRemote>[]);
      await pumpPanel(tester, service);

      final button = pushButton(tester);
      expect(button.onPressed, isNull);

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const Key('git-push-button')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, SourceControlPanel.noRemoteHint);
      expect(service.pushCalls, isEmpty, reason: 'no remote: nothing may run');
    });

    testWidgets('the confirmation dialog shows the stripped URL, the branch '
        'line and the commit count; confirming pushes', (tester) async {
      final service = _FakeGitService(
        upstream: 'origin/main',
        ahead: 2,
        remotes: [credentialed],
      );
      final runner = DartRunnerService();
      addTearDown(runner.dispose);
      final console = <String>[];
      final subscription = runner.outputStream.listen(console.add);
      addTearDown(subscription.cancel);

      await pumpPanel(tester, service, runner: runner);

      await tester.tap(find.byKey(const Key('git-push-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('git-push-dialog')), findsOneWidget);
      final url = tester.widget<Text>(
        find.byKey(const Key('git-push-dialog-url')),
      );
      expect(url.data, 'https://github.com/user/repo.git');
      expect(find.byKey(const Key('git-push-dialog-branch')), findsOneWidget);
      expect(find.text('2 commits will be pushed.'), findsOneWidget);
      expect(
        find.byKey(const Key('git-push-dialog-will-run')),
        findsNothing,
        reason: 'the -u form is only announced for a branch without upstream',
      );

      // Nothing was run while the dialog was up.
      expect(service.pushCalls, isEmpty);

      await tester.tap(find.byKey(const Key('git-push-dialog-confirm')));
      await tester.pumpAndSettle();

      expect(service.pushCalls, hasLength(1));
      expect(service.pushCalls.single.remote, 'origin');
      expect(service.pushCalls.single.setUpstream, isFalse);
      expect(find.text('Pushed'), findsOneWidget);
      expect(find.byKey(const Key('git-success-line')), findsOneWidget);
      expect(
        service.statusCalls,
        greaterThan(0),
        reason: 'the status must refresh after the push',
      );
      expect(console, contains('[Git push]'));
      // The dialog is gone and the button is usable again.
      expect(find.byKey(const Key('git-push-dialog')), findsNothing);
      expect(pushButton(tester).onPressed, isNotNull);
    });

    testWidgets('a branch with no upstream announces the exact -u command '
        'and pushes with -u', (tester) async {
      final service = _FakeGitService(remotes: [origin]);
      await pumpPanel(tester, service);

      await tester.tap(find.byKey(const Key('git-push-button')));
      await tester.pumpAndSettle();

      expect(find.text('will run: git push -u origin main'), findsOneWidget);
      expect(find.byKey(const Key('git-push-dialog-count')), findsNothing);

      await tester.tap(find.byKey(const Key('git-push-dialog-confirm')));
      await tester.pumpAndSettle();

      expect(service.pushCalls, hasLength(1));
      expect(service.pushCalls.single.setUpstream, isTrue);
      expect(service.pushCalls.single.remote, 'origin');
      expect(find.text('Pushed'), findsOneWidget);
    });

    testWidgets('cancelling the dialog runs nothing', (tester) async {
      final service = _FakeGitService(
        upstream: 'origin/main',
        ahead: 1,
        remotes: [origin],
      );
      await pumpPanel(tester, service);

      await tester.tap(find.byKey(const Key('git-push-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('git-push-dialog-cancel')));
      await tester.pumpAndSettle();

      expect(service.pushCalls, isEmpty);
      expect(find.byKey(const Key('git-push-dialog')), findsNothing);
    });

    testWidgets('a rejected push shows the Pull hint and the buttons come '
        'back', (tester) async {
      final service =
          _FakeGitService(upstream: 'origin/main', ahead: 1, remotes: [origin])
            ..pushResult = const GitResult(
              1,
              '',
              "To github.com:user/repo.git\n"
                  " ! [rejected]        main -> main (fetch first)\n"
                  "error: failed to push some refs to 'github.com:user/repo.git'\n",
              false,
              false,
            );
      await pumpPanel(tester, service);

      await tester.tap(find.byKey(const Key('git-push-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('git-push-dialog-confirm')));
      await tester.pumpAndSettle();

      final banner = tester.widget<Text>(
        find.byKey(const Key('git-error-banner')),
      );
      expect(banner.data, 'The remote has new commits. Pull first');
      expect(pushButton(tester).onPressed, isNotNull);
      expect(find.byKey(const Key('git-push-cancel-button')), findsNothing);
    });

    testWidgets('the Cancel button kills a running push', (tester) async {
      final service = _FakeGitService(remotes: [origin])..holdPush = true;
      await pumpPanel(tester, service);

      await tester.tap(find.byKey(const Key('git-push-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('git-push-dialog-confirm')));
      await tester.pump();

      // While running: the push button is disabled and a Cancel button
      // appeared.
      expect(pushButton(tester).onPressed, isNull);
      expect(find.byKey(const Key('git-push-cancel-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('git-push-cancel-button')));
      await tester.pumpAndSettle();

      final banner = tester.widget<Text>(
        find.byKey(const Key('git-error-banner')),
      );
      expect(banner.data, 'Push cancelled.');
      expect(find.byKey(const Key('git-push-cancel-button')), findsNothing);
      expect(pushButton(tester).onPressed, isNotNull);
    });
  });
}
