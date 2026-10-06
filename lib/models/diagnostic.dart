import 'package:flutter/material.dart';

class Diagnostic {
  final String file;
  final int line;
  final int column;
  final String severity; // 'error', 'warning', 'info'
  final String message;
  final String code;

  Diagnostic({
    required this.file,
    required this.line,
    required this.column,
    required this.severity,
    required this.message,
    required this.code,
  });

  Color get color {
    switch (severity) {
      case 'error':
        return const Color(0xFFCC0000);
      case 'warning':
        return const Color(0xFFFFA500);
      default:
        return const Color(0xFF0000FF);
    }
  }

  String get icon {
    switch (severity) {
      case 'error':
        return '❌';
      case 'warning':
        return '⚠️';
      default:
        return 'ℹ️';
    }
  }
}
