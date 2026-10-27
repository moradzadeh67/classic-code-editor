import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/services/theme_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/editor_context_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// TASK-086: right click always opens Cut / Copy / Paste / Select All, styled
/// like the app's own menus, and the actions go through the field itself.
void main() {
  late FileService fileService;
  late LspService lspService;
  String? clipboard;

  setUp(() {
    fileService = FileService();
    lspService = LspService();
    fileService.createNewFile();
    clipboard = null;
    // Fake clipboard: `hasStrings` reports whether text is set, `getData`
    // returns it, `setData` stores it.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.hasStrings':
              return <String, dynamic>{'value': clipboard != null};
            case 'Clipboard.getData':
              return clipboard == null
                  ? null
                  : <String, dynamic>{'text': clipboard};
            case 'Clipboard.setData':
              clipboard = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.setClipboard':
              clipboard = (call.arguments as Map)['text'] as String?;
              return null;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    lspService.dispose();
    fileService.dispose();
  });

  Widget wrap() => MaterialApp(
    home: Scaffold(
      body: CodeEditorPanel(fileService: fileService, lspService: lspService),
    ),
  );

  TextEditingController controller(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!;

  bool rowEnabled(WidgetTester tester, String label) => tester
      .widget<EditorContextMenuRow>(find.byKey(EditorContextMenu.rowKey(label)))
      .enabled;

  Future<void> rightClick(WidgetTester tester, Offset position) async {
    final gesture = await tester.startGesture(
      position,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a fresh, empty buffer offers Paste and Select All', (
    tester,
  ) async {
    clipboard = 'hello';
    await tester.pumpWidget(wrap());
    await tester.pump();
    // Not focused yet: the menu must still open.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await rightClick(tester, const Offset(300, 60));

    expect(find.byKey(EditorContextMenu.menuKey), findsOneWidget);
    expect(rowEnabled(tester, EditorContextMenu.pasteLabel), isTrue);
    expect(rowEnabled(tester, EditorContextMenu.selectAllLabel), isFalse);
    expect(rowEnabled(tester, EditorContextMenu.cutLabel), isFalse);
    expect(rowEnabled(tester, EditorContextMenu.copyLabel), isFalse);
  });

  testWidgets('a selection enables Cut and Copy and is left untouched', (
    tester,
  ) async {
    clipboard = 'hello';
    await tester.pumpWidget(wrap());
    await tester.enterText(find.byType(TextField), 'foobar');
    controller(tester).selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 3,
    );
    await tester.pump();

    // Right click inside the existing selection.
    await rightClick(tester, const Offset(300, 60));

    expect(find.byKey(EditorContextMenu.menuKey), findsOneWidget);
    expect(rowEnabled(tester, EditorContextMenu.cutLabel), isTrue);
    expect(rowEnabled(tester, EditorContextMenu.copyLabel), isTrue);
    expect(
      controller(tester).selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
  });

  testWidgets('Paste inserts the clipboard through the field', (tester) async {
    clipboard = 'hello';
    await tester.pumpWidget(wrap());
    await tester.enterText(find.byType(TextField), 'abc');
    controller(tester).selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await rightClick(tester, const Offset(300, 60));
    await tester.pump();
    expect(rowEnabled(tester, EditorContextMenu.pasteLabel), isTrue);

    await tester.tap(
      find.byKey(EditorContextMenu.rowKey(EditorContextMenu.pasteLabel)),
    );
    await tester.pumpAndSettle();

    expect(controller(tester).text, 'abchello');
    expect(find.byKey(EditorContextMenu.menuKey), findsNothing);
  });

  testWidgets('the panel is content-sized and opens under the pointer', (
    tester,
  ) async {
    // The test window is 800x600.
    clipboard = 'hello';
    await tester.pumpWidget(wrap());
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await rightClick(tester, const Offset(100, 100));

    final menu = tester.getRect(find.byKey(EditorContextMenu.menuKey));
    expect(menu.width, lessThan(300));
    expect(menu.height, lessThan(200));
    expect(menu.topLeft.dx, closeTo(100, 1));
    expect(menu.topLeft.dy, closeTo(100, 1));
    // Entirely inside the window.
    expect(menu.left, greaterThanOrEqualTo(0));
    expect(menu.top, greaterThanOrEqualTo(0));
    expect(menu.right, lessThanOrEqualTo(800));
    expect(menu.bottom, lessThanOrEqualTo(600));
  });

  testWidgets('near the window edge the panel is shifted to stay inside', (
    tester,
  ) async {
    clipboard = 'hello';
    await tester.pumpWidget(wrap());
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    // Bottom-right corner of the editor's text area.
    final field = tester.getRect(find.byType(TextField));
    await rightClick(
      tester,
      Offset(field.right - 6, field.bottom - 6),
    );

    final menu = tester.getRect(find.byKey(EditorContextMenu.menuKey));
    expect(menu.width, lessThan(300));
    expect(menu.height, lessThan(200));
    expect(menu.right, lessThanOrEqualTo(800 - 3));
    expect(menu.bottom, lessThanOrEqualTo(600 - 3));
    expect(menu.left, greaterThanOrEqualTo(4));
    expect(menu.top, greaterThanOrEqualTo(4));
  });

  testWidgets('a click outside the panel closes it', (tester) async {
    clipboard = 'hello';
    await tester.pumpWidget(wrap());
    await tester.pump();

    await rightClick(tester, const Offset(100, 100));
    expect(find.byKey(EditorContextMenu.menuKey), findsOneWidget);

    // Far from the panel: the transparent barrier closes it.
    await tester.tapAt(const Offset(600, 400));
    await tester.pumpAndSettle();

    expect(find.byKey(EditorContextMenu.menuKey), findsNothing);
  });

  testWidgets('no row text is underlined, in any of the four themes', (
    tester,
  ) async {
    clipboard = 'hello';
    addTearDown(() => ThemeService.instance.switchTheme(ThemeType.vc6));

    for (final theme in ThemeType.values) {
      ThemeService.instance.switchTheme(theme);
      await tester.pumpWidget(wrap());
      await tester.pump();

      await rightClick(tester, const Offset(100, 100));
      expect(find.byKey(EditorContextMenu.menuKey), findsOneWidget, reason: theme.name);

      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(EditorContextMenu.menuKey),
          matching: find.byType(Text),
        ),
      );
      expect(texts, isNotEmpty);
      for (final text in texts) {
        expect(
          text.style?.decoration,
          TextDecoration.none,
          reason: '${theme.name}: "${text.data}" must not be underlined',
        );
      }
    }
  });
}
