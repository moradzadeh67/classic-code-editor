import 'package:classic_code_editor/utils/completion_docs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCompletionDocumentation', () {
    test('strips inline code, bold markers and link targets', () {
      final raw =
          'Returns a **bold** value from [`Timer`](dart:async/Timer).';
      expect(
        formatCompletionDocumentation(raw),
        'Returns a bold value from Timer.',
      );
    });

    test('keeps line breaks and drops heading markers', () {
      final raw = '## Summary\nLine one\nLine two';
      expect(
        formatCompletionDocumentation(raw),
        'Summary\nLine one\nLine two',
      );
    });

    test('keeps fenced code but removes the fence markers', () {
      final raw = 'Example:\n```dart\nvoid main() {}\n```';
      expect(
        formatCompletionDocumentation(raw),
        'Example:\n\nvoid main() {}',
      );
    });

    test('truncates to 12 lines and appends an ellipsis line', () {
      final raw = List.generate(30, (i) => 'line $i').join('\n');
      final result = formatCompletionDocumentation(raw);
      final lines = result.split('\n');

      expect(lines.length, 13);
      expect(lines.first, 'line 0');
      expect(lines[11], 'line 11');
      expect(lines.last, '…');
      expect(result.contains('line 12'), isFalse);
    });

    test('plain text without markdown is unchanged', () {
      expect(
        formatCompletionDocumentation('Just text.\nSecond line.'),
        'Just text.\nSecond line.',
      );
    });

    test('empty input stays empty', () {
      expect(formatCompletionDocumentation(''), '');
    });
  });
}
