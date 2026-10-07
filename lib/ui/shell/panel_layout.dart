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
  int _activeBottomTab = 0; // 0 for Console, 1 for Diagnostics, 2 for Terminal

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
      color: ThemeService.instance.uiColors['background'],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TabBarWidget(fileService: widget.fileService),
                      const SizedBox(height: 2),
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
          height: 34,
          color: ThemeService.instance.uiColors['panel'],
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
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
              : TerminalPanel(terminalService: widget.terminalService),
        ),
      ],
    );
  }

  Widget _buildTabButton(String label, bool isActive, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        margin: const EdgeInsets.only(top: 1, bottom: 1),
        constraints: const BoxConstraints(minHeight: 30),
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
