// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Service that manages editor font-size settings with persistence.
class EditorSettingsService extends ChangeNotifier {
  static const double minFontSize = 8;
  static const double maxFontSize = 32;
  static const double defaultFontSize = 13;
  static const double fontSizeStep = 1;

  static final EditorSettingsService instance = EditorSettingsService._internal();

  EditorSettingsService._internal({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider {
    _load();
  }

  @visibleForTesting
  EditorSettingsService.forTesting({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider,
        _fontSize = defaultFontSize {
    // Testing constructor: does not call load() automatically
    // so tests can inject state before loading if needed.
    // To match production behavior, tests may call load() explicitly.
  }

  final Future<Directory> Function()? _directoryProvider;
  double _fontSize = defaultFontSize;

  double get fontSize => _fontSize;

  bool get canIncrease => _fontSize < maxFontSize;

  bool get canDecrease => _fontSize > minFontSize;

  void increase() => setFontSize(_fontSize + fontSizeStep);

  void decrease() => setFontSize(_fontSize - fontSizeStep);

  void reset() => setFontSize(defaultFontSize);

  void setFontSize(double v) {
    final clamped = v.clamp(minFontSize, maxFontSize);
    if (_fontSize == clamped) return; // notify ONLY on change
    _fontSize = clamped;
    notifyListeners();
    _save();
  }

  Future<void> load() => _load();

  static const String _fileName = 'editor_settings.json';

  Future<File> get _settingsFile async {
    if (_directoryProvider != null) {
      final dir = await _directoryProvider();
      return File('${dir.path}/$_fileName');
    }
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> _load() async {
    // When FLUTTER_TEST is set and no directoryProvider is injected,
    // load is a no-op (same idea as DebuggerEnvironment).
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (isTest && _directoryProvider == null) return;

    try {
      final file = await _settingsFile;
      if (!await file.exists()) {
        // Missing file -> use default (already set), never throws.
        return;
      }
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final value = data['fontSize'];
      if (value is num) {
        final newValue = value.toDouble();
        // Set without notifying to avoid build cycles during init,
        // then save will occur separately if needed.
        final clamped = newValue.clamp(minFontSize, maxFontSize);
        if (_fontSize != clamped) {
          _fontSize = clamped;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('EditorSettingsService load error: $e');
      // Never throws; corrupt/missing JSON falls back to default.
    }
  }

  Future<void> _save() async {
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (isTest && _directoryProvider == null) return;

    try {
      final file = await _settingsFile;
      final content = jsonEncode({'fontSize': _fontSize});
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('EditorSettingsService save error: $e');
    }
  }
}
