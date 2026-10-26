/// Pure helpers for applying the edits that come with an accepted completion
/// item (`additionalTextEdits`, e.g. the automatic import Dart adds for an
/// unimported symbol) together with the main insertion.
///
/// No business logic: document offsets and caret arithmetic only.
library;

/// A replacement in the current document, using character offsets.
class CompletionEdit {
  /// Offset (0-based) where the replaced range starts.
  final int start;

  /// Offset (0-based) where the replaced range ends (exclusive).
  final int end;

  /// Text that replaces `[start, end)`.
  final String newText;

  const CompletionEdit({
    required this.start,
    required this.end,
    required this.newText,
  });
}

/// Converts an LSP position (0-based [line] and [character]) into a character
/// offset in [text].
///
/// Positions past the end of a line clamp to that line's end, and lines past
/// the last line clamp to the end of the document, so a server that is one
/// keystroke ahead can never throw.
int offsetFromLineCharacter(
  String text, {
  required int line,
  required int character,
}) {
  var offset = 0;
  var currentLine = 0;
  while (currentLine < line) {
    final next = text.indexOf('\n', offset);
    if (next == -1) return text.length;
    offset = next + 1;
    currentLine++;
  }
  final lineEnd = text.indexOf('\n', offset);
  final maxCharacter = (lineEnd == -1 ? text.length : lineEnd) - offset;
  return offset + character.clamp(0, maxCharacter);
}

/// Applies [edits] to [text] and returns the new document plus the caret
/// offset.
///
/// [primaryIndex] identifies the edit whose `newText` contains the caret (the
/// completion insertion itself); [caretOffsetInPrimary] is the caret position
/// inside that text. Edits are applied bottom-up so earlier offsets stay
/// valid, and the caret is shifted for every edit that starts at or before
/// the primary one — that is what keeps it on the symbol after an `import`
/// line is inserted above it.
///
/// Edits with out-of-range or inverted spans are ignored rather than throwing:
/// language servers occasionally answer for a slightly older document.
(String, int) applyCompletionEdits({
  required String text,
  required List<CompletionEdit> edits,
  required int primaryIndex,
  required int caretOffsetInPrimary,
}) {
  if (edits.isEmpty) return (text, caretOffsetInPrimary);
  if (primaryIndex < 0 || primaryIndex >= edits.length) {
    return (text, caretOffsetInPrimary);
  }

  final primary = edits[primaryIndex];
  var caret = primary.start + caretOffsetInPrimary;

  for (var i = 0; i < edits.length; i++) {
    if (i == primaryIndex) continue;
    final edit = edits[i];
    if (edit.start > edit.end || edit.start < 0) continue;
    if (edit.start <= primary.start) {
      caret += edit.newText.length - (edit.end - edit.start);
    }
  }

  final ordered = List<CompletionEdit>.of(edits)
    ..sort((a, b) => b.start.compareTo(a.start));

  var result = text;
  for (final edit in ordered) {
    if (edit.start < 0 || edit.end > result.length || edit.start > edit.end) {
      continue;
    }
    result = result.replaceRange(edit.start, edit.end, edit.newText);
  }

  return (result, caret.clamp(0, result.length));
}
