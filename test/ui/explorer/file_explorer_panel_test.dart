import 'dart:io';

import 'package:classic_code_editor/services/file_explorer_service.dart';
import 'package:classic_code_editor/ui/explorer/file_explorer_panel.dart';
import 'package:classic_code_editor/ui/shell/retro_menu_item.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 260, height: 500, child: child)),
  );
}

void main() {
  late Directory root;
  late FileExplorerService service;
  late List<String> opened;
  late List<String> trashed;
  late List<String> moved;
  late List<String> beforeDelete;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('explorer_ui_');
    Directory('${root.path}/src').createSync();
    File('${root.path}/src/main.dart').writeAsStringSync('void main() {}');
    Directory('${root.path}/docs').createSync();
    File('${root.path}/docs/guide.txt').writeAsStringSync('guide');
    File('${root.path}/README.md').writeAsStringSync('readme');

    trashed = <String>[];
    moved = <String>[];
    beforeDelete = <String>[];
    // Never the real Trash.
    service = FileExplorerService(
      moveToTrash: (path) async {
        trashed.add(path);
        File(path).deleteSync();
      },
    );
    await service.openFolder(root.path);
    opened = <String>[];
  });

  tearDown(() async {
    service.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> pumpPanel(WidgetTester tester, {String? active}) async {
    await tester.pumpWidget(
      _wrap(
        FileExplorerPanel(
          service: service,
          activeFilePath: active,
          onOpenFile: opened.add,
          onPathMoved: (from, to) => moved.add('$from -> $to'),
          onBeforeDelete: (path) async {
            beforeDelete.add(path);
            return true;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('path bar is an editable box that opens a typed folder', (
    tester,
  ) async {
    await pumpPanel(tester);
    final bar = find.byKey(const ValueKey('explorer-path-bar'));
    expect(tester.widget<TextField>(bar).controller!.text, root.path);

    // A typed existing folder is opened.
    await tester.enterText(bar, '${root.path}/src/');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(service.rootPath, '${root.path}/src');
    expect(tester.widget<TextField>(bar).controller!.text, '${root.path}/src');

    // A path that does not exist (or is a file) is refused; the box resets.
    await tester.enterText(bar, '${root.path}/nope');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(service.rootPath, '${root.path}/src');
    expect(tester.widget<TextField>(bar).controller!.text, '${root.path}/src');
    await tester.enterText(bar, '${root.path}/src/main.dart');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(service.rootPath, '${root.path}/src');
  });

  /// Right-clicks the tree row labelled [label] (`.last`: the open folder's
  /// name is also the panel header, above the tree).
  Future<void> rightClick(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  testWidgets('right click on a file shows the file menu', (tester) async {
    await pumpPanel(tester);
    await rightClick(tester, 'README.md');

    for (final action in <String>[
      'open',
      'cut',
      'copy',
      'paste',
      'duplicate',
      'rename',
      'delete',
      'copyPath',
      'copyRelativePath',
      'revealInFinder',
    ]) {
      expect(find.byKey(ValueKey('explorer-menu-$action')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('explorer-menu-newFile')), findsNothing);
    // Nothing copied yet: Paste is disabled.
    final paste = tester.widget<RetroMenuItem<ExplorerAction>>(
      find.byKey(const ValueKey('explorer-menu-paste')),
    );
    expect(paste.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the open folder has no Rename or Delete', (tester) async {
    await pumpPanel(tester);
    await rightClick(tester, service.rootName);

    expect(find.byKey(const ValueKey('explorer-menu-newFile')), findsOneWidget);
    expect(find.byKey(const ValueKey('explorer-menu-rename')), findsNothing);
    expect(find.byKey(const ValueKey('explorer-menu-delete')), findsNothing);
  });

  testWidgets('Rename renames on disk and tells the shell', (tester) async {
    await pumpPanel(tester);
    await rightClick(tester, 'README.md');
    await tester.tap(find.byKey(const ValueKey('explorer-menu-rename')));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('retro-input-field'));
    expect(tester.widget<TextField>(field).controller!.text, 'README.md');

    // A clashing name keeps the dialog open with an error.
    await tester.enterText(field, 'docs');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already exists'), findsOneWidget);

    await tester.enterText(field, 'INTRO.md');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(File('${root.path}/INTRO.md').readAsStringSync(), 'readme');
    expect(File('${root.path}/README.md').existsSync(), isFalse);
    expect(moved, ['${root.path}/README.md -> ${root.path}/INTRO.md']);
    expect(find.text('INTRO.md'), findsOneWidget);
  });

  testWidgets('Move to Trash asks, closes tabs, then trashes', (tester) async {
    await pumpPanel(tester);
    await rightClick(tester, 'README.md');
    await tester.tap(find.byKey(const ValueKey('explorer-menu-delete')));
    await tester.pumpAndSettle();

    // Cancel leaves everything alone.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(trashed, isEmpty);
    expect(beforeDelete, isEmpty);

    await rightClick(tester, 'README.md');
    await tester.tap(find.byKey(const ValueKey('explorer-menu-delete')));
    await tester.pumpAndSettle();
    // The menu is closed; the only "Move to Trash" left is the dialog button.
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();

    expect(beforeDelete, ['${root.path}/README.md']);
    expect(trashed, ['${root.path}/README.md']);
    expect(find.text('README.md'), findsNothing);
  });

  testWidgets('New File creates the file in the folder and opens it', (
    tester,
  ) async {
    await pumpPanel(tester);
    await rightClick(tester, 'docs');
    await tester.tap(find.byKey(const ValueKey('explorer-menu-newFile')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('retro-input-field')),
      'todo.txt',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(File('${root.path}/docs/todo.txt').existsSync(), isTrue);
    expect(opened, ['${root.path}/docs/todo.txt']);
    expect(find.text('todo.txt'), findsOneWidget);
  });

  testWidgets(
    'folder click expands, double-click opens, active file is marked',
    (tester) async {
      await pumpPanel(tester, active: '${root.path}/src/main.dart');
      await tester.pump();

      // The active file's parent folder was expanded for us, and the row is bold.
      expect(find.text('main.dart'), findsOneWidget);
      final activeText = tester.widget<Text>(find.text('main.dart'));
      expect(activeText.style!.fontWeight, FontWeight.bold);

      // A collapsed folder expands on a single click.
      expect(find.text('guide.txt'), findsNothing);
      await tester.tap(find.text('docs'));
      await tester.pump();
      expect(find.text('guide.txt'), findsOneWidget);

      // Double-click on the file asks the shell to open it.
      await tester.tap(find.text('guide.txt'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('guide.txt'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opened, ['${root.path}/docs/guide.txt']);

      expect(tester.takeException(), isNull);
    },
  );
}
