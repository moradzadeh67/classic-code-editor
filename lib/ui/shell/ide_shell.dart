import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../services/theme_service.dart';
import '../../services/dart_runner_service.dart';
import '../../services/file_service.dart';
import '../../services/analyzer_service.dart';
import '../../services/lsp_service.dart';
import '../../services/terminal_service.dart';
import '../../services/debugger_manager.dart';
import '../../utils/app_shortcuts.dart';
import '../../utils/line_edit.dart';
import '../../utils/toggle_comment.dart';
import '../../services/editor_settings_service.dart';
import '../../services/session_service.dart';
import '../editor/code_editor_panel.dart';
import '../editor/go_to_line_dialog.dart';
import 'close_guard.dart';
import 'retro_menu_bar.dart';
import 'retro_toolbar.dart';
import 'retro_status_bar.dart';
import 'panel_layout.dart';

class IDEShell extends StatefulWidget {
  const IDEShell({super.key});

  @override
  State<IDEShell> createState() => _IDEShellState();
}

class _IDEShellState extends State<IDEShell> {
  bool _showFileExplorer = true;
  bool _showConsole = true;
  bool _showDiagnostics = true;
  final DartRunnerService _dartRunnerService = DartRunnerService();
  final FileService _fileService = FileService();
  final AnalyzerService _analyzerService = AnalyzerService();
  final LspService _lspService = LspService();
  final TerminalService _terminalService = TerminalService();
  final CodeController _codeController = CodeController();

  /// Owns one debugger per language and swaps the active one as tabs change.
  late final DebuggerManager _debuggerManager = DebuggerManager(
    _fileService,
    preferredLanguage: () => _dartRunnerService.preferredLanguage,
  );

  /// Forwards every language debugger's output into the shared Console stream.
  final List<StreamSubscription<String>> _debuggerOutputSubscriptions = [];
  final FocusNode _shellFocusNode = FocusNode();
  String? _lastAnalyzedPath;

  /// Receives the platform's cancelable exit request (Cmd+Q / window close).
  late final AppLifecycleListener _appLifecycle;

  /// Lets the shell ask the editor to jump to a line (Cmd+L).
  final GlobalKey<CodeEditorPanelState> _editorKey =
      GlobalKey<CodeEditorPanelState>();

  /// Caret position shown in the status bar (`Ln 12, Col 5`). The editor
  /// reports it on every move; the shell only rebuilds when it really changes.
  int _caretLine = 1;
  int _caretColumn = 1;

  void _onCaretChanged(int line, int column) {
    if (line == _caretLine && column == _caretColumn) return;
    setState(() {
      _caretLine = line;
      _caretColumn = column;
    });
  }

  /// Last persisted tab set, so typing never rewrites `session.json`.
  String? _lastSessionSignature;

  /// Path currently registered with the language server, plus the last content
  /// pushed to it, so we only emit `didOpen` / `didChange` when needed.
  String? _lspOpenPath;
  String? _lspLastContent;

  @override
  void initState() {
    super.initState();
    _fileService.addListener(_onFileServiceChanged);
    // Mirror every language debugger's output into the Console stream so a
    // debug session is never silent.
    for (final debugger in _debuggerManager.factory.all) {
      _debuggerOutputSubscriptions.add(
        debugger.output.listen(_dartRunnerService.emitOutput),
      );
    }
    // Start the language server in the background so it is warming up while the
    // user is still opening their first file.
    unawaited(_lspService.startServer());
    // macOS routes Cmd+Q and the red window button through the engine's
    // cancelable exit request, so this is the single quit guard.
    _appLifecycle = AppLifecycleListener(onExitRequested: _handleExitRequested);
    unawaited(_restoreSession());
  }

