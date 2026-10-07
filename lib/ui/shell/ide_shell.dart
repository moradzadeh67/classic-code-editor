import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import '../../services/dart_runner_service.dart';
import '../../services/file_service.dart';
import '../../services/analyzer_service.dart';
import '../../services/lsp_service.dart';
import '../../services/terminal_service.dart';
import '../../services/dart_debugger.dart';
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
  final DartDebugger _debugger = DartDebugger();
  String? _lastAnalyzedPath;

  /// Path currently registered with the language server, plus the last content
  /// pushed to it, so we only emit `didOpen` / `didChange` when needed.
  String? _lspOpenPath;
  String? _lspLastContent;

  @override
  void initState() {
    super.initState();
    _fileService.addListener(_onFileServiceChanged);
    // Start the language server in the background so it is warming up while the
    // user is still opening their first file.
    unawaited(_lspService.startServer());
  }

  @override
  void dispose() {
    _fileService.removeListener(_onFileServiceChanged);
    _lspService.dispose();
    _dartRunnerService.dispose();
    _terminalService.dispose();
    _debugger.dispose();
    _fileService.dispose();
    _analyzerService.dispose();
    super.dispose();
  }

  void _onFileServiceChanged() {
    final path = _fileService.currentFilePath;
    final content = _fileService.fileContent;

    if (path == null) {
      _lastAnalyzedPath = null;
      _lspOpenPath = null;
      _lspLastContent = null;
      _analyzerService.clearDiagnostics();
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole shell whenever the theme changes. This is wrapped here
    // (and not only in app.dart) because `home:` widgets inside a Navigator
    // route are not rebuilt automatically when the parent app rebuilds.
    return ListenableBuilder(
      listenable: ThemeService.instance,
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
                ),
                // NOTE: deliberately NOT `const` so their build() re-runs when
                // the theme changes.
                RetroToolbar(
                  fileService: _fileService,
                  analyzerService: _analyzerService,
                  dartRunnerService: _dartRunnerService,
                  debugger: _debugger,
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
                    debugger: _debugger,
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
    );
  }
}
