import 'dart:io';
import 'dart:typed_data';

import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// Measures the **real** glyph advance and rendered line height of every font
/// family the editor offers, and pins the one invariant the gutter depends on:
/// a family's chosen strut must render exactly [EditorMetrics.lineHeight].
///
/// `flutter_tester` ships no system fonts, so a bare `TextStyle(fontFamily:
/// 'Menlo')` would be rendered with the test fallback and report meaningless
/// numbers. The fonts are therefore registered explicitly through [FontLoader]:
///
/// * `RecursiveMonoCasual` is our bundled asset (always available);
/// * `Menlo.ttc` is a *collection*; if the engine refuses it the Menlo checks
///   are skipped instead of failing on a host without Menlo.
///
/// The numbers here are a diagnostic table, not a verdict: `TextPainter.height`
/// floors the strut halves, so it can report a forced row 1-3 px shorter than
/// `lineHeight` while the editor renders it exactly. The authoritative check is
/// at widget level in `editor_font_fallback_drift_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sizes = <double>[8, 13, 32];

  /// Registers [path] under [family]; false when the host cannot provide it.
  Future<bool> register(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return false;
    final bytes = await file.readAsBytes();
    try {
      await (FontLoader(family)..addFont(
            Future<ByteData>.value(
              ByteData.sublistView(Uint8List.fromList(bytes)),
            ),
          ))
          .load();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Rendered height of one line with the given strut settings.
  double heightOf({
    required EditorMetrics metrics,
    required String fontFamily,
    required bool forceStrutHeight,
    double? height,
  }) {
    final strutHeight = height ?? metrics.lineHeightFactor;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      strutStyle: StrutStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: const <String>[EditorMetrics.fallbackFamily],
        fontSize: metrics.fontSize,
        height: strutHeight,
        forceStrutHeight: forceStrutHeight,
      ),
    )..text = TextSpan(text: '0', style: metrics.textStyle);
    painter.layout();
    final rendered = painter.height;
    painter.dispose();
    return rendered;
  }

  /// Width of one character, measured in the editor's real style.
  double advanceOf(EditorMetrics metrics) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      strutStyle: metrics.strutStyle,
    )..text = TextSpan(text: '0000000000', style: metrics.textStyle);
    painter.layout();
    final advance = painter.width / 10;
    painter.dispose();
    return advance;
  }

  test('every family renders exactly the metrics line height', () async {
    final available = <EditorFontFamily>{};
    for (final family in EditorFontFamily.values) {
      final path = switch (family) {
        EditorFontFamily.menlo => '/System/Library/Fonts/Menlo.ttc',
        EditorFontFamily.recursive =>
          'assets/fonts/RecursiveMonoCslSt-Regular.ttf',
      };
      if (await register(family.fontFamily, path)) {
        available.add(family);
      } else {
        // ignore: avoid_print
        print('SKIP ${family.id}: could not load $path');
      }
    }

    // The bundled faces must always be measurable - they ship with the app.
    expect(
      available,
      contains(EditorFontFamily.recursive),
      reason: 'the bundled Recursive asset must load',
    );

    final rows = <String>[];
    for (final family in available) {
      for (final size in sizes) {
        final metrics = EditorMetrics.forFontSize(size, family: family);

        final strutHeight = metrics.strutStyle.height ?? 0;

        // `TextPainter.height` with the strut the metrics chose. A painter can
        // report a forced row 1-3px SHORT of lineHeight even though the editor
        // renders it exactly: the painter floors the strut's ascent and descent
        // halves separately, while `RenderEditable` rounds `fontSize * height`.
        // This column is therefore reported, not asserted - asserting it is what
        // made an earlier "fix" wrong. The real invariant is measured on a live
        // EditableText in editor_font_fallback_drift_test.dart.
        final forced = heightOf(
          metrics: metrics,
          fontFamily: family.fontFamily,
          forceStrutHeight: true,
          height: strutHeight,
        );
        // What an unforced strut renders for ASCII: equal to lineHeight for
        // every family, which is why ASCII-only tests never saw the bug.
        final soft = heightOf(
          metrics: metrics,
          fontFamily: family.fontFamily,
          forceStrutHeight: false,
        );
        final advance = advanceOf(metrics);

        rows.add(
          '${family.id.padRight(10)} size=${size.toStringAsFixed(0).padLeft(2)} '
          'advance=${advance.toStringAsFixed(4)} '
          'painterForced=${forced.toStringAsFixed(2)} '
          'painterSoft=${soft.toStringAsFixed(2)} '
          'lineHeight=${metrics.lineHeight.toStringAsFixed(2)} '
          'factor=${strutHeight.toStringAsFixed(4)} '
          '(canonical ${metrics.lineHeightFactor.toStringAsFixed(4)})',
        );

        // The strut is forced for every family - the one thing that makes the
        // row immune to the fallback font of a Persian glyph.
        expect(metrics.strutStyle.forceStrutHeight, isTrue);
        expect(
          metrics.strutStyle.height,
          closeTo(metrics.lineHeightFactor, 1e-9),
        );

        // For ASCII, even an unforced strut lands on lineHeight.
        expect(
          soft,
          closeTo(metrics.lineHeight, 0.01),
          reason:
              '${family.id} at $size: ASCII rows must be lineHeight even '
              'unforced',
        );

        // A monospace advance must land near 0.6em, so a family can never
        // silently fall back to the proportional test font.
        expect(
          advance,
          greaterThan(size * 0.5),
          reason: '${family.id} advance',
        );
        expect(advance, lessThan(size * 0.8), reason: '${family.id} advance');
      }
    }

    // ignore: avoid_print
    print('MEASURED EDITOR FONTS\n${rows.join('\n')}');
  });
}
