import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../models/diagnostic.dart';
import '../../models/debugger_models.dart';
import '../../services/dart_runner_service.dart';
import '../../services/analyzer_service.dart';
import '../../services/lsp_service.dart';
import '../../services/file_service.dart';
import '../../services/theme_service.dart';
import '../../services/base_debugger.dart';
import '../editor/code_editor_panel.dart';
import '../editor/tab_bar.dart';
import '../console/console_panel.dart';
import '../analyzer/diagnostics_panel.dart';
import '../terminal/terminal_panel.dart';
import '../debugger/debugger_sidebar.dart';
import '../../services/terminal_service.dart';
import '../retro/retro_border.dart';
import '../retro/retro_watch_window.dart';
import '../retro/language_logo.dart';
import 'vertical_splitter.dart';
import 'horizontal_splitter.dart';

class PanelLayout extends StatefulWidget {
  final bool showFileExplorer;
  final bool showConsole;
  final bool showDiagnostics;
  final DartRunnerService dartRunnerService;
  final AnalyzerService analyzerService;
  final LspService lspService;
  final FileService fileService;
  final TerminalService terminalService;
  final BaseDebugger? debugger;
  final CodeController? codeEditorController;

  const PanelLayout({
    super.key,
    required this.showFileExplorer,
    required this.showConsole,
    required this.showDiagnostics,
    required this.dartRunnerService,
    required this.analyzerService,
    required this.lspService,
    required this.fileService,
    required this.terminalService,
    this.debugger,
    this.codeEditorController,
  });

  @override
  State<PanelLayout> createState() => _PanelLayoutState();
}

class _PanelLayoutState extends State<PanelLayout> {
  double _explorerWidth = 200;
  double _consoleHeight = 150;
  int _activeBottomTab = 0; // 0: Console, 1: Diagnostics, 2: Terminal, 3: Watch
  String _selectedLanguage = 'Auto';

  void _onExplorerResize(double delta) {
    setState(() {
      _explorerWidth = (_explorerWidth + delta).clamp(100, 400);
    });
  }

  void _onConsoleResize(double delta) {
    setState(() {
      _consoleHeight = (_consoleHeight - delta).clamp(80, 400);
    });
  }

  List<Diagnostic> get _mergedDiagnostics {
    if (widget.lspService.isConnected) {
      return widget.lspService.diagnostics;
    }
    return widget.analyzerService.diagnostics;
  }

  bool get _isAnalyzing {
    if (widget.lspService.isConnected) return false;
    return widget.lspService.isStarting || widget.analyzerService.isAnalyzing;
  }

  String get _diagnosticsSourceLabel {
    if (widget.lspService.isConnected) return 'LSP';
    return 'Analyzer';
  }

