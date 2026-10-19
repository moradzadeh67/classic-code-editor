import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/language_config.dart';
import '../models/tab_file.dart';

class FileService extends ChangeNotifier {
  final List<TabFile> _openTabs = [];
  int _activeTabIndex = -1;

  List<TabFile> get openTabs => _openTabs;
  int get activeTabIndex => _activeTabIndex;

  TabFile? get activeTab =>
      (_activeTabIndex >= 0 && _activeTabIndex < _openTabs.length)
      ? _openTabs[_activeTabIndex]
      : null;

  String? get currentFilePath => activeTab?.filePath;

  String get fileName => activeTab?.fileName ?? 'Untitled';

  String get fileContent => activeTab?.content ?? '';

  bool get isModified => activeTab?.isModified ?? false;

  /// Creates a new untitled tab for editing, making it the active tab.
  void createNewFile() {
    _openTabs.add(TabFile(fileName: 'Untitled', content: ''));
    _activeTabIndex = _openTabs.length - 1;
    notifyListeners();
  }

  Future<void> openFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dart', 'c', 'cpp', 'py', 's'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);
        final content = await file.readAsString();
        openFilePath(filePath, content);
      }
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
  }

  /// Opens a file from an already-resolved [filePath] and [content].
  ///
  /// Reuses an existing tab when the file is already open, otherwise appends
  /// a new one and makes it active. Exposed separately from [openFile] so it
  /// can be driven from tests without invoking the platform file picker.
  /// Re-opens a file that was open in the previous session (no picker, no
  /// dialog), reusing its tab when it is already open.
  void restoreFile(String filePath, String content) {
    openFilePath(filePath, content);
  }

  @visibleForTesting
  void openFilePath(String filePath, String content) {
    final name = filePath.split('/').last;

    // Check if file is already open
    final existingIndex = _openTabs.indexWhere(
      (tab) => tab.filePath == filePath,
    );
    if (existingIndex >= 0) {
      _activeTabIndex = existingIndex;
    } else {
      final newTab = TabFile(
        filePath: filePath,
        fileName: name,
        content: content,
      );
      _openTabs.add(newTab);
      _activeTabIndex = _openTabs.length - 1;
    }
    notifyListeners();
  }

  void closeTab(int index) {
    if (index < 0 || index >= _openTabs.length) return;

    _openTabs.removeAt(index);

    if (_openTabs.isEmpty) {
      _activeTabIndex = -1;
    } else if (_activeTabIndex >= index) {
      _activeTabIndex = (_activeTabIndex - 1).clamp(0, _openTabs.length - 1);
    }
    notifyListeners();
  }

  void switchTab(int index) {
    if (index >= 0 && index < _openTabs.length && index != _activeTabIndex) {
      _activeTabIndex = index;
      notifyListeners();
    }
  }

  Future<String> _formatCode(String content, String? filePath) async {
    final config = LanguageConfig.fromExtension(filePath);
    if (config.formatCommand == null) return content;

    try {
      if (config.extension == '.dart') {
        // `dart` from PATH, NOT Platform.resolvedExecutable: inside a packaged
        // macOS app the latter is the app binary itself, so saving a .dart file
        // launched a second copy of the IDE (the empty black window) and the
        // formatted text came from a process that had never formatted anything.
        final process = await Process.start('dart', [
          'format',
          '--output=show',
        ]);
        process.stdin.write(content);
        await process.stdin.close();

        final result = await process.stdout.transform(utf8.decoder).join();
        final exitCode = await process.exitCode;

        if (exitCode == 0 && result.isNotEmpty) {
          return result;
        }
      } else if (config.extension == '.c' || config.extension == '.cpp') {
        final process = await Process.start('clang-format', []);
        process.stdin.write(content);
        await process.stdin.close();

        final result = await process.stdout.transform(utf8.decoder).join();
        final exitCode = await process.exitCode;

        if (exitCode == 0 && result.isNotEmpty) {
          return result;
        }
      } else if (config.extension == '.py') {
        final process = await Process.start('black', ['-q', '-']);
        process.stdin.write(content);
        await process.stdin.close();

        final result = await process.stdout.transform(utf8.decoder).join();
        final exitCode = await process.exitCode;

        if (exitCode == 0 && result.isNotEmpty) {
          return result;
        }
      }
    } catch (e) {
      debugPrint(
        'Warning: Format command "${config.formatCommand}" failed or not installed: $e',
      );
    }
    return content;
  }

  Future<void> saveCurrentFile() async {
    await saveFile(fileContent);
  }

  /// Saves the active tab. Returns false when the user cancelled the Save As
  /// dialog or the write failed, so callers can treat it as "not saved".
  Future<bool> saveFile(String content) async {
    final tab = activeTab;
    if (tab == null) return false;
    if (tab.filePath == null) return saveFileAs(content);

    try {
      final formattedContent = await _formatCode(content, tab.filePath);
      final file = File(tab.filePath!);
      await file.writeAsString(formattedContent);

      // Update tab with new content and sync originalContent
      _openTabs[_activeTabIndex] = TabFile(
        filePath: tab.filePath,
        fileName: tab.fileName,
        content: formattedContent,
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error saving file: $e');
      return false;
    }
  }

  /// Saves tab [index] to its own path without changing the active tab.
  ///
  /// Untitled tabs fall back to Save As (which needs the native dialog and
  /// therefore acts on the active tab). Used by the unsaved-changes guard.
  Future<bool> saveTab(int index) async {
    if (index < 0 || index >= _openTabs.length) return false;
    final tab = _openTabs[index];
    if (tab.filePath == null) {
      switchTab(index);
      return saveFileAs(tab.content);
    }

    try {
      final filePath = tab.filePath!;
      final formattedContent = await _formatCode(tab.content, filePath);
      await File(filePath).writeAsString(formattedContent);
      _openTabs[index] = TabFile(
        filePath: filePath,
        fileName: tab.fileName,
        content: formattedContent,
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error saving file: $e');
      return false;
    }
  }

  /// Returns false when the user cancelled the native save dialog.
  Future<bool> saveFileAs(String content) async {
    try {
      // Let the current frame (and any dialog that is closing) finish before the
      // native panel is shown: opening it mid-frame is what produced the empty
      // black window on macOS.
      await Future<void>.delayed(Duration.zero);

      // Show the native save dialog FIRST, before spawning any subprocess
      // (e.g. the formatter), so there is no black overlay on macOS.
      //
      // FileType.any (no allowedExtensions) on purpose: with a custom filter the
      // macOS save panel opened its own un-themed window that rendered black.
      // The suggested file name still carries the right extension.
      String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File As',
        fileName: activeTab?.fileName ?? 'main.dart',
        type: FileType.any,
      );
      if (path == null) return false;
      // Only format/write once the user has chosen a destination.
      final formattedContent = await _formatCode(content, path);
      final fileName = path.split('/').last;
      final file = File(path);
      await file.writeAsString(formattedContent);
      // If active tab exists, update it or add new
      if (_activeTabIndex >= 0 && _activeTabIndex < _openTabs.length) {
        _openTabs[_activeTabIndex] = TabFile(
          filePath: path,
          fileName: fileName,
          content: formattedContent,
        );
      } else {
        final newTab = TabFile(
          filePath: path,
          fileName: fileName,
          content: formattedContent,
        );
        _openTabs.add(newTab);
        _activeTabIndex = _openTabs.length - 1;
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error saving file as: $e');
      return false;
    }
  }

  void updateContent(String newContent) {
    final tab = activeTab;
    if (tab != null && tab.content != newContent) {
      tab.content = newContent;
      notifyListeners();
    }
  }
}
