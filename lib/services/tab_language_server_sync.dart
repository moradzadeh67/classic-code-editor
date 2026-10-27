import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/language_config.dart';
import 'lsp_server_manager.dart';
import 'lsp_service.dart';
import 'unsaved_buffer_workspace.dart';

/// Points the language server at the document that matches a tab's **effective**
/// language, and keeps that document in sync.
///
/// The effective language is whatever Run, the highlighter and the language logo
/// already agree on (`LanguageConfig.resolveTab`): an explicit per-tab choice
/// wins, otherwise the extension/content resolver answers. When that language is
/// not what the file's extension says — `Untitled 23.c` holding Dart, or a `.c`
/// buffer switched to C++ — the buffer is exposed to the server as a virtual
/// `<basename>.<effective ext>` document inside [UnsavedBufferWorkspace], exactly
/// like an untitled buffer. Nothing is ever written next to the user's file, and
/// saving still uses the real path.
///
/// Kept separate from `IDEShell` so the whole open/close/switch lifecycle can be
/// tested with a fake manager.
class TabLanguageServerSync {
  TabLanguageServerSync({
    required this.manager,
    required this.workspace,
    this.onOutput,
  });

  final LspServerManager manager;
  final UnsavedBufferWorkspace workspace;

  /// Called for a one-line explanation when no virtual workspace is available.
  final void Function(String message)? onOutput;

  String? _openPath;
  LspService? _openService;
  String? _lastContent;
  int _token = 0;

  /// Document the server currently has open, or `null` before the first sync.
  String? get openPath => _openPath;

  /// Server that owns [openPath].
  LspService? get openService => _openService;

  /// Whether [effective] needs a virtual document instead of the real path.
  ///
  /// True for an untitled buffer, for a different explicit language, for a
  /// resolved mismatch and for an extension we do not know (the server would
  /// otherwise derive the wrong grammar from it).
  static bool needsVirtualDocument({
    required LanguageConfig effective,
    required String? realPath,
    required LanguageConfig? extensionLanguage,
  }) {
    if (realPath == null || realPath.isEmpty) return true;
    return extensionLanguage != effective;
  }

  /// The document path the server should use for this tab.
  Future<String?> documentPathFor({
    required LanguageConfig effective,
    required String? realPath,
    required String? bufferName,
  }) async {
    final usesVirtual = needsVirtualDocument(
      effective: effective,
      realPath: realPath,
      extensionLanguage: LanguageConfig.fromExtensionOrNull(realPath),
    );
    if (!usesVirtual) return realPath;
    try {
      return await workspace.pathFor(
        effective,
        bufferName: bufferName ?? _basename(realPath),
      );
    } on FileSystemException catch (e) {
      debugPrint('Unsaved buffer workspace unavailable: $e');
      return null;
    }
  }

  /// Makes the active server document match the tab.
  ///
  /// * same document + same server: only `didChange` when the text changed;
  /// * another document or another server: `didClose` on the old one first (which
  ///   also drops its diagnostics), then `didOpen` on the new one.
  Future<void> sync({
    required LanguageConfig effective,
    required String? realPath,
    required String content,
    String? bufferName,
  }) async {
    final token = ++_token;
    final previousPath = _openPath;
    final previousService = _openService;

    final documentPath = await documentPathFor(
      effective: effective,
      realPath: realPath,
      bufferName: bufferName,
    );
    if (token != _token) return;

    if (documentPath == null) {
      // No writable directory: report "no analysis" instead of inventing one.
      _closePrevious(previousPath, previousService);
      _openPath = null;
      _lastContent = null;
      _openService = manager.activateForUnsavedBuffer();
      onOutput?.call(
        'No writable temp folder — live analysis is off for this tab.',
      );
      return;
    }

    final service = await manager.activateFor(documentPath, content: content);
    if (token != _token) return;

    final switchedService = !identical(service, previousService);
    if (switchedService || documentPath != previousPath) {
      _closePrevious(previousPath, previousService);
      _openPath = documentPath;
      _openService = service;
      _lastContent = content;
      await service.openFile(documentPath, content);
      return;
    }

    if (content != _lastContent) {
      _lastContent = content;
      service.updateFile(documentPath, content);
      if (content.isEmpty) {
        unawaited(service.flushPendingChange(documentPath));
      }
    }
  }

  /// Flushes a change the service's debounce still holds (Save / Run / Debug).
  void flushPendingChange() {
    final service = _openService;
    final path = _openPath;
    if (service != null && path != null) {
      unawaited(service.flushPendingChange(path));
    }
  }

  void _closePrevious(String? path, LspService? service) {
    if (path == null || service == null) return;
    // Closing clears the diagnostics stored for that URI, so a stale count from
    // the previous server can never stay on screen.
    service.closeDocument(path);
  }

  static String? _basename(String? path) {
    if (path == null) return null;
    final parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }
}
