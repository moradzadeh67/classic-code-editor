/// Pure text-manipulation helper for line operations (Duplicate Line).
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
