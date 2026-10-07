import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/diagnostic.dart';
import '../models/lsp_models.dart';
import '../utils/json_rpc_client.dart';

/// Connection state of the Dart Language Server process.
enum LspConnectionStatus { stopped, starting, connected, error }

/// Manages a connection to the official Dart Language Server
/// (`dart language-server`) over stdio using the Language Server Protocol.
///
/// Responsibilities:
/// * spawn and tear down the language server process,
/// * perform the LSP `initialize` handshake,
/// * keep the server in sync with open documents (`didOpen` / `didChange`),
/// * surface real-time diagnostics published by the server,
/// * request code completion and hover documentation.
class LspService extends ChangeNotifier {
  LspService({String? workspaceRoot})
    : _rootPath = workspaceRoot ?? Directory.current.path;

  static const Duration _initializeTimeout = Duration(seconds: 20);

  Process? _process;
  JsonRpcClient? _rpc;
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;

  int _nextRequestId = 1;
  final Map<int, Completer<Map<String, dynamic>?>> _pendingRequests = {};

  /// URIs of documents registered with the server, mapped to their version.
  final Map<String, int> _documentVersions = {};

  /// Last content sent to the server for each document URI.
  final Map<String, String> _documentContents = {};

  /// Diagnostics reported by the server, keyed by document URI.
  final Map<String, List<Diagnostic>> _diagnosticsByUri = {};

  /// Workspace folder URIs already registered with the server.
  final Set<String> _workspaceFolders = <String>{};

  final String? _rootPath;

  LspConnectionStatus _status = LspConnectionStatus.stopped;
  String? _lastError;
  bool _disposed = false;

  /// Current connection state of the language server.
  LspConnectionStatus get status => _status;

  /// Whether the server has completed the `initialize` handshake.
  bool get isConnected => _status == LspConnectionStatus.connected;

  /// Whether the server is in the middle of starting up.
  bool get isStarting => _status == LspConnectionStatus.starting;

  /// The last error encountered while talking to the server, if any.
  String? get lastError => _lastError;

  /// A short human-readable label suitable for the status bar.
  String get statusLabel {
    switch (_status) {
      case LspConnectionStatus.stopped:
        return 'LSP: Stopped';
      case LspConnectionStatus.starting:
        return 'LSP: Starting...';
      case LspConnectionStatus.connected:
        return 'LSP: Connected';
      case LspConnectionStatus.error:
        return 'LSP: Error';
    }
  }

  /// All diagnostics currently reported by the server, flattened across files.
  List<Diagnostic> get diagnostics {
    final all = <Diagnostic>[];
    for (final list in _diagnosticsByUri.values) {
      all.addAll(list);
    }
    return all;
  }

  /// Diagnostics reported for a specific [filePath].
  List<Diagnostic> diagnosticsFor(String filePath) {
    return _diagnosticsByUri[_pathToUri(filePath)] ?? const <Diagnostic>[];
  }

  int get errorCount => diagnostics.where((d) => d.severity == 'error').length;

  int get warningCount =>
      diagnostics.where((d) => d.severity == 'warning').length;

