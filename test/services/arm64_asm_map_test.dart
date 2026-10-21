import 'dart:io';

import 'package:classic_code_editor/services/arm64_asm_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Offsets must be relative to the entry symbol `_main`, not to the top of the
/// file: a helper assembled *before* `_main` occupies negative offsets, which is
/// what `breakpoint set -a <main + offset>` needs.
void main() {
  group('Arm64AsmParser offsets are relative to _main', () {
    late String sample;

    setUpAll(() {
      sample = File('samples/array_sum_arm64.s').readAsStringSync();
    });

    test('samples/array_sum_arm64.s: entry line is the _main: label', () {
      final map = Arm64AsmParser.parse(sample);
      expect(map.entryLine, 42);
    });

    test('code assembled before _main gets negative offsets', () {
      final map = Arm64AsmParser.parse(sample);

      // _sum_array occupies 40 bytes (10 instructions) before _main, so the
      // 6th instruction of the helper sits 20 bytes *before* the entry symbol.
      expect(map.lineToOffset(33), -20);
      expect(map.lineToOffset(27), -40); // first instruction of _sum_array
      expect(map.lineToOffset(38), -4); // `ret`
    });

    test('code inside _main gets non-negative offsets', () {
      final map = Arm64AsmParser.parse(sample);

      expect(map.lineToOffset(43), 0); // stp x29, x30, [sp, #-32]!
      expect(map.lineToOffset(45), 8); // mov x29, sp
      expect(map.lineToOffset(54), 36); // str x19, [sp]
      expect(map.lineToOffset(55), 40); // adrp x0, fmt@PAGE
      expect(map.lineToOffset(56), 44); // add x0, x0, fmt@PAGEOFF
      expect(map.lineToOffset(57), 48); // bl _printf
    });

    test('round-trips a negative offset back to its source line', () {
      final map = Arm64AsmParser.parse(sample);

      expect(map.offsetToLine(-20), 33);
      expect(map.offsetToLine(-40), 27);
      expect(map.offsetToLine(0), 43);
      expect(map.offsetToLine(48), 57);
    });

    test('a bare label maps to the instruction that follows it', () {
      final map = Arm64AsmParser.parse(sample);

      // `_sum_array:` (26) and `_main:` (42) are label-only lines.
      expect(map.lineToOffset(26), -40);
      expect(map.lineToOffset(42), 0);
      // `sum_loop:` (29) precedes `cmp` at +8 relative to the file, -32 to main.
      expect(map.lineToOffset(29), -32);
    });

    test('a label and its instruction share one offset', () {
      const source = '''
    .text
_main:
    mov x0, x0
one_liner: add x2, x2, x3
    ret
''';
      final map = Arm64AsmParser.parse(source);

      expect(map.lineToOffset(4), 4);
      expect(map.lineToOffset(3), 0);
      expect(map.offsetToLine(4), 4);
    });
  });

  group('Arm64AsmParser section detection', () {
    test('.section __TEXT,__cstring is data, not code', () {
      const source = '''
    .section __TEXT,__cstring,cstring_literals
msg:
    .asciz "Sum = %d\\n"

    .text
_main:
    mov x0, #1
    ret
''';
      final map = Arm64AsmParser.parse(source);

      // `.asciz` must not be counted: `mov` is the first instruction.
      expect(map.lineToOffset(7), 0);
      expect(map.lineToOffset(8), 4);
      expect(map.executableLines, <int>{7, 8});
      expect(map.executableLines, isNot(contains(3)));
    });

    test('.section __TEXT,__text is code', () {
      const source = '''
    .section __TEXT,__text,regular,pure_instructions
_main:
    mov x0, #1
    ret
''';
      final map = Arm64AsmParser.parse(source);

      expect(map.lineToOffset(3), 0);
      expect(map.lineToOffset(4), 4);
    });

    test('.data and .bss do not contribute instructions', () {
      const source = '''
    .data
numbers:
    .word 10, 20, 30
    .bss
scratch:
    .zero 64

    .text
_main:
    mov x0, #0
    ret
''';
      final map = Arm64AsmParser.parse(source);

      expect(map.lineToOffset(10), 0);
      expect(map.lineToOffset(11), 4);
      expect(map.executableLines, <int>{10, 11});
    });

    test('a source without _main falls back to line 1 and offset 0', () {
      const source = '''
main:
    mov x0, #42
    ret
''';
      final map = Arm64AsmParser.parse(source);

      expect(map.entryLine, 1);
      expect(map.lineToOffset(2), 0);
    });
  });
}
