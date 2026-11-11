import 'dart:async';

import 'package:classic_code_editor/models/git_models.dart';
import 'package:classic_code_editor/services/git_controller.dart';
import 'package:classic_code_editor/services/git_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [GitService] whose every read is replaced by a canned answer.
///
/// The controller never touches a process here: each of the four methods it
/// calls records the invocation and returns a value the test controls, so the
/// debounce, the single-flight collapse and the directory resolution can all be
/// observed without a repository on disk.
class _FakeGitService extends GitService {
  _FakeGitService({
    this.available = true,
    this.root = '/repo',
    this.info,
    this.changes = const <GitChange>[],
    this.rootGate,
  });

  bool available;
  String? root;
  GitRepoInfo? info;
  List<GitChange> changes;

  /// When set, [findRepoRoot] waits for it before answering.
  Completer<void>? rootGate;

  final List<String> calls = <String>[];
  final List<String> rootsQueried = <String>[];

  @override
  Future<GitAvailability> gitAvailability({GitCancelToken? cancel}) async {
    calls.add('availability');
    return available
        ? const GitAvailability.available('/fake/bin/git')
        : const GitAvailability.unavailable('not installed');
  }

  @override
  Future<String?> findRepoRoot(
    String directory, {
    GitCancelToken? cancel,
  }) async {
    calls.add('findRepoRoot');
    rootsQueried.add(directory);
    final gate = rootGate;
    if (gate != null) await gate.future;
    return root;
  }

  @override
  Future<GitRepoInfo?> repoInfo(String root, {GitCancelToken? cancel}) async {
    calls.add('repoInfo');
    return info;
  }

  @override
  Future<List<GitChange>> status(String root, {GitCancelToken? cancel}) async {
    calls.add('status');
    return changes;
  }

  @override
  Future<GitResult> fetch(
    String root, {
    GitCancelToken? cancel,
    Duration timeout = GitService.fetchTimeout,
  }) async {
    calls.add('fetch');
    return fetchResult;
  }

  /// What the fake `git fetch` answers; a failure must still refresh.
  GitResult fetchResult = const GitResult(0, '', '', false, false);

  int countOf(String call) => calls.where((entry) => entry == call).length;
}

GitRepoInfo _info({
  String branch = 'main',
  bool isDetached = false,
  String? upstream = 'origin/main',
  int ahead = 0,
  int behind = 0,
  List<GitRemote> remotes = const <GitRemote>[],
}) {
  return GitRepoInfo(
    root: '/repo',
    branch: branch,
    isDetached: isDetached,
    hasCommits: true,
    upstream: upstream,
    ahead: ahead,
    behind: behind,
    remotes: remotes,
  );
}

GitChange _change(String path) =>
    GitChange(path: path, indexStatus: ' ', worktreeStatus: 'M');

