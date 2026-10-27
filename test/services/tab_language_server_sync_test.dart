import 'package:classic_code_editor/models/diagnostic.dart';
import 'package:classic_code_editor/models/language_config.dart';
import 'package:classic_code_editor/services/lsp_server_manager.dart';
import 'package:classic_code_editor/services/lsp_server_spec.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/services/tab_language_server_sync.dart';
import 'package:classic_code_editor/services/unsaved_buffer_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

/// TASK-087: the server (and its diagnostics) follow the tab's effective
/// language, not just the file extension.
class _FakeWorkspace extends UnsavedBufferWorkspace {
  @override
  Future<String> pathFor(LanguageConfig config, {String? bufferName}) async {
    final slug = (bufferName ?? 'untitled')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '/tmp/ccvirtual/${slug.isEmpty ? 'untitled' : slug}'
        '${config.extension}';
  }
}

/// Records which document each "server" was asked for and hands out the real
/// [LspService] instances, keyed by spec id.
class _FakeManager extends LspServerManager {
  _FakeManager(this.services) : super(workspaceRoot: '/tmp');

  final Map<String, LspService> services;
  final List<String> activated = <String>[];

  @override
  Future<LspService> activateFor(String? filePath, {String content = ''}) async {
    activated.add(filePath ?? '<null>');
    final language = LanguageConfig.fromPathOrContent(
      filePath,
      content,
    ).highlightLanguage;
    final id = switch (language) {
      'dart' => 'dart',
      'python' => 'pylsp',
      _ => 'clangd',
    };
    return services[id]!;
  }

  @override
  LspService activateForUnsavedBuffer() => services['off']!;
}

void main() {
  late LspService dartService;
  late LspService clangdService;
  late _FakeManager manager;
  late TabLanguageServerSync sync;

  setUp(() {
    dartService = LspService(
      spec: LspServerSpec.dart,
      workspaceRoot: '/tmp',
    );
    clangdService = LspService(
      spec: LspServerSpec.clangd,
      workspaceRoot: '/tmp',
    );
    manager = _FakeManager({
      'dart': dartService,
      'clangd': clangdService,
      'off': LspService(spec: LspServerSpec.off),
    });
    sync = TabLanguageServerSync(manager: manager, workspace: _FakeWorkspace());
  });

  tearDown(() {
    dartService.dispose();
    clangdService.dispose();
    manager.dispose();
  });

  const realPath = '/Users/me/project/Untitled 23.c';

  test('a .c tab switched to Dart is documented as .dart on the Dart server', () async {
    await sync.sync(
      effective: LanguageConfig.supportedLanguages[0],
      realPath: realPath,
      content: 'void main() {}',
      bufferName: 'Untitled 23.c',
    );

    expect(sync.openPath, endsWith('/untitled-23-c.dart'));
    expect(sync.openService, same(dartService));
    expect(manager.activated.single, endsWith('.dart'));
    expect(sync.openService!.spec.id, 'dart');
  });

  test('switching back to Auto closes the old document and its diagnostics', () async {
    await sync.sync(
      effective: LanguageConfig.supportedLanguages[0],
      realPath: realPath,
      content: 'void main() {}',
      bufferName: 'Untitled 23.c',
    );
    final virtualPath = sync.openPath!;
    dartService.debugSetDiagnosticsFor(virtualPath, [
      Diagnostic(
        file: virtualPath,
        line: 1,
        column: 1,
        severity: 'error',
        message: 'Eight clangd-style errors',
        code: 'x',
      ),
    ]);
    expect(dartService.activeDiagnostics, hasLength(1));

    // Auto on a `.c` file means C again: the real path, on clangd.
    await sync.sync(
      effective: LanguageConfig.supportedLanguages[1],
      realPath: realPath,
      content: 'void main() {}',
      bufferName: 'Untitled 23.c',
    );

    expect(sync.openPath, realPath);
    expect(sync.openService!.spec.id, 'clangd');
    // The old URI was closed, so its stale count is gone.
    expect(dartService.activeDiagnostics, isEmpty);
    expect(dartService.activeDocumentPath, isNull);
  });

  test('an untitled buffer still gets a virtual document', () async {
    await sync.sync(
      effective: LanguageConfig.supportedLanguages[1],
      realPath: null,
      content: 'int main(void) { return 0; }',
      bufferName: 'Untitled',
    );

    expect(sync.openPath, '/tmp/ccvirtual/untitled.c');
    expect(sync.openService!.spec.id, 'clangd');
  });

  test('an explicit language that matches the extension keeps the real path', () async {
    await sync.sync(
      effective: LanguageConfig.supportedLanguages[1],
      realPath: realPath,
      content: 'int main(void) { return 0; }',
      bufferName: 'Untitled 23.c',
    );

    expect(sync.openPath, realPath);
    expect(manager.activated.single, realPath);
  });

  group('needsVirtualDocument', () {
    test('matches the extension or not', () {
      expect(
        TabLanguageServerSync.needsVirtualDocument(
          effective: LanguageConfig.supportedLanguages[0],
          realPath: realPath,
          extensionLanguage: LanguageConfig.supportedLanguages[1],
        ),
        isTrue,
      );
      expect(
        TabLanguageServerSync.needsVirtualDocument(
          effective: LanguageConfig.supportedLanguages[1],
          realPath: realPath,
          extensionLanguage: LanguageConfig.supportedLanguages[1],
        ),
        isFalse,
      );
      expect(
        TabLanguageServerSync.needsVirtualDocument(
          effective: LanguageConfig.supportedLanguages[0],
          realPath: null,
          extensionLanguage: null,
        ),
        isTrue,
      );
      // An extension we do not know also needs the virtual document.
      expect(
        TabLanguageServerSync.needsVirtualDocument(
          effective: LanguageConfig.supportedLanguages[0],
          realPath: '/tmp/notes.txt',
          extensionLanguage: null,
        ),
        isTrue,
      );
    });
  });
}
