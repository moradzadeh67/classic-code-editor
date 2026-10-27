import 'dart:io';

import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionService', () {
    late Directory tempDir;
    late SessionService service;

    Future<SessionService> fresh() async {
      final instance = SessionService.forTesting(
        directoryProvider: () async => tempDir,
      );
      await instance.load();
      return instance;
    }

    File file(String name) {
      final file = File('${tempDir.path}/$name');
      file.writeAsStringSync('// $name');
      return file;
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('session_service_test');
      service = await fresh();
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // The temp folder may already be gone on CI; nothing to clean up.
      }
    });

    test('save/load roundtrip keeps paths and the active file', () async {
      final a = file('a.dart');
      final b = file('b.dart');

      service.saveSession(openPaths: [a.path, b.path], activePath: b.path);

      final reloaded = await fresh();
      expect(reloaded.openPaths, [a.path, b.path]);
      expect(reloaded.activePath, b.path);
    });

    test('missing files are skipped on save', () async {
      final a = file('a.dart');
      service.saveSession(
        openPaths: [a.path, '${tempDir.path}/gone.dart'],
        activePath: '${tempDir.path}/gone.dart',
      );

      final reloaded = await fresh();
      expect(reloaded.openPaths, [a.path]);
      expect(reloaded.activePath, isNull);
    });

    test('recent files are de-duplicated and capped at 10', () async {
      final files = [for (var i = 0; i < 12; i++) file('f$i.dart')];
      for (final f in files) {
        service.addRecentFile(f.path);
      }
      // Re-adding an existing entry moves it to the front.
      service.addRecentFile(files[5].path);

      final recent = service.recentFiles;
      expect(recent.length, 10);
      expect(recent.first, files[5].path);
      expect(recent.toSet().length, recent.length);
    });

    test('recent entries for missing files are dropped', () async {
      final a = file('a.dart');
      service.addRecentFile(a.path);
      a.deleteSync();

      final reloaded = await fresh();
      expect(reloaded.recentFiles, isEmpty);
    });

    test('clearRecentFiles empties the list', () async {
      service.addRecentFile(file('a.dart').path);
      expect(service.recentFiles, isNotEmpty);
      service.clearRecentFiles();
      expect(service.recentFiles, isEmpty);
    });

    test('pathsToRestore is empty while restoring is OFF', () async {
      final a = file('a.dart');
      final b = file('b.dart');
      service.saveSession(openPaths: [a.path, b.path], activePath: a.path);

      final reloaded = await fresh();
      expect(reloaded.pathsToRestore(restoreTabsOnLaunch: false), isEmpty);
    });

    test('pathsToRestore returns the saved files when restoring is ON',
        () async {
      final a = file('a.dart');
      final b = file('b.dart');
      service.saveSession(openPaths: [a.path, b.path], activePath: a.path);

      final reloaded = await fresh();
      expect(reloaded.pathsToRestore(restoreTabsOnLaunch: true), [
        a.path,
        b.path,
      ]);
    });

    test('pathsToRestore skips a file that no longer exists, without error',
        () async {
      final a = file('a.dart');
      final b = file('b.dart');
      service.saveSession(openPaths: [a.path, b.path], activePath: a.path);
      b.deleteSync();

      final reloaded = await fresh();
      expect(reloaded.pathsToRestore(restoreTabsOnLaunch: true), [a.path]);
    });

    /// The launch contract `IDEShell._restoreSession` implements: reopen what
    /// [SessionService.pathsToRestore] allows, then never leave the tab strip
    /// empty.
    Future<FileService> launch({required bool restoreTabsOnLaunch}) async {
      final session = await fresh();
      final fileService = FileService();
      addTearDown(fileService.dispose);

      for (final path in session.pathsToRestore(
        restoreTabsOnLaunch: restoreTabsOnLaunch,
      )) {
        final file = File(path);
        if (!file.existsSync()) continue;
        fileService.restoreFile(path, await file.readAsString());
      }
      if (fileService.openTabs.isEmpty) fileService.createNewFile();
      return fileService;
    }

    test('a launch with the setting OFF starts on one empty Untitled tab',
        () async {
      final a = file('a.dart');
      final b = file('b.dart');
      service.saveSession(openPaths: [a.path, b.path], activePath: a.path);

      final fileService = await launch(restoreTabsOnLaunch: false);

      expect(fileService.openTabs, hasLength(1));
      expect(fileService.openTabs.single.filePath, isNull);
      expect(fileService.openTabs.single.fileName, 'Untitled');
      expect(fileService.activeTab!.content, isEmpty);
    });

    test('a launch with the setting ON restores the saved tabs', () async {
      final a = file('a.dart');
      final b = file('b.dart');
      service.saveSession(openPaths: [a.path, b.path], activePath: a.path);

      final fileService = await launch(restoreTabsOnLaunch: true);

      expect(
        [for (final tab in fileService.openTabs) tab.filePath],
        [a.path, b.path],
      );
    });

    test('a launch with the setting ON skips a missing file silently',
        () async {
      final a = file('a.dart');
      final b = file('b.dart');
      service.saveSession(openPaths: [a.path, b.path], activePath: a.path);
      b.deleteSync();

      final fileService = await launch(restoreTabsOnLaunch: true);

      expect(
        [for (final tab in fileService.openTabs) tab.filePath],
        [a.path],
      );
    });

    test('corrupt JSON falls back to an empty session', () async {
      File('${tempDir.path}/session.json').writeAsStringSync('{not json');

      final reloaded = await fresh();
      expect(reloaded.openPaths, isEmpty);
      expect(reloaded.activePath, isNull);
      expect(reloaded.recentFiles, isEmpty);
    });
  });
}
