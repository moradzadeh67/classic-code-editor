import 'package:classic_code_editor/services/theme_service.dart';
import 'package:classic_code_editor/ui/shell/retro_menu_bar.dart';
import 'package:classic_code_editor/ui/shell/retro_menu_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fresh tree every time; the theme is part of the key so a theme switch
/// really rebuilds the bar (a const widget would be reused unchanged).
Widget _wrap() => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        RetroMenuBar(key: ValueKey(ThemeService.instance.currentTheme)),
      ],
    ),
  ),
);

/// Menu-bar title (not the item with the same text inside the open popup).
Finder _title(String label) => find
    .descendant(of: find.byType(RetroMenuBar), matching: find.text(label))
    .first;

/// Labels of the open menu's rows that are currently checked.
///
/// The View menu carries two independent check groups - the active theme and
/// the active font - so a bare `RetroMenuCheck` count is no longer meaningful;
/// what matters is that each group checks exactly one of its own rows.
List<String> _checkedLabels(WidgetTester tester) => tester
    .widgetList<RetroMenuItem<String>>(find.byType(RetroMenuItem<String>))
    .where((row) => row.checked == true)
    .map((row) => row.label)
    .toList();

/// The menu row that is currently drawn with the "menu active" background.
Finder _activeRow() => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.color == ThemeService.instance.colors.menuActive,
  description: 'active menu row',
);

/// Any popup decoration that would break the sharp retro look.
Finder _roundedOrShadowedDecoration() => find.byWidgetPredicate((widget) {
  if (widget is! DecoratedBox || widget.decoration is! BoxDecoration) {
    return false;
  }
  final decoration = widget.decoration as BoxDecoration;
  if (decoration.boxShadow != null && decoration.boxShadow!.isNotEmpty) {
    return true;
  }
  final radius = decoration.borderRadius;
  return radius != null && radius != BorderRadius.zero;
}, description: 'rounded or shadowed decoration');

void main() {
  setUp(() {
    ThemeService.instance.switchTheme(ThemeType.vc6);
  });

  tearDown(() {
    ThemeService.instance.switchTheme(ThemeType.vc6);
  });

  Future<void> openMenu(WidgetTester tester, String title) async {
    await tester.tap(_title(title));
    await tester.pumpAndSettle();
  }

  Future<void> closeMenu(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  testWidgets('all six menus open without exceptions', (tester) async {
    await tester.pumpWidget(_wrap());

    for (final title in ['File', 'Edit', 'View', 'Run', 'Tools', 'Help']) {
      await openMenu(tester, title);
      expect(tester.takeException(), isNull, reason: '$title threw');
      expect(
        find.byType(RetroMenuItem<String>),
        findsWidgets,
        reason: '$title has no retro rows',
      );
      await closeMenu(tester);
      expect(tester.takeException(), isNull, reason: '$title close threw');
    }
  });

  testWidgets('rows are 22px tall and separators at most 6px', (tester) async {
    await tester.pumpWidget(_wrap());
    await openMenu(tester, 'File');

    // File: 5 commands + the "Open Recent" block (empty state) + Exit.
    final rows = find.byType(RetroMenuItem<String>);
    expect(rows, findsWidgets);
    for (var i = 0; i < rows.evaluate().length; i++) {
      expect(tester.getSize(rows.at(i)).height, 22);
    }

    final separators = find.byType(RetroMenuSeparator<String>);
    expect(separators, findsWidgets);
    for (var i = 0; i < separators.evaluate().length; i++) {
      expect(tester.getSize(separators.at(i)).height, lessThanOrEqualTo(6));
    }
  });

  testWidgets('View menu checks one theme and one font, four + three', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await openMenu(tester, 'View');

    expect(find.text('Theme: VC++ 6.0'), findsOneWidget);
    expect(find.text('Theme: Borland Delphi'), findsOneWidget);
    expect(find.text('Theme: Visual Basic 6.0'), findsOneWidget);
    expect(find.text('Theme: Turbo Pascal'), findsOneWidget);
    expect(find.text('Font: Menlo'), findsOneWidget);
    expect(find.text('Font: Monaco'), findsNothing);
    expect(find.text('Font: Recursive Mono Casual'), findsOneWidget);

    var checked = _checkedLabels(tester);
    expect(checked.where((label) => label.startsWith('Theme: ')), [
      'Theme: VC++ 6.0',
    ], reason: 'exactly one theme row is checked');
    expect(checked.where((label) => label.startsWith('Font: ')), [
      'Font: Menlo',
    ], reason: 'exactly one font row is checked, and it is the default');

    await closeMenu(tester);

    // Switch the theme and reopen: the check mark must move with it.
    ThemeService.instance.switchTheme(ThemeType.delphi);
    await tester.pumpWidget(_wrap());
    await openMenu(tester, 'View');

    checked = _checkedLabels(tester);
    expect(checked.where((label) => label.startsWith('Theme: ')), [
      'Theme: Borland Delphi',
    ]);
    expect(checked.where((label) => label.startsWith('Font: ')), [
      'Font: Menlo',
    ], reason: 'a theme switch must not disturb the font choice');
  });

  testWidgets('shortcuts live in their own column, sized from the text', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await openMenu(tester, 'View');

    // Not inside the labels any more.
    expect(find.textContaining('(Cmd'), findsNothing);
    expect(find.text('Increase Font Size'), findsOneWidget);
    expect(find.text('Cmd +'), findsOneWidget);
    expect(find.text('Cmd -'), findsOneWidget);
    expect(find.text('Cmd 0'), findsOneWidget);

    final columnWidth = tester.getSize(find.text('Cmd +')).width;
    expect(columnWidth, greaterThan(0));
    expect(columnWidth, lessThanOrEqualTo(RetroMenuMetrics.maxShortcutWidth));

    // The measured column leaves room for the widest shortcut of a menu.
    final measured = RetroMenuMetrics.shortcutColumnWidth(['Cmd + S']);
    expect(
      measured,
      inInclusiveRange(
        RetroMenuMetrics.minShortcutWidth,
        RetroMenuMetrics.maxShortcutWidth,
      ),
    );

    // The longest label of any menu must not overflow its row.
    await closeMenu(tester);
    await openMenu(tester, 'Help');
    expect(tester.takeException(), isNull);
    expect(find.text('About Classic Code Editor'), findsOneWidget);
  });

  testWidgets('popup keeps sharp corners, no shadow, 2px raised frame', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());

    final button = tester.widget<PopupMenuButton<String>>(
      find.byType(PopupMenuButton<String>).first,
    );
    expect(button.shape, isA<RetroPopupShape>());
    expect(button.elevation, 0);
    expect(
      (button.shape! as RetroPopupShape).dimensions,
      const EdgeInsets.all(2),
    );

    await openMenu(tester, 'File');
    expect(_roundedOrShadowedDecoration(), findsNothing);
  });

  testWidgets('keyboard navigation highlights the focused row', (tester) async {
    await tester.pumpWidget(_wrap());
    await openMenu(tester, 'Edit');

    // Arrow keys move focus between the rows; the focused row must paint the
    // menu-active background (not only the mouse hover does).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_activeRow(), findsOneWidget);
  });
}
