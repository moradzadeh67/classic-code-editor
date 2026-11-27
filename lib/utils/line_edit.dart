/// Pure text-manipulation helpers for line operations (Duplicate Line, the
/// J+K "end the statement" chord).
library;

/// Highlight languages whose statements end with `;` (the J+K chord only
/// works in these).
const Set<String> semicolonLanguages = <String>{'dart', 'c', 'cpp'};

/// Text and caret after [endStatement].
class EndStatementResult {
  final String text;
  final int caret;

  const EndStatementResult({required this.text, required this.caret});
}

/// Ends the statement on the line that holds [caret]: the caret goes to the
/// end of that line and a `;` is added there.
///
/// No `;` is added when the line already ends with `;`, ends with `{` (a block
/// opener, where `;` is always wrong) or is blank; the caret still moves to
/// the end. Trailing spaces are replaced by the `;`.
EndStatementResult endStatement({required String text, required int caret}) {
  final offset = caret.clamp(0, text.length);
  final newline = text.indexOf('\n', offset);
  final lineEnd = newline == -1 ? text.length : newline;
  final lineStart = offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
  final content = text.substring(lineStart, lineEnd).trimRight();

  if (content.trim().isEmpty ||
      content.endsWith(';') ||
      content.endsWith('{')) {
    return EndStatementResult(text: text, caret: lineEnd);
  }
  final contentEnd = lineStart + content.length;
  final newText = text.replaceRange(contentEnd, lineEnd, ';');
  return EndStatementResult(text: newText, caret: contentEnd + 1);
}

/// Text and selection after [duplicateLines].
class DuplicateLineResult {
  final String text;
  final int selectionStart;
  final int selectionEnd;

  const DuplicateLineResult({
    required this.text,
    required this.selectionStart,
    required this.selectionEnd,
  });
}

/// Duplicates the current line (or range of selected lines) below it.
DuplicateLineResult duplicateLines({
  required String text,
  required int selectionStart,
  required int selectionEnd,
}) {
  if (text.isEmpty) {
    return DuplicateLineResult(text: '\n', selectionStart: 1, selectionEnd: 1);
  }

  var start = selectionStart.clamp(0, text.length);
  var end = selectionEnd.clamp(0, text.length);
  if (start > end) {
    final tmp = start;
    start = end;
    end = tmp;
  }

  final lines = text.split('\n');
  final lineOffsets = <int>[0];
  for (var i = 0; i < lines.length - 1; i++) {
    lineOffsets.add(lineOffsets.last + lines[i].length + 1);
  }

  int startLine = 0;
  while (startLine < lines.length - 1 && lineOffsets[startLine + 1] <= start) {
    startLine++;
  }

  int endLine = startLine;
  while (endLine < lines.length - 1 && lineOffsets[endLine + 1] <= end) {
    endLine++;
  }

  if (endLine > startLine && end == lineOffsets[endLine]) {
    endLine--;
  }

  final targetBlock = lines.sublist(startLine, endLine + 1).join('\n');
  final newLines = List<String>.from(lines);
  newLines.insertAll(endLine + 1, lines.sublist(startLine, endLine + 1));

  final newText = newLines.join('\n');
  final addedOffset = targetBlock.length + 1;

  return DuplicateLineResult(
    text: newText,
    selectionStart: (start + addedOffset).clamp(0, newText.length),
    selectionEnd: (end + addedOffset).clamp(0, newText.length),
  );
}
