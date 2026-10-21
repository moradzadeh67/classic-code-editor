// Click-to-line probe - measures the real app, because the click/band mismatch
// only shows up there (`flutter_tester` has no system fonts and no CoreText).
//
//   flutter run -d macos -t tool/probe_click_line.dart
//
// It mounts the real [CodeEditorPanel] on a generated 400-line file, scrolls to
// line 400, clicks the middle of that row with a synthetic pointer, then prints:
//
//   * the line of the controller's selection after the click,
//   * the gutter number that is painted bold (the panel's own `_caretLine`),
//   * the caret row of the selected offset, and of line 400.
//
// If the first two disagree, the panel's caret tracking is stale; if the click
// lands on the wrong line, the renderer's hit test is off; if the caret row of
// the selection differs from line 400's row, the gutter's wrap model is wrong.
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:classic_code_editor/models/lsp_models.dart';
import 'package:classic_code_editor/services/file_service.dart';
import 'package:classic_code_editor/services/lsp_service.dart';
import 'package:classic_code_editor/ui/editor/code_editor_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

class _OfflineLspService extends LspService {
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
  static const int _lines = 400;
  static const int _target = 400;

  final FileService _fileService = FileService();
  final LspService _lsp = _OfflineLspService();
  final GlobalKey _panelKey = GlobalKey();

  /// Every 50th line is a long Persian line, so the document contains wrapped
  /// continuation rows above the target - the case that exposes the mismatch.
  String get _text => <String>[
    for (var i = 1; i <= _lines; i++)
      i % 50 == 0 ? '// ${'متن فارسی ' * 14}$i' : 'std::cout << "$i";',
  ].join('\n');

  @override
  void initState() {
    super.initState();
    _fileService.openFilePath('/tmp/probe_click.cpp', _text);
    SchedulerBinding.instance.addPostFrameCallback((_) => _run());
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
      body: SizedBox(
        width: 700,
        height: 800,
        child: CodeEditorPanel(
          key: _panelKey,
          fileService: _fileService,
          lspService: _lsp,
        ),
      ),
    ),
  );

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final panel = _panelKey.currentState as dynamic;
    panel.goToLine(_target);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final editable = _findRenderEditable(_panelKey.currentContext);
    if (editable == null) {
      print('NO RenderEditable');
      exit(1);
    }

    final text = _text;
    final targetRect = editable.getLocalRectForCaret(
      TextPosition(offset: _offsetOfLine(text, _target)),
    );
    final global = editable.localToGlobal(
      targetRect.topLeft + Offset(60, targetRect.height / 2),
    );

    print('=== CLICK-LINE PROBE (real macOS runtime) ===');
    print('click point = $global');
    print(
      'caret top of line $_target = '
      '${editable.localToGlobal(targetRect.topLeft).dy}',
    );

    _tapAt(global);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final selection = editable.textSelectionDelegate.textEditingValue.selection;
    final selectedOffset = selection.extentOffset.clamp(0, text.length);
    final selectedLine =
        '\n'.allMatches(text.substring(0, selectedOffset)).length + 1;
    final selectedTop = editable
        .localToGlobal(
          editable
              .getLocalRectForCaret(TextPosition(offset: selectedOffset))
              .topLeft,
        )
        .dy;

    print('selection extent offset = $selectedOffset -> line $selectedLine');
    print('caret row of the selection = $selectedTop');
    print(
      'row of line $_target        = '
      '${editable.localToGlobal(targetRect.topLeft).dy}',
    );
    print('bold gutter number (panel _caretLine) = ${_boldGutterNumber()}');
    print(
      selectedLine == _target
          ? 'RESULT: click maps correctly'
          : 'RESULT: WRONG LINE',
    );
    exit(0);
  }

  /// The gutter number painted bold: the panel bolds the caret line.
  String _boldGutterNumber() {
    String? found;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Text) {
        final weight = widget.style?.fontWeight;
        if (weight == FontWeight.bold &&
            int.tryParse(widget.data ?? '') != null) {
          found = widget.data;
        }
      }
      element.visitChildren(visit);
    }

    final context = _panelKey.currentContext;
    if (context is Element) context.visitChildren(visit);
    return found ?? '(none)';
  }

  void _tapAt(Offset position) {
    const pointer = 7;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: pointer, position: position),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: pointer, position: position),
    );
    print('tapped at $position');
  }

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
}
