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
/// - A *call* snippet — `name(...)` where the argument list holds nothing but
///   placeholders — becomes `name()` with the caret inside. The placeholder
///   defaults there are parameter *declarations* (`Object? object`,
///   `int a`), so expanding them typed a signature the user never wrote. See
///   [collapseToEmptyCall].
/// - Any other snippet (`insertTextFormat == 2`) is expanded through
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
    final callName = collapseToEmptyCall(insertText);
    if (callName != null && !nextCharIsParen) {
      final text = '$callName()';
      return CompletionInsertion(
        text: text,
        caretOffset: text.length - 1,
        addedParens: true,
      );
    }

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

  return CompletionInsertion(text: insertText, caretOffset: insertText.length);
}

/// Matches a snippet that is exactly one call: `name(...)`.
///
/// The argument list is captured so its contents can be inspected.
final RegExp _callSnippetShape = RegExp(
  r'^([A-Za-z_$][A-Za-z0-9_$]*)\((.*)\)$',
  dotAll: true,
);

/// A `${n:default}` placeholder, default included.
final RegExp _bracedPlaceholder = RegExp(r'\$\{\d+[^}]*\}');

/// A bare `$n` placeholder.
final RegExp _plainPlaceholder = RegExp(r'\$\d+');

/// What may remain in an argument list once every placeholder is removed:
/// separators only, so the list carries no real code.
final RegExp _separatorsOnly = RegExp(r'^[\s,\[\]{}]*$');

/// Returns the callee name when [snippet] is a call whose argument list is
/// nothing but placeholders — `print(${1:Object? object})`, `f(${1:int a},
/// ${2:int b})` — and `null` otherwise.
///
/// The Dart language server describes every parameter as a placeholder whose
/// default is the parameter *declaration*. Expanding those defaults typed a
/// signature the user never wrote (`print(Object? object)`), so the caller
/// turns such a snippet into an empty `name()` and lets the user fill it in.
///
/// A snippet that carries real code inside the call is left untouched: the
/// `setState(() { $0 })` shape keeps its closure body because `()` is not a
/// separator.
String? collapseToEmptyCall(String snippet) {
  // A trailing `$0` is only “leave the caret at the end of the call”.
  final trimmed = snippet.replaceAll(r'$0', '').trim();
  final match = _callSnippetShape.firstMatch(trimmed);
  if (match == null) return null;

  final inner = match.group(2)!.replaceAll(_bracedPlaceholder, '');
  final rest = inner.replaceAll(_plainPlaceholder, '');
  if (!_separatorsOnly.hasMatch(rest)) return null;

  return match.group(1);
}
