import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/python.dart';

import '../models/language_config.dart';
import '../models/syntax_scheme.dart';

void registerHighlightLanguages() {
  MultiLanguageHighlighter.patchSymbolModes();
}

class MultiLanguageHighlighter {
  static const Color keywordColor = Color(0xFFC842F5);
  static const Color preprocessorColor = Color(0xFF7B1FA2);
  static const Color typeColor = Color(0xFF00796B);
  static const Color stringColor = Color(0xFFC62828);
  static const Color methodColor = Color(0xFF0D47A1);
  static const Color numberColor = Color(0xFFE65100);
  static const Color commentColor = Color(0xFF596E48);
  static const Color operatorColor = Color(0xFF00BF69);
  static const Color bracketColor = Color(0xFF031CFC);
  static const Color variableColor = Color(0xFF1A237E);

  /// The palette category a token class belongs to.
  ///
  /// A scheme only has to describe these categories; every language then picks
  /// its colors through one shared mapping. That is why Assembly needs no
  /// palette work of its own: registers are tagged `built_in` (the built-in
  /// category), directives `meta` (annotations) and labels `title` (functions).
  /// New token classes the grammars start emitting are added to
  /// [_categoryByClass] only — never to a scheme's color list.
  static const Map<String, _SyntaxCategory> _categoryByClass = {
    // Order mirrors the classic palette so Standard keeps the exact same map.
    'meta': _SyntaxCategory.annotation,
    'meta-keyword': _SyntaxCategory.annotation,
    'meta-string': _SyntaxCategory.string,
    'keyword': _SyntaxCategory.keyword,
    'selector-tag': _SyntaxCategory.keyword,
    'built_in': _SyntaxCategory.builtIn,
    'type': _SyntaxCategory.type,
    'class': _SyntaxCategory.className,
    'string': _SyntaxCategory.string,
    'quote': _SyntaxCategory.string,
    // The Python grammar wraps every f-string `{...}` interpolation in this
    // class; without an entry it fell back to the default (black) text color.
    'subst': _SyntaxCategory.string,
    'title': _SyntaxCategory.functionTitle,
    'title.function': _SyntaxCategory.functionTitle,
    'function': _SyntaxCategory.function,
    'number': _SyntaxCategory.number,
    'literal': _SyntaxCategory.literal,
    'comment': _SyntaxCategory.comment,
    'variable': _SyntaxCategory.variable,
    'params': _SyntaxCategory.params,
    'operator': _SyntaxCategory.operator,
    'punctuation': _SyntaxCategory.punctuation,
    'symbol': _SyntaxCategory.operator,
    // Brackets split out of punctuation: curly and square get their own
    // Colorful colors; Standard keeps the old bracket/punctuation color.
    'bracket': _SyntaxCategory.punctuation,
    '{': _SyntaxCategory.curlyBrace,
    '}': _SyntaxCategory.curlyBrace,
    '[': _SyntaxCategory.squareBracket,
    ']': _SyntaxCategory.squareBracket,
    // The patched single-character bracket rules below emit these class names
    // so curly braces and square brackets win their own Colorful colors.
    'curlyBrace': _SyntaxCategory.curlyBrace,
    'squareBracket': _SyntaxCategory.squareBracket,
    // Emitted by the Dart grammar for `///` doc comments. The classic palette
    // never styled it, so Standard must keep leaving it as plain text; only
    // Colorful assigns it a category (see [_unstyledInStandard]).
    'doctag': _SyntaxCategory.comment,
  };

  /// Classes that Standard deliberately leaves without a style, exactly as
  /// before this setting existed.
  static const Set<String> _unstyledInStandard = {'doctag'};

