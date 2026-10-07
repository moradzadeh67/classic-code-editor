// Diagnostic probe: talks raw JSON-RPC to `dart language-server` over stdio
// and dumps the RAW completion labels for a given source snippet.
//
// This answers the question "is `print` even in the server's response for a
// file containing `prin`?", which client-side filtering alone cannot fix.
//
// Run with:
//   dart run tool/probe_lsp_completion.dart
//
// Deliberately free of any Flutter import so it runs under plain `dart run`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _source = '''
void main() {
  prin
}
''';

/// Character offset just after `prin` on line 2 (1-based line 2, col 7).
const int _cursorLine = 1; // 0-based
const int _cursorChar = 6; // 0-based, right after "prin"

Future<void> main(List<String> args) async {
  // A temp file inside a real Dart package resolves much better than one in
  // /tmp, so allow overriding the location to compare both.
  final useWorkspaceFile = args.contains('--in-workspace');

  final workspaceRoot = Directory.current.path;
  final file = useWorkspaceFile
      ? File('$workspaceRoot/tool/_probe_sample.dart')
      : File(
          '${Directory.systemTemp.createTempSync('bd_probe_').path}/main.dart',
        );
  file.writeAsStringSync(_source);

  stdout.writeln('workspace : $workspaceRoot');
  stdout.writeln('file      : ${file.path}');
  stdout.writeln('source    : ${jsonEncode(_source)}');
  stdout.writeln('cursor    : line=$_cursorLine char=$_cursorChar');
  stdout.writeln('');

  final dartExecutable = Platform.resolvedExecutable;
  stdout.writeln('dart      : $dartExecutable');

  final process = await Process.start(dartExecutable, [
    'language-server',
    '--client-id=probe',
  ]);

  final stderrLines = <String>[];
  process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (l) {
      if (l.trim().isNotEmpty) stderrLines.add(l);
    },
  );

  final rpc = _JsonRpc(process);
  rpc.start();

  try {
    final initResult = await rpc
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

    stdout.writeln('initialize: ${initResult == null ? "NO RESPONSE" : "ok"}');

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

    // Give the analyzer a moment to build its context before asking.
    await Future<void>.delayed(const Duration(seconds: 12));

    final completion = await rpc
        .request('textDocument/completion', {
          'textDocument': {'uri': uri},
          'position': {'line': _cursorLine, 'character': _cursorChar},
        })
        .timeout(const Duration(seconds: 30));

    stdout.writeln('');
    stdout.writeln('=== RAW COMPLETION RESPONSE ===');
    if (completion == null) {
      stdout.writeln('NO RESPONSE');
    } else {
      final raw = completion['items'];
      final items = raw is List ? raw : const [];
      stdout.writeln('item count: ${items.length}');

      final labels = <String>[];
      for (final item in items) {
        if (item is Map) {
          final label = item['label'];
          if (label is String) labels.add(label);
        }
      }
      stdout.writeln('labels: $labels');

      stdout.writeln('');
      stdout.writeln('contains "print"?  ${labels.contains('print')}');
      stdout.writeln(
        'labels starting with "prin": '
        '${labels.where((l) => l.toLowerCase().startsWith('prin')).toList()}',
      );

      // Show the raw shape of the first item so we can see kind/detail.
      if (items.isNotEmpty) {
        stdout.writeln('');
        stdout.writeln('first item raw: ${jsonEncode(items.first)}');
      }
    }
  } catch (e, st) {
    stdout.writeln('PROBE ERROR: $e');
    stdout.writeln('$st');
  } finally {
    if (stderrLines.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('=== server stderr ===');
      for (final l in stderrLines) {
        stdout.writeln(l);
      }
    }
    await rpc.dispose();
    process.kill();
    if (!useWorkspaceFile) {
      try {
        file.parent.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}

/// Minimal LSP JSON-RPC client over the child process' stdio.
class _JsonRpc {
  _JsonRpc(this._process);

  final Process _process;
  final Map<int, Completer<Map<String, dynamic>?>> _pending = {};
  final List<Map<String, dynamic>> _diagnostics = [];
  int _nextId = 1;

  List<Map<String, dynamic>> get diagnostics => _diagnostics;

  void start() {
    final buffer = <int>[];

    _process.stdout.listen((chunk) {
      buffer.addAll(chunk);
      _drainBuffer(buffer);
    });
  }

  void _drainBuffer(List<int> buffer) {
    while (true) {
      final headerEnd = _findHeaderEnd(buffer);
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
        if (decoded is Map<String, dynamic>) _handleMessage(decoded);
      } catch (_) {
        // Ignore malformed frames.
      }
    }
  }

  int _findHeaderEnd(List<int> buffer) {
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

  void _handleMessage(Map<String, dynamic> message) {
    final id = message['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        final result = message['result'];
        completer.complete(result is Map<String, dynamic> ? result : null);
      }
      return;
    }

    // Notification: keep diagnostics so we can spot "no analysis context".
    final method = message['method'];
    if (method == 'textDocument/publishDiagnostics') {
      final params = message['params'];
      if (params is Map<String, dynamic>) _diagnostics.add(params);
    }
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

  Future<void> dispose() async {
    await _process.stdin.close();
  }
}
