// End-to-end check of the REAL pipeline, with no Flutter imports so it runs
// under plain `dart run`:
//
//   dart language-server  ->  raw JSON-RPC  ->  parse like LspService does
//                         ->  CompletionFilter  ->  what the popup would show
//
// This is the closest we can get to "typing prin in the app" without driving
// the GUI, and it exercises the exact code paths the app uses.
//
// Run with:
//   dart run tool/probe_real_pipeline.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:borland_dart/models/lsp_models.dart';
import 'package:borland_dart/utils/completion_filter.dart';

const String _source = 'void main() {\n  prin\n}\n';
const int _cursorLine = 1; // 0-based
const int _cursorChar = 6; // 0-based, right after "prin"

Future<void> main() async {
  final workspaceRoot = Directory.current.path;
  final tempDir = Directory.systemTemp.createTempSync('bd_pipeline_');
  final file = File('${tempDir.path}/main.dart')..writeAsStringSync(_source);

  stdout.writeln('source  : ${jsonEncode(_source)}');
  stdout.writeln('typed   : "prin" (chars 3-6 of line 2)');
  stdout.writeln('');

  final process = await Process.start(Platform.resolvedExecutable, [
    'language-server',
    '--client-id=probe',
  ]);

  final rpc = _JsonRpc(process);
  rpc.start();

  try {
    await rpc
        .request('initialize', {
          'processId': pid,
          'clientInfo': {'name': 'probe', 'version': '1.0.0'},
          'rootUri': Uri.directory(workspaceRoot).toString(),
          'capabilities': {
            'textDocument': {
              'synchronization': {
                'dynamicRegistration': false,
                'didSave': false,
              },
              'publishDiagnostics': {'relatedInformation': false},
              'completion': {
                'completionItem': {'snippetSupport': true},
              },
              'hover': <String, dynamic>{},
            },
            'workspace': {'workspaceFolders': true},
          },
          'initializationOptions': <String, dynamic>{},
          'workspaceFolders': [
            {
              'uri': Uri.directory(workspaceRoot).toString(),
              'name': 'workspace',
            },
          ],
        })
        .timeout(const Duration(seconds: 30));

    rpc.notify('initialized', <String, dynamic>{});

    final uri = Uri.file(file.path).toString();
    rpc.notify('textDocument/didOpen', {
      'textDocument': {
        'uri': uri,
        'languageId': 'dart',
        'version': 1,
        'text': _source,
      },
    });

    await Future<void>.delayed(const Duration(seconds: 12));

    final completion = await rpc
        .request('textDocument/completion', {
          'textDocument': {'uri': uri},
          'position': {'line': _cursorLine, 'character': _cursorChar},
        })
        .timeout(const Duration(seconds: 30));

    final rawItems = completion?['items'];
    final items = rawItems is List ? rawItems : const [];

    // --- Step 1: parse exactly like LspService.requestCompletion does. -------
    final parsed = <CompletionItem>[];
    for (final entry in items) {
      if (entry is! Map<String, dynamic>) continue;
      final label = entry['label'] as String? ?? '';
      if (label.isEmpty) continue;

      String? textEditNewText;
      final textEdit = entry['textEdit'];
      if (textEdit is Map<String, dynamic>) {
        textEditNewText = textEdit['newText'] as String?;
      }

      parsed.add(
        CompletionItem(
          label: label,
          kind: 'method',
          detail: entry['detail'] as String?,
          insertText: entry['insertText'] as String?,
          textEditNewText: textEditNewText,
          filterText: entry['filterText'] as String?,
        ),
      );
    }

    stdout.writeln('server returned ${parsed.length} item(s)');
    stdout.writeln('raw labels     : ${parsed.map((e) => e.label).toList()}');
    stdout.writeln(
      'display labels : ${parsed.map((e) => e.displayLabel).toList()}',
    );
    stdout.writeln('');

    // --- Step 2: filter on the word the user typed. -------------------------
    final currentWord = CompletionFilter.currentWord(_source, 20);
    stdout.writeln('currentWord(text, 20) = ${jsonEncode(currentWord)}');
    final filtered = CompletionFilter.filter(parsed, currentWord);

    stdout.writeln(
      'popup would show: ${filtered.map((e) => e.displayLabel).toList()}',
    );
    stdout.writeln('');

    final ok = filtered.isNotEmpty && filtered.first.displayLabel == 'print';
    if (ok) {
      stdout.writeln('RESULT: PASS - "print" is the first suggestion');
      stdout.writeln(
        '        inserting it would write: '
        '"${filtered.first.effectiveInsert}"',
      );
    } else {
      stdout.writeln(
        'RESULT: FAIL - got ${filtered.map((e) => e.displayLabel)}',
      );
    }
  } catch (e, st) {
    stdout.writeln('ERROR: $e');
    stdout.writeln('$st');
  } finally {
    await process.stdin.close();
    process.kill();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Minimal LSP JSON-RPC client over the child process' stdio.
class _JsonRpc {
  _JsonRpc(this._process);

  final Process _process;
  final Map<int, Completer<Map<String, dynamic>?>> _pending = {};
  int _nextId = 1;

  void start() {
    final buffer = <int>[];
    _process.stdout.listen((chunk) {
      buffer.addAll(chunk);
      _drain(buffer);
    });
  }

  void _drain(List<int> buffer) {
    while (true) {
      final headerEnd = _headerEnd(buffer);
      if (headerEnd == -1) return;

      final header = String.fromCharCodes(buffer.sublist(0, headerEnd));
      final match = RegExp(
        r'Content-Length:\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(header);
      if (match == null) {
        buffer.removeRange(0, headerEnd + 4);
        continue;
      }

      final length = int.parse(match.group(1)!);
      final bodyStart = headerEnd + 4;
      if (buffer.length < bodyStart + length) return;

      final body = utf8.decode(buffer.sublist(bodyStart, bodyStart + length));
      buffer.removeRange(0, bodyStart + length);

      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          final id = decoded['id'];
          if (id is int) {
            final completer = _pending.remove(id);
            if (completer != null && !completer.isCompleted) {
              final result = decoded['result'];
              completer.complete(
                result is Map<String, dynamic> ? result : null,
              );
            }
          }
        }
      } catch (_) {
        // Ignore malformed frames.
      }
    }
  }

  int _headerEnd(List<int> buffer) {
    for (var i = 0; i + 3 < buffer.length; i++) {
      if (buffer[i] == 13 &&
          buffer[i + 1] == 10 &&
          buffer[i + 2] == 13 &&
          buffer[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  Future<Map<String, dynamic>?> request(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = _nextId++;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    final completer = Completer<Map<String, dynamic>?>();
    _pending[id] = completer;
    _process.stdin.write(
      'Content-Length: ${utf8.encode(body).length}\r\n\r\n$body',
    );
    return completer.future;
  }

  void notify(String method, Map<String, dynamic> params) {
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
    _process.stdin.write(
      'Content-Length: ${utf8.encode(body).length}\r\n\r\n$body',
    );
  }
}
