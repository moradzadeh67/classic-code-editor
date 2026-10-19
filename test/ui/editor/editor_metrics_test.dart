import 'package:flutter_test/flutter_test.dart';

import 'package:classic_code_editor/ui/editor/editor_metrics.dart';

void main() {
  group('EditorMetrics', () {
    test('standard equals default-13 metrics', () {
      final m = EditorMetrics.standard;
      expect(m.fontSize, 13);
      expect(m.lineHeight, 19);
      expect(m.gutterWidth, 52);
      expect(m.markerSlotWidth, 22);
      expect(m.markerFontSize, 12);
      expect(m.lineNumberFontSize, 11);
      expect(m.lineHeightFactor, 19 / 13);
      expect(m.letterSpacing, 0.5);
    });

    test('lineHeight is whole number for every integer 8..32', () {
      for (int s = 8; s <= 32; s++) {
        final m = EditorMetrics.forFontSize(s.toDouble());
        expect(
          m.lineHeight,
          equals(m.lineHeight.toInt().toDouble()),
          reason: 'size $s lineHeight should be whole',
        );
      }
    });

    test('lineHeight never decreases as size grows', () {
      double prev = 0;
      for (int s = 8; s <= 32; s++) {
        final lh = EditorMetrics.forFontSize(s.toDouble()).lineHeight;
        expect(
          lh,
          greaterThanOrEqualTo(prev),
          reason: 'lineHeight must not decrease at size $s',
        );
        prev = lh;
      }
    });

    test('fontSize * factor approximates lineHeight within 1e-9', () {
      for (int s = 8; s <= 32; s++) {
        final m = EditorMetrics.forFontSize(s.toDouble());
        expect(
          (m.fontSize * m.lineHeightFactor - m.lineHeight).abs(),
          lessThan(1e-9),
          reason: 'mismatch at size $s',
        );
      }
    });

    test('lineHeight vectors match expected values', () {
      final expectations = {8: 12, 10: 15, 16: 23, 20: 29, 24: 35, 32: 47};
      for (final entry in expectations.entries) {
        final m = EditorMetrics.forFontSize(entry.key.toDouble());
        expect(
          m.lineHeight,
          entry.value,
          reason: 'lineHeight at size ${entry.key}',
        );
      }
    });

    test('gutter and marker slot scale with minimums', () {
      final m20 = EditorMetrics.forFontSize(20);
      expect(m20.gutterWidth, 80); // 52*20/13 = 80
      expect(m20.markerSlotWidth, 34); // 22*20/13 ≈ 33.8 -> 34

      final m32 = EditorMetrics.forFontSize(32);
      expect(m32.gutterWidth, 128); // 52*32/13 = 128
      expect(m32.markerSlotWidth, 54); // 22*32/13 ≈ 54.15 -> 54
    });

    test('markerFontSize and lineNumberFontSize clamped correctly', () {
      final m8 = EditorMetrics.forFontSize(8);
      expect(m8.markerFontSize, 10); // clamped lower
      expect(m8.lineNumberFontSize, 8); // clamped lower (11*8/13 ≈ 6.7 -> 8)

      final m32 = EditorMetrics.forFontSize(32);
      expect(m32.markerFontSize, 30); // clamped upper
      expect(m32.lineNumberFontSize, 27); // 11*32/13 ≈ 27.07 -> 27
    });

    test('equals and hashCode based on fontSize only', () {
      final a = EditorMetrics.forFontSize(16);
      final b = EditorMetrics.forFontSize(16);
      final c = EditorMetrics.forFontSize(20);
      expect(a == b, isTrue);
      expect(a.hashCode == b.hashCode, isTrue);
      expect(a == c, isFalse);
    });

    test(
      'textStyle and strutStyle share same family, size, height, spacing',
      () {
        final m = EditorMetrics.forFontSize(13);
        expect(m.textStyle.fontFamily, 'Menlo');
        expect(m.strutStyle.fontFamily, 'Menlo');
        expect(m.textStyle.fontSize, 13);
        expect(m.strutStyle.fontSize, 13);
        expect(m.textStyle.height, m.strutStyle.height);
        expect(m.textStyle.letterSpacing, 0.5);
        expect(m.strutStyle.forceStrutHeight, isTrue);
      },
    );
  });
}
