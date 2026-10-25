import 'package:flutter_test/flutter_test.dart';

import 'package:classic_code_editor/services/lsp_server_manager.dart';
import 'package:classic_code_editor/services/lsp_server_spec.dart';
import 'package:classic_code_editor/services/lsp_service.dart';

/// A language server that never spawns a process.
class _FakeLspService extends LspService {
  _FakeLspService(this.fakeSpec, {this.connects = true, this.startError});

  final LspServerSpec fakeSpec;
  final bool connects;
  final String? startError;
  int starts = 0;

  @override
  LspServerSpec get spec => fakeSpec;

  @override
  String? get lastError => startError;

  @override
  bool get isConnected => connects && starts > 0;

  @override
  Future<void> startServer() async {
    starts++;
  }
}

void main() {
  late List<String> createdSpecIds;
  late List<String> output;
  late Map<String, _FakeLspService> fakes;

  LspServerManager buildManager({
    Map<String, bool> connects = const <String, bool>{},
    Map<String, String> errors = const <String, String>{},
  }) {
    return LspServerManager(
      workspaceRoot: '/tmp/lsp_manager_test',
      onOutput: output.add,
      serviceFactory: (spec) {
        createdSpecIds.add(spec.id);
        return fakes[spec.id] = _FakeLspService(
          spec,
          connects: connects[spec.id] ?? true,
          startError: errors[spec.id],
        );
      },
    );
  }

  setUp(() {
    createdSpecIds = <String>[];
    output = <String>[];
    fakes = <String, _FakeLspService>{};
  });

  test(
    'starts on Dart and reuses the warm instance when coming back',
    () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      final dartFirst = manager.active;
      expect(dartFirst.spec.id, 'dart');

      await manager.activateFor('/tmp/main.c');
      expect(manager.active.spec.id, 'clangd');

      await manager.activateFor('/tmp/main.dart');
      expect(identical(manager.active, dartFirst), isTrue);
      expect(createdSpecIds.where((id) => id == 'dart'), hasLength(1));
    },
  );

  test('switching between C and C++ keeps the same clangd process', () async {
    final manager = buildManager();
    addTearDown(manager.dispose);

    await manager.activateFor('/tmp/one.c');
    final first = manager.active;

    await manager.activateFor('/tmp/two.cpp');

    expect(identical(manager.active, first), isTrue);
    expect(createdSpecIds.where((id) => id == 'clangd'), hasLength(1));
  });

  test('same language twice does not activate anything again', () async {
    final manager = buildManager();
    addTearDown(manager.dispose);

    await manager.activateFor('/tmp/one.c');
    final starts = fakes['clangd']!.starts;

    await manager.activateFor('/tmp/two.c');

    expect(fakes['clangd']!.starts, starts);
  });

  test('falls back from pyright to pylsp when pyright is missing', () async {
    final manager = buildManager(
      connects: <String, bool>{'pyright': false},
      errors: <String, String>{'pyright': 'PID not found'},
    );
    addTearDown(manager.dispose);

    final service = await manager.activateFor('/tmp/tool.py');

    expect(service.spec.id, 'pylsp');
    expect(
      output.any((line) => line.contains('pyright is not available')),
      isTrue,
    );
    expect(output.any((line) => line.contains('npm install')), isTrue);
  });

  test('reports the install hint once and uses the off service', () async {
    final manager = buildManager(
      connects: <String, bool>{'clangd': false},
      errors: <String, String>{'clangd': 'No such file'},
    );
    addTearDown(manager.dispose);

    await manager.activateFor('/tmp/main.c');
    expect(manager.active.spec.id, 'off');

    await manager.activateFor('/tmp/another.c');
    expect(
      output.where((line) => line.contains('xcode-select')).length,
      1,
      reason: 'a tab switch must not repeat the hint',
    );
  });

  test('assembly files get no server at all', () async {
    final manager = buildManager();
    addTearDown(manager.dispose);

    await manager.activateFor('/tmp/samples/hello_arm64.s');

    expect(manager.active.spec.id, 'off');
    expect(createdSpecIds, isNot(contains('clangd')));
    expect(output, isEmpty);
  });

  test(
    'notifies listeners only when the active server really changes',
    () async {
      final manager = buildManager();
      addTearDown(manager.dispose);

      var notifications = 0;
      manager.addListener(() => notifications++);

      await manager.activateFor('/tmp/one.c');
      final afterFirstSwitch = notifications;

      await manager.activateFor('/tmp/two.c');

      expect(afterFirstSwitch, greaterThan(0));
      expect(notifications, afterFirstSwitch);
    },
  );
}
