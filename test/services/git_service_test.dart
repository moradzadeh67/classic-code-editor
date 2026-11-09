import 'dart:async';
import 'dart:io';

import 'package:classic_code_editor/models/git_models.dart';
import 'package:classic_code_editor/services/git_service.dart';
import 'package:classic_code_editor/services/tool_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

const Map<String, String> _testEnvironment = <String, String>{
  'HOME': '/Users/test',
  'PATH': '/usr/bin:/bin',
};

bool _gitInstalled() {
  try {
    return Process.runSync('git', const <String>['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

class _Call {
  _Call(
    this.executable,
    this.arguments,
    this.workingDirectory,
    this.environment,
    this.timeout,
    this.cancel,
  );

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final Duration? timeout;
  final GitCancelToken? cancel;
}

class _FakeRunner implements GitProcessRunner {
  _FakeRunner(this.handler);

  final Future<GitResult> Function(String executable, List<String> arguments)
  handler;
  final List<_Call> calls = <_Call>[];

  @override
  Future<GitResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    GitCancelToken? cancel,
  }) async {
    calls.add(
      _Call(
        executable,
        List<String>.unmodifiable(arguments),
        workingDirectory,
        environment == null
            ? null
            : Map<String, String>.unmodifiable(environment),
        timeout,
        cancel,
      ),
    );
    return handler(executable, arguments);
  }
}

ToolPathResolver _resolver({
  String? gitPath = '/fake/bin/git',
  Set<String> existing = const <String>{},
  Map<String, String> environment = _testEnvironment,
}) {
  return ToolPathResolver(
    loginShellWhich: (String name) async => name == 'git' ? gitPath : null,
    loginShellPath: () async => '/usr/bin:/bin',
    fileExists: existing.contains,
    environment: environment,
  );
}

GitService _fakeService({
  required GitProcessRunner runner,
  String? gitPath = '/fake/bin/git',
  Set<String> existing = const <String>{},
  Map<String, String> environment = _testEnvironment,
}) {
  return GitService(
    runner: runner,
    resolver: _resolver(
      gitPath: gitPath,
      existing: existing,
      environment: environment,
    ),
    environment: environment,
    fileExists: existing.contains,
  );
}

Future<GitResult> _defaultFakeHandler(
  String executable,
  List<String> arguments,
) async {
  if (arguments.contains('--show-toplevel')) {
    return const GitResult(0, '/repo\n', '', false, false);
  }
  if (arguments.contains('symbolic-ref')) {
    return const GitResult(0, 'main\n', '', false, false);
  }
  if (arguments.contains('--verify')) {
    return const GitResult(0, 'abc1234\n', '', false, false);
  }
  if (arguments.contains('--abbrev-ref')) {
    return const GitResult(1, '', 'no upstream', false, false);
  }
  if (arguments.contains('status')) {
    return const GitResult(0, '?? a.txt\u0000', '', false, false);
  }
  if (arguments.contains('remote')) {
    return const GitResult(
      0,
      'origin\thttps://user:secret@example.com/repo.git (fetch)\n'
          'origin\thttps://user:secret@example.com/repo.git (push)\n',
      '',
      false,
      false,
    );
  }
  return const GitResult(0, '', '', false, false);
}

Future<Directory> _tempDir(String prefix) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // Already gone (or a test killed the process); nothing to clean up.
    }
  });
  return directory;
}

Future<ProcessResult> _runGit(
  Directory directory,
  List<String> arguments,
) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory.path,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result;
}

Future<Directory> _newRepo({bool bare = false, String branch = 'main'}) async {
  final directory = await _tempDir(bare ? 'cce_git_bare_' : 'cce_git_repo_');
  await _runGit(directory, <String>['init', if (bare) '--bare', '-b', branch]);
  if (!bare) {
    await _configureUser(directory);
  }
  return directory;
}

Future<void> _configureUser(Directory repository) async {
  await _runGit(repository, <String>['config', 'user.name', 'Test User']);
  await _runGit(repository, <String>[
    'config',
    'user.email',
    'test@example.com',
  ]);
}

Future<Directory> _cloneRepo(Directory bare) async {
  final directory = await _tempDir('cce_git_clone_');
  final result = await Process.run('git', <String>[
    'clone',
    bare.path,
    directory.path,
  ]);
  if (result.exitCode != 0) {
    fail('git clone failed: ${result.stderr}');
  }
  await _configureUser(directory);
  return directory;
}

Future<void> _writeCommit(
  Directory repository,
  String name,
  String content,
  String message,
) async {
  await File('${repository.path}/$name').writeAsString(content);
  await _runGit(repository, <String>['add', '--', name]);
  await _runGit(repository, <String>['commit', '-m', message]);
}

