// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/syntax_scheme.dart';

/// The editor fonts offered by View > Font.
///
/// [id] is what `editor_settings.json` stores, so renaming a label (or even the
/// Flutter family) can never invalidate a user's saved choice. [fontFamily] is
/// the name Flutter resolves: Menlo is a macOS system font used by its real
/// family name, while the bundled Recursive faces live under our own alias so
/// the lookup never depends on a family installed on the host.
///
/// Measured line heights (see `test/ui/editor/editor_font_measure_test.dart`)
/// are 12/19/47 px at sizes 8/13/32 for both, which is exactly what
/// `EditorMetrics.lineHeight` predicts.
///
/// Monaco is **not** offered: it has no real bold/italic (both are synthesized),
/// and its metrics made the row height depend on the fallback font of a Persian
/// glyph. A file that still says `"fontFamily": "monaco"` resolves to [menlo]
/// through [fromId]'s fallback, so no user is left without a font.
enum EditorFontFamily {
  menlo('menlo', 'Menlo', 'Menlo'),
  recursive('recursive', 'Recursive Mono Casual', 'RecursiveMonoCasual');

  const EditorFontFamily(this.id, this.label, this.fontFamily);

  /// Stable id persisted in `editor_settings.json`.
  final String id;

  /// Label shown in the View menu.
  final String label;

  /// Family name Flutter resolves to a real font.
  final String fontFamily;

  /// Resolves a persisted [id].
  ///
  /// Anything unknown - a corrupt file, a font removed in a later version (e.g.
  /// the retired `monaco`), an old file with no key at all - falls back to
  /// [menlo], the default the editor has always used.
  static EditorFontFamily fromId(Object? id) {
    for (final family in values) {
      if (family.id == id) return family;
    }
    return menlo;
  }
}

/// Service that manages editor font size and family with persistence.
class EditorSettingsService extends ChangeNotifier {
  static const double minFontSize = 8;
  static const double maxFontSize = 32;
  static const double defaultFontSize = 13;
  static const double fontSizeStep = 1;

  static final EditorSettingsService instance =
      EditorSettingsService._internal();

  EditorSettingsService._internal({
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider {
    _load();
  }

  @visibleForTesting
  EditorSettingsService.forTesting({
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider,
       _fontSize = defaultFontSize {
    // Testing constructor: does not call load() automatically
    // so tests can inject state before loading if needed.
    // To match production behavior, tests may call load() explicitly.
  }

  final Future<Directory> Function()? _directoryProvider;
  double _fontSize = defaultFontSize;
  EditorFontFamily _fontFamily = EditorFontFamily.menlo;
  SyntaxScheme _syntaxScheme = SyntaxScheme.standard;
  bool _restoreTabsOnLaunch = false;

  double get fontSize => _fontSize;

  /// The editor font selected in View > Font.
  EditorFontFamily get fontFamily => _fontFamily;

  /// The palette selected in View > Syntax Colors (shared by all four themes).
  SyntaxScheme get syntaxScheme => _syntaxScheme;

  /// Whether a launch reopens the tabs saved in `session.json`.
  ///
  /// Off by default: a fresh install must start with one empty editor, not
  /// whatever the last session happened to have open.
  bool get restoreTabsOnLaunch => _restoreTabsOnLaunch;

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

  void setFontFamily(EditorFontFamily v) {
    if (_fontFamily == v) return; // notify ONLY on change
    _fontFamily = v;
    notifyListeners();
    _save();
  }

  /// Switches the syntax palette; listeners (the editor) repaint immediately.
  void setSyntaxScheme(SyntaxScheme v) {
    if (_syntaxScheme == v) return; // notify ONLY on change
    _syntaxScheme = v;
    notifyListeners();
    _save();
  }

  /// Turns tab restoring on or off; saved immediately.
  void setRestoreTabsOnLaunch(bool v) {
    if (_restoreTabsOnLaunch == v) return; // notify ONLY on change
    _restoreTabsOnLaunch = v;
    notifyListeners();
    _save();
  }

  Future<void> load() => _load();

  static const String _fileName = 'editor_settings.json';

  /// Settings file resolved once, so a save no longer has to await the
  /// directory provider on every write.
  File? _cachedFile;

  Future<File> get _settingsFile async {
    final cached = _cachedFile;
    if (cached != null) return cached;

    final File file;
    if (_directoryProvider != null) {
      final dir = await _directoryProvider();
      file = File('${dir.path}/$_fileName');
    } else {
      final dir = await getApplicationSupportDirectory();
      file = File('${dir.path}/$_fileName');
    }
    _cachedFile = file;
    return file;
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

      // An old file has no `fontFamily` key at all, and a corrupt or unknown
      // value must never leave the editor without a font: both land on Menlo.
      final family = EditorFontFamily.fromId(data['fontFamily']);
      if (_fontFamily != family) {
        _fontFamily = family;
        notifyListeners();
      }

      // Same rules for the palette: a missing key (older settings file) or a
      // corrupt/unknown id resolves to Standard rather than leaving the editor
      // in an undefined state.
      final scheme = SyntaxScheme.fromId(data['syntaxScheme']);
      if (_syntaxScheme != scheme) {
        _syntaxScheme = scheme;
        notifyListeners();
      }

      // Missing (older settings file), corrupt or unknown -> OFF: only an
      // explicit `true` opts back into restoring tabs.
      final restore = data['restoreTabsOnLaunch'] is bool &&
          data['restoreTabsOnLaunch'] == true;
      if (_restoreTabsOnLaunch != restore) {
        _restoreTabsOnLaunch = restore;
        notifyListeners();
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
      final content = jsonEncode({
        'fontSize': _fontSize,
        'fontFamily': _fontFamily.id,
        'syntaxScheme': _syntaxScheme.id,
        'restoreTabsOnLaunch': _restoreTabsOnLaunch,
      });
      final cached = _cachedFile;
      if (cached != null) {
        // The path is already known (load() or an earlier save resolved it), so
        // write synchronously: an async write could otherwise land *after* the
        // next caller has replaced the file, which made save/load round-trips
        // order-dependent.
        cached.writeAsStringSync(content);
        return;
      }
      final file = await _settingsFile;
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('EditorSettingsService save error: $e');
    }
  }
}
