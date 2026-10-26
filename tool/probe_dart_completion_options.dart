// Diagnostic probe for the Dart language server's completion options.
//
// Answers, against the *installed* SDK's `dart language-server`:
//   1. Does `initializationOptions.suggestFromUnimportedLibraries: true` make
//      `Timer` / `Uint8List` (SDK libraries that are not imported) appear?
//   2. Does the client setting `dart.completeFunctionCalls` change the label
//      of `print` (e.g. `print()` instead of `print(…)`)?
//   3. Does the client setting `dart.enableSnippets` make snippet items
//      (kind 15) appear for a `for` prefix?
//
// Settings are served the way a real LSP client serves them: by advertising
// `workspace.configuration` and answering the server's
// `workspace/configuration` request with `{"dart": {...}}`-shaped values.
//
// Run with:
//   dart run tool/probe_dart_completion_options.dart
//
// Deliberately free of any Flutter import so it runs under plain `dart run`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _source = '''
void f() {
  Timer
}

void g() {
  Uint8List
}

void h() {
  prin
}

void i() {
  for
}

void j() {
  Random
}

void k() {
  StreamController
}
''';

const int _timerLine = 1;
const int _timerChar = 7;
const int _uint8Line = 5;
const int _uint8Char = 11;
const int _printLine = 9;
const int _printChar = 6;
const int _forLine = 13;
const int _forChar = 5;
const int _randomLine = 17;
const int _randomChar = 8;
const int _streamLine = 21;
const int _streamChar = 16;

Future<void> main(List<String> args) async {
  final onlyB = args.contains('--b');

  // A scratch package on disk: `tool/**` is excluded from this repository's
  // analysis options, so a sample there gets no full analysis context.
  final workspaceRoot =
      Directory.systemTemp.createTempSync('dart_completion_probe_').path;
  File('$workspaceRoot/pubspec.yaml').writeAsStringSync('''
name: completion_probe
environment:
  sdk: ^3.0.0
