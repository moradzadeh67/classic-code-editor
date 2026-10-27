import 'package:classic_code_editor/utils/completion_retry.dart';
import 'package:flutter_test/flutter_test.dart';

/// TASK-084: the popup re-queries a warming-up language server on a bounded
/// backoff instead of staying on the local keyword list forever.
void main() {
  group('CompletionRetry', () {
    test('backs off 300 ms, 1 s, 2 s, then every 2 s', () {
      expect(CompletionRetry.delayFor(0), const Duration(milliseconds: 300));
      expect(CompletionRetry.delayFor(1), const Duration(seconds: 1));
      expect(CompletionRetry.delayFor(2), const Duration(seconds: 2));
      expect(CompletionRetry.delayFor(3), const Duration(seconds: 2));
      expect(CompletionRetry.delayFor(99), const Duration(seconds: 2));
      // A negative attempt is clamped to the first delay.
      expect(CompletionRetry.delayFor(-1), const Duration(milliseconds: 300));
    });

    test('gives up 20 s after the first local answer', () {
      final first = DateTime(2026, 1, 1, 12);
      expect(
        CompletionRetry.expired(first, first.add(const Duration(seconds: 19))),
        isFalse,
      );
      expect(
        CompletionRetry.expired(first, first.add(const Duration(seconds: 20))),
        isTrue,
      );
      expect(
        CompletionRetry.expired(first, first.add(const Duration(minutes: 2))),
        isTrue,
      );
    });

    test('a schedule of the first six attempts fits inside the window', () {
      var elapsed = Duration.zero;
      for (var attempt = 0; attempt < 6; attempt++) {
        elapsed += CompletionRetry.delayFor(attempt);
      }
      expect(elapsed, const Duration(seconds: 9, milliseconds: 300));
      expect(elapsed, lessThan(CompletionRetry.window));
    });
  });
}
