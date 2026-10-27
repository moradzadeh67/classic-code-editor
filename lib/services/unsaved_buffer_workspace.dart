import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/language_config.dart';
import 'compile_flags.dart';

/// A writable workspace for buffers that have no file on disk yet.
///
/// A language server identifies a document by its path and derives the grammar,
/// the package context and the build flags from it, so an unsaved `Untitled`
/// buffer used to be analyzed as a fake file called `Untitled` in the editor's
/// working directory: clangd lost the macOS SDK headers (and reported 20+
/// invented errors) while the Dart server flagged `Untitled.dart` as
/// "isn't a lower_case_with_underscores identifier".
///
/// Here every unsaved buffer gets a lowercase name carrying the extension of
/// the language its content resolved to (`untitled.cpp`, `untitled.py`, …)
/// inside one per-session temp directory, which also receives the
/// `compile_flags.txt` clangd needs. Nothing is written for the buffer itself —
/// `didOpen` carries the text — and nothing outside that directory is touched.
class UnsavedBufferWorkspace {
  Directory? _directory;
  Future<Directory>? _creating;

  /// Base directory of the virtual documents, or `null` when the OS refused to
  /// create one (the caller then falls back to "no analysis").
  Directory? get directory => _directory;

  /// Stable virtual path for an unsaved buffer of [config].
  ///
  /// [bufferName] is the tab's own name, so two untitled tabs get two documents
  /// (`untitled.dart`, `untitled-2.dart`) instead of overwriting each other's
  /// diagnostics. Without a name the original `untitled` document is used.
  ///
  /// Throws [FileSystemException] when no writable directory is available.
  Future<String> pathFor(LanguageConfig config, {String? bufferName}) async {
    final dir = _directory ?? await (_creating ??= _create());
    return '${dir.path}/${_documentSlug(bufferName)}${config.extension}';
  }

  /// Lowercase, server-safe document name (`"Untitled 2"` -> `untitled-2`).
  static String _documentSlug(String? bufferName) {
    final slug = (bufferName ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'untitled' : slug;
  }

  Future<Directory> _create() async {
    final dir = await Directory.systemTemp.createTemp(
      'classic_code_editor_unsaved_',
    );
    _directory = dir;
    // clangd reads this from the document's own directory; an empty SDK
    // resolution writes nothing and clangd falls back to the driver's flags.
    await CompileFlagsEnsurer().ensure(dir.path);
    return dir;
  }

  /// Removes the temp directory (best effort; the OS would clean it anyway).
  void dispose() {
    final dir = _directory;
    _directory = null;
    _creating = null;
    if (dir == null) return;
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (e) {
      debugPrint('Could not remove ${dir.path}: $e');
    }
  }
}
