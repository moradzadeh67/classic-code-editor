import 'dart:io';

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

    test('corrupt JSON falls back to an empty session', () async {
      File('${tempDir.path}/session.json').writeAsStringSync('{not json');

      final reloaded = await fresh();
      expect(reloaded.openPaths, isEmpty);
      expect(reloaded.activePath, isNull);
      expect(reloaded.recentFiles, isEmpty);
    });
  });
}
