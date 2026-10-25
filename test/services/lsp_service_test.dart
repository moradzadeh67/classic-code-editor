import 'package:flutter_test/flutter_test.dart';

import 'package:classic_code_editor/models/diagnostic.dart';
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
            return <String, dynamic>{'isIncomplete': true, 'items': <dynamic>[]};
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
}
