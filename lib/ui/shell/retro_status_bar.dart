import 'package:flutter/material.dart';

import '../../services/analyzer_service.dart';
import '../../services/diagnostics_source.dart';
import '../../services/git_controller.dart';
import '../../services/lsp_service.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';

/// Key of the Git segment (absent when no repository is shown).
const Key kGitSegmentKey = ValueKey<String>('git-segment');

/// Key of the Git segment's label.
const Key kGitSegmentTextKey = ValueKey<String>('git-segment-text');

/// Fixed width of the Git segment.
///
/// A constant keeps the segments beside it from shifting while a refresh
/// resolves; a long branch name is ellipsized instead of overflowing.
const double kGitSegmentWidth = 150;

class RetroStatusBar extends StatelessWidget {
  final String statusText;
  final String positionText;
  final AnalyzerService? analyzerService;
  final LspService? lspService;

  /// Read-only Git snapshot; when null (or with no repository) the segment is
  /// not drawn at all.
  final GitController? gitController;

  /// Callback invoked when the Git segment is clicked.
  final VoidCallback? onGitSegmentTap;

  const RetroStatusBar({
    super.key,
    this.statusText = 'Ready',
    this.positionText = 'Ln 1, Col 1',
    this.analyzerService,
    this.lspService,
    this.gitController,
    this.onGitSegmentTap,
  });

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[ThemeService.instance];
    if (analyzerService != null) listenables.add(analyzerService!);
    if (lspService != null) listenables.add(lspService!);
    if (gitController != null) listenables.add(gitController!);

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final textColor = ThemeService.instance.uiColors['text'];

        // The same resolver as the Diagnostics panel: a connected server owns
        // the active document's counts, even when it reported nothing at all;
        // the one-shot analyzer is only the fallback when no server serves this
        // document.
        final lsp = lspService;
        final analyzer = analyzerService;
        final int errors;
        final int warnings;
        final bool isAnalyzing;

        if (lsp != null && analyzer != null) {
          final view = resolveDiagnostics(lsp: lsp, analyzer: analyzer);
          errors = view.errorCount;
          warnings = view.warningCount;
          isAnalyzing = view.isAnalyzing;
        } else {
          errors = analyzer?.errorCount ?? 0;
          warnings = analyzer?.warningCount ?? 0;
          isAnalyzing = lsp?.isStarting ?? false;
        }

        final analysisText = isAnalyzing
            ? 'Analyzing...'
            : 'Errors: $errors, Warnings: $warnings';

        final lspText = lsp?.statusLabel ?? 'LSP: Stopped';
        final lspConnected = lsp?.isConnected ?? false;

        // Null while no repository is shown (or Git is unavailable): the
        // segment is not laid out at all, so nothing is left behind.
        final git = gitController;
        final gitLabel = git?.statusLabel;
        final gitTooltip = git?.tooltipText ?? '';

        // Compact, matching the classic Windows 9x status bar (~22-24px).
        return Container(
          height: 26,
          decoration: RetroBorder.raised(
            backgroundColor: ThemeService.instance.uiColors['panel'],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: _segment(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Arial',
                      height: 1.0,
                      color: textColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: _segment(
                  child: Text(
                    analysisText,
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Arial',
                      height: 1.0,
                      color: errors > 0 ? const Color(0xFFCC0000) : textColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (gitLabel != null) ...[
                MouseRegion(
                  cursor: onGitSegmentTap != null
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: GestureDetector(
                    onTap: onGitSegmentTap,
                    behavior: HitTestBehavior.opaque,
                    child: _segment(
                      key: kGitSegmentKey,
                      width: kGitSegmentWidth,
                      child: Tooltip(
                        message: gitTooltip,
                        child: Text(
                          gitLabel,
                          key: kGitSegmentTextKey,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w400,
                            fontFamily: 'Arial',
                            height: 1.0,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              _segment(
                width: 110,
                child: Tooltip(
                  message: lsp?.statusDetail ?? '',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color:
                                ThemeService.instance.uiColors['borderDark']!,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.zero,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: lspConnected
                                ? const Color(0xFF008000)
                                : const Color(0xFF808080),
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          lspText,
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w400,
                            fontFamily: 'Arial',
                            height: 1.0,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _segment(
                width: 100,
                alignment: Alignment.centerRight,
                child: Text(
                  positionText,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'Arial',
                    height: 1.0,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _segment({
    Key? key,
    required Widget child,
    double? width,
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Container(
      key: key,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: alignment,
      decoration: RetroBorder.sunken(),
      child: child,
    );
  }
}