  /// Starts the Dart Language Server and performs the LSP handshake.
  Future<void> startServer() async {
    if (_disposed) return;
    if (_process != null || _status == LspConnectionStatus.starting) return;

    _status = LspConnectionStatus.starting;
    _lastError = null;
    _safeNotify();

    try {
      final dartExecutable = await _resolveDartExecutable();
      final process = await Process.start(dartExecutable, <String>[
        'language-server',
        '--client-id=RetroDart',
        '--client-version=1.0.0',
      ], workingDirectory: _rootPath);
      _process = process;

      final rpc = JsonRpcClient(process.stdin);
      _rpc = rpc;

      _stdoutSubscription = process.stdout.listen(
        rpc.feed,
        onError: _handleProcessError,
        onDone: _handleProcessDone,
      );

      _stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.trim().isNotEmpty) {
              debugPrint('[LSP] $line');
            }
          });

      _messageSubscription = rpc.messages.listen(_handleMessage);

      await _initialize();
    } catch (e) {
      _lastError = e.toString();
      _status = LspConnectionStatus.error;
      debugPrint('LspService failed to start: $e');
      _safeNotify();
    }
  }

  Future<void> _initialize() async {
    final rootUri = _rootUri;

    final params = <String, dynamic>{
      'processId': pid,
      'clientInfo': <String, dynamic>{'name': 'RetroDart', 'version': '1.0.0'},
      'rootUri': rootUri,
      'capabilities': <String, dynamic>{
        'textDocument': <String, dynamic>{
          'synchronization': <String, dynamic>{
            'dynamicRegistration': false,
            'willSave': false,
            'willSaveWaitUntil': false,
            'didSave': false,
          },
          'publishDiagnostics': <String, dynamic>{'relatedInformation': false},
          'completion': <String, dynamic>{
            'completionItem': <String, dynamic>{'snippetSupport': true},
          },
          'hover': <String, dynamic>{},
        },
        'workspace': <String, dynamic>{'workspaceFolders': true},
      },
      'initializationOptions': <String, dynamic>{},
    };

    if (rootUri != null) {
      params['workspaceFolders'] = <Map<String, dynamic>>[
        <String, dynamic>{'uri': rootUri, 'name': 'workspace'},
      ];
    }

    final response = await _sendRequest(
      'initialize',
      params,
    ).timeout(_initializeTimeout, onTimeout: () => null);

    if (response == null) {
      throw StateError('Language server did not respond to initialize');
    }

    _sendNotification('initialized', <String, dynamic>{});

    if (rootUri != null) _workspaceFolders.add(rootUri);

    _status = LspConnectionStatus.connected;
    _safeNotify();
  }

  void _ensureWorkspaceFolder(String filePath) {
    final directory = File(filePath).parent.path;
    if (directory.isEmpty) return;

    for (final folder in _workspaceFolders) {
      final folderPath = Uri.tryParse(folder)?.toFilePath();
      if (folderPath == null || folderPath.isEmpty) continue;
      final prefix = folderPath.endsWith('/') ? folderPath : '$folderPath/';
      if (directory == folderPath || directory.startsWith(prefix)) return;
    }

    final directoryUri = Uri.directory(directory).toString();
    _workspaceFolders.add(directoryUri);

    _sendNotification('workspace/didChangeWorkspaceFolders', <String, dynamic>{
      'event': <String, dynamic>{
        'added': <Map<String, dynamic>>[
          <String, dynamic>{
            'uri': directoryUri,
            'name': directory.split('/').last,
          },
        ],
        'removed': <Map<String, dynamic>>[],
      },
    });
  }

  Future<void> openFile(String filePath, String content) async {
    if (_disposed) return;
    if (!isConnected) {
      await startServer();
    }
    if (!isConnected) return;

    final uri = _pathToUri(filePath);

    if (_documentVersions.containsKey(uri)) {
      updateFile(filePath, content);
      return;
    }

    _ensureWorkspaceFolder(filePath);

    _documentVersions[uri] = 1;
    _documentContents[uri] = content;

    _sendNotification('textDocument/didOpen', <String, dynamic>{
      'textDocument': <String, dynamic>{
        'uri': uri,
        'languageId': 'dart',
        'version': 1,
        'text': content,
      },
    });
  }

  void updateFile(String filePath, String content) {
    if (_disposed || !isConnected) return;

    final uri = _pathToUri(filePath);

    if (!_documentVersions.containsKey(uri)) {
      unawaited(openFile(filePath, content));
      return;
    }

    if (_documentContents[uri] == content) return;

    final version = (_documentVersions[uri] ?? 1) + 1;
    _documentVersions[uri] = version;
    _documentContents[uri] = content;

    _sendNotification('textDocument/didChange', <String, dynamic>{
      'textDocument': <String, dynamic>{'uri': uri, 'version': version},
      'contentChanges': <Map<String, dynamic>>[
        <String, dynamic>{'text': content},
      ],
    });
  }

  /// Requests completion items from the LSP server at [filePath], [line], [column].
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column,
  ) async {
    if (!isConnected) return const [];
    final uri = _pathToUri(filePath);

    final response = await _sendRequest(
      'textDocument/completion',
      <String, dynamic>{
        'textDocument': <String, dynamic>{'uri': uri},
        'position': <String, dynamic>{
          'line': line - 1, // LSP is 0-based
          'character': column - 1,
        },
      },
    );

    if (response == null) return const [];

    List<dynamic>? items = response['items'] as List<dynamic>?;

    if (items == null) return const [];

    final result = <CompletionItem>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final rawLabel = item['label'] as String? ?? '';
      if (rawLabel.isEmpty) continue;

      final kindInt = item['kind'] as int? ?? 1;
      final kind = _completionKindToString(kindInt);
      final detail = item['detail'] as String?;
      final insertText = item['insertText'] as String?;
      final filterText = item['filterText'] as String?;

      String? textEditNewText;
      final textEdit = item['textEdit'];
      if (textEdit is Map<String, dynamic>) {
        textEditNewText = textEdit['newText'] as String?;
      }

      result.add(
        CompletionItem(
          label: rawLabel,
          kind: kind,
          detail: detail,
          insertText: insertText,
          textEditNewText: textEditNewText,
          filterText: filterText,
        ),
      );
    }
    return result;
  }

  String _completionKindToString(int kind) {
    switch (kind) {
      case 1:
      case 13:
      case 21:
        return 'text';
      case 2:
      case 3:
      case 4:
      case 5:
        return 'method';
      case 6:
      case 22:
        return 'function';
      case 7:
        return 'constructor';
      case 8:
      case 9:
      case 10:
        return 'field';
      case 11:
        return 'variable';
      case 12:
      case 23:
        return 'class';
      case 14:
      case 17:
      case 25:
        return 'interface';
      case 15:
        return 'module';
      case 16:
        return 'property';
      case 18:
        return 'unit';
      case 19:
      case 20:
        return 'value';
      case 24:
        return 'enum';
      default:
        return 'variable';
    }
  }

  /// Requests hover documentation from the LSP server at [filePath], [line], [column].
  Future<HoverInfo?> requestHover(String filePath, int line, int column) async {
    if (!isConnected) return null;
    final uri = _pathToUri(filePath);

    final response = await _sendRequest('textDocument/hover', <String, dynamic>{
      'textDocument': <String, dynamic>{'uri': uri},
      'position': <String, dynamic>{'line': line - 1, 'character': column - 1},
    });

    if (response == null) return null;

    final contents = response['contents'];
    String contentStr = '';

    if (contents is String) {
      contentStr = contents;
    } else if (contents is Map<String, dynamic>) {
      contentStr = contents['value'] as String? ?? '';
    } else if (contents is List) {
      for (final c in contents) {
        if (c is String) {
          contentStr += '$c\n';
        } else if (c is Map<String, dynamic>) {
          contentStr += '${c['value'] ?? ''}\n';
        }
      }
    }

    if (contentStr.trim().isEmpty) return null;
    return HoverInfo(content: contentStr.trim());
  }

  Future<void> stopServer() async {
    final rpc = _rpc;
    final process = _process;

    if (rpc != null && process != null) {
      try {
        await _sendRequest(
          'shutdown',
          <String, dynamic>{},
        ).timeout(const Duration(seconds: 2), onTimeout: () => null);
        rpc.send(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'exit',
          'params': <String, dynamic>{},
        });
      } catch (e) {
        debugPrint('LSP shutdown error: $e');
      }
    }

    _rpc = null;
    _process = null;

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;
    await _messageSubscription?.cancel();
    _messageSubscription = null;

    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pendingRequests.clear();

    await rpc?.dispose();

    process?.kill(ProcessSignal.sigkill);

    _documentVersions.clear();
    _documentContents.clear();
    _diagnosticsByUri.clear();
    _workspaceFolders.clear();

    _status = LspConnectionStatus.stopped;
    _safeNotify();
  }

  // ---------------------------------------------------------------------------
  // JSON-RPC plumbing
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _sendRequest(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final rpc = _rpc;
    if (rpc == null || _disposed) return Future<Map<String, dynamic>?>.value();

    final id = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>?>();
    _pendingRequests[id] = completer;

    final message = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
    };
    if (params != null) message['params'] = params;
    rpc.send(message);

    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _pendingRequests.remove(id);
        return null;
      },
    );
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    _rpc?.send(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  void _handleMessage(Map<String, dynamic> message) {
    final method = message['method'] as String?;

    if (method == null) {
      _handleResponse(message);
      return;
    }

    switch (method) {
      case 'textDocument/publishDiagnostics':
        final params = message['params'];
        if (params is Map<String, dynamic>) {
          _handlePublishDiagnostics(params);
        }
        return;
      case 'window/logMessage':
      case 'window/showMessage':
        return;
    }

    final id = message['id'];
    if (id != null) {
      final result = method == 'workspace/configuration' ? <dynamic>[] : null;
      _rpc?.send(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      });
    }
  }

  void _handleResponse(Map<String, dynamic> message) {
    final id = message['id'];
    if (id is! int) return;

    final completer = _pendingRequests.remove(id);
    if (completer == null || completer.isCompleted) return;

    final error = message['error'];
    if (error != null) {
      debugPrint('[LSP] Request $id failed: $error');
      completer.complete(null);
      return;
    }

    final result = message['result'];
    completer.complete(result is Map<String, dynamic> ? result : null);
  }

  void _handlePublishDiagnostics(Map<String, dynamic> params) {
    final uri = params['uri'] as String?;
    if (uri == null) return;

    final rawDiagnostics = params['diagnostics'];
    final parsed = <Diagnostic>[];

    if (rawDiagnostics is List) {
      for (final raw in rawDiagnostics) {
        if (raw is! Map<String, dynamic>) continue;
        final diagnostic = _parseDiagnostic(uri, raw);
        if (diagnostic != null) parsed.add(diagnostic);
      }
    }

    _diagnosticsByUri[uri] = parsed;
    _safeNotify();
  }

  Diagnostic? _parseDiagnostic(String uri, Map<String, dynamic> raw) {
    final range = raw['range'];
    if (range is! Map<String, dynamic>) return null;

    final start = range['start'];
    final line = start is Map<String, dynamic> && start['line'] is int
        ? start['line'] as int
        : 0;
    final character = start is Map<String, dynamic> && start['character'] is int
        ? start['character'] as int
        : 0;

    return Diagnostic(
      file: _uriToPath(uri),
      line: line + 1,
      column: character + 1,
      severity: _severityToString(raw['severity']),
      message: raw['message'] as String? ?? '',
      code: raw['code']?.toString() ?? '',
    );
  }

  String _severityToString(dynamic severity) {
    switch (severity) {
      case 1:
        return 'error';
      case 2:
        return 'warning';
      default:
        return 'info';
    }
  }

  void _handleProcessDone() {
    if (_status == LspConnectionStatus.stopped) return;
    _process = null;
    _status = LspConnectionStatus.stopped;
    _safeNotify();
  }

  void _handleProcessError(Object error) {
    _lastError = error.toString();
    _status = LspConnectionStatus.error;
    _safeNotify();
  }

  Future<String> _resolveDartExecutable() async {
    try {
      final which = await Process.run('which', <String>['dart']);
      if (which.exitCode == 0) {
        final path = (which.stdout as String).trim();
        if (path.isNotEmpty) return path;
      }
    } catch (e) {
      debugPrint('Unable to resolve the dart executable: $e');
    }
    return 'dart';
  }

  String? get _rootUri {
    final path = _rootPath;
    if (path == null || path.isEmpty) return null;
    return Uri.directory(path).toString();
  }

  String _pathToUri(String filePath) => Uri.file(filePath).toString();

  String _uriToPath(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed != null && parsed.scheme == 'file') {
      return parsed.toFilePath();
    }
    return uri;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(stopServer());
    super.dispose();
  }
}
