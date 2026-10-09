import 'dart:async';

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
  }

  @override
  void dispose() {
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
      _lspOpenPath = path;
      _lspLastContent = content;
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
          // 4. Undo (Ctrl+Z / Cmd+Z)
          else if (event.logicalKey == LogicalKeyboardKey.keyZ &&
              isControlOrMeta) {
            _handleUndo();
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
                    ),
                  ),
                  RetroStatusBar(
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
