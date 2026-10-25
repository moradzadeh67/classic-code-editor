import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/diagnostic.dart';
import '../models/language_config.dart';
import '../models/lsp_models.dart';
import '../utils/json_rpc_client.dart';
import 'lsp_server_spec.dart';

/// Connection state of the Dart Language Server process.
enum LspConnectionStatus { stopped, starting, connected, error }

/// Manages a connection to a language server over stdio using the Language
/// Server Protocol.
///
/// Which server is launched (and with which arguments) comes from an
/// [LspServerSpec]; selection per file lives in `LspServerManager`. This class
/// only knows how to talk LSP.
///
/// Responsibilities:
/// * spawn and tear down the language server process,
/// * perform the LSP `initialize` handshake,
/// * keep the server in sync with open documents (`didOpen` / `didChange`),
/// * surface real-time diagnostics published by the server,
/// * request code completion and hover documentation.
class LspService extends ChangeNotifier {
  LspService({
    String? workspaceRoot,
    LspServerSpec? spec,
    this._prepareWorkspace,
    @visibleForTesting this._requestSender,
  }) : _rootPath = workspaceRoot ?? Directory.current.path,
       _spec = spec ?? LspServerSpec.dart;

  static const Duration _initializeTimeout = Duration(seconds: 20);

  /// One retry, because the first completion after `initialized` often lands
  /// while the server is still indexing and comes back empty.
  static const Duration _warmupRetryDelay = Duration(milliseconds: 200);

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
  final LspServerSpec _spec;
  final Future<void> Function()? _prepareWorkspace;
  final Future<Map<String, dynamic>?> Function(
    String method,
    Map<String, dynamic>? params,
  )?
  _requestSender;

  /// In-flight startup, so `openFile` can wait instead of racing the handshake.
  Future<void>? _startTask;

  /// The server this instance was configured for.
  LspServerSpec get spec => _spec;

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
    // No server applies to this file (Assembly, unknown extension).
    if (_spec.languageIds.isEmpty) return 'LSP: Off';
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

  /// Longer explanation for a tooltip: which server, and why it is not running.
  String get statusDetail {
    final name = _spec.displayName;
    if (_spec.languageIds.isEmpty) {
      return 'No language server for this file — the built-in analyzer is used.';
    }
    final error = _lastError;
    switch (_status) {
      case LspConnectionStatus.stopped:
        return '$name language server is stopped.';
      case LspConnectionStatus.starting:
        return 'Starting the $name language server…';
      case LspConnectionStatus.connected:
        return '$name language server: connected.';
      case LspConnectionStatus.error:
        return error == null || error.isEmpty
            ? '$name language server: error.'
            : '$name language server: $error';
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

  /// Starts the configured language server and performs the LSP handshake.
  ///
  /// Safe to call repeatedly: concurrent callers share one startup future, and
  /// a failed start clears it so a later attempt can retry.
  Future<void> startServer() {
    if (_disposed || _spec.languageIds.isEmpty) return Future<void>.value();
    return _startTask ??= _startServer().whenComplete(() => _startTask = null);
  }

  Future<void> _startServer() async {
    if (_disposed) return;
    if (_process != null || _status == LspConnectionStatus.starting) return;

    _status = LspConnectionStatus.starting;
    _lastError = null;
    _safeNotify();

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _status = LspConnectionStatus.connected;
      _safeNotify();
      return;
    }

    try {
      final executable = await _resolveExecutable();
      // clangd cannot see the SDK headers without compile_flags.txt, and it
      // indexes on initialize, so the file has to exist before the handshake.
      try {
        await _prepareWorkspace?.call();
      } catch (e) {
        debugPrint('LspService workspace preparation failed: $e');
      }

      final process = await Process.start(
        executable,
        _spec.arguments,
        workingDirectory: _rootPath,
      );
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
              debugPrint('[LSP ${_spec.id}] $line');
            }
          });

      _messageSubscription = rpc.messages.listen(_handleMessage);

