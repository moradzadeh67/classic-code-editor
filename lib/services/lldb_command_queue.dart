import 'dart:async';

/// One queued unit of lldb work: a label for error messages plus the commands
/// that must be written together.
///
/// A unit is the retry granularity: when an acknowledgement is lost the *whole*
/// unit is re-sent once, so it has to be idempotent (a breakpoint resync deletes
/// the ids it owns before installing them again).
class LldbUnit {
  LldbUnit(
    this.label,
    this.commands, {
    this.userAction = false,
    this.retryOnTimeout = true,
  });

  final String label;
  final List<String> commands;

  /// Continue/Step jump to the front of the queue: a debugger must never feel
  /// stuck behind pending breakpoint work.
  final bool userAction;

  /// Whether a lost acknowledgement may be retried (safe only when the unit is
  /// idempotent, e.g. not for `run`).
  final bool retryOnTimeout;
}

/// Serialises everything written to lldb's stdin.
///
/// Why this exists: lldb's stdin is a **pipe**, so its line editor reads
/// whatever arrives and splits it wherever it happens to be. Writing while lldb
/// is still printing the stop report cut a command in two - `breakpoint set -a
/// 0x…` reached lldb as `b` + `reakpoint set -a 0x…`, i.e. "resync the
/// breakpoints" silently lost one (measured with a byte-level trace of stdin and
/// of the raw stdout chunks). So:
///
///  * one command is in flight at a time, written as **one** line;
///  * a command is only written when lldb has been quiet for [quietWindow];
///  * every non-resuming command is verified with a `script print("@@ACK n")`
///    sentinel (sent as its own line, once lldb is idle again - a batched
///    `cmd\nscript print(...)` is read ahead by lldb's input thread, echoed
///    immediately and executed only after the command finished, which never
///    happens for a command that resumes the target);
///  * a lost acknowledgement retries the whole unit once, and the console is
///    told when that happens;
///  * [close] drops everything immediately, so Stop never waits for a command
///    stuck behind the gate.
class LldbCommandQueue {
  LldbCommandQueue({
    required this.write,
    this.log,
    this.quietWindow = const Duration(milliseconds: 40),
    this.gateTimeout = const Duration(seconds: 5),
    this.ackTimeout = const Duration(seconds: 5),
  });

  /// Writes one line to lldb's stdin (the newline is added here).
  final void Function(String line) write;

  /// Reports protocol problems on the Console ([log] receives one line).
  final void Function(String line)? log;

  /// How long lldb must be silent before a command may be written.
  final Duration quietWindow;

  /// How long to wait for lldb to become idle before giving up on a command.
  final Duration gateTimeout;

  /// How long to wait for the acknowledgement sentinel of a command.
  final Duration ackTimeout;

  /// Commands that start or resume the inferior. They are written one line at a
  /// time and *not* acknowledged: lldb does not execute anything after them
  /// until the target stops again.
  static const List<String> resumeCommands = <String>[
    'run',
    'continue',
    'process launch',
    'thread step',
    'next',
    'step',
    'finish',
    'process kill',
    'quit',
  ];

  static bool isResumeCommand(String command) {
    final trimmed = command.trimLeft();
    return resumeCommands.any(trimmed.startsWith);
  }

  final List<LldbUnit> _pending = <LldbUnit>[];
  bool _running = false;
  bool _closed = false;
  DateTime _lastOutputAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastWriteAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _ackSeq = 0;
  Completer<void>? _ackWaiter;

  /// Pid parsed from `Process <pid> launched`, so a killed session cannot leave
  /// the inferior running.
  int? inferiorPid;

  /// Every line actually written, in order. Only used by tests.
  final List<String> writtenLines = <String>[];

  bool get isClosed => _closed;

  /// Queues [unit]; the returned future completes when the queue has drained it
  /// (or when it gave up), which makes it usable from tests.
  Future<void> enqueue(LldbUnit unit) {
    if (_closed) return Future<void>.value();
    if (unit.userAction) {
      _pending.insert(0, unit);
    } else {
      _pending.add(unit);
    }
    return _pump();
  }

