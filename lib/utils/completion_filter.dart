import '../models/lsp_models.dart';

/// Pure, framework-free helpers for narrowing language-server completion
/// candidates down to what the user has actually typed.
///
/// The Dart language server answers a completion request with the full
/// universe of candidates at the cursor (keywords, types, members, ...). Those
/// results are ranked for a *full* member-access expression, not for a bare
/// identifier prefix, so feeding them straight into the popup shows noise:
///
/// ```text
/// user typed:  prin
/// server says: pragma, part '', part of '', Pattern, ...   // and no print
/// ```
///
/// Filtering and ordering on the client is therefore required for the popup to
/// be useful.
///
/// Kept free of any Flutter dependency so it can be exercised by plain Dart
/// tests and scripts without booting a widget tree.
class CompletionFilter {
  const CompletionFilter._();

  /// How many identifier characters the word under the cursor needs before
  /// completions are worth offering.
  ///
  /// Below this we should not even ask the language server. An empty prefix
  /// matches every symbol the server knows about, and a single character
  /// matches almost as many, so the popup would effectively never close and
  /// would block normal typing.
  static const int minimumPrefixLength = 3;

  /// Whether [word] is long enough to justify showing completions.
  static bool isTriggering(String word) => word.length >= minimumPrefixLength;

  /// Returns the identifier fragment being typed immediately before [offset]
  /// in [text].
  ///
  /// Walks backwards from [offset] until it hits a character that cannot be
  /// part of an identifier. For example, given `void main() { pri| }` with
  /// [offset] at `|`, this returns `'pri'`. Returns `''` when the cursor sits
  /// at the very start or directly after a non-identifier character.
  static String currentWord(String text, int offset) {
    if (offset <= 0 || offset > text.length) return '';

    int start = offset;
    while (start > 0 && isIdentifierChar(text[start - 1])) {
      start--;
    }
    return text.substring(start, offset);
  }

  /// Whether [ch] may appear in a Dart identifier (`a-z`, `A-Z`, `0-9`, `_`).
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
  ///
  /// Matching is done against [CompletionItem.effectiveFilter] rather than
  /// the label, because the Dart language server renders signatures into the
  /// label (`print(...)`) while putting the matchable identifier in
  /// `filterText` (`print`).
  ///
  /// Ordering rules, in priority order:
  /// 1. exact match to the query first (typing `int` puts `int` at the top),
  /// 2. then case-sensitive match ahead of case-insensitive
  ///    (typing `True` prefers `True` over `true`),
  /// 3. then shortest label first (typing `pri` puts `print` above
  ///    `printToConsole`),
  /// 4. then alphabetical, so the order is stable across requests.
  ///
  /// An empty [query] matches everything and preserves the server's ordering,
  /// which is what we want right after a `.` when there is no prefix yet.
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

      // Prefer an exact case match, e.g. `True` over `true` for query `True`.
      // Only consulted when BOTH items matched the query case-sensitively;
      // otherwise a case-insensitive match would be wrongly promoted.
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
}
