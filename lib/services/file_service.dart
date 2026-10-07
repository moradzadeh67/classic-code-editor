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
        allowedExtensions: ['dart', 'c', 'cpp', 'py'],
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
        final process = await Process.start(Platform.resolvedExecutable, [
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

  Future<void> saveFile(String content) async {
    final tab = activeTab;
    if (tab == null || tab.filePath == null) {
      await saveFileAs(content);
      return;
    }

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
    } catch (e) {
      debugPrint('Error saving file: $e');
    }
  }

  Future<void> saveFileAs(String content) async {
    try {
      // Show the native save dialog FIRST, before spawning any subprocess
      // (e.g. the formatter), so there is no black overlay on macOS.
      String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File As',
        fileName: activeTab?.fileName ?? 'main.dart',
        allowedExtensions: ['dart', 'c', 'cpp', 'py'],
        type: FileType.custom,
      );
      if (path == null) return;
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
    } catch (e) {
      debugPrint('Error saving file as: $e');
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
