/// Pure snippet-expansion helper (LSP snippet syntax).
///
/// Rules:
/// - `${n:default}` → insert `default`; caret stops at $n.
/// - `$n` → placeholder with no default; caret stops at $n.
/// - `$$` → literal `$`.
/// - `$0` → final cursor position (after all tab stops visited).
/// - Multi-line text: prefix each new line with current indentation.
///
/// Output: (plainText, caretOffset, firstPlaceholderRange?)
class SnippetExpander {
  /// Expands [snippet] and returns (expandedText, caretOffset).
  ///
  /// If snippet contains tab stops (`$1`, `${2:...}`), [caretOffset] points
  /// to the first tab stop (`$1` before `$2`, before `$0`). If only `$0`
  /// exists, caret points there; if none exist, at end of text.
  static (String, int) expand(String snippet, {String? indent}) {
    final buffer = StringBuffer();
    final placeholderDefaults = <int, String>{};
    int caretOffset = -1; // -1 = none yet; set to first tab stop

    int i = 0;
    while (i < snippet.length) {
      final ch = snippet[i];
      if (ch == r'$' && i + 1 < snippet.length) {
        final next = snippet[i + 1];
        if (next == r'$') {
          // Escaped dollar
          buffer.write(r'$');
          i += 2;
        } else if (next == '{') {
          // ${n:default} or ${n}
          final braceEnd = snippet.indexOf('}', i + 2);
          if (braceEnd == -1) {
            // Malformed: treat as literal
            buffer.write(ch);
            i++;
          } else {
            final inner = snippet.substring(i + 2, braceEnd);
            final colonIdx = inner.indexOf(':');
            String numberStr = colonIdx >= 0 ? inner.substring(0, colonIdx) : inner;
            String defaultText = colonIdx >= 0 ? inner.substring(colonIdx + 1) : '';
            final number = int.tryParse(numberStr.trim()) ?? 0;
            placeholderDefaults[number] ??= defaultText;
            buffer.write(defaultText);
            final newCaret = buffer.length - defaultText.length;
            if (number > 0 && caretOffset == -1) {
              caretOffset = newCaret;
            }
            if (number == 0 && caretOffset == -1) {
              // $0 is the final stop; use it as fallback only if no $1+
              caretOffset = newCaret;
            }
            i = braceEnd + 1;
          }
        } else if (RegExp(r'[0-9]').hasMatch(next)) {
          // Simple $n (single digit for simplicity; multi-digit handled via braces)
          final numberStr = next;
          final number = int.parse(numberStr);
          String defaultText = placeholderDefaults[number] ?? '';
          buffer.write(defaultText);
          final newCaret = buffer.length - defaultText.length;
          if (number > 0 && caretOffset == -1) {
            caretOffset = newCaret;
          }
          if (number == 0 && caretOffset == -1) {
            caretOffset = newCaret;
          }
          placeholderDefaults[number] ??= defaultText;
          i += 2;
        } else {
          // Unknown escape sequence, treat as literal
          buffer.write(ch);
          i++;
        }
      } else {
        buffer.write(ch);
        i++;
      }
    }

    // Multi-line: prefix each line with current indentation
    final expandedText = indent != null && indent.isNotEmpty
        ? _applyIndent(buffer.toString(), indent)
        : buffer.toString();

    final finalCaretOffset = caretOffset >= 0 ? caretOffset : expandedText.length;
    return (expandedText, finalCaretOffset);
  }

  static String _applyIndent(String text, String indent) {
    final lines = text.split('\n');
    final result = <String>[];
    for (int idx = 0; idx < lines.length; idx++) {
      if (idx == 0) {
        result.add(lines[idx]);
      } else {
        result.add(indent + lines[idx]);
      }
    }
    return result.join('\n');
  }

  /// Returns the default text for a given placeholder index (for mirroring).
  static String? defaultForPlaceholder(int index, Map<int, String> defaults) {
    return defaults[index];
  }
}
