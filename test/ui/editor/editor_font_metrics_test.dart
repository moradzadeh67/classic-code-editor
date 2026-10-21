import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// R2: every measurement still comes from [fontSize] alone, and the family only
/// decides which face is painted - so the whole 19/13 line-height rule, the
/// gutter width and the marker sizes are unchanged for all three fonts.
void main() {
  group('EditorMetrics family plumbing', () {
    test('the resolved family name reaches textStyle and strutStyle', () {
      for (final family in EditorFontFamily.values) {
        final m = EditorMetrics.forFontSize(13, family: family);
        expect(
          m.fontFamily,
          family.fontFamily,
          reason: '${family.id} must resolve to ${family.fontFamily}',
        );
        expect(m.textStyle.fontFamily, family.fontFamily);
        expect(m.strutStyle.fontFamily, family.fontFamily);
        expect(m.family, family);
      }
    });

    test('Menlo remains the fallback for every family', () {
      for (final family in EditorFontFamily.values) {
        final m = EditorMetrics.forFontSize(13, family: family);
        expect(m.textStyle.fontFamilyFallback, contains('Menlo'));
        expect(m.strutStyle.fontFamilyFallback, contains('Menlo'));
      }
    });

    test('code ligatures are disabled for every family', () {
      for (final family in EditorFontFamily.values) {
        final m = EditorMetrics.forFontSize(13, family: family);
        final features = m.textStyle.fontFeatures ?? const <FontFeature>[];
        expect(
          features.map((f) => f.feature),
          containsAll(<String>['calt', 'liga']),
          reason: '${family.id} must not ligate',
        );
        for (final feature in features) {
          expect(
            feature.value,
            0,
            reason: '${feature.feature} must be *disabled*, not enabled',
          );
        }
      }
    });

    test('the default family is menlo and equals the standard metrics', () {
      expect(
        EditorMetrics.forFontSize(13),
        EditorMetrics.forFontSize(13, family: EditorFontFamily.menlo),
      );
      expect(EditorMetrics.standard.family, EditorFontFamily.menlo);
      expect(EditorMetrics.standard.fontFamily, 'Menlo');
    });

    test('the line-height rule is family-independent and unchanged', () {
      // The values "standard equals default-13 metrics" already pins, plus the
      // whole-pixel rule across the slider range - for *all three* families.
      for (final family in EditorFontFamily.values) {
        expect(EditorMetrics.forFontSize(13, family: family).lineHeight, 19);
        for (int size = 8; size <= 32; size++) {
          final m = EditorMetrics.forFontSize(size.toDouble(), family: family);
          expect(
            m.lineHeight,
            m.lineHeight.roundToDouble(),
            reason: '${family.id} at $size: line height must be whole pixels',
          );
          expect(
            m.lineHeight,
            closeTo(size * 19 / 13, 0.5),
            reason: '${family.id} at $size: must stay on the 19/13 rule',
          );
          expect(
            (m.fontSize * m.lineHeightFactor - m.lineHeight).abs(),
            lessThan(1e-9),
            reason: '${family.id} at $size: the factor must be the exact ratio',
          );
        }
      }
    });

    test('gutter and marker measurements do not depend on the family', () {
      for (final size in <double>[8, 13, 20, 32]) {
        final menlo = EditorMetrics.forFontSize(size);
        for (final family in <EditorFontFamily>[EditorFontFamily.recursive]) {
          final other = EditorMetrics.forFontSize(size, family: family);
          expect(other.lineHeight, menlo.lineHeight);
          expect(other.lineHeightFactor, menlo.lineHeightFactor);
          expect(other.gutterWidth, menlo.gutterWidth);
          expect(other.markerSlotWidth, menlo.markerSlotWidth);
          expect(other.markerFontSize, menlo.markerFontSize);
          expect(other.lineNumberFontSize, menlo.lineNumberFontSize);
          expect(other.letterSpacing, menlo.letterSpacing);
        }
      }
    });

    test('equality and hashCode include the family', () {
      final menlo = EditorMetrics.forFontSize(16);
      final sameMenlo = EditorMetrics.forFontSize(16);
      final recursive = EditorMetrics.forFontSize(
        16,
        family: EditorFontFamily.recursive,
      );
      final bigger = EditorMetrics.forFontSize(20);

      expect(menlo == sameMenlo, isTrue);
      expect(menlo.hashCode, sameMenlo.hashCode);

      // Same size, different face: these are *different* metrics, otherwise the
      // panel would skip the repaint and keep the old glyph advance.
      expect(menlo == recursive, isFalse);
      expect(menlo.hashCode, isNot(recursive.hashCode));

      expect(menlo == bigger, isFalse);
      expect(recursive == bigger, isFalse);
      expect(menlo == Object(), isFalse);
    });

    test('toString names the family, for debugging drift reports', () {
      expect(
        EditorMetrics.forFontSize(
          13,
          family: EditorFontFamily.recursive,
        ).toString(),
        contains('recursive'),
      );
    });
  });

  group('strut rule', () {
    test('every family forces the strut', () {
      // Forcing is what makes a row immune to the fallback font. Without it a
      // Persian glyph grew Monaco's rows by 1px (2px at size 32) and the gutter
      // drifted ~4 rows by line 400.
      for (final family in EditorFontFamily.values) {
        expect(
          EditorMetrics.forFontSize(
            13,
            family: family,
          ).strutStyle.forceStrutHeight,
          isTrue,
          reason: '${family.id} must force the strut',
        );
      }
    });

    test('every family keeps the plain lineHeight/fontSize factor', () {
      // The factor is never tweaked per family. `TextPainter.height` floors the
      // strut halves and made a forced Monaco look 1-3px short, but the editor's
      // RenderEditable rounds `fontSize * height`: calibrating for the painter
      // made the real editor render 20px rows at size 13 and 50px at size 32.
      // That is why the exactness invariant is asserted on a real EditableText
      // in editor_font_fallback_drift_test.dart, not here.
      for (final family in EditorFontFamily.values) {
        final m = EditorMetrics.forFontSize(13, family: family);
        expect(
          m.strutStyle.height,
          closeTo(m.lineHeightFactor, 1e-9),
          reason: '${family.id} must keep the canonical strut factor',
        );
        expect(
          m.textStyle.height,
          closeTo(m.lineHeightFactor, 1e-9),
          reason: '${family.id} must keep the canonical text height',
        );
      }
    });

    test('the panel-smoke constant is untouched', () {
      // Existing tests reference these; the family work must not move them.
      expect(editorFontSize, 13.0);
      expect(editorLineHeight, 19.0);
      expect(editorLineHeightFactor, 19.0 / 13.0);
    });
  });
}
