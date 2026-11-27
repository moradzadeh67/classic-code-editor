import 'package:classic_code_editor/utils/line_edit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('endStatement', () {
    test('adds ; at the end of the caret line and moves the caret there', () {
      final result = endStatement(text: 'foo(1)\nbar()', caret: 2);
      expect(result.text, 'foo(1);\nbar()');
      expect(result.caret, 7);
    });

    test('works on the last line and at the very start', () {
      expect(endStatement(text: 'a\nb', caret: 3).text, 'a\nb;');
      expect(endStatement(text: 'x = 1', caret: 0).text, 'x = 1;');
    });

    test('replaces trailing spaces with the ;', () {
      final result = endStatement(text: 'x = 1   \ny', caret: 0);
      expect(result.text, 'x = 1;\ny');
      expect(result.caret, 6);
    });

    test('only moves the caret when ; is already there or wrong', () {
      for (final line in <String>['x = 1;', 'void main() {', '   ', '']) {
        final text = '$line\nnext';
        final result = endStatement(text: text, caret: 0);
        expect(result.text, text, reason: line);
        expect(result.caret, line.length, reason: line);
      }
    });

    test('the languages with ; statements', () {
      expect(semicolonLanguages, containsAll(<String>['dart', 'c', 'cpp']));
      expect(semicolonLanguages, isNot(contains('python')));
      expect(semicolonLanguages, isNot(contains('armasm')));
    });
  });
}
