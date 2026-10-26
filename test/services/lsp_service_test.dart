import 'package:flutter_test/flutter_test.dart';

import 'package:classic_code_editor/models/diagnostic.dart';
import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/lsp_service.dart';

Diagnostic _diag(String file, String severity, {int line = 1}) => Diagnostic(
  file: file,
  line: line,
  column: 1,
  severity: severity,
  message: '$severity on line $line',
  code: 'test',
);

void main() {
  late LspService lsp;

  setUp(() {
    lsp = LspService(workspaceRoot: '/tmp/lsp_diagnostics_test');
  });

  tearDown(() {
    lsp.dispose();
  });

  group('LspService diagnostics aggregation', () {
    test('counts cover every document the server published for', () {
      lsp.debugSetDiagnosticsFor('/tmp/a.dart', [
        _diag('/tmp/a.dart', 'error'),
        _diag('/tmp/a.dart', 'warning'),
      ]);
      lsp.debugSetDiagnosticsFor('/tmp/b.dart', [
        _diag('/tmp/b.dart', 'error'),
      ]);

      expect(lsp.errorCount, 2);
      expect(lsp.warningCount, 1);
      expect(lsp.diagnostics, hasLength(3));
    });
  });

  group('LspService completion warm-up', () {
    test('retries an empty first completion once and returns the second list',
        () async {
      var calls = 0;
      final lsp = LspService(
        workspaceRoot: '/tmp/lsp_completion_test',
        requestSender: (method, params) async {
          calls++;
          if (calls == 1) {
            return <String, dynamic>{
              'isIncomplete': true,
              'items': <dynamic>[],
            };
          }
          return <String, dynamic>{
            'items': <dynamic>[
              <String, dynamic>{'label': 'printf', 'kind': 3},
            ],
          };
        },
      );
      addTearDown(lsp.dispose);

      await lsp.startServer();
      final items = await lsp.requestCompletion('/tmp/main.c', 1, 1);

      expect(calls, 2);
      expect(items.single.label, 'printf');
    });

    test('does not retry when the first answer has items', () async {
      var calls = 0;
      final lsp = LspService(
        workspaceRoot: '/tmp/lsp_completion_test',
        requestSender: (method, params) async {
          calls++;
          return <String, dynamic>{
            'items': <dynamic>[
              <String, dynamic>{'label': 'main', 'kind': 3},
            ],
          };
        },
      );
      addTearDown(lsp.dispose);

      await lsp.startServer();
      final items = await lsp.requestCompletion('/tmp/main.c', 1, 1);

      expect(calls, 1);
      expect(items.single.label, 'main');
    });

    test('gives up after one retry when the server keeps returning nothing',
        () async {
      var calls = 0;
      final lsp = LspService(
        workspaceRoot: '/tmp/lsp_completion_test',
        requestSender: (method, params) async {
          calls++;
          return <String, dynamic>{'items': <dynamic>[]};
        },
      );
      addTearDown(lsp.dispose);

      await lsp.startServer();
      final items = await lsp.requestCompletion('/tmp/main.c', 1, 1);

      expect(calls, 2);
      expect(items, isEmpty);
    });
  });

  group('LspService.closeDocument', () {
    test('drops that document diagnostics and keeps the others', () {
      lsp.debugSetDiagnosticsFor('/tmp/a.dart', [
        _diag('/tmp/a.dart', 'error'),
        _diag('/tmp/a.dart', 'error', line: 2),
      ]);
      lsp.debugSetDiagnosticsFor('/tmp/b.dart', [
        _diag('/tmp/b.dart', 'warning'),
      ]);

      lsp.closeDocument('/tmp/a.dart');

      expect(lsp.errorCount, 0, reason: 'closed file must stop counting');
      expect(lsp.warningCount, 1);
      expect(lsp.diagnosticsFor('/tmp/a.dart'), isEmpty);
      expect(lsp.diagnosticsFor('/tmp/b.dart'), hasLength(1));
    });

    test('notifies listeners so the status bar refreshes', () {
      lsp.debugSetDiagnosticsFor('/tmp/a.dart', [
        _diag('/tmp/a.dart', 'error'),
      ]);

      var notifications = 0;
      lsp.addListener(() => notifications++);

      lsp.closeDocument('/tmp/a.dart');

      expect(notifications, 1);
      expect(lsp.errorCount, 0);
    });

    test('stays silent when the file had no diagnostics', () {
      lsp.debugSetDiagnosticsFor('/tmp/a.dart', [
        _diag('/tmp/a.dart', 'error'),
      ]);

      var notifications = 0;
      lsp.addListener(() => notifications++);

      lsp.closeDocument('/tmp/never-opened.dart');

      expect(notifications, 0, reason: 'no rebuild for a no-op close');
      expect(lsp.errorCount, 1, reason: 'other files are untouched');
    });

    test('clears an empty diagnostic entry left by a clean analysis', () {
      lsp.debugSetDiagnosticsFor('/tmp/a.dart', []);
      expect(lsp.diagnosticsFor('/tmp/a.dart'), isEmpty);

      lsp.closeDocument('/tmp/a.dart');

      // The entry is gone, so a later clean publish cannot resurrect stale
      // bookkeeping for a document that is no longer open.
      expect(lsp.diagnostics, isEmpty);
    });

    test('does not throw for a file that was never opened', () {
      expect(() => lsp.closeDocument('/tmp/unknown.dart'), returnsNormally);
    });
  });

  group('LspService.active-diagnostics', () {
    test('a valid empty LSP list does not fall back to AnalyzerService', () {
      // Register a document at version 1 and let the server publish an empty
      // list. The new active-diagnostics read path must treat this as
      // authoritative ("no problems") instead of switching sources.
      final uri = 'file:///tmp/clean.dart';
      lsp.debugSetDiagnosticsFor('/tmp/clean.dart', []);

      // Simulate the server answering an open with an empty diagnostics list.
      lsp.debugPublishDiagnostics({'uri': uri, 'diagnostics': <dynamic>[], 'version': 1});

      // The LSP-published (empty) list is what the UI should show for this document.
      // Key assertion: activeDiagnostics returns the LSP-empty, NOT the analyzer results.
      expect(lsp.activeDiagnostics, isEmpty);
      expect(lsp.activeErrorCount, 0);
      expect(lsp.activeWarningCount, 0);
    });

    test('a stale-version publishDiagnostics is dropped', () {
      // Register a document, then advance its version to 2.
      lsp.debugSetDiagnosticsFor('/tmp/old.dart', []);
      lsp.updateFile('/tmp/old.dart', 'var y = 2;\n');

      // A late answer arrives for the OLD content (version 1). The document is
      // now at version 2, so the version-1 publish must be dropped.
      lsp.debugPublishDiagnostics({
        'uri': 'file:///tmp/old.dart',
        'diagnostics': [
          {'range': {'start': {'line': 0, 'character': 0}},
           'message': 'stale',
           'severity': 1},
        ],
        'version': 1,
      });

      // The stale publish must not surface as current diagnostics.
      expect(lsp.activeDiagnostics, isEmpty);
    });
  });

  group('LspService completion resolve', () {
    test('parses completionProvider.resolveProvider', () {
      expect(
        LspService.parseCompletionResolveProvider({
          'capabilities': {
            'completionProvider': {'resolveProvider': true},
          },
        }),
        isTrue,
      );
      expect(
        LspService.parseCompletionResolveProvider({
          'capabilities': {'completionProvider': <String, dynamic>{}},
        }),
        isFalse,
      );
      expect(LspService.parseCompletionResolveProvider(null), isFalse);
    });

    test('documentation can be a string or a MarkupContent value', () {
      expect(LspService.parseDocumentation('plain'), 'plain');
      expect(
        LspService.parseDocumentation({'kind': 'markdown', 'value': '# hi'}),
        '# hi',
      );
      expect(LspService.parseDocumentation(null), isNull);
    });

    test('resolve is not sent when the server does not support it', () async {
      var calls = 0;
      final service = LspService(
        workspaceRoot: '/tmp/lsp_resolve_test',
        requestSender: (method, params) async {
          calls++;
          return <String, dynamic>{};
        },
      );
      addTearDown(service.dispose);
      await service.startServer();

      final item = CompletionItem(
        label: 'Timer',
        kind: 'class',
        raw: <String, dynamic>{
          'label': 'Timer',
          'data': <String, dynamic>{'ref': 'dart:async;Timer'},
        },
      );

      expect(service.supportsCompletionResolve, isFalse);
      expect(await service.resolveCompletionItem(item), isNull);
      expect(calls, 0);
    });

    test('resolve sends the raw item back and parses docs + import edit',
        () async {
      String? seenMethod;
      Map<String, dynamic>? seenParams;

      final service = LspService(
        workspaceRoot: '/tmp/lsp_resolve_test',
        requestSender: (method, params) async {
          seenMethod = method;
          seenParams = params;
          return <String, dynamic>{
            'documentation': {
              'kind': 'markdown',
              'value': 'A countdown timer.\n\nUse **Timer**.',
            },
            'detail': "Auto import from 'dart:async'",
            'additionalTextEdits': [
              {
                'newText': "import 'dart:async';\n\n",
                'range': {
                  'start': {'line': 0, 'character': 0},
                  'end': {'line': 0, 'character': 0},
                },
              },
            ],
          };
        },
      );
      addTearDown(service.dispose);
      await service.startServer();
      service.debugSetCompletionResolveProvider(true);

      final raw = <String, dynamic>{
        'label': 'Timer',
        'kind': 7,
        'data': <String, dynamic>{'ref': 'dart:async;Timer'},
      };
      final resolved = await service.resolveCompletionItem(
        CompletionItem(label: 'Timer', kind: 'class', raw: raw),
      );

      expect(seenMethod, 'completionItem/resolve');
      expect(seenParams?['label'], 'Timer');
      expect(seenParams?['data'], raw['data']);

      expect(resolved, isNotNull);
      expect(resolved!.documentation, contains('A countdown timer.'));
      expect(resolved.detail, "Auto import from 'dart:async'");
      expect(resolved.additionalTextEdits, hasLength(1));
      final edit = resolved.additionalTextEdits.single;
      expect(edit.newText, "import 'dart:async';\n\n");
      expect(edit.startLine, 0);
      expect(edit.startCharacter, 0);
      expect(edit.endLine, 0);
      expect(edit.endCharacter, 0);
    });

    test('returns null when the server answer has no result', () async {
      final service = LspService(
        workspaceRoot: '/tmp/lsp_resolve_test',
        requestSender: (method, params) async => null,
      );
      addTearDown(service.dispose);
      await service.startServer();
      service.debugSetCompletionResolveProvider(true);

      final resolved = await service.resolveCompletionItem(
        CompletionItem(
          label: 'Timer',
          kind: 'class',
          raw: <String, dynamic>{'label': 'Timer'},
        ),
      );
      expect(resolved, isNull);
    });
  });

  group('LspService workspace/applyEdit answer', () {
    test('declines with a spec-shaped ApplyWorkspaceEditResult', () {
      // The client advertises `workspace.applyEdit` (the Dart server needs it
      // for unimported-library completions) but never applies the server's
      // edits, so the answer must be an explicit "not applied" result rather
      // than `null`.
      expect(LspService.applyEditResult(), <String, dynamic>{
        'applied': false,
        'failureReason': 'not supported by this client',
      });
    });
  });

  group('LspService document sync before position requests', () {
    test('a pending didChange is sent before completion', () async {
      final events = <String>[];
      final service = LspService(
        workspaceRoot: '/tmp/lsp_sync_test',
        notificationSender: (method, params) {
          if (!method.startsWith('textDocument/')) return;
          final version =
              (params['textDocument'] as Map?)?['version'];
          events.add('$method@$version');
        },
        requestSender: (method, params) async {
          events.add(method);
          return <String, dynamic>{
            'items': <dynamic>[
              <String, dynamic>{'label': 'Timer', 'kind': 7},
            ],
          };
        },
      );
      addTearDown(service.dispose);
      await service.startServer();
      await service.openFile('/tmp/lsp_sync_test/main.dart', 'void f() {}');

      // Typing is debounced, so this change is still pending.
      service.updateFile('/tmp/lsp_sync_test/main.dart', 'void f() { Tim }');

      final items = await service.requestCompletion(
        '/tmp/lsp_sync_test/main.dart',
        1,
        12,
      );

      expect(items, isNotEmpty);
      expect(
        events,
        <String>[
          'textDocument/didOpen@1',
          'textDocument/didChange@2',
          'textDocument/completion',
        ],
        reason: 'the server must see the newest text before being asked',
      );
    });

    test('a pending didChange is sent before completionItem/resolve', () async {
      final events = <String>[];
      final service = LspService(
        workspaceRoot: '/tmp/lsp_sync_test',
        notificationSender: (method, params) {
          if (!method.startsWith('textDocument/')) return;
          final version = (params['textDocument'] as Map?)?['version'];
          events.add('$method@$version');
        },
        requestSender: (method, params) async {
          events.add(method);
          return <String, dynamic>{
            'additionalTextEdits': <dynamic>[
              <String, dynamic>{
                'newText': "import 'dart:async';\n\n",
                'range': <String, dynamic>{
                  'start': <String, dynamic>{'line': 0, 'character': 0},
                  'end': <String, dynamic>{'line': 0, 'character': 0},
                },
              },
            ],
          };
        },
      );
      addTearDown(service.dispose);
      await service.startServer();
      await service.openFile('/tmp/lsp_sync_test/main.dart', 'void f() {}');
      service.debugSetCompletionResolveProvider(true);

      service.updateFile('/tmp/lsp_sync_test/main.dart', 'Timer');

      final item = CompletionItem(
        label: 'Timer',
        kind: 'class',
        kindInt: 7,
        raw: <String, dynamic>{
          'label': 'Timer',
          'data': <String, dynamic>{'ref': 'dart:async;Timer'},
        },
      );
      final resolved = await service.resolveCompletionItem(
        item,
        filePath: '/tmp/lsp_sync_test/main.dart',
      );

      expect(
        events,
        <String>[
          'textDocument/didOpen@1',
          'textDocument/didChange@2',
          'completionItem/resolve',
        ],
      );
      expect(service.documentVersion('/tmp/lsp_sync_test/main.dart'), 2);
      expect(resolved?.documentVersion, 2);
      expect(resolved?.additionalTextEdits, hasLength(1));
    });

    test('an unchanged document sends no extra didChange', () async {
      final events = <String>[];
      final service = LspService(
        workspaceRoot: '/tmp/lsp_sync_test',
        notificationSender: (method, params) {
          if (method.startsWith('textDocument/')) events.add(method);
        },
        requestSender: (method, params) async {
          events.add(method);
          return <String, dynamic>{
            'items': <dynamic>[
              <String, dynamic>{'label': 'print', 'kind': 3},
            ],
          };
        },
      );
      addTearDown(service.dispose);
      await service.startServer();
      await service.openFile('/tmp/lsp_sync_test/main.dart', 'pri');

      await service.requestCompletion('/tmp/lsp_sync_test/main.dart', 1, 4);
      await service.requestCompletion('/tmp/lsp_sync_test/main.dart', 1, 4);

      expect(
        events,
        <String>[
          'textDocument/didOpen',
          'textDocument/completion',
          'textDocument/completion',
        ],
      );
    });
  });

}
