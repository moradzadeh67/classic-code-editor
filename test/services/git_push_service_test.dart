import 'dart:io';

import 'package:classic_code_editor/models/git_models.dart';
import 'package:classic_code_editor/services/git_service.dart';
import 'package:classic_code_editor/services/tool_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for `GitService.push` and its failure mapping (Git G5).
///
/// Real tests run only in throwaway temporary repositories with a local bare
/// remote (never the project's own repository, never the network) and are
/// skipped when `git` is not installed. The contract tests use a recording
/// fake runner, so the exact arguments/timeout can be asserted — including
/// that none of the forbidden flags is ever added for any input.
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
      // Already gone; nothing to clean up.
    }
  });
  return directory;
}

Future<void> _git(Directory directory, List<String> arguments) async {
  final result = await Process.run('git', arguments,
      workingDirectory: directory.path);
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}

/// A repository with a local identity and an initial commit.
Future<Directory> _newRepo() async {
  final directory = await _tempDir('cce_git_push_');
  await _git(directory, <String>['init', '-b', 'main']);
  await _git(directory, <String>['config', 'user.name', 'Test User']);
  await _git(directory, <String>['config', 'user.email', 'test@example.com']);
  await File('${directory.path}/first.txt').writeAsString('one\n');
  await _git(directory, <String>['add', '--', 'first.txt']);
  await _git(directory, <String>['commit', '-m', 'first']);
  return directory;
}

/// A bare remote inside a fresh temp host directory that [work] tracks as
/// `origin` (the remote is added but nothing is pushed yet).
Future<Directory> _bareRemoteWithUpstream(Directory work) async {
  final host = await _tempDir('cce_git_push_host_');
  final bare = Directory('${host.path}/remote.git');
  await _git(work, <String>['init', '--bare', '-b', 'main', bare.path]);
  await _git(work, <String>['remote', 'add', 'origin', bare.path]);
  return bare;
}

/// A recording fake runner: keeps every argument, the timeout and the cancel
/// token it was given.
class _RecordingRunner implements GitProcessRunner {
  GitResult Function()? handler;

  String? executable;
  List<String>? arguments;
  String? workingDirectory;
  Map<String, String>? environment;
  Duration? timeout;
  GitCancelToken? cancel;
  String? stdinInput;

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
    this.stdinInput = stdinInput;
    return handler?.call() ?? const GitResult(0, '', '', false, false);
  }
}

ToolPathResolver _fakeResolver() {
  return ToolPathResolver(
    loginShellWhich: (String name) async => name == 'git' ? '/fake/git' : null,
    loginShellPath: () async => '/usr/bin:/bin',
    fileExists: (_) => false,
    environment: const <String, String>{'PATH': '/usr/bin:/bin'},
  );
}

GitService _fakeService(_RecordingRunner runner) {
  return GitService(
    runner: runner,
    resolver: _fakeResolver(),
    environment: const <String, String>{'PATH': '/usr/bin:/bin'},
  );
}

