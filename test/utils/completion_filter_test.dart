import 'package:borland_dart/models/lsp_models.dart';
import 'package:borland_dart/utils/completion_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompletionFilter Tests', () {
    test(
      'isTriggering returns true for single character and trigger chars',
      () {
        expect(CompletionFilter.isTriggering('a'), isTrue);
        expect(CompletionFilter.isTriggering(''), isFalse);
        expect(CompletionFilter.isTriggering('', previousChar: '.'), isTrue);
        expect(CompletionFilter.isTriggering('', previousChar: '>'), isTrue);
        expect(CompletionFilter.isTriggering('', previousChar: ':'), isTrue);
      },
    );

    test('previousChar correctly extracts character before current word', () {
      expect(CompletionFilter.previousChar('stdout.write', 12), equals('.'));
      expect(CompletionFilter.previousChar('ptr->field', 10), equals('>'));
      expect(CompletionFilter.previousChar('std::string', 11), equals(':'));
      expect(CompletionFilter.previousChar('print', 5), isNull);
    });

    test('filter ranks and narrows items accurately', () {
      const items = [
        CompletionItem(
          label: 'print(...)',
          filterText: 'print',
          kind: 'method',
        ),
        CompletionItem(label: 'printf', kind: 'function'),
        CompletionItem(label: 'pragma', kind: 'keyword'),
      ];

      final filtered = CompletionFilter.filter(items, 'pri');
      expect(filtered.length, equals(2));
      expect(filtered.first.effectiveFilter, equals('print'));
    });

    test('generateFallbackCompletions provides Python keywords & tokens', () {
      const doc = 'import sys\ndef process_data():\n    pass';
      final completions = CompletionFilter.generateFallbackCompletions(
        doc,
        'pr',
        'python',
      );

      final labels = completions.map((c) => c.label).toList();
      expect(labels, contains('print'));
      expect(labels, contains('process_data'));
    });

    test('generateFallbackCompletions provides C/C++ keywords & tokens', () {
      const doc = '#include <stdio.h>\nint calculate_total() { return 0; }';
      final completions = CompletionFilter.generateFallbackCompletions(
        doc,
        'calc',
        'cpp',
      );

      final labels = completions.map((c) => c.label).toList();
      expect(labels, contains('calculate_total'));
    });

    test('generateFallbackCompletions provides Dart keywords & tokens', () {
      const doc = 'void main() { final score = 100; }';
      final completions = CompletionFilter.generateFallbackCompletions(
        doc,
        'sc',
        'dart',
      );

      final labels = completions.map((c) => c.label).toList();
      expect(labels, contains('score'));
    });
  });
}
