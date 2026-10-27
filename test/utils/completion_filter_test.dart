import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/utils/completion_filter.dart';
import 'package:classic_code_editor/utils/dart_snippets.dart';
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

    test('decide() — LSP on: trigger character opens immediately', () {
      // typing `Strin` then `.`: previous char is '.', triggerKind 2.
      final decision = CompletionFilter.decide(
        text: 'Strin.',
        offset: 6,
        lspConnected: true,
        triggerCharacters: const ['.', ','],
      );
      expect(decision.shouldRequest, isTrue);
      expect(decision.immediate, isTrue);
      expect(decision.triggerKind, equals(2));
      expect(decision.triggerCharacter, equals('.'));
    });

    test('decide() — LSP on: one identifier letter opens on the debounce', () {
      final decision = CompletionFilter.decide(
        text: 'a',
        offset: 1,
        lspConnected: true,
        triggerCharacters: const ['.'],
      );
      expect(decision.shouldRequest, isTrue);
      expect(decision.immediate, isFalse);
      expect(decision.triggerKind, equals(1));
    });

    test('decide() — LSP on: whitespace does not open the popup', () {
      // Caret right after the space (offset 4 in 'foo bar'), word is empty,
      // previous char is space → should not trigger.
      final decision = CompletionFilter.decide(
        text: 'foo bar',
        offset: 4,
        lspConnected: true,
        triggerCharacters: const ['.'],
      );
      expect(decision.shouldRequest, isFalse);
    });

    test('decide() — LSP on: closing bracket does not open the popup', () {
      for (final bracket in ['}', ')', ']']) {
        final decision = CompletionFilter.decide(
          text: 'foo$bracket',
          offset: 4,
          lspConnected: true,
          triggerCharacters: const ['.'],
        );
        expect(decision.shouldRequest, isFalse, reason: 'bracket $bracket');
      }
    });

    test('decide() — LSP off: single letter does NOT open (offline min 3)', () {
      final decision = CompletionFilter.decide(
        text: 'a',
        offset: 1,
        lspConnected: false,
        triggerCharacters: const ['.'],
      );
      expect(decision.shouldRequest, isFalse);
    });

    test('decide() — LSP off: two letters do NOT open', () {
      final decision = CompletionFilter.decide(
        text: 'ab',
        offset: 2,
        lspConnected: false,
        triggerCharacters: const ['.'],
      );
      expect(decision.shouldRequest, isFalse);
    });

    test('decide() — LSP off: three letters open on the debounce', () {
      final decision = CompletionFilter.decide(
        text: 'abc',
        offset: 3,
        lspConnected: false,
        triggerCharacters: const ['.'],
      );
      expect(decision.shouldRequest, isTrue);
      expect(decision.immediate, isFalse);
    });

    test('decide() — LSP off: trigger character does NOT open (offline fallback list)', () {
      final decision = CompletionFilter.decide(
        text: 'foo.',
        offset: 4,
        lspConnected: false,
        triggerCharacters: const ['.'],
      );
      expect(decision.shouldRequest, isFalse);
    });

    test('decide() — server-announced trigger characters are honoured', () {
      // clangd advertises `.,:>`; typing `>` must fire immediately.
      final decision = CompletionFilter.decide(
        text: 'ptr>',
        offset: 4,
        lspConnected: true,
        triggerCharacters: const ['.', ':', '>'],
      );
      expect(decision.shouldRequest, isTrue);
      expect(decision.immediate, isTrue);
      expect(decision.triggerCharacter, equals('>'));
    });

    test('parseTriggerCharacters defaults to ["."]', () {
      expect(LspService.parseTriggerCharacters(null), const ['.']);
      expect(LspService.parseTriggerCharacters(<String, dynamic>{}), const ['.']);
      expect(
        LspService.parseTriggerCharacters(<String, dynamic>{
          'capabilities': <String, dynamic>{},
        }),
        const ['.'],
      );
      expect(
        LspService.parseTriggerCharacters(<String, dynamic>{
          'capabilities': <String, dynamic>{
            'completionProvider': <String, dynamic>{},
          },
        }),
        const ['.'],
      );
    });

    test('parseTriggerCharacters reads the server-announced list', () {
      final result = LspService.parseTriggerCharacters(<String, dynamic>{
        'capabilities': <String, dynamic>{
          'completionProvider': <String, dynamic>{
            'triggerCharacters': ['.', ',', ':', '>'],
          },
        },
      });
      expect(result, const ['.', ',', ':', '>']);
    });

    test('parseTriggerCharacters ignores non-string entries', () {
      final result = LspService.parseTriggerCharacters(<String, dynamic>{
        'capabilities': <String, dynamic>{
          'completionProvider': <String, dynamic>{
            'triggerCharacters': ['.', 42, null, ':'],
          },
        },
      });
      expect(result, const ['.', ':']);
    });

    test('parseTriggerCharacters falls back when the list is empty', () {
      final result = LspService.parseTriggerCharacters(<String, dynamic>{
        'capabilities': <String, dynamic>{
          'completionProvider': <String, dynamic>{
            'triggerCharacters': <dynamic>[],
          },
        },
      });
      expect(result, const ['.']);
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

    test('the word being typed is never offered as a candidate', () {
      const items = [
        // The document-token list contains the word itself while typing.
        CompletionItem(label: 'pri', kind: 'variable', filterText: 'pri'),
        CompletionItem(label: 'print', kind: 'keyword'),
        CompletionItem(label: 'PRI', kind: 'keyword'),
      ];

      expect(CompletionFilter.filter(items, 'pri').map((i) => i.label), [
        'print',
      ]);
      // Case-insensitively too.
      expect(CompletionFilter.filter(items, 'PRI').map((i) => i.label), [
        'print',
      ]);
    });

    test('a server item keeps kindInt/detail through the merge pipeline', () {
      const serverItems = [
        CompletionItem(
          label: 'print',
          kind: 'method',
          kindInt: 3,
          detail: 'void print(Object? object)',
          documentation: 'Prints an object.',
        ),
      ];

      // Exactly what CodeEditorPanel does: merge snippets, then filter.
      final merged = mergeSnippets(serverItems, const []);
      final filtered = CompletionFilter.filter(merged, 'pri');

      expect(filtered, hasLength(1));
      expect(filtered.single.kindInt, 3);
      expect(filtered.single.detail, 'void print(Object? object)');
      expect(filtered.single.documentation, 'Prints an object.');
    });

    test('offline keywords carry the keyword kind, words stay unknown', () {
      final completions = CompletionFilter.generateFallbackCompletions(
        'pri',
        'pri',
        'dart',
      );
      final keyword = completions.firstWhere((item) => item.label == 'print');
      expect(keyword.kindInt, 14);
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

    test('ranking: exact case-sensitive first, then case-insensitive', () {
      final items = [
        CompletionItem(label: 'alpha', kind: 'method'),
        CompletionItem(label: 'Alpha', kind: 'method'),
        CompletionItem(label: 'alphabet', kind: 'function'),
      ];
      // "Alph" rather than "Alpha": the full word being typed is never offered
      // (see the exact-prefix test below), but the tier order is unchanged.
      final sorted = CompletionFilter.filter(items, 'Alph');
      expect(sorted.map((i) => i.label), equals(['Alpha', 'alpha', 'alphabet']));

      // The exact word is dropped (case-insensitively), leaving the rest.
      expect(
        CompletionFilter.filter(items, 'Alpha').map((i) => i.label),
        equals(['alphabet']),
      );
    });

    test('MRU: accepted item moves up within same tier', () {
      final items = [
        CompletionItem(label: 'alpha', kind: 'variable'),
        CompletionItem(label: 'alpha_beta', kind: 'variable'),
      ];
      // First call: alphabetical.
      final first = CompletionFilter.filter(items, 'alp');
      expect(first.map((i) => i.label), equals(['alpha', 'alpha_beta']));

      // Record 'alpha_beta' as accepted.
      CompletionFilter.recordCompletion('alpha_beta');

      // Second call: 'alpha_beta' should now come first (same tier, higher MRU).
      final second = CompletionFilter.filter(items, 'alp');
      expect(second.map((i) => i.label), equals(['alpha_beta', 'alpha']));
    });

    test('MRU cap: oldest entry dropped after 200', () {
      // Fill with 201 distinct labels that all match the same prefix.
      final labels = List.generate(201, (i) => 'item$i');
      for (final label in labels) {
        CompletionFilter.recordCompletion(label);
      }
      // First label should have been dropped.
      expect(CompletionFilter.mruValueFor('item0'), equals(0));
      expect(CompletionFilter.mruValueFor('item1'), greaterThan(0));
    });
  });
}
