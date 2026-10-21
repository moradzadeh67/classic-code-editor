import 'dart:convert';

/// Represents the mapping between source line numbers (1-indexed)
/// and instruction offsets (in bytes relative to `_main`/entry point)
/// for an ARM64 Assembly source file.
///
/// Offsets are **signed and relative to the entry symbol** (`_main:`/`main:`),
/// so code assembled *before* `_main` (a helper function such as
/// `_sum_array`) gets negative offsets. That is exactly the space LLDB needs
/// when a breakpoint is set with an absolute address:
/// `breakpoint set -a <mainAddress + offset>`.
class Arm64AsmMap {
  Arm64AsmMap({
    required this.entryLine,
    required this.lineToOffsetMap,
    required this.offsetToLineMap,
    required this.executableLines,
  });

  /// 1-indexed line number of the main entry point (`_main:` or `main:`).
  final int entryLine;

  /// Map from 1-indexed line number to instruction byte offset relative to
  /// the entry point. May be negative for code placed before `_main`.
  final Map<int, int> lineToOffsetMap;

  /// Map from instruction byte offset relative to the entry point to the
  /// 1-indexed line number that holds that instruction.
  final Map<int, int> offsetToLineMap;

  /// Set of 1-indexed line numbers that correspond to executable instructions.
  final Set<int> executableLines;

  /// Returns the instruction byte offset for a given 1-indexed [line].
  ///
  /// If the requested line is a comment, blank or directive, searches forward
  /// up to 10 lines for the nearest executable instruction.
  int? lineToOffset(int line) {
    if (lineToOffsetMap.containsKey(line)) {
      return lineToOffsetMap[line];
    }
    for (var l = line + 1; l <= line + 10; l++) {
      if (lineToOffsetMap.containsKey(l)) {
        return lineToOffsetMap[l];
      }
    }
    return null;
  }

  /// Returns the 1-indexed source line number for a given instruction [offset].
  ///
  /// Offsets that fall between two instructions (or inside the entry prologue)
  /// resolve to the instruction that starts at or before [offset].
  int? offsetToLine(int offset) {
    if (offsetToLineMap.containsKey(offset)) {
      return offsetToLineMap[offset];
    }
    final offsets = offsetToLineMap.keys.toList()..sort();
    int? bestOffset;
    for (final o in offsets) {
      if (o <= offset) {
        bestOffset = o;
      } else {
        break;
      }
    }
    if (bestOffset != null) {
      return offsetToLineMap[bestOffset];
    }
    return entryLine;
  }
}

/// Parses ARM64 assembly (`.s`) source files to calculate line-to-offset
/// and offset-to-line mappings relative to the `_main`/`main` entry label.
///
/// Deliberate simplifications, because the source is hand-written assembly:
///  * every instruction is assumed to be 4 bytes;
///  * `.p2align`/`.align` padding is not modelled (hand-written samples only
///    align to 4 or 8 bytes, which never inserts padding between two
///    consecutive instructions);
///  * only the `__text` section contributes instructions.
class Arm64AsmParser {
  /// Parses [content] into an [Arm64AsmMap].
  static Arm64AsmMap parse(String content) {
    final lines = const LineSplitter().convert(content);
    return parseLines(lines);
  }

