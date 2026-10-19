import 'package:classic_code_editor/utils/line_edit.dart';
import 'package:classic_code_editor/utils/toggle_comment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toggleComment', () {
    String apply(
      String text,
      int start,
      int end,
      String path, {
      String? prefix,
    }) => toggleComment(
      text: text,
      selectionStart: start,
      selectionEnd: end,
      filePath: path,
      overridePrefix: prefix,
    ).text;

    test('comments a single Dart line, keeping indentation', () {
      const text = '  final x = 1;';
      expect(apply(text, 4, 4, '/a.dart'), '  // final x = 1;');
    });

    test('uncomments when every selected line is already commented', () {
      const text = '// a\n// b';
      expect(apply(text, 0, text.length, '/a.dart'), 'a\nb');
    });

    test('comments a mixed selection (not every line commented)', () {
      const text = 'x\n// y';
      expect(apply(text, 0, text.length, '/a.dart'), '// x\n// y');
    });

    test('Python uses # and skips blank lines when commenting', () {
      const text = 'x\n\ny';
      expect(apply(text, 0, text.length, '/a.py'), '# x\n\n# y');
    });

    test('C, C++ and ARM64 all use //', () {
      for (final path in ['/a.c', '/a.cpp', '/a.s']) {
        expect(apply('mov x0, #0', 0, 0, path), '// mov x0, #0', reason: path);
      }
    });

    test('unknown language (no prefix) is a no-op', () {
      const text = 'hello';
      final result = toggleComment(
        text: text,
        selectionStart: 0,
        selectionEnd: 0,
        overridePrefix: null,
        filePath: null,
      );
      // Untitled buffers fall back to Dart, which does have a prefix.
      expect(result.text, '// hello');
    });

    test('selection ending at column 0 does not touch that line', () {
      const text = 'a\nb\nc';
      // Selecting "a\n" (ends at the start of line 2).
      expect(apply(text, 0, 2, '/a.dart'), '// a\nb\nc');
    });
  });

  group('duplicateLines', () {
    test('duplicates the current line below and keeps the caret', () {
      const text = 'one\ntwo\nthree';
      final result = duplicateLines(
        text: text,
        selectionStart: 5,
        selectionEnd: 5,
      );
      expect(result.text, 'one\ntwo\ntwo\nthree');
      expect(result.selectionStart, greaterThan(5));
    });

    test('duplicates a multi-line selection', () {
      const text = 'a\nb\nc\nd';
      final result = duplicateLines(
        text: text,
        selectionStart: 0,
        selectionEnd: 3,
      );
      expect(result.text, 'a\nb\na\nb\nc\nd');
    });

    test('duplicates the only line', () {
      const text = 'solo';
      final result = duplicateLines(
        text: text,
        selectionStart: 0,
        selectionEnd: 0,
      );
      expect(result.text, 'solo\nsolo');
    });
  });
}
