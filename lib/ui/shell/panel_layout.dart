import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../models/debugger_models.dart';
import '../../models/language_config.dart';
import '../../services/dart_runner_service.dart';
import '../../services/analyzer_service.dart';
import '../../services/diagnostics_source.dart';
import '../../services/lsp_service.dart';
import '../../services/file_explorer_service.dart';
import '../../services/file_service.dart';
import '../../services/theme_service.dart';
import '../../services/base_debugger.dart';
import '../editor/code_editor_panel.dart';
import '../editor/tab_bar.dart';
import '../console/console_panel.dart';
import '../analyzer/diagnostics_panel.dart';
import '../terminal/terminal_panel.dart';
import '../debugger/debugger_sidebar.dart';
import '../explorer/file_explorer_panel.dart';
import '../../services/terminal_service.dart';
import '../retro/retro_border.dart';
import '../retro/retro_watch_window.dart';
import '../retro/language_logo.dart';
import 'retro_menu_item.dart';
import 'vertical_splitter.dart';
import 'horizontal_splitter.dart';

/// Keys of the compact language selector, for widget tests and tooling.
const Key kLanguageDropdownKey = ValueKey<String>('language-dropdown');
const Key kLanguageDropdownLabelKey = ValueKey<String>(
  'language-dropdown-label',
);

/// Every value the language dropdown offers, in display order.
const List<String> kLanguageOptions = [
  'Auto',
  'Dart',
  'Python',
  'C',
  'C++',
  'ARM64 Assembly',
];

class PanelLayout extends StatefulWidget {
  final bool showFileExplorer;
  final bool showConsole;
  final bool showDiagnostics;
  final DartRunnerService dartRunnerService;
  final AnalyzerService analyzerService;
  final LspService lspService;
  final FileService fileService;
  final FileExplorerService explorerService;
  final TerminalService terminalService;

  /// Path of the active tab, highlighted in the explorer.
  final String? activeFilePath;

  /// Double-clicked file in the explorer: the shell opens it.
  final ValueChanged<String> onOpenFile;

  /// "Open Folder..." in the explorer's empty state.
  final VoidCallback onOpenFolder;
  final BaseDebugger? debugger;
  final CodeController? codeEditorController;

  /// Lets the shell drive the editor ("Go to Line").
  final GlobalKey<CodeEditorPanelState>? editorKey;

  /// Forwarded to [CodeEditorPanel] so the status bar can show the caret
  /// position.
  final void Function(int line, int column)? onCaretChanged;

  const PanelLayout({
    super.key,
    required this.showFileExplorer,
    required this.showConsole,
    required this.showDiagnostics,
    required this.dartRunnerService,
    required this.analyzerService,
    required this.lspService,
    required this.fileService,
    required this.explorerService,
    required this.terminalService,
    required this.activeFilePath,
    required this.onOpenFile,
    required this.onOpenFolder,
    this.debugger,
    this.codeEditorController,
    this.editorKey,
    this.onCaretChanged,
  });

  @override
  State<PanelLayout> createState() => _PanelLayoutState();
}

class _PanelLayoutState extends State<PanelLayout> {
  double _explorerWidth = 200;
  double _consoleHeight = 240;
  int _activeBottomTab = 0; // 0: Console, 1: Diagnostics, 2: Terminal, 3: Watch

  /// Last tab whose dropdown value this panel painted, so a tab switch (or a
  /// dropdown change) rebuilds it without rebuilding on every keystroke.
  int _lastTabIndex = -1;
  String _lastLanguageOverride = 'Auto';

  @override
  void initState() {
    super.initState();
    widget.debugger?.addListener(_onDebuggerChanged);
    _syncLanguageFromTab();
    widget.fileService.addListener(_onFileChanged);
  }

  @override
  void didUpdateWidget(covariant PanelLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The shell hands us a different debugger when the tab language changes.
    if (oldWidget.debugger != widget.debugger) {
      oldWidget.debugger?.removeListener(_onDebuggerChanged);
      widget.debugger?.addListener(_onDebuggerChanged);
    }
    if (oldWidget.fileService != widget.fileService) {
      oldWidget.fileService.removeListener(_onFileChanged);
      widget.fileService.addListener(_onFileChanged);
    }
    _syncLanguageFromTab();
  }

  @override
  void dispose() {
    widget.fileService.removeListener(_onFileChanged);
    widget.debugger?.removeListener(_onDebuggerChanged);
    super.dispose();
  }

  /// Rebuilds only when the dropdown really has to change: another tab became
  /// active, or that tab's own language selection changed. Typing notifies the
  /// same service on every keystroke and must not rebuild this panel.
  void _onFileChanged() {
    if (!mounted) return;
    final tab = widget.fileService.activeTab;
    final index = widget.fileService.activeTabIndex;
    final override = tab?.languageOverride ?? 'Auto';
    if (index != _lastTabIndex || override != _lastLanguageOverride) {
      setState(_syncLanguageFromTab);
    }
  }

