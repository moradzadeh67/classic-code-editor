import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/theme_service.dart';
import 'package:classic_code_editor/ui/shell/retro_menu_bar.dart';
import 'package:classic_code_editor/ui/shell/retro_menu_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// R2 of the Phase 22 follow-up: after choosing a font the check mark must move
/// **without** anyone rebuilding the menu bar.
///
/// The View > Font bug was a staleness bug, not a data bug: the bar is a
/// StatelessWidget that rebuilds only on SessionService, and the rows were
/// constructed in build() and then captured by itemBuilder, so the popup kept
/// showing whatever family was current at the last rebuild. The Phase 22 test
/// hid it by calling pumpWidget again after switching; this one deliberately
/// does not rebuild between choosing and reopening - the path the real app
/// takes.
void main() {
  setUp(() {
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);
    ThemeService.instance.switchTheme(ThemeType.vc6);
  });

  tearDown(() {
    EditorSettingsService.instance.setFontFamily(EditorFontFamily.menlo);
    ThemeService.instance.switchTheme(ThemeType.vc6);
  });

  /// A bar keyed by the theme, exactly like the shell keys it.
  Widget bar() => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          RetroMenuBar(key: ValueKey(ThemeService.instance.currentTheme)),
        ],
      ),
    ),
  );

  Finder viewTitle() => find
      .descendant(of: find.byType(RetroMenuBar), matching: find.text('View'))
      .first;

  Future<void> openView(WidgetTester tester) async {
    await tester.tap(viewTitle());
    await tester.pumpAndSettle();
  }

  Future<void> closeMenu(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  /// Checked rows of the currently open popup, by label prefix.
  List<String> checkedRows(WidgetTester tester, String prefix) => tester
      .widgetList<RetroMenuItem<String>>(find.byType(RetroMenuItem<String>))
      .where((row) => row.checked == true && row.label.startsWith(prefix))
      .map((row) => row.label)
      .toList(growable: false);

  List<String> checkedFonts(WidgetTester tester) =>
      checkedRows(tester, 'Font: ');

  testWidgets('choosing a font moves the check mark on the next open', (
    tester,
  ) async {
    await tester.pumpWidget(bar());
    await openView(tester);
    expect(checkedFonts(tester), <String>['Font: Menlo']);
    await closeMenu(tester);

    // Pick every family through the real menu path, never rebuilding the bar.
    for (final family in <EditorFontFamily>[
      EditorFontFamily.recursive,
      EditorFontFamily.menlo,
      EditorFontFamily.recursive,
    ]) {
      await openView(tester);
      await tester.tap(find.text('Font: ${family.label}'));
      await tester.pumpAndSettle();
      expect(EditorSettingsService.instance.fontFamily, family);

      await openView(tester);
      expect(
        checkedFonts(tester),
        <String>['Font: ${family.label}'],
        reason:
            'after selecting ${family.id}, reopening View must check its row: '
            'the rows are built when the popup opens',
      );
      await closeMenu(tester);
    }
  });

  testWidgets('only one font row is ever checked', (tester) async {
    await tester.pumpWidget(bar());

    for (final family in EditorFontFamily.values) {
      await openView(tester);
      await tester.tap(find.text('Font: ${family.label}'));
      await tester.pumpAndSettle();

      await openView(tester);
      final checked = checkedFonts(tester);
      expect(checked, hasLength(1));
      expect(checked.single, 'Font: ${family.label}');
      await closeMenu(tester);
    }
  });

  testWidgets('the check survives a theme switch', (tester) async {
    await tester.pumpWidget(bar());
    await openView(tester);
    await tester.tap(find.text('Font: ${EditorFontFamily.recursive.label}'));
    await tester.pumpAndSettle();

    ThemeService.instance.switchTheme(ThemeType.delphi);
    await tester.pumpWidget(bar());
    await openView(tester);

    expect(checkedFonts(tester), <String>['Font: Recursive Mono Casual']);
    expect(checkedRows(tester, 'Theme: '), <String>['Theme: Borland Delphi']);
    await closeMenu(tester);
  });

  testWidgets('the theme rows are live on the same path', (tester) async {
    // The same staleness affected the theme rows: a switch that did not rebuild
    // the bar left the old check in place. Both groups read live values now.
    await tester.pumpWidget(bar());

    for (final entry in <(ThemeType, String)>[
      (ThemeType.delphi, 'Borland Delphi'),
      (ThemeType.vb6, 'Visual Basic 6.0'),
      (ThemeType.vc6, 'VC++ 6.0'),
    ]) {
      final (theme, label) = entry;
      await openView(tester);
      await tester.tap(find.text('Theme: $label'));
      await tester.pumpAndSettle();
      expect(ThemeService.instance.currentTheme, theme);

      // The shell re-keys the bar on a theme change, so rebuild for that one.
      await tester.pumpWidget(bar());
      await openView(tester);
      expect(checkedRows(tester, 'Theme: '), <String>['Theme: $label']);
      expect(checkedFonts(tester), <String>['Font: Menlo']);
      await closeMenu(tester);
    }
  });
}
