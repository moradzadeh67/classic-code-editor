import '../models/diagnostic.dart';
import 'analyzer_service.dart';
import 'lsp_service.dart';

/// The diagnostics one UI surface shows, and where they came from.
///
/// Plain data: the Diagnostics panel and the status bar both read this so the
/// list and the counters can never disagree about the active document.
class DiagnosticsView {
  const DiagnosticsView({
    required this.diagnostics,
    required this.sourceLabel,
    required this.isAnalyzing,
  });

  final List<Diagnostic> diagnostics;

  /// `'LSP'` or `'Analyzer'` — shown in the panel header.
  final String sourceLabel;

  /// Whether a result is still on its way (only the analyzer is one-shot).
  final bool isAnalyzing;

  int get errorCount => diagnostics.where((d) => d.severity == 'error').length;

  int get warningCount =>
      diagnostics.where((d) => d.severity == 'warning').length;
}

/// Chooses the diagnostics source for the active document.
///
/// A connected language server owns the answer for the document it has open,
/// **even when it published an empty list**: an empty list is a successful "no
/// problems", not a reason to show the one-shot [AnalyzerService] result from an
/// older text (or another file). The analyzer is only the fallback for a
/// document no server serves — Assembly, a missing server, or before the first
/// `didOpen`.
DiagnosticsView resolveDiagnostics({
  required LspService lsp,
  required AnalyzerService analyzer,
}) {
  if (lsp.isConnected && lsp.activeDocumentPath != null) {
    return DiagnosticsView(
      diagnostics: lsp.activeDiagnostics,
      sourceLabel: 'LSP',
      isAnalyzing: false,
    );
  }
  return DiagnosticsView(
    diagnostics: analyzer.diagnostics,
    sourceLabel: 'Analyzer',
    isAnalyzing: lsp.isStarting || analyzer.isAnalyzing,
  );
}
