import 'dart:io';

import 'package:classic_code_editor/services/git_controller.dart';
import 'package:classic_code_editor/services/git_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The end-to-end path with the *real* service: a temporary repository on disk
/// is read through `GitService` and surfaced as the status-bar label.
///
/// The unit tests use a canned service, so nothing there proves that the fields
/// the controller reads are the ones `GitService` actually fills in. This file
/// closes that gap with a genuine repository (and skips when `git` is not
/// installed, matching `git_service_test.dart`).
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

Future<Directory> _newRepo() async {
  final directory = await _tempDir('cce_git_ui_');
  await _git(directory, <String>['init', '-b', 'main']);
  await _git(directory, <String>['config', 'user.name', 'Test User']);
  await _git(directory, <String>['config', 'user.email', 'test@example.com']);
  return directory;
}

void main() {
  test(
    'a real repository reaches the segment as branch, count and arrows',
    () async {
      final repository = await _newRepo();
      await File('${repository.path}/a.txt').writeAsString('one\n');
      await _git(repository, <String>['add', '--', 'a.txt']);
      await _git(repository, <String>['commit', '-m', 'first']);

      final controller = GitController(service: GitService());
      addTearDown(controller.dispose);

      controller.setExplorerFolder(repository.path);
      await controller.refreshNow();

      expect(controller.isAvailable, isTrue);
      expect(controller.hasRepo, isTrue);
      expect(controller.statusLabel, '⎇ main');

      // An untracked file and a modification both count.
      await File('${repository.path}/b.txt').writeAsString('two\n');
      await File('${repository.path}/a.txt').writeAsString('one\nedited\n');

      await controller.refreshNow();

      expect(controller.statusLabel, '⎇ main ● 2');
      expect(controller.repoRoot, isNotNull);
      expect(controller.tooltipText, contains('upstream: no upstream'));
    },
    skip: _gitInstalled() ? false : 'git is not installed',
  );

  test('an ahead count against a real remote reaches the segment', () async {
    final bare = await _tempDir('cce_git_ui_bare_');
    await _git(bare, <String>['init', '--bare', '-b', 'main']);

    final clone = await _tempDir('cce_git_ui_clone_');
    final cloneResult = await Process.run('git', <String>[
      'clone',
      bare.path,
      clone.path,
    ]);
    if (cloneResult.exitCode != 0) {
      fail('git clone failed: ${cloneResult.stderr}');
    }
    await _git(clone, <String>['config', 'user.name', 'Test User']);
    await _git(clone, <String>['config', 'user.email', 'test@example.com']);

    await File('${clone.path}/a.txt').writeAsString('one\n');
    await _git(clone, <String>['add', '--', 'a.txt']);
    await _git(clone, <String>['commit', '-m', 'first']);
    await _git(clone, <String>['push', '-u', 'origin', 'main']);

    // Two local commits the upstream does not have.
    await File('${clone.path}/a.txt').writeAsString('two\n');
    await _git(clone, <String>['add', '--', 'a.txt']);
    await _git(clone, <String>['commit', '-m', 'second']);
    await File('${clone.path}/a.txt').writeAsString('three\n');
    await _git(clone, <String>['add', '--', 'a.txt']);
    await _git(clone, <String>['commit', '-m', 'third']);

    final controller = GitController(service: GitService());
    addTearDown(controller.dispose);

    controller.setExplorerFolder(clone.path);
    await controller.refreshNow();

    expect(controller.statusLabel, '⎇ main ↑2');
    expect(controller.tooltipText, contains('upstream: origin/main'));
    expect(controller.tooltipText, contains('origin:'));
  }, skip: _gitInstalled() ? false : 'git is not installed');

  test('a sub-folder of the repository resolves to its root', () async {
    final repository = await _newRepo();
    await File('${repository.path}/a.txt').writeAsString('one\n');
    await _git(repository, <String>['add', '--', 'a.txt']);
    await _git(repository, <String>['commit', '-m', 'first']);
    final sub = Directory('${repository.path}/lib/deep')
      ..createSync(recursive: true);

    final controller = GitController(service: GitService());
    addTearDown(controller.dispose);

    // No folder open: the active tab's directory is the only hint.
    controller.setActiveFilePath('${sub.path}/main.dart');
    await controller.refreshNow();

    expect(controller.statusLabel, '⎇ main');
    expect(controller.repoRoot, await repository.resolveSymbolicLinks());
  }, skip: _gitInstalled() ? false : 'git is not installed');

  test('a plain folder with no repository hides the segment', () async {
    final plain = await _tempDir('cce_git_ui_plain_');
    final controller = GitController(service: GitService());
    addTearDown(controller.dispose);

    controller.setExplorerFolder(plain.path);
    await controller.refreshNow();

    expect(controller.hasRepo, isFalse);
    expect(controller.statusLabel, isNull);
    // The read path created nothing in the folder.
    expect(plain.listSync(), isEmpty);
  }, skip: _gitInstalled() ? false : 'git is not installed');

  test('a detached HEAD shows the short SHA, not a branch', () async {
    final repository = await _newRepo();
    await File('${repository.path}/a.txt').writeAsString('one\n');
    await _git(repository, <String>['add', '--', 'a.txt']);
    await _git(repository, <String>['commit', '-m', 'first']);
    await _git(repository, <String>['checkout', '--detach']);

    final controller = GitController(service: GitService());
    addTearDown(controller.dispose);

    controller.setExplorerFolder(repository.path);
    await controller.refreshNow();

    final label = controller.statusLabel;
    expect(label, isNotNull);
    expect(label, startsWith('⎇ '));
    expect(
      label,
      isNot('⎇ main'),
      reason: 'a detached HEAD must not report the branch name',
    );
    expect(controller.tooltipText, contains('detached HEAD'));
  }, skip: _gitInstalled() ? false : 'git is not installed');
}
