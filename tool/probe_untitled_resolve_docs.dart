// Diagnostic probe: what does `completionItem/resolve` return for `print`,
// `List` and `DateTime` on a virtual untitled buffer?
//
// Run with:
//   dart run tool/probe_untitled_resolve_docs.dart
//
// Prints, for the selected item: label, kind, `detail`, whether
// `documentation` is present (and its kind/value length) and whether
// `additionalTextEdits` came back. This is what the completion doc panel
// renders (or fails to render).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _source = '''
void f() {
  prin
}

void g() {
  Lis
}

void h() {
  DateTim
}
''';

const int _printLine = 1;
const int _printChar = 6;
const int _listLine = 5;
const int _listChar = 5;
const int _dateLine = 9;
const int _dateChar = 8;

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('cce_resolve_docs_');
  final file = File('${dir.path}/untitled.dart')..writeAsStringSync(_source);
  File('${dir.path}/compile_flags.txt').writeAsStringSync('');
  final uri = Uri.file(file.path).toString();

  final process = await Process.start(
    Platform.resolvedExecutable,
    <String>['language-server', '--client-id=probe-resolve-docs'],
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
        'text': _source,
      },
    });

    await Future<void>.delayed(const Duration(seconds: 12));

    for (final (prefix, line, character) in <(String, int, int)>[
      ('print', _printLine, _printChar),
      ('List', _listLine, _listChar),
      ('DateTime', _dateLine, _dateChar),
    ]) {
      // The uri the client must use: the document the server actually has
      // open (the virtual untitled path).
      final response = await rpc
          .request('textDocument/completion', <String, dynamic>{
            'textDocument': <String, dynamic>{'uri': uri},
            'position': <String, dynamic>{'line': line, 'character': character},
          })
          .timeout(const Duration(seconds: 30));

      // The uri an Unsaved tab used to send: its display name, which the
      // server does not have open. The list is empty, so nothing can resolve.
      final wrongUri = Uri.file('${Directory.current.path}/Untitled').toString();
      final wrongResponse = await rpc
          .request('textDocument/completion', <String, dynamic>{
            'textDocument': <String, dynamic>{'uri': wrongUri},
            'position': <String, dynamic>{'line': line, 'character': character},
          })
          .timeout(const Duration(seconds: 30));
      final wrongItems = (wrongResponse?['items'] as List?) ?? const <dynamic>[];
      stdout.writeln(
        '$prefix: open-document items=${(response?['items'] as List?)?.length} '
        'vs "Untitled" uri items=${wrongItems.length}',
      );

      final items = (response?['items'] as List?) ?? const <dynamic>[];
      Map<dynamic, dynamic>? match;
      for (final item in items) {
        if (item is Map && '${item['label']}'.startsWith(prefix)) {
          match = item;
          break;
        }
      }
      if (match == null) {
        stdout.writeln('$prefix -> NOT IN LIST (${items.length} items)');
        continue;
      }

      final label = match['label'];
      final resolved = await rpc
          .request('completionItem/resolve', Map<String, dynamic>.from(match))
          .timeout(const Duration(seconds: 30));

      final doc = resolved?['documentation'];
      stdout.writeln('--- $prefix');
      stdout.writeln('  label      : $label  kind=${match['kind']}');
      stdout.writeln('  detail     : ${jsonEncode(resolved?['detail'])}');
      stdout.writeln(
        '  documentation: ${doc == null ? "NULL" : doc is String ? "String(${doc.length})" : doc is Map ? "MarkupContent(kind=${doc['kind']}, value=${'${doc['value']}'.length})" : doc.runtimeType}'
        '${doc is String && doc.isNotEmpty ? " first=${jsonEncode(doc.split('\n').first)}" : ""}',
      );
      stdout.writeln(
        '  additionalTextEdits: ${jsonEncode(resolved?['additionalTextEdits'])}',
      );
    }
  } catch (e, st) {
    stdout.writeln('PROBE ERROR: $e\n$st');
  } finally {
    await rpc.dispose();
    process.kill();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
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
