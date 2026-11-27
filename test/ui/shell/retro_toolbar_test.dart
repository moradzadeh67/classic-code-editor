import 'package:classic_code_editor/services/theme_service.dart';
import 'package:classic_code_editor/ui/shell/retro_toolbar.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> pressed;

  Future<void> pumpToolbar(WidgetTester tester) async {
    pressed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: RetroToolbar(
              onUndo: () => pressed.add('undo'),
              onRedo: () => pressed.add('redo'),
              onCut: () => pressed.add('cut'),
              onCopy: () => pressed.add('copy'),
              onPaste: () => pressed.add('paste'),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester, String name) {
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byKey(ValueKey<String>('toolbar-$name')),
        matching: find.byType(Container),
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('edit buttons call their callbacks', (tester) async {
    await pumpToolbar(tester);
    for (final name in <String>['cut', 'copy', 'paste', 'undo', 'redo']) {
      await tester.tap(find.byKey(ValueKey<String>('toolbar-$name')));
      await tester.pump();
    }
    expect(pressed, <String>['cut', 'copy', 'paste', 'undo', 'redo']);
  });

  testWidgets('buttons are raised at rest and sunken while pressed', (
    tester,
  ) async {
    await pumpToolbar(tester);
    final colors = ThemeService.instance.colors;

    final rest = decorationOf(tester, 'save').border! as Border;
    expect(rest.top.color, colors.borderLight);
    expect(rest.bottom.color, colors.borderDark);

    final press = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('toolbar-save'))),
    );
    // A tap reports "down" only after the press timeout.
    await tester.pump(kPressTimeout);
    final down = decorationOf(tester, 'save').border! as Border;
    expect(down.top.color, colors.borderDark);
    expect(down.bottom.color, colors.borderLight);

    await press.up();
    await tester.pump();
    final up = decorationOf(tester, 'save').border! as Border;
    expect(up.top.color, colors.borderLight);
  });

  testWidgets('buttons sit 4px below the top and 1px above the bottom', (
    tester,
  ) async {
    await pumpToolbar(tester);
    final bar = tester.getRect(find.byType(RetroToolbar));
    for (final name in <String>['open', 'save', 'cut', 'undo', 'redo', 'run']) {
      final button = tester.getRect(
        find.byKey(ValueKey<String>('toolbar-$name')),
      );
      expect(button.top - bar.top, 4, reason: name);
      expect(bar.bottom - button.bottom, 1, reason: name);
      // And the icon is in the middle of its button.
      final icon = tester.getRect(
        find.descendant(
          of: find.byKey(ValueKey<String>('toolbar-$name')),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(icon.center.dy, closeTo(button.center.dy, 0.5), reason: name);
    }
  });
}
