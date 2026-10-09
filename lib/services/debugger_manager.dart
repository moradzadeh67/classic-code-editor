import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/debugger_models.dart';
import 'base_debugger.dart';
import 'debugger_factory.dart';
import 'file_service.dart';

/// Keeps the active [BaseDebugger] in sync with the active editor tab.
///
/// The shell rebuilds when [activeDebugger] changes, so switching language (by
/// opening another file or by editing an unsaved buffer into a new language)
/// hands the toolbar and the panels the right debugger without any widget
/// knowing which languages exist.
///
/// When the active language moves away from a *running* debugger that session is
/// stopped, so no process or temp file survives the switch. Breakpoints are
/// deliberately NOT cleared: they belong to the debugger that owns that
/// language and reappear when the user returns to it.
class DebuggerManager extends ChangeNotifier {
  /// Creates a manager over [fileService].
  ///
  /// [preferredLanguage] mirrors the toolbar dropdown so a manual language
  /// choice steers dispatch exactly as it steers the runner.
  DebuggerManager(
    this._fileService, {
    DebuggerFactory? factory,
    String Function()? preferredLanguage,
  }) : _factory = factory ?? DebuggerFactory(),
       _preferredLanguage = preferredLanguage ?? (() => 'Auto') {
    _activeDebugger = _resolveActive();
    _fileService.addListener(_onFileChanged);
  }

  final FileService _fileService;
  final DebuggerFactory _factory;
  final String Function() _preferredLanguage;

  late BaseDebugger _activeDebugger;
  bool _disposed = false;

  /// The debugger responsible for the currently active tab.
  BaseDebugger get activeDebugger => _activeDebugger;

  /// The factory backing this manager (also used to subscribe to every
  /// debugger's output stream).
  DebuggerFactory get factory => _factory;

  BaseDebugger _resolveActive() => _factory.forCode(
    _fileService.currentFilePath ?? _fileService.fileName,
    _fileService.fileContent,
    preferredLanguage: _preferredLanguage(),
  );

  void _onFileChanged() {
    final next = _resolveActive();
    if (identical(next, _activeDebugger)) return;

    final previous = _activeDebugger;
    _activeDebugger = next;
    if (previous.state != DebugState.inactive) {
      unawaited(previous.stopDebugging());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fileService.removeListener(_onFileChanged);
    _factory.dispose();
    super.dispose();
  }
}
