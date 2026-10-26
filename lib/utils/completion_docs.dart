/// Pure helpers for turning language-server documentation into the plain text
/// the completion documentation panel renders.
///
/// No business logic: markdown stripping and line truncation only.
library;

/// Converts LSP documentation (plain text, or markdown from Dart's doc
/// comments) into plain text for the retro editor.
///
/// - fenced code fences drop their ```` ``` ```` markers, the code stays,
/// - inline backticks, `**bold**`/`__bold__` markers are removed,
/// - links `[text](url)` become their text,
/// - ATX heading markers (`## `) are removed,
/// - line breaks are preserved (runs of 3+ blank lines collapse to one),
/// - output longer than [maxLines] is cut and gets a trailing `…` line.
String formatCompletionDocumentation(String raw, {int maxLines = 12}) {
  if (raw.isEmpty) return '';

  var text = raw.replaceAll('\r\n', '\n');

  // Fenced code block delimiters (```dart, ```), keep the code itself.
  text = text.replaceAll(RegExp(r'^[ \t]*```[^\n]*$', multiLine: true), '');

  // Markdown links: keep the label, drop the target.
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );

  // Emphasis markers.
  text = text.replaceAll('**', '').replaceAll('__', '');

  // Inline code and the remaining stray backticks.
  text = text.replaceAll('`', '');

  // ATX headings.
  text = text.replaceAll(RegExp(r'^[ \t]{0,3}#{1,6}[ \t]*', multiLine: true), '');

  // Collapse the blank lines that removing fences/headings can leave behind.
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

  final lines = text.split('\n');
  if (lines.length <= maxLines) return text;
  return '${lines.take(maxLines).join('\n')}\n…';
}
