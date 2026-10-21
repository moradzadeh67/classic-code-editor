// Font-drift probe - the measurement instrument for the PHASE 22 follow-up.
//
//   flutter run -d macos -t tool/probe_font_drift.dart
//
// `flutter test` cannot answer these questions: `flutter_tester` has no system
// fonts and no CoreText, so it never sees how macOS resolves Menlo/Monaco, nor
// how a *fallback* font is used for Persian glyphs.
//
// It has two phases on purpose:
//
//   1. PAINTER phase - a TextPainter with the editor's TextStyle/StrutStyle.
//      Useful, but `TextPainter.height` floors the strut's ascent and descent
//      halves separately, so a forced Monaco looks 1-3 px short here even when
//      the editor renders it correctly. Read it as a diagnostic, not a verdict.
//   2. WIDGET phase - the same styles inside a real TextField, measured through
//      RenderEditable caret rects. This is what the app actually shows, and it
//      is the only column that decides whether the gutter can be aligned.
//
// Both phases use generated 1000-line documents of ASCII, Persian and mixed
// lines and print the caret top of lines 1/100/400/1000 next to the expected
// `(n - 1) * lineHeight`.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

/// Which text a case lays out.
enum TextKind {
  ascii('ascii'),
  persian('persian'),
  mixed('mixed');

  const TextKind(this.label);

  final String label;

  /// One line of this kind, for line number [i] (1-based).
  String line(int i) => switch (this) {
    ascii => 'final value$i = $i;',
    persian => '// سلام دنیا شماره $i - متن آزمایشی فارسی',
    mixed => 'final s$i = "متن فارسی $i"; // trailing ascii comment',
  };

  /// A document of [lines] lines, every tenth of them [other] when given.
  String document(int lines, {TextKind? other}) => List<String>.generate(
    lines,
    (i) => (other != null && i % 10 == 9 ? other : this).line(i + 1),
  ).join('\n');
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  static const List<double> _sizes = <double>[8, 13, 32];
  static const List<int> _probeLines = <int>[1, 100, 400, 1000];
  static const int _documentLines = 1000;

  /// The four sample points the drift shows up at.
  final Map<int, double> _tops = <int, double>{};

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();

  /// Cases: family x size x text.
  late final List<(EditorFontFamily, double, TextKind)> _cases =
      <(EditorFontFamily, double, TextKind)>[
        for (final family in EditorFontFamily.values)
          for (final size in _sizes)
            for (final kind in TextKind.values) (family, size, kind),
      ];

  int _index = 0;
  EditorMetrics? _metrics;

