import 'package:flutter/material.dart';

import '../../services/dart_runner_service.dart';
import '../../services/file_service.dart';
import '../../services/analyzer_service.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';
import '../retro/retro_button.dart';

class RetroToolbar extends StatelessWidget {
  final VoidCallback? onNew;
  final VoidCallback? onOpen;
  final VoidCallback? onSave;
  final VoidCallback? onAnalyze;
  final VoidCallback? onRun;
  final VoidCallback? onStop;
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
    this.fileService,
    this.analyzerService,
    this.dartRunnerService,
  });

  @override
  Widget build(BuildContext context) {
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
          final content =
              fileService?.activeTab?.content ?? fileService?.fileContent ?? '';
          if (content.isEmpty) {
            debugPrint('No code to run');
            return;
          }
          debugPrint('Run button clicked, executing code...');
          dartRunnerService?.runCode(content);
        };
    final stopCallback =
        onStop ??
        () {
          debugPrint('Stop button clicked');
          dartRunnerService?.stopExecution();
        };

    // 28px tall ≈ Delphi 6 toolbar (22px buttons + borders/padding). No
    // vertical padding; the 2px border leaves a 24px content region.
    return Container(
      height: 28,
      decoration: RetroBorder.raised(
        backgroundColor: ThemeService.instance.colors.panel,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          _toolbarButton(label: 'New', onPressed: onNew),
          const SizedBox(width: 3),
          _toolbarButton(label: 'Open', onPressed: openCallback),
          const SizedBox(width: 3),
          _toolbarButton(label: 'Save', onPressed: saveCallback),
          const SizedBox(width: 3),
          _toolbarButton(label: 'Analyze', onPressed: analyzeCallback),
          const SizedBox(width: 5),
          _buildSeparator(),
          const SizedBox(width: 5),
          _toolbarButton(label: 'Run', onPressed: runCallback),
          const SizedBox(width: 3),
          _toolbarButton(label: 'Stop', onPressed: stopCallback),
          const SizedBox(width: 8),
          // Theme selector lives in the remaining space and SCROLLS
          // horizontally when it does not fit, instead of overflowing (which
          // produced the yellow/black "OVERFLOWED" hazard stripes).
          const Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: _ThemeSelector(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Content-sized toolbar button (no fixed width; min height handled by
  /// [RetroButton]). No style here: RetroButton forces Arial 12 / w500.
  Widget _toolbarButton({required String label, VoidCallback? onPressed}) {
    return RetroButton(onPressed: onPressed ?? () {}, child: Text(label));
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

/// Theme selector buttons.
///
/// Labels are deliberately SHORT (`VC++ 6.0` / `Delphi` / `VB6`) so the whole
/// toolbar fits. Wrapped in a [ListenableBuilder] on [ThemeService.instance] so
/// the pressed (sunken) state of each button refreshes immediately whenever the
/// active theme changes.
class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final currentTheme = ThemeService.instance.currentTheme;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Theme:',
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w500,
                fontFamily: 'Arial',
                height: 1.2,
                color: ThemeService.instance.colors.text,
              ),
            ),
            const SizedBox(width: 5),
            RetroButton(
              isPressed: currentTheme == ThemeType.vc6,
              onPressed: () => ThemeService.instance.switchTheme(ThemeType.vc6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: const Text('VC++ 6.0'),
            ),
            const SizedBox(width: 3),
            RetroButton(
              isPressed: currentTheme == ThemeType.delphi,
              onPressed: () =>
                  ThemeService.instance.switchTheme(ThemeType.delphi),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: const Text('Delphi'),
            ),
            const SizedBox(width: 3),
            RetroButton(
              isPressed: currentTheme == ThemeType.vb6,
              onPressed: () => ThemeService.instance.switchTheme(ThemeType.vb6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: const Text('VB6'),
            ),
          ],
        );
      },
    );
  }
}
