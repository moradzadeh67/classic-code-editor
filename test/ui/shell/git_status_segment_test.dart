import 'package:classic_code_editor/models/git_models.dart';
import 'package:classic_code_editor/services/git_controller.dart';
import 'package:classic_code_editor/services/git_service.dart';
import 'package:classic_code_editor/services/theme_service.dart';
import 'package:classic_code_editor/ui/shell/retro_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [GitService] whose four reads return canned answers, so the segment text
/// can be driven without a repository on disk.
class _FakeGitService extends GitService {
  _FakeGitService({this.info, this.changes = const <GitChange>[]});

  GitRepoInfo? info;
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
      info;

  @override
  Future<List<GitChange>> status(String root, {GitCancelToken? cancel}) async =>
      changes;
}

GitRepoInfo _info({
  String branch = 'main',
  bool isDetached = false,
  String? upstream = 'origin/main',
  int ahead = 0,
  int behind = 0,
}) => GitRepoInfo(
  root: '/repo',
  branch: branch,
  isDetached: isDetached,
  hasCommits: true,
  upstream: upstream,
  ahead: ahead,
  behind: behind,
  remotes: const <GitRemote>[],
);

GitChange _change(String path) =>
    GitChange(path: path, indexStatus: ' ', worktreeStatus: 'M');

Widget _wrap(GitController controller) {
  return MaterialApp(
    home: Scaffold(body: RetroStatusBar(gitController: controller)),
  );
}

/// Builds a controller already pointing at a repository, without leaving the
/// debounce timer armed.
Future<GitController> _ready(_FakeGitService service, String? folder) async {
  final controller = GitController(service: service);
  controller.setExplorerFolder(folder);
  await controller.refreshNow();
  return controller;
}

void main() {
  testWidgets('shows the branch and the changed-file count', (tester) async {
    final service = _FakeGitService(
      info: _info(ahead: 1, behind: 2),
      changes: <GitChange>[
        _change('a.txt'),
        _change('b.txt'),
        _change('c.txt'),
      ],
    );
    final controller = await _ready(service, '/repo');

    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(find.byKey(kGitSegmentKey), findsOneWidget);
    expect(find.text('⎇ main ● 3 ↑1 ↓2'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('a detached HEAD shows the short sha', (tester) async {
    final service = _FakeGitService(
      info: _info(branch: 'abc1234', isDetached: true, upstream: null),
    );
    final controller = await _ready(service, '/repo');

    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(find.text('⎇ abc1234'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('the segment is absent with no repository', (tester) async {
    final service = _FakeGitService();
    final controller = await _ready(service, null);

    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    expect(find.byKey(kGitSegmentKey), findsNothing);

    controller.dispose();
  });

  testWidgets('the segment fits every theme without overflow', (tester) async {
    final service = _FakeGitService(
      info: _info(ahead: 1, behind: 2),
      changes: <GitChange>[
        _change('a.txt'),
        _change('b.txt'),
        _change('c.txt'),
      ],
    );
    final controller = await _ready(service, '/repo');

    addTearDown(() {
      ThemeService.instance.switchTheme(ThemeType.vc6);
    });

    await tester.pumpWidget(_wrap(controller));
    for (final theme in ThemeType.values) {
      ThemeService.instance.switchTheme(theme);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(kGitSegmentTextKey), findsOneWidget);
    }

    controller.dispose();
  });

  testWidgets('tapping the segment asks the shell for Source Control', (
    tester,
  ) async {
    final service = _FakeGitService(info: _info());
    final controller = await _ready(service, '/repo');

    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RetroStatusBar(
            gitController: controller,
            onGitSegmentTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(kGitSegmentKey));
    await tester.pump();

    expect(taps, 1);

    controller.dispose();
  });
}
