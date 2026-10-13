import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/python.dart';

import '../models/language_config.dart';

void registerHighlightLanguages() {
  MultiLanguageHighlighter.patchSymbolModes();
}

class MultiLanguageHighlighter {
  static const Color keywordColor = Color(0xFFF803FC);
  static const Color preprocessorColor = Color(0xFF7B1FA2);
  static const Color typeColor = Color(0xFF00796B);
  static const Color stringColor = Color(0xFFC62828);
  static const Color methodColor = Color(0xFF0D47A1);
  static const Color numberColor = Color(0xFFE65100);
  static const Color commentColor = Color(0xFF558B2F);
  static const Color operatorColor = Color(0xFF0B6E00);
  static const Color bracketColor = Color(0xFF031CFC);
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
        color: bracketColor,
        fontWeight: FontWeight.bold,
      ),
      'symbol': const TextStyle(
        color: operatorColor,
        fontWeight: FontWeight.bold,
      ),
    };
  }

  static bool _symbolsPatched = false;

  /// highlight 0.7's Dart / C / C++ / Python grammars emit no
  /// `operator` / `punctuation` classes of their own, so symbols used to
  /// render in the default editor text color. These single-character rules
  /// are appended to each grammar once (before any controller compiles it)
  /// so operators pick up `operatorColor` and brackets `bracketColor`.
  static void patchSymbolModes() {
    if (_symbolsPatched) return;
    _symbolsPatched = true;

    final fatArrow = Mode(begin: '=>', className: 'operator', relevance: 0);
    final brackets = Mode(
      begin: r'[()\[\]{}]',
      className: 'punctuation',
      relevance: 0,
    );
    final operators = Mode(
      begin: r'[!@#\$%^&*+=\-~<>/|?:;.,]',
      className: 'operator',
      relevance: 0,
    );

    void patch(Mode mode) {
      final contains = List<Mode?>.from(mode.contains ?? const <Mode?>[]);
      // Replace the stock plain `=>` rule so the fat arrow is colored too.
      for (var i = 0; i < contains.length; i++) {
        final m = contains[i];
        if (m != null && m.begin == '=>' && m.className == null) {
          contains[i] = fatArrow;
        }
      }
      contains.add(brackets);
      contains.add(operators);
      mode.contains = contains;
      mode.compiled = false; // force a recompile including the new rules
    }

    patch(dart);
    patch(python);
    patch(cpp);

    // cpp fix: the generated grammar opens swallowing variants on
    // `Mode(begin: "=", end: ";")` / `Mode(begin: "(", end: ")")` whose own
    // `contains` never include the symbol rules above, so operators and
    // brackets inside assignments / calls stayed uncolored (user-visible in
    // real C++ files even though `mode.contains` carried the rules).
    // Those variants only boost highlight.js relevance — their keyword lists
    // duplicate the top-level ones — so dropping that element lets the
    // patched top-level rules color symbols everywhere. Function parameter
    // lists still open the `params` mode below, so patch it (and its nested
    // paren mode) with the same rules.
    void patchContains(Mode? mode) {
      if (mode == null) return;
      final list = List<Mode?>.from(mode.contains ?? const <Mode?>[]);
      list.add(brackets);
      list.add(operators);
      mode.contains = list;
      mode.compiled = false;
    }

    cpp.contains = List<Mode?>.from(cpp.contains ?? const <Mode?>[])
      ..removeWhere(
        (m) =>
            m != null &&
            m.className == null &&
            m.begin == null &&
            m.beginKeywords == null &&
            m.variants != null,
      );

    Mode? firstWhereOrNull(List<Mode?>? list, bool Function(Mode) test) {
      for (final m in list ?? const <Mode?>[]) {
        if (m != null && test(m)) return m;
      }
      return null;
    }

    final functionMode = firstWhereOrNull(
      cpp.contains,
      (m) => m.className == 'function',
    );
    final paramsMode = firstWhereOrNull(
      functionMode?.contains,
      (m) => m.className == 'params',
    );
    patchContains(paramsMode);
    patchContains(
      firstWhereOrNull(
        paramsMode?.contains,
        (m) => m.begin == r'\(' && m.className == null && m.contains != null,
      ),
    );

    cpp.compiled = false; // recompile everything touched above
  }

  static Mode getModeForLanguage(String highlightLanguage) {
    patchSymbolModes();
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