  /// Parses a list of source lines into an [Arm64AsmMap].
  static Arm64AsmMap parseLines(List<String> lines) {
    var entryLine = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('_main:') || line.startsWith('main:')) {
        entryLine = i + 1;
        break;
      }
    }

    // Pass 1 — address of every instruction counted from the top of the file,
    // plus the bare-label lines waiting for "the offset of the next
    // instruction".
    final instructionAddr = <int, int>{};
    final pendingLabels = <int>[];
    var inTextSection = true;
    var fileAddr = 0;

    for (var i = 0; i < lines.length; i++) {
      final lineNum = i + 1;
      var cleaned = _stripComments(lines[i]).trim();
      if (cleaned.isEmpty) continue;

      if (cleaned.startsWith('.')) {
        final section = _sectionFor(cleaned);
        if (section != null) inTextSection = section;
        continue;
      }
      if (!inTextSection) continue;

      // `label:` or `label: instruction` — drop the label part.
      final labelMatch = RegExp(r'^[a-zA-Z_$.][a-zA-Z0-9_$.]*:\s*')
          .firstMatch(cleaned);
      if (labelMatch != null) {
        cleaned = cleaned.substring(labelMatch.end).trim();
      }

      if (cleaned.isEmpty) {
        // Bare label: it belongs to whatever instruction comes next.
        pendingLabels.add(lineNum);
        continue;
      }

      instructionAddr[lineNum] = fileAddr;
      fileAddr += 4;
    }

    // The entry symbol's address, in the same "from the top of the file"
    // space. Everything is rebased onto it so that offsets are relative to
    // `_main`, matching what `breakpoint set -a <main + offset>` needs.
    var entryAddr = 0;
    if (entryLine > 0) {
      final entryInstructions = instructionAddr.keys.where(
        (line) => line >= entryLine,
      );
      if (entryInstructions.isNotEmpty) {
        entryAddr =
            instructionAddr[entryInstructions.reduce((a, b) => a < b ? a : b)]!;
      }
    }

    final lineToOffset = <int, int>{};
    final offsetToLine = <int, int>{};
    final executableLines = <int>{};

    instructionAddr.forEach((line, addr) {
      final offset = addr - entryAddr;
      lineToOffset[line] = offset;
      offsetToLine[offset] = line;
      executableLines.add(line);
    });

    final sortedInstructionLines = instructionAddr.keys.toList()..sort();
    for (final labelLine in pendingLabels) {
      // A bare label maps to the instruction that follows it (so that
      // clicking `loop:` sets a breakpoint on the loop body), falling back to
      // the end of the section when nothing follows.
      final next = sortedInstructionLines.where((line) => line > labelLine);
      if (next.isNotEmpty) {
        lineToOffset[labelLine] = lineToOffset[next.first]!;
      } else {
        lineToOffset[labelLine] = fileAddr - entryAddr;
      }
    }

    return Arm64AsmMap(
      entryLine: entryLine > 0 ? entryLine : 1,
      lineToOffsetMap: lineToOffset,
      offsetToLineMap: offsetToLine,
      executableLines: executableLines,
    );
  }

  /// Classifies a directive line.
  ///
  /// Returns `true` when the directive switches to executable code, `false`
  /// when it switches to data, and `null` for every other directive
  /// (`.globl`, `.p2align`, `.asciz`, `.cfi_startproc`, …) which must not
  /// change the current section.
  static bool? _sectionFor(String directive) {
    final lower = directive.toLowerCase();
    if (lower.startsWith('.text') || lower.startsWith('.code')) return true;
    if (lower.startsWith('.data') ||
        lower.startsWith('.bss') ||
        lower.startsWith('.rodata') ||
        lower.startsWith('.const') ||
        lower.startsWith('.cstring')) {
      return false;
    }
    if (!lower.startsWith('.section')) return null;

    // `.section <segment>,<section>[,<flags>]` — the *second* comma-separated
    // token is the section name. Checking for a bare "__text" substring would
    // misclassify `.section __TEXT,__cstring,cstring_literals`, whose *segment*
    // is also called __TEXT.
    final rest = directive.substring('.section'.length).trim();
    if (rest.isEmpty) return null;
    final tokens = rest.split(',').map((t) => t.trim().toLowerCase()).toList();
    if (tokens.length >= 2 && tokens[1] == '__text') return true;
    if (tokens.length == 1 && tokens[0] == '__text') return true;
    return false;
  }

  static String _stripComments(String line) {
    var result = line;
    final idxDoubleSlash = result.indexOf('//');
    if (idxDoubleSlash != -1) {
      result = result.substring(0, idxDoubleSlash);
    }
    final idxSemicolon = result.indexOf(';');
    if (idxSemicolon != -1) {
      result = result.substring(0, idxSemicolon);
    }
    return result;
  }
}
