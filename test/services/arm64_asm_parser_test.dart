import 'package:classic_code_editor/services/arm64_asm_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Arm64AsmParser', () {
    test('identifies _main: entry line', () {
      const source = '''
// Header
.text
.globl _main
.p2align 2
_main:
    mov x0, #0
    ret
''';
      final map = Arm64AsmParser.parse(source);
      expect(map.entryLine, 5);
    });

    test('identifies main: entry line when _main is absent', () {
      const source = '''
main:
    mov x0, #42
    ret
''';
      final map = Arm64AsmParser.parse(source);
      expect(map.entryLine, 1);
    });

    test('maps instructions to sequential 4-byte offsets', () {
      const source = '''
    .text
    .globl _main
    .p2align 2
_main:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x0, #42
    ldp x29, x30, [sp], #16
    ret
''';
      final map = Arm64AsmParser.parse(source);

      // Line 5: stp -> offset 0
      // Line 6: mov -> offset 4
      // Line 7: mov -> offset 8
      // Line 8: ldp -> offset 12
      // Line 9: ret -> offset 16
      expect(map.lineToOffset(5), 0);
      expect(map.lineToOffset(6), 4);
      expect(map.lineToOffset(7), 8);
      expect(map.lineToOffset(8), 12);
      expect(map.lineToOffset(9), 16);

      expect(map.offsetToLine(0), 5);
      expect(map.offsetToLine(4), 6);
      expect(map.offsetToLine(8), 7);
      expect(map.offsetToLine(12), 8);
      expect(map.offsetToLine(16), 9);
    });

    test('handles comments and blank lines without incrementing offsets', () {
      const source = '''
_main:
    mov x0, #1 // first instruction
    // a full line comment
    ; another comment format
    mov x1, #2
''';
      final map = Arm64AsmParser.parse(source);

      expect(map.lineToOffset(2), 0);
      expect(map.lineToOffset(5), 4);

      expect(map.offsetToLine(0), 2);
      expect(map.offsetToLine(4), 5);
    });

    test('handles labels on their own lines', () {
      const source = '''
_main:
    mov x0, #0
loop:
    add x0, x0, #1
    cmp x0, #5
    b.lt loop
    ret
''';
      final map = Arm64AsmParser.parse(source);

      // Line 3: loop: -> maps to offset 4 (next instruction line 4)
      // Line 4: add x0, x0, #1 -> offset 4
      expect(map.lineToOffset(3), 4);
      expect(map.lineToOffset(4), 4);
      expect(map.offsetToLine(4), 4);
    });

    test('ignores data sections', () {
      const source = '''
    .section __TEXT,__cstring,cstring_literals
msg:
    .asciz "Hello World"

    .text
    .globl _main
_main:
    mov x0, #0
    ret
''';
      final map = Arm64AsmParser.parse(source);

      // Line 8: mov x0, #0 -> offset 0
      // Line 9: ret -> offset 4
      expect(map.lineToOffset(8), 0);
      expect(map.lineToOffset(9), 4);
      expect(map.offsetToLine(0), 8);
      expect(map.offsetToLine(4), 9);
    });

    test('offsetToLine falls back gracefully for unknown offsets', () {
      const source = '''
_main:
    mov x0, #1
    mov x1, #2
''';
      final map = Arm64AsmParser.parse(source);

      // Offset 2 is mid-instruction (between 0 and 4), resolves to preceding offset 0 (line 2)
      expect(map.offsetToLine(2), 2);
    });
  });
}
