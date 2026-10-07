/// Represents an LSP completion item.
class CompletionItem {
  final String label;
  final String kind;
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

  const CompletionItem({
    required this.label,
    required this.kind,
    this.detail,
    this.insertText,
    this.textEditNewText,
    this.filterText,
  });

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
