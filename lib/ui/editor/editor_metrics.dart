import 'package:flutter/material.dart';

/// Pure value class that computes all editor/gutter metrics from a single
/// [fontSize]. Every measurement is a whole logical pixel so the gutter's
/// `itemExtent` and the code's line-height stay pixel-identical.
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
  });

  factory EditorMetrics.forFontSize(double fontSize) {
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
      fontFamily: 'Menlo',
      fontSize: fontSize,
      height: lineHeightFactor,
      letterSpacing: 0.5,
    );
    final strut = StrutStyle(
      fontFamily: 'Menlo',
      fontSize: fontSize,
      height: lineHeightFactor,
      forceStrutHeight: true,
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
    );
  }

  static final EditorMetrics standard = EditorMetrics.forFontSize(13);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorMetrics &&
          runtimeType == other.runtimeType &&
          fontSize == other.fontSize;

  @override
  int get hashCode => fontSize.hashCode;
}
