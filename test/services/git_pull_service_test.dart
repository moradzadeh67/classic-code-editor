import 'dart:io';

import 'package:classic_code_editor/models/git_models.dart';
import 'package:classic_code_editor/services/git_controller.dart';
import 'package:classic_code_editor/services/git_service.dart';
import 'package:classic_code_editor/services/tool_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

bool _gitInstalled() {
  try {
    return Process.runSync('git', const <String>['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<Directory> _tempDir(String prefix) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // Cleaned up
    }
  });
  return directory;
}

Future<void> _git(Directory directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory.path,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}

/// A recording fake runner for process isolation testing.
class _RecordingRunner implements GitProcessRunner {
  GitResult Function()? handler;

  String? executable;
  List<String>? arguments;
  String? workingDirectory;
  Map<String, String>? environment;
  Duration? timeout;
  GitCancelToken? cancel;

  @override
  Future<GitResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    GitCancelToken? cancel,
    String? stdinInput,
  }) async {
    this.executable = executable;
    this.arguments = List<String>.unmodifiable(arguments);
    this.workingDirectory = workingDirectory;
    this.environment = environment;
    this.timeout = timeout;
    this.cancel = cancel;
    return handler?.call() ?? const GitResult(0, '', '', false, false);
  }
}

class _FakeControllerService extends GitService {
  _FakeControllerService(this.runner);
  final _RecordingRunner runner;

  @override
  Future<GitAvailability> gitAvailability({GitCancelToken? cancel}) async =>
      const GitAvailability.available('/opt/homebrew/bin/git');

  @override
  Future<String?> findRepoRoot(
    String directory, {
    GitCancelToken? cancel,
  }) async => '/tmp/repo';

  @override
  Future<GitRepoInfo?> repoInfo(String root, {GitCancelToken? cancel}) async =>
      const GitRepoInfo(
        root: '/tmp/repo',
        branch: 'main',
        isDetached: false,
        hasCommits: true,
        ahead: 0,
        behind: 0,
        remotes: [],
      );

  @override
  Future<List<GitChange>> status(String root, {GitCancelToken? cancel}) async =>
      [];

  @override
  Future<GitResult> pull(
    String root, {
    GitCancelToken? cancel,
    Duration timeout = GitService.pullTimeout,
  }) async {
    return runner.run(
      '/opt/homebrew/bin/git',
      const <String>['-c', 'core.quotepath=false', 'pull', '--ff-only'],
      workingDirectory: root,
      timeout: timeout,
      cancel: cancel,
    );
  }
}

ToolPathResolver _fakeResolver() {
  return ToolPathResolver(
    fileExists: (path) => path == '/opt/homebrew/bin/git',
  );
}

