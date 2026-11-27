import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/file_node.dart';

/// Moves one file or folder to the macOS Trash. Throws
/// [FileOperationException] when it could not.
typedef TrashMover = Future<void> Function(String path);

/// A file operation from the explorer's context menu failed.
///
/// [message] is written for the user (it is shown as-is in the panel).
class FileOperationException implements Exception {
  const FileOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Whether the explorer clipboard holds a copied or a cut entry.
enum ExplorerClipboardMode { copy, cut }

/// Where a pasted entry came from and where it ended up.
class ExplorerPasteResult {
  const ExplorerPasteResult({
    required this.from,
    required this.to,
    required this.moved,
  });

  final String from;
  final String to;

  /// True for a Cut + Paste (the source is gone), false for a copy.
  final bool moved;
}

/// Reads the folder the explorer shows, one level at a time.
///
/// The whole tree is never walked up front: a directory's [FileNode.children]
/// are read the first time it is expanded, so a big repository costs only the
/// levels the user actually opened.
class FileExplorerService extends ChangeNotifier {
  FileExplorerService({this.maxEntries = 2000, TrashMover? moveToTrash})
    : _moveToTrash = moveToTrash ?? _trashWithSystemCommand;

  /// How Delete removes an entry. Injectable so tests never touch the real
  /// Trash.
  final TrashMover _moveToTrash;

  /// macOS' own `trash` tool (moves to the Trash, keeps "Put Back" working).
  static const String trashCommand = '/usr/bin/trash';

