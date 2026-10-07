import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/python.dart';

import '../models/language_config.dart';

void registerHighlightLanguages() {
  // No-op for highlight 0.7+ where modes are passed directly.
}

class MultiLanguageHighlighter {
  static const Color keywordColor = Color(0xFFF803FC);
  static const Color preprocessorColor = Color(0xFF7B1FA2);
  static const Color typeColor = Color(0xFF00796B);
  static const Color stringColor = Color(0xFFC62828);
  static const Color methodColor = Color(0xFF0D47A1);
  static const Color numberColor = Color(0xFFE65100);
  static const Color commentColor = Color(0xFF558B2F);
  static const Color operatorColor = Color(0xFF03E8FC);
  static const Color variableColor = Color(0xFF1A237E);

  static Map<String, TextStyle> getThemeStyles() {
    return {
      'meta': const TextStyle(
        color: preprocessorColor,
        fontWeight: FontWeight.bold,
      ),
      'meta-keyword': const TextStyle(
        color: preprocessorColor,
        fontWeight: FontWeight.bold,
      ),
      'meta-string': const TextStyle(color: stringColor),
      'keyword': const TextStyle(
        color: keywordColor,
        fontWeight: FontWeight.bold,
      ),
      'selector-tag': const TextStyle(
        color: keywordColor,
        fontWeight: FontWeight.bold,
      ),
      'built_in': const TextStyle(
        color: typeColor,
        fontWeight: FontWeight.w600,
      ),
      'type': const TextStyle(color: typeColor, fontWeight: FontWeight.w600),
      'class': const TextStyle(
        color: Color(0xFF006699),
        fontWeight: FontWeight.bold,
      ),
      'string': const TextStyle(color: stringColor),
      'quote': const TextStyle(color: stringColor),
      'title': const TextStyle(color: methodColor, fontWeight: FontWeight.bold),
      'title.function': const TextStyle(
        color: methodColor,
        fontWeight: FontWeight.bold,
      ),
      'function': const TextStyle(color: methodColor),
      'number': const TextStyle(
        color: numberColor,
        fontWeight: FontWeight.w600,
      ),
      'literal': const TextStyle(
        color: numberColor,
        fontWeight: FontWeight.bold,
      ),
      'comment': const TextStyle(
        color: commentColor,
        fontStyle: FontStyle.italic,
      ),
      'variable': const TextStyle(color: variableColor),
      'params': const TextStyle(color: Color(0xFF283593)),
      'operator': const TextStyle(
        color: operatorColor,
        fontWeight: FontWeight.bold,
      ),
      'punctuation': const TextStyle(
        color: operatorColor,
        fontWeight: FontWeight.bold,
      ),
      'symbol': const TextStyle(
        color: operatorColor,
        fontWeight: FontWeight.bold,
      ),
    };
  }

  static Mode getModeForLanguage(String highlightLanguage) {
    switch (highlightLanguage) {
      case 'c':
      case 'cpp':
        return cpp;
      case 'python':
        return python;
      case 'dart':
      default:
        return dart;
    }
  }

  static CodeController createController({
    required String text,
    String? filePath,
  }) {
    final config = LanguageConfig.fromExtension(filePath);
    final mode = getModeForLanguage(config.highlightLanguage);
    return CodeController(text: text, language: mode);
  }
}

// Retain DartHighlighter for backwards compatibility
class DartHighlighter {
  static Map<String, TextStyle> get themeStyles =>
      MultiLanguageHighlighter.getThemeStyles();

  static CodeController createController({required String text}) {
    return MultiLanguageHighlighter.createController(text: text);
  }
}
