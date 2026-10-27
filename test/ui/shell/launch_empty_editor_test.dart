import 'dart:io';

import 'package:classic_code_editor/services/session_service.dart';
import 'package:classic_code_editor/ui/editor/tab_bar.dart';
import 'package:classic_code_editor/ui/shell/ide_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A launch always starts on one empty Untitled editor.
///
/// `session.json` still records the open tabs (and an older file may carry
/// `openPaths`/`activePath`), but nothing replays them any more: only the
/// explorer's folder and the recent-files list survive a restart.
void main() {
  testWidgets('a session with openPaths reopens no tab and starts empty', (
    tester,
  ) async {
    // Real file I/O inside testWidgets must run through runAsync, otherwise the
    // fake clock leaves the I/O future pending and the test hangs.
    late Directory tempDir;
    late File saved;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('launch_empty_test');
      saved = File('${tempDir.path}/main.dart')
        ..writeAsStringSync('void main() {}');

      // What the previous run left behind.
      SessionService.instance.saveSession(
        openPaths: [saved.path],
        activePath: saved.path,
      );
    });
    expect(SessionService.instance.openPaths, [saved.path]);

    // The shell warms up a language server, which spawns real processes; those
    // futures need the real clock too.
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: IDEShell()));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    // The saved file is not reopened...
    expect(find.text('main.dart'), findsNothing);
    // ...and the tab strip holds exactly one empty Untitled buffer.
    expect(find.byType(TabBarWidget), findsOneWidget);
    expect(find.text('Untitled'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Tear the shell down inside the test so its timers are gone before the
    // framework checks for pending timers.
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pump();

    await tester.runAsync(() async {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Already gone.
      }
    });
  });
}