  /// Asks about every modified tab before the app terminates.
  Future<AppExitResponse> _handleExitRequested() async {
    if (!mounted) return AppExitResponse.exit;
    final canQuit = await TabCloseGuard.confirmExit(
      context,
      fileService: _fileService,
    );
    return canQuit ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  Future<void> _handleCloseTab() async {
    final index = _fileService.activeTabIndex;
    if (index < 0) return;
    await TabCloseGuard.confirmClose(
      context,
      fileService: _fileService,
      index: index,
    );
  }

  @override
  void dispose() {
    _appLifecycle.dispose();
    _shellFocusNode.dispose();
    _fileService.removeListener(_onFileServiceChanged);
    _lspService.dispose();
    for (final subscription in _debuggerOutputSubscriptions) {
      unawaited(subscription.cancel());
    }
    _debuggerManager.dispose();
    _dartRunnerService.dispose();
    _terminalService.dispose();
    _fileService.dispose();
    _analyzerService.dispose();
    super.dispose();
  }

  void _onFileServiceChanged() {
    final path = _fileService.currentFilePath ?? _fileService.fileName;
    final content = _fileService.fileContent;

    // Push the active document to the language server (open once, then change).
    if (path != _lspOpenPath) {
      final previousPath = _lspOpenPath;
      _lspOpenPath = path;
      _lspLastContent = content;
      // Close the document we are leaving first: the server otherwise keeps
      // publishing its diagnostics and the status bar counts problems from a
      // file that is no longer open (e.g. errors from a closed tab showing up
      // under the file that replaced it).
      if (previousPath != null) {
        _lspService.closeDocument(previousPath);
      }
      unawaited(_lspService.openFile(path, content));
    } else if (content != _lspLastContent) {
      _lspLastContent = content;
      _lspService.updateFile(path, content);
    }

    // Keep the one-shot analyzer as a fallback while the LSP is unavailable.
    if (!_lspService.isConnected && path != _lastAnalyzedPath) {
      _lastAnalyzedPath = path;
      _analyzerService.analyzeFile(path);
    }

    // Persist the tab set (open / close / switch) and the MRU list.
    _persistSession();
  }

  void _toggleFileExplorer() {
    setState(() {
      _showFileExplorer = !_showFileExplorer;
    });
  }

  void _toggleConsole() {
    setState(() {
      _showConsole = !_showConsole;
    });
  }

  void _toggleDiagnostics() {
    setState(() {
      _showDiagnostics = !_showDiagnostics;
    });
  }

  void _handleSave() {
    _fileService.saveCurrentFile();
  }

  void _handleNewFile() {
    _fileService.createNewFile();
  }

  void _handleRun() {
    _dartRunnerService.runActiveFile(_fileService);
  }

  void _handleUndo() {
    // Undo handled natively by platform/focused editor
  }

  /// Opens a file picked from the "Open Recent" section.
  Future<void> _openRecent(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      // The file moved or was deleted since it entered the MRU list.
      SessionService.instance.removeRecentFile(path);
      return;
    }
    try {
      _fileService.restoreFile(path, await file.readAsString());
    } on FileSystemException catch (e) {
      debugPrint('Could not open recent file $path: $e');
    }
  }

  /// Cmd+/: comments or uncomments the selected lines.
  void _handleToggleComment() {
    final selection = _codeController.selection;
    if (!selection.isValid) return;
    final result = toggleComment(
      text: _codeController.text,
      selectionStart: selection.start,
      selectionEnd: selection.end,
      filePath: _fileService.currentFilePath,
    );
    _codeController.value = TextEditingValue(
      text: result.text,
      selection: TextSelection(
        baseOffset: result.selectionStart,
        extentOffset: result.selectionEnd,
      ),
    );
  }

  /// Cmd+Shift+D: duplicates the current line (or the selected lines).
  void _handleDuplicateLine() {
    final selection = _codeController.selection;
    if (!selection.isValid) return;
    final result = duplicateLines(
      text: _codeController.text,
      selectionStart: selection.start,
      selectionEnd: selection.end,
    );
    _codeController.value = TextEditingValue(
      text: result.text,
      selection: TextSelection(
        baseOffset: result.selectionStart,
        extentOffset: result.selectionEnd,
      ),
    );
  }

  /// Restores the previous session: only files that still exist, and the active
  /// tab by path. Untitled buffers are never restored.
  Future<void> _restoreSession() async {
    await SessionService.instance.load();
    if (!mounted) return;

    for (final path in SessionService.instance.openPaths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        _fileService.restoreFile(path, await file.readAsString());
      } on FileSystemException catch (e) {
        debugPrint('Could not restore $path: $e');
      }
    }

