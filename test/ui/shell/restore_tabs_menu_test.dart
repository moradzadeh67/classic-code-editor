import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/theme_service.dart';
import 'package:classic_code_editor/ui/shell/retro_menu_bar.dart';
import 'package:classic_code_editor/ui/shell/retro_menu_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// TASK-055: View > "Restore Tabs on Launch" is a persisted check-mark toggle.
///
/// The rows are built in `itemBuilder`, so the mark must follow the live
/// setting even though the bar itself never rebuilds.
void main() {
  const label = 'Restore Tabs on Launch';

  setUp(() {
    ThemeService.instance.switchTheme(ThemeType.vc6);
    EditorSettingsService.instance.setRestoreTabsOnLaunch(false);
  });

  tearDown(() {
    EditorSettingsService.instance.setRestoreTabsOnLaunch(false);
    ThemeService.instance.switchTheme(ThemeType.vc6);
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

  bool? checked(WidgetTester tester) => tester
      .widgetList<RetroMenuItem<String>>(find.byType(RetroMenuItem<String>))
      .firstWhere((row) => row.label == label)
      .checked;

  testWidgets('lives in View and reflects the setting', (tester) async {
    await tester.pumpWidget(wrap());
    await openView(tester);

    expect(find.text(label), findsOneWidget);
    expect(checked(tester), isFalse);
  });

  testWidgets('selecting it turns restoring on, and the mark follows', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await openView(tester);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();

    expect(EditorSettingsService.instance.restoreTabsOnLaunch, isTrue);

    // Reopening is the real path: no rebuild of the bar happens in between.
    await openView(tester);
    expect(checked(tester), isTrue);

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(EditorSettingsService.instance.restoreTabsOnLaunch, isFalse);
  });
}
