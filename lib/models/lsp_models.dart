/// A single LSP `TextEdit` attached to a completion item.
///
/// Ranges are kept in LSP form (0-based line / character) and converted to
/// document offsets by `completion_edit_applier.dart` when the edit is
/// applied.
class CompletionTextEdit {
  final int startLine;
  final int startCharacter;
  final int endLine;
  final int endCharacter;
  final String newText;

  const CompletionTextEdit({
    required this.startLine,
    required this.startCharacter,
    required this.endLine,
    required this.endCharacter,
    required this.newText,
  });
}

/// The parts of a `completionItem/resolve` answer this client understands.
class ResolvedCompletionItem {
  /// Documentation as sent by the server (plain text or the value of a
  /// `MarkupContent` object), before any markdown stripping.
  final String? documentation;

  /// Optional `detail` the server only adds on resolve. For Dart's automatic
  /// imports this is e.g. `Auto import from 'dart:async'`.
  final String? detail;

  /// Edits that must be applied together with the main insertion — for Dart
  /// this is the `import 'dart:async';` line for an unimported symbol.
  final List<CompletionTextEdit> additionalTextEdits;

  /// The document version the server resolved against, or `null` when unknown.
  ///
  /// The editor only applies [additionalTextEdits] while the document is still
  /// at this version; otherwise the edit ranges describe older text.
  final int? documentVersion;

  const ResolvedCompletionItem({
    this.documentation,
    this.detail,
    this.additionalTextEdits = const [],
    this.documentVersion,
  });
}

/// Represents an LSP completion item.
class CompletionItem {
  final String label;

  /// The normalised kind used by the popup and the insertion rules
  /// (`method`, `function`, `field`, `snippet`, …).
  final String kind;

  /// The raw LSP `CompletionItemKind` int (1 = text, 2 = method, 3 = function,
  /// 4 = constructor, 7 = class, 15 = snippet, …), or `null` for items this
  /// client generated itself.
  ///
  /// The name above is lossy — the server reports methods, functions and
  /// constructors as three kinds while `kind` calls them all `method` — and the
  /// parentheses rule must follow what the server actually said.
  final int? kindInt;

  final String? detail;
  final String? insertText;
  final String? textEditNewText;

  /// The text the language server wants us to match the typed prefix against.
  ///
  /// This differs from [label] for items whose label carries a rendered
  /// signature: the Dart language server returns
  /// `label: "print(...)"` together with `filterText: "print"`. Filtering on
  /// the label alone still happens to work there, but for other items the
  /// label is purely a human-readable description and only [filterText]
  /// matches what the user actually typed.
  final String? filterText;
  /// LSP `insertTextFormat`: 1 = plain text, 2 = snippet.
  final int? insertTextFormat;
  /// LSP `sortText`: server-provided ranking string.
  final String? sortText;

  /// Documentation sent with the completion item itself (may be absent; most
  /// servers only send it from `completionItem/resolve`).
  final String? documentation;

  /// Edits the server wants applied with the main insertion. Mostly absent on
  /// the initial list and delivered by `completionItem/resolve` instead.
  final List<CompletionTextEdit> additionalTextEdits;

  /// The original JSON of the item, kept verbatim so `completionItem/resolve`
  /// can send it back (it carries the server-specific `data` field).
  final Map<String, dynamic>? raw;

  const CompletionItem({
    required this.label,
    required this.kind,
    this.kindInt,
    this.detail,
    this.insertText,
    this.textEditNewText,
    this.filterText,
    this.insertTextFormat,
    this.sortText,
    this.documentation,
    this.additionalTextEdits = const [],
    this.raw,
  });

  /// Whether the server asks for a `completionItem/resolve` round-trip before
  /// the item is complete (Dart sets `data` on auto-import and documented
  /// items).
  bool get needsResolve => raw != null && raw!.containsKey('data');

  /// The text used to insert the item into the document.
  String get effectiveInsert => textEditNewText ?? insertText ?? displayLabel;

  /// The text used to match against what the user has typed.
  ///
  /// Falls back to [label] when the server did not supply [filterText], which
  /// is the behaviour mandated by the LSP specification.
  String get effectiveFilter => filterText ?? label;

  /// The label to actually render in the completion popup.
  ///
  /// The Dart language server renders a signature into the label
  /// (`print(...)`, `printTo(...)`) and puts the bare identifier in
  /// `filterText` (`print`, `printTo`). Showing the raw label makes the list
  /// noisy, so prefer the bare identifier when the server gave us one and the
  /// label is clearly a rendered signature (it has parentheses the filter text
  /// does not).
  String get displayLabel {
    final filter = filterText;
    if (filter != null &&
        filter.isNotEmpty &&
        label.contains('(') &&
        !filter.contains('(')) {
      return filter;
    }
    return label;
  }
}

/// Represents LSP hover information.
class HoverInfo {
  final String content;

  const HoverInfo({required this.content});
}
