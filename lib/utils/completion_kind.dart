import 'package:flutter/material.dart';

import '../models/syntax_scheme.dart';
import 'multi_language_highlighter.dart';

/// The semantic colour group a completion kind belongs to.
///
/// The badges never carry a literal colour: each category is resolved through
/// the *shared* syntax palette of the active scheme (see
/// [completionBadgeColor]), so the popup follows `View > Syntax Colors` in all
/// four themes.
enum CompletionKindCategory {
  /// Something you call (method, function, constructor).
  callable,

  /// Something that holds a value (field, property, variable, constant).
  value,

  /// A type name (class, interface, struct, enum, enum member).
  type,

  /// A language keyword.
  keyword,

  /// Namespace-like or unknown kinds: painted with the palette's plain
  /// identifier colour.
  plain,
}

/// The one-letter badge and colour group of a completion kind.
class CompletionKindBadge {
  /// The letter drawn inside the badge.
  final String letter;

  /// The colour group the letter is painted with.
  final CompletionKindCategory category;

  const CompletionKindBadge(this.letter, this.category);

  @override
  String toString() => 'CompletionKindBadge($letter, ${category.name})';
}

const CompletionKindBadge _callable = CompletionKindBadge(
  'M',
  CompletionKindCategory.callable,
);
const CompletionKindBadge _field = CompletionKindBadge(
  'F',
  CompletionKindCategory.value,
);
const CompletionKindBadge _variable = CompletionKindBadge(
  'V',
  CompletionKindCategory.value,
);
const CompletionKindBadge _type = CompletionKindBadge(
  'C',
  CompletionKindCategory.type,
);
const CompletionKindBadge _enum = CompletionKindBadge(
  'E',
  CompletionKindCategory.type,
);
const CompletionKindBadge _keyword = CompletionKindBadge(
  'K',
  CompletionKindCategory.keyword,
);
const CompletionKindBadge _snippet = CompletionKindBadge(
  'S',
  CompletionKindCategory.plain,
);
const CompletionKindBadge _constant = CompletionKindBadge(
  '#',
  CompletionKindCategory.value,
);
const CompletionKindBadge _module = CompletionKindBadge(
  'P',
  CompletionKindCategory.plain,
);
const CompletionKindBadge _unknown = CompletionKindBadge(
  '·',
  CompletionKindCategory.plain,
);

/// Maps a raw LSP `CompletionItemKind` int to its badge.
///
/// The numbers are the values from the LSP specification
/// (`CompletionItemKind`). Anything outside the table — including `null` for
/// items this client generated itself — is the neutral `·`.
CompletionKindBadge completionKindBadge(int? kind) {
  switch (kind) {
    case 2: // Method
    case 3: // Function
    case 4: // Constructor
      return _callable;
    case 5: // Field
    case 10: // Property
      return _field;
    case 6: // Variable
      return _variable;
    case 7: // Class
    case 8: // Interface
    case 22: // Struct
      return _type;
    case 13: // Enum
    case 20: // EnumMember
      return _enum;
    case 14: // Keyword
      return _keyword;
    case 15: // Snippet
      return _snippet;
    case 21: // Constant
      return _constant;
    case 9: // Module
      return _module;
    default:
      return _unknown;
  }
}

/// The colour [category] is painted with, taken from the shared syntax palette
/// of [scheme].
///
/// Callable uses the palette's function colour, value the number colour, type
/// the type colour, keyword the keyword colour; [CompletionKindCategory.plain]
/// uses the palette's plain identifier colour. Nothing here is hardcoded, so a
/// scheme switch repaints the badges with the same colours the editor uses.
Color completionBadgeColor(
  CompletionKindCategory category,
  SyntaxScheme scheme,
) {
  final tokenClass = switch (category) {
    CompletionKindCategory.callable => 'function',
    CompletionKindCategory.value => 'number',
    CompletionKindCategory.type => 'type',
    CompletionKindCategory.keyword => 'keyword',
    CompletionKindCategory.plain => 'variable',
  };
  return MultiLanguageHighlighter.completionColor(scheme, tokenClass);
}
