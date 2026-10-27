/// Backoff for re-querying a language server that is still warming up.
///
/// While the server has not answered yet the popup keeps showing the local
/// word/keyword list, so a slow first answer must not look like "no
/// completions". The popup re-queries on this schedule until the server answers
/// with something or [window] has passed since the first local answer.
class CompletionRetry {
  const CompletionRetry._();

  /// How long after the first local answer retries stop.
  static const Duration window = Duration(seconds: 20);

  /// First three delays, in milliseconds; every later attempt reuses the last
  /// one (300 ms → 1 s → 2 s → 2 s → …).
  static const List<int> delaysMs = <int>[300, 1000, 2000];

  /// Delay before attempt number [attempt] (0-based).
  static Duration delayFor(int attempt) {
    final index = attempt < 0
        ? 0
        : (attempt >= delaysMs.length ? delaysMs.length - 1 : attempt);
    return Duration(milliseconds: delaysMs[index]);
  }

  /// Whether the retry budget that started at [firstAnswer] is spent at [now].
  static bool expired(DateTime firstAnswer, DateTime now) =>
      now.difference(firstAnswer) >= window;
}