  @override
  void initState() {
    super.initState();
    // Let the engine load fonts and lay out the first frame, then measure.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _runPainterPhase();
      _mountNextCase();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics;
    if (metrics == null) return const SizedBox.shrink();
    // Same configuration as code_editor_panel.dart's editor TextField.
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          // Wide on purpose: a Persian line is proportional in the fallback
          // font and can be far wider than 0.6em/char, so a narrow field would
          // wrap and make this a wrapping test instead of a row-height test.
          width: 9000,
          height: 900,
          child: TextField(
            key: _fieldKey,
            controller: _controller,
            focusNode: _focusNode,
            maxLines: null,
            expands: true,
            strutStyle: metrics.strutStyle,
            style: metrics.textStyle,
            decoration: const InputDecoration.collapsed(hintText: ''),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ driver

  void _mountNextCase() {
    if (_index >= _cases.length) {
      print('=== END PROBE (widget phase clean) ===');
      exit(0);
    }
    final (family, size, kind) = _cases[_index];
    _metrics = EditorMetrics.forFontSize(size, family: family);
    // Mostly `kind`, every tenth line the other kind: the fallback path must be
    // exercised in a document that is otherwise uniform.
    _controller.text = kind.document(
      _documentLines,
      other: kind == TextKind.persian ? TextKind.ascii : TextKind.persian,
    );
    _tops.clear();
    setState(() {});
    SchedulerBinding.instance.addPostFrameCallback((_) => _measureCase());
  }

  void _measureCase() {
    final (family, size, kind) = _cases[_index];
    final metrics = _metrics!;
    final editable = _findRenderEditable(_fieldKey.currentContext);
    if (editable == null) {
      print(
        '[${family.id} size=${size.toInt()} ${kind.label}] no RenderEditable',
      );
      _advance();
      return;
    }

    final text = _controller.text;
    for (final n in _probeLines) {
      final rect = editable.getLocalRectForCaret(
        TextPosition(offset: _offsetOfLine(text, n)),
      );
      _tops[n] = rect.top;
    }

    final origin = _tops[1]!;
    final parts = <String>[];
    var worst = 0.0;
    var wrapped = false;
    for (final n in _probeLines) {
      final expected = (n - 1) * metrics.lineHeight;
      final actual = _tops[n]! - origin;
      final delta = actual - expected;
      // A wrapped document makes a logical line occupy two rows, so the caret
      // is a whole number of rows further down. Flag it rather than call it
      // drift: the grid itself is still uniform.
      if ((delta / metrics.lineHeight - (delta / metrics.lineHeight).round())
              .abs() >
          0.01) {
        if (delta.abs() > worst.abs()) worst = delta;
      } else if (delta.abs() > 0.5) {
        wrapped = true;
      }
      parts.add(
        'L$n d=${_signed(delta)} '
        '(got ${actual.toStringAsFixed(1)} exp ${expected.toStringAsFixed(1)})',
      );
    }

    final verdict = worst.abs() >= 0.5
        ? 'DRIFT'
        : wrapped
        ? 'WRAP '
        : 'OK   ';
    print(
      '$verdict '
      '[${family.id} size=${size.toInt()} ${kind.label}] '
      'lineHeight=${metrics.lineHeight.toStringAsFixed(0)} | '
      '${parts.join('  ')}',
    );
    _advance();
  }

  void _advance() {
    _index++;
    _mountNextCase();
  }

  /// The RenderEditable inside the probed TextField.
  RenderEditable? _findRenderEditable(BuildContext? context) {
    final root = context?.findRenderObject();
    if (root == null) return null;
    RenderEditable? found;
    void walk(RenderObject node) {
      if (found != null) return;
      if (node is RenderEditable) {
        found = node;
        return;
      }
      node.visitChildren(walk);
    }

    walk(root);
    return found;
  }

  int _offsetOfLine(String text, int oneBasedLine) {
    var offset = 0;
    for (var i = 1; i < oneBasedLine; i++) {
      final nl = text.indexOf('\n', offset);
      if (nl < 0) return 0;
      offset = nl + 1;
    }
    return offset;
  }

  static String _signed(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';

  // ----------------------------------------------------------- painter phase

  static void _runPainterPhase() {
    print('=== FONT DRIFT PROBE (real macOS runtime) ===');
    print(
      'platform=${Platform.operatingSystem} '
      'flutter=${Platform.environment['FLUTTER_ROOT'] ?? '?'}',
    );
    print(
      '--- painter phase (diagnostic only: TextPainter floors the strut '
      'halves) ---',
    );

    for (final size in _sizes) {
      for (final family in EditorFontFamily.values) {
        final m = EditorMetrics.forFontSize(size, family: family);
        final forced = _rowHeight(m, force: true);
        final soft = _rowHeight(m, force: false);
        print(
          '[${family.id} size=${size.toInt()}] '
          'lineHeight=${m.lineHeight.toStringAsFixed(2)} '
          'factor=${m.lineHeightFactor.toStringAsFixed(4)} '
          'painterForced=${forced.toStringAsFixed(2)} '
          'painterSoft=${soft.toStringAsFixed(2)} '
          'forcedStrut=${m.strutStyle.forceStrutHeight}',
        );
      }
    }
    print(
      '--- widget phase (authoritative: caret rects of a real TextField) ---',
    );
  }

  static double _rowHeight(EditorMetrics m, {required bool force}) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      strutStyle: StrutStyle(
        fontFamily: m.fontFamily,
        fontFamilyFallback: const <String>[EditorMetrics.fallbackFamily],
        fontSize: m.fontSize,
        height: m.lineHeightFactor,
        forceStrutHeight: force,
      ),
    )..text = TextSpan(text: 'X', style: m.textStyle);
    painter.layout();
    final row = painter.height;
    painter.dispose();
    return row;
  }
}
