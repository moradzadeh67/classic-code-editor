import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:classic_code_editor/services/lsp_server_spec.dart';

/// Opt-in: needs a real clangd on this Mac.
///
///     BORLAND_REAL_CLANGD_TEST=1 flutter test \
///       test/integration/clangd_presence_test.dart
///
/// The unit suite never spawns a language server (`FLUTTER_TEST` short-circuits
/// `LspService`), so only this test proves that the arguments in
/// [LspServerSpec.clangd] really produce a working handshake.
void main() {
  const gate = 'BORLAND_REAL_CLANGD_TEST';
  final enabled = Platform.environment[gate] == '1';
  final skip = enabled ? null : 'set $gate=1 to run against the real clangd';

  test('clangd is installed and reports a version', () async {
    final clangd = await _findClangd();

    expect(
      clangd,
      isNotNull,
      reason: 'install it with `xcode-select --install` or `brew install llvm`',
    );

    final version = await Process.run(clangd!, <String>['--version']);
    expect(version.exitCode, 0);
    expect(version.stdout.toString().toLowerCase(), contains('clangd'));
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));

  test('clangd answers initialize with the arguments the spec uses', () async {
    final clangd = await _findClangd();
    expect(clangd, isNotNull);

    final process = await Process.start(clangd!, LspServerSpec.clangd.arguments);
    final client = _LspClient(process);
    addTearDown(() async {
      client.send(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'exit',
      });
      process.kill(ProcessSignal.sigkill);
      await client.dispose();
    });

    final initialize = client
        .nextResponse(1)
        .timeout(const Duration(seconds: 20));
    client.send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, dynamic>{
        'processId': pid,
        'clientInfo': <String, dynamic>{
          'name': LspServerSpec.clientId,
          'version': LspServerSpec.clientVersion,
        },
        'rootUri': null,
        'capabilities': <String, dynamic>{},
      },
    });

    final response = await initialize;
    final result = response['result'];
    expect(result, isA<Map<String, dynamic>>());
    expect((result! as Map<String, dynamic>)['capabilities'], isNotNull);

    final shutdown = client
        .nextResponse(2)
        .timeout(const Duration(seconds: 10));
    client.send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'shutdown',
      'params': <String, dynamic>{},
    });
    expect((await shutdown)['error'], isNull);
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));
}

Future<String?> _findClangd() async {
  for (final candidate in LspServerSpec.clangd.executableNames) {
    if (candidate.contains('/')) {
      if (File(candidate).existsSync()) return candidate;
      continue;
    }
    final result = await Process.run('/usr/bin/which', <String>[candidate]);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim();
      if (path.isNotEmpty) return path;
    }
  }
  return null;
}

/// Minimal `Content-Length` framed LSP client, enough for two request/response
/// round-trips without any of `LspService`'s test-mode short-circuits.
class _LspClient {
  _LspClient(this._process) {
    _subscription = _process.stdout.listen(_onData);
    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(stdout.writeln);
  }

  final Process _process;
  final List<int> _buffer = <int>[];
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);
  StreamSubscription<List<int>>? _subscription;

  /// Completes with the response whose `id` is [id].
  Future<Map<String, dynamic>> nextResponse(int id) {
    return _messages.stream.firstWhere(
      (message) => message['id'] == id && message['method'] == null,
    );
  }

  void send(Map<String, dynamic> message) {
    final body = utf8.encode(jsonEncode(message));
    _process.stdin.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
    _process.stdin.add(body);
    _process.stdin.flush();
  }

  void _onData(List<int> chunk) {
    _buffer.addAll(chunk);
    while (true) {
      final headerEnd = _headerEnd();
      if (headerEnd < 0) return;
      final header = latin1.decode(_buffer.sublist(0, headerEnd));
      final match = RegExp(
        r'Content-Length:\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(header);
      if (match == null) {
        _buffer.removeRange(0, headerEnd + 4);
        continue;
      }
      final length = int.parse(match.group(1)!);
      final bodyStart = headerEnd + 4;
      if (_buffer.length < bodyStart + length) return;

      final body = utf8.decode(_buffer.sublist(bodyStart, bodyStart + length));
      _buffer.removeRange(0, bodyStart + length);

      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) _messages.add(decoded);
    }
  }

  int _headerEnd() {
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

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _messages.close();
    await _process.stdin.close();
  }
}
