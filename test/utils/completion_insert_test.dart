import 'package:classic_code_editor/utils/completion_insert.dart';
import 'package:flutter_test/flutter_test.dart';

/// One row of the accept table: what the server sends, what is inserted.
class _Case {
  const _Case({
    required this.name,
    required this.insertText,
    required this.kind,
    required this.kindInt,
    required this.expected,
    required this.expectedCaret,
    this.nextCharIsParen = false,
    this.insertTextFormat,
  });

  final String name;
  final String insertText;
  final String? kind;
  final int? kindInt;
  final String expected;
  final int expectedCaret;
  final bool nextCharIsParen;
  final int? insertTextFormat;
}

void main() {
  group('buildCompletionInsertion', () {
    final cases = <_Case>[
      _Case(
        name: 'print (method) gets an empty pair and the caret inside',
        insertText: 'print',
        kind: 'method',
        kindInt: 2,
        expected: 'print()',
        expectedCaret: 6,
      ),
      _Case(
        name: 'setState (method) gets an empty pair and the caret inside',
        insertText: 'setState',
        kind: 'method',
        kindInt: 2,
        expected: 'setState()',
        expectedCaret: 9,
      ),
      _Case(
        name: 'a field is inserted without parentheses',
        insertText: 'length',
        kind: 'field',
        kindInt: 5,
        expected: 'length',
        expectedCaret: 6,
      ),
      _Case(
        name: 'a class is inserted without parentheses',
        insertText: 'Timer',
        kind: 'class',
        kindInt: 7,
        expected: 'Timer',
        expectedCaret: 5,
      ),
      _Case(
        name: 'an existing "(" after the caret suppresses the pair',
        insertText: 'print',
        kind: 'method',
        kindInt: 2,
        expected: 'print',
        expectedCaret: 5,
        nextCharIsParen: true,
      ),
      _Case(
        name: 'text that already has "(" is left alone',
        insertText: 'print(x)',
        kind: 'method',
        kindInt: 2,
        expected: 'print(x)',
        expectedCaret: 8,
      ),
      _Case(
        name: 'a snippet with parentheses is expanded, not extended',
        insertText: r'print($0)',
        kind: 'snippet',
        kindInt: 15,
        insertTextFormat: 2,
        expected: 'print()',
        expectedCaret: 6,
      ),
      _Case(
        name: 'a snippet without parentheses never gets a pair',
        insertText: r'''for (final $1 in $2) {
$0
}''',
        kind: 'snippet',
        kindInt: 15,
        insertTextFormat: 2,
        expected: 'for (final  in ) {\n\n}',
        expectedCaret: 11,
      ),
    ];

    for (final testCase in cases) {
      test(testCase.name, () {
        final insertion = buildCompletionInsertion(
          insertText: testCase.insertText,
          kind: testCase.kind,
          kindInt: testCase.kindInt,
          insertTextFormat: testCase.insertTextFormat,
          nextCharIsParen: testCase.nextCharIsParen,
        );

        expect(insertion.text, testCase.expected);
        expect(insertion.caretOffset, testCase.expectedCaret);
      });
    }

    test('a method without a raw kind still falls back to the kind name', () {
      final insertion = buildCompletionInsertion(
        insertText: 'forEach',
        kind: 'method',
        kindInt: null,
        insertTextFormat: null,
      );
      expect(insertion.text, 'forEach()');
      expect(insertion.caretOffset, 8);
      expect(insertion.addedParens, isTrue);
    });

    test('a function (kind 3) and a constructor (kind 4) are callable', () {
      for (final kindInt in <int>[3, 4]) {
        final insertion = buildCompletionInsertion(
          insertText: 'f',
          kind: 'method',
          kindInt: kindInt,
          insertTextFormat: null,
        );
        expect(insertion.text, 'f()', reason: 'kind $kindInt');
        expect(insertion.caretOffset, 2, reason: 'kind $kindInt');
      }
    });

    test('a snippet is indented on every continuation line', () {
      final insertion = buildCompletionInsertion(
        insertText: r'''void main() {
  $0
}''',
        kind: 'snippet',
        kindInt: 15,
        insertTextFormat: 2,
        indent: '  ',
      );
      expect(insertion.text, 'void main() {\n    \n  }');
      expect(insertion.caretOffset, 16);
    });
  });
}
