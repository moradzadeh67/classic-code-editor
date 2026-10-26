import 'package:classic_code_editor/utils/dart_snippets.dart';
import 'package:classic_code_editor/utils/snippet_expander.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('snippetCompletions', () {
    test('matches snippets by typed prefix (case-insensitive)', () {
      final items = snippetCompletions(prefix: 'st', language: 'dart');
      expect(items.map((i) => i.label), equals(['stless', 'stful']));

      final upper = snippetCompletions(prefix: 'ST', language: 'dart');
      expect(upper.map((i) => i.label), equals(['stless', 'stful']));
    });

    test('empty prefix returns every snippet', () {
      final items = snippetCompletions(prefix: '', language: 'dart');
      expect(items.length, equals(dartSnippets.length));
    });

    test('snippets are marked as snippet format', () {
      final items = snippetCompletions(prefix: 'for', language: 'dart');
      expect(items.map((i) => i.label), equals(['fori', 'forin']));
      for (final item in items) {
        expect(item.kind, equals('snippet'));
        expect(item.insertTextFormat, equals(2));
        expect(item.detail, isNotNull);
      }
    });

    test('no snippets for non-Dart languages', () {
      expect(snippetCompletions(prefix: 'stl', language: 'python'), isEmpty);
      expect(snippetCompletions(prefix: 'for', language: 'cpp'), isEmpty);
      expect(snippetCompletions(prefix: '', language: 'c'), isEmpty);
    });

    test('no snippets after member access (.)', () {
      expect(
        snippetCompletions(prefix: 'stl', language: 'dart', previousChar: '.'),
        isEmpty,
      );
      expect(
        snippetCompletions(prefix: 'for', language: 'dart', previousChar: '.'),
        isEmpty,
      );
      // A different previous character keeps them available.
      expect(
        snippetCompletions(prefix: 'stl', language: 'dart', previousChar: ' '),
        isNotEmpty,
      );
    });
  });

  group('snippet bodies expand correctly', () {
    test('stless expands to a StatelessWidget with caret on the class name', () {
      final snippet = dartSnippets.firstWhere((s) => s.prefix == 'stless');
      final result = SnippetExpander.expand(snippet.body, indent: '  ');

      expect(result.$1, contains('class MyWidget extends StatelessWidget {'));
      expect(result.$1, contains('const MyWidget({super.key});'));
      expect(result.$1, contains('Widget build(BuildContext context) {'));
      expect(result.$1, contains('return Container();'));
      // The current line's indent is applied to continuation lines only.
      final lines = result.$1.split('\n');
      expect(lines.first.startsWith('  '), isFalse);
      expect(lines[1].startsWith('    const'), isTrue);
      // Caret sits right after `class `.
      expect(result.$2, equals('class '.length));
    });

    test('fori expands with caret on the first tab stop (length)', () {
      final snippet = dartSnippets.firstWhere((s) => s.prefix == 'fori');
      final result = SnippetExpander.expand(snippet.body);

      expect(
        result.$1,
        equals('for (var i = 0; i < length; i++) {\n  \n}'),
      );
      expect(result.$2, equals('for (var i = 0; i < '.length));
    });
  });

  group('mergeSnippets', () {
    test('appends snippets without duplicates', () {
      final base = snippetCompletions(prefix: 'stl', language: 'dart');
      final merged = mergeSnippets(base, base);
      expect(merged.length, equals(base.length));

      final extra = snippetCompletions(prefix: 'for', language: 'dart');
      final both = mergeSnippets(base, extra);
      expect(both.length, equals(base.length + extra.length));
    });
  });
}