  static Future<void> _trashWithSystemCommand(String path) async {
    final name = _nameOf(path);
    if (!File(trashCommand).existsSync()) {
      throw const FileOperationException(
        'Move to Trash is not available: $trashCommand was not found.',
      );
    }
    final ProcessResult result;
    try {
      result = await Process.run(trashCommand, <String>[path]);
    } on ProcessException catch (error) {
      throw FileOperationException(
        'Could not move "$name" to the Trash: ${error.message}',
      );
    }
    if (result.exitCode != 0) {
      final detail = '${result.stderr}'.trim();
      throw FileOperationException(
        'Could not move "$name" to the Trash'
        '${detail.isEmpty ? '' : ': $detail'}',
      );
    }
  }

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
  ///
  /// A path that names a file (not a directory) opens the file's own folder,
  /// so a file can never end up as the root of the tree.
  Future<void> openFolder(String path) async {
    if (FileSystemEntity.isFileSync(path)) {
      path = File(path).parent.path;
    }
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

  /// Turns text typed into the path bar into an existing directory path.
  ///
  /// Trims, expands a leading `~` to the home folder, drops a trailing
  /// separator (except for `/` itself) and returns `null` when the result is
  /// not an existing directory (missing, or a file).
  String? resolveDirectory(String input) {
    var path = input.trim();
    if (path.isEmpty) return null;
    final home = Platform.environment['HOME'];
    if (home != null && (path == '~' || path.startsWith('~/'))) {
      path = '$home${path.substring(1)}';
    }
    while (path.length > 1 && path.endsWith(Platform.pathSeparator)) {
      path = path.substring(0, path.length - 1);
    }
    return FileSystemEntity.isDirectorySync(path) ? path : null;
  }

  /// Lets the user pick a folder through the platform dialog.
  ///
  /// Returns the chosen path, or null when the dialog was cancelled.
  Future<String?> pickFolder() async {
    try {
      await FilePicker.skipEntitlementsChecks();
      final picked = await FilePicker.getDirectoryPath();
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

  // ---------------------------------------------------------------------------
  // File operations (the explorer's context menu)
  //
  // Synchronous I/O inside, for the same reason as [_readDirectory]. Every
  // failure is a [FileOperationException] with a message for the user; every
  // success re-reads the tree.
  // ---------------------------------------------------------------------------

  ExplorerClipboardMode? _clipboardMode;
  String? _clipboardPath;

  /// Whether Paste has something to paste.
  bool get hasClipboard => _clipboardPath != null;

  /// The entry waiting to be pasted (null when the clipboard is empty).
  String? get clipboardPath => _clipboardPath;

  /// Copy or Cut, for the entry in [clipboardPath].
  ExplorerClipboardMode? get clipboardMode => _clipboardMode;

  /// Last path segment of [path].
  static String _nameOf(String path) => path.split(Platform.pathSeparator).last;

  /// Folder that holds [path].
  static String parentOf(String path) => File(path).parent.path;

  static String _join(String directory, String name) =>
      '$directory${Platform.pathSeparator}$name';

  static bool _exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  /// [path] relative to the open folder (the path itself when outside it).
  String relativePath(String path) {
    final root = _rootPath;
    if (root == null || !contains(path)) return path;
    if (path == root) return '.';
    return path.substring(root.length + 1);
  }

  /// Why [name] cannot be used in [directory], or null when it can.
  ///
  /// [currentName] is the entry being renamed: keeping it, or changing only
  /// its letter case, is not a clash.
  String? nameError(String directory, String name, {String? currentName}) {
    if (name.trim().isEmpty) return 'Please enter a name.';
    if (name != name.trim()) {
      return 'A name cannot start or end with a space.';
    }
    if (name.contains('/')) return 'A name cannot contain "/".';
    if (name == '.' || name == '..') return '"$name" is not a valid name.';
    final sameEntry =
        currentName != null && currentName.toLowerCase() == name.toLowerCase();
    if (!sameEntry && _exists(_join(directory, name))) {
      return '"$name" already exists in this folder.';
    }
    return null;
  }

  void _checkName(String directory, String name, {String? currentName}) {
    final error = nameError(directory, name, currentName: currentName);
    if (error != null) throw FileOperationException(error);
  }

  void _checkNotRoot(String path, String action) {
    if (path == _rootPath) {
      throw FileOperationException('The open folder itself cannot be $action.');
    }
  }

  /// Re-reads the tree and opens the folders leading to [path].
  Future<void> _refreshAndReveal(String? path) async {
    await refresh();
    if (path != null) await revealFile(path);
  }

  /// Creates an empty file called [name] in [directory]; returns its path.
  Future<String> createFile(String directory, String name) async {
    _checkName(directory, name);
    final path = _join(directory, name);
    try {
      File(path).createSync();
    } on FileSystemException catch (error) {
      throw FileOperationException(
        'Could not create "$name": ${error.osError?.message ?? error.message}',
      );
    }
    await _refreshAndReveal(path);
    return path;
  }

  /// Creates a folder called [name] in [directory]; returns its path.
  Future<String> createFolder(String directory, String name) async {
    _checkName(directory, name);
    final path = _join(directory, name);
    try {
      Directory(path).createSync();
    } on FileSystemException catch (error) {
      throw FileOperationException(
        'Could not create "$name": ${error.osError?.message ?? error.message}',
      );
    }
    await _refreshAndReveal(path);
    return path;
  }

  /// Renames [path] to [newName] in the same folder; returns the new path.
  Future<String> rename(String path, String newName) async {
    _checkNotRoot(path, 'renamed');
    final oldName = _nameOf(path);
    if (newName == oldName) return path;
    final directory = parentOf(path);
    _checkName(directory, newName, currentName: oldName);
    final target = _join(directory, newName);
    try {
      _renameEntity(path, target);
    } on FileSystemException catch (error) {
      throw FileOperationException(
        'Could not rename "$oldName": '
        '${error.osError?.message ?? error.message}',
      );
    }
    _retargetClipboard(path, target);
    await _refreshAndReveal(target);
    return target;
  }

  /// Copies [path] next to itself as "name copy"; returns the copy's path.
  Future<String> duplicate(String path) async {
    _checkNotRoot(path, 'duplicated');
    final directory = parentOf(path);
    final target = _join(directory, uniqueCopyName(directory, _nameOf(path)));
    try {
      _copyEntity(path, target);
    } on FileSystemException catch (error) {
      throw FileOperationException(
        'Could not duplicate "${_nameOf(path)}": '
        '${error.osError?.message ?? error.message}',
      );
    }
    await _refreshAndReveal(target);
    return target;
  }

  /// Moves [path] to the Trash (recoverable with Finder's "Put Back").
  Future<void> moveToTrash(String path) async {
    _checkNotRoot(path, 'deleted');
    await _moveToTrash(path);
    if (_clipboardPath != null &&
        (_clipboardPath == path ||
            _clipboardPath!.startsWith('$path${Platform.pathSeparator}'))) {
      clearClipboard();
    }
    await refresh();
  }

  /// Puts [path] on the explorer clipboard for a later copy.
  void copyToClipboard(String path) =>
      _setClipboard(path, ExplorerClipboardMode.copy);

  /// Puts [path] on the explorer clipboard for a later move.
  void cutToClipboard(String path) {
    _checkNotRoot(path, 'moved');
    _setClipboard(path, ExplorerClipboardMode.cut);
  }

  /// Empties the explorer clipboard.
  void clearClipboard() {
    if (_clipboardPath == null) return;
    _clipboardPath = null;
    _clipboardMode = null;
    notifyListeners();
  }

  void _setClipboard(String path, ExplorerClipboardMode mode) {
    _clipboardPath = path;
    _clipboardMode = mode;
    notifyListeners();
  }

  /// Keeps a clipboard entry valid after it (or a folder above it) was
  /// renamed or moved.
  void _retargetClipboard(String from, String to) {
    final clip = _clipboardPath;
    if (clip == null) return;
    if (clip == from) {
      _clipboardPath = to;
    } else if (clip.startsWith('$from${Platform.pathSeparator}')) {
      _clipboardPath = '$to${clip.substring(from.length)}';
    }
  }

  /// Pastes the clipboard entry into [directory].
  ///
  /// A copy that would clash gets a free "name copy" name. A cut entry is
  /// moved (and the clipboard emptied); moving it into the folder it is
  /// already in does nothing and returns null.
  Future<ExplorerPasteResult?> paste(String directory) async {
    final source = _clipboardPath;
    final mode = _clipboardMode;
    if (source == null || mode == null) return null;
    final name = _nameOf(source);
    if (!_exists(source)) {
      clearClipboard();
      throw FileOperationException('"$name" no longer exists.');
    }
    if (directory == source ||
        directory.startsWith('$source${Platform.pathSeparator}')) {
      throw FileOperationException(
        'Cannot paste the folder "$name" inside itself.',
      );
    }

    final moved = mode == ExplorerClipboardMode.cut;
    if (moved && parentOf(source) == directory) {
      clearClipboard();
      return null;
    }
    final String target;
    if (moved) {
      _checkName(directory, name);
      target = _join(directory, name);
    } else {
      // Keep the name when it is free; only a clash gets "name copy".
      final free = !_exists(_join(directory, name));
      target = _join(directory, free ? name : uniqueCopyName(directory, name));
    }

    try {
      if (moved) {
        _renameEntity(source, target);
      } else {
        _copyEntity(source, target);
      }
    } on FileSystemException catch (error) {
      throw FileOperationException(
        'Could not paste "$name": ${error.osError?.message ?? error.message}',
      );
    }
    if (moved) {
      _clipboardPath = null;
      _clipboardMode = null;
    }
    await _refreshAndReveal(target);
    return ExplorerPasteResult(from: source, to: target, moved: moved);
  }

  /// First free name for a copy of [name] in [directory]: `name copy.ext`,
  /// then `name copy 2.ext`, `name copy 3.ext`, …
  String uniqueCopyName(String directory, String name) {
    final dot = name.lastIndexOf('.');
    // A leading dot (".env") is part of the name, not an extension.
    final hasExtension = dot > 0;
    final base = hasExtension ? name.substring(0, dot) : name;
    final extension = hasExtension ? name.substring(dot) : '';
    var candidate = '$base copy$extension';
    var counter = 2;
    while (_exists(_join(directory, candidate))) {
      candidate = '$base copy $counter$extension';
      counter++;
    }
    return candidate;
  }

  /// Shows [path] selected in a Finder window.
  Future<void> revealInFinder(String path) async {
    final ProcessResult result;
    try {
      result = await Process.run('open', <String>['-R', path]);
    } on ProcessException catch (error) {
      throw FileOperationException('Could not open Finder: ${error.message}');
    }
    if (result.exitCode != 0) {
      final detail = '${result.stderr}'.trim();
      throw FileOperationException(
        'Could not open Finder${detail.isEmpty ? '' : ': $detail'}',
      );
    }
  }

  /// Renames [from] to [to]; across volumes (where rename fails) it copies
  /// and then removes the source.
  void _renameEntity(String from, String to) {
    final type = FileSystemEntity.typeSync(from, followLinks: false);
    try {
      switch (type) {
        case FileSystemEntityType.directory:
          Directory(from).renameSync(to);
        case FileSystemEntityType.link:
          Link(from).renameSync(to);
        default:
          File(from).renameSync(to);
      }
    } on FileSystemException catch (error) {
      // EXDEV (18): a different volume. Anything else is a real failure.
      if (error.osError?.errorCode != 18) rethrow;
      _copyEntity(from, to);
      _deleteEntity(from);
    }
  }

  /// Copies a file, a link (as a link) or a whole folder from [from] to [to].
  void _copyEntity(String from, String to) {
    switch (FileSystemEntity.typeSync(from, followLinks: false)) {
      case FileSystemEntityType.directory:
        Directory(to).createSync();
        for (final child in Directory(from).listSync(followLinks: false)) {
          _copyEntity(child.path, _join(to, _nameOf(child.path)));
        }
      case FileSystemEntityType.link:
        Link(to).createSync(Link(from).targetSync());
      case FileSystemEntityType.notFound:
        throw FileSystemException('No such file or directory', from);
      default:
        File(from).copySync(to);
    }
  }

  void _deleteEntity(String path) {
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.directory:
        Directory(path).deleteSync(recursive: true);
      case FileSystemEntityType.link:
        Link(path).deleteSync();
      case FileSystemEntityType.notFound:
        return;
      default:
        File(path).deleteSync();
    }
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

      final bytes = await file
          .openRead(0, binaryProbeBytes)
          .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
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
