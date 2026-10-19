import 'dart:io';

import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/theme_service.dart';
import 'package:classic_code_editor/ui/shell/close_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late FileService fileService;
  late File file;

  setUp(() async {
    ThemeService.instance.switchTheme(ThemeType.vc6);
    tempDir = await Directory.systemTemp.createTemp('close_guard_test');
    file = File('${tempDir.path}/main.dart')
      ..writeAsStringSync('void main() {}');
    fileService = FileService();
    fileService.openFilePath(file.path, 'void main() {}');
  });

  tearDown(() async {
    fileService.dispose();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Already gone on CI: nothing left to clean up.
    }
  });

  /// Pumps a button that runs the guard, so a dialog can be shown on top.
  Future<void> pumpGuard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => TabCloseGuard.confirmClose(
                context,
                fileService: fileService,
                index: 0,
              ),
              child: const Text('close'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('an unmodified tab closes without asking', (tester) async {
    await pumpGuard(tester);
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Save changes to'), findsNothing);
    expect(fileService.openTabs, isEmpty);
  });

  testWidgets('a modified tab asks, and Cancel keeps it open', (tester) async {
    fileService.updateContent('void main() { /* changed */ }');
    await pumpGuard(tester);

    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    expect(find.text('Save changes to main.dart?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fileService.openTabs, hasLength(1));
  });

  testWidgets("Don't Save closes the tab and discards the buffer", (
    tester,
  ) async {
    fileService.updateContent('void main() { /* changed */ }');
    await pumpGuard(tester);

    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't Save"));
    await tester.pumpAndSettle();

    expect(fileService.openTabs, isEmpty);
    expect(file.readAsStringSync(), 'void main() {}');
  });

  // NOTE: the guard's Save branch awaits real file IO, which cannot complete
  // inside the fake async zone of testWidgets. It is verified manually (see the
  // MANUAL CHECK list) instead of here.

  testWidgets('confirmExit returns false when the user cancels', (
    tester,
  ) async {
    fileService.updateContent('void main() { /* changed */ }');

    late bool result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await TabCloseGuard.confirmExit(
                  context,
                  fileService: fileService,
                );
              },
              child: const Text('quit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('quit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
