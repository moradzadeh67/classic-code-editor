import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:flutter/material.dart';

/// Pure value class that computes all editor/gutter metrics from a single
/// [fontSize] and [family]. Every measurement is a whole logical pixel so the
/// gutter's `itemExtent` and the code's line-height stay pixel-identical.
@immutable
class EditorMetrics {
  final double fontSize;
  final double lineHeight;
  final double lineHeightFactor;
  final double letterSpacing;
  final double gutterWidth;
  final double markerSlotWidth;
  final double markerFontSize;
  final double lineNumberFontSize;
  final TextStyle textStyle;
  final StrutStyle strutStyle;

  /// The choice this metrics object was built for (persisted id, menu label).
  final EditorFontFamily family;

  /// The family name Flutter resolves, i.e. [EditorFontFamily.fontFamily].
  final String fontFamily;

  const EditorMetrics({
    required this.fontSize,
    required this.lineHeight,
    required this.lineHeightFactor,
    required this.letterSpacing,
    required this.gutterWidth,
    required this.markerSlotWidth,
    required this.markerFontSize,
    required this.lineNumberFontSize,
    required this.textStyle,
    required this.strutStyle,
    required this.family,
    required this.fontFamily,
  });

  /// Code ligatures are off for every family.
  ///
  /// A code editor must keep `--`, `->`, `!=` and `<=` as separate glyphs: with
  /// `calt`/`liga` enabled the paragraph's width would also stop being a whole
  /// multiple of one advance, and the gutter's wrap gate relies on exactly that.
  static const List<FontFeature> noLigatures = <FontFeature>[
    FontFeature.disable('calt'),
    FontFeature.disable('liga'),
  ];

  /// Menlo is the editor's default and its own family name is used directly.
  static const String fallbackFamily = 'Menlo';

  factory EditorMetrics.forFontSize(
    double fontSize, {
    EditorFontFamily family = EditorFontFamily.menlo,
  }) {
    final lineHeight = (fontSize * 19 / 13).roundToDouble();
    final lineHeightFactor = lineHeight / fontSize;
    final gutterW = (52 * fontSize / 13).roundToDouble();
    final gutterWidthValue = gutterW > 52 ? gutterW : 52.0;
    final markerSlotW = (22 * fontSize / 13).roundToDouble();
    final markerSlotWidthValue = markerSlotW > 22 ? markerSlotW : 22.0;
    final markerFont = (12 * fontSize / 13).roundToDouble().clamp(10.0, 30.0);
    final lineNumberFont = (11 * fontSize / 13).roundToDouble().clamp(
      8.0,
      28.0,
    );

    final text = TextStyle(
      fontFamily: family.fontFamily,
      // Menlo is the editor's historic face and stays the last resort if a
      // bundled face ever misses a glyph.
      fontFamilyFallback: const <String>[fallbackFamily],
      fontSize: fontSize,
      height: lineHeightFactor,
      letterSpacing: 0.5,
      fontFeatures: noLigatures,
    );
    // The strut is *always* forced, at the plain `lineHeight / fontSize`
    // factor. See [forceStrutHeight].
    final strut = StrutStyle(
      fontFamily: family.fontFamily,
      fontFamilyFallback: const <String>[fallbackFamily],
      fontSize: fontSize,
      height: lineHeightFactor,
      forceStrutHeight: forceStrutHeight,
    );

    return EditorMetrics(
      fontSize: fontSize,
      lineHeight: lineHeight,
      lineHeightFactor: lineHeightFactor,
      letterSpacing: 0.5,
      gutterWidth: gutterWidthValue,
      markerSlotWidth: markerSlotWidthValue,
      markerFontSize: markerFont,
      lineNumberFontSize: lineNumberFont,
      textStyle: text,
      strutStyle: strut,
      family: family,
      fontFamily: family.fontFamily,
    );
  }

  /// Why the strut is forced for **every** family, at the plain
  /// `lineHeight / fontSize` factor.
  ///
  /// The row height of a code line has to equal [lineHeight], because the
  /// gutter rows, the current-line band, scrolling and click-to-line mapping all
  /// assume it. Two measurements from the real macOS runtime decide this:
  ///
  /// * **Unforced is unsafe.** Without `forceStrutHeight` the row is set by the
  ///   font of whichever glyph is on the line, so a line containing Persian text
  ///   fell back to another face and grew the row (measured: +1 px per such line
  ///   at sizes 8/13 and +2 px at 32). Over a 1000-line file the caret of line
  ///   400 ended up 400-800 px below where the gutter had reserved space - "the
  ///   code drifts away from the gutter".
  /// * **Forced is exact.** With the strut forced, the same documents kept a
  ///   perfectly uniform grid for both families, verified over 1000 lines with
  ///   ASCII, Persian and mixed lines interleaved, at sizes 8/13/32 - see
  ///   `test/ui/editor/editor_font_fallback_drift_test.dart`.
  ///
  /// Do **not** "fix" the strut factor per family: `TextPainter.height` floors
  /// the strut's ascent and descent halves separately, so a painter can report a
  /// forced row 1-3 px shorter than [lineHeight], while the editor's own
  /// `RenderEditable` rounds `fontSize * height` and renders it exactly.
  /// Calibrating the factor for the painter is what once made the editor render
  /// 20 px rows at size 13 and 50 px at size 32 - the drift it meant to cure.
  /// The invariant is asserted at widget level, on a real `EditableText`.
  static const bool forceStrutHeight = true;

  static final EditorMetrics standard = EditorMetrics.forFontSize(13);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorMetrics &&
          runtimeType == other.runtimeType &&
          fontSize == other.fontSize &&
          family == other.family;

  @override
  int get hashCode => Object.hash(fontSize, family);

  @override
  String toString() =>
      'EditorMetrics(size: $fontSize, family: ${family.id}, '
      'lineHeight: $lineHeight)';
}
