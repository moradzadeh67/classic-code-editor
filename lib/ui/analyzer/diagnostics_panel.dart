import 'package:flutter/material.dart';

import '../../models/diagnostic.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';

/// Displays a list of [diagnostics] (from the static analyzer and/or the
/// language server) using the retro 3D panel styling.
///
/// This widget is intentionally stateless and data-driven: it renders whatever
/// list it is given, so the caller can decide whether the diagnostics come from
/// `AnalyzerService`, `LspService`, or a merge of both.
class DiagnosticsPanel extends StatelessWidget {
  final List<Diagnostic> diagnostics;
  final bool isAnalyzing;
  final String? sourceLabel;

  const DiagnosticsPanel({
    super.key,
    required this.diagnostics,
    this.isAnalyzing = false,
    this.sourceLabel,
  });

  int get _errorCount => diagnostics.where((d) => d.severity == 'error').length;

  int get _warningCount =>
      diagnostics.where((d) => d.severity == 'warning').length;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final uiColors = ThemeService.instance.uiColors;

        return Container(
          decoration: RetroBorder.sunken(backgroundColor: uiColors['panel']),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: uiColors['highlight'],
                child: Row(
                  children: [
                    Text(
                      sourceLabel == null
                          ? 'Diagnostics'
                          : 'Diagnostics ($sourceLabel)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Arial',
                        color: uiColors['text'],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isAnalyzing) ...[
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Analyzing...',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Arial',
                          color: uiColors['text'],
                        ),
                      ),
                    ] else
                      Text(
                        '(Errors: $_errorCount, Warnings: $_warningCount)',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Arial',
                          color: uiColors['text'],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: diagnostics.isEmpty
                    ? Center(
                        child: Text(
                          isAnalyzing
                              ? 'Running static analysis...'
                              : 'No diagnostics found. Code is clean!',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Arial',
                            color: uiColors['text']?.withValues(alpha: 0.7),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: diagnostics.length,
                        itemBuilder: (context, index) {
                          return _buildRow(
                            context,
                            diagnostics[index],
                            uiColors,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    Diagnostic diagnostic,
    Map<String, Color> uiColors,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: uiColors['borderDark']!.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(diagnostic.icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  diagnostic.message,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Arial',
                    color: uiColors['text'],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${diagnostic.file.split('/').last} • Line ${diagnostic.line}, Col ${diagnostic.column}'
                  '${diagnostic.code.isEmpty ? '' : ' [${diagnostic.code}]'}',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'Arial',
                    color: uiColors['text']?.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