    final activePath = SessionService.instance.activePath;
    if (activePath != null) {
      final index = _fileService.openTabs.indexWhere(
        (tab) => tab.filePath == activePath,
      );
      if (index >= 0) _fileService.switchTab(index);
    }
    _persistSession();
  }

  /// Stores the open paths + active path, and keeps the MRU list fresh.
  ///
  /// Only writes when the tab set actually changed, so typing never touches the
  /// disk.
  void _persistSession() {
    final paths = [
      for (final tab in _fileService.openTabs)
        if (tab.filePath != null) tab.filePath!,
    ];
    final activePath = _fileService.currentFilePath;
    final signature = '${paths.join('|')}#$activePath';
    if (signature == _lastSessionSignature) return;
    _lastSessionSignature = signature;

    SessionService.instance.saveSession(
      openPaths: paths,
      activePath: activePath,
    );
    if (activePath != null) {
      SessionService.instance.addRecentFile(activePath);
    }
  }

  /// Cmd+L: asks for a line number and jumps there.
  Future<void> _handleGoToLine() async {
    final editor = _editorKey.currentState;
    if (editor == null) return;
    final line = await showGoToLineDialog(context, maxLines: editor.lineCount);
    if (line != null) editor.goToLine(line);
  }

  void _handleRedo() {
    // Redo handled natively by platform/focused editor
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _shellFocusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          final isControlOrMeta =
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;

          // 1. Save (Ctrl+S / Cmd+S)
          if (event.logicalKey == LogicalKeyboardKey.keyS && isControlOrMeta) {
            _handleSave();
          }
          // 2. New File (Ctrl+N / Cmd+N)
          else if (event.logicalKey == LogicalKeyboardKey.keyN &&
              isControlOrMeta) {
            _handleNewFile();
          }
          // 3. Run (F5)
          else if (event.logicalKey == LogicalKeyboardKey.f5) {
            _handleRun();
          }
          // 2b. Close Tab (Cmd+W) — through the unsaved-changes guard.
          else if (event.logicalKey == LogicalKeyboardKey.keyW &&
              isControlOrMeta) {
            unawaited(_handleCloseTab());
          }
          // 2c. Open File (Cmd+O).
          else if (event.logicalKey == LogicalKeyboardKey.keyO &&
              isControlOrMeta) {
            unawaited(_fileService.openFile());
          }
          // 3b. Go to Line (Cmd+L).
          else if (event.logicalKey == LogicalKeyboardKey.keyL &&
              isControlOrMeta) {
            unawaited(_handleGoToLine());
          }
          // 3c. Toggle Comment (Cmd+/).
          else if (event.logicalKey == LogicalKeyboardKey.slash &&
              isControlOrMeta) {
            _handleToggleComment();
          }
          // 3d. Duplicate Line (Cmd+Shift+D).
          else if (event.logicalKey == LogicalKeyboardKey.keyD &&
              isControlOrMeta &&
              HardwareKeyboard.instance.isShiftPressed) {
            _handleDuplicateLine();
          }
          // 4. Undo (Ctrl+Z / Cmd+Z)
          else if (event.logicalKey == LogicalKeyboardKey.keyZ &&
              isControlOrMeta) {
            _handleUndo();
          }
          // 6. Editor zoom (Cmd + / Cmd - / Cmd 0)
          else if (isControlOrMeta) {
            final zoom = zoomActionFor(
              event.logicalKey,
              commandOrControl: isControlOrMeta,
            );
            if (zoom != null) {
              switch (zoom) {
                case EditorZoomAction.increase:
                  EditorSettingsService.instance.increase();
                  break;
                case EditorZoomAction.decrease:
                  EditorSettingsService.instance.decrease();
                  break;
                case EditorZoomAction.reset:
                  EditorSettingsService.instance.reset();
                  break;
              }
            }
          }
          // 5. Redo (Ctrl+Y / Cmd+Y)
          else if (event.logicalKey == LogicalKeyboardKey.keyY &&
              isControlOrMeta) {
            _handleRedo();
          }
        }
      },
      child: ListenableBuilder(
        // Rebuild on theme changes AND when the active debugger swaps language.
        listenable: Listenable.merge([ThemeService.instance, _debuggerManager]),
        builder: (context, _) {
          return Scaffold(
            backgroundColor: ThemeService.instance.colors.background,
            body: SafeArea(
              child: Column(
                children: [
                  RetroMenuBar(
                    onToggleFileExplorer: _toggleFileExplorer,
                    onToggleConsole: _toggleConsole,
                    onToggleDiagnostics: _toggleDiagnostics,
                    fileService: _fileService,
                    analyzerService: _analyzerService,
                    dartRunnerService: _dartRunnerService,
                    codeEditorController: _codeController,
                    onCloseTab: () => unawaited(_handleCloseTab()),
                    onGoToLine: () => unawaited(_handleGoToLine()),
                    onOpenRecent: (path) => unawaited(_openRecent(path)),
                  ),
                  // NOTE: deliberately NOT `const` so their build() re-runs when
                  // the theme changes.
                  RetroToolbar(
                    fileService: _fileService,
                    analyzerService: _analyzerService,
                    dartRunnerService: _dartRunnerService,
                    debugger: _debuggerManager.activeDebugger,
                  ),
                  Expanded(
                    child: PanelLayout(
                      showFileExplorer: _showFileExplorer,
                      showConsole: _showConsole,
                      showDiagnostics: _showDiagnostics,
                      dartRunnerService: _dartRunnerService,
                      analyzerService: _analyzerService,
                      lspService: _lspService,
                      fileService: _fileService,
                      terminalService: _terminalService,
                      debugger: _debuggerManager.activeDebugger,
                      codeEditorController: _codeController,
                      editorKey: _editorKey,
                      onCaretChanged: _onCaretChanged,
                    ),
                  ),
                  RetroStatusBar(
                    positionText: 'Ln $_caretLine, Col $_caretColumn',
                    analyzerService: _analyzerService,
                    lspService: _lspService,
                  ),
                  Container(
                    height: 2,
                    color: ThemeService.instance.uiColors['panel'],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
