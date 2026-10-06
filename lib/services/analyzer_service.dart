import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/diagnostic.dart';

class AnalyzerService extends ChangeNotifier {
  List<Diagnostic> _diagnostics = [];
  bool _isAnalyzing = false;

  List<Diagnostic> get diagnostics => _diagnostics;
  bool get isAnalyzing => _isAnalyzing;

  int get errorCount => _diagnostics.where((d) => d.severity == 'error').length;
  int get warningCount =>
      _diagnostics.where((d) => d.severity == 'warning').length;

  Future<void> analyzeFile(String filePath) async {
    _isAnalyzing = true;
    _diagnostics.clear();
    notifyListeners();

    try {
      // Find dart executable
      String dartExecutable = 'dart';
      try {
        final whichResult = await Process.run('which', ['dart']);
        if (whichResult.exitCode == 0) {
          dartExecutable = (whichResult.stdout as String).trim();
        }
      } catch (e) {
        // Fallback to 'dart'
      }

      // Run dart analyze with machine format
      final result = await Process.run(dartExecutable, [
        'analyze',
        '--format=machine',
        filePath,
      ]);

      // Parse output
      final lines = result.stdout.toString().split('\n');
      final newDiagnostics = <Diagnostic>[];
      for (var line in lines) {
        if (line.isEmpty) continue;

        // Format: SEVERITY|TYPE|ERROR_CODE|FILE|LINE|COLUMN|LENGTH|MESSAGE
        final parts = line.split('|');
        if (parts.length >= 8) {
          newDiagnostics.add(
            Diagnostic(
              file: parts[3],
              line: int.tryParse(parts[4]) ?? 1,
              column: int.tryParse(parts[5]) ?? 1,
              severity: parts[0].toLowerCase(),
              message: parts[7],
              code: parts[2],
            ),
          );
        }
      }
      _diagnostics = newDiagnostics;
    } catch (e) {
      debugPrint('Analyzer error: $e');
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  void clearDiagnostics() {
    _diagnostics.clear();
    notifyListeners();
  }
}