  void _syncLanguageFromTab() {
    _lastTabIndex = widget.fileService.activeTabIndex;
    _lastLanguageOverride = widget.fileService.activeLanguageOverride;
  }

  /// Rebuilds when a session starts or ends so the debugger sidebar appears
  /// only while something is actually being debugged.
  void _onDebuggerChanged() {
    if (mounted) setState(() {});
  }

  void _onExplorerResize(double delta) {
    setState(() {
      _explorerWidth = (_explorerWidth + delta).clamp(100, 400);
    });
  }

  void _onConsoleResize(double delta) {
    setState(() {
      // Keep a floor that still fits the tab strip, the "Console" header and
      // the stdin input bar; below that the output ListView collapses to a
      // few pixels and the console looks empty.
      _consoleHeight = (_consoleHeight - delta).clamp(200, 400);
    });
  }

  /// The diagnostics of the active document, from the single resolver both this
  /// panel and the status bar use.
  DiagnosticsView get _diagnosticsView => resolveDiagnostics(
    lsp: widget.lspService,
    analyzer: widget.analyzerService,
  );

  @override
  Widget build(BuildContext context) {
    final showBottom = widget.showConsole || widget.showDiagnostics;
    // Only an actual debug session earns the sidebar. Breakpoints alone are a
    // gutter concept - clicking one while merely editing used to pop the whole
    // debugger panel open, which read as "why did the debugger open?".
    final debuggerState = widget.debugger?.state;
    final showDebugger =
        widget.debugger != null &&
        (debuggerState == DebugState.running ||
            debuggerState == DebugState.paused);

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
                    child: FileExplorerPanel(
                      service: widget.explorerService,
                      activeFilePath: widget.activeFilePath,
                      onOpenFile: widget.onOpenFile,
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
                            key: widget.editorKey,
                            fileService: widget.fileService,
                            lspService: widget.lspService,
                            debugger: widget.debugger,
                            controller: widget.codeEditorController,
                            languageOverride:
                                widget.fileService.activeLanguageOverride,
                            onCaretChanged: widget.onCaretChanged,
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
    final diagnosticsView = _diagnosticsView;
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
                  diagnostics: diagnosticsView.diagnostics,
                  isAnalyzing: diagnosticsView.isAnalyzing,
                  sourceLabel: diagnosticsView.sourceLabel,
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
    final tab = widget.fileService.activeTab;
    // The one resolver the runner and the highlighter also use: the tab's own
    // selection wins, then the extension, then content sniffing. The logo can
    // therefore never contradict Run/Debug.
    final hasExtension = LanguageConfig.fromExtensionOrNull(
      tab?.filePath ?? tab?.fileName,
    ) != null;
    if (!hasExtension && (tab?.content ?? '').trim().isEmpty) return '';

    switch (LanguageConfig.resolveTab(tab).language.highlightLanguage) {
      case 'dart':
        return 'dart';
      case 'python':
        return 'py';
      case 'c':
        return 'c';
      case 'cpp':
        return 'cpp';
      case 'armasm':
        return 'asm';
    }
    return '';
  }

  /// Compact retro language selector ("Auto" keeps the automatic
  /// content/extension detection).
  ///
  /// Deliberately not a [DropdownButton]: Material forces an item height of at
  /// least 48 px, which was taller than the 44 px panel header. A
  /// [PopupMenuButton] with a sunken 28 px field keeps the header tidy while
  /// the menu itself uses the app's retro popup border.
  Widget _buildLanguageDropdown() {
    final uiColors = ThemeService.instance.uiColors;
    final value = widget.fileService.activeLanguageOverride;
    return PopupMenuButton<String>(
      key: kLanguageDropdownKey,
      tooltip: 'Language',
      initialValue: value,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 2),
      color: uiColors['panel'],
      elevation: 0,
      shape: const RetroPopupShape(),
      menuPadding: const EdgeInsets.symmetric(vertical: 2),
      constraints: const BoxConstraints(minWidth: 120),
      onSelected: (language) {
        // Per tab, in memory: the shell/editor pick it up from the tab and
        // re-highlight immediately (text, caret and scroll are untouched).
        widget.fileService.setActiveLanguage(language);
      },
      itemBuilder: (context) => [
        for (final language in kLanguageOptions)
          PopupMenuItem<String>(
            value: language,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              language,
              style: TextStyle(
                fontSize: 11,
                color: uiColors['text'],
                fontWeight: language == value
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
      ],
      child: Container(
        height: 28,
        padding: const EdgeInsets.only(left: 8, right: 4),
        decoration: RetroBorder.sunken(backgroundColor: uiColors['panel']),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              key: kLanguageDropdownLabelKey,
              style: TextStyle(fontSize: 12, color: uiColors['text']),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_drop_down, size: 18, color: uiColors['text']),
          ],
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
