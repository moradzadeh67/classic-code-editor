import 'dart:io';

import 'package:classic_code_editor/services/file_explorer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('explorer_test_');
  });

  tearDown(() async {
    // Make sure a permission-tested folder can be removed again.
    if (await root.exists()) {
      for (final entity in await root.list(recursive: true).toList()) {
        if (entity is Directory) {
          await Process.run('chmod', ['700', entity.path]);
        }
      }
      await root.delete(recursive: true);
    }
  });

  void write(String relative, [String content = 'x']) {
    final file = File('${root.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void mkdir(String relative) {
    Directory('${root.path}/$relative').createSync(recursive: true);
  }

  test('sorts folders first, then files, case-insensitively', () async {
    write('beta.txt');
    write('Alpha.txt');
    mkdir('zeta');
    mkdir('Beta');

    final service = FileExplorerService();
    await service.openFolder(root.path);

    final names = service.root!.children.map((n) => n.name).toList();
    expect(names, ['Beta', 'zeta', 'Alpha.txt', 'beta.txt']);
    expect(service.root!.children.first.isDirectory, isTrue);
    service.dispose();
  });

  test('hides dot names and tool directories', () async {
    write('main.dart');
    write('.hidden.dart');
    write('.DS_Store');
    mkdir('.git');
    mkdir('build');
    mkdir('.dart_tool');
    mkdir('node_modules');
    mkdir('__pycache__');

    final service = FileExplorerService();
    await service.openFolder(root.path);

    expect(
      service.root!.children.map((n) => n.name),
      ['main.dart'],
    );
    service.dispose();
  });

  test('reads a child directory only when it is expanded', () async {
    write('src/main.dart');
    write('src/util.dart');

    final service = FileExplorerService();
    await service.openFolder(root.path);

    final src = service.root!.children.single;
    expect(src.isDirectory, isTrue);
    expect(src.childrenLoaded, isFalse);
    expect(src.children, isEmpty);

    await service.toggleFolder(src);
    expect(src.expanded, isTrue);
    expect(src.childrenLoaded, isTrue);
    expect(src.children.map((n) => n.name), ['main.dart', 'util.dart']);

    await service.toggleFolder(src);
    expect(src.expanded, isFalse);
    // Collapsing keeps the read children, so re-opening is instant.
    expect(src.childrenLoaded, isTrue);
    service.dispose();
  });

  test('caps one directory at 2000 entries plus a summary row', () async {
    for (var i = 0; i < 2003; i++) {
      write('file_${i.toString().padLeft(4, '0')}.txt');
    }

    final service = FileExplorerService();
    await service.openFolder(root.path);

    final children = service.root!.children;
    expect(children.length, 2001);
    expect(children.last.isTruncationNotice, isTrue);
    expect(children.last.name, '… 3 more not shown');
    service.dispose();
  });

  test('an unreadable folder shows as empty instead of throwing', () async {
    write('locked/secret.txt');
    await Process.run('chmod', ['000', '${root.path}/locked']);

    final service = FileExplorerService();
    await service.openFolder(root.path);
    final locked = service.root!.children.single;

    await service.toggleFolder(locked);
    expect(locked.children, isEmpty);
    expect(locked.expanded, isTrue);

    await Process.run('chmod', ['700', '${root.path}/locked']);
    service.dispose();
  });

  test('refuses binary and oversized files', () async {
    write('ok.txt', 'hello');
    File('${root.path}/bin.dat').writeAsBytesSync([65, 0, 66]);
    File('${root.path}/big.txt').writeAsStringSync('a' * (2 * 1024 * 1024 + 1));

    final service = FileExplorerService();
    await service.openFolder(root.path);

    expect(await service.readFileForOpen('${root.path}/ok.txt'), 'hello');
    expect(await service.readFileForOpen('${root.path}/bin.dat'), isNull);
    expect(await service.readFileForOpen('${root.path}/big.txt'), isNull);
    service.dispose();
  });
}
