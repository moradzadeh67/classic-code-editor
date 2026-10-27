import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../services/theme_service.dart';
import '../../services/dart_runner_service.dart';
import '../../services/file_explorer_service.dart';
import '../../services/file_service.dart';
import '../../services/analyzer_service.dart';
import '../../services/lsp_server_manager.dart';
import '../../services/lsp_service.dart';
import '../../models/language_config.dart';
import '../../services/terminal_service.dart';
import '../../services/unsaved_buffer_workspace.dart';
import '../../services/debugger_manager.dart';
import '../../utils/app_shortcuts.dart';
import '../../utils/line_edit.dart';
import '../../utils/toggle_comment.dart';
import '../../services/editor_settings_service.dart';
import '../../services/session_service.dart';
import '../../services/tab_language_server_sync.dart';
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
  final FileExplorerService _explorerService = FileExplorerService();
  final AnalyzerService _analyzerService = AnalyzerService();

  /// Picks the language server per file (Dart, clangd, pyright/pylsp) and keeps
  /// each of them warm across tab switches.
  late final LspServerManager _lspManager = LspServerManager(
    onOutput: (message) => _dartRunnerService.emitOutput(message),
  );

  /// The server for the active file. Never null: `Off` when nothing applies.
  LspService get _lspService => _lspManager.active;

  /// Where an unsaved buffer is analyzed: servers need a document path, so the
  /// buffer is exposed under a lowercase name with the right extension inside a
  /// temp workspace (see [UnsavedBufferWorkspace]).
  final UnsavedBufferWorkspace _unsavedWorkspace = UnsavedBufferWorkspace();
  final TerminalService _terminalService = TerminalService();
  final CodeController _codeController = CodeController();

  /// Owns one debugger per language and swaps the active one as tabs change.
  late final DebuggerManager _debuggerManager = DebuggerManager(
    _fileService,
    preferredLanguage: () => _fileService.activeLanguageOverride,
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

  /// Path the language server currently has `didOpen` for, on which service.

  /// Keeps the active server's document aligned with the tab's effective
  /// language (see [TabLanguageServerSync]).
  late final TabLanguageServerSync _lspSync = TabLanguageServerSync(
    manager: _lspManager,
    workspace: _unsavedWorkspace,
    onOutput: (message) => _dartRunnerService.emitOutput(message),
  );

  /// Path + content the one-shot analyzer result describes. When either changes
  /// the result is stale, so it is dropped instead of being shown for new text.
  String? _analyzerSnapshotPath;
  String? _analyzerSnapshotContent;

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
    // Warm up the default language server (Dart) while the user is still
    // opening their first file; the server for another language starts on the
    // first file that needs it.
    unawaited(_lspManager.activateFor(null));
    // Start the Dart server immediately instead of waiting for the first tab:
    // `initialize` takes a while, and the first completion request needs it.
    unawaited(_lspService.startServer());
    // A run must see the latest text, whichever button started it (toolbar,
    // menu or F5): the runner notifies when its state changes.
    _dartRunnerService.addListener(_flushPendingDocumentChange);
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
    _dartRunnerService.removeListener(_flushPendingDocumentChange);
    _fileService.removeListener(_onFileServiceChanged);
    _lspManager.dispose();
    _unsavedWorkspace.dispose();
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
    final path = _fileService.currentFilePath;
    final content = _fileService.fileContent;

    // The one-shot analyzer result for the previous text of this file is
    // immediately stale once the content changed — drop it, don't wait for
    // the server.
    if (path != null &&
        (_analyzerSnapshotPath != path ||
            _analyzerSnapshotContent != content)) {
      _analyzerSnapshotPath = path;
      _analyzerSnapshotContent = content;
      _analyzerService.clearDiagnostics();
    }

    unawaited(_syncLanguageServer(path, content));

    // Keep the one-shot analyzer running for Dart files when the LSP is still
    // unavailable. Only run when the path has changed (not on every keystroke).
    final language = LanguageConfig.fromPathOrContent(
      path,
      content,
    ).highlightLanguage;
    if (path != null &&
        !_lspService.isConnected &&
        language == 'dart' &&
        path != _lastAnalyzedPath) {
      _lastAnalyzedPath = path;
      _analyzerService.analyzeFile(path);
    }

    // Persist the tab set (open / close / switch) and the MRU list.
    _persistSession();
  }

  /// Points the matching language server at the document for this tab and
  /// keeps it in sync.
  ///
  /// The tab's **effective** language decides (explicit dropdown choice, else
  /// the extension/content resolver), so a `.c` buffer switched to Dart is
  /// served by the Dart server as a virtual `.dart` document instead of being
  /// flagged by clangd. Activation is asynchronous, so a token inside
  /// [TabLanguageServerSync] discards a superseded tab switch.
  Future<void> _syncLanguageServer(String? path, String content) {
    final tab = _fileService.activeTab;
    return _lspSync.sync(
      effective: LanguageConfig.resolveTab(tab).language,
      realPath: path,
      content: content,
      bufferName: tab?.fileName ?? path?.split('/').last,
    );
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

  Future<void> _handleSave() async {
    _flushPendingDocumentChange();
    await _fileService.saveCurrentFile();
    // A save can add or rename nothing (no create/rename in this task), but the
    // file's size and timestamp changed: re-read the expanded folders.
    final savedPath = _fileService.currentFilePath;
    if (savedPath != null && _explorerService.contains(savedPath)) {
      unawaited(_explorerService.refresh());
    }
  }

  /// File > "Open Folder..." / the explorer's empty-state button.
  Future<void> _handleOpenFolder() async {
    final path = await _explorerService.pickFolder();
    if (path != null) SessionService.instance.setOpenFolderPath(path);
  }

  /// File > "Close Folder": forgets the folder in this and the next session.
  void _handleCloseFolder() {
    _explorerService.closeFolder();
    SessionService.instance.setOpenFolderPath(null);
  }

  /// Double-click in the explorer: the one open path, with the size/binary
  /// guards in front of it.
  Future<void> _openFileFromExplorer(String path) async {
    final content = await _explorerService.readFileForOpen(path);
    if (content == null) {
      _dartRunnerService.emitOutput('Not opened: binary or too large');
      return;
    }
    _fileService.restoreFile(path, content);
  }

  Future<void> _handleNewFile() async {
    _fileService.createNewFile();
  }

  Future<void> _handleRun() async {
    _flushPendingDocumentChange();
    _dartRunnerService.runActiveFile(_fileService);
  }

  /// Sends any document change the service's debounce still holds so Run/Debug
  /// and Save never operate on text the server has not seen yet.
  void _flushPendingDocumentChange() => _lspSync.flushPendingChange();

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

  /// Reopens only the parts of the previous session that are still useful: the
  /// File Explorer's folder and the recent-files list.
  ///
  /// Tabs are never replayed. An old `session.json` may still contain
  /// `openPaths`/`activePath`; it loads without error and simply has no effect,
  /// because a launch always starts on one empty **Untitled** editor.
  Future<void> _restoreSession() async {
    await SessionService.instance.load();
    if (!mounted) return;

    // Re-open the explorer's folder only when it still exists.
    final folder = SessionService.instance.openFolderPath;
    if (folder != null && Directory(folder).existsSync()) {
      await _explorerService.openFolder(folder);
    }

    // Always start empty: one Untitled buffer, whatever is on disk.
    _fileService.createNewFile();
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
      // Not `autofocus: true`: grabbing the keyboard here kept the editor from
      // ever being focused on launch (no caret, no typing). Key events still
      // reach this listener because they bubble up from the focused editor.
      focusNode: _shellFocusNode,
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
          // 2c. Open Folder (Cmd+Shift+O) — before the plain Cmd+O branch.
          else if (event.logicalKey == LogicalKeyboardKey.keyO &&
              isControlOrMeta &&
              HardwareKeyboard.instance.isShiftPressed) {
            unawaited(_handleOpenFolder());
          }
          // 2d. Open File (Cmd+O).
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
          // 6. Trigger Completion (Ctrl+Shift+Space, plus Ctrl+Space).
          // Deliberately before the zoom branch below, which swallows every
          // other Ctrl/Cmd key. Cmd+Space is *not* bound: macOS uses it to
          // switch the keyboard input source and never delivers it here.
          else if (event.logicalKey == LogicalKeyboardKey.space &&
              HardwareKeyboard.instance.isControlPressed) {
            _editorKey.currentState?.triggerCompletionFromCommand();
          }
          // 7. Editor zoom (Cmd + / Cmd - / Cmd 0)
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
        // Rebuild on theme changes, when the active debugger swaps language, and
        // when the language server for the focused file changes.
        listenable: Listenable.merge([
          ThemeService.instance,
          _debuggerManager,
          _lspManager,
        ]),
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
                    onOpenFolder: () => unawaited(_handleOpenFolder()),
                    onCloseFolder: _handleCloseFolder,
                    onTriggerCompletion: () =>
                        _editorKey.currentState?.triggerCompletionFromCommand(),
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
                      explorerService: _explorerService,
                      terminalService: _terminalService,
                      activeFilePath: _fileService.currentFilePath,
                      onOpenFile: (path) => unawaited(_openFileFromExplorer(path)),
                      onOpenFolder: () => unawaited(_handleOpenFolder()),
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
