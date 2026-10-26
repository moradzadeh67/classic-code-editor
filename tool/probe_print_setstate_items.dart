// Diagnostic probe: what does the installed Dart language server actually send
// for the `print` and `setState` completion items?
//
// Run with:
//   dart run tool/probe_print_setstate_items.dart
//
// Prints the raw `kind`, `insertText`, `insertTextFormat`, `textEdit`, `detail`
// and `label` of both items, which the acceptance tests and TASKS.md quote.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _source = '''
void f() {
  pri
}

class W extends State<Object> {
  @override
  Widget build(BuildContext context) {
    setS
    return const SizedBox();
  }
}
''';

const int _printLine = 1;
const int _printChar = 5;
const int _setStateLine = 7;
const int _setStateChar = 8;

Future<void> main(List<String> args) async {
  // `--flutter` uses a scratch *Flutter* package instead of a bare Dart one;
  // `setState` only exists when the Flutter SDK is on the analysis path.
  final useFlutter = args.contains('--flutter');
  final dir = useFlutter
      ? Directory('${Directory.current.path}/.probe_items')
      : Directory.systemTemp.createTempSync('cce_items_probe_');
  dir.createSync(recursive: true);
  if (useFlutter) {
    File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: probe_items
environment:
  sdk: ^3.0.0
dependencies:
  flutter:
    sdk: flutter
''');
    await Process.run(
      Platform.resolvedExecutable,
      <String>['pub', 'get'],
      workingDirectory: dir.path,
    );
  }
  final source = useFlutter
      ? "import 'package:flutter/material.dart';\n\n$_source"
      : _source;
  final file = File('${dir.path}/untitled.dart')..writeAsStringSync(source);
  final uri = Uri.file(file.path).toString();

  final process = await Process.start(
    Platform.resolvedExecutable,
    <String>['language-server', '--client-id=probe-items'],
    workingDirectory: dir.path,
  );
  final rpc = _JsonRpc(process);
  rpc.start();

  try {
    await rpc.request('initialize', <String, dynamic>{
      'processId': pid,
      'clientInfo': <String, dynamic>{'name': 'probe', 'version': '1.0.0'},
      'rootUri': Uri.directory(dir.path).toString(),
      'capabilities': <String, dynamic>{
        'textDocument': <String, dynamic>{
          'completion': <String, dynamic>{
            'completionItem': <String, dynamic>{'snippetSupport': true},
          },
          'hover': <String, dynamic>{},
        },
        'workspace': <String, dynamic>{
          'applyEdit': true,
          'configuration': true,
          'workspaceFolders': true,
        },
      },
      'initializationOptions': <String, dynamic>{
        'suggestFromUnimportedLibraries': true,
      },
      'workspaceFolders': <Map<String, dynamic>>[
        <String, dynamic>{
          'uri': Uri.directory(dir.path).toString(),
          'name': 'workspace',
        },
      ],
    }).timeout(const Duration(seconds: 30));
    rpc.notify('initialized', <String, dynamic>{});
    rpc.notify('textDocument/didOpen', <String, dynamic>{
      'textDocument': <String, dynamic>{
        'uri': uri,
        'languageId': 'dart',
        'version': 1,
        'text': source,
      },
    });

    await Future<void>.delayed(const Duration(seconds: 12));

    final offset = useFlutter ? 2 : 0; // the import adds two lines
    for (final (label, line, character) in <(String, int, int)>[
      ('print', _printLine + offset, _printChar),
      ('setState', _setStateLine + offset, _setStateChar),
    ]) {
      final response = await rpc
          .request('textDocument/completion', <String, dynamic>{
            'textDocument': <String, dynamic>{'uri': uri},
            'position': <String, dynamic>{'line': line, 'character': character},
          })
          .timeout(const Duration(seconds: 30));

      final items = (response?['items'] as List?) ?? const <dynamic>[];
      Map<dynamic, dynamic>? match;
      for (final item in items) {
        if (item is Map && '${item['label']}'.startsWith(label)) {
          match = item;
          break;
        }
      }
      stdout.writeln('$label -> ${match == null ? "NOT FOUND" : jsonEncode(match)}');
    }
  } catch (e, st) {
    stdout.writeln('PROBE ERROR: $e\n$st');
  } finally {
    await rpc.dispose();
    process.kill();
    if (!useFlutter) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}

/// Minimal LSP JSON-RPC client over the child process' stdio.
class _JsonRpc {
  _JsonRpc(this._process);

  final Process _process;
  final Map<int, Completer<Map<String, dynamic>?>> _pending = {};
  final List<int> _buffer = <int>[];
  int _nextId = 1;

  void start() {
    _process.stdout.listen((chunk) {
      _buffer.addAll(chunk);
      _drain();
    });
  }

  void _drain() {
    while (true) {
      final headerEnd = _findHeaderEnd();
      if (headerEnd == -1) return;
      final header = String.fromCharCodes(_buffer.sublist(0, headerEnd));
      final match = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false)
          .firstMatch(header);
      if (match == null) {
        _buffer.removeRange(0, headerEnd + 4);
        continue;
      }
      final length = int.parse(match.group(1)!);
      final bodyStart = headerEnd + 4;
      if (_buffer.length < bodyStart + length) return;
      final body = utf8.decode(_buffer.sublist(bodyStart, bodyStart + length));
      _buffer.removeRange(0, bodyStart + length);
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) _handle(decoded);
      } catch (_) {
        // Ignore malformed frames.
      }
    }
  }

  int _findHeaderEnd() {
    for (var i = 0; i + 3 < _buffer.length; i++) {
      if (_buffer[i] == 13 &&
          _buffer[i + 1] == 10 &&
          _buffer[i + 2] == 13 &&
          _buffer[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  void _handle(Map<String, dynamic> message) {
    final method = message['method'];
    final id = message['id'];
    if (method != null && id != null) {
      _send(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': method == 'workspace/configuration'
            ? <dynamic>[
                <String, dynamic>{'enableSnippets': true},
              ]
            : method == 'workspace/applyEdit'
            ? <String, dynamic>{
                'applied': false,
                'failureReason': 'not supported by this client',
              }
            : null,
      });
      return;
    }
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        final result = message['result'];
        completer.complete(result is Map<String, dynamic> ? result : null);
      }
    }
  }

  Future<Map<String, dynamic>?> request(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>?>();
    _pending[id] = completer;
    _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    return completer.future;
  }

  void notify(String method, Map<String, dynamic> params) {
    _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  void _send(Map<String, dynamic> message) {
    final body = jsonEncode(message);
    _process.stdin.write(
      'Content-Length: ${utf8.encode(body).length}\r\n\r\n$body',
    );
  }

  Future<void> dispose() async {
    await _process.stdin.close();
  }
}
