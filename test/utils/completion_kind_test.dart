import 'package:classic_code_editor/models/syntax_scheme.dart';
import 'package:classic_code_editor/utils/completion_kind.dart';
import 'package:classic_code_editor/utils/multi_language_highlighter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The kind → badge mapping is pure data: no widget, no theme.
void main() {
  group('completionKindBadge', () {
    final expected = <int, String>{
      2: 'M', // Method
      3: 'M', // Function
      4: 'M', // Constructor
      5: 'F', // Field
      10: 'F', // Property
      6: 'V', // Variable
      7: 'C', // Class
      8: 'C', // Interface
      22: 'C', // Struct
      13: 'E', // Enum
      20: 'E', // EnumMember
      14: 'K', // Keyword
      15: 'S', // Snippet
      9: 'P', // Module
      21: '#', // Constant
      1: '·', // Text (no badge of its own)
      11: '·', // Unit
      12: '·', // Value
      16: '·', // Color
      17: '·', // File
      18: '·', // Reference
      19: '·', // Folder
      23: '·', // Event
      24: '·', // Operator
      25: '·', // TypeParameter
    };

    test('maps every LSP kind to its letter', () {
      expected.forEach((kind, letter) {
        expect(
          completionKindBadge(kind).letter,
          letter,
          reason: 'kind $kind',
        );
      });
    });

    test('null / unknown kinds get the neutral badge', () {
      expect(completionKindBadge(null).letter, '·');
      expect(completionKindBadge(0).letter, '·');
      expect(completionKindBadge(99).letter, '·');
      expect(
        completionKindBadge(null).category,
        CompletionKindCategory.plain,
      );
    });

    test('groups kinds by the colour category they share', () {
      expect(completionKindBadge(3).category, CompletionKindCategory.callable);
      expect(completionKindBadge(4).category, CompletionKindCategory.callable);
      expect(completionKindBadge(5).category, CompletionKindCategory.value);
      expect(completionKindBadge(6).category, CompletionKindCategory.value);
      expect(completionKindBadge(21).category, CompletionKindCategory.value);
      expect(completionKindBadge(7).category, CompletionKindCategory.type);
      expect(completionKindBadge(13).category, CompletionKindCategory.type);
      expect(completionKindBadge(14).category, CompletionKindCategory.keyword);
      expect(completionKindBadge(9).category, CompletionKindCategory.plain);
    });
  });

  group('completionBadgeColor', () {
    test('uses the palette of the scheme it is asked for', () {
      final standard = MultiLanguageHighlighter.getThemeStyles(
        SyntaxScheme.standard,
      );
      final colorful = MultiLanguageHighlighter.getThemeStyles(
        SyntaxScheme.colorful,
      );

      expect(
        completionBadgeColor(
          CompletionKindCategory.callable,
          SyntaxScheme.standard,
        ),
        standard['function']!.color,
      );
      expect(
        completionBadgeColor(
          CompletionKindCategory.value,
          SyntaxScheme.colorful,
        ),
        colorful['number']!.color,
      );
      expect(
        completionBadgeColor(CompletionKindCategory.keyword, SyntaxScheme.standard),
        standard['keyword']!.color,
      );
      // The two schemes really do differ, so the colours are not hardcoded.
      expect(
        completionBadgeColor(
          CompletionKindCategory.type,
          SyntaxScheme.standard,
        ),
        isNot(
          completionBadgeColor(
            CompletionKindCategory.type,
            SyntaxScheme.colorful,
          ),
        ),
      );
    });
  });
}
