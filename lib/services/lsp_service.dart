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
    @visibleForTesting this._notificationSender,
  }) : _rootPath = workspaceRoot ?? Directory.current.path,
       _spec = spec ?? LspServerSpec.dart;

  static const Duration _initializeTimeout = Duration(seconds: 20);

  /// How long a `didChange` waits for more typing before it is written.
  ///
  /// Sending on every keystroke made the server re-analyze constantly; sending
  /// too late is worse, because a completion request for the newest text can
  /// then land on an older document (`-32004 invalid line number`). Every
  /// position-based request therefore flushes the pending change first — see
  /// [_ensureSynced].
  static const Duration _didChangeDebounce = Duration(milliseconds: 250);

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

  /// URI of the document the editor is looking at, if one has been opened.
  ///
  /// The map above deliberately keeps each document's own list; the UI must
  /// never be shown the union of every document the server ever published for.
  String? _activeUri;

  /// Trigger characters advertised by the server's `completionProvider` in the
  /// `initialize` response. Falls back to the LSP convention (`['.']`) when the
  /// server sent none.
  List<String> _triggerCharacters = const ['.'];

  /// The characters that must open completion immediately when typed.
  List<String> get triggerCharacters => _triggerCharacters;

  /// Whether the server advertised `completionProvider.resolveProvider`.
  ///
  /// Only then may `completionItem/resolve` be sent; the Dart server uses it
  /// to attach the automatic import and the full dartdoc to an item.
  bool _completionResolveProvider = false;

  /// Whether `completionItem/resolve` is supported by the connected server.
  bool get supportsCompletionResolve => _completionResolveProvider;

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

  /// Test seam: receives notifications (didOpen/didChange/…) instead of the
  /// JSON-RPC client, so the order between a flushed change and a request can
  /// be asserted without spawning a server.
  final void Function(String method, Map<String, dynamic> params)?
  _notificationSender;

  /// Content waiting for the debounce timer, per document URI.
  final Map<String, String> _pendingContents = {};

  /// The debounce timer of each document URI.
  final Map<String, Timer> _didChangeTimers = {};

  /// Context of every in-flight request, so a failed answer can name the
  /// method and position it was for.
  final Map<int, ({String method, Map<String, dynamic>? params})>
  _requestContexts = {};

  /// `-32004` failures already printed, keyed by method + URI: one line per
  /// method and document, not one per keystroke.
  final Set<String> _reportedInvalidPositions = {};

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

  /// Parses `capabilities.completionProvider.triggerCharacters` from the
  /// `initialize` response, defaulting to `['.']`.
  @visibleForTesting
  static List<String> parseTriggerCharacters(Map<String, dynamic>? response) {
    if (response == null) return const ['.'];
    final completion = _completionProvider(response);
    if (completion == null) return const ['.'];
    final chars = completion['triggerCharacters'] as List<dynamic>?;
    if (chars == null || chars.isEmpty) return const ['.'];
    return chars.whereType<String>().toList();
  }

  /// Parses `capabilities.completionProvider.resolveProvider` from the
  /// `initialize` response. Absent means "not supported" per the LSP spec.
  @visibleForTesting
  static bool parseCompletionResolveProvider(Map<String, dynamic>? response) {
    final completion = _completionProvider(response);
    return completion?['resolveProvider'] == true;
  }

  static Map<String, dynamic>? _completionProvider(
    Map<String, dynamic>? response,
  ) {
    if (response == null) return null;
    final caps = response['capabilities'] as Map<String, dynamic>?;
    if (caps == null) return null;
    return caps['completionProvider'] as Map<String, dynamic>?;
  }

  /// Reads an LSP `documentation` value: either a plain string or a
  /// `MarkupContent` object (`{"kind": "markdown", "value": "..."}`).
  @visibleForTesting
  static String? parseDocumentation(dynamic value) {
    if (value is String) return value;
    if (value is Map) {
      final text = value['value'];
      if (text is String) return text;
    }
    return null;
  }

  /// Parses an LSP `TextEdit[]` (`additionalTextEdits`) into model objects.
  @visibleForTesting
  static List<CompletionTextEdit> parseTextEdits(dynamic value) {
    if (value is! List) return const [];
    final edits = <CompletionTextEdit>[];
    for (final raw in value) {
      if (raw is! Map) continue;
      final range = raw['range'];
      final newText = raw['newText'];
      if (range is! Map || newText is! String) continue;
      final start = range['start'];
      final end = range['end'];
      if (start is! Map || end is! Map) continue;
      final startLine = start['line'];
      final startCharacter = start['character'];
      final endLine = end['line'];
      final endCharacter = end['character'];
      if (startLine is! int ||
          startCharacter is! int ||
          endLine is! int ||
          endCharacter is! int) {
        continue;
      }
      edits.add(
        CompletionTextEdit(
          startLine: startLine,
          startCharacter: startCharacter,
          endLine: endLine,
          endCharacter: endCharacter,
          newText: newText,
        ),
      );
    }
    return edits;
  }

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
      return _spec.detail ??
          'No language server for this file — the built-in analyzer is used.';
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

  /// Path of the document the editor last opened on this server, or `null` when
  /// this server does not currently serve a document.
  ///
  /// The UI treats a connected server as authoritative **only** for this
  /// document; without it there is nothing to show (and the one-shot analyzer
  /// is the only fallback).
  String? get activeDocumentPath {
    final uri = _activeUri;
    return uri == null ? null : _uriToPath(uri);
  }

  /// Diagnostics published for [activeDocumentPath] only.
  ///
  /// An empty list is a real answer ("no problems"), not "nothing was
  /// published", so callers must not replace it with another source.
  List<Diagnostic> get activeDiagnostics {
    final uri = _activeUri;
    return uri == null
        ? const <Diagnostic>[]
        : (_diagnosticsByUri[uri] ?? const <Diagnostic>[]);
  }

  /// Error count of [activeDiagnostics].
  int get activeErrorCount =>
      activeDiagnostics.where((d) => d.severity == 'error').length;

  /// Warning count of [activeDiagnostics].
  int get activeWarningCount =>
      activeDiagnostics.where((d) => d.severity == 'warning').length;

  /// Total error count across all open documents (original behavior preserved).
  int get errorCount => diagnostics.where((d) => d.severity == 'error').length;

  /// Total warning count across all open documents (original behavior preserved).
  int get warningCount => diagnostics.where((d) => d.severity == 'warning').length;

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
        'workspace': <String, dynamic>{
          // Required by the Dart server before it includes completions from
          // libraries that are not imported yet (it needs to be able to ask
          // the client to add the import).
          'applyEdit': true,
          'configuration': true,
          'workspaceFolders': true,
        },
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

    _triggerCharacters = parseTriggerCharacters(response);
    _completionResolveProvider = parseCompletionResolveProvider(response);

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
    _activeUri = uri;

    _sendNotification('textDocument/didOpen', <String, dynamic>{
      'textDocument': <String, dynamic>{
        'uri': uri,
        'languageId': languageId,
        'version': 1,
        'text': content,
      },
    });

    // The panel and the status bar follow the active document: announce it even
    // when no diagnostic has arrived yet, so the old document's list (or the
    // analyzer fallback) cannot stay on screen.
    _safeNotify();
  }

  void updateFile(String filePath, String content) {
    if (_disposed || !isConnected) return;

    final uri = _pathToUri(filePath);

    if (!_documentVersions.containsKey(uri)) {
      unawaited(openFile(filePath, content));
      return;
    }

    final becameActive = _activeUri != uri;
    if (_documentContents[uri] == content &&
        !_pendingContents.containsKey(uri)) {
      if (becameActive) {
        _activeUri = uri;
        _safeNotify();
      }
      return;
    }

    _activeUri = uri;

    // Debounced: typing sends one change instead of one per keystroke. A
    // position-based request flushes it first through [_ensureSynced], so the
    // server never answers for text it has not seen.
    _didChangeTimers.remove(uri)?.cancel();
    _pendingContents[uri] = content;
    _didChangeTimers[uri] = Timer(_didChangeDebounce, () {
      unawaited(_flushPendingChange(uri));
    });

    if (becameActive) _safeNotify();
  }

  /// Sends the debounced `didChange` for [filePath] right away.
  ///
  /// Used by Run/Save in the shell, which must not operate on a document the
  /// server has not received yet.
  Future<void> flushPendingChange(String filePath) =>
      _flushPendingChange(_pathToUri(filePath));

  /// The one sync helper: writes whatever `didChange` the debounce still holds
  /// for [uri] and completes after the notification has been sent.
  ///
  /// Every request that carries a position (completion, resolve, hover) calls
  /// this first. Without it the server can be one edit behind, which surfaces
  /// as `[LSP] request failed: code -32004, invalid line number` or as
  /// completion for a symbol the user has already finished typing.
  Future<void> _ensureSynced(String uri) => _flushPendingChange(uri);

  Future<void> _flushPendingChange(String uri) {
    _didChangeTimers.remove(uri)?.cancel();
    final content = _pendingContents.remove(uri);
    if (content == null) return Future<void>.value();
    if (_disposed || !isConnected) return Future<void>.value();
    if (_documentContents[uri] == content) return Future<void>.value();

    final version = (_documentVersions[uri] ?? 1) + 1;
    _documentVersions[uri] = version;
    _documentContents[uri] = content;

    _sendNotification('textDocument/didChange', <String, dynamic>{
      'textDocument': <String, dynamic>{'uri': uri, 'version': version},
      'contentChanges': <Map<String, dynamic>>[
        <String, dynamic>{'text': content},
      ],
    });
    return Future<void>.value();
  }

  /// The version of the document at [filePath] as the server last received it,
  /// or `null` when it is not open.
  int? documentVersion(String filePath) =>
      _documentVersions[_pathToUri(filePath)];

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

    // A change still waiting in the debounce belongs to a document the server
    // is about to forget.
    _didChangeTimers.remove(uri)?.cancel();
    _pendingContents.remove(uri);

    if (wasOpen && isConnected) {
      _sendNotification('textDocument/didClose', <String, dynamic>{
        'textDocument': <String, dynamic>{'uri': uri},
      });
    }

    _documentVersions.remove(uri);
    _documentContents.remove(uri);

    final wasActive = _activeUri == uri;
    if (wasActive) _activeUri = null;

    // Only notify when something actually went away, so listeners are not
    // rebuilt on every tab switch that had no diagnostics.
    final removed = _diagnosticsByUri.remove(uri) != null;
    if (removed || wasActive) {
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

  /// Test seam: pretends the `initialize` response advertised
  /// `completionProvider.resolveProvider`, which is skipped in tests because
  /// `startServer` short-circuits under `FLUTTER_TEST`.
  @visibleForTesting
  void debugSetCompletionResolveProvider(bool value) {
    _completionResolveProvider = value;
  }

  /// Requests completion items from the LSP server at [filePath], [line], [column].
  ///
  /// A completely empty result is retried once after a short delay: the first
  /// request after `initialized` usually arrives while a server (clangd,
  /// pyright) is still indexing, and users read that as "completion is broken".
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column, {
    int? triggerKind,
    String? triggerCharacter,
  }) async {
    if (!isConnected) return const [];
    final uri = _pathToUri(filePath);
    await _ensureSynced(uri);

    final params = <String, dynamic>{
      'textDocument': <String, dynamic>{'uri': uri},
      'position': <String, dynamic>{
        'line': line - 1, // LSP is 0-based
        'character': column - 1,
      },
    };

    if (triggerKind != null || triggerCharacter != null) {
      final context = <String, dynamic>{};
      if (triggerKind != null) context['triggerKind'] = triggerKind;
      if (triggerCharacter != null) {
        context['triggerCharacter'] = triggerCharacter;
      }
      params['context'] = context;
    }

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
      final insertTextFormat = item['insertTextFormat'] as int?;
      final filterText = item['filterText'] as String?;
      final sortText = item['sortText'] as String?;

      String? textEditNewText;
      final textEdit = item['textEdit'];
      if (textEdit is Map<String, dynamic>) {
        textEditNewText = textEdit['newText'] as String?;
      }

      result.add(
        CompletionItem(
          label: rawLabel,
          kind: kind,
          kindInt: kindInt,
          detail: detail,
          insertText: insertText,
          textEditNewText: textEditNewText,
          filterText: filterText,
          insertTextFormat: insertTextFormat,
          sortText: sortText,
          documentation: parseDocumentation(item['documentation']),
          additionalTextEdits: parseTextEdits(item['additionalTextEdits']),
          raw: item,
        ),
      );
      _logProbedItem(rawLabel, item);
    }
    return result;
  }

  /// Labels whose raw completion payload is printed once, to document what the
  /// server really sends for the two items users report paren problems with.
  static const Set<String> _probeLogLabels = {'print', 'setState'};
  final Set<String> _loggedProbeItems = {};

  /// One `debugPrint` per probed label and session: kind, insert text/format
  /// and detail exactly as the server sent them.
  void _logProbedItem(String label, Map<String, dynamic> raw) {
    if (!_probeLogLabels.contains(label)) return;
    if (!_loggedProbeItems.add(label)) return;
    debugPrint(
      '[LSP] completion "$label": kind=${raw['kind']} '
      'insertText=${jsonEncode(raw['insertText'])} '
      'insertTextFormat=${raw['insertTextFormat']} '
      'textEdit=${jsonEncode(raw['textEdit'])} '
      'detail=${jsonEncode(raw['detail'])}',
    );
  }

  /// Asks the server to complete [item] (`completionItem/resolve`).
  ///
  /// Only sent when the server advertised `completionProvider.resolveProvider`;
  /// returns `null` otherwise (and when the server has no `raw` JSON to send
  /// back). The Dart server attaches the automatic import
  /// (`additionalTextEdits`) and the full dartdoc here.
  Future<ResolvedCompletionItem?> resolveCompletionItem(
    CompletionItem item, {
    String? filePath,
  }) async {
    if (!isConnected || !_completionResolveProvider) return null;
    final raw = item.raw;
    if (raw == null) return null;

    // The import the server attaches is only valid for the document text it
    // resolved against, so flush any pending change first and remember which
    // version that was.
    final uri = filePath == null ? null : _pathToUri(filePath);
    if (uri != null) await _ensureSynced(uri);
    final version = uri == null ? null : _documentVersions[uri];

    final response = await _request(
      'completionItem/resolve',
      Map<String, dynamic>.from(raw),
    );
    if (response == null) return null;

    return ResolvedCompletionItem(
      documentation: parseDocumentation(response['documentation']),
      detail: response['detail'] as String?,
      additionalTextEdits: parseTextEdits(response['additionalTextEdits']),
      documentVersion: version,
    );
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
        return 'snippet';
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
    await _ensureSynced(uri);

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

    for (final timer in _didChangeTimers.values) {
      timer.cancel();
    }
    _didChangeTimers.clear();
    _pendingContents.clear();
    _requestContexts.clear();
    _reportedInvalidPositions.clear();

    _documentVersions.clear();
    _documentContents.clear();
    _diagnosticsByUri.clear();
    _activeUri = null;
    _workspaceFolders.clear();
    _triggerCharacters = const ['.'];
    _completionResolveProvider = false;

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
    _requestContexts[id] = (method: method, params: params);

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
        _requestContexts.remove(id);
        return null;
      },
    );
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    final message = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    };
    final sender = _notificationSender;
    if (sender != null) {
      sender(method, params);
      return;
    }
    _rpc?.send(message);
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
      if (method == 'workspace/configuration') {
        _sendConfiguration(message, id);
        return;
      }
      final result = method == 'workspace/applyEdit' ? applyEditResult() : null;
      _rpc?.send(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      });
    }
  }

  /// The `ApplyWorkspaceEditResult` sent back for a server-initiated
  /// `workspace/applyEdit` request.
  ///
  /// The client advertises `workspace.applyEdit` because the Dart server only
  /// offers completions from unimported libraries when that capability is
  /// present, but it never applies workspace edits itself: accepting a
  /// completion applies the item's `additionalTextEdits` directly in the
  /// editor. The LSP spec requires a result object (not `null`), so the
  /// request is declined explicitly instead of silently ignored.
  @visibleForTesting
  static Map<String, dynamic> applyEditResult() => <String, dynamic>{
    'applied': false,
    'failureReason': 'not supported by this client',
  };

  /// Answers a server-initiated `workspace/configuration` request.
  ///
  /// The Dart server reads `dart.enableSnippets` this way; the probe in
  /// `tool/probe_dart_completion_options.dart` confirmed it is honoured.
  /// Everything else is left out of the answer so the server keeps its own
  /// defaults (`completeFunctionCalls` stays at its default, on purpose).
  void _sendConfiguration(Map<String, dynamic> message, Object id) {
    final params = message['params'];
    final rawItems = params is Map ? params['items'] : null;
    final items = rawItems is List ? rawItems : const <dynamic>[];

    final dartSettings = <String, dynamic>{};
    if (_spec.id == 'dart') {
      dartSettings['enableSnippets'] = true;
    }

    _rpc?.send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <dynamic>[
        for (var i = 0; i < items.length; i++)
          <String, dynamic>{...dartSettings},
      ],
    });
  }

  void _handleResponse(Map<String, dynamic> message) {
    final id = message['id'];
    if (id is! int) return;

    final completer = _pendingRequests.remove(id);
    final context = _requestContexts.remove(id);
    if (completer == null || completer.isCompleted) return;

    final error = message['error'];
    if (error != null) {
      _reportRequestError(id, context, error);
      completer.complete(null);
      return;
    }

    final result = message['result'];
    completer.complete(result is Map<String, dynamic> ? result : null);
  }

  /// Logs a failed request, naming the method, position and document version
  /// when the server says the position was invalid (`-32004`).
  ///
  /// The pair method + document is only reported once: a document that is out
  /// of sync fails on every keystroke, and a wall of identical lines hides the
  /// first one.
  void _reportRequestError(
    int id,
    ({String method, Map<String, dynamic>? params})? context,
    Object error,
  ) {
    final method = context?.method ?? 'request $id';
    final params = context?.params;
    final position = params?['position'];
    final uri = (params?['textDocument'] as Map?)?['uri'];

    int? code;
    String? errorMessage;
    if (error is Map) {
      final rawCode = error['code'];
      if (rawCode is int) code = rawCode;
      errorMessage = error['message'] as String?;
    }

    if (code == -32004) {
      final key = '$method|$uri';
      if (_reportedInvalidPositions.add(key)) {
        final line = position?['line'];
        final character = position?['character'];
        final version = uri is String ? _documentVersions[uri] : null;
        debugPrint(
          '[LSP] $method failed with -32004 (invalid position) at '
          'line=$line character=$character documentVersion=$version'
          '${errorMessage == null ? '' : ' — $errorMessage'}',
        );
      }
      return;
    }

    debugPrint('[LSP] Request $id failed: $error');
  }

  void _handlePublishDiagnostics(Map<String, dynamic> params) {
    final uri = params['uri'] as String?;
    if (uri == null) return;

    // Only a document this client has open can be displayed or counted. A
    // publish that arrives after `didClose` (clangd and pyright answer
    // asynchronously) must not re-create the entry nobody is looking at, and a
    // file the server analyzed on its own is not the active document.
    final currentVersion = _documentVersions[uri];
    if (currentVersion == null) return;

    // Out-of-order answers: a list computed for older text must not replace the
    // one for the text the server already has. Servers may omit `version`
    // (the Dart language server does), in which case there is nothing to compare.
    final version = params['version'];
    if (version is int && version < currentVersion) return;

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

  /// Test seam: delivers a raw `textDocument/publishDiagnostics` payload exactly
  /// as a server would, so the document/version filters can be verified without
  /// spawning a process.
  @visibleForTesting
  void debugPublishDiagnostics(Map<String, dynamic> params) =>
      _handlePublishDiagnostics(params);

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
