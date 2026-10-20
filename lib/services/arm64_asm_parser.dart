import 'dart:convert';

/// Represents the mapping between source line numbers (1-indexed)
/// and instruction offsets (in bytes relative to `_main`/entry point)
/// for an ARM64 Assembly source file.
class Arm64AsmMap {
  Arm64AsmMap({
    required this.entryLine,
    required this.lineToOffsetMap,
    required this.offsetToLineMap,
    required this.executableLines,
  });

  /// 1-indexed line number of the main entry point (`_main:` or `main:`).
  final int entryLine;

  /// Map from 1-indexed line number to instruction byte offset relative to entry point.
  final Map<int, int> lineToOffsetMap;

  /// Map from instruction byte offset relative to entry point to 1-indexed line number.
  final Map<int, int> offsetToLineMap;

  /// Set of 1-indexed line numbers that correspond to executable instructions.
  final Set<int> executableLines;

  /// Returns the instruction byte offset for a given 1-indexed [line].
  ///
  /// If the requested line is a label, comment, or blank, searches forward up
  /// to 10 lines for the nearest executable instruction.
  int? lineToOffset(int line) {
    if (lineToOffsetMap.containsKey(line)) {
      return lineToOffsetMap[line];
    }
    for (var l = line; l <= line + 10; l++) {
      if (lineToOffsetMap.containsKey(l)) {
        return lineToOffsetMap[l];
      }
    }
    return null;
  }

  /// Returns the 1-indexed source line number for a given instruction [offset].
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
class Arm64AsmParser {
  /// Parses [content] into an [Arm64AsmMap].
  static Arm64AsmMap parse(String content) {
    final lines = const LineSplitter().convert(content);
    return parseLines(lines);
  }

  /// Parses a list of source lines into an [Arm64AsmMap].
  static Arm64AsmMap parseLines(List<String> lines) {
    int entryLine = 1;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line == '_main:' ||
          line == 'main:' ||
          line.startsWith('_main:') ||
          line.startsWith('main:')) {
        entryLine = i + 1;
        break;
      }
    }

    final lineToOffset = <int, int>{};
    final offsetToLine = <int, int>{};
    final executableLines = <int>{};

    bool inTextSection = true;
    int currentOffset = 0;

    for (var i = 0; i < lines.length; i++) {
      final lineNum = i + 1;
      final rawLine = lines[i];

      var cleaned = _stripComments(rawLine).trim();
      if (cleaned.isEmpty) continue;

      // Track sections
      if (cleaned.startsWith('.')) {
        final lower = cleaned.toLowerCase();
        if (lower.startsWith('.text') || lower.startsWith('.code')) {
          inTextSection = true;
          continue;
        } else if (lower.startsWith('.data') ||
            lower.startsWith('.section') ||
            lower.startsWith('.cstring') ||
            lower.startsWith('.bss') ||
            lower.startsWith('.rodata')) {
          if (lower.startsWith('.section __text') ||
              lower.startsWith('.section __text,') ||
              lower.contains('__text')) {
            inTextSection = true;
          } else {
            inTextSection = false;
          }
          continue;
        }
      }

      if (!inTextSection) continue;

      // Ignore assembler non-code directives starting with '.'
      if (cleaned.startsWith('.')) continue;

      // Check for label prefix e.g. `_main:` or `loop:`
      final labelMatch = RegExp(r'^[a-zA-Z_$.][a-zA-Z0-9_$.]*:\s*')
          .firstMatch(cleaned);
      if (labelMatch != null) {
        cleaned = cleaned.substring(labelMatch.end).trim();
      }

      // If line had only a label (or label + comment):
      if (cleaned.isEmpty) {
        lineToOffset[lineNum] = currentOffset;
        continue;
      }

      if (cleaned.startsWith('.')) continue;

      // Valid ARM64 instruction!
      lineToOffset[lineNum] = currentOffset;
      offsetToLine[currentOffset] = lineNum;
      executableLines.add(lineNum);

      currentOffset += 4;
    }

    return Arm64AsmMap(
      entryLine: entryLine,
      lineToOffsetMap: lineToOffset,
      offsetToLineMap: offsetToLine,
      executableLines: executableLines,
    );
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