  /// Colors of the classic (Standard) palette, per category.
  ///
  /// These values are what `View > Syntax Colors > Standard` renders and must
  /// not change: several categories share a color on purpose.
  static const Map<_SyntaxCategory, TextStyle> _standardStyleByCategory = {
    _SyntaxCategory.keyword: TextStyle(
      color: keywordColor,
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.literal: TextStyle(
      color: numberColor,
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.string: TextStyle(color: stringColor),
    _SyntaxCategory.number: TextStyle(
      color: numberColor,
      fontWeight: FontWeight.w600,
    ),
    _SyntaxCategory.type: TextStyle(
      color: typeColor,
      fontWeight: FontWeight.w600,
    ),
    _SyntaxCategory.builtIn: TextStyle(
      color: typeColor,
      fontWeight: FontWeight.w600,
    ),
    _SyntaxCategory.className: TextStyle(
      color: Color(0xFF006699),
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.function: TextStyle(color: methodColor),
    _SyntaxCategory.functionTitle: TextStyle(
      color: methodColor,
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.params: TextStyle(color: Color(0xFF283593)),
    _SyntaxCategory.operator: TextStyle(
      color: operatorColor,
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.punctuation: TextStyle(
      color: bracketColor,
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.curlyBrace: TextStyle(
      color: bracketColor,
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.squareBracket: TextStyle(
      color: bracketColor,
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.comment: TextStyle(
      color: commentColor,
      fontStyle: FontStyle.italic,
    ),
    _SyntaxCategory.annotation: TextStyle(
      color: preprocessorColor,
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.variable: TextStyle(color: variableColor),
  };

  /// The Colorful scheme: eleven distinct colors tuned for the shared
  /// `#E8F1FF` editor background (all at roughly 4.5:1 contrast or better).
  ///
  /// Identifiers and parameter lists keep the default text color, which is what
  /// the editor paints when a category has no color of its own.
  static const Map<_SyntaxCategory, TextStyle> _colorfulStyleByCategory = {
    _SyntaxCategory.keyword: TextStyle(
      color: Color(0xFFA800E0),
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.literal: TextStyle(
      color: Color(0xFF8F5A00),
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.string: TextStyle(color: Color(0xFF007A1F)),
    _SyntaxCategory.number: TextStyle(color: Color(0xFFB34A00)),
    _SyntaxCategory.type: TextStyle(color: Color(0xFF00718F)),
    _SyntaxCategory.builtIn: TextStyle(color: Color(0xFFC2185B)),
    _SyntaxCategory.className: TextStyle(color: Color(0xFF00718F)),
    _SyntaxCategory.function: TextStyle(color: Color(0xFF0050E6)),
    _SyntaxCategory.functionTitle: TextStyle(color: Color(0xFF0050E6)),
    _SyntaxCategory.annotation: TextStyle(color: Color(0xFF4B3FE0)),
    _SyntaxCategory.operator: TextStyle(
      color: colorfulOperatorColor,
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.punctuation: TextStyle(
      color: Color(0xFF031CFC),
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.curlyBrace: TextStyle(
      color: colorfulCurlyBraceColor,
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.squareBracket: TextStyle(
      color: colorfulSquareBracketColor,
      fontWeight: FontWeight.bold,
    ),
    _SyntaxCategory.comment: TextStyle(
      color: Color(0xFF596E48),
      fontStyle: FontStyle.italic,
    ),
    // Plain identifiers. Written out instead of relying on inheritance, because
    // a parameter list nests inside the (colored) function node.
    _SyntaxCategory.params: TextStyle(color: Color(0xFF000000)),
    _SyntaxCategory.variable: TextStyle(color: Color(0xFF000000)),
  };

  /// Token-class styles for the editor, built from one class → category mapping.
  ///
  /// [scheme] defaults to [SyntaxScheme.standard] so existing callers (and
  /// tests) keep the classic palette without passing anything.
  static Map<String, TextStyle> getThemeStyles([
    SyntaxScheme scheme = SyntaxScheme.standard,
  ]) {
    final colorful = scheme == SyntaxScheme.colorful;
    final byCategory = colorful
        ? _colorfulStyleByCategory
        : _standardStyleByCategory;

    final styles = <String, TextStyle>{};
    _categoryByClass.forEach((className, category) {
      if (!colorful && _unstyledInStandard.contains(className)) return;
      final style = byCategory[category];
      if (style != null) styles[className] = style;
    });
    return styles;
  }

  /// Minimal ARM64 (AArch64) grammar for `.s` files.
  ///
  /// `highlight` 0.7 does ship an `armasm` grammar, but it targets 32-bit ARM:
  /// it has no `x0`..`x30` / `w0`..`w30` registers and no `//` comments, both of
  /// which every clang-assembled Apple Silicon file uses. This grammar is built
  /// here instead (no extra package) and reuses the shared palette classes.
  static final Mode arm64Asm = _buildArm64Asm();

  static Mode _buildArm64Asm() {
    final registers = <String>[
      for (var i = 0; i <= 30; i++) 'x$i',
      for (var i = 0; i <= 30; i++) 'w$i',
      'sp',
      'fp',
      'lr',
      'pc',
      'xzr',
      'wzr',
      'cpsr',
    ].join(' ');

    return Mode(
      case_insensitive: true,
      lexemes: r'[a-zA-Z_.$][\w.$]*',
      keywords: {
        'keyword':
            'adc add adds adr adrp and asr b b.eq b.ne b.lt b.le b.gt b.ge '
            'b.hi b.lo b.hs b.cs b.cc b.mi b.pl b.vs b.vc b.al bl blr br brk '
            'cbz cbnz cmn cmp csel eor eret hlt ldp ldr ldur lsl lsr madd '
            'mov movk movn movz msub mul mvn neg nop orr ret rev sdiv smaddl '
            'smulh stp str stur sub subs svc sxtb sxth sxtw tbnz tbz udiv '
            'umaddl uxtb uxth uxtw',
        'meta':
            '.align .ascii .asciz .balign .byte .data .double .equ .file '
            '.float .globl .global .hidden .include .long .p2align .quad '
            '.section .set .short .skip .space .text .type .weak .word '
            '.private_extern .subsections_via_symbols',
        'built_in': registers,
      },
      contains: [
        // Clang accepts both comment forms; `//` is what Apple's own examples
        // and this project's sample file use.
        Mode(className: 'comment', begin: '//', end: r'$', relevance: 0),
        Mode(className: 'comment', begin: r'/\*', end: r'\*/', relevance: 0),
        Mode(className: 'string', begin: '"', end: '"', illegal: r'\n'),
        // Immediates, decimal and hexadecimal, with or without the `#`.
        // The lookbehind keeps the digits of `x19` / `w0` out of this rule:
        // without it the mode starts mid-identifier and `x19` never reaches
        // the keyword pass as a whole lexeme.
        Mode(
          className: 'number',
          begin: r'(?<![\w.$])#?-?0x[0-9a-fA-F]+',
          relevance: 0,
        ),
        Mode(className: 'number', begin: r'(?<![\w.$])#?-?\d+', relevance: 0),
        // A label is anything followed by a colon at the start of a line. It is
        // `title` (the palette's function/label blue), not `symbol`, which is
        // the operator green — that made every label look like an operator
        // while the real separators stayed black.
        Mode(className: 'title', begin: r'^[A-Za-z_.$][\w.$]*:', relevance: 0),
        // Separators the stock grammar leaves in the default text color.
        Mode(className: 'operator', begin: r'[,!]', relevance: 0),
        Mode(className: 'punctuation', begin: r'[()]', relevance: 0),
        Mode(className: 'curlyBrace', begin: r'[\{\}]', relevance: 0),
        Mode(className: 'squareBracket', begin: r'[\[\]]', relevance: 0),
      ],
    );
  }

  static bool _symbolsPatched = false;

  /// highlight 0.7's Dart / C / C++ / Python grammars emit no
  /// `operator` / `punctuation` classes of their own, so symbols used to
  /// render in the default editor text color. These single-character rules
  /// are appended to each grammar once (before any controller compiles it)
  /// so operators pick up `operatorColor` and brackets `bracketColor`.
  static void patchSymbolModes() {
    if (_symbolsPatched) return;
    _symbolsPatched = true;

    final fatArrow = Mode(begin: '=>', className: 'operator', relevance: 0);
    final parenBrackets = Mode(
      begin: r'[()]',
      className: 'punctuation',
      relevance: 0,
    );
    final curlyBraces = Mode(
      begin: r'[\{\}]',
      className: 'curlyBrace',
      relevance: 0,
    );
    final squareBrackets = Mode(
      begin: r'[\[\]]',
      className: 'squareBracket',
      relevance: 0,
    );
    final operators = Mode(
      begin: r'[!@#\$%^&*+=\-~<>/|?:;.,\\`]',
      className: 'operator',
      relevance: 0,
    );

    // A `contains` rule always wins over the enclosing mode's own `end` match,
    // so a mode that ends on one of these characters must never receive a rule
    // that can match it: the mode would never close and would swallow the rest
    // of the file (that is exactly what used to happen to C++ function bodies).
    // Hence one explicit rule set per context instead of one shared set.
    final operatorsNoColon = Mode(
      begin: r'[!@#\$%^&*+=\-~<>/|?;.,\\`]',
      className: 'operator',
      relevance: 0,
    );
    final operatorsNoSemiEq = Mode(
      begin: r'[!@#\$%^&*+\-~<>/|?:.,\\`]',
      className: 'operator',
      relevance: 0,
    );

    /// The rules a removed `params` mode used to provide, minus anything that
    /// owns parentheses again (`Mode(self: true)` and nested `( ... )` modes) —
    /// re-adding one of those would put the delimiters back under a mode.
    List<Mode> contentRulesOf(Mode? mode) => [
      for (final m in mode?.contains ?? const <Mode?>[])
        if (m != null &&
            m.self != true &&
            m.className != 'params' &&
            m.begin != r'\(')
          m,
    ];

    Mode? firstWhereOrNull(List<Mode?>? list, bool Function(Mode) test) {
      for (final m in list ?? const <Mode?>[]) {
        if (m != null && test(m)) return m;
      }
      return null;
    }

    void patch(Mode mode) {
      final contains = List<Mode?>.from(mode.contains ?? const <Mode?>[]);
      // Replace the stock plain `=>` rule so the fat arrow is colored too.
      for (var i = 0; i < contains.length; i++) {
        final m = contains[i];
        if (m != null && m.begin == '=>' && m.className == null) {
          contains[i] = fatArrow;
        }
      }
      contains.add(parenBrackets);
      contains.add(curlyBraces);
      contains.add(squareBrackets);
      contains.add(operators);
      mode.contains = contains;
      mode.compiled = false; // force a recompile including the new rules
    }

    patch(dart);
    patch(python);
    patch(cpp);

    // python fix: the grammar's `\b(print|exec)\(` rule carries no className
    // (and `print`/`exec` are keywords, not `built_in`), so calls to the
    // common builtins rendered in the default text color. A rule placed first
    // in `contains` wins over that bare rule, exactly like the symbol rules.
    final pyBuiltins = Mode(
      begin:
          r'\b(print|exec|len|range|str|int|float|bool|list|dict|set|tuple|'
          r'open|input|enumerate|zip|sorted|sum|min|max|abs|type|isinstance|'
          r'super|self|repr|map|filter)\b',
      className: 'built_in',
      relevance: 0,
    );
    python.contains = <Mode?>[pyBuiltins, ...?python.contains];
    python.compiled = false;

    // python fix: `def f(self, name)` opened a `params` mode that owned its own
    // parentheses (`begin: "\\(", end: "\\)"`), so a signature's `(` and `)`
    // were painted in the params color instead of the bracket color while every
    // other paren in the file was blue. Dropping that mode lets the shared
    // bracket rule color them too; the literals it used to color inside a
    // signature are inlined so `x=1` / `y="s"` keep their colors.
    final pyDefinition = firstWhereOrNull(
      python.contains,
      (m) => m.end == ':' && m.variants != null,
    );
    final pyParams = firstWhereOrNull(
      pyDefinition?.contains,
      (m) => m.className == 'params',
    );
    if (pyDefinition != null && pyParams != null) {
      pyDefinition.contains =
          List<Mode?>.from(pyDefinition.contains ?? const <Mode?>[])
            ..remove(pyParams)
            ..addAll(contentRulesOf(pyParams))
            // The definition mode ends at `:`, so `:` stays out of its operator
            // rules or the mode could never close.
            ..add(parenBrackets)
            ..add(operatorsNoColon);
      // `,` and `=` are legal in a signature and only survived because the
      // params mode swallowed them; without relaxing this the whole `def`
      // would be rejected as illegal and lose its keyword color.
      pyDefinition.illegal = r'[\$\n;]';
      pyDefinition.compiled = false;
    }

    // cpp fix: the generated grammar opens swallowing variants on
    // `Mode(begin: "=", end: ";")` / `Mode(begin: "(", end: ")")` whose own
    // `contains` never include the symbol rules above, so operators and
    // brackets inside assignments / calls stayed uncolored (user-visible in
    // real C++ files even though `mode.contains` carried the rules).
    // Those variants only boost highlight.js relevance — their keyword lists
    // duplicate the top-level ones — so dropping that element lets the
    // patched top-level rules color symbols everywhere.
    cpp.contains = List<Mode?>.from(cpp.contains ?? const <Mode?>[])
      ..removeWhere(
        (m) =>
            m != null &&
            m.className == null &&
            m.begin == null &&
            m.beginKeywords == null &&
            m.variants != null,
      );

    // cpp fix: a signature's parameter list was a `params` mode owning its
    // parentheses (and recursing into itself for calls like `f(g())`), so those
    // `(` `)` were params-colored instead of blue. The function mode ends at
    // one of `{ ; =`, so those characters stay out of the rules added to it.
    final functionMode = firstWhereOrNull(
      cpp.contains,
      (m) => m.className == 'function',
    );
    final paramsMode = firstWhereOrNull(
      functionMode?.contains,
      (m) => m.className == 'params',
    );
    if (functionMode != null && paramsMode != null) {
      functionMode.contains =
          List<Mode?>.from(functionMode.contains ?? const <Mode?>[])
            ..remove(paramsMode)
            ..addAll(contentRulesOf(paramsMode))
            ..add(parenBrackets)
            ..add(squareBrackets)
            ..add(operatorsNoSemiEq);
      // The stock rule forbids anything but word characters, spaces, `* & : < >`
      // inside a signature; commas, parentheses and `=` are ordinary there, and
      // a rejected character makes the whole declaration lose its colors, so
      // the same conservative illegal marker the grammar uses at top level is
      // applied instead.
      functionMode.illegal = '</';
      functionMode.compiled = false;
    }

    cpp.compiled = false; // recompile everything touched above
  }

  static Mode getModeForLanguage(String highlightLanguage) {
    patchSymbolModes();
    switch (highlightLanguage) {
      case 'c':
      case 'cpp':
        return cpp;
      case 'python':
        return python;
      case 'dart':
        return dart;
      case 'armasm':
        return arm64Asm;
      default:
        return dart;
    }
  }

  static CodeController createController({
    required String text,
    String? filePath,
  }) {
    final config = LanguageConfig.fromPathOrContent(filePath, text);
    final mode = getModeForLanguage(config.highlightLanguage);
    return CodeController(text: text, language: mode);
  }
}

// Retain DartHighlighter for backwards compatibility
class DartHighlighter {
  static Map<String, TextStyle> get themeStyles =>
      MultiLanguageHighlighter.getThemeStyles();

  static CodeController createController({required String text}) {
    return MultiLanguageHighlighter.createController(text: text);
  }
}

/// One slot of a syntax palette.
///
/// This is a color concept, not a language concept: every token class the five
/// grammars emit resolves to one of these through
/// `MultiLanguageHighlighter._categoryByClass`, so a scheme only ever lists
/// colors once, and no language needs its own palette.
/// Shared named colors for schemes that split the classic palette further.
/// They are declared in one place so changing the Colorful accent colors is a
/// single edit.
const Color colorfulOperatorColor = Color(0xFFd6026c); // #d6026c
const Color colorfulCurlyBraceColor = Color(0xFF1e64d8); // #1e64d8 (bold braces)
const Color colorfulSquareBracketColor = Color(0xFF00796f); // #00796f (bold brackets)

enum _SyntaxCategory {
  keyword,
  literal,
  string,
  number,
  type,
  builtIn,
  className,
  function,
  functionTitle,
  params,
  operator,
  punctuation,
  curlyBrace,
  squareBracket,
  comment,
  annotation,
  variable,
}
