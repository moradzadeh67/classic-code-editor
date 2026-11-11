import 'dart:convert';
import 'dart:io';

import 'package:classic_code_editor/models/git_models.dart';
import 'package:classic_code_editor/services/git_service.dart';
import 'package:classic_code_editor/services/tool_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for `GitService.commit` and the identity helpers behind the Source
/// Control panel's Commit button (Git G4).
///
/// Real tests run only in throwaway temporary repositories (never the
/// project's own repository, never the network) and are skipped when `git`
/// is not installed. The contract tests use a recording fake runner, so the
/// exact arguments/timeout/stdin split can be asserted.
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
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory.path,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}

/// A repository, with a local identity and an initial commit by default.
///
/// `withIdentity: false` leaves the identity unset (nothing local, and no
/// global identity is consulted because the environment is not the user's);
/// `withCommit: false` keeps the branch unborn — which is required together
/// with `withIdentity: false`, since git refuses a first commit without an
/// identity.
Future<Directory> _newRepo({bool withIdentity = true, bool withCommit = true}) async {
  assert(withIdentity || !withCommit);
  final directory = await _tempDir('cce_git_commit_');
  await _git(directory, <String>['init', '-b', 'main']);
  if (withIdentity) {
    await _git(directory, <String>['config', 'user.name', 'Test User']);
    await _git(directory, <String>['config', 'user.email', 'test@example.com']);
  }
  if (withCommit) {
    await File('${directory.path}/first.txt').writeAsString('one\n');
    await _git(directory, <String>['add', '--', 'first.txt']);
    await _git(directory, <String>['commit', '-m', 'first']);
  }
  return directory;
}

