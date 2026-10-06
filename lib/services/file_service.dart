import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

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

  Future<void> openFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dart'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final fileName = filePath.split('/').last;
        final file = File(filePath);
        final content = await file.readAsString();

        // Check if file is already open
        final existingIndex = _openTabs.indexWhere(
          (tab) => tab.filePath == filePath,
        );
        if (existingIndex >= 0) {
          _activeTabIndex = existingIndex;
        } else {
          final newTab = TabFile(
            filePath: filePath,
            fileName: fileName,
            content: content,
          );
          _openTabs.add(newTab);
          _activeTabIndex = _openTabs.length - 1;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
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

  Future<void> saveFile(String content) async {
    final tab = activeTab;
    if (tab == null || tab.filePath == null) {
      await saveFileAs(content);
      return;
    }

    try {
      final file = File(tab.filePath!);
      await file.writeAsString(content);

      // Update tab with new content and sync originalContent
      _openTabs[_activeTabIndex] = TabFile(
        filePath: tab.filePath,
        fileName: tab.fileName,
        content: content,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving file: $e');
    }
  }

  Future<void> saveFileAs(String content) async {
    try {
      String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File As',
        fileName: activeTab?.fileName ?? 'main.dart',
        allowedExtensions: ['dart'],
        type: FileType.custom,
      );

      if (path != null) {
        final fileName = path.split('/').last;
        final file = File(path);
        await file.writeAsString(content);

        // If active tab exists, update it or add new
        if (_activeTabIndex >= 0 && _activeTabIndex < _openTabs.length) {
          _openTabs[_activeTabIndex] = TabFile(
            filePath: path,
            fileName: fileName,
            content: content,
          );
        } else {
          final newTab = TabFile(
            filePath: path,
            fileName: fileName,
            content: content,
          );
          _openTabs.add(newTab);
          _activeTabIndex = _openTabs.length - 1;
        }
        notifyListeners();
      }
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
