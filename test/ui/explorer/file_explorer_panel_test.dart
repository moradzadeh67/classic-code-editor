import 'dart:io';

import 'package:classic_code_editor/services/file_explorer_service.dart';
import 'package:classic_code_editor/ui/explorer/file_explorer_panel.dart';
import 'package:flutter/material.dart';
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

  setUp(() async {
    root = await Directory.systemTemp.createTemp('explorer_ui_');
    Directory('${root.path}/src').createSync();
    File('${root.path}/src/main.dart').writeAsStringSync('void main() {}');
    Directory('${root.path}/docs').createSync();
    File('${root.path}/docs/guide.txt').writeAsStringSync('guide');
    File('${root.path}/README.md').writeAsStringSync('readme');

    service = FileExplorerService();
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
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('folder click expands, double-click opens, active file is marked', (
    tester,
  ) async {
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
  });
}
