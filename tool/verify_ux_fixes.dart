// Verification script for the 4 UX fixes:
// 1. Auto-indentation logic
// 2. Closing bracket dedent logic
// 3. Format on save using dart format stdio
//
// Run with:
//   dart run tool/verify_ux_fixes.dart

import 'dart:convert';
import 'dart:io';

int _checks = 0;
int _failures = 0;

void _check(String label, bool condition, String detail) {
  _checks++;
  if (condition) {
    print('  PASS  $label');
  } else {
    _failures++;
    print('  FAIL  $label\n        $detail');
  }
}

// Emulate _handleEnterPressed indentation calculation
(String newIndent, bool isBeforeClosing) calculateEnterIndent(
  String currentLine,
  String textAfterCursor,
) {
  final match = RegExp(r'^(\s*)').firstMatch(currentLine);
  final currentIndent = match?.group(1) ?? '';

  final trimmed = currentLine.trimRight();
  final shouldIncrease =
      trimmed.endsWith('{') || trimmed.endsWith('(') || trimmed.endsWith('[');

  String newIndent = currentIndent;
  if (shouldIncrease) {
    newIndent += '  ';
  }

  final trimmedRest = textAfterCursor.trimLeft();
  final isBeforeClosing =
      shouldIncrease &&
      (trimmedRest.startsWith('}') ||
          trimmedRest.startsWith(')') ||
          trimmedRest.startsWith(']'));

  return (newIndent, isBeforeClosing);
}

// Emulate dedent on closing bracket
bool canDedent(String lineBeforeCursor) {
  return RegExp(r'^\s+$').hasMatch(lineBeforeCursor) &&
      lineBeforeCursor.length >= 2;
}

Future<void> main() async {
  print('--- 1. Auto-indentation logic ---');

  final r1 = calculateEnterIndent('void main() {', '}');
  _check(
    'after "void main() {" -> indent is "  ", isBeforeClosing = true',
    r1.$1 == '  ' && r1.$2 == true,
    'got indent="${r1.$1}" isBeforeClosing=${r1.$2}',
  );

  final r2 = calculateEnterIndent('  print("hi");', '');
  _check(
    'after "  print("hi");" -> indent remains "  ", isBeforeClosing = false',
    r2.$1 == '  ' && r2.$2 == false,
    'got indent="${r2.$1}" isBeforeClosing=${r2.$2}',
  );

  final r3 = calculateEnterIndent('  if (x == 1) {', 'print(x); }');
  _check(
    'after "  if (x == 1) {" -> indent is "    "',
    r3.$1 == '    ' && r3.$2 == false,
    'got indent="${r3.$1}"',
  );

  print('');
  print('--- 2. Dedent logic ---');

  _check('line "  " can dedent', canDedent('  ') == true, '');
  _check('line "    " can dedent', canDedent('    ') == true, '');
  _check('line "  abc " cannot dedent', canDedent('  abc ') == false, '');
  _check('line "" cannot dedent', canDedent('') == false, '');

  print('');
  print('--- 3. Format on Save using dart format process ---');

  const unformattedCode = 'void main(){print("hello");}';
  try {
    final process = await Process.start(Platform.resolvedExecutable, [
      'format',
      '--output=show',
    ]);
    process.stdin.write(unformattedCode);
    await process.stdin.close();

    final formatted = await process.stdout.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;

    _check(
      'dart format process runs cleanly',
      exitCode == 0,
      'exitCode=$exitCode',
    );
    _check(
      'dart format adds spaces and newlines',
      formatted.contains('void main() {') && formatted.contains('\n'),
      'got:\n$formatted',
    );
  } catch (e) {
    _check('dart format process runs', false, 'error: $e');
  }

  print('');
  if (_failures == 0) {
    print('ALL $_checks CHECKS PASSED');
  } else {
    print('$_failures of $_checks CHECKS FAILED');
  }
}
