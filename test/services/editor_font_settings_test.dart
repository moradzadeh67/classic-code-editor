import 'dart:convert';
import 'dart:io';

import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// R1: the font choice is persisted next to `fontSize` as a stable id, and any
/// value the app cannot understand must fall back to Menlo - the editor must
/// never end up with no font at all.
void main() {
  group('EditorFontFamily', () {
    test('ids are the stable strings written to disk', () {
      expect(EditorFontFamily.menlo.id, 'menlo');
      expect(EditorFontFamily.recursive.id, 'recursive');
      expect(EditorFontFamily.values, hasLength(2));
    });

    test('resolved family names are the ones Flutter looks up', () {
      // Menlo keeps its real system family name; the bundled faces use our own
      // alias so the lookup cannot depend on what is installed.
      expect(EditorFontFamily.menlo.fontFamily, 'Menlo');
      expect(EditorFontFamily.recursive.fontFamily, 'RecursiveMonoCasual');
    });

    test('the retired monaco id resolves to menlo', () {
      // A file written while Monaco was still offered (or hand-edited) must
      // never leave the editor without a font.
      expect(EditorFontFamily.fromId('monaco'), EditorFontFamily.menlo);
      expect(EditorFontFamily.fromId('Monaco'), EditorFontFamily.menlo);
    });

    test('fromId round-trips every id', () {
      for (final family in EditorFontFamily.values) {
        expect(EditorFontFamily.fromId(family.id), family);
      }
    });

    test('fromId maps anything unknown or corrupt to menlo', () {
      for (final bad in <Object?>[
        null,
        '',
        'MENLO',
        'comic-sans',
        'RecursiveMonoCasual',
        42,
        <String>['menlo'],
      ]) {
        expect(
          EditorFontFamily.fromId(bad),
          EditorFontFamily.menlo,
          reason: 'unknown id $bad must fall back to Menlo',
        );
      }
    });

    test('menlo stays the default and the enum starts with it', () {
      expect(EditorFontFamily.values.first, EditorFontFamily.menlo);
    });
  });

  group('EditorSettingsService font family', () {
    late Directory tempDir;
    late EditorSettingsService service;

    Future<File> settingsFile() async =>
        File('${tempDir.path}/editor_settings.json');

    Future<void> resetService() async {
      service = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      await service.load();
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('editor_font_settings');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Ignore cleanup errors.
      }
    });

    test('defaults to menlo', () async {
      await resetService();
      expect(service.fontFamily, EditorFontFamily.menlo);
    });

    test('setter notifies only on a real change', () async {
      await resetService();
      var notifications = 0;
      void listener() => notifications++;
      service.addListener(listener);
      addTearDown(() => service.removeListener(listener));

      service.setFontFamily(EditorFontFamily.recursive);
      expect(service.fontFamily, EditorFontFamily.recursive);
      expect(notifications, 1);

      // Same value again: no rebuild.
      service.setFontFamily(EditorFontFamily.recursive);
      expect(notifications, 1);

      service.setFontFamily(EditorFontFamily.menlo);
      expect(service.fontFamily, EditorFontFamily.menlo);
      expect(notifications, 2);
    });

    test('changing the family does not disturb the font size', () async {
      await resetService();
      service.setFontSize(20);
      service.setFontFamily(EditorFontFamily.recursive);
      expect(service.fontSize, 20);
      expect(service.fontFamily, EditorFontFamily.recursive);

      service.setFontSize(9);
      expect(service.fontFamily, EditorFontFamily.recursive);
    });

    test('persists both keys and round-trips through load()', () async {
      await resetService();
      service.setFontSize(18);
      service.setFontFamily(EditorFontFamily.recursive);
      // Save is fire-and-forget; let the write land.
      await Future<void>.delayed(Duration.zero);

      final raw = jsonDecode(
        await (await settingsFile()).readAsString(),
      ) as Map<String, dynamic>;
      expect(raw['fontSize'], 18);
      expect(raw['fontFamily'], 'recursive');

      final reloaded = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      await reloaded.load();
      expect(reloaded.fontFamily, EditorFontFamily.recursive);
      expect(reloaded.fontSize, 18);
    });

    test(
      'a file written before this feature has no key and stays menlo',
      () async {
        await resetService();
        await (await settingsFile()).writeAsString('{"fontSize": 16}');

        final reloaded = EditorSettingsService.forTesting(
          directoryProvider: () async => tempDir,
        );
        await reloaded.load();
        expect(reloaded.fontFamily, EditorFontFamily.menlo);
        expect(reloaded.fontSize, 16);
      },
    );

    test(
      'an unknown or corrupt family in the file falls back to menlo',
      () async {
        for (final raw in <String>[
          '{"fontSize": 14, "fontFamily": "wingdings"}',
          '{"fontSize": 14, "fontFamily": ""}',
          '{"fontSize": 14, "fontFamily": null}',
          '{"fontSize": 14, "fontFamily": 7}',
          '{"fontSize": 14, "fontFamily": {"id": "monaco"}}',
        ]) {
          await (await settingsFile()).writeAsString(raw);
          final reloaded = EditorSettingsService.forTesting(
            directoryProvider: () async => tempDir,
          );
          await reloaded.load();
          expect(
            reloaded.fontFamily,
            EditorFontFamily.menlo,
            reason: 'raw $raw must fall back to Menlo',
          );
          expect(reloaded.fontSize, 14, reason: 'the size is unaffected');
        }
      },
    );

    test('a corrupt file as a whole still leaves menlo', () async {
      await resetService();
      await (await settingsFile()).writeAsString('{not json at all');

      final reloaded = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      await reloaded.load();
      expect(reloaded.fontFamily, EditorFontFamily.menlo);
    });

    test('load notifies when the file selects a different family', () async {
      await (await settingsFile()).writeAsString('{"fontFamily": "recursive"}');
      final reloaded = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      var notifications = 0;
      void listener() => notifications++;
      reloaded.addListener(listener);
      addTearDown(() => reloaded.removeListener(listener));

      await reloaded.load();
      expect(reloaded.fontFamily, EditorFontFamily.recursive);
      expect(notifications, 1);
    });

    test('a file still selecting the retired monaco loads as menlo', () async {
      await (await settingsFile()).writeAsString('{"fontFamily": "monaco"}');
      final reloaded = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      await reloaded.load();
      expect(reloaded.fontFamily, EditorFontFamily.menlo);
    });
  });
}