      await _initialize();
    } catch (e) {
      _lastError = e.toString();
      _status = LspConnectionStatus.error;
      debugPrint('LspService (${_spec.id}) failed to start: $e');
      _safeNotify();
    }
  }

  Future<void> _initialize() async {
    final rootUri = _rootUri;

    final params = <String, dynamic>{
      'processId': pid,
      'clientInfo': <String, dynamic>{
        'name': LspServerSpec.clientId,
        'version': LspServerSpec.clientVersion,
      },
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
      'initializationOptions': _spec.initializationOptions,
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

    // Stop/Dispose may have run while we were waiting for the handshake.
    if (_disposed || _rpc == null) return;

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

    // Same resolver as the editor: an unsaved buffer is identified by its
    // content, not only by a path it may not have yet.
    final languageId = LanguageConfig.fromPathOrContent(
      filePath,
      content,
    ).highlightLanguage;

    _documentVersions[uri] = 1;
    _documentContents[uri] = content;

    _sendNotification('textDocument/didOpen', <String, dynamic>{
      'textDocument': <String, dynamic>{
        'uri': uri,
        'languageId': languageId,
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

  /// Tells the server the document is closed and forgets everything we knew
  /// about it (tracked version, cached content, published diagnostics).
  ///
  /// Without this the server keeps publishing diagnostics for a file the user
  /// closed, and since [errorCount] / [warningCount] aggregate every known
  /// URI, the status bar kept reporting problems from files nobody is looking
  /// at any more.
  void closeDocument(String filePath) {
    if (_disposed) return;

    final uri = _pathToUri(filePath);
    final wasOpen = _documentVersions.containsKey(uri);

    if (wasOpen && isConnected) {
      _sendNotification('textDocument/didClose', <String, dynamic>{
        'textDocument': <String, dynamic>{'uri': uri},
      });
    }

    _documentVersions.remove(uri);
    _documentContents.remove(uri);

    // Only notify when something actually went away, so listeners are not
    // rebuilt on every tab switch that had no diagnostics.
    if (_diagnosticsByUri.remove(uri) != null) {
      notifyListeners();
    }
  }

  /// Test seam: injects diagnostics exactly as the server would publish them,
  /// so the aggregation/close lifecycle can be verified without spawning
  /// `dart language-server`.
  @visibleForTesting
  void debugSetDiagnosticsFor(String filePath, List<Diagnostic> diagnostics) {
    _diagnosticsByUri[_pathToUri(filePath)] = diagnostics;
    notifyListeners();
  }

  /// Requests completion items from the LSP server at [filePath], [line], [column].
  ///
  /// A completely empty result is retried once after a short delay: the first
  /// request after `initialized` usually arrives while a server (clangd,
  /// pyright) is still indexing, and users read that as "completion is broken".
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column,
  ) async {
    if (!isConnected) return const [];
    final uri = _pathToUri(filePath);

    final params = <String, dynamic>{
      'textDocument': <String, dynamic>{'uri': uri},
      'position': <String, dynamic>{
        'line': line - 1, // LSP is 0-based
        'character': column - 1,
      },
    };

    var items = await _completionAt(params);

    if (items.isEmpty) {
      await Future<void>.delayed(_warmupRetryDelay);
      if (!isConnected) return const [];
      items = await _completionAt(params);
    }

    return items;
  }

  Future<List<CompletionItem>> _completionAt(
    Map<String, dynamic> params,
  ) async {
    final response = await _request('textDocument/completion', params);

    if (response == null) return const [];

    final items = response['items'] as List<dynamic>?;

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

    final response = await _request('textDocument/hover', <String, dynamic>{
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

  Future<Map<String, dynamic>?> _request(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final sender = _requestSender;
    if (sender != null) return sender(method, params);
    return _sendRequest(method, params);
  }

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

  Future<String> _resolveExecutable() async {
    // Absolute candidates first: a bundled .app starts with launchd's minimal
    // PATH, so `which` alone misses /opt/homebrew/bin.
    for (final candidate in _spec.executableNames) {
      if (!candidate.contains('/')) continue;
      final expanded = _expandHome(candidate);
      if (File(expanded).existsSync()) return expanded;
    }

    for (final candidate in _spec.executableNames) {
      if (candidate.contains('/')) continue;
      for (final directory in _searchDirectories()) {
        final path = '$directory/$candidate';
        if (File(path).existsSync()) return path;
      }
      try {
        final which = await Process.run('/usr/bin/which', <String>[candidate]);
        if (which.exitCode == 0) {
          final path = (which.stdout as String).trim();
          if (path.isNotEmpty) return path;
        }
      } catch (e) {
        debugPrint('Unable to resolve $candidate: $e');
      }
    }

    // Fall back to the bare name so Process.start reports a clear error.
    final names = _spec.executableNames;
    return names.isEmpty ? _spec.id : names.last;
  }

  List<String> _searchDirectories() {
    final home = Platform.environment['HOME'];
    return <String>[
      '/usr/bin',
      '/usr/local/bin',
      '/opt/homebrew/bin',
      '/opt/local/bin',
      if (home != null && home.isNotEmpty) ...<String>[
        '$home/.local/bin',
        '$home/.npm-global/bin',
        '$home/Library/Python/3.14/bin',
        '$home/Library/Python/3.13/bin',
        '$home/Library/Python/3.12/bin',
      ],
    ];
  }

  String _expandHome(String path) {
    if (!path.startsWith('~/')) return path;
    final home = Platform.environment['HOME'];
    return home == null ? path : '$home${path.substring(1)}';
  }

  String? get _rootUri {
    final path = _rootPath;
    if (path == null || path.isEmpty) return null;
    return Uri.directory(path).toString();
  }

  String _pathToUri(String filePath) {
    if (filePath.startsWith('file://')) return filePath;
    if (!filePath.startsWith('/')) {
      final absolute = File(filePath).absolute.path;
      return Uri.file(absolute).toString();
    }
    return Uri.file(filePath).toString();
  }

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
