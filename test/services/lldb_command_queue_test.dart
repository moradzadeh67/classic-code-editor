import 'dart:async';

import 'package:classic_code_editor/services/lldb_command_queue.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake-lldb transcript tests for the stdin protocol.
///
/// The real defect: lldb's stdin is a pipe, so a command written while lldb was
/// still printing the stop report arrived split (`b` + `reakpoint set -a 0x…`)
/// and the breakpoint resync silently lost that breakpoint. These tests drive the
/// protocol with byte-level transcripts - no lldb, no processes - and they fail
/// on the naive "just write the line" implementation.
void main() {
  late List<String> written;
  late List<String> console;
  late LldbCommandQueue queue;
  late int handled;

  setUp(() {
    written = <String>[];
    console = <String>[];
    handled = 0;
    queue = LldbCommandQueue(
      write: written.add,
      log: console.add,
      quietWindow: const Duration(milliseconds: 20),
      gateTimeout: const Duration(seconds: 2),
      ackTimeout: const Duration(milliseconds: 300),
    );
  });

  tearDown(() => queue.close());

  String describe() =>
      queue.writtenLines.map((line) => line.trim()).join(' | ');

  /// Acts like lldb for one tick: echoes what it just read and acknowledges
  /// every sentinel, unless [dropAck] says this one is lost.
  void answerOnce({bool Function(String sentinel, String previous)? dropAck}) {
    while (handled < queue.writtenLines.length) {
      final index = handled++;
      final line = queue.writtenLines[index].trim();
      if (!line.startsWith('script print("@@ACK')) {
        queue.handleStdoutChunk('(lldb) $line\n');
        continue;
      }
      final previous = index > 0 ? queue.writtenLines[index - 1] : '';
      if (dropAck != null && dropAck(line, previous)) continue;
      final seq = RegExp(r'\d+').firstMatch(line)!.group(0)!;
      queue.handleStdoutChunk('(lldb) $line\n@@ACK $seq\n');
    }
  }

  /// Drives the protocol until [done] completes (bounded, no fixed sleep).
  Future<void> drive(
    Future<void> done, {
    bool Function(String sentinel, String previous)? dropAck,
    void Function()? beforeAnswer,
  }) async {
    var finished = false;
    unawaited(done.whenComplete(() => finished = true));
    for (var tick = 0; tick < 600; tick++) {
      beforeAnswer?.call();
      answerOnce(dropAck: dropAck);
      if (finished && handled >= queue.writtenLines.length) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('the queue never finished; ${describe()}');
  }

  test(
    '(a) a command is held while the stop output is still arriving',
    () async {
      // lldb is mid stop-report: output keeps coming for ~60ms.
      queue.handleStdoutChunk('Process 4711 stopped\n');
      await Future<void>.delayed(const Duration(milliseconds: 15));
      queue.handleStdoutChunk('* thread #1, stop reason = breakpoint 2.1\n');
      await Future<void>.delayed(const Duration(milliseconds: 15));
      queue.handleStdoutChunk('Target 0: (x) stopped.\n(lldb) ');

      final done = queue.enqueueCommands('breakpoints', <String>[
        'breakpoint set -a 0x1000',
      ]);

      // Nothing may be written before the quiet window has elapsed.
      expect(
        written,
        isEmpty,
        reason: 'a command written during the stop report is what got split',
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(written.single, 'breakpoint set -a 0x1000\n');
      await drive(done);
    },
  );

  test('(b) bytes split across a prompt execute exactly once', () async {
    final done = queue.enqueueCommands('breakpoints', <String>[
      'breakpoint set -a 0x1000004bc',
    ]);

    // lldb reads the line and echoes it in two chunks, with the prompt in
    // between - the exact shape that produced `b` + `reakpoint set …`.
    var echoed = false;
    await drive(
      done,
      beforeAnswer: () {
        if (echoed || queue.writtenLines.isEmpty) return;
        echoed = true;
        handled = 1; // lldb consumed the line, so the echo is what we send
        queue.handleStdoutChunk('(lldb) b');
        queue.handleStdoutChunk('reakpoint set -a 0x1000004bc\n');
        queue.handleStdoutChunk('Breakpoint 2: where = x`sum_loop\n');
      },
    );

    expect(
      queue.writtenLines.where((l) => l.startsWith('breakpoint set')),
      hasLength(1),
      reason:
          'the command must not be re-sent: it was only split on the wire. '
          '${describe()}',
    );
    expect(console, isEmpty, reason: 'the ack arrived, so no retry: ${describe()}');
  });

  test('(c) a lost ack retries the unit once, idempotently', () async {
    final done = queue.enqueueCommands('breakpoints', <String>[
      'breakpoint delete 4',
      'breakpoint set -a 0x1000',
    ]);

    // The acknowledgement of the *first* `breakpoint set` is lost: the
    // breakpoint is installed, the ack never arrives - exactly the case where a
    // naive retry would leave a duplicate behind.
    var swallowed = false;
    await drive(
      done,
      dropAck: (sentinel, previous) {
        if (previous.startsWith('breakpoint set') && !swallowed) {
          swallowed = true;
          return true;
        }
        return false;
      },
    );

    expect(swallowed, isTrue, reason: 'the first set ack must be lost; ${describe()}');
    expect(
      queue.writtenLines.where((l) => l.startsWith('breakpoint set')),
      hasLength(2),
      reason: 'the retry re-sends the set: ${describe()}',
    );
    expect(
      queue.writtenLines.where((l) => l.startsWith('breakpoint delete')),
      hasLength(2),
      reason: 'and it deletes first, so no duplicate survives: ${describe()}',
    );
    final firstSet = queue.writtenLines.indexWhere(
      (l) => l.startsWith('breakpoint set'),
    );
    final lastDelete = queue.writtenLines.lastIndexWhere(
      (l) => l.startsWith('breakpoint delete'),
    );
    expect(
      lastDelete,
      greaterThan(firstSet),
      reason: 'the retry must delete before re-adding: ${describe()}',
    );
    expect(
      console,
      contains('lldb did not acknowledge "breakpoints" - retrying once'),
    );
  });

  test('(d) close() during a pending command drops the queue', () async {
    final first = queue.enqueueCommands('breakpoints', <String>[
      'breakpoint set -a 0x1',
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final queued = queue.enqueueCommands('more', <String>[
      'breakpoint set -a 0x2',
    ]);

    queue.close();
    await queued;
    await first;
    final before = written.length;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(
      written.length,
      before,
      reason: 'nothing may be written after Stop closed the queue: ${describe()}',
    );
    expect(queue.isClosed, isTrue);
  });

  test('a resume command is never acknowledged', () async {
    final done = queue.enqueueCommands('continue', <String>['continue']);
    await drive(done);
    expect(
      queue.writtenLines.where((l) => l.startsWith('script print')),
      isEmpty,
      reason: 'lldb executes nothing after a resume until the next stop: ${describe()}',
    );
  });

  test('the ack marker never reaches the console', () {
    final text = queue.handleStdoutChunk(
      '(lldb) script print("@@ACK 7")\n@@ACK 7\n(lldb) ',
    );
    expect(text, isNot(contains('@@ACK')));
  });
}