  @override
  Widget build(BuildContext context) {
    final showBottom = widget.showConsole || widget.showDiagnostics;
    final showDebugger =
        widget.debugger != null &&
        (widget.debugger!.state != DebugState.inactive ||
            widget.debugger!.breakpoints.isNotEmpty);

    return Container(
      color: ThemeService.instance.uiColors['panel'],
      padding: const EdgeInsets.fromLTRB(2, 2, 4, 2),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showFileExplorer) ...[
                  SizedBox(
                    width: _explorerWidth,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: RetroBorder.sunken(
                        backgroundColor:
                            ThemeService.instance.uiColors['panel'],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'File Explorer',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: ThemeService.instance.uiColors['text'],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '[Project Root]',
                            style: TextStyle(
                              fontSize: 12,
                              color: ThemeService.instance.uiColors['text'],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  VerticalSplitter(onDragUpdate: _onExplorerResize),
                  const SizedBox(width: 2),
                ],
                if (showDebugger) ...[
                  DebuggerSidebar(debugger: widget.debugger!),
                  const SizedBox(width: 2),
                  VerticalSplitter(onDragUpdate: (delta) {}),
                  const SizedBox(width: 2),
                ],
                // Editor area with TabBar above CodeEditorPanel
                Expanded(
                  // Same sunken frame as the File Explorer, so the editor starts
                  // at the very top and spans the full height like that panel.
                  child: Container(
                    decoration: RetroBorder.sunken(
                      backgroundColor: ThemeService.instance.uiColors['panel'],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBarWidget(fileService: widget.fileService),
                        Expanded(
                          child: CodeEditorPanel(
                            fileService: widget.fileService,
                            lspService: widget.lspService,
                            debugger: widget.debugger,
                            controller: widget.codeEditorController,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showBottom) ...[
            const SizedBox(height: 2),
            HorizontalSplitter(onDragUpdate: _onConsoleResize),
            const SizedBox(height: 2),
            SizedBox(
              height: _consoleHeight,
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  widget.analyzerService,
                  widget.lspService,
                  widget.fileService,
                  ThemeService.instance,
                ]),
                builder: (context, _) => _buildBottomPanel(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 44,
          color: ThemeService.instance.uiColors['panel'],
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildTabButton('Console', _activeBottomTab == 0, () {
                setState(() => _activeBottomTab = 0);
              }),
              const SizedBox(width: 4),
              _buildTabButton('Diagnostics', _activeBottomTab == 1, () {
                setState(() => _activeBottomTab = 1);
              }),
              const SizedBox(width: 4),
              _buildTabButton('Terminal', _activeBottomTab == 2, () {
                setState(() => _activeBottomTab = 2);
              }),
              const SizedBox(width: 4),
              _buildTabButton('Watch', _activeBottomTab == 3, () {
                setState(() => _activeBottomTab = 3);
              }),
              const Spacer(),
              _buildLanguageDropdown(),
              const SizedBox(width: 6),
              _buildLanguageIcon(),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: _activeBottomTab == 0
              ? ConsolePanel(dartRunnerService: widget.dartRunnerService)
              : _activeBottomTab == 1
              ? DiagnosticsPanel(
                  diagnostics: _mergedDiagnostics,
                  isAnalyzing: _isAnalyzing,
                  sourceLabel: _diagnosticsSourceLabel,
                )
              : _activeBottomTab == 2
              ? TerminalPanel(terminalService: widget.terminalService)
              : const RetroWatchWindow(),
        ),
      ],
    );
  }

  /// Detects the language of the currently active editor, using the file
  /// extension when available and falling back to sniffing the file content
  /// (so untitled buffers still show the right icon).
  String _detectLanguageExt() {
    final path = widget.fileService.currentFilePath ?? '';
    final source = path.isNotEmpty ? path : widget.fileService.fileName;
    final dot = source.lastIndexOf('.');
    var ext = '';
    if (dot >= 0 && dot < source.length - 1) {
      ext = source.substring(dot + 1).toLowerCase();
    }

    switch (ext) {
      case 'dart':
        return 'dart';
      case 'py':
        return 'py';
      case 'c':
        return 'c';
      case 'cpp':
      case 'cc':
      case 'cxx':
      case 'h':
      case 'hpp':
        return 'cpp';
    }

    // No usable extension (e.g. "Untitled") -> sniff the buffer content.
    final content = widget.fileService.fileContent;
    if (content.isEmpty) return '';
    if (content.contains("import '") ||
        content.contains('import "') ||
        content.contains('void main(') ||
        content.contains('extends ')) {
      return 'dart';
    }
    if (content.contains('#include')) {
      return (content.contains('std::') ||
              content.contains('namespace') ||
              content.contains('cout') ||
              content.contains('iostream'))
          ? 'cpp'
          : 'c';
    }
    if (RegExp(r'^\s*def\s+\w+\s*\(', multiLine: true).hasMatch(content) ||
        RegExp(r'^\s*print\s*\(', multiLine: true).hasMatch(content)) {
      return 'py';
    }
    return '';
  }

  /// Dropdown that lets the user pick the run/debug language explicitly
  /// ("Auto" keeps the automatic content/extension detection).
  Widget _buildLanguageDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: RetroBorder.sunken(
        backgroundColor: ThemeService.instance.uiColors['panel'],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedLanguage,
          isDense: true,
          items: const ['Auto', 'Dart', 'Python', 'C', 'C++']
              .map(
                (lang) => DropdownMenuItem<String>(
                  value: lang,
                  child: Text(
                    lang,
                    style: TextStyle(
                      fontSize: 11,
                      color: ThemeService.instance.uiColors['text'],
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() => _selectedLanguage = value ?? 'Auto');
            widget.dartRunnerService.setPreferredLanguage(_selectedLanguage);
          },
          style: TextStyle(
            fontSize: 11,
            color: ThemeService.instance.uiColors['text'],
          ),
          dropdownColor: ThemeService.instance.uiColors['panel'],
          underline: const SizedBox(),
        ),
      ),
    );
  }

  Widget _buildLanguageIcon() {
    final ext = _detectLanguageExt();
    if (ext.isEmpty) return const SizedBox.shrink();

    return Container(
      width: 40,
      height: 40,
      decoration: RetroBorder.raised(backgroundColor: Colors.white),
      padding: const EdgeInsets.all(3),
      child: Center(child: LanguageLogo(language: ext, size: 34)),
    );
  }

  Widget _buildTabButton(String label, bool isActive, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        margin: const EdgeInsets.only(top: 2, bottom: 2),
        constraints: const BoxConstraints(minHeight: 38),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        decoration: isActive
            ? RetroBorder.sunken(
                backgroundColor: ThemeService.instance.uiColors['panel'],
              )
            : RetroBorder.raised(
                backgroundColor: ThemeService.instance.uiColors['panel'],
              ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: ThemeService.instance.uiColors['text'],
          ),
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}
