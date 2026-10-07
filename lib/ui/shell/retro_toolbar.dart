import 'package:flutter/material.dart';

import '../../services/dart_runner_service.dart';
import '../../services/file_service.dart';
import '../../services/analyzer_service.dart';
import '../../services/theme_service.dart';
import '../../services/base_debugger.dart';
import '../../models/debugger_models.dart';
import '../retro/retro_border.dart';

class RetroToolbar extends StatelessWidget {
  final VoidCallback? onNew;
  final VoidCallback? onOpen;
  final VoidCallback? onSave;
  final VoidCallback? onAnalyze;
  final VoidCallback? onRun;
  final VoidCallback? onStop;
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
          dartRunnerService?.runCode(path, content);
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
          height: 34,
          color: ThemeService.instance.uiColors['panel'],
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _toolbarButton(
                icon: Icons.note_add_outlined,
                tooltip: 'New File',
                onPressed: newCallback,
              ),
              const SizedBox(width: 3),
              _toolbarButton(
                icon: Icons.folder_open_outlined,
                tooltip: 'Open File',
                onPressed: openCallback,
              ),
              const SizedBox(width: 3),
              _toolbarButton(
                icon: Icons.save_outlined,
                tooltip: 'Save File',
                onPressed: saveCallback,
              ),
              const SizedBox(width: 3),
              _toolbarButton(
                icon: Icons.fact_check_outlined,
                tooltip: 'Analyze Code',
                onPressed: analyzeCallback,
              ),
              const SizedBox(width: 5),
              _buildSeparator(),
              const SizedBox(width: 5),
              _toolbarButton(
                icon: Icons.play_arrow,
                tooltip: 'Run Code',
                iconColor: const Color(0xFF008000),
                onPressed: runCallback,
              ),
              const SizedBox(width: 3),
              _toolbarButton(
                icon: Icons.stop,
                tooltip: 'Stop Execution',
                iconColor: const Color(0xFFCC0000),
                onPressed: stopCallback,
              ),
              const SizedBox(width: 5),
              _buildSeparator(),
              const SizedBox(width: 5),
              // Debug buttons
              if (debugger != null) ...[
                if (!isDebugging)
                  _toolbarButton(
                    icon: Icons.bug_report_outlined,
                    tooltip: 'Start Debugging',
                    onPressed: () {
                      final path = fileService?.currentFilePath;
                      if (path != null) {
                        debugger?.startDebugging(path);
                      } else {
                        debugPrint('No file selected for debugging');
                      }
                    },
                  )
                else ...[
                  _toolbarButton(
                    icon: Icons.cancel_outlined,
                    tooltip: 'Stop Debugging',
                    iconColor: const Color(0xFFCC0000),
                    onPressed: () => debugger?.stopDebugging(),
                  ),
                  const SizedBox(width: 3),
                  _toolbarButton(
                    icon: Icons.redo,
                    tooltip: 'Step Over',
                    onPressed: () => debugger?.stepOver(),
                  ),
                  const SizedBox(width: 3),
                  _toolbarButton(
                    icon: Icons.south_east,
                    tooltip: 'Step Into',
                    onPressed: () => debugger?.stepInto(),
                  ),
                  const SizedBox(width: 3),
                  _toolbarButton(
                    icon: Icons.north_east,
                    tooltip: 'Step Out',
                    onPressed: () => debugger?.stepOut(),
                  ),
                  const SizedBox(width: 3),
                  _toolbarButton(
                    icon: Icons.fast_forward,
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

  /// Toolbar icon button formatted with 3D raised border and Tooltip.
  Widget _toolbarButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          margin: const EdgeInsets.only(top: 1, bottom: 1),
          constraints: const BoxConstraints(minHeight: 30, minWidth: 32),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          decoration: RetroBorder.raised(
            backgroundColor: ThemeService.instance.uiColors['panel'],
          ),
          child: Icon(
            icon,
            size: 18,
            color: iconColor ?? ThemeService.instance.uiColors['text'],
          ),
        ),
      ),
    );
  }

  Widget _buildSeparator() {
    return Container(
      width: 2,
      height: 18,
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

/// Returns a representative background swatch for a [ThemeType].
Color _themeSwatch(ThemeType type) => switch (type) {
  ThemeType.vc6 => const Color(0xFF1C1C1C),
  ThemeType.delphi => const Color(0xFF242834),
  ThemeType.vb6 => const Color(0xFF000080),
};

/// Custom theme selector dropdown utilizing [PopupMenuButton] and root [Overlay].
class RetroThemeDropdown extends StatelessWidget {
  const RetroThemeDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final currentThemeName = ThemeService.instance.currentThemeName;
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
                          fontFamily: 'Arial',
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
              margin: const EdgeInsets.only(top: 1, bottom: 1),
              constraints: const BoxConstraints(minHeight: 30),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              decoration: RetroBorder.raised(
                backgroundColor: uiColors['panel'],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Swatch(color: _themeSwatch(currentTheme)),
                  const SizedBox(width: 4),
                  Text(
                    currentThemeName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Arial',
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