void main() {
  group('refresh debounce', () {
    test('runs no command before 400 ms, then exactly one refresh', () async {
      final service = _FakeGitService(info: _info());
      final controller = GitController(service: service);

      controller.setExplorerFolder('/repo');
      // Arming the timer must not start a command.
      expect(service.calls, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(service.calls, isEmpty, reason: 'still inside the debounce');

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(service.countOf('findRepoRoot'), 1);
      expect(service.rootsQueried, ['/repo']);

      controller.dispose();
    });

    test('a burst of triggers collapses into a single refresh', () async {
      final service = _FakeGitService(info: _info());
      final controller = GitController(service: service);

      controller.setExplorerFolder('/repo');
      controller.refresh();
      controller.refresh();
      controller.refreshForExternalChange();

      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(service.countOf('findRepoRoot'), 1);

      controller.dispose();
    });

    test('a zero debounce runs as soon as the loop turns', () async {
      final service = _FakeGitService(info: _info());
      final controller = GitController(
        service: service,
        debounce: Duration.zero,
      );

      controller.setExplorerFolder('/repo');
      expect(service.calls, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(service.countOf('findRepoRoot'), 1);

      controller.dispose();
    });
  });

  group('single flight', () {
    test(
      'a refresh during a refresh runs exactly one more time after',
      () async {
        final gate = Completer<void>();
        final service = _FakeGitService(info: _info(), rootGate: gate);
        final controller = GitController(service: service);

        // Arm the debounce, then start the run at once (refreshNow cancels it).
        controller.setExplorerFolder('/repo');
        unawaited(controller.refreshNow());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(service.countOf('findRepoRoot'), 1);

        // Two more requests arrive while it is still running.
        unawaited(controller.refreshNow());
        unawaited(controller.refreshNow());

        // Unblocking the first run must trigger exactly one follow-up.
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(service.countOf('findRepoRoot'), 2);

        controller.dispose();
      },
    );
  });

  group('no repository', () {
    test('runs no command when neither a folder nor a file is known', () async {
      final service = _FakeGitService(info: _info());
      final controller = GitController(service: service);

      await controller.refreshNow();

      expect(service.calls, isEmpty);
      expect(controller.hasRepo, isFalse);
      expect(controller.statusLabel, isNull);

      controller.dispose();
    });

    test('a non-repository directory yields no segment', () async {
      final service = _FakeGitService(root: null, info: _info());
      final controller = GitController(service: service);

      controller.setExplorerFolder('/not-a-repo');
      await controller.refreshNow();

      expect(service.calls, contains('findRepoRoot'));
      expect(service.calls, isNot(contains('repoInfo')));
      expect(controller.hasRepo, isFalse);
      expect(controller.statusLabel, isNull);

      controller.dispose();
    });

    test('an unavailable git stops before looking for a root', () async {
      final service = _FakeGitService(available: false, info: _info());
      final controller = GitController(service: service);

      controller.setExplorerFolder('/repo');
      await controller.refreshNow();

      expect(controller.isAvailable, isFalse);
      expect(controller.statusLabel, isNull);
      expect(service.calls, isNot(contains('findRepoRoot')));

      controller.dispose();
    });
  });

  group('directory resolution order', () {
    test('the explorer folder wins over the active file', () async {
      final service = _FakeGitService(info: _info());
      final controller = GitController(service: service);

      controller.setActiveFilePath('/project/lib/main.dart');
      controller.setExplorerFolder('/project');
      await controller.refreshNow();

      expect(service.rootsQueried.last, '/project');

      controller.dispose();
    });

    test('falls back to the active file directory', () async {
      final service = _FakeGitService(info: _info());
      final controller = GitController(service: service);

      controller.setActiveFilePath('/project/lib/deep/main.dart');
      await controller.refreshNow();

      expect(service.rootsQueried.last, '/project/lib/deep');

      controller.dispose();
    });

    test(
      'closing the folder falls back to the file, then to nothing',
      () async {
        final service = _FakeGitService(info: _info());
        final controller = GitController(service: service);

        controller.setActiveFilePath('/project/lib/main.dart');
        controller.setExplorerFolder('/project');
        await controller.refreshNow();
        expect(service.rootsQueried.last, '/project');

        controller.setExplorerFolder(null);
        await controller.refreshNow();
        expect(service.rootsQueried.last, '/project/lib');

        // No file-backed tab any more: the segment goes away, nothing runs.
        final before = service.calls.length;
        controller.setActiveFilePath(null);
        await controller.refreshNow();
        expect(service.calls.length, before);
        expect(controller.statusLabel, isNull);

        controller.dispose();
      },
    );
  });

  group('status label', () {
    test('branch, count and arrows, with a credential-free tooltip', () async {
      final service = _FakeGitService(
        info: _info(
          ahead: 2,
          behind: 1,
          remotes: const <GitRemote>[
            GitRemote('origin', 'https://example.com/repo.git'),
          ],
        ),
        changes: <GitChange>[
          _change('a.txt'),
          _change('b.txt'),
          _change('c.txt'),
        ],
      );
      final controller = GitController(service: service);

      controller.setExplorerFolder('/repo');
      await controller.refreshNow();

      expect(controller.statusLabel, '⎇ main ● 3 ↑2 ↓1');
      expect(controller.tooltipText, contains('/repo'));
      expect(controller.tooltipText, contains('upstream: origin/main'));
      expect(
        controller.tooltipText,
        contains('origin: https://example.com/repo.git'),
      );

      controller.dispose();
    });

    test('a detached HEAD shows the short sha and no upstream', () async {
      final service = _FakeGitService(
        info: _info(branch: 'abc1234', isDetached: true, upstream: null),
      );
      final controller = GitController(service: service);

      controller.setExplorerFolder('/repo');
      await controller.refreshNow();

      expect(controller.statusLabel, '⎇ abc1234');
      expect(controller.tooltipText, contains('detached HEAD'));
      expect(controller.tooltipText, contains('upstream: no upstream'));

      controller.dispose();
    });

    test('a clean tree shows the branch only', () async {
      final service = _FakeGitService(info: _info(upstream: null));
      final controller = GitController(service: service);

      controller.setExplorerFolder('/repo');
      await controller.refreshNow();

      expect(controller.statusLabel, '⎇ main');

      controller.dispose();
    });

    test(
      'the label shows the pull distance once the remote is fetched',
      () async {
        final service = _FakeGitService(
          info: _info(
            remotes: const <GitRemote>[
              GitRemote('origin', 'https://e.com/r.git'),
            ],
          ),
        );
        final controller = GitController(service: service);

        controller.setExplorerFolder('/repo');
        await controller.refreshNow();
        // Nothing is behind yet — this is the state that kept Pull disabled.
        expect(controller.statusLabel, '⎇ main');

        service.info = _info(
          behind: 2,
          remotes: const <GitRemote>[
            GitRemote('origin', 'https://e.com/r.git'),
          ],
        );
        await controller.fetchNow();

        expect(controller.statusLabel, '⎇ main ↓2');
        expect(service.countOf('fetch'), equals(1));

        controller.dispose();
      },
    );
  });

  group('fetchNow', () {
    test('runs one fetch and refreshes afterwards', () async {
      final service = _FakeGitService(
        info: _info(
          behind: 1,
          remotes: const <GitRemote>[
            GitRemote('origin', 'https://e.com/r.git'),
          ],
        ),
      );
      final controller = GitController(service: service);

      controller.setExplorerFolder('/repo');
      await controller.refreshNow();
      final statusBefore = service.countOf('status');

      final result = await controller.fetchNow();

      expect(result, isNotNull);
      expect(result!.succeeded, isTrue);
      expect(service.countOf('fetch'), equals(1));
      expect(service.countOf('status'), greaterThan(statusBefore));

      controller.dispose();
    });

    test(
      'a failed fetch still refreshes, so a partial transfer shows',
      () async {
        final service = _FakeGitService(
          info: _info(
            remotes: const <GitRemote>[
              GitRemote('origin', 'https://e.com/r.git'),
            ],
          ),
        );
        service.fetchResult = const GitResult(
          1,
          '',
          'Could not resolve host',
          false,
          false,
        );
        final controller = GitController(service: service);

        controller.setExplorerFolder('/repo');
        await controller.refreshNow();
        final statusBefore = service.countOf('status');

        final result = await controller.fetchNow();

        expect(result!.succeeded, isFalse);
        expect(service.countOf('status'), greaterThan(statusBefore));

        controller.dispose();
      },
    );

    test('starts no process when there is no repository', () async {
      final service = _FakeGitService(root: null);
      final controller = GitController(service: service);

      final result = await controller.fetchNow();

      expect(result, isNull);
      expect(service.countOf('fetch'), equals(0));

      controller.dispose();
    });

    test('starts no process when the repository has no remote', () async {
      final service = _FakeGitService(info: _info());
      final controller = GitController(service: service);

      controller.setExplorerFolder('/repo');
      await controller.refreshNow();

      final result = await controller.fetchNow();

      expect(result, isNull);
      expect(service.countOf('fetch'), equals(0));

      controller.dispose();
    });

    test('starts no process after dispose', () async {
      final service = _FakeGitService(
        info: _info(
          remotes: const <GitRemote>[
            GitRemote('origin', 'https://e.com/r.git'),
          ],
        ),
      );
      final controller = GitController(service: service);
      controller.setExplorerFolder('/repo');
      await controller.refreshNow();

      controller.dispose();

      expect(await controller.fetchNow(), isNull);
      expect(service.countOf('fetch'), equals(0));
    });
  });
}
