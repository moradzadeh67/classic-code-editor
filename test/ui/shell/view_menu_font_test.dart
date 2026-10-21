import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/theme_service.dart';
import 'package:classic_code_editor/ui/shell/retro_menu_bar.dart';
import 'package:classic_code_editor/ui/shell/retro_menu_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// R4: View > Font offers the three faces and marks the live one.
///
/// The rows are deliberately **not** const: their `checked` flag is read from
/// the service on every build (Rule 8), so switching the font must move the
/// check mark without any extra plumbing.
void main() {
  setUp(() {
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);
    EditorSettingsService.instance.setFontSize(
      EditorSettingsService.defaultFontSize,
    );
  });

  tearDown(() {
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);
    EditorSettingsService.instance.setFontSize(
      EditorSettingsService.defaultFontSize,
    );
  });

  Widget wrap() => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          RetroMenuBar(key: ValueKey(ThemeService.instance.currentTheme)),
        ],
      ),
    ),
  );

  Future<void> openView(WidgetTester tester) async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(RetroMenuBar),
            matching: find.text('View'),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  List<String> checkedFontRows(WidgetTester tester) => tester
      .widgetList<RetroMenuItem<String>>(find.byType(RetroMenuItem<String>))
      .where((row) => row.checked == true && row.label.startsWith('Font: '))
      .map((row) => row.label)
      .toList();

  testWidgets('the two fonts are listed in the View menu', (tester) async {
    await tester.pumpWidget(wrap());
    await openView(tester);

    expect(find.text('Font: Menlo'), findsOneWidget);
    expect(find.text('Font: Recursive Mono Casual'), findsOneWidget);
    // Monaco is no longer offered at all.
    expect(find.text('Font: Monaco'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menlo is checked by default', (tester) async {
    await tester.pumpWidget(wrap());
    await openView(tester);

    expect(checkedFontRows(tester), ['Font: Menlo']);
  });

  testWidgets('the check mark follows the live setting', (tester) async {
    await tester.pumpWidget(wrap());
    await openView(tester);
    expect(checkedFontRows(tester), ['Font: Menlo']);

    // Close, switch, reopen: the row reads the service, it does not cache.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.recursive);
    await tester.pumpWidget(wrap());
    await openView(tester);
    expect(checkedFontRows(tester), ['Font: Recursive Mono Casual']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);
    await tester.pumpWidget(wrap());
    await openView(tester);
    expect(checkedFontRows(tester), ['Font: Menlo']);

    // Exactly one row is ever checked.
    expect(
      tester
          .widgetList<RetroMenuItem<String>>(find.byType(RetroMenuItem<String>))
          .where((row) => row.checked == true && row.label.startsWith('Font: '))
          .length,
      1,
    );
  });

  testWidgets('picking a row sets the family', (tester) async {
    await tester.pumpWidget(wrap());
    await openView(tester);

    await tester.tap(find.text('Font: Recursive Mono Casual'));
    await tester.pumpAndSettle();

    expect(
      EditorSettingsService.instance.fontFamily,
      EditorFontFamily.recursive,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a row does not change the size or the theme', (
    tester,
  ) async {
    EditorSettingsService.instance.setFontSize(20);
    final themeBefore = ThemeService.instance.currentTheme;

    await tester.pumpWidget(wrap());
    await openView(tester);
    await tester.tap(find.text('Font: Recursive Mono Casual'));
    await tester.pumpAndSettle();

    expect(
      EditorSettingsService.instance.fontFamily,
      EditorFontFamily.recursive,
    );
    expect(EditorSettingsService.instance.fontSize, 20);
    expect(ThemeService.instance.currentTheme, themeBefore);
  });

  testWidgets('re-picking the checked row is a no-op', (tester) async {
    await tester.pumpWidget(wrap());
    await openView(tester);

    var notifications = 0;
    void listener() => notifications++;
    EditorSettingsService.instance.addListener(listener);
    addTearDown(() => EditorSettingsService.instance.removeListener(listener));

    await tester.tap(find.text('Font: Menlo'));
    await tester.pumpAndSettle();

    expect(EditorSettingsService.instance.fontFamily, EditorFontFamily.menlo);
    expect(notifications, 0, reason: 'no rebuild for an unchanged choice');
  });
}