/// A recording fake runner: keeps every argument, the stdin payload, the
/// timeout and the cancel token it was given.
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
    test('the message goes to stdin, never to the argument list', () async {
      final runner = _RecordingRunner();
      final service = _fakeService(runner);
      const message = 'subject line\n\nbody پیام چندخطی\n';

      final result = await service.commit('/repo', message);

      expect(result.succeeded, isTrue);
      expect(runner.executable, '/fake/git');
      expect(
        runner.arguments,
        const <String>['-c', 'core.quotepath=false', 'commit', '-F', '-'],
      );
      // The message must not appear in any argument (arguments were recorded
      // unmodifiable, so this loop cannot be optimised away).
      for (final argument in runner.arguments!) {
        expect(argument.contains('subject line'), isFalse);
        expect(argument.contains('پیام'), isFalse);
      }
      expect(runner.stdinInput, message);
      expect(runner.workingDirectory, '/repo');
    });

    test('the commit runs with the 60 s hook timeout and a cancel token',
        () async {
      final runner = _RecordingRunner();
      final service = _fakeService(runner);
      final token = GitCancelToken();

      await service.commit(
        '/repo',
        'm\n',
        cancel: token,
        timeout: const Duration(milliseconds: 5),
      );

      expect(runner.timeout, const Duration(milliseconds: 5));
      expect(runner.cancel, same(token));
    });

    test('the default timeout leaves room for slow hooks', () async {
      final runner = _RecordingRunner();
      final service = _fakeService(runner);

      await service.commit('/repo', 'm\n');

      expect(runner.timeout, GitService.commitTimeout);
      expect(runner.timeout, const Duration(seconds: 60));
    });
  });

  group('commitFailureMessage mapping', () {
    const cancelled = GitResult(-1, '', 'Cancelled', false, true);
    const timedOut = GitResult(0, '', '', true, false);

    test('cancel and timeout', () {
      expect(
        GitService.commitFailureMessage(cancelled),
        'Commit cancelled.',
      );
      expect(
        GitService.commitFailureMessage(timedOut),
        contains('timed out after 60 s'),
      );
    });

    test('index.lock exists', () {
      final result = const GitResult(
        128,
        '',
        'fatal: Unable to create '
            "'/repo/.git/index.lock': File exists.\n\nAnother git process "
            'seems to be running in this repository.',
        false,
        false,
      );
      expect(
        GitService.commitFailureMessage(result),
        'Another git process is running; if none is, delete '
        '.git/index.lock yourself.',
      );
    });

    test('nothing staged (both wordings)', () {
      final stdoutForm = const GitResult(
        1,
        'On branch main\nnothing to commit, working tree clean\n',
        '',
        false,
        false,
      );
      final stderrForm = const GitResult(
        1,
        '',
        'no changes added to commit (use "git add" and/or "git commit -a")',
        false,
        false,
      );
      expect(
        GitService.commitFailureMessage(stdoutForm),
        'Nothing staged to commit.',
      );
      expect(
        GitService.commitFailureMessage(stderrForm),
        'Nothing staged to commit.',
      );
    });

    test('identity unknown', () {
      final result = const GitResult(
        128,
        '',
        'Author identity unknown\n\n*** Please tell me who you are.\n\n'
            'unable to auto-detect email address',
        false,
        false,
      );
      expect(
        GitService.commitFailureMessage(result),
        'Git identity unknown — set user.name and user.email.',
      );
    });

    test('a hook failure shows the hook\'s first output line', () {
      final result = const GitResult(
        1,
        '',
        'hook says: nope\nmore detail\n',
        false,
        false,
      );
      expect(GitService.commitFailureMessage(result), 'hook says: nope');
    });

    test('no output at all still says something', () {
      final result = const GitResult(128, '', '', false, false);
      expect(
        GitService.commitFailureMessage(result),
        'git commit failed (exit 128).',
      );
    });
  });

  test(
    'a multi-line Persian message round-trips exactly through a real commit',
    () async {
      final repository = await _newRepo();
      final service = GitService();
      final root = repository.path;

      await File('$root/second.txt').writeAsString('دو\n');
      expect((await service.stage(root, <String>['second.txt'])).succeeded,
          isTrue);

      const message = 'subject: سلام دنیا\n\nاین بدنه‌ی پیام است\n'
          'خط دوم پیام\n';
      final result = await service.commit(root, message);
      expect(result.succeeded, isTrue, reason: result.stderr);

      final log = await Process.run(
        'git',
        const <String>['log', '-1', '--format=%B'],
        workingDirectory: root,
        stdoutEncoding: utf8,
      );
      expect(log.exitCode, 0);
      // `%B` prints the raw message; `--format` appends one newline of its
      // own, so the exact round-trip is message + '\n'.
      expect(log.stdout, '$message\n');
    },
    skip: skip,
  );

  test(
    'a failing pre-commit hook leaves the files staged and reports its error',
    () async {
      final repository = await _newRepo();
      final service = GitService();
      final root = repository.path;

      // A dedicated hooks directory set in the repository-local config, so a
      // globally configured core.hooksPath cannot swallow this hook.
      final hooksDir = Directory('${repository.parent.path}/hooks_g4');
      await hooksDir.create();
      addTearDown(() async {
        if (await hooksDir.exists()) await hooksDir.delete(recursive: true);
      });
      final hook = File('${hooksDir.path}/pre-commit');
      await hook.writeAsString('#!/bin/sh\necho "hook says: nope" >&2\nexit 1\n');
      await Process.run('chmod', <String>['+x', hook.path]);
      await _git(repository, <String>[
        'config',
        'core.hooksPath',
        hooksDir.path,
      ]);

      await File('$root/hooked.txt').writeAsString('x\n');
      expect((await service.stage(root, <String>['hooked.txt'])).succeeded,
          isTrue);

      final result = await service.commit(root, 'should not land\n');
      expect(result.succeeded, isFalse);
      expect(result.exitCode, 1);
      expect('${result.stdout}${result.stderr}', contains('hook says: nope'));
      expect(
        GitService.commitFailureMessage(result),
        'hook says: nope',
      );

      // The staged files are untouched by the failed commit.
      final changes = await service.status(root);
      final entry = changes.firstWhere((c) => c.path == 'hooked.txt');
      expect(entry.isStaged, isTrue);
      // And nothing was committed:
      final log = await Process.run(
        'git',
        const <String>['log', '-1', '--format=%s'],
        workingDirectory: root,
      );
      expect(log.stdout, 'first\n');
    },
    skip: skip,
  );

  test(
    'committing with nothing staged fails and maps to one clear line',
    () async {
      final repository = await _newRepo();
      final service = GitService();
      final root = repository.path;

      final result = await service.commit(root, 'nothing to commit\n');
      expect(result.succeeded, isFalse);
      expect(
        GitService.commitFailureMessage(result),
        'Nothing staged to commit.',
      );
    },
    skip: skip,
  );

  test(
    'a missing identity is reported as unset and local writes stay local',
    () async {
      // An unborn branch with no identity anywhere: an empty HOME (and no
      // XDG dir) means git has no global identity to fall back on.
      final emptyHome = await _tempDir('cce_git_home_');
      final repository = await _newRepo(withIdentity: false, withCommit: false);
      final service = GitService(
        environment: <String, String>{'HOME': emptyHome.path},
      );
      final root = repository.path;

      expect(await service.configValue(root, 'user.name'), isNull);
      expect(await service.configValue(root, 'user.email'), isNull);

      final nameResult = await service.setLocalConfig(
        root,
        'user.name',
        'Local User',
      );
      expect(nameResult.succeeded, isTrue, reason: nameResult.stderr);
      final emailResult = await service.setLocalConfig(
        root,
        'user.email',
        'local@example.com',
      );
      expect(emailResult.succeeded, isTrue, reason: emailResult.stderr);

      // The values read back — and they live in the repository-local config.
      expect(await service.configValue(root, 'user.name'), 'Local User');
      expect(await service.configValue(root, 'user.email'),
          'local@example.com');
      final local = await Process.run(
        'git',
        const <String>['config', '--local', '--get', 'user.name'],
        workingDirectory: root,
      );
      expect(local.stdout, 'Local User\n');

      // Nothing was written to the (empty) HOME, i.e. no --global write.
      expect(File('${emptyHome.path}/.gitconfig').existsSync(), isFalse);
    },
    skip: skip,
  );

  test('setLocalConfig refuses keys outside the commit identity', () async {
    final runner = _RecordingRunner();
    final service = _fakeService(runner);

    final result = await service.setLocalConfig('/repo', 'core.hooksPath', 'x');

    expect(result.succeeded, isFalse);
    expect(runner.arguments, isNull, reason: 'no git process may be started');
  });
}
