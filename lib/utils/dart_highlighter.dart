import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/dart.dart';

class DartHighlighter {
  // IntelliJ-style colors
  static const Color keywordColor = Color(0xFFE91E63); // Magenta/Pink
  static const Color classNameColor = Color(0xFF2E7D32); // Dark Green
  static const Color stringColor = Color(0xFFD84315); // Red/Orange
  static const Color methodColor = Color(0xFF1565C0); // Blue
  static const Color annotationColor = Color(0xFF6A1B9A); // Purple
  static const Color variableColor = Color(0xFF0D47A1); // Dark Blue
  static const Color numberColor = Color(0xFFD32F2F); // Red
  static const Color commentColor = Color(0xFF757575); // Gray
  static const Color punctuationColor = Color(0xFFFF00E1); // Magenta Pink

  static final Map<String, TextStyle> themeStyles = {
    'comment': const TextStyle(color: commentColor),
    'quote': const TextStyle(color: stringColor),
    'string': const TextStyle(color: stringColor),
    'keyword': const TextStyle(
      color: keywordColor,
      fontWeight: FontWeight.bold,
    ),
    'selector-tag': const TextStyle(color: keywordColor),
    'type': const TextStyle(color: classNameColor),
    'class': const TextStyle(color: classNameColor),
    'title': const TextStyle(color: methodColor),
    'title.function': const TextStyle(color: methodColor),
    'built_in': const TextStyle(color: classNameColor),
    'number': const TextStyle(color: numberColor),
    'symbol': const TextStyle(color: punctuationColor),
    'punctuation': const TextStyle(color: punctuationColor),
    'meta': const TextStyle(color: annotationColor),
    'variable': const TextStyle(color: variableColor),
    'operator': const TextStyle(color: punctuationColor),
  };

  static CodeController createController({required String text}) {
    return CodeController(text: text, language: dart);
  }
}
