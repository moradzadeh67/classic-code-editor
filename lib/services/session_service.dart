// The optional test seam mirrors EditorSettingsService: a nullable provider is
// assigned in the initializer list on purpose.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists open tabs and the list of recent files across restarts.
class SessionService extends ChangeNotifier {
  static final SessionService instance = SessionService._internal();

  SessionService._internal({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider {
    _load();
  }

  @visibleForTesting
  SessionService.forTesting({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider;

  final Future<Directory> Function()? _directoryProvider;

  List<String> _openPaths = [];
  String? _activePath;
  List<String> _recentFiles = [];
  String? _openFolderPath;

  List<String> get openPaths => List.unmodifiable(_openPaths);
  String? get activePath => _activePath;
  List<String> get recentFiles => List.unmodifiable(_recentFiles);

  /// Folder shown in the explorer, or null when none is open.
  String? get openFolderPath => _openFolderPath;

  /// The saved paths a launch should reopen.
  ///
  /// Restoring tabs is opt-in ([restoreTabsOnLaunch], the persisted
  /// `restoreTabsOnLaunch` setting): while it is off the app starts with a
  /// single empty editor and `session.json` is only written, never replayed.
  /// Even when it is on, a path that no longer exists on disk is skipped
  /// silently — a stale session must never fail a launch.
  List<String> pathsToRestore({required bool restoreTabsOnLaunch}) {
    if (!restoreTabsOnLaunch) return const <String>[];
    return [
      for (final path in _openPaths)
        if (File(path).existsSync()) path,
    ];
  }

  /// Remembers (or forgets) the explorer's folder.
  void setOpenFolderPath(String? path) {
    final exists = path != null && Directory(path).existsSync();
    final next = exists ? path : null;
    if (next == _openFolderPath) return;
    _openFolderPath = next;
    notifyListeners();
    _save();
  }

  static const String _fileName = 'session.json';
  File? _cachedFile;

  Future<File> get _sessionFile async {
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

  void saveSession({
    required List<String> openPaths,
    required String? activePath,
  }) {
    _openPaths = openPaths.where((p) => File(p).existsSync()).toList();
    _activePath = (activePath != null && File(activePath).existsSync())
        ? activePath
        : null;

    for (final path in _openPaths) {
      addRecentFile(path, saveNow: false);
    }
    _save();
  }

  void addRecentFile(String filePath, {bool saveNow = true}) {
    if (filePath.isEmpty || !File(filePath).existsSync()) return;

    _recentFiles.remove(filePath);
    _recentFiles.insert(0, filePath);
    if (_recentFiles.length > 10) {
      _recentFiles = _recentFiles.sublist(0, 10);
    }

    notifyListeners();
    if (saveNow) _save();
  }

  /// Drops one entry (used when the file no longer exists on disk).
  void removeRecentFile(String filePath) {
    if (!_recentFiles.contains(filePath)) return;
    _recentFiles.remove(filePath);
    notifyListeners();
    _save();
  }

  void clearRecentFiles() {
    _recentFiles.clear();
    notifyListeners();
    _save();
  }

  Future<void> load() => _load();

  Future<void> _load() async {
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (isTest && _directoryProvider == null) return;

    try {
      final file = await _sessionFile;
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      if (data['openPaths'] is List) {
        _openPaths = (data['openPaths'] as List)
            .cast<String>()
            .where((p) => File(p).existsSync())
            .toList();
      }

      if (data['activePath'] is String) {
        final path = data['activePath'] as String;
        _activePath = File(path).existsSync() ? path : null;
      }

      if (data['openFolderPath'] is String) {
        final path = data['openFolderPath'] as String;
        _openFolderPath = Directory(path).existsSync() ? path : null;
      }

      if (data['recentFiles'] is List) {
        _recentFiles = (data['recentFiles'] as List)
            .cast<String>()
            .where((p) => File(p).existsSync())
            .take(10)
            .toList();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('SessionService load error: $e');
    }
  }

  void _save() async {
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (isTest && _directoryProvider == null) return;

    try {
      final data = {
        'openPaths': _openPaths,
        'activePath': _activePath,
        'recentFiles': _recentFiles,
        'openFolderPath': _openFolderPath,
      };
      final content = jsonEncode(data);

      final cached = _cachedFile;
      if (cached != null) {
        cached.writeAsStringSync(content);
        return;
      }
      final file = await _sessionFile;
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('SessionService save error: $e');
    }
  }
}
