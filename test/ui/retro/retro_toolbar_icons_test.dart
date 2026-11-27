import 'package:classic_code_editor/ui/retro/retro_toolbar_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every pixel icon is a 16x16 grid of palette symbols', () {
    for (final type in RetroToolbarIconType.values) {
      final rows = retroToolbarIconRows(type);
      if (rows == null) continue;
      expect(rows, hasLength(16), reason: type.name);
      for (var y = 0; y < rows.length; y++) {
        expect(rows[y].length, 16, reason: '${type.name} row $y');
        for (final symbol in rows[y].split('')) {
          expect(
            isRetroIconPaletteSymbol(symbol),
            isTrue,
            reason: '${type.name} row $y has "$symbol"',
          );
        }
      }
      // An icon must draw something.
      expect(rows.join().replaceAll('.', ''), isNotEmpty, reason: type.name);
    }
  });

  test('Undo, Redo and the Debug bug are vector drawings, not pixels', () {
    expect(retroToolbarIconRows(RetroToolbarIconType.undo), isNull);
    expect(retroToolbarIconRows(RetroToolbarIconType.redo), isNull);
    expect(retroToolbarIconRows(RetroToolbarIconType.debug), isNull);
  });

  test('Run is green and Stop is red', () {
    String colors(RetroToolbarIconType type) =>
        retroToolbarIconRows(type)!.join().replaceAll('.', '');
    expect(colors(RetroToolbarIconType.run), matches(RegExp(r'^G+$')));
    expect(colors(RetroToolbarIconType.stop), matches(RegExp(r'^r+$')));
  });

  test('pixel icons are shifted to the middle of their cell', () {
    for (final type in RetroToolbarIconType.values) {
      final rows = retroToolbarIconRows(type);
      if (rows == null) continue;
      final shift = centeringShift(rows);
      var top = 16, bottom = -1, left = 16, right = -1;
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          if (rows[y][x] == '.') continue;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
          if (x < left) left = x;
          if (x > right) right = x;
        }
      }
      final spaceAbove = top + shift.dy;
      final spaceBelow = 15 - (bottom + shift.dy);
      final spaceLeft = left + shift.dx;
      final spaceRight = 15 - (right + shift.dx);
      // Equal margins, or one pixel apart when the size is odd.
      expect(
        (spaceAbove - spaceBelow).abs(),
        lessThanOrEqualTo(1),
        reason: type.name,
      );
      expect(
        (spaceLeft - spaceRight).abs(),
        lessThanOrEqualTo(1),
        reason: type.name,
      );
    }
  });

  testWidgets('every icon paints without errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (final type in RetroToolbarIconType.values)
              RetroToolbarIcon(type),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