  Future<void> enqueueCommands(String label, List<String> commands) =>
      enqueue(LldbUnit(label, commands));

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_pending.isNotEmpty && !_closed) {
        final unit = _pending.removeAt(0);
        var ok = await _sendUnit(unit);
        if (!ok && unit.retryOnTimeout && !_closed) {
          // A lost ack means lldb may have swallowed the line. Retry the whole
          // unit once; units are idempotent by contract.
          log?.call('lldb did not acknowledge "${unit.label}" - retrying once');
          ok = await _sendUnit(unit);
        }
        if (!ok && !_closed) {
          log?.call('could not send "${unit.label}" to lldb');
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<bool> _sendUnit(LldbUnit unit) async {
    for (final command in unit.commands) {
      if (_closed) return false;
      if (!await _sendCommand(command)) return false;
    }
    return true;
  }

  Future<bool> _sendCommand(String command) async {
    if (!await _waitForIdle()) return false;
    _writeLine(command);
    if (isResumeCommand(command)) return true;

    // The sentinel goes out as its own line, once lldb is idle again.
    if (!await _waitForIdle()) return false;
    final seq = ++_ackSeq;
    final waiter = Completer<void>();
    _ackWaiter = waiter;
    _writeLine('script print("@@ACK $seq")');
    try {
      await waiter.future.timeout(ackTimeout);
      return true;
    } on TimeoutException {
      // The line may have been swallowed; let the retry (or the next unit) go
      // through instead of blocking every later command on a dead flag.
      return false;
    } finally {
      if (identical(_ackWaiter, waiter)) _ackWaiter = null;
    }
  }

  void _writeLine(String line) {
    _lastWriteAt = DateTime.now();
    writtenLines.add(line);
    write('$line\n');
  }

  /// True when nothing is outstanding, lldb has been quiet for [quietWindow],
  /// and nothing was written during that window.
  bool get isReadyForInput {
    if (_ackWaiter != null) return false;
    final now = DateTime.now();
    return now.difference(_lastOutputAt) >= quietWindow &&
        now.difference(_lastWriteAt) >= quietWindow;
  }

  Future<bool> _waitForIdle() async {
    final deadline = DateTime.now().add(gateTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_closed) return false;
      if (isReadyForInput) return true;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return false;
  }

  /// Feeds a raw stdout chunk through the protocol state machine and returns the
  /// text the Console should see.
  ///
  /// Must be called with the **raw** chunks (before any line splitting): the
  /// acknowledgement knowledge lives in the line boundaries, and the marker must
  /// be stripped so it can never reach the Console.
  String handleStdoutChunk(String chunk) {
    _lastOutputAt = DateTime.now();

    final launched = RegExp(r'Process (\d+) launched').firstMatch(chunk);
    if (launched != null) {
      inferiorPid = int.tryParse(launched.group(1)!);
    }

    // An acknowledgement only counts as a whole line of its own: the echo of
    // `script print("@@ACK n")` also contains the marker, and completing on it
    // would release the next command while this one is still running.
    final ackLine = RegExp(r'(?:^|\n)@@ACK (\d+)[ \t]*(?=\n|$)');
    for (final match in ackLine.allMatches(chunk)) {
      final seq = int.tryParse(match.group(1)!);
      final waiter = _ackWaiter;
      if (seq == _ackSeq && waiter != null && !waiter.isCompleted) {
        waiter.complete();
      }
    }

    // Strip both the ack output and the echo of the sentinel itself, which the
    // input thread prints as soon as it reads the line (`(lldb) ` may be in a
    // different chunk, so it cannot be relied on here). What is left of an echo
    // line is just a prompt, which the chatter filter drops.
    return chunk
        .replaceAll(ackLine, '\n')
        .replaceAll(RegExp(r'script print\("@@ACK \d+"\)'), '');
  }

  /// Drops every pending command and stops queueing. Used by Stop and by the
  /// finalizer, so the kill sequence is never queued behind a stuck command.
  void close() {
    _closed = true;
    _pending.clear();
    final waiter = _ackWaiter;
    _ackWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }
}
