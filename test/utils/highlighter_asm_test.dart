import 'package:classic_code_editor/utils/multi_language_highlighter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/highlight.dart' show Highlight, Node;

const String _sample = '''// hello_arm64.s - macOS Apple Silicon
.section __TEXT,__cstring,cstring_literals
msg:
    .asciz "Hello from ARM64 assembly"

.text
.globl _main
.p2align 2
_main:
    mov     x19, #0
    add     x19, x19, x20
    cmp     x20, #6
    b.lt    loop
    ret''';

void main() {
  group('ARM64 Assembly Highlighter Tests', () {
    test('armasm language resolves to the ARM64 grammar', () {
      MultiLanguageHighlighter.patchSymbolModes();
      final mode = MultiLanguageHighlighter.getModeForLanguage('armasm');
      expect(mode, same(MultiLanguageHighlighter.arm64Asm));
    });

    test('the ARM64 grammar tags every class the editor colors', () {
      MultiLanguageHighlighter.patchSymbolModes();
      final highlighter = Highlight()
        ..registerLanguage('armasm', MultiLanguageHighlighter.arm64Asm);
      final result = highlighter.parse(_sample, language: 'armasm');

      // A node's own `className` is often null while an ancestor carries it,
      // so classes are inherited down the tree here.
      final classes = <String>{};
      final valuesByClass = <String, Set<String>>{};
      void walk(List<Node>? nodes, String? currentClass) {
        for (final n in nodes ?? const <Node>[]) {
          final effectiveClass = n.className ?? currentClass;
          if (effectiveClass != null) {
            classes.add(effectiveClass);
          }
          if (n.value != null && effectiveClass != null) {
            valuesByClass
                .putIfAbsent(effectiveClass, () => <String>{})
                .add(n.value!);
          }
          walk(n.children, effectiveClass);
        }
      }

      walk(result.nodes, null);

      expect(classes.contains('comment'), isTrue);
      expect(
        valuesByClass['comment']!.any((v) => v.contains('hello_arm64')),
        isTrue,
      );

      expect(classes.contains('meta'), isTrue);
      expect(valuesByClass['meta']!.any((v) => v.contains('.section')), isTrue);
      expect(valuesByClass['meta']!.any((v) => v.contains('.globl')), isTrue);

      expect(classes.contains('keyword'), isTrue);
      expect(valuesByClass['keyword']!.any((v) => v.contains('mov')), isTrue);
      expect(valuesByClass['keyword']!.any((v) => v.contains('ret')), isTrue);

      expect(classes.contains('built_in'), isTrue);
      expect(valuesByClass['built_in']!.any((v) => v.contains('x19')), isTrue);
      expect(valuesByClass['built_in']!.any((v) => v.contains('x20')), isTrue);

      expect(classes.contains('number'), isTrue);
      expect(valuesByClass['number']!.any((v) => v.contains('0')), isTrue);
      expect(valuesByClass['number']!.any((v) => v.contains('6')), isTrue);

      expect(classes.contains('string'), isTrue);
      expect(
        valuesByClass['string']!.any(
          (v) => v.contains('Hello from ARM64 assembly'),
        ),
        isTrue,
      );

      expect(classes.contains('symbol'), isTrue);
      expect(valuesByClass['symbol']!.any((v) => v.contains('msg')), isTrue);
    });
  });
}
