import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A minimal JSON-RPC 2.0 client for the Dart VM Service protocol, speaking
/// over a `dart:io` [WebSocket].
///
/// The Dart VM Service (formerly known as "Observatory") exposes a JSON-RPC
/// API over a WebSocket at `ws://host:port/<auth-token>/ws`. This client
/// handles request/response correlation by id and surfaces the asynchronous
/// stream notifications (debug pauses, isolate lifecycle, ...) through
/// [events].
///
/// No external package is required: the framing and transport are provided by
/// `dart:convert` and `dart:io`.
class VmServiceClient {
  VmServiceClient._(this._socket, this._uri);

  final WebSocket _socket;
  final Uri _uri;

  final Map<int, Completer<Map<String, dynamic>?>> _pending = {};
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  int _nextId = 1;
  bool _closed = false;

  /// The WebSocket endpoint this client is connected to.
  Uri get uri => _uri;

  /// Stream of `streamNotify` payloads, i.e. the `event` object of every
  /// notification delivered by the service (Debug, Isolate, VM, ... streams).
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Connects to the VM Service [httpUri] printed by the Dart VM and completes
  /// with a ready [VmServiceClient] once the WebSocket handshake succeeds.
  static Future<VmServiceClient> connect(String httpUri) async {
    final endpoint = webSocketUriFor(httpUri);
    final socket = await WebSocket.connect(endpoint.toString());
    final client = VmServiceClient._(socket, endpoint);
    client._listen();
    return client;
  }

  /// Converts the HTTP VM Service URI printed by the Dart VM into the
  /// corresponding WebSocket endpoint URI (same host/port, `ws` scheme and a
  /// trailing `/ws` path segment).
  static Uri webSocketUriFor(String httpUri) {
    final parsed = Uri.parse(httpUri.trim());
    final scheme = parsed.scheme == 'https' ? 'wss' : 'ws';
    final basePath = parsed.path.isEmpty ? '/' : parsed.path;
    final path = basePath.endsWith('/') ? '${basePath}ws' : '$basePath/ws';
    return parsed.replace(scheme: scheme, path: path);
  }

  void _listen() {
    _socket.listen(
      (dynamic data) {
        if (data is String) {
          _handleMessage(data);
        } else if (data is List<int>) {
          _handleMessage(utf8.decode(data, allowMalformed: true));
        }
      },
      onError: (Object error) => _fail(error),
      onDone: () => _fail(StateError('VM Service connection closed')),
      cancelOnError: true,
    );
  }

  void _handleMessage(String raw) {
    if (raw.trim().isEmpty) return;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      debugPrint('VmServiceClient: failed to decode message: $e');
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    // A response to one of our own requests carries the request id back.
    final id = decoded['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer == null || completer.isCompleted) return;
      final error = decoded['error'];
      if (error != null) {
        debugPrint('VmServiceClient: request $id failed: $error');
        completer.complete(null);
      } else {
        final result = decoded['result'];
        completer.complete(result is Map<String, dynamic> ? result : null);
      }
      return;
    }

    // Otherwise it is a server-initiated notification.
    if (decoded['method'] == 'streamNotify') {
      final params = decoded['params'];
      if (params is Map<String, dynamic>) {
        final event = params['event'];
        if (event is Map<String, dynamic> && !_events.isClosed) {
          _events.add(event);
        }
      }
    }
  }

  /// Sends a JSON-RPC [method] with optional [params] and awaits its result.
  ///
  /// Completes with `null` if the service reports an error or does not answer
  /// within [timeout].
  Future<Map<String, dynamic>?> call(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 15),
  ]) {
    if (_closed) return Future<Map<String, dynamic>?>.value();

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>?>();
    _pending[id] = completer;

    final message = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
    };
    if (params != null) message['params'] = params;
    _socket.add(jsonEncode(message));

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        return null;
      },
    );
  }

  void _fail(Object error) {
    if (_closed) return;
    debugPrint('VmServiceClient: $error');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
    if (!_events.isClosed) _events.close();
  }

  /// Closes the WebSocket and releases all resources.
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
    try {
      await _socket.close();
    } catch (e) {
      debugPrint('VmServiceClient: error closing socket: $e');
    }
    if (!_events.isClosed) await _events.close();
  }
}