''');
  await Process.run(Platform.resolvedExecutable, ['pub', 'get'], workingDirectory: workspaceRoot);

  final file = File('$workspaceRoot/bin/main.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(_source);
  final uri = Uri.file(file.path).toString();

  stdout.writeln('dart      : ${Platform.resolvedExecutable}');
  stdout.writeln('workspace : $workspaceRoot');
  stdout.writeln('file      : ${file.path}\n');

  try {
    if (onlyB) {
      await _runScenario(
        name: 'B. + initializationOptions.suggestFromUnimportedLibraries',
        workspaceRoot: workspaceRoot,
        uri: uri,
        suggestUnimported: true,
        settings: const <String, dynamic>{},
      );
      return;
    }
    await _runScenario(
      name: 'A. baseline (no unimported libraries, no settings)',
      workspaceRoot: workspaceRoot,
      uri: uri,
      suggestUnimported: false,
      settings: const <String, dynamic>{},
    );

    await _runScenario(
      name: 'B. + initializationOptions.suggestFromUnimportedLibraries',
      workspaceRoot: workspaceRoot,
      uri: uri,
      suggestUnimported: true,
      settings: const <String, dynamic>{},
    );

    await _runScenario(
      name: 'C. B + dart.enableSnippets (workspace/configuration)',
      workspaceRoot: workspaceRoot,
      uri: uri,
      suggestUnimported: true,
      settings: const <String, dynamic>{'enableSnippets': true},
    );

    await _runScenario(
      name: 'E. applyEdit true + suggestFromUnimportedLibraries: false',
      workspaceRoot: workspaceRoot,
      uri: uri,
      suggestUnimported: false,
      settings: const <String, dynamic>{},
    );

    await _runScenario(
      name: 'F. applyEdit true + dart.enableSnippets: false',
      workspaceRoot: workspaceRoot,
      uri: uri,
      suggestUnimported: true,
      settings: const <String, dynamic>{'enableSnippets': false},
    );

    await _runScenario(
      name: 'D. B + dart.completeFunctionCalls (workspace/configuration)',
      workspaceRoot: workspaceRoot,
      uri: uri,
      suggestUnimported: true,
      settings: const <String, dynamic>{'completeFunctionCalls': true},
    );
  } finally {
    try {
      Directory(workspaceRoot).deleteSync(recursive: true);
    } catch (_) {}
  }
}

Future<void> _runScenario({
  required String name,
  required String workspaceRoot,
  required String uri,
  required bool suggestUnimported,
  required Map<String, dynamic> settings,
}) async {
  stdout.writeln('=== $name ===');

  final process = await Process.start(Platform.resolvedExecutable, [
    'language-server',
    '--client-id=probe-options',
  ]);
  final rpc = _JsonRpc(process, dartSettings: settings);
  rpc.start();

  try {
    final init = await rpc
        .request('initialize', <String, dynamic>{
          'processId': pid,
          'clientInfo': <String, dynamic>{'name': 'probe', 'version': '1.0.0'},
          'rootUri': Uri.directory(workspaceRoot).toString(),
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
            'suggestFromUnimportedLibraries': suggestUnimported,
          },
          'workspaceFolders': <Map<String, dynamic>>[
            <String, dynamic>{
              'uri': Uri.directory(workspaceRoot).toString(),
              'name': 'workspace',
            },
          ],
        })
        .timeout(const Duration(seconds: 30));

    stdout.writeln(
      'initialize: ${init == null ? "NO RESPONSE" : "ok"}  '
      'completionProvider=${jsonEncode(init?["capabilities"]?["completionProvider"])}',
    );
    rpc.notify('initialized', <String, dynamic>{});
    rpc.notify('textDocument/didOpen', <String, dynamic>{
      'textDocument': <String, dynamic>{
        'uri': uri,
        'languageId': 'dart',
        'version': 1,
        'text': _source,
      },
    });

    // The analyzer needs a moment to build its context before the first query.
    await Future<void>.delayed(const Duration(seconds: 12));

    stdout.writeln('workspace/configuration requests: '
        '${rpc.configurationRequests}  (answered with ${jsonEncode(settings)})');

    final printItems = await _completion(
      rpc,
      uri,
      line: _printLine,
      character: _printChar,
      prefix: 'prin',
    );
    final loopItems = await _completion(
      rpc,
      uri,
      line: _forLine,
      character: _forChar,
      prefix: '',
    );
    final random = await _completion(
      rpc, uri, line: _randomLine, character: _randomChar, prefix: 'Random');
    final stream = await _completion(
      rpc, uri, line: _streamLine, character: _streamChar, prefix: 'StreamController');
    stdout.writeln('  Random raw   : ${random.total} ${random.rawLabels.take(4).toList()}');
    stdout.writeln('  StreamCtrl   : ${stream.total} ${stream.rawLabels.take(4).toList()}');
    final timer = await _completion(
      rpc,
      uri,
      line: _timerLine,
      character: _timerChar,
      prefix: 'Timer',
    );
    final uint8 = await _completion(
      rpc,
      uri,
      line: _uint8Line,
      character: _uint8Char,
      prefix: 'Uint8',
    );

    stdout.writeln('  Timer present   : ${timer.present} '
        '(${timer.total} items, raw=${timer.rawLabels.take(6).toList()})');
    stdout.writeln('  Timer raw item  : ${jsonEncode(timer.rawFirst)}');
    final rawTimer = timer.rawFirst;
    if (rawTimer != null) {
      final resolved = await rpc
          .request('completionItem/resolve', Map<String, dynamic>.from(rawTimer))
          .timeout(const Duration(seconds: 30));
      stdout.writeln('  Timer resolved  : ${jsonEncode(resolved)}');
    }
    stdout.writeln('  Uint8List gone? : ${uint8.present} '
        '(${uint8.total} items, raw=${uint8.rawLabels.take(6).toList()})');
    stdout.writeln('  print labels    : ${printItems.labels}');
    stdout.writeln('  snippet kind-15 : ${loopItems.snippetCount} '
        '${loopItems.snippetLabels}');
  } catch (e, st) {
    stdout.writeln('PROBE ERROR: $e\n$st');
  } finally {
    await rpc.dispose();
    process.kill();
  }
  stdout.writeln('');
}

class _CompletionResult {
  _CompletionResult({
    required this.total,
    required this.labels,
    required this.rawLabels,
    required this.snippetCount,
    required this.snippetLabels,
    required this.present,
    this.rawFirst,
  });

  final int total;
  final List<String> labels;
  final List<String> rawLabels;
  final int snippetCount;
  final List<String> snippetLabels;
  final bool present;
  final Map<dynamic, dynamic>? rawFirst;
}

Future<_CompletionResult> _completion(
  _JsonRpc rpc,
  String uri, {
  required int line,
  required int character,
  required String prefix,
}) async {
  final response = await rpc
      .request('textDocument/completion', <String, dynamic>{
        'textDocument': <String, dynamic>{'uri': uri},
        'position': <String, dynamic>{'line': line, 'character': character},
      })
      .timeout(const Duration(seconds: 30));

  final rawItems = response?['items'];
  final items = rawItems is List ? rawItems : const <dynamic>[];

  final labels = <String>[];
  final rawLabels = <String>[];
  final snippetLabels = <String>[];
  Map<dynamic, dynamic>? firstTimerItem;
  for (final item in items) {
    if (item is! Map) continue;
    final itemLabel = item['label'];
    if (itemLabel is! String) continue;
    rawLabels.add(itemLabel);
    if (prefix.isEmpty ||
        itemLabel.toLowerCase().startsWith(prefix.toLowerCase())) {
      labels.add(itemLabel);
    }
    if (item['kind'] == 15) snippetLabels.add(itemLabel);
    if (itemLabel == prefix && firstTimerItem == null) firstTimerItem = item;
  }

  return _CompletionResult(
    total: items.length,
    labels: labels,
    rawLabels: rawLabels,
    snippetCount: snippetLabels.length,
    snippetLabels: snippetLabels.take(8).toList(),
    present: rawLabels.any((l) => l == '${prefix}()' || l == prefix),
    rawFirst: firstTimerItem,
  );
}

/// Minimal LSP JSON-RPC client over the child process' stdio.
class _JsonRpc {
  _JsonRpc(this._process, {required this.dartSettings});

  final Process _process;
  final Map<String, dynamic> dartSettings;
  final Map<int, Completer<Map<String, dynamic>?>> _pending = {};
  int _nextId = 1;
  int configurationRequests = 0;

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
      final match = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false)
          .firstMatch(header);
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
    final method = message['method'];
    final id = message['id'];

    // Server-initiated request: answer `workspace/configuration`.
    if (method != null && id != null) {
      if (method == 'workspace/configuration') {
        configurationRequests++;
        final params = message['params'];
        final items = (params is Map ? params['items'] : null) as List?;
        final count = items?.length ?? 1;
        _send(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <dynamic>[
            for (var i = 0; i < count; i++) <String, dynamic>{...dartSettings},
          ],
        });
      } else {
        // Politely decline anything else.
        _send(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': null,
        });
      }
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
