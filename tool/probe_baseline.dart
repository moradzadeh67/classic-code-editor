// Baseline probe - measures the *painted* baselines of the gutter digits and of
// the code, in the real macOS app (CoreText), because that is where the 1px
// offset is visible. `flutter_tester` loads the same fonts but not through the
// platform, and the numbers came out ±1px different there.
//
//   flutter run -d macos -t tool/probe_baseline.dart
//
// For every font and size it prints the last inked row of the digit and of the
// code on the same visual row. Digits and capitals have no descender, so the
// last inked row *is* the baseline: a positive delta means the number sits lower
// than the code.
//
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/editor_settings_service.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:classic_code_editor/ui/editor/editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

class _QuietLspService extends LspService {
  @override
  bool get isConnected => false;

  @override
  Future<List<CompletionItem>> requestCompletion(
    String filePath,
    int line,
    int column,
  ) async => const <CompletionItem>[];

  @override
  Future<HoverInfo?> requestHover(
    String filePath,
    int line,
    int column,
  ) async => null;
}

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  static const List<double> _sizes = <double>[8, 13, 32];
  static const String _text = 'aaaa;\nbbbb;\nMMMM;\nWWWW;\n';

  final FileService _fileService = FileService();
  final LspService _lsp = _QuietLspService();
  final GlobalKey _boundary = GlobalKey();
  final GlobalKey<CodeEditorPanelState> _panel = GlobalKey();

  late final List<(EditorFontFamily, double)> _cases =
      <(EditorFontFamily, double)>[
        for (final family in EditorFontFamily.values)
          for (final size in _sizes) (family, size),
      ];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _fileService.openFilePath('/tmp/probe_baseline.cpp', _text);
    SchedulerBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _fileService.dispose();
    _lsp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: RepaintBoundary(
        key: _boundary,
        child: SizedBox(
          width: 700,
          height: 500,
          child: CodeEditorPanel(
            key: _panel,
            fileService: _fileService,
            lspService: _lsp,
          ),
        ),
      ),
    ),
  );

  Future<void> _measure() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_index >= _cases.length) {
      print('=== END BASELINE PROBE ===');
      exit(0);
    }
    final (family, size) = _cases[_index];
    EditorSettingsService.instance.setFontSize(size);
    EditorSettingsService.instance.setFontFamily(family);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() {});

    final boundary =
        _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final width = image.width;
    image.dispose();

    final metrics = EditorMetrics.forFontSize(size, family: family);
    final editable = _findRenderEditable(_boundary.currentContext!);
    if (editable == null) {
      print('no render editable');
      exit(1);
    }
    final rowTop = editable
        .localToGlobal(
          editable.getLocalRectForCaret(TextPosition(offset: 16)).topLeft,
        )
        .dy; // line 3 ("MMMM;")
    final textLeft = editable.localToGlobal(Offset.zero).dx;
    final numberRect = _rectOfText('3');
    // The caret line of line 3, so the band sits on it.
    _panel.currentState?.goToLine(3);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final bandRect = _rectOfBand();

    double? lastInk(double left, double right, double top, double height) {
      for (var y = (top + height).round() - 1; y >= top.round(); y--) {
        for (var x = left.round(); x < right.round(); x++) {
          if (x < 0 || x >= width) continue;
          final i = (y * width + x) * 4;
          if (data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2) <
              300) {
            return y.toDouble();
          }
        }
      }
      return null;
    }

    final digit = lastInk(
      numberRect.left,
      numberRect.right,
      rowTop,
      metrics.lineHeight,
    );
    final code = lastInk(
      textLeft + 2,
      textLeft + 60,
      rowTop,
      metrics.lineHeight,
    );
    print(
      '[${family.id}@${size.toInt()}] caretRow=$rowTop '
      'numberRow=${numberRect.top} rowDelta=${numberRect.top - rowTop} '
      'bandRow=${bandRect.top} bandVsNumber=${bandRect.top - numberRect.top} '
      'digitInk=$digit codeInk=$code '
      'inkDelta=${digit != null && code != null ? digit - code : "?"}',
    );

    _index++;
    if (mounted) setState(() {});
    SchedulerBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// The current-line band: the only translucent selection fill in the panel.
  Rect _rectOfBand() {
    Rect? found;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is DecoratedBox) {
        final decoration = widget.decoration;
        if (decoration is BoxDecoration) {
          final color = decoration.color;
          if (color != null && (color.a - 0.14).abs() < 0.01) {
            final box = element.renderObject;
            if (box is RenderBox && box.hasSize) {
              found ??= box.localToGlobal(Offset.zero) & box.size;
            }
          }
        }
      }
      element.visitChildren(visit);
    }

    (_boundary.currentContext! as Element).visitChildren(visit);
    return found ?? Rect.zero;
  }

  Rect _rectOfText(String value) {
    Rect? found;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Text && widget.data == value) {
        final box = element.renderObject;
        if (box is RenderBox && box.hasSize) {
          found ??= box.localToGlobal(Offset.zero) & box.size;
        }
      }
      element.visitChildren(visit);
    }

    (_boundary.currentContext! as Element).visitChildren(visit);
    return found ?? Rect.zero;
  }

  RenderEditable? _findRenderEditable(BuildContext context) {
    RenderEditable? found;
    void walk(RenderObject node) {
      if (found != null) return;
      if (node is RenderEditable) {
        found = node;
        return;
      }
      node.visitChildren(walk);
    }

    walk(context.findRenderObject()!);
    return found;
  }
}
