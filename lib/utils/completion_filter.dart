import '../models/lsp_models.dart';

/// Pure, framework-free helpers for narrowing language-server completion
/// candidates down to what the user has actually typed, and providing fallback
/// keyword/token completions when an LSP server is unavailable.
class CompletionFilter {
  const CompletionFilter._();

  /// How many identifier characters the word under the cursor needs before
  /// completions are worth offering. Set to 1 so typing a single character
  /// immediately offers suggestions.
  static const int minimumPrefixLength = 1;

  /// Whether completions should be offered based on [word] and [previousChar].
  static bool isTriggering(String word, {String? previousChar}) {
    if (previousChar == '.' || previousChar == '>' || previousChar == ':') {
      return true;
    }
    return word.length >= minimumPrefixLength;
  }

  /// Returns the character immediately preceding the word at [offset],
  /// e.g. `.` in `list.add` or `>` in `ptr->field`.
  static String? previousChar(String text, int offset) {
    if (offset <= 0 || offset > text.length) return null;
    final word = currentWord(text, offset);
    final wordStart = offset - word.length;
    if (wordStart > 0) {
      return text[wordStart - 1];
    }
    return null;
  }

  /// Returns the identifier fragment being typed immediately before [offset]
  /// in [text].
  static String currentWord(String text, int offset) {
    if (offset <= 0 || offset > text.length) return '';

    int start = offset;
    while (start > 0 && isIdentifierChar(text[start - 1])) {
      start--;
    }
    return text.substring(start, offset);
  }

  /// Whether [ch] may appear in an identifier (`a-z`, `A-Z`, `0-9`, `_`).
  static bool isIdentifierChar(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    return (code >= 0x61 && code <= 0x7A) || // a-z
        (code >= 0x41 && code <= 0x5A) || // A-Z
        (code >= 0x30 && code <= 0x39) || // 0-9
        code == 0x5F; // _
  }

  /// Filters [items] to those whose match text starts with [query], ignoring
  /// case, and orders them most-relevant first.
  static List<CompletionItem> filter(List<CompletionItem> items, String query) {
    if (query.isEmpty) return List<CompletionItem>.of(items);

    final q = query.toLowerCase();

    final matches = items
        .where((item) => item.effectiveFilter.toLowerCase().startsWith(q))
        .toList();

    matches.sort((a, b) {
      final aFilter = a.effectiveFilter;
      final bFilter = b.effectiveFilter;

      final aExact = aFilter.toLowerCase() == q;
      final bExact = bFilter.toLowerCase() == q;
      if (aExact != bExact) return aExact ? -1 : 1;

      final aCase = aFilter.startsWith(query);
      final bCase = bFilter.startsWith(query);
      if (aCase && bCase && aCase != bCase) return aCase ? -1 : 1;

      if (a.displayLabel.length != b.displayLabel.length) {
        return a.displayLabel.length.compareTo(b.displayLabel.length);
      }

      return a.displayLabel.compareTo(b.displayLabel);
    });

    return matches;
  }

  /// Generates fallback completion items from language keywords and tokens
  /// extracted from [documentText].
  static List<CompletionItem> generateFallbackCompletions(
    String documentText,
    String query,
    String language,
  ) {
    final items = <CompletionItem>[];
    final seenLabels = <String>{};

    // 1. Keywords for the target language
    final keywords = _getKeywordsForLanguage(language);
    for (final kw in keywords) {
      if (seenLabels.add(kw)) {
        items.add(
          CompletionItem(
            label: kw,
            kind: 'keyword',
            filterText: kw,
            insertText: kw,
          ),
        );
      }
    }

    // 2. Document tokens (identifiers typed in the active document)
    final tokenRegExp = RegExp(r'\b[a-zA-Z_][a-zA-Z0-9_]*\b');
    for (final match in tokenRegExp.allMatches(documentText)) {
      final token = match.group(0)!;
      if (token.length >= 2 && seenLabels.add(token)) {
        items.add(
          CompletionItem(
            label: token,
            kind: 'variable',
            filterText: token,
            insertText: token,
          ),
        );
      }
    }

    return filter(items, query);
  }

  static List<String> _getKeywordsForLanguage(String language) {
    switch (language.toLowerCase()) {
      case 'python':
      case 'py':
        return const [
          'and',
          'as',
          'assert',
          'async',
          'await',
          'break',
          'class',
          'continue',
          'def',
          'del',
          'elif',
          'else',
          'except',
          'False',
          'finally',
          'for',
          'from',
          'global',
          'if',
          'import',
          'in',
          'is',
          'lambda',
          'None',
          'nonlocal',
          'not',
          'or',
          'pass',
          'raise',
          'return',
          'True',
          'try',
          'while',
          'with',
          'yield',
          'print',
          'range',
          'len',
          'str',
          'int',
          'float',
          'list',
          'dict',
          'set',
          'tuple',
          'input',
          'open',
          'type',
          'isinstance',
        ];
      case 'c':
        return const [
          'auto',
          'break',
          'case',
          'char',
          'const',
          'continue',
          'default',
          'do',
          'double',
          'else',
          'enum',
          'extern',
          'float',
          'for',
          'goto',
          'if',
          'inline',
          'int',
          'long',
          'register',
          'restrict',
          'return',
          'short',
          'signed',
          'sizeof',
          'static',
          'struct',
          'switch',
          'typedef',
          'union',
          'unsigned',
          'void',
          'volatile',
          'while',
          'printf',
          'scanf',
          'malloc',
          'free',
          'NULL',
          'main',
        ];
      case 'cpp':
      case 'c++':
        return const [
          'auto',
          'bool',
          'break',
          'case',
          'catch',
          'char',
          'class',
          'const',
          'constexpr',
          'continue',
          'default',
          'delete',
          'do',
          'double',
          'else',
          'enum',
          'explicit',
          'export',
          'extern',
          'false',
          'float',
          'for',
          'friend',
          'goto',
          'if',
          'inline',
          'int',
          'long',
          'mutable',
          'namespace',
          'new',
          'operator',
          'private',
          'protected',
          'public',
          'register',
          'return',
          'short',
          'signed',
          'sizeof',
          'static',
          'struct',
          'switch',
          'template',
          'this',
          'throw',
          'true',
          'try',
          'typedef',
          'typename',
          'union',
          'unsigned',
          'using',
          'virtual',
          'void',
          'volatile',
          'while',
          'std',
          'cout',
          'cin',
          'endl',
          'vector',
          'string',
          'map',
          'main',
        ];
      case 'dart':
      default:
        return const [
          'abstract',
          'as',
          'assert',
          'async',
          'await',
          'break',
          'case',
          'catch',
          'class',
          'const',
          'continue',
          'default',
          'deferred',
          'do',
          'dynamic',
          'else',
          'enum',
          'export',
          'extends',
          'extension',
          'external',
          'factory',
          'false',
          'final',
          'finally',
          'for',
          'get',
          'if',
          'implements',
          'import',
          'in',
          'interface',
          'is',
          'late',
          'library',
          'mixin',
          'new',
          'null',
          'operator',
          'part',
          'required',
          'return',
          'set',
          'show',
          'static',
          'super',
          'switch',
          'sync',
          'this',
          'throw',
          'true',
          'try',
          'typedef',
          'var',
          'void',
          'while',
          'with',
          'yield',
          'print',
          'main',
          'String',
          'int',
          'double',
          'bool',
          'List',
          'Map',
          'Set',
          'Future',
          'Stream',
        ];
    }
  }
}
