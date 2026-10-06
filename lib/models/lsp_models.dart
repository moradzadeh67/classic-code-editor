/// Represents an LSP completion item.
class CompletionItem {
  final String label;
  final String kind;
  final String? detail;
  final String? insertText;
  final String? textEditNewText;

  const CompletionItem({
    required this.label,
    required this.kind,
    this.detail,
    this.insertText,
    this.textEditNewText,
  });

  String get effectiveInsert => textEditNewText ?? insertText ?? label;
}

/// Represents LSP hover information.
class HoverInfo {
  final String content;

  const HoverInfo({required this.content});
}
