import 'package:classic_code_editor/models/language_config.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/unsaved_buffer_workspace.dart';
import 'package:classic_code_editor/ui/editor/tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 700, height: 120, child: child)),
  );
}

void main() {
  late FileService fileService;

  setUp(() {
    fileService = FileService();
    // The strip (and its "+") only exists once there is a tab to sit beside.
    fileService.openFilePath('/tmp/main.dart', 'void main() {}');
  });

  tearDown(() => fileService.dispose());

  testWidgets('the "+" button adds an active Untitled tab, twice distinct', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(TabBarWidget(fileService: fileService)));

    await tester.tap(find.byKey(kNewTabButtonKey));
    await tester.pump();

    expect(fileService.openTabs, hasLength(2));
    expect(fileService.activeTabIndex, 1);
    expect(fileService.activeTab!.fileName, 'Untitled');
    expect(fileService.activeTab!.content, isEmpty);

    await tester.tap(find.byKey(kNewTabButtonKey));
    await tester.pump();

    expect(fileService.openTabs, hasLength(3));
    expect(fileService.activeTabIndex, 2);
    final names = fileService.openTabs.map((tab) => tab.fileName).toList();
    expect(names, ['main.dart', 'Untitled', 'Untitled 2']);

    expect(tester.takeException(), isNull);
  });

  test('two untitled tabs get two distinct virtual LSP documents', () async {
    fileService.createNewFile();
    fileService.createNewFile();
    final workspace = UnsavedBufferWorkspace();
    addTearDown(workspace.dispose);

    final config = LanguageConfig.fromPathOrContent(null, '');
    final first = await workspace.pathFor(
      config,
      bufferName: fileService.openTabs[1].fileName,
    );
    final second = await workspace.pathFor(
      config,
      bufferName: fileService.openTabs[2].fileName,
    );

    expect(first, endsWith('/untitled${config.extension}'));
    expect(second, endsWith('/untitled-2${config.extension}'));
    expect(first, isNot(second));
  });

  test('closing a tab drops its language selection', () {
    fileService.switchTab(0);
    fileService.setActiveLanguage('Python');
    expect(fileService.activeLanguageOverride, 'Python');

    fileService.createNewFile();
    expect(fileService.activeLanguageOverride, 'Auto');

    fileService.switchTab(0);
    expect(fileService.activeLanguageOverride, 'Python');

    fileService.closeTab(0);
    expect(fileService.activeTab!.languageOverride, 'Auto');
  });

  testWidgets('the "+" is pinned outside the scrolling tabs', (tester) async {
    for (var i = 0; i < 12; i++) {
      fileService.openFilePath('/tmp/file$i.dart', 'void main() {}');
    }
    await tester.pumpWidget(_wrap(TabBarWidget(fileService: fileService)));

    final plus = find.byKey(kNewTabButtonKey);
    expect(plus, findsOneWidget);
    // Still inside the strip's right edge, even with many tabs.
    final strip = tester.getRect(find.byType(TabBarWidget));
    final button = tester.getRect(plus);
    expect(button.right, lessThanOrEqualTo(strip.right));
    expect(button.height, kEditorTabHeight);
    expect(tester.takeException(), isNull);
  });
}
