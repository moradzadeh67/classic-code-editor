import 'package:material_ui/material_ui.dart';

import '../../services/dart_runner_service.dart';
import '../../services/file_service.dart';
import '../../services/analyzer_service.dart';
import '../../services/theme_service.dart';
import '../../services/base_debugger.dart';
import '../../services/debug_service.dart';
import '../../models/debugger_models.dart';
import '../../models/language_config.dart';
import '../retro/retro_border.dart';
import '../retro/retro_toolbar_icons.dart';

class RetroToolbar extends StatelessWidget {
  final VoidCallback? onNew;
  final VoidCallback? onOpen;
  final VoidCallback? onSave;
  final VoidCallback? onAnalyze;
  final VoidCallback? onRun;
  final VoidCallback? onStop;

  /// Edit buttons; each runs the same action as its keyboard shortcut.
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onCut;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final BaseDebugger? debugger;
  final FileService? fileService;
  final AnalyzerService? analyzerService;
  final DartRunnerService? dartRunnerService;

  const RetroToolbar({
    super.key,
    this.onNew,
    this.onOpen,
    this.onSave,
    this.onAnalyze,
    this.onRun,
    this.onStop,
    this.onUndo,
    this.onRedo,
    this.onCut,
    this.onCopy,
    this.onPaste,
    this.debugger,
    this.fileService,
    this.analyzerService,
    this.dartRunnerService,
  });