void main() {
  final skip = _gitInstalled() ? null : 'git is not installed';

  group('contract with the process runner (fake, no git needed)', () {
    test('a branch with an upstream runs a plain `git push`', () async {
      final runner = _RecordingRunner();
      final service = _fakeService(runner);

      final result = await service.push(
        '/repo',
        remote: 'origin',
        branch: 'main',
      );

      expect(result.succeeded, isTrue);
      expect(
        runner.arguments,
        const <String>['-c', 'core.quotepath=false', 'push'],
      );
      expect(runner.workingDirectory, '/repo');
    });

    test('a branch without upstream runs `git push -u <remote> <branch>`',
        () async {
      final runner = _RecordingRunner();
      final service = _fakeService(runner);

      await service.push(
        '/repo',
        remote: 'origin',
        branch: 'feature/آی',
        setUpstream: true,
      );

      expect(
        runner.arguments,
        const <String>[
          '-c',
          'core.quotepath=false',
          'push',
          '-u',
          'origin',
          'feature/آی',
        ],
      );
    });

    test('the push runs with the 120 s network timeout and a cancel token',
        () async {
      final runner = _RecordingRunner();
      final service = _fakeService(runner);
      final token = GitCancelToken();

      await service.push(
        '/repo',
        remote: 'origin',
        branch: 'main',
        cancel: token,
        timeout: const Duration(milliseconds: 5),
      );

      expect(runner.timeout, const Duration(milliseconds: 5));
      expect(runner.cancel, same(token));
    });

    test('the default timeout leaves room for a slow network', () async {
      final runner = _RecordingRunner();
      final service = _fakeService(runner);

      await service.push('/repo', remote: 'origin', branch: 'main');

      expect(runner.timeout, GitService.pushTimeout);
      expect(runner.timeout, const Duration(seconds: 120));
    });

    test('no forbidden flag is ever added for any input', () async {
      const forbidden = <String>[
        '--force',
        '--force-with-lease',
        '--delete',
        '--mirror',
        '--all',
        '--tags',
      ];
      final inputs = <({String remote, String branch, bool setUpstream})>[
        (remote: 'origin', branch: 'main', setUpstream: false),
        (remote: 'origin', branch: 'main', setUpstream: true),
        (remote: 'upstream', branch: 'feature/x/y', setUpstream: true),
        (remote: '--force', branch: 'main', setUpstream: false),
        (remote: 'origin', branch: '--force-with-lease', setUpstream: false),
        (remote: '--mirror', branch: '--all', setUpstream: true),
      ];
      for (final input in inputs) {
        final runner = _RecordingRunner();
        final service = _fakeService(runner);
        await service.push(
          '/repo',
          remote: input.remote,
          branch: input.branch,
          setUpstream: input.setUpstream,
        );
        // An option-looking remote or branch is refused before any process
        // starts; every other input goes through with only the plain form.
        for (final argument in runner.arguments ?? const <String>[]) {
          expect(argument, isNot(anyOf(forbidden)),
              reason: 'arguments were $runner.arguments');
        }
      }
    });

    test('an option-looking remote or branch starts no process at all',
        () async {
      final runner = _RecordingRunner();
      final service = _fakeService(runner);

      final remoteResult = await service.push(
        '/repo',
        remote: '--force',
        branch: 'main',
      );
      final branchResult = await service.push(
        '/repo',
        remote: 'origin',
        branch: '--delete',
      );

      expect(remoteResult.succeeded, isFalse);
      expect(branchResult.succeeded, isFalse);
      expect(runner.arguments, isNull, reason: 'no git process may be started');
    });
  });

  group('pushFailureMessage mapping', () {
    const cancelled = GitResult(-1, '', 'Cancelled', false, true);
    const timedOut = GitResult(0, '', '', true, false);

    test('cancel and timeout', () {
      expect(GitService.pushFailureMessage(cancelled), 'Push cancelled.');
      expect(
        GitService.pushFailureMessage(timedOut),
        contains('timed out after 120 s'),
      );
    });

    test('cannot resolve the host (ssh and https forms)', () {
      final ssh = const GitResult(
        128,
        '',
        'ssh: Could not resolve hostname github.com: nodename nor servname '
            'provided',
        false,
        false,
      );
      final https = const GitResult(
        128,
        '',
        "fatal: unable to access 'https://github.com/user/repo.git/': "
            'Could not resolve host: github.com',
        false,
        false,
      );
      expect(
        GitService.pushFailureMessage(ssh),
        'Could not reach the remote. Check the network and the remote URL.',
      );
      expect(
        GitService.pushFailureMessage(https),
        'Could not reach the remote. Check the network and the remote URL.',
      );
    });

    test('a passphrase git cannot supply points at ssh-agent', () {
      final result = const GitResult(
        128,
        '',
        'Load key "/Users/me/.ssh/id_ed25519": incorrect passphrase supplied '
            'to decrypt private key',
        false,
        false,
      );
      expect(
        GitService.pushFailureMessage(result),
        'Add your key to ssh-agent (ssh-add --apple-use-keychain).',
      );
    });

    test('authentication failed (ssh and https forms)', () {
      final ssh = const GitResult(
        128,
        '',
        'git@github.com: Permission denied (publickey).\n'
            'fatal: Could not read from remote repository.',
        false,
        false,
      );
      final https = const GitResult(
        128,
        '',
        "fatal: Authentication failed for 'https://github.com/user/repo.git/'",
        false,
        false,
      );
      const expected =
          'Authentication failed. Push once from a terminal or run '
          '`gh auth login`, or check your SSH key';
      expect(GitService.pushFailureMessage(ssh), expected);
      expect(GitService.pushFailureMessage(https), expected);
    });

    test('a rejected (non-fast-forward) push points at Pull', () {
      final result = const GitResult(
        1,
        '',
        'To github.com:user/repo.git\n'
            ' ! [rejected]        main -> main (fetch first)\n'
            "error: failed to push some refs to 'github.com:user/repo.git'\n"
            'hint: Updates were rejected because the tip of your current '
            'branch is behind\n',
        false,
        false,
      );
      expect(
        GitService.pushFailureMessage(result),
        'The remote has new commits. Pull first',
      );
    });

    test('no output at all still says something', () {
      final result = const GitResult(128, '', '', false, false);
      expect(
        GitService.pushFailureMessage(result),
        'git push failed (exit 128).',
      );
    });
  });

  test(
    'push without upstream sets the upstream on a local bare remote',
    () async {
      final work = await _newRepo();
      final bare = await _bareRemoteWithUpstream(work);
      final service = GitService();

      // A second commit that only exists locally.
      await File('${work.path}/second.txt').writeAsString('two\n');
      await _git(work, <String>['add', '--', 'second.txt']);
      await _git(work, <String>['commit', '-m', 'second']);

      final result = await service.push(
        work.path,
        remote: 'origin',
        branch: 'main',
        setUpstream: true,
      );
      expect(result.succeeded, isTrue, reason: result.stderr);

      // The tracking branch was set...
      final info = await service.repoInfo(work.path);
      expect(info, isNotNull);
      expect(info!.upstream, 'origin/main');
      expect(info.ahead, 0);

      // ...and the bare remote now holds the branch.
      final rev = await Process.run(
        'git',
        const <String>['rev-parse', 'main'],
        workingDirectory: bare.path,
      );
      final local = await Process.run(
        'git',
        const <String>['rev-parse', 'main'],
        workingDirectory: work.path,
      );
      expect(rev.exitCode, 0, reason: rev.stderr);
      expect(rev.stdout.trim(), local.stdout.trim());
    },
    skip: skip,
  );

  test(
    'push with an upstream sends new commits with the plain form',
    () async {
      final work = await _newRepo();
      final bare = await _bareRemoteWithUpstream(work);
      final service = GitService();

      await File('${work.path}/second.txt').writeAsString('two\n');
      await _git(work, <String>['add', '--', 'second.txt']);
      await _git(work, <String>['commit', '-m', 'second']);
      final first = await service.push(
        work.path,
        remote: 'origin',
        branch: 'main',
        setUpstream: true,
      );
      expect(first.succeeded, isTrue, reason: first.stderr);

      // A third commit pushed with the plain `git push` form.
      await File('${work.path}/third.txt').writeAsString('three\n');
      await _git(work, <String>['add', '--', 'third.txt']);
      await _git(work, <String>['commit', '-m', 'third']);
      final second = await service.push(
        work.path,
        remote: 'origin',
        branch: 'main',
      );
      expect(second.succeeded, isTrue, reason: second.stderr);

      final bareRev = await Process.run(
        'git',
        const <String>['rev-parse', 'main'],
        workingDirectory: bare.path,
      );
      final localRev = await Process.run(
        'git',
        const <String>['rev-parse', 'main'],
        workingDirectory: work.path,
      );
      expect(bareRev.stdout.trim(), localRev.stdout.trim());
    },
    skip: skip,
  );

  test(
    'a rejected push shows the Pull hint and changes nothing locally',
    () async {
      final work = await _newRepo();
      final bare = await _bareRemoteWithUpstream(work);
      final service = GitService();

      await File('${work.path}/second.txt').writeAsString('two\n');
      await _git(work, <String>['add', '--', 'second.txt']);
      await _git(work, <String>['commit', '-m', 'second']);
      expect(
        (await service.push(
          work.path,
          remote: 'origin',
          branch: 'main',
          setUpstream: true,
        ))
            .succeeded,
        isTrue,
      );

      // A second clone of the bare remote moves it ahead.
      final clone = await _tempDir('cce_git_push_clone_');
      final cloneResult = await Process.run(
        'git',
        <String>['clone', bare.path, clone.path],
      );
      expect(cloneResult.exitCode, 0, reason: cloneResult.stderr);
      await _git(clone, <String>['config', 'user.name', 'Clone User']);
      await _git(clone, <String>['config', 'user.email', 'clone@example.com']);
      await File('${clone.path}/other.txt').writeAsString('other\n');
      await _git(clone, <String>['add', '--', 'other.txt']);
      await _git(clone, <String>['commit', '-m', 'divergent']);
      final clonePush = await Process.run(
        'git',
        const <String>['push'],
        workingDirectory: clone.path,
      );
      expect(clonePush.exitCode, 0, reason: clonePush.stderr);

      // The first repository now has a divergent commit of its own.
      await File('${work.path}/mine.txt').writeAsString('mine\n');
      await _git(work, <String>['add', '--', 'mine.txt']);
      await _git(work, <String>['commit', '-m', 'mine']);
      final headBefore = await Process.run(
        'git',
        const <String>['rev-parse', 'HEAD'],
        workingDirectory: work.path,
      );

      final result = await service.push(
        work.path,
        remote: 'origin',
        branch: 'main',
      );
      expect(result.succeeded, isFalse);
      expect(
        GitService.pushFailureMessage(result),
        'The remote has new commits. Pull first',
      );

      // The failed push changed nothing locally.
      final headAfter = await Process.run(
        'git',
        const <String>['rev-parse', 'HEAD'],
        workingDirectory: work.path,
      );
      expect(headAfter.stdout.trim(), headBefore.stdout.trim());
    },
    skip: skip,
  );
}
