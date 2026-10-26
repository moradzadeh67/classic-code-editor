import 'package:classic_code_editor/utils/snippet_expander.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SnippetExpander.expand', () {
    test('plain text with no placeholders', () {
      final result = SnippetExpander.expand('hello');
      expect(result.$1, 'hello');
      expect(result.$2, 5);
    });

    test(r'no tab stop (0 only) -> caret at 0', () {
      final result = SnippetExpander.expand(r'func($0)');
      expect(result.$1, 'func()');
      expect(result.$2, 5);
    });

    test(r'$1 tab stop → caret at first $1', () {
      final result = SnippetExpander.expand(r'print($1)');
      expect(result.$1, 'print()');
      expect(result.$2, 6);
    });

    test('placeholder with default inserts default, caret at start', () {
      final result = SnippetExpander.expand(r'log(${1:msg})');
      expect(result.$1, 'log(msg)');
      expect(result.$2, 4);
    });

    test('same-index placeholders get same default text', () {
      final result = SnippetExpander.expand(r'${1:foo} and ${1:foo}');
      expect(result.$1, 'foo and foo');
      expect(result.$2, 0);
    });

    test('escaped dollar -> literal dollar', () {
      final result = SnippetExpander.expand(r'cost is $$5');
      expect(result.$1, r'cost is $5');
      expect(result.$2, 10);
    });

    test('multi-line with indentation', () {
      final result = SnippetExpander.expand('line1\nline2', indent: '  ');
      expect(result.$1, 'line1\n  line2');
      expect(result.$2, 13);
    });
  });
}
