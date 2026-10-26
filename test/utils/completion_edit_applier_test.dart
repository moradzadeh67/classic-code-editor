import 'package:classic_code_editor/utils/completion_edit_applier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('offsetFromLineCharacter', () {
    test('maps line/character to an offset', () {
      const text = 'abc\ndef\nghi';
      expect(offsetFromLineCharacter(text, line: 0, character: 0), 0);
      expect(offsetFromLineCharacter(text, line: 1, character: 2), 6);
      expect(offsetFromLineCharacter(text, line: 2, character: 3), 11);
    });

    test('clamps out-of-range positions instead of throwing', () {
      const text = 'abc\ndef';
      expect(offsetFromLineCharacter(text, line: 9, character: 9), 7);
      expect(offsetFromLineCharacter(text, line: 0, character: 99), 3);
    });
  });

  group('applyCompletionEdits', () {
    test('inserts an import above the caret and keeps it on the symbol', () {
      // Doc: `Tim` — accepting `Timer` adds `import 'dart:async';` at 0:0.
      const text = 'Tim';
      const importText = "import 'dart:async';\n\n";

      final (newText, caret) = applyCompletionEdits(
        text: text,
        edits: const [
          CompletionEdit(start: 0, end: 3, newText: 'Timer'),
          CompletionEdit(start: 0, end: 0, newText: importText),
        ],
        primaryIndex: 0,
        caretOffsetInPrimary: 5,
      );

      expect(newText, "$importText""Timer");
      // The import is 22 characters, so the caret moved from 5 to 27.
      expect(importText.length, 22);
      expect(caret, 27);
      expect(newText.substring(caret), isEmpty);
      expect(newText.substring(newText.length - 5, caret), 'Timer');
    });

    test('applies multiple edits bottom-up so earlier offsets stay valid', () {
      const text = 'aaa bbb';
      final (newText, caret) = applyCompletionEdits(
        text: text,
        edits: const [
          CompletionEdit(start: 0, end: 3, newText: 'XYZ'),
          CompletionEdit(start: 4, end: 7, newText: 'Q'),
        ],
        primaryIndex: 0,
        caretOffsetInPrimary: 3,
      );

      expect(newText, 'XYZ Q');
      expect(caret, 3);
    });

    test('returns the text untouched when there are no edits', () {
      final (newText, caret) = applyCompletionEdits(
        text: 'abc',
        edits: const [],
        primaryIndex: 0,
        caretOffsetInPrimary: 2,
      );
      expect(newText, 'abc');
      expect(caret, 2);
    });

    test('ignores an out-of-range edit', () {
      final (newText, caret) = applyCompletionEdits(
        text: 'abc',
        edits: const [
          CompletionEdit(start: 0, end: 3, newText: 'ok'),
          CompletionEdit(start: 50, end: 60, newText: 'nope'),
        ],
        primaryIndex: 0,
        caretOffsetInPrimary: 2,
      );
      expect(newText, 'ok');
      expect(caret, 2);
    });
  });
}
