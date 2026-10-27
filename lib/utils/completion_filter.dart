import '../models/lsp_models.dart';

/// Pure, framework-free helpers for narrowing language-server completion
/// candidates down to what the user has actually typed, and providing fallback
/// keyword/token completions when an LSP server is unavailable.
/// What the editor should do right after a keystroke: nothing, a debounced
/// completion request, or an immediate one (a trigger character was typed).
class CompletionDecision {
  const CompletionDecision({
    required this.shouldRequest,
    required this.immediate,
    this.triggerKind = 1,
    this.triggerCharacter,
  });

  /// No popup: do not request (and dismiss whatever is open).
  static const CompletionDecision none = CompletionDecision(
    shouldRequest: false,
    immediate: false,
  );

  /// Whether a completion request should be made at all.
  final bool shouldRequest;

  /// Whether it must go out now, without the typing debounce. Only true when
  /// the character just typed is a trigger character.
  final bool immediate;

  /// LSP `CompletionContext.triggerKind`: 1 = invoked (debounced prefix),
  /// 2 = trigger character.
  final int triggerKind;

  /// The trigger character, when [triggerKind] is 2.
  final String? triggerCharacter;
}

/// In-memory most-recently-used tracker for accepted completions.
/// Capped at 200 entries; session-only (not persisted).
class _CompletionMru {
  static final _counter = <String, int>{};

  /// Records [label] as accepted; increments its counter.
  static void record(String label) {
    _counter[label] = (_counter[label] ?? 0) + 1;
    if (_counter.length > 200) {
      // Drop the oldest (lowest counter) entry.
      final oldest = _counter.entries
          .reduce((a, b) => a.value <= b.value ? a : b)
          .key;
      _counter.remove(oldest);
    }
  }

  /// Returns the current counter value for [label], or 0.
  static int valueFor(String label) => _counter[label] ?? 0;
}

class CompletionFilter {
  const CompletionFilter._();

  /// How many identifier characters the word under the cursor needs before
  /// completions are worth offering when a language server is connected.
  /// Set to 1 so typing a single character immediately offers suggestions.
  static const int minimumPrefixLength = 1;

  /// The same minimum for the offline fallback list (no server attached),
  /// kept at the original TASK-011 value so an offline session does not pop
  /// the list on every keystroke.
  static const int offlineMinimumPrefixLength = 3;

  /// Characters that open member completion regardless of what the server
  /// advertised — `.` plus the pre-triggerCharacters `->` and `::` paths.
  static const Set<String> legacyTriggerCharacters = {'.', '>', ':'};

  /// Decides what happens after a keystroke that left the caret at [offset].
  ///
  /// - a trigger character (server list ∪ legacy set) with an LSP server
  ///   attached → request immediately, `triggerKind = 2`;
  /// - an identifier prefix of [minimumPrefixLength] (LSP) or
  ///   [offlineMinimumPrefixLength] (fallback list) → request on the debounce;
  /// - whitespace, closing brackets or a bare caret → nothing.
  static CompletionDecision decide({
    required String text,
    required int offset,
    required bool lspConnected,
    required Iterable<String> triggerCharacters,
  }) {
    final word = currentWord(text, offset);
    final previous = previousChar(text, offset);

    final opens = <String>{...legacyTriggerCharacters, ...triggerCharacters};
    if (lspConnected && previous != null && opens.contains(previous)) {
      return CompletionDecision(
        shouldRequest: true,
        immediate: true,
        triggerKind: 2,
        triggerCharacter: previous,
      );
    }

    final minimum = lspConnected
        ? minimumPrefixLength
        : offlineMinimumPrefixLength;
    if (word.length >= minimum) {
      return const CompletionDecision(
        shouldRequest: true,
        immediate: false,
      );
    }
    return CompletionDecision.none;
  }

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

  /// Computes the match tier for [item] against [query].
  /// Lower tier = better match.
  /// Tier 1: exact case-sensitive prefix.
  /// Tier 2: case-insensitive prefix.
  /// Tier 3: word-start / camelCase match.
  /// Tier 4: subsequence match (or anything else).
  static int _matchTier(CompletionItem item, String query) {
    final filter = item.effectiveFilter;
    final lowerFilter = filter.toLowerCase();
    final lowerQuery = query.toLowerCase();

    // Tier 1: exact case-sensitive.
    if (filter.startsWith(query)) return 1;

    // Tier 2: case-insensitive prefix.
    if (lowerFilter.startsWith(lowerQuery)) return 2;

    // Tier 3: word-start or camelCase match (starts at a new word boundary).
    final words = filter.split(RegExp(r'[A-Z_\s]'));
    if (words.any((w) => w.toLowerCase().startsWith(lowerQuery))) return 3;

    // Tier 4: subsequence match.
    if (_isSubsequence(lowerFilter, lowerQuery)) return 4;

    // Fallback for anything else (should not occur with current filter).
    return 5;
  }

  static bool _isSubsequence(String text, String query) {
    int textIdx = 0;
    int queryIdx = 0;
    while (textIdx < text.length && queryIdx < query.length) {
      if (text[textIdx] == query[queryIdx]) {
        queryIdx++;
      }
      textIdx++;
    }
    return queryIdx == query.length;
  }

  /// Filters [items] to those whose match text starts with [query], ignoring
  /// case, and orders them most-relevant first.
  static List<CompletionItem> filter(List<CompletionItem> items, String query) {
    if (query.isEmpty) return List<CompletionItem>.of(items);

    final q = query.toLowerCase();

    final matches = items
        .where((item) => item.effectiveFilter.toLowerCase().startsWith(q))
        // The word being typed is never a candidate: with "pri" in the buffer,
        // the document-token list would otherwise offer "pri" next to "print".
        // Snippets are exempt: typing `stless` must still offer the template
        // that expands to a StatelessWidget.
        .where(
          (item) =>
              item.effectiveFilter.toLowerCase() != q ||
              item.kindInt == 15 ||
              item.kind == 'snippet',
        )
        .toList();

    matches.sort((a, b) {
      final tierA = _matchTier(a, query);
      final tierB = _matchTier(b, query);
      if (tierA != tierB) return tierA.compareTo(tierB);

      // b. Recently accepted first (higher MRU counter = better).
      final mruA = _CompletionMru.valueFor(a.displayLabel);
      final mruB = _CompletionMru.valueFor(b.displayLabel);
      if (mruA != mruB) return mruB.compareTo(mruA);

      // c. Server sortText (fall back to label), alphabetical.
      final sortA = a.sortText ?? a.displayLabel;
      final sortB = b.sortText ?? b.displayLabel;
      final sortCompare = sortA.compareTo(sortB);
      if (sortCompare != 0) return sortCompare;

      // d. Label alphabetical.
      return a.displayLabel.compareTo(b.displayLabel);
    });

    return matches;
  }

  /// Records [label] as recently accepted (increments MRU counter).
  static void recordCompletion(String label) => _CompletionMru.record(label);

  /// Returns the current counter value for [label], or 0.
  static int mruValueFor(String label) => _CompletionMru.valueFor(label);

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
            // A real LSP kind, so the popup shows K rather than "·": the
            // neutral badge is reserved for plain words from the document.
            kindInt: 14,
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