  @override
  Widget build(BuildContext context) {
    final newCallback =
        onNew ??
        () {
          debugPrint('New button clicked');
          fileService?.createNewFile();
        };
    final openCallback = onOpen ?? () => fileService?.openFile();
    final saveCallback =
        onSave ?? () => fileService?.saveFile(fileService?.fileContent ?? '');
    final analyzeCallback =
        onAnalyze ??
        () {
          final path = fileService?.currentFilePath;
          if (path != null) {
            analyzerService?.analyzeFile(path);
          }
        };
    final runCallback =
        onRun ??
        () {
          final path = fileService?.currentFilePath;
          final content =
              fileService?.activeTab?.content ?? fileService?.fileContent ?? '';
          if (content.isEmpty) {
            debugPrint('No code to run');
            return;
          }
          debugPrint('Run button clicked, executing code...');
          DebugService.instance.parseAndExtractVariables(content);
          // The active tab's own selection, so another tab's dropdown value
          // can never leak into this buffer.
          dartRunnerService?.runCode(
            path,
            content,
            preferredLanguage:
                fileService?.activeTab?.languageOverride ?? 'Auto',
          );
        };
    final stopCallback =
        onStop ??
        () {
          debugPrint('Stop button clicked');
          dartRunnerService?.stopExecution();
          debugger?.stopDebugging();
        };

    // 28px tall ≈ Delphi 6 toolbar (22px buttons + borders/padding). No
    // vertical padding; the 2px border leaves a 24px content region.
    return ListenableBuilder(
      listenable: Listenable.merge([?debugger, ThemeService.instance]),
      builder: (context, _) {
        final isDebugging = debugger?.state != DebugState.inactive;

        return Container(
          height: 35,
          color: ThemeService.instance.uiColors['panel'],
          // Uneven on purpose: the panel layout below adds its own 2px top
          // padding, while the menu bar's dark bottom edge above eats one.
          // 4 above + 1 below leaves the buttons a visible 3px from both
          // lines (measured in the running app).
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbarButton(
                iconType: RetroToolbarIconType.newFile,
                tooltip: 'New File',
                onPressed: newCallback,
              ),
              const SizedBox(width: 3),
              _toolbarButton(
                iconType: RetroToolbarIconType.open,
                tooltip: 'Open File',
                onPressed: openCallback,
              ),
              const SizedBox(width: 3),
              _toolbarButton(
                iconType: RetroToolbarIconType.save,
                tooltip: 'Save File',
                onPressed: saveCallback,
              ),
              const SizedBox(width: 3),
              _toolbarButton(
                iconType: RetroToolbarIconType.analyze,
                tooltip: 'Analyze Code',
                onPressed: analyzeCallback,
              ),
              const SizedBox(width: 5),
              _buildSeparator(),
              const SizedBox(width: 5),
              _toolbarButton(
                iconType: RetroToolbarIconType.cut,
                tooltip: 'Cut',
                onPressed: onCut,
              ),
              const SizedBox(width: 3),
              _toolbarButton(
                iconType: RetroToolbarIconType.copy,
                tooltip: 'Copy',
                onPressed: onCopy,
              ),
              const SizedBox(width: 3),
              _toolbarButton(
                iconType: RetroToolbarIconType.paste,
                tooltip: 'Paste',
                onPressed: onPaste,
              ),
              const SizedBox(width: 5),
              _buildSeparator(),
              const SizedBox(width: 5),
              _toolbarButton(
                iconType: RetroToolbarIconType.undo,
                tooltip: 'Undo',
                onPressed: onUndo,
              ),
              const SizedBox(width: 3),
              _toolbarButton(
                iconType: RetroToolbarIconType.redo,
                tooltip: 'Redo',
                onPressed: onRedo,
              ),
              const SizedBox(width: 5),
              _buildSeparator(),
              const SizedBox(width: 5),
              _toolbarButton(
                iconType: RetroToolbarIconType.run,
                tooltip: 'Run Code',
                onPressed: runCallback,
              ),
              const SizedBox(width: 3),
              _toolbarButton(
                iconType: RetroToolbarIconType.stop,
                tooltip: 'Stop Execution',
                onPressed: stopCallback,
              ),
              const SizedBox(width: 5),
              _buildSeparator(),
              const SizedBox(width: 5),
              // Debug buttons
              if (debugger != null) ...[
                if (!isDebugging)
                  _toolbarButton(
                    iconType: RetroToolbarIconType.debug,
                    tooltip: 'Start Debugging',
                    onPressed: () {
                      // Untitled/unsaved buffers have no path; fall back to the
                      // displayed file name so they are debuggable too.
                      final String? path =
                          fileService?.currentFilePath ?? fileService?.fileName;
                      final content =
                          fileService?.activeTab?.content ??
                          fileService?.fileContent ??
                          '';
                      if (path == null || content.trim().isEmpty) {
                        debugPrint('Nothing to debug: no file or empty buffer');
                        return;
                      }
                      // A buffer whose content clearly belongs to another
                      // language is never compiled: same one-line answer as
                      // Run, from the same resolver.
                      final resolution = LanguageConfig.resolveTab(
                        fileService?.activeTab,
                      );
                      if (resolution.hasMismatch) {
                        dartRunnerService?.clearConsole();
                        dartRunnerService?.emitOutput(
                          resolution.mismatchMessage(
                            fileName: path.split('/').last,
                          ),
                        );
                        return;
                      }
                      // Printed so the IDE log shows which engine handles the
                      // file (AsmDebugger for .s, DartDebugger for .dart).
                      debugPrint(
                        'Debug button clicked: ${debugger.runtimeType} -> $path',
                      );
                      // A debug session writes to the same Console: start it
                      // from a clean slate like Run does.
                      dartRunnerService?.clearConsole();
                      debugger?.startDebugging(path, content: content);
                    },
                  )
                else ...[
                  _toolbarButton(
                    iconType: RetroToolbarIconType.stop,
                    tooltip: 'Stop Debugging',
                    onPressed: () => debugger?.stopDebugging(),
                  ),
                  const SizedBox(width: 3),
                  _toolbarButton(
                    iconType: RetroToolbarIconType.stepOver,
                    tooltip: 'Step Over',
                    onPressed: () => debugger?.stepOver(),
                  ),
                  const SizedBox(width: 3),
                  _toolbarButton(
                    iconType: RetroToolbarIconType.stepInto,
                    tooltip: 'Step Into',
                    onPressed: () => debugger?.stepInto(),
                  ),
                  const SizedBox(width: 3),
                  _toolbarButton(
                    iconType: RetroToolbarIconType.stepOut,
                    tooltip: 'Step Out',
                    onPressed: () => debugger?.stepOut(),
                  ),
                  const SizedBox(width: 3),
                  _toolbarButton(
                    iconType: RetroToolbarIconType.resume,
                    tooltip: 'Continue',
                    onPressed: () => debugger?.continueExecution(),
                  ),
                ],
              ],
              const SizedBox(width: 8),
              // Theme selector lives in the remaining space and SCROLLS
              // horizontally when it does not fit, instead of overflowing.
              const Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: RetroThemeDropdown(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// One flat toolbar button with its pixel icon and tooltip.
  Widget _toolbarButton({
    required RetroToolbarIconType iconType,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: RetroToolbarButton(
        key: ValueKey<String>('toolbar-${iconType.name}'),
        onPressed: onPressed,
        child: RetroToolbarIcon(iconType),
      ),
    );
  }

  Widget _buildSeparator() {
    return Container(
      width: 2,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: ThemeService.instance.colors.borderDark,
            width: 1,
          ),
          right: BorderSide(
            color: ThemeService.instance.colors.borderLight,
            width: 1,
          ),
        ),
      ),
    );
  }
}

/// A classic 3D toolbar button: always raised, its own separate frame, sunken
/// while it is pressed.
class RetroToolbarButton extends StatefulWidget {
  const RetroToolbarButton({super.key, required this.child, this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  State<RetroToolbarButton> createState() => _RetroToolbarButtonState();
}

class _RetroToolbarButtonState extends State<RetroToolbarButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // Rule 8: theme colors are read here, never captured in a const widget.
    final panel = ThemeService.instance.uiColors['panel'];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onPressed,
      child: Container(
        constraints: const BoxConstraints(minWidth: 28),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(4),
        decoration: _pressed
            ? RetroBorder.sunken(backgroundColor: panel)
            : RetroBorder.raised(backgroundColor: panel),
        // The pressed icon moves 1px down-right, like a real 9x button.
        child: Transform.translate(
          offset: _pressed ? const Offset(1, 1) : Offset.zero,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Returns a representative background swatch for a [ThemeType].
Color _themeSwatch(ThemeType type) => switch (type) {
  ThemeType.vc6 => const Color(0xFF1C1C1C),
  ThemeType.delphi => const Color(0xFF242834),
  ThemeType.vb6 => const Color(0xFF000080),
  ThemeType.turboPascal => const Color(0xFF0000A8),
};

/// Custom theme selector dropdown utilizing [PopupMenuButton] and root [Overlay].
class RetroThemeDropdown extends StatelessWidget {
  const RetroThemeDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final currentTheme = ThemeService.instance.currentTheme;
        final uiColors = ThemeService.instance.uiColors;

        return Theme(
          data: Theme.of(context).copyWith(
            popupMenuTheme: PopupMenuThemeData(
              color: uiColors['panel'],
              elevation: 4,
              shape: Border(
                top: BorderSide(
                  color: ThemeService.instance.colors.borderLight,
                  width: 2,
                ),
                left: BorderSide(
                  color: ThemeService.instance.colors.borderLight,
                  width: 2,
                ),
                right: BorderSide(
                  color: ThemeService.instance.colors.borderDark,
                  width: 2,
                ),
                bottom: BorderSide(
                  color: ThemeService.instance.colors.borderDark,
                  width: 2,
                ),
              ),
            ),
          ),
          child: PopupMenuButton<ThemeType>(
            tooltip: 'Select Theme',
            offset: const Offset(0, 26),
            onSelected: (ThemeType type) {
              ThemeService.instance.switchTheme(type);
            },
            itemBuilder: (context) {
              return ThemeType.values.map((entry) {
                final themeName = switch (entry) {
                  ThemeType.vc6 => 'VC++ 6.0',
                  ThemeType.delphi => 'Delphi',
                  ThemeType.vb6 => 'VB6',
                  ThemeType.turboPascal => 'Turbo Pascal',
                };
                final isSelected = entry == currentTheme;
                return PopupMenuItem<ThemeType>(
                  value: entry,
                  height: 30,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Swatch(color: _themeSwatch(entry), size: 10),
                      const SizedBox(width: 6),
                      Text(
                        themeName,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Tahoma',
                          color: isSelected
                              ? ThemeService.instance.uiColors['selection']
                              : ThemeService.instance.uiColors['text'],
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 30),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              decoration: RetroBorder.raised(
                backgroundColor: uiColors['panel'],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Theme',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Tahoma',
                      color: uiColors['text'],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 14,
                    color: uiColors['text'],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tiny colored square used as a theme preview swatch.
class _Swatch extends StatelessWidget {
  final Color color;
  final double size;

  const _Swatch({required this.color, this.size = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(
          color: ThemeService.instance.colors.borderDark,
          width: 1,
        ),
      ),
    );
  }
}
