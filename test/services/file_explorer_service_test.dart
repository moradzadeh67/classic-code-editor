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

    expect(service.root!.children.map((n) => n.name), ['main.dart']);
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

  group('file operations', () {
    late FileExplorerService service;
    late List<String> trashed;

    setUp(() async {
      trashed = <String>[];
      // Never the real Trash: record the call and remove the entry.
      service = FileExplorerService(
        moveToTrash: (path) async {
          trashed.add(path);
          final type = FileSystemEntity.typeSync(path);
          if (type == FileSystemEntityType.directory) {
            Directory(path).deleteSync(recursive: true);
          } else {
            File(path).deleteSync();
          }
        },
      );
      write('src/main.dart', 'void main() {}');
      write('notes.txt', 'n');
      await service.openFolder(root.path);
    });

    tearDown(() => service.dispose());

    List<String> topNames() =>
        service.root!.children.map((n) => n.name).toList();

    test('creates a file and a folder and shows them', () async {
      final file = await service.createFile(root.path, 'new.dart');
      final folder = await service.createFolder('${root.path}/src', 'lib');

      expect(File(file).existsSync(), isTrue);
      expect(Directory(folder).existsSync(), isTrue);
      expect(topNames(), contains('new.dart'));
      // The parent was expanded so the new folder is visible.
      final src = service.root!.children.firstWhere((n) => n.name == 'src');
      expect(src.expanded, isTrue);
      expect(src.children.map((n) => n.name), contains('lib'));
    });

    test('validates names', () {
      expect(service.nameError(root.path, ''), isNotNull);
      expect(service.nameError(root.path, '  '), isNotNull);
      expect(service.nameError(root.path, ' a.txt'), isNotNull);
      expect(service.nameError(root.path, 'a/b'), isNotNull);
      expect(service.nameError(root.path, '..'), isNotNull);
      expect(service.nameError(root.path, 'notes.txt'), contains('exists'));
      expect(service.nameError(root.path, 'fresh.txt'), isNull);
      // Renaming to itself or only changing the case is not a clash.
      expect(
        service.nameError(root.path, 'Notes.txt', currentName: 'notes.txt'),
        isNull,
      );
    });

    test('refuses to create over an existing entry', () async {
      await expectLater(
        service.createFile(root.path, 'notes.txt'),
        throwsA(isA<FileOperationException>()),
      );
      expect(File('${root.path}/notes.txt').readAsStringSync(), 'n');
    });

    test('renames a file and a folder', () async {
      final renamed = await service.rename('${root.path}/notes.txt', 'a.md');
      expect(renamed, '${root.path}/a.md');
      expect(File(renamed).readAsStringSync(), 'n');
      expect(File('${root.path}/notes.txt').existsSync(), isFalse);

      final folder = await service.rename('${root.path}/src', 'source');
      expect(File('$folder/main.dart').existsSync(), isTrue);
      expect(topNames(), ['source', 'a.md']);
    });

    test('the open folder itself cannot be renamed or trashed', () async {
      await expectLater(
        service.rename(root.path, 'x'),
        throwsA(isA<FileOperationException>()),
      );
      await expectLater(
        service.moveToTrash(root.path),
        throwsA(isA<FileOperationException>()),
      );
      expect(trashed, isEmpty);
    });

    test('duplicates with free "copy" names', () async {
      final first = await service.duplicate('${root.path}/notes.txt');
      final second = await service.duplicate('${root.path}/notes.txt');
      final folder = await service.duplicate('${root.path}/src');

      expect(first, '${root.path}/notes copy.txt');
      expect(second, '${root.path}/notes copy 2.txt');
      expect(File('$folder/main.dart').readAsStringSync(), 'void main() {}');
      expect(service.uniqueCopyName(root.path, '.env'), '.env copy');
    });

    test('copy + paste copies, cut + paste moves', () async {
      service.copyToClipboard('${root.path}/notes.txt');
      expect(service.hasClipboard, isTrue);
      final copied = await service.paste('${root.path}/src');
      expect(copied!.moved, isFalse);
      expect(copied.to, '${root.path}/src/notes.txt');
      expect(File('${root.path}/notes.txt').existsSync(), isTrue);
      // A copy stays on the clipboard; pasting again picks a free name.
      final again = await service.paste('${root.path}/src');
      expect(again!.to, '${root.path}/src/notes copy.txt');

      service.cutToClipboard('${root.path}/notes.txt');
      await expectLater(
        service.paste('${root.path}/src'),
        throwsA(isA<FileOperationException>()),
      );
      await service.rename('${root.path}/src/notes.txt', 'old.txt');
      final moved = await service.paste('${root.path}/src');
      expect(moved!.moved, isTrue);
      expect(File('${root.path}/notes.txt').existsSync(), isFalse);
      expect(File('${root.path}/src/notes.txt').readAsStringSync(), 'n');
      expect(service.hasClipboard, isFalse);
    });

    test('a folder cannot be pasted inside itself', () async {
      service.copyToClipboard('${root.path}/src');
      await expectLater(
        service.paste('${root.path}/src'),
        throwsA(isA<FileOperationException>()),
      );
    });

    test('the clipboard follows a rename of its entry', () async {
      service.copyToClipboard('${root.path}/src/main.dart');
      await service.rename('${root.path}/src', 'source');
      expect(service.clipboardPath, '${root.path}/source/main.dart');
    });

    test('moves to the Trash through the injected mover', () async {
      service.copyToClipboard('${root.path}/src/main.dart');
      await service.moveToTrash('${root.path}/src');
      expect(trashed, ['${root.path}/src']);
      expect(topNames(), ['notes.txt']);
      // The clipboard entry was inside the trashed folder.
      expect(service.hasClipboard, isFalse);
    });

    test('relative paths are relative to the open folder', () {
      expect(
        service.relativePath('${root.path}/src/main.dart'),
        'src/main.dart',
      );
      expect(service.relativePath(root.path), '.');
      expect(service.relativePath('/elsewhere/x'), '/elsewhere/x');
    });
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
