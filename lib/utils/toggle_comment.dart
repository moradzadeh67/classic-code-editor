import '../models/language_config.dart';

/// Pure text-manipulation helper for line comments (Cmd+/).
///
/// Modifies [text] given the current [selection] and the language [filePath] (or
/// optional explicit [overridePrefix]).
///
/// Rules:
/// - Prefix comes from [LanguageConfig.fromExtension] (`//` for Dart/C/C++/ASM, `#` for Python).
/// - If [LanguageConfig.commentPrefix] is null, returns [text] unchanged.
/// - Resolves every line intersected by [selection].
/// - If the selection ends at column 0 of a line and spans multiple lines, that last line is excluded.
/// - Blank / whitespace-only lines are skipped when adding comments.
/// - If EVERY non-blank line in the range is already commented with the prefix,
///   uncomments all of them; otherwise comments all non-blank lines.
/// - Indentation is preserved: the prefix is inserted right after the leading whitespace.
class ToggleCommentResult {
  final String text;
  final int selectionStart;
  final int selectionEnd;

  const ToggleCommentResult({
    required this.text,
    required this.selectionStart,
    required this.selectionEnd,
  });
}

ToggleCommentResult toggleComment({
  required String text,
  required int selectionStart,
  required int selectionEnd,
  String? filePath,
  String? overridePrefix,
}) {
  final prefix =
      overridePrefix ?? LanguageConfig.fromExtension(filePath).commentPrefix;
  if (prefix == null || prefix.isEmpty) {
    return ToggleCommentResult(
      text: text,
      selectionStart: selectionStart,
      selectionEnd: selectionEnd,
    );
  }

  var start = selectionStart.clamp(0, text.length);
  var end = selectionEnd.clamp(0, text.length);
  if (start > end) {
    final tmp = start;
    start = end;
    end = tmp;
  }

  // Find 0-based logical line indices.
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

  // Exclude the last line if selection ends at column 0 of that line and spans >1 lines.
  if (endLine > startLine && end == lineOffsets[endLine]) {
    endLine--;
  }

  // Check if all non-blank lines in range are already commented.
  final prefixWithSpace = '$prefix ';
  var allCommented = true;
  var nonBlankCount = 0;

  for (var i = startLine; i <= endLine; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) continue;
    nonBlankCount++;
    if (!trimmed.startsWith(prefix)) {
      allCommented = false;
    }
  }

  if (nonBlankCount == 0) {
    allCommented = false;
  }

  // Mutate lines.
  final newLines = List<String>.from(lines);
  for (var i = startLine; i <= endLine; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty && !allCommented) continue;

    final indent = line.substring(0, line.length - trimmed.length);

    if (allCommented) {
      if (trimmed.startsWith(prefixWithSpace)) {
        newLines[i] = indent + trimmed.substring(prefixWithSpace.length);
      } else if (trimmed.startsWith(prefix)) {
        newLines[i] = indent + trimmed.substring(prefix.length);
      }
    } else {
      // Commenting must never double-comment an already commented line.
      if (trimmed.startsWith(prefix)) continue;
      newLines[i] = '$indent$prefixWithSpace$trimmed';
    }
  }

  final newText = newLines.join('\n');

  // Simple selection recovery: map caret/range to start of startLine and end of endLine.
  return ToggleCommentResult(
    text: newText,
    selectionStart: start,
    selectionEnd: (end + (newText.length - text.length)).clamp(
      0,
      newText.length,
    ),
  );
}
