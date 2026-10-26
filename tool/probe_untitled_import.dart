// Diagnostic probe: does the installed Dart language server offer `Timer`
// (an unimported symbol) and its `dart:async` auto-import for a *virtual*
// untitled buffer like the one `UnsavedBufferWorkspace` creates?
//
// Run with:
//   dart run tool/probe_untitled_import.dart
//
// Scenarios:
//   A. temp dir with only compile_flags.txt (what the app's unsaved workspace
//      currently holds), server started with that dir as rootUri.
//   B. same dir + a minimal pubspec.yaml + `dart pub get` package_config.
//   C. no pubspec, but the server started with the *repository* as rootUri
//      while the document lives in the temp dir (what the app does today:
//      workspaceRoot is the process CWD, the document is somewhere in /tmp).
//
// Deliberately free of any Flutter import so it runs under plain `dart run`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _source = '''
void f() {
  Timer
}
''';

const int _line = 1; // 0-based
const int _character = 7; // right after "  Timer"

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('cce_untitled_probe_');
  final file = File('${dir.path}/untitled.dart')..writeAsStringSync(_source);
  File('${dir.path}/compile_flags.txt').writeAsStringSync('');
  final uri = Uri.file(file.path).toString();

  stdout.writeln('temp dir : ${dir.path}');
  stdout.writeln('document : ${file.path}\n');

  try {
    await _run(
      name: 'A. bare temp dir (compile_flags only), rootUri = temp dir',
      rootUri: Uri.directory(dir.path).toString(),
      workingDirectory: dir.path,
      uri: uri,
    );

    File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: untitled_probe
environment:
  sdk: ^3.0.0
''');
    final pubGet = await Process.run(
      Platform.resolvedExecutable,
      <String>['pub', 'get'],
      workingDirectory: dir.path,
    );
    stdout.writeln(
      'dart pub get: exit=${pubGet.exitCode} '
      '${pubGet.exitCode == 0 ? "" : pubGet.stderr}',
    );

    await _run(
      name: 'B. temp dir + pubspec/package_config, rootUri = temp dir',
      rootUri: Uri.directory(dir.path).toString(),
      workingDirectory: dir.path,
      uri: uri,
    );

    await _run(
      name: 'C. bare temp dir, rootUri = repository (app workspaceRoot)',
      rootUri: Uri.directory(Directory.current.path).toString(),
      workingDirectory: Directory.current.path,
      uri: uri,
    );

    await _run(
      name: 'D. bare temp dir, rootUri = repository + temp dir as workspace folder',
      rootUri: Uri.directory(Directory.current.path).toString(),
      workingDirectory: Directory.current.path,
      uri: uri,
      extraFolder: Uri.directory(dir.path).toString(),
    );

    await _run(
      name: 'E. temp dir with pubspec, rootUri = repository + temp dir as folder',
      rootUri: Uri.directory(Directory.current.path).toString(),
      workingDirectory: Directory.current.path,
      uri: uri,
      extraFolder: Uri.directory(dir.path).toString(),
    );
  } finally {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

Future<void> _run({
  required String name,
  required String rootUri,
  required String workingDirectory,
  required String uri,
  String? extraFolder,
}) async {
  stdout.writeln('=== $name ===');
  final process = await Process.start(
    Platform.resolvedExecutable,
    <String>['language-server', '--client-id=probe-untitled'],
    workingDirectory: workingDirectory,
  );
  final rpc = _JsonRpc(process);
  rpc.start();

  try {
    final init = await rpc.request('initialize', <String, dynamic>{
      'processId': pid,
      'clientInfo': <String, dynamic>{'name': 'probe', 'version': '1.0.0'},
      'rootUri': rootUri,
      'capabilities': <String, dynamic>{
        'textDocument': <String, dynamic>{
          'synchronization': <String, dynamic>{
            'dynamicRegistration': false,
            'didSave': false,
          },
          'publishDiagnostics': <String, dynamic>{
            'relatedInformation': false,
          },
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
        <String, dynamic>{'uri': rootUri, 'name': 'workspace'},
      ],
    }).timeout(const Duration(seconds: 30));
    stdout.writeln('initialize: ${init == null ? "NO RESPONSE" : "ok"}');
    rpc.notify('initialized', <String, dynamic>{});
    if (extraFolder != null) {
      rpc.notify('workspace/didChangeWorkspaceFolders', <String, dynamic>{
        'event': <String, dynamic>{
          'added': <Map<String, dynamic>>[
            <String, dynamic>{'uri': extraFolder, 'name': 'untitled'},
          ],
          'removed': <Map<String, dynamic>>[],
        },
      });
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    rpc.notify('textDocument/didOpen', <String, dynamic>{
      'textDocument': <String, dynamic>{
        'uri': uri,
        'languageId': 'dart',
        'version': 1,
        'text': _source,
      },
    });

    await Future<void>.delayed(const Duration(seconds: 12));

    final completion = await rpc
        .request('textDocument/completion', <String, dynamic>{
          'textDocument': <String, dynamic>{'uri': uri},
          'position': <String, dynamic>{'line': _line, 'character': _character},
        })
        .timeout(const Duration(seconds: 30));

    final items = (completion?['items'] as List?) ?? const <dynamic>[];
    final labels = <String>[];
    Map<dynamic, dynamic>? timerRaw;
    for (final item in items) {
      if (item is! Map) continue;
      final label = item['label'];
      if (label is! String) continue;
      labels.add(label);
      if (label == 'Timer' && timerRaw == null) timerRaw = item;
    }
    stdout.writeln('items=${items.length} Timer present=${timerRaw != null}');
    stdout.writeln('sample=${labels.take(8).toList()}');
    stdout.writeln('diagnostics received: ${rpc.diagnosticCount}');

    if (timerRaw != null) {
      final resolved = await rpc
          .request(
            'completionItem/resolve',
            Map<String, dynamic>.from(timerRaw),
          )
          .timeout(const Duration(seconds: 30));
      final edits = resolved?['additionalTextEdits'];
      final importUris = resolved?['data']?['importUris'];
      stdout.writeln('resolve additionalTextEdits=${jsonEncode(edits)}');
      stdout.writeln('resolve data.importUris=${jsonEncode(importUris)}');
    } else {
      stdout.writeln('resolve: not attempted (no Timer item)');
    }
  } catch (e, st) {
    stdout.writeln('PROBE ERROR: $e\n$st');
  } finally {
    await rpc.dispose();
    process.kill();
  }
  stdout.writeln('');
}

/// Minimal LSP JSON-RPC client over the child process' stdio.
class _JsonRpc {
  _JsonRpc(this._process);

  final Process _process;
  final Map<int, Completer<Map<String, dynamic>?>> _pending = {};
  final List<int> _buffer = <int>[];
  int _nextId = 1;
  int diagnosticCount = 0;

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
        if (decoded is Map<String, dynamic>) _handleMessage(decoded);
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

  void _handleMessage(Map<String, dynamic> message) {
    final method = message['method'];
    final id = message['id'];

    if (method != null && id != null) {
      if (method == 'workspace/configuration') {
        _send(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <dynamic>[
            <String, dynamic>{'enableSnippets': true},
          ],
        });
      } else {
        _send(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': method == 'workspace/applyEdit'
              ? <String, dynamic>{
                  'applied': false,
                  'failureReason': 'not supported by this client',
                }
              : null,
        });
      }
      return;
    }

    if (method == 'textDocument/publishDiagnostics') diagnosticCount++;

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
