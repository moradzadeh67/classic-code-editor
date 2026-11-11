import 'dart:io';

import 'package:classic_code_editor/services/git_controller.dart';
import 'package:classic_code_editor/services/git_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage/unstage against a *real* repository in a temporary directory.
///
/// The unit tests use a fake service, so nothing there proves that the argument
/// lists handed to Git are the ones Git accepts. These tests run the actual
/// commands in a throwaway repository (never the project repository, never the
/// network) and skip when `git` is not installed.
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

/// A repository with a local identity, either with or without a first commit.
Future<Directory> _newRepo({required bool withCommit}) async {
  final directory = await _tempDir('cce_git_stage_');
  await _git(directory, <String>['init', '-b', 'main']);
  await _git(directory, <String>['config', 'user.name', 'Test User']);
  await _git(directory, <String>['config', 'user.email', 'test@example.com']);
  if (withCommit) {
    await File('${directory.path}/a.txt').writeAsString('one\n');
    await _git(directory, <String>['add', '--', 'a.txt']);
    await _git(directory, <String>['commit', '-m', 'first']);
  }
  return directory;
}

void main() {
  final skip = _gitInstalled() ? null : 'git is not installed';

  test('stage then unstage moves a file between index and worktree', () async {
    final repository = await _newRepo(withCommit: true);
    final service = GitService();
    final root = repository.path;

    await File('$root/b.txt').writeAsString('two\n');

    final staged = await service.stage(root, <String>['b.txt']);
    expect(staged.succeeded, isTrue, reason: staged.stderr);

    var changes = await service.status(root);
    expect(changes.map((c) => c.path), contains('b.txt'));
    expect(changes.firstWhere((c) => c.path == 'b.txt').isStaged, isTrue);

    final unstaged = await service.unstage(root, <String>[
      'b.txt',
    ], hasCommits: true);
    expect(unstaged.succeeded, isTrue, reason: unstaged.stderr);

    changes = await service.status(root);
    final entry = changes.firstWhere((c) => c.path == 'b.txt');
    expect(entry.isStaged, isFalse);
    expect(entry.isUntracked, isTrue);
  }, skip: skip);

  test(
    'unstage on an unborn branch removes the entry from the index',
    () async {
      // No commit yet: `git restore --staged` cannot work without HEAD, so the
      // `git rm --cached` path has to be taken.
      final repository = await _newRepo(withCommit: false);
      final service = GitService();
      final root = repository.path;

      await File('$root/first.txt').writeAsString('one\n');
      expect(
        (await service.stage(root, <String>['first.txt'])).succeeded,
        isTrue,
      );

      var changes = await service.status(root);
      expect(changes.firstWhere((c) => c.path == 'first.txt').isStaged, isTrue);

      final unstaged = await service.unstage(root, <String>[
        'first.txt',
      ], hasCommits: false);
      expect(unstaged.succeeded, isTrue, reason: unstaged.stderr);

      changes = await service.status(root);
      final entry = changes.firstWhere((c) => c.path == 'first.txt');
      expect(entry.isStaged, isFalse);
      expect(entry.isUntracked, isTrue);
    },
    skip: skip,
  );

  test('a Persian file name survives stage and unstage untouched', () async {
    const name = 'پیش‌نویس‌ها.txt';
    final repository = await _newRepo(withCommit: true);
    final service = GitService();
    final root = repository.path;

    await File('$root/$name').writeAsString('سلام\n');

    expect((await service.stage(root, <String>[name])).succeeded, isTrue);

    var changes = await service.status(root);
    expect(changes.map((c) => c.path), contains(name));

    expect(
      (await service.unstage(root, <String>[name], hasCommits: true)).succeeded,
      isTrue,
    );
    changes = await service.status(root);
    expect(changes.firstWhere((c) => c.path == name).isUntracked, isTrue);
  }, skip: skip);

  test(
    'a path that looks like an option is passed after the separator',
    () async {
      final repository = await _newRepo(withCommit: true);
      final service = GitService();
      final root = repository.path;

      // Without the `--` separator this would be read as a Git option.
      const name = '--amend.txt';
      await File('$root/$name').writeAsString('tricky\n');

      final staged = await service.stage(root, <String>[name]);
      expect(staged.succeeded, isTrue, reason: staged.stderr);
      expect((await service.status(root)).map((c) => c.path), contains(name));

      final unstaged = await service.unstage(root, <String>[
        name,
      ], hasCommits: true);
      expect(unstaged.succeeded, isTrue, reason: unstaged.stderr);
    },
    skip: skip,
  );

  test('the controller refreshes itself after stage and unstage', () async {
    final repository = await _newRepo(withCommit: false);
    final controller = GitController(service: GitService());
    addTearDown(controller.dispose);

    controller.setExplorerFolder(repository.path);
    await controller.refreshNow();
    expect(controller.hasRepo, isTrue);
    expect(
      controller.repoInfo?.hasCommits,
      isFalse,
      reason: 'the unborn branch must be detected',
    );

    await File('${repository.path}/tracked.txt').writeAsString('x\n');
    await controller.refreshNow();
    expect(controller.changeCount, 1);

    // Staging goes through the unborn-branch fallback and refreshes at once.
    final staged = await controller.stage(<String>['tracked.txt']);
    expect(staged.succeeded, isTrue, reason: staged.stderr);
    expect(controller.changes.single.isStaged, isTrue);

    final unstaged = await controller.unstage(<String>['tracked.txt']);
    expect(unstaged.succeeded, isTrue, reason: unstaged.stderr);
    expect(controller.changes.single.isStaged, isFalse);
    expect(controller.changes.single.isUntracked, isTrue);
  }, skip: skip);
}