Future<String> _realPath(String path) => Directory(path).resolveSymbolicLinks();

void main() {
  final gitInstalled = _gitInstalled();

  group('GitChange status helpers', () {
    GitChange change(String index, String worktree) =>
        GitChange(path: 'p', indexStatus: index, worktreeStatus: worktree);

    test('staged, unstaged and staged+modified are distinct', () {
      final staged = change('M', ' ');
      expect(staged.isStaged, isTrue);
      expect(staged.isUnstaged, isFalse);

      final unstaged = change(' ', 'M');
      expect(unstaged.isStaged, isFalse);
      expect(unstaged.isUnstaged, isTrue);

      final both = change('M', 'M');
      expect(both.isStaged, isTrue);
      expect(both.isUnstaged, isTrue);
    });

    test('untracked and conflicted paths belong to neither group', () {
      final untracked = change('?', '?');
      expect(untracked.isUntracked, isTrue);
      expect(untracked.isStaged, isFalse);
      expect(untracked.isUnstaged, isFalse);

      for (final pair in <String>['UU', 'AA', 'DD', 'AU', 'UA', 'DU', 'UD']) {
        final conflicted = change(pair[0], pair[1]);
        expect(conflicted.isConflicted, isTrue, reason: pair);
        expect(conflicted.isStaged, isFalse, reason: pair);
        expect(conflicted.isUnstaged, isFalse, reason: pair);
      }
    });

    test('a rename keeps its original path', () {
      final rename = GitChange(
        path: 'new name.txt',
        originalPath: 'old name.txt',
        indexStatus: 'R',
        worktreeStatus: ' ',
      );
      expect(rename.isStaged, isTrue);
      expect(rename.isUnstaged, isFalse);
      expect(rename.originalPath, 'old name.txt');
    });
  });

  group('GitService (fake runner)', () {
    test(
      'every call is an argument list with the read-only environment',
      () async {
        final fake = _FakeRunner(_defaultFakeHandler);
        final service = _fakeService(runner: fake);

        final availability = await service.gitAvailability();
        expect(availability.isAvailable, isTrue);
        expect(availability.path, '/fake/bin/git');

        expect(await service.findRepoRoot('/repo'), '/repo');
        final info = await service.repoInfo('/repo');
        expect(info, isNotNull);
        expect(info!.branch, 'main');
        expect(info.hasCommits, isTrue);
        expect(info.upstream, isNull);
        expect(info.ahead, 0);
        expect(info.behind, 0);
        expect(info.remotes.single.url, 'https://example.com/repo.git');

        final changes = await service.status('/repo');
        expect(changes.single.path, 'a.txt');

        expect(fake.calls, isNotEmpty);
        for (final call in fake.calls) {
          expect(call.executable, '/fake/bin/git');
          expect(call.arguments, isA<List<String>>());
          expect(call.arguments, isNotEmpty);
          expect(call.arguments[0], '-c');
          expect(call.arguments[1], 'core.quotepath=false');
          for (final argument in call.arguments) {
            expect(
              argument.contains(' '),
              isFalse,
              reason:
                  'a spaced argument would look like a shell string: '
                  '"$argument"',
            );
          }
          expect(call.timeout, const Duration(seconds: 15));
          expect(call.workingDirectory, '/repo');
          final environment = call.environment!;
          expect(environment['GIT_TERMINAL_PROMPT'], '0');
          expect(environment['GIT_OPTIONAL_LOCKS'], '0');
          expect(environment['LC_ALL'], 'C');
          expect(environment['GIT_SSH_COMMAND'], 'ssh -o BatchMode=yes');
          expect(environment['PATH'], contains('/opt/homebrew/bin'));
          expect(environment['PATH'], contains('/usr/bin'));
        }
      },
    );

    test('keeps a caller-provided GIT_SSH_COMMAND', () async {
      final fake = _FakeRunner(_defaultFakeHandler);
      final environment = <String, String>{
        ..._testEnvironment,
        'GIT_SSH_COMMAND': 'ssh -i /tmp/key',
      };
      final service = _fakeService(runner: fake, environment: environment);

      await service.status('/repo');

      expect(
        fake.calls.single.environment!['GIT_SSH_COMMAND'],
        'ssh -i /tmp/key',
      );
    });

    test('passes the cancel token to the process runner', () async {
      final token = GitCancelToken();
      final fake = _FakeRunner((
        String executable,
        List<String> arguments,
      ) async {
        token.cancel();
        return const GitResult(-1, '', 'Cancelled', false, true);
      });

      final changes = await _fakeService(runner: fake)
          .status('/repo', cancel: token);

      expect(changes, isEmpty);
      expect(fake.calls.single.cancel, same(token));
    });

    test('a pre-cancelled token starts no process', () async {
      final token = GitCancelToken()..cancel();
      final fake = _FakeRunner(_defaultFakeHandler);

      final changes = await _fakeService(runner: fake)
          .status('/repo', cancel: token);

      expect(changes, isEmpty);
      expect(fake.calls, isEmpty);
    });

    test(
      'parses porcelain -z rename, untracked and conflict entries',
      () async {
        const output =
            'R  new name.txt\u0000old name.txt\u0000'
            '?? چای با شیر.txt\u0000'
            'UU uu.txt\u0000AA aa.txt\u0000DD dd.txt\u0000'
            'AU au.txt\u0000UA ua.txt\u0000DU du.txt\u0000UD ud.txt\u0000';
        final fake = _FakeRunner((
          String executable,
          List<String> arguments,
        ) async {
          return const GitResult(0, output, '', false, false);
        });

        final changes = await _fakeService(runner: fake).status('/repo');

        expect(changes, hasLength(9));

        final rename = changes.first;
        expect(rename.path, 'new name.txt');
        expect(rename.originalPath, 'old name.txt');
        expect(rename.isStaged, isTrue);
        expect(rename.isUnstaged, isFalse);

        final persian = changes.firstWhere(
          (GitChange change) => change.path == 'چای با شیر.txt',
        );
        expect(persian.isUntracked, isTrue);
        expect(persian.isStaged, isFalse);
        expect(persian.isUnstaged, isFalse);

        for (final pair in <String>['UU', 'AA', 'DD', 'AU', 'UA', 'DU', 'UD']) {
          final conflicted = changes.firstWhere(
            (GitChange change) =>
                '${change.indexStatus}${change.worktreeStatus}' == pair,
          );
          expect(conflicted.isConflicted, isTrue, reason: pair);
          expect(conflicted.isStaged, isFalse, reason: pair);
          expect(conflicted.isUnstaged, isFalse, reason: pair);
        }
      },
    );

    test('strips only user:password from remote URLs', () {
      expect(
        GitService.stripCredentials('https://user:secret@example.com/repo.git'),
        'https://example.com/repo.git',
      );
      expect(
        GitService.stripCredentials('ssh://user:p%40ss@example.com/repo.git'),
        'ssh://example.com/repo.git',
      );
      expect(
        GitService.stripCredentials('git@github.com:user/repo.git'),
        'git@github.com:user/repo.git',
      );
      expect(
        GitService.stripCredentials('https://token@example.com/repo.git'),
        'https://token@example.com/repo.git',
      );
      expect(
        GitService.stripCredentials('https://example.com/repo.git'),
        'https://example.com/repo.git',
      );
    });
  });

  group('GitService availability', () {
    const stubPaths = <String>{'/usr/bin/git', '/usr/bin/xcode-select'};

    test('reports the install hint without executing the Apple stub', () async {
      final fake = _FakeRunner((
        String executable,
        List<String> arguments,
      ) async {
        expect(executable, '/usr/bin/xcode-select');
        expect(arguments, <String>['-p']);
        return const GitResult(
          1,
          '',
          'unable to get active developer directory',
          false,
          false,
        );
      });
      final service = _fakeService(
        runner: fake,
        gitPath: '/usr/bin/git',
        existing: stubPaths,
      );

      final availability = await service.gitAvailability();

      expect(availability.isAvailable, isFalse);
      expect(availability.hint, GitService.installHint);
      expect(fake.calls, hasLength(1));
      expect(
        fake.calls.any((_Call call) => call.executable == '/usr/bin/git'),
        isFalse,
      );
    });

    test('uses the Apple stub once Command Line Tools are installed', () async {
      final fake = _FakeRunner((
        String executable,
        List<String> arguments,
      ) async {
        return const GitResult(
          0,
          '/Applications/Xcode.app/Contents/Developer',
          '',
          false,
          false,
        );
      });
      final service = _fakeService(
        runner: fake,
        gitPath: '/usr/bin/git',
        existing: stubPaths,
      );

      final availability = await service.gitAvailability();

      expect(availability.isAvailable, isTrue);
      expect(availability.path, '/usr/bin/git');
      expect(fake.calls.single.executable, '/usr/bin/xcode-select');
    });

    test('prefers a Homebrew git when the stub cannot run', () async {
      final fake = _FakeRunner((
        String executable,
        List<String> arguments,
      ) async {
        return const GitResult(1, '', 'no developer directory', false, false);
      });
      final service = _fakeService(
        runner: fake,
        gitPath: '/usr/bin/git',
        existing: <String>{...stubPaths, '/opt/homebrew/bin/git'},
      );

      final availability = await service.gitAvailability();

      expect(availability.isAvailable, isTrue);
      expect(availability.path, '/opt/homebrew/bin/git');
      expect(
        fake.calls.any((_Call call) => call.executable == '/usr/bin/git'),
        isFalse,
      );
    });

    test('reports not found without running xcode-select', () async {
      final fake = _FakeRunner(_defaultFakeHandler);
      final service = _fakeService(runner: fake, gitPath: null);

      final availability = await service.gitAvailability();

      expect(availability.isAvailable, isFalse);
      expect(availability.hint, GitService.installHint);
      expect(fake.calls, isEmpty);
    });
  });

  group('SystemGitProcessRunner', () {
    const runner = SystemGitProcessRunner();

    test('times out and kills the child', () async {
      final result = await runner.run('/bin/sleep', const <String>[
        '5',
      ], timeout: const Duration(milliseconds: 150));
      expect(result.timedOut, isTrue);
      expect(result.exitCode, isNot(0));
    }, skip: !File('/bin/sleep').existsSync());

    test('cancels and kills the child', () async {
      final token = GitCancelToken();
      final future = runner.run('/bin/sleep', const <String>[
        '5',
      ], cancel: token);
      Timer(const Duration(milliseconds: 150), token.cancel);

      final result = await future.timeout(const Duration(seconds: 5));

      expect(result.cancelled, isTrue);
      expect(result.exitCode, isNot(0));
    }, skip: !File('/bin/sleep').existsSync());

    test('caps each captured stream at 5 MB', () async {
      final directory = await _tempDir('cce_git_capture_');
      final file = File('${directory.path}/big.txt');
      await file.writeAsBytes(
        List<int>.filled(6 * 1024 * 1024, 0x41),
        flush: true,
      );

      final result = await runner.run('/bin/cat', <String>[file.path]);

      expect(result.exitCode, 0);
      expect(result.stdout.length, greaterThan(0));
      expect(
        result.stdout.length,
        lessThanOrEqualTo(SystemGitProcessRunner.maxCaptureBytes),
      );
    }, skip: !File('/bin/cat').existsSync());
  });

  group('GitService with temporary repositories', () {
    test(
      'findRepoRoot works from a sub-folder and rejects a plain folder',
      () async {
        final repository = await _newRepo();
        final sub = Directory('${repository.path}/sub/deep')
          ..createSync(recursive: true);
        final plain = await _tempDir('cce_git_plain_');
        final service = GitService();

        expect(
          await service.findRepoRoot(sub.path),
          await _realPath(repository.path),
        );
        expect(await service.findRepoRoot(plain.path), isNull);
      },
    );

    test('status reports modified, staged, staged+modified, deleted and renamed paths', () async {
      final repository = await _newRepo();
      for (final name in <String>[
        'tracked.txt',
        'staged.txt',
        'both.txt',
        'deleted.txt',
        'staged-delete.txt',
        'old name.txt',
      ]) {
        await File('${repository.path}/$name').writeAsString('base\n');
      }
      await _runGit(repository, <String>[
        'add',
        '--',
        'tracked.txt',
        'staged.txt',
        'both.txt',
        'deleted.txt',
        'staged-delete.txt',
        'old name.txt',
      ]);
      await _runGit(repository, <String>['commit', '-m', 'base']);

      await File('${repository.path}/tracked.txt')
          .writeAsString('base\nchanged\n');
      await File('${repository.path}/staged.txt').writeAsString('staged\n');
      await _runGit(repository, <String>['add', '--', 'staged.txt']);
      await File('${repository.path}/both.txt').writeAsString('both staged\n');
      await _runGit(repository, <String>['add', '--', 'both.txt']);
      await File('${repository.path}/both.txt')
          .writeAsString('both staged\nand modified\n');
      await File('${repository.path}/deleted.txt').delete();
      await _runGit(repository, <String>['rm', '--', 'staged-delete.txt']);
      await _runGit(repository, <String>['mv', 'old name.txt', 'new name.txt']);
      await File('${repository.path}/untracked.txt')
          .writeAsString('untracked\n');

      final changes = await GitService().status(repository.path);
      expect(changes, hasLength(7));

      GitChange byPath(String path) =>
          changes.firstWhere((GitChange change) => change.path == path);

      final modified = byPath('tracked.txt');
      expect(modified.isStaged, isFalse);
      expect(modified.isUnstaged, isTrue);

      final staged = byPath('staged.txt');
      expect(staged.isStaged, isTrue);
      expect(staged.isUnstaged, isFalse);

      final both = byPath('both.txt');
      expect(both.isStaged, isTrue);
      expect(both.isUnstaged, isTrue);

      final deleted = byPath('deleted.txt');
      expect(deleted.isStaged, isFalse);
      expect(deleted.isUnstaged, isTrue);

      final stagedDelete = byPath('staged-delete.txt');
      expect(stagedDelete.isStaged, isTrue);
      expect(stagedDelete.isUnstaged, isFalse);

      final renamed = byPath('new name.txt');
      expect(renamed.originalPath, 'old name.txt');
      expect(renamed.isStaged, isTrue);
      expect(renamed.isUnstaged, isFalse);

      final untracked = byPath('untracked.txt');
      expect(untracked.isUntracked, isTrue);
      expect(untracked.isStaged, isFalse);
      expect(untracked.isUnstaged, isFalse);
    });

    test('status keeps Persian names and names with spaces verbatim', () async {
      final repository = await _newRepo();
      const persian = 'چای با شیر.txt';
      const spaced = 'file with spaces.txt';
      await File('${repository.path}/$persian').writeAsString('چای\n');
      await File('${repository.path}/$spaced').writeAsString('space\n');

      final changes = await GitService().status(repository.path);

      expect(changes, hasLength(2));
      expect(
        changes
            .firstWhere((GitChange change) => change.path == persian)
            .isUntracked,
        isTrue,
      );
      expect(
        changes
            .firstWhere((GitChange change) => change.path == spaced)
            .isUntracked,
        isTrue,
      );
    });

    test('an unborn branch has a name but no commits or upstream', () async {
      final repository = await _newRepo(branch: 'main');

      final info = await GitService().repoInfo(repository.path);

      expect(info, isNotNull);
      expect(info!.branch, 'main');
      expect(info.isDetached, isFalse);
      expect(info.hasCommits, isFalse);
      expect(info.upstream, isNull);
      expect(info.ahead, 0);
      expect(info.behind, 0);
      expect(info.remotes, isEmpty);
    });

    test('a detached HEAD reports the short SHA', () async {
      final repository = await _newRepo();
      await _writeCommit(repository, 'f.dart', 'void main() {}\n', 'init');
      await _runGit(repository, <String>['checkout', '--detach']);

      final info = await GitService().repoInfo(repository.path);

      expect(info, isNotNull);
      expect(info!.isDetached, isTrue);
      expect(info.hasCommits, isTrue);
      expect(RegExp(r'^[0-9a-f]{7,}$').hasMatch(info.branch), isTrue);
    });

    test('ahead/behind count against a local bare remote', () async {
      final bare = await _newRepo(bare: true);
      final repository = await _cloneRepo(bare);
      await _writeCommit(repository, 'a.txt', '1\n', 'first');
      await _runGit(repository, <String>['push', '-u', 'origin', 'main']);
      await _writeCommit(repository, 'a.txt', '2\n', 'local');

      var info = await GitService().repoInfo(repository.path);
      expect(info, isNotNull);
      expect(info!.upstream, 'origin/main');
      expect(info.ahead, 1);
      expect(info.behind, 0);

      final other = await _cloneRepo(bare);
      await _writeCommit(other, 'b.txt', 'remote\n', 'remote');
      await _runGit(other, <String>['push', 'origin', 'main']);
      await _runGit(repository, <String>['fetch', 'origin']);

      info = await GitService().repoInfo(repository.path);
      expect(info, isNotNull);
      expect(info!.ahead, 1);
      expect(info.behind, 1);
    });

    test('remote fetch URLs have credentials stripped', () async {
      final repository = await _newRepo();
      await _runGit(repository, <String>[
        'remote',
        'add',
        'origin',
        'https://user:secret@example.com/repo.git',
      ]);
      await _runGit(repository, <String>[
        'remote',
        'add',
        'upstream',
        'git@github.com:user/repo.git',
      ]);

      final info = await GitService().repoInfo(repository.path);

      expect(info, isNotNull);
      expect(info!.remotes, hasLength(2));
      expect(
        info.remotes
            .firstWhere((GitRemote remote) => remote.name == 'origin')
            .url,
        'https://example.com/repo.git',
      );
      expect(
        info.remotes
            .firstWhere((GitRemote remote) => remote.name == 'upstream')
            .url,
        'git@github.com:user/repo.git',
      );
    });
  }, skip: gitInstalled ? false : 'git is not installed');
}
