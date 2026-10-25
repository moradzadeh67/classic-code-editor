import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/language_config.dart';
import 'compile_flags.dart';
import 'lsp_server_spec.dart';
import 'lsp_service.dart';

/// Owns one [LspService] per language server and keeps the server that matches
/// the active file in front.
///
/// Dart, clangd and pyright/pylsp are different processes with different warm-up
/// costs, so switching tabs between a `.c` and a `.dart` file must not tear a
/// server down and start it again. Services are cached by [LspServerSpec.id] and
/// only ever started once; [active] is always non-null (the "off" service when
/// no server applies) so the panels never need a null check.
class LspServerManager extends ChangeNotifier {
  LspServerManager({
    String? workspaceRoot,
    CompileFlagsEnsurer? compileFlags,
    this._serviceFactory,
    this._onOutput,
  }) : _workspaceRoot = workspaceRoot ?? Directory.current.path,
       _compileFlags = compileFlags ?? CompileFlagsEnsurer();

  final String _workspaceRoot;
  final CompileFlagsEnsurer _compileFlags;
  final LspService Function(LspServerSpec spec)? _serviceFactory;
  final void Function(String message)? _onOutput;

  final Map<String, LspService> _services = <String, LspService>{};

  /// Install hints already printed, so a tab switch does not repeat them.
  final Set<String> _hintsShown = <String>{};

  /// Dart is the warm-up service: it matches the editor's default language.
  late LspService _active = _build(LspServerSpec.dart);
  String _activeLanguage = 'dart';
  bool _disposed = false;

  /// The service that should serve the currently focused file.
  LspService get active => _active;

  /// `LanguageConfig.highlightLanguage` behind [active] (`dart`, `c`, …).
  String get activeLanguage => _activeLanguage;

  /// Selects and starts the server for [filePath], then returns it.
  ///
  /// The language comes from the file extension, or - for an unsaved buffer -
  /// from its content, through the same `LanguageConfig.fromPathOrContent`
  /// resolver the editor uses for coloring: an untitled C++ tab must get
  /// `clangd`, not the Dart server the path (`Untitled`) would imply.
  ///
  /// Switching between two files of the same language is a no-op. When no server
  /// is installed for the language, the "off" service is returned (it never
  /// connects, so the UI falls back to `AnalyzerService`) and the install hint is
  /// printed once.
  Future<LspService> activateFor(
    String? filePath, {
    String content = '',
  }) async {
    if (_disposed) return _active;

    final language = LanguageConfig.fromPathOrContent(
      filePath,
      content,
    ).highlightLanguage;
    if (language == _activeLanguage) return _active;
    _activeLanguage = language;

    final candidates = LspServerSpec.candidatesForLanguage(language);
    if (candidates.isEmpty) {
      // ARM64 Assembly and unknown files have no language server.
      _setActive(_build(LspServerSpec.off));
      return _active;
    }

    for (final spec in candidates) {
      final service = _build(spec);
      // Point the UI at the server we are about to start: the status bar should
      // say "Starting" instead of showing the previous language's server.
      _setActive(service);
      await service.startServer();
      if (_disposed) return service;
      if (service.isConnected) return service;
      _reportUnavailable(spec, service.lastError);
    }

    _setActive(_build(LspServerSpec.off));
    return _active;
  }

  /// Returns the cached service for [spec], creating and starting it on demand.
  LspService _build(LspServerSpec spec) {
    return _services.putIfAbsent(spec.id, () {
      final factory = _serviceFactory;
      if (factory != null) return factory(spec);
      return LspService(
        spec: spec,
        workspaceRoot: _workspaceRoot,
        prepareWorkspace: spec.usesCompileFlags ? _prepareCompileFlags : null,
      );
    });
  }

  /// clangd needs the SDK flags *before* it parses the first document.
  Future<void> _prepareCompileFlags() async {
    final outcome = await _compileFlags.ensure(_workspaceRoot);
    if (outcome == CompileFlagsOutcome.failed) {
      _onOutput?.call(
        '[LSP] Could not write ${CompileFlagsEnsurer.fileName} in '
        '$_workspaceRoot — clangd may not find the system headers.',
      );
    }
  }

  void _setActive(LspService service) {
    if (identical(_active, service)) return;
    _active = service;
    _safeNotify();
  }

  void _reportUnavailable(LspServerSpec spec, String? error) {
    if (!_hintsShown.add(spec.id)) return;
    final detail = (error == null || error.isEmpty) ? '' : ' ($error)';
    _onOutput?.call(
      '[LSP] ${spec.displayName} is not available$detail — falling back to the '
      'built-in analyzer.',
    );
    _onOutput?.call('[LSP] To enable it: ${spec.installHint}.');
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final service in _services.values) {
      service.dispose();
    }
    _services.clear();
    super.dispose();
  }
}