void main() {
  group('GitService.pull argument & timeout hygiene', () {
    test('runs exactly `git pull --ff-only` with 120 s timeout', () async {
      final runner = _RecordingRunner();
      final service = GitService(runner: runner, resolver: _fakeResolver());

      final result = await service.pull('/tmp/repo');

      expect(result.exitCode, equals(0));
      expect(runner.executable, equals('/opt/homebrew/bin/git'));
      expect(
        runner.arguments,
        equals(const <String>[
          '-c',
          'core.quotepath=false',
          'pull',
          '--ff-only',
        ]),
      );
      expect(runner.workingDirectory, equals('/tmp/repo'));
      expect(runner.timeout, equals(const Duration(seconds: 120)));
    });

    test('passes cancel token through to the runner', () async {
      final runner = _RecordingRunner();
      final service = GitService(runner: runner, resolver: _fakeResolver());
      final token = GitCancelToken();

      await service.pull('/tmp/repo', cancel: token);

      expect(runner.cancel, same(token));
    });

    test('GitController.pull delegates to service and refreshes', () async {
      final runner = _RecordingRunner();
      final service = _FakeControllerService(runner);
      final controller = GitController(
        service: service,
        debounce: Duration.zero,
      );
      controller.setExplorerFolder('/tmp/repo');
      await controller.refreshNow();

      final result = await controller.pull();

      expect(result.exitCode, equals(0));
      expect(
        runner.arguments,
        equals(const <String>[
          '-c',
          'core.quotepath=false',
          'pull',
          '--ff-only',
        ]),
      );
    });
  });

  group('GitService.fetch argument & timeout hygiene', () {
    test('runs exactly `git fetch` with a 60 s timeout', () async {
      final runner = _RecordingRunner();
      final service = GitService(runner: runner, resolver: _fakeResolver());

      final result = await service.fetch('/tmp/repo');

      expect(result.exitCode, equals(0));
      expect(runner.executable, equals('/opt/homebrew/bin/git'));
      expect(
        runner.arguments,
        equals(const <String>['-c', 'core.quotepath=false', 'fetch']),
      );
      expect(runner.workingDirectory, equals('/tmp/repo'));
      expect(runner.timeout, equals(const Duration(seconds: 60)));
    });

    test('never adds a pruning, tagging, forcing or deepening flag', () async {
      final runner = _RecordingRunner();
      final service = GitService(runner: runner, resolver: _fakeResolver());

      await service.fetch('/tmp/repo');

      for (final forbidden in const <String>[
        '--prune',
        '--tags',
        '--all',
        '--force',
        '--mirror',
        '--depth',
      ]) {
        expect(runner.arguments, isNot(contains(forbidden)));
      }
    });

    test('passes cancel token through to the runner', () async {
      final runner = _RecordingRunner();
      final service = GitService(runner: runner, resolver: _fakeResolver());
      final token = GitCancelToken();

      await service.fetch('/tmp/repo', cancel: token);

      expect(runner.cancel, same(token));
    });
  });

  group('GitService.fetchFailureMessage', () {
    test('cancelled result', () {
      const res = GitResult(-1, '', '', false, true);
      expect(GitService.fetchFailureMessage(res), equals('Fetch cancelled.'));
    });

    test('timed out result names the shorter fetch timeout', () {
      const res = GitResult(-1, '', '', true, false);
      expect(
        GitService.fetchFailureMessage(res),
        equals('Fetch timed out after 60 s (the network may be slow).'),
      );
    });

    test('unreachable remote', () {
      const res = GitResult(
        1,
        '',
        'fatal: unable to access: Could not resolve host: github.com',
        false,
        false,
      );
      expect(
        GitService.fetchFailureMessage(res),
        equals(
          'Could not reach the remote. Check the network and the remote URL.',
        ),
      );
    });

    test('falls back to git\'s own first line', () {
      const res = GitResult(
        1,
        '',
        '\nfatal: something unexpected\nmore',
        false,
        false,
      );
      expect(
        GitService.fetchFailureMessage(res),
        equals('fatal: something unexpected'),
      );
    });
  });

  group('GitService.pullFailureMessage', () {
    test('cancelled result', () {
      const res = GitResult(-1, '', '', false, true);
      expect(GitService.pullFailureMessage(res), equals('Pull cancelled.'));
    });

    test('timed out result', () {
      const res = GitResult(-1, '', '', true, false);
      expect(
        GitService.pullFailureMessage(res),
        equals('Pull timed out after 120 s (the network may be slow).'),
      );
    });

    test('diverged branches / non-ff error', () {
      const res = GitResult(
        1,
        '',
        'fatal: Not possible to fast-forward, aborting.',
        false,
        false,
      );
      expect(
        GitService.pullFailureMessage(res),
        equals(
          'Branches have diverged. Resolve this in a terminal (merge or rebase).',
        ),
      );
    });

    test('local changes uncommitted error', () {
      const res = GitResult(
        1,
        '',
        'error: Your local changes to the following files would be overwritten by merge:\n\tfoo.txt',
        false,
        false,
      );
      expect(
        GitService.pullFailureMessage(res),
        equals('Commit or stash your changes first.'),
      );
    });

    test('unreachable remote', () {
      const res = GitResult(
        1,
        '',
        'fatal: Could not resolve host: github.com',
        false,
        false,
      );
      expect(
        GitService.pullFailureMessage(res),
        equals(
          'Could not reach the remote. Check the network and the remote URL.',
        ),
      );
    });
  });

  group('Real GitService.pull integration tests', () {
    test('pull fast-forwards cleanly from local bare upstream', () async {
      if (!_gitInstalled()) return;

      // 1. Create bare origin repo
      final bareHost = await _tempDir('cce_pull_bare_');
      final bareDir = Directory('${bareHost.path}/remote.git');
      final seedDir = await _tempDir('cce_pull_seed_');
      await _git(seedDir, <String>['init', '-b', 'main']);
      await _git(seedDir, <String>['config', 'user.name', 'Test User']);
      await _git(seedDir, <String>['config', 'user.email', 'test@example.com']);
      await File('${seedDir.path}/file.txt').writeAsString('v1\n');
      await _git(seedDir, <String>['add', '--', 'file.txt']);
      await _git(seedDir, <String>['commit', '-m', 'initial']);
      await _git(seedDir, <String>[
        'init',
        '--bare',
        '-b',
        'main',
        bareDir.path,
      ]);
      await _git(seedDir, <String>['remote', 'add', 'origin', bareDir.path]);
      await _git(seedDir, <String>['push', '-u', 'origin', 'main']);

      // 2. Clone local repo
      final clientHost = await _tempDir('cce_pull_client_');
      final clientDir = Directory('${clientHost.path}/client');
      final seedResult = await Process.run('git', <String>[
        'clone',
        bareDir.path,
        clientDir.path,
      ]);
      expect(seedResult.exitCode, equals(0));
      await _git(clientDir, <String>['config', 'user.name', 'Test User']);
      await _git(clientDir, <String>[
        'config',
        'user.email',
        'test@example.com',
      ]);

      // 3. Add new commit to seed and push to bare
      await File('${seedDir.path}/file.txt').writeAsString('v2\n');
      await _git(seedDir, <String>['add', '--', 'file.txt']);
      await _git(seedDir, <String>['commit', '-m', 'v2 commit']);
      await _git(seedDir, <String>['push', 'origin', 'main']);

      // 4. Fetch in client to update remote tracking branch
      await _git(clientDir, <String>['fetch']);

      // 5. Test GitService.pull
      final service = GitService();
      final result = await service.pull(clientDir.path);
      expect(result.succeeded, isTrue);

      final updatedContent = await File('${clientDir.path}/file.txt')
          .readAsString();
      expect(updatedContent, equals('v2\n'));
    });

    test('fetch moves `behind` and leaves the worktree alone', () async {
      if (!_gitInstalled()) return;

      final bareHost = await _tempDir('cce_fetch_bare_');
      final bareDir = Directory('${bareHost.path}/remote.git');
      final seedDir = await _tempDir('cce_fetch_seed_');
      await _git(seedDir, <String>['init', '-b', 'main']);
      await _git(seedDir, <String>['config', 'user.name', 'Test User']);
      await _git(seedDir, <String>['config', 'user.email', 'test@example.com']);
      await File('${seedDir.path}/file.txt').writeAsString('v1\n');
      await _git(seedDir, <String>['add', '--', 'file.txt']);
      await _git(seedDir, <String>['commit', '-m', 'initial']);
      await _git(seedDir, <String>[
        'init',
        '--bare',
        '-b',
        'main',
        bareDir.path,
      ]);
      await _git(seedDir, <String>['remote', 'add', 'origin', bareDir.path]);
      await _git(seedDir, <String>['push', '-u', 'origin', 'main']);

      final clientHost = await _tempDir('cce_fetch_client_');
      final clientDir = Directory('${clientHost.path}/client');
      await Process.run('git', <String>['clone', bareDir.path, clientDir.path]);
      await _git(clientDir, <String>['config', 'user.name', 'Test User']);
      await _git(clientDir, <String>[
        'config',
        'user.email',
        'test@example.com',
      ]);

      // The remote moves on after the clone, as it does in real use.
      await File('${seedDir.path}/file.txt').writeAsString('v2\n');
      await _git(seedDir, <String>['add', '--', 'file.txt']);
      await _git(seedDir, <String>['commit', '-m', 'v2 commit']);
      await _git(seedDir, <String>['push', 'origin', 'main']);

      final service = GitService();

      // The defect `fetch` exists to fix: without it `behind` stays 0, so the
      // Pull button can never enable.
      final stale = await service.repoInfo(clientDir.path);
      expect(stale, isNotNull);
      expect(stale!.behind, equals(0));

      final result = await service.fetch(clientDir.path);
      expect(result.succeeded, isTrue);

      final fresh = await service.repoInfo(clientDir.path);
      expect(fresh, isNotNull);
      expect(fresh!.behind, equals(1));

      // A fetch moves refs only: the worktree still holds the old content.
      expect(
        await File('${clientDir.path}/file.txt').readAsString(),
        equals('v1\n'),
      );
    });

    test('pull fails when branches have diverged', () async {
      if (!_gitInstalled()) return;

      final bareHost = await _tempDir('cce_pull_diverge_bare_');
      final bareDir = Directory('${bareHost.path}/remote.git');
      final seedDir = await _tempDir('cce_pull_diverge_seed_');
      await _git(seedDir, <String>['init', '-b', 'main']);
      await _git(seedDir, <String>['config', 'user.name', 'Test User']);
      await _git(seedDir, <String>['config', 'user.email', 'test@example.com']);
      await File('${seedDir.path}/file.txt').writeAsString('v1\n');
      await _git(seedDir, <String>['add', '--', 'file.txt']);
      await _git(seedDir, <String>['commit', '-m', 'initial']);
      await _git(seedDir, <String>[
        'init',
        '--bare',
        '-b',
        'main',
        bareDir.path,
      ]);
      await _git(seedDir, <String>['remote', 'add', 'origin', bareDir.path]);
      await _git(seedDir, <String>['push', '-u', 'origin', 'main']);

      final clientHost = await _tempDir('cce_pull_diverge_client_');
      final clientDir = Directory('${clientHost.path}/client');
      await Process.run('git', <String>['clone', bareDir.path, clientDir.path]);
      await _git(clientDir, <String>['config', 'user.name', 'Test User']);
      await _git(clientDir, <String>[
        'config',
        'user.email',
        'test@example.com',
      ]);

      // Commit on seed and push
      await File('${seedDir.path}/file.txt').writeAsString('seed v2\n');
      await _git(seedDir, <String>['add', '--', 'file.txt']);
      await _git(seedDir, <String>['commit', '-m', 'seed commit']);
      await _git(seedDir, <String>['push', 'origin', 'main']);

      // Local commit on client
      await File('${seedDir.path}/file.txt').writeAsString('client v2\n');
      await File('${clientDir.path}/file.txt').writeAsString('client v2\n');
      await _git(clientDir, <String>['add', '--', 'file.txt']);
      await _git(clientDir, <String>['commit', '-m', 'client commit']);

      // Fetch
      await _git(clientDir, <String>['fetch']);

      // Pull fast-forward only should fail
      final service = GitService();
      final result = await service.pull(clientDir.path);
      expect(result.succeeded, isFalse);

      final msg = GitService.pullFailureMessage(result);
      expect(
        msg,
        equals(
          'Branches have diverged. Resolve this in a terminal (merge or rebase).',
        ),
      );
    });
  });
}
