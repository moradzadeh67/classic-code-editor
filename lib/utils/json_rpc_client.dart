import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A minimal JSON-RPC 2.0 client that handles the `Content-Length` header
/// framing required by the Language Server Protocol when it is carried over
/// a byte stream such as stdio.
///
/// The class is deliberately transport agnostic:
/// * it writes framed messages to an [IOSink], and
/// * it exposes a stream of decoded JSON-RPC messages that are pushed in via
///   [feed] (typically from a process's `stdout`).
///
/// Request/response correlation is intentionally left to the caller so this
/// helper stays a thin, reusable framing layer.
class JsonRpcClient {
  static const List<int> _headerTerminator = <int>[13, 10, 13, 10]; // \r\n\r\n

  final IOSink _sink;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Raw bytes received so far that do not yet form a complete message.
  final List<int> _buffer = <int>[];

  bool _disposed = false;

  JsonRpcClient(this._sink);

  /// Decoded JSON-RPC messages received from the remote endpoint.
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Encodes [message] as JSON and writes it to the sink, prefixed with the
  /// required `Content-Length` header.
  ///
  /// The length is measured in UTF-8 bytes (not characters), which is what the
  /// protocol requires.
  void send(Map<String, dynamic> message) {
    if (_disposed) return;

    final body = utf8.encode(jsonEncode(message));
    final header = utf8.encode('Content-Length: ${body.length}\r\n\r\n');
    _sink.add(header);
    _sink.add(body);
  }

  /// Feeds raw [data] received from the remote endpoint into the parser.
  ///
  /// Data may arrive split at arbitrary byte boundaries; the parser buffers
  /// incomplete frames until more data becomes available.
  void feed(List<int> data) {
    if (_disposed || data.isEmpty) return;
    _buffer.addAll(data);
    _drainBuffer();
  }

  void _drainBuffer() {
    while (true) {
      final headerEnd = _indexOf(_buffer, _headerTerminator);
      if (headerEnd < 0) return; // Header not complete yet.

      final headerText = ascii.decode(
        _buffer.sublist(0, headerEnd),
        allowInvalid: true,
      );
      final contentLength = _parseContentLength(headerText);
      if (contentLength == null) {
        // Malformed header: drop a single byte and try to resynchronise.
        _buffer.removeAt(0);
        continue;
      }

      final bodyStart = headerEnd + _headerTerminator.length;
      if (_buffer.length < bodyStart + contentLength) {
        return; // Body not complete yet.
      }

      final bodyBytes = _buffer.sublist(bodyStart, bodyStart + contentLength);
      _buffer.removeRange(0, bodyStart + contentLength);

      try {
        final decoded = jsonDecode(utf8.decode(bodyBytes));
        if (decoded is Map<String, dynamic>) {
          _messageController.add(decoded);
        }
      } catch (e) {
        // Ignore individual malformed payloads; subsequent frames may still be
        // valid and the parser is already positioned at the next message.
        stderr.writeln('[JsonRpcClient] Failed to decode message: $e');
      }
    }
  }

  int? _parseContentLength(String headerText) {
    for (final line in headerText.split('\r\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final colon = trimmed.indexOf(':');
      if (colon < 0) continue;

      final name = trimmed.substring(0, colon).trim().toLowerCase();
      if (name == 'content-length') {
        return int.tryParse(trimmed.substring(colon + 1).trim());
      }
    }
    return null;
  }

  static int _indexOf(List<int> haystack, List<int> needle) {
    if (needle.isEmpty || haystack.length < needle.length) return -1;
    for (var i = 0; i <= haystack.length - needle.length; i++) {
      var matched = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
  }

  /// Releases the message stream. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _buffer.clear();
    await _messageController.close();
  }
}
