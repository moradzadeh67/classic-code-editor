import 'package:flutter/material.dart';

import '../../services/analyzer_service.dart';
import '../../services/lsp_service.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';

class RetroStatusBar extends StatelessWidget {
  final String statusText;
  final String positionText;
  final AnalyzerService? analyzerService;
  final LspService? lspService;

  const RetroStatusBar({
    super.key,
    this.statusText = 'Ready',
    this.positionText = 'Ln 1, Col 1',
    this.analyzerService,
    this.lspService,
  });

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[ThemeService.instance];
    if (analyzerService != null) listenables.add(analyzerService!);
    if (lspService != null) listenables.add(lspService!);

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final textColor = ThemeService.instance.uiColors['text'];

        // Once the language server is connected its real-time results are the
        // source of truth; otherwise we report the one-shot analyzer counts.
        final lsp = lspService;
        final int errors;
        final int warnings;
        final bool isAnalyzing;

        if (lsp != null && lsp.isConnected) {
          errors = lsp.errorCount;
          warnings = lsp.warningCount;
          isAnalyzing = false;
        } else {
          errors = analyzerService?.errorCount ?? 0;
          warnings = analyzerService?.warningCount ?? 0;
          isAnalyzing =
              (lsp?.isStarting ?? false) ||
              (analyzerService?.isAnalyzing ?? false);
        }

        final analysisText = isAnalyzing
            ? 'Analyzing...'
            : 'Errors: $errors, Warnings: $warnings';

        final lspText = lsp?.statusLabel ?? 'LSP: Stopped';
        final lspConnected = lsp?.isConnected ?? false;

        // Compact, matching the classic Windows 9x status bar (~22-24px).
        return Container(
          height: 28,
          decoration: RetroBorder.raised(
            backgroundColor: ThemeService.instance.uiColors['panel'],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
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
                      height: 1.2,
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
                      height: 1.2,
                      color: errors > 0 ? const Color(0xFFCC0000) : textColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _segment(
                width: 110,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: ThemeService.instance.uiColors['borderDark']!,
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
                          height: 1.2,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
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
                    height: 1.2,
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
    required Widget child,
    double? width,
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: alignment,
      decoration: RetroBorder.sunken(),
      child: child,
    );
  }
}
