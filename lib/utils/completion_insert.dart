/// Pure decision logic for what accepting a completion item inserts.
///
/// No business logic: snippet expansion, parentheses and caret arithmetic only.
library;

import 'snippet_expander.dart';

/// What the editor should insert for an accepted completion item.
class CompletionInsertion {
  /// The final text (snippet expanded, parentheses added).
  final String text;

  /// Caret offset inside [text].
  final int caretOffset;

  /// Whether a `()` pair was appended by this helper.
  final bool addedParens;

  const CompletionInsertion({
    required this.text,
    required this.caretOffset,
    this.addedParens = false,
  });
}

/// LSP `CompletionItemKind` values that are called with `()`.
const Set<int> callableCompletionKinds = {2, 3, 4};

/// Builds the text inserted for an accepted completion item.
///
/// - A snippet (`insertTextFormat == 2`) is expanded through
///   [SnippetExpander] with [indent]; the server's own snippet is authoritative,
///   so no parentheses are ever appended to it.
/// - A plain callable item (`method` = 2, `function` = 3, `constructor` = 4)
///   gets `()` and the caret is placed between them, unless the inserted text
///   already contains `(`, the document already has `(` right after the caret
///   ([nextCharIsParen]), or nothing is callable at all.
/// - Anything else (field, class, variable, keyword) is inserted as-is with the
///   caret at its end.
CompletionInsertion buildCompletionInsertion({
  required String insertText,
  required int? kindInt,
  required int? insertTextFormat,
  String? kind,
  String? indent,
  bool nextCharIsParen = false,
}) {
  if (insertText.isEmpty) {
    return const CompletionInsertion(text: '', caretOffset: 0);
  }

  if (insertTextFormat == 2) {
    final expanded = SnippetExpander.expand(insertText, indent: indent ?? '');
    return CompletionInsertion(text: expanded.$1, caretOffset: expanded.$2);
  }

  // Items from the server always carry [kindInt]; client-generated ones (the
  // built-in snippets and test fixtures) only have the normalised name.
  final isCallable = kindInt != null
      ? callableCompletionKinds.contains(kindInt)
      : (kind == 'method' || kind == 'function' || kind == 'constructor');

  if (isCallable && !insertText.contains('(') && !nextCharIsParen) {
    final text = '$insertText()';
    return CompletionInsertion(
      text: text,
      caretOffset: text.length - 1,
      addedParens: true,
    );
  }

  return CompletionInsertion(
    text: insertText,
    caretOffset: insertText.length,
  );
}
