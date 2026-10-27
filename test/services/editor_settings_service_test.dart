import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';

void main() {
  group('EditorSettingsService', () {
    late Directory tempDir;
    late EditorSettingsService service;

    Future<void> resetService() async {
      // Create a fresh service with injected temp directory.
      service = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      // Explicitly load (testing constructor does not auto-start).
      await service.load();
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('editor_settings_test');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Ignore cleanup errors.
      }
      // Also reset singleton state for isolation if needed.
    });

    test('defaults are at 13, clamp range 8..32, step 1', () {
      expect(EditorSettingsService.defaultFontSize, 13);
      expect(EditorSettingsService.minFontSize, 8);
      expect(EditorSettingsService.maxFontSize, 32);
      expect(EditorSettingsService.fontSizeStep, 1);
    });

    test('clamp at min/max and notify only on change', () async {
      await resetService();
      final listenerCalled = <bool>[];
      service.addListener(() => listenerCalled.add(true));

      service.setFontSize(8);
      expect(service.fontSize, 8);
      expect(listenerCalled, hasLength(1));

      // Same value: no notification.
      listenerCalled.clear();
      service.setFontSize(8);
      expect(service.fontSize, 8);
      expect(listenerCalled, isEmpty);

      service.setFontSize(32);
      expect(service.fontSize, 32);
      expect(listenerCalled, hasLength(1));

      service.setFontSize(5); // below min -> clamped to 8
      expect(service.fontSize, 8);
      expect(listenerCalled, hasLength(2));

      service.setFontSize(40); // above max -> clamped to 32
      expect(service.fontSize, 32);
      expect(listenerCalled, hasLength(3));
    });

    test('increase, decrease, reset', () async {
      await resetService();
      expect(service.fontSize, 13);
      service.increase();
      expect(service.fontSize, 14);
      service.decrease();
      expect(service.fontSize, 13);
      service.increase();
      service.increase();
      expect(service.fontSize, 15);
      service.reset();
      expect(service.fontSize, 13);
    });

    test('canIncrease and canDecrease reflect clamped state', () async {
      await resetService();
      service.setFontSize(8);
      expect(service.canDecrease, isFalse);
      expect(service.canIncrease, isTrue);
      service.setFontSize(32);
      expect(service.canIncrease, isFalse);
      expect(service.canDecrease, isTrue);
    });

    test('save -> load roundtrip', () async {
      await resetService();
      service.setFontSize(20);
      // Save is fire-and-forget; await briefly.
      await Future<void>.delayed(Duration.zero);
      // Create a new service pointing at the same directory to simulate reload.
      final reloaded = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      await reloaded.load();
      expect(reloaded.fontSize, 20);
    });

    test('corrupt JSON -> default 13', () async {
      await resetService();
      service.setFontSize(25);
      await Future<void>.delayed(Duration.zero);
      // Overwrite file with corrupt JSON.
      final file = File('${tempDir.path}/editor_settings.json');
      await file.writeAsString('not json');
      final reloaded = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      await reloaded.load();
      expect(reloaded.fontSize, 13);
    });

    test('out-of-range stored value -> clamped', () async {
      await resetService();
      final file = File('${tempDir.path}/editor_settings.json');
      await file.writeAsString('{"fontSize": 100}');
      final reloaded = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      await reloaded.load();
      expect(reloaded.fontSize, 32);

      await file.writeAsString('{"fontSize": -5}');
      final reloadedLow = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      await reloadedLow.load();
      expect(reloadedLow.fontSize, 8);
    });

    test('restoreTabsOnLaunch defaults to OFF', () async {
      await resetService();
      expect(service.restoreTabsOnLaunch, isFalse);
    });

    test('restoreTabsOnLaunch saves and loads back', () async {
      await resetService();
      service.setRestoreTabsOnLaunch(true);
      await Future<void>.delayed(Duration.zero);

      final reloaded = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      await reloaded.load();
      expect(reloaded.restoreTabsOnLaunch, isTrue);

      reloaded.setRestoreTabsOnLaunch(false);
      await Future<void>.delayed(Duration.zero);
      final again = EditorSettingsService.forTesting(
        directoryProvider: () async => tempDir,
      );
      await again.load();
      expect(again.restoreTabsOnLaunch, isFalse);
    });

    test('corrupt or unknown restoreTabsOnLaunch -> OFF', () async {
      final file = File('${tempDir.path}/editor_settings.json');
      for (final value in ['yes', '1', 'null', '{}', '"true"']) {
        await file.writeAsString('{"restoreTabsOnLaunch": $value}');
        final reloaded = EditorSettingsService.forTesting(
          directoryProvider: () async => tempDir,
        );
        await reloaded.load();
        expect(
          reloaded.restoreTabsOnLaunch,
          isFalse,
          reason: 'value $value must fall back to OFF',
        );
      }
    });

    test(
      'load/save are no-ops under FLUTTER_TEST without directoryProvider',
      () async {
        // When FLUTTER_TEST is set and no directoryProvider is injected,
        // load/save must not throw and must leave fontSize unchanged.
        // We simulate by creating the singleton directly (without provider)
        // and calling load; it should return without error.
        // Note: if running inside flutter test, the singleton may have been
        // initialized already; we test the no-op behavior by injecting a
        // provider and then simulating the guard condition explicitly.
        // The simpler test: call load on a service with no provider under test.
        // Because the singleton instance exists, we create forTesting without provider.
        final noProvider = EditorSettingsService.forTesting(
          directoryProvider: null,
        );
        // Under FLUTTER_TEST (this environment), load should be a no-op.
        await noProvider.load();
        expect(noProvider.fontSize, 13);
      },
    );
  });
}
