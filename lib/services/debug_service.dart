import 'package:flutter/foundation.dart';

class WatchVariable {
  final String name;
  final String value;
  final String type;

  const WatchVariable({
    required this.name,
    required this.value,
    required this.type,
  });
}

class DebugService extends ChangeNotifier {
  static final instance = DebugService._internal();

  factory DebugService() => instance;
  DebugService._internal();

  final List<WatchVariable> _variables = [];

  List<WatchVariable> get variables => List.unmodifiable(_variables);

  void addVariable(String name, String value, String type) {
    _variables.add(WatchVariable(name: name, value: value, type: type));
    notifyListeners();
  }

  void clearVariables() {
    _variables.clear();
    notifyListeners();
  }

  /// Parses [code] and extracts declared variables into the watch list.
  /// Supports Dart/C/C++ declaration forms such as:
  ///   `var x = 1;`
  ///   `int x = 1;`
  ///   `double y = 5.0;`
  ///   `String s = 'hi';`
  ///   `bool flag = true;`
  /// Also supports Python-style (untyped) assignments:
  ///   `count = 100`
  ///   `ide_name = "Retro Python IDE"`
  ///   `is_running = True`
  void parseAndExtractVariables(String code) {
    _variables.clear();

    // --- C-like explicit typed declarations (Dart, C, C++, Java) ---
    // Pattern: `type name = ... ;`
    final typedRegex = RegExp(
      r'(var\b|\b(int|double|bool|String|dynamic|num|float|long|short|byte|char|void|unsigned)\b)\s+([a-zA-Z_]\w*)\s*=\s*(.+?);',
      multiLine: true,
    );
    for (final match in typedRegex.allMatches(code)) {
      final type = match.group(2)!; // actual type
      final name = match.group(3)!;
      final value = match
          .group(4)!
          .trim()
          .replaceAll(RegExp(r'//.*$'), '')
          .trim();

      _variables.add(
        WatchVariable(name: name, value: value, type: _normalizeType(type)),
      );
    }

    // --- Python-style untyped assignments ---
    // Matches `name = value` lines that do NOT start with keywords like
    // import, print, if, for, while, def, class, return, elif, else, try,
    // except, finally, with, assert, raise, from, as, in, lambda, pass,
    // break, continue, global, nonlocal, del, yield, await, async.
    final pythonRegex = RegExp(
      r'(?<![\w$])([a-zA-Z_]\w*)\s*=\s*(?!=)([^\n;]*)',
      multiLine: true,
    );
    final reservedKeywords = {
      'import',
      'print',
      'if',
      'elif',
      'else',
      'for',
      'while',
      'def',
      'class',
      'return',
      'try',
      'except',
      'finally',
      'with',
      'assert',
      'raise',
      'from',
      'as',
      'in',
      'lambda',
      'pass',
      'break',
      'continue',
      'global',
      'nonlocal',
      'del',
      'yield',
      'await',
      'async',
      'True',
      'False',
      'None',
    };
    for (final match in pythonRegex.allMatches(code)) {
      final name = match.group(1)!;
      // Skip reserved keywords and names from typed declarations already handled
      if (reservedKeywords.contains(name)) continue;
      final value = match
          .group(2)!
          .trim()
          .replaceAll(RegExp(r'#.*$'), '')
          .trim();
      _variables.add(
        WatchVariable(name: name, value: value, type: _inferType(value)),
      );
    }

    // --- var/untyped Dart/C++ (group 1 = var) inference done in typed pass ---
    // Re-scan to fix 'var' entries (group1 == var) using inference
    final re = RegExp(r'(var)\s+([a-zA-Z_]\w*)\s*=\s*(.+?);', multiLine: true);
    final varMatches = Map.fromEntries(
      re
          .allMatches(code)
          .map(
            (m) => MapEntry(
              m.group(2)!,
              m.group(3)!.trim().replaceAll(RegExp(r'//.*$'), '').trim(),
            ),
          ),
    );
    if (varMatches.isNotEmpty) {
      _variables
        ..removeWhere(
          (v) => _normalizeType('var') == v.type || v.type == 'dynamic',
        )
        ..addAll(
          varMatches.entries.map(
            (e) => WatchVariable(
              name: e.key,
              value: e.value,
              type: _inferType(e.value),
            ),
          ),
        );
    }

    notifyListeners();
  }

  /// Heuristic inference of a type from a literal value string.
  /// Handles both Dart (`True`, `False`) and Python (`True`, `False`) booleans.
  String _inferType(String value) {
    final v = value.trim();
    if (v.startsWith('"') || v.startsWith("'")) {
      return 'str';
    }
    if (v == 'true' || v == 'false' || v == 'True' || v == 'False') {
      return 'bool';
    }
    if (v.contains('.') || v.toLowerCase().contains('e')) {
      return 'float';
    }
    if (double.tryParse(v) == null && int.tryParse(v) != null) {
      return 'int';
    }
    return 'dynamic';
  }

  /// Normalizes a type keyword to a watch-friendly label.
  String _normalizeType(String type) => switch (type) {
    'var' => 'dynamic',
    'num' => 'num',
    'dynamic' => 'dynamic',
    'bool' => 'bool',
    'int' => 'int',
    'double' => 'double',
    'float' => 'float',
    'String' => 'str',
    'str' => 'str',
    _ => type,
  };
}
