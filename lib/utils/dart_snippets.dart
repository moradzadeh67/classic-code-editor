import '../models/lsp_models.dart';

/// A built-in Dart/Flutter snippet shown in the completion popup.
///
/// [body] uses LSP snippet syntax (`$0`, `$1`, `${1:default}`) and is expanded
/// by `SnippetExpander` when the user accepts the item. Bodies are written at
/// column 0; the expander adds the current line's indentation to every line
/// after the first.
class DartSnippet {
  final String prefix;
  final String label;
  final String description;
  final String body;

  const DartSnippet({
    required this.prefix,
    required this.label,
    required this.description,
    required this.body,
  });
}

/// Built-in snippets for Dart/Flutter files.
const List<DartSnippet> dartSnippets = [
  DartSnippet(
    prefix: 'stless',
    label: 'stless',
    description: 'StatelessWidget class',
    body: r'''class ${1:MyWidget} extends StatelessWidget {
  const ${1:MyWidget}({super.key});

  @override
  Widget build(BuildContext context) {
    return ${2:Container()};
  }
}''',
  ),
  DartSnippet(
    prefix: 'stful',
    label: 'stful',
    description: 'StatefulWidget + State class',
    body: r'''class ${1:MyWidget} extends StatefulWidget {
  const ${1:MyWidget}({super.key});

  @override
  State<${1:MyWidget}> createState() => _${1:MyWidget}State();
}

class _${1:MyWidget}State extends State<${1:MyWidget}> {
  @override
  Widget build(BuildContext context) {
    return ${2:Container()};
  }
}''',
  ),
  DartSnippet(
    prefix: 'main',
    label: 'main',
    description: 'void main() entry point',
    body: r'''void main() {
  $0
}''',
  ),
  DartSnippet(
    prefix: 'fori',
    label: 'fori',
    description: 'Indexed for loop',
    body: r'''for (var i = 0; i < ${1:length}; i++) {
  $0
}''',
  ),
  DartSnippet(
    prefix: 'forin',
    label: 'forin',
    description: 'for-in loop',
    body: r'''for (final ${1:item} in ${2:items}) {
  $0
}''',
  ),
  DartSnippet(
    prefix: 'try',
    label: 'try',
    description: 'try / catch block',
    body: r'''try {
  $1
} catch (e) {
  $0
}''',
  ),
  DartSnippet(
    prefix: 'init',
    label: 'init',
    description: 'initState override',
    body: r'''@override
void initState() {
  super.initState();
  $0
}''',
  ),
  DartSnippet(
    prefix: 'dispose',
    label: 'dispose',
    description: 'dispose override',
    body: r'''@override
void dispose() {
  $0
  super.dispose();
}''',
  ),
];

/// Completion items for the built-in snippets matching [prefix].
///
/// Returns an empty list unless [language] is Dart, and never after member
/// access ([previousChar] == `.`).
List<CompletionItem> snippetCompletions({
  required String prefix,
  required String language,
  String? previousChar,
}) {
  if (language.toLowerCase() != 'dart') return const [];
  if (previousChar == '.') return const [];

  final query = prefix.toLowerCase();
  return [
    for (final snippet in dartSnippets)
      if (snippet.prefix.toLowerCase().startsWith(query))
        CompletionItem(
          label: snippet.label,
          kind: 'snippet',
          kindInt: 15,
          detail: snippet.description,
          insertText: snippet.body,
          insertTextFormat: 2,
          filterText: snippet.prefix,
        ),
  ];
}

/// Returns [items] with any [snippets] that are not already present appended.
///
/// A snippet is skipped when an item with the same match text already exists,
/// so a server that also offers snippets never produces duplicate rows.
List<CompletionItem> mergeSnippets(
  List<CompletionItem> items,
  List<CompletionItem> snippets,
) {
  if (snippets.isEmpty) return items;
  final existing = {
    for (final item in items) item.effectiveFilter.toLowerCase(),
  };
  return [
    ...items,
    for (final snippet in snippets)
      if (!existing.contains(snippet.effectiveFilter.toLowerCase())) snippet,
  ];
}
