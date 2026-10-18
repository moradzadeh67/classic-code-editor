import 'package:classic_code_editor/utils/app_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('zoomActionFor', () {
    test('increase keys with modifier', () {
      expect(zoomActionFor(LogicalKeyboardKey.equal, commandOrControl: true),
          EditorZoomAction.increase);
      expect(
          zoomActionFor(LogicalKeyboardKey.numpadAdd, commandOrControl: true),
          EditorZoomAction.increase);
    });

    test('decrease keys with modifier', () {
      expect(
          zoomActionFor(LogicalKeyboardKey.minus, commandOrControl: true),
          EditorZoomAction.decrease);
      expect(
          zoomActionFor(LogicalKeyboardKey.numpadSubtract,
              commandOrControl: true),
          EditorZoomAction.decrease);
    });

    test('reset keys with modifier', () {
      expect(
          zoomActionFor(LogicalKeyboardKey.digit0, commandOrControl: true),
          EditorZoomAction.reset);
      expect(
          zoomActionFor(LogicalKeyboardKey.numpad0, commandOrControl: true),
          EditorZoomAction.reset);
    });

    test('ignores without modifier', () {
      expect(
          zoomActionFor(LogicalKeyboardKey.equal, commandOrControl: false),
          isNull);
    });

    test('ignores shift modifier only', () {
      // The spec says ignore Shift because Cmd + is Cmd+Shift+= on US Mac.
      // Our helper only checks commandOrControl, not Shift, so Shift alone
      // should return null.
      expect(
          zoomActionFor(LogicalKeyboardKey.equal, commandOrControl: false),
          isNull);
    });

    test('ignores unrelated keys', () {
      expect(zoomActionFor(LogicalKeyboardKey.keyA, commandOrControl: true),
          isNull);
    });
  });
}
