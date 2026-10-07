// Scratch verification for CompletionFilter. Run with:
//   dart run tool/verify_completion_filter.dart
//
// Exercises the exact cases from the bug report against the real filter code.
import 'package:borland_dart/models/lsp_models.dart';
import 'package:borland_dart/utils/completion_filter.dart';

int _failures = 0;
int _checks = 0;

void _check(String label, bool condition, String detail) {
  _checks++;
  if (condition) {
    print('  PASS  $label');
  } else {
    _failures++;
    print('  FAIL  $label\n        $detail');
  }
}

CompletionItem _item(String label) =>
    CompletionItem(label: label, kind: 'test');

List<String> _labels(List<CompletionItem> items) =>
    items.map((e) => e.displayLabel).toList();

void main() {
  print('--- currentWord() ---');
  const text = 'void main() {\n  prin\n}';
  //                       ^ prin ends at index 20
  _check(
    'extracts "prin" before cursor',
    CompletionFilter.currentWord(text, 20) == 'prin',
    'got "${CompletionFilter.currentWord(text, 20)}"',
  );
  _check(
    'empty at start of text',
    CompletionFilter.currentWord(text, 0) == '',
    'got "${CompletionFilter.currentWord(text, 0)}"',
  );
  _check(
    'empty right after a space',
    CompletionFilter.currentWord('void main', 5) == '',
    'got "${CompletionFilter.currentWord('void main', 5)}"',
  );
  _check(
    'handles member access after dot',
    CompletionFilter.currentWord('list.forEa', 10) == 'forEa',
    'got "${CompletionFilter.currentWord('list.forEa', 10)}"',
  );
  // 'foo my_var1' -> f0 o1 o2 _3 m4 y5 _6 v7 a8 r9 1:10, so the cursor sits
  // at offset 11 to include the trailing digit.
  _check(
    'digits and underscore are identifier chars',
    CompletionFilter.currentWord('foo my_var1', 11) == 'my_var1',
    'got "${CompletionFilter.currentWord('foo my_var1', 11)}"',
  );

  print('');
  print('--- visibility gate: isTriggering() ---');
  // The popup must stay closed for empty/short prefixes, otherwise an empty
  // prefix matches the entire candidate list and the popup blocks typing.
  for (final entry in {
    '': false, // right after a space / newline / bracket
    'p': false, // one char: matches almost everything
    'pr': false, // two chars: still far too broad
    'pri': true, // three chars: worth asking the server
    'prin': true,
  }.entries) {
    _check(
      'isTriggering("${entry.key}") == ${entry.value}',
      CompletionFilter.isTriggering(entry.key) == entry.value,
      'got ${CompletionFilter.isTriggering(entry.key)}',
    );
  }
  _check(
    'minimumPrefixLength is 3',
    CompletionFilter.minimumPrefixLength == 3,
    'got ${CompletionFilter.minimumPrefixLength}',
  );

  // The dangerous case: an empty query matches everything, so if the gate ever
  // let '' through, the popup would show the whole server list.
  _check(
    'empty query would match the entire list (hence the gate)',
    CompletionFilter.filter([
          _item('pragma'),
          _item('print'),
          _item('Pattern'),
        ], '').length ==
        3,
    'empty query did not match everything',
  );

  print('');
  print('--- filter(): the reported "prin" bug (real server output) ---');
  // Reproduces the ACTUAL shape returned by `dart language-server`, captured
  // via tool/probe_lsp_completion.dart:
  //   {"label":"print(...)", "filterText":"print", "kind":3,
  //    "detail":"(Object? object) \u2192 void", "textEdit":{"newText":"print"}}
  // The labelled signature and the missing filterText handling were why the
  // popup showed `pragma` instead of `print`.
  final lspResult = [
    _item('pragma'),
    _item("part ''"),
    _item("part of ''"),
    _item('Pattern'),
    CompletionItem(
      label: 'print(...)',
      kind: 'method',
      detail: '(Object? object) \u2192 void',
      filterText: 'print',
      textEditNewText: 'print',
    ),
    CompletionItem(
      label: 'printTo(...)',
      kind: 'method',
      filterText: 'printTo',
      textEditNewText: 'printTo',
    ),
  ];
  final prinFiltered = CompletionFilter.filter(lspResult, 'prin');
  print('  input : ${_labels(lspResult)}');
  print('  output: ${_labels(prinFiltered)}');
  _check(
    'typing "prin" surfaces only print-like labels',
    _labels(prinFiltered).every((l) => l.toLowerCase().startsWith('prin')),
    'got ${_labels(prinFiltered)}',
  );
  _check(
    '"print" is the FIRST suggestion',
    prinFiltered.isNotEmpty && prinFiltered.first.displayLabel == 'print',
    'got ${_labels(prinFiltered)}',
  );
  _check(
    'label renders as "print", not the raw "print(...)"',
    prinFiltered.any((e) => e.displayLabel == 'print') &&
        prinFiltered.every((e) => e.label.contains('(')),
    'labels=${prinFiltered.map((e) => e.label).toList()} '
        'display=${_labels(prinFiltered)}',
  );
  _check(
    'accepting "print" inserts the bare identifier, not "print(...)"',
    prinFiltered.first.effectiveInsert == 'print',
    'got "${prinFiltered.first.effectiveInsert}"',
  );
  _check(
    'irrelevant keywords are gone',
    !_labels(prinFiltered).contains('pragma') &&
        !_labels(prinFiltered).contains('Pattern'),
    'got ${_labels(prinFiltered)}',
  );

  print('');
  print('--- filter(): checklist cases ---');
  final universe = [
    _item('print'),
    _item('String'),
    _item('stringify'),
    _item('void'),
    _item('int'),
    _item('intValue'),
    _item('pragma'),
    _item('Pattern'),
  ];

  for (final entry in {
    'pri': 'print',
    'Str': 'String',
    'voi': 'void',
    'int': 'int',
  }.entries) {
    final result = CompletionFilter.filter(universe, entry.key);
    _check(
      'typing "${entry.key}" puts "${entry.value}" first',
      result.isNotEmpty && result.first.label == entry.value,
      'got ${_labels(result)}',
    );
  }

  _check(
    'typing "int" puts exact match before "intValue"',
    _labels(CompletionFilter.filter(universe, 'int')).first == 'int' &&
        _labels(CompletionFilter.filter(universe, 'int')).contains('intValue'),
    'got ${_labels(CompletionFilter.filter(universe, 'int'))}',
  );

  _check(
    'typing "xyz" yields nothing -> popup stays closed',
    CompletionFilter.filter(universe, 'xyz').isEmpty,
    'got ${_labels(CompletionFilter.filter(universe, 'xyz'))}',
  );

  _check(
    'shorter label ranks above longer for same prefix',
    _labels(CompletionFilter.filter(universe, 'str')).first == 'String',
    'got ${_labels(CompletionFilter.filter(universe, 'str'))}',
  );

  // NB: Dart's `List.==` is identity, so compare the joined labels instead.
  _check(
    'empty query preserves server order',
    _labels(CompletionFilter.filter(universe, '')).join(',') ==
        _labels(universe).join(','),
    'got ${_labels(CompletionFilter.filter(universe, ''))}',
  );

  _check(
    'case-insensitive prefix match',
    CompletionFilter.filter(universe, 'PRIN').first.label == 'print',
    'got ${_labels(CompletionFilter.filter(universe, 'PRIN'))}',
  );

  print('');
  if (_failures == 0) {
    print('ALL $_checks CHECKS PASSED');
  } else {
    print('$_failures of $_checks CHECKS FAILED');
  }
}
