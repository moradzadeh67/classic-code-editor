import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/file_node.dart';

/// Reads the folder the explorer shows, one level at a time.
///
/// The whole tree is never walked up front: a directory's [FileNode.children]
/// are read the first time it is expanded, so a big repository costs only the
/// levels the user actually opened.
class FileExplorerService extends ChangeNotifier {
  FileExplorerService({this.maxEntries = 2000});

  /// Maximum entries listed for one directory. Anything past it is summarised
  /// by a "… N more not shown" row.
  final int maxEntries;

  /// Files opened from the tree may not exceed this size.
  static const int maxOpenFileBytes = 2 * 1024 * 1024;

  /// How many bytes are inspected for a NUL byte (a binary file's tell).
  static const int binaryProbeBytes = 4 * 1024;

  /// Names the explorer never shows: tool output and VCS/OS clutter.
  static const Set<String> hiddenNames = <String>{
    'build',
    '.dart_tool',
    'node_modules',
    '__pycache__',
    '.DS_Store',
  };

  String? _rootPath;
  FileNode? _root;

  /// The open folder, or null when none is.
  String? get rootPath => _rootPath;

  /// The open folder's node (its children are the top level of the tree).
  FileNode? get root => _root;

  /// Folder name shown in the panel header.
  String get rootName {
    final path = _rootPath;
    if (path == null) return '';
    final segments = path.split(Platform.pathSeparator)
      ..removeWhere((segment) => segment.isEmpty);
    return segments.isEmpty ? path : segments.last;
  }

  /// True when [path] is inside the open folder.
  bool contains(String path) {
    final root = _rootPath;
    if (root == null) return false;
    return path == root || path.startsWith('$root${Platform.pathSeparator}');
  }

  /// Opens a folder (and reads its first level).
  Future<void> openFolder(String path) async {
    _rootPath = path;
    _root = FileNode(
      path: path,
      name: rootName,
      isDirectory: true,
      children: _readDirectory(path),
      childrenLoaded: true,
      expanded: true,
    );
    notifyListeners();
  }

  /// Lets the user pick a folder through the platform dialog.
  ///
  /// Returns the chosen path, or null when the dialog was cancelled.
  Future<String?> pickFolder() async {
    try {
      final picked = await FilePicker.platform.getDirectoryPath();
      if (picked == null) return null;
      await openFolder(picked);
      return picked;
    } catch (e) {
      debugPrint('Could not open folder: $e');
      return null;
    }
  }

  /// Closes the open folder and empties the tree.
  void closeFolder() {
    if (_rootPath == null && _root == null) return;
    _rootPath = null;
    _root = null;
    notifyListeners();
  }

  /// Expands or collapses [node], reading its children the first time.
  Future<void> toggleFolder(FileNode node) async {
    if (!node.isDirectory || node.isTruncationNotice) return;
    if (node.expanded) {
      node.expanded = false;
      notifyListeners();
      return;
    }
    if (!node.childrenLoaded) {
      node.children = _readDirectory(node.path);
      node.childrenLoaded = true;
    }
    node.expanded = true;
    notifyListeners();
  }

  /// Expands every folder on the way to [filePath], reading lazily as it goes.
  ///
  /// Does nothing when the file is not inside the open folder.
  Future<void> revealFile(String filePath) async {
    final root = _root;
    if (root == null || !contains(filePath) || filePath == root.path) return;

    final segments = filePath
        .substring(root.path.length + 1)
        .split(Platform.pathSeparator);
    var changed = false;
    var node = root;
    var current = root.path;

    // Every segment but the last is a folder that has to be open.
    for (var i = 0; i < segments.length - 1; i++) {
      current = '$current${Platform.pathSeparator}${segments[i]}';
      FileNode? next;
      for (final child in node.children) {
        if (child.isDirectory && child.path == current) {
          next = child;
          break;
        }
      }
      if (next == null) return;
      if (!next.childrenLoaded) {
        next.children = _readDirectory(current);
        next.childrenLoaded = true;
        changed = true;
      }
      if (!next.expanded) {
        next.expanded = true;
        changed = true;
      }
      node = next;
    }
    if (changed) notifyListeners();
  }

  /// Re-reads the tree, keeping every folder that was expanded open.
  Future<void> refresh() async {
    final root = _root;
    final rootPath = _rootPath;
    if (root == null || rootPath == null) return;

    final expandedPaths = <String>{};
    void collect(FileNode node) {
      for (final child in node.children) {
        if (child.isDirectory && !child.isTruncationNotice) {
          if (child.expanded) expandedPaths.add(child.path);
          collect(child);
        }
      }
    }

    collect(root);
    _root = FileNode(
      path: rootPath,
      name: rootName,
      isDirectory: true,
      children: _readDirectory(rootPath),
      childrenLoaded: true,
      expanded: true,
    );
    await _reopen(expandedPaths);
    notifyListeners();
  }

  Future<void> _reopen(Set<String> expandedPaths) async {
    Future<void> walk(FileNode node) async {
      for (final child in node.children) {
        if (!child.isDirectory || child.isTruncationNotice) continue;
        if (expandedPaths.contains(child.path)) {
          child.children = _readDirectory(child.path);
          child.childrenLoaded = true;
          child.expanded = true;
          await walk(child);
        }
      }
    }

    await walk(_root!);
  }

  /// Reads one directory: sorted, filtered, capped, and never throwing.
  ///
  /// Synchronous on purpose: the tree is expanded inside a widget callback, and
  /// a real `Directory.list()` future would only complete off the test's fake
  /// clock. A directory listing is short enough for the UI thread, and the cap
  /// bounds the worst case.
  List<FileNode> _readDirectory(String path) {
    final entries = <FileSystemEntity>[];
    try {
      entries.addAll(
        Directory(path).listSync(followLinks: false, recursive: false),
      );
    } on FileSystemException {
      // Unreadable folder (permissions, a race with a delete): show it empty.
      return <FileNode>[];
    } catch (_) {
      return <FileNode>[];
    }

    final nodes = <FileNode>[];
    for (final entity in entries) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.isEmpty || name.startsWith('.') || hiddenNames.contains(name)) {
        continue;
      }
      nodes.add(
        FileNode(
          path: entity.path,
          name: name,
          isDirectory: entity is Directory,
        ),
      );
    }

    nodes.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    if (nodes.length > maxEntries) {
      final hidden = nodes.length - maxEntries;
      nodes.removeRange(maxEntries, nodes.length);
      nodes.add(
        FileNode(
          path: '',
          name: '… $hidden more not shown',
          isDirectory: false,
          isTruncationNotice: true,
        ),
      );
    }
    return nodes;
  }

  /// Reads [path] for the editor, or returns null when it must not be opened.
  ///
  /// Two guards: bigger than [maxOpenFileBytes], or a NUL byte in the first
  /// [binaryProbeBytes] (a binary file's tell, which also means the text is
  /// not valid UTF-8).
  Future<String?> readFileForOpen(String path) async {
    try {
      final file = File(path);
      final size = await file.length();
      if (size > maxOpenFileBytes) return null;

      final bytes = await file.openRead(0, binaryProbeBytes).fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      if (bytes.contains(0)) return null;
      final text = size > bytes.length
          // Read the rest now that the head proved to be text.
          ? utf8.decode(await file.readAsBytes(), allowMalformed: true)
          : utf8.decode(bytes, allowMalformed: true);
      return text;
    } catch (e) {
      debugPrint('Could not read $path: $e');
      return null;
    }
  }
}
