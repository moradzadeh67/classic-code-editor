import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../models/debugger_models.dart';
import '../../models/language_config.dart';
import '../../models/lsp_models.dart';
import 'editor_metrics.dart';
import '../../services/file_service.dart';
import '../../services/lsp_service.dart';
import '../../services/theme_service.dart';
import '../../services/editor_settings_service.dart';
import '../../services/base_debugger.dart';
import '../../utils/completion_filter.dart';
import '../../utils/multi_language_highlighter.dart';
import 'autocomplete_popup.dart';
import 'hover_tooltip.dart';

/// Font size of the code editor's text.
///
/// Shared with the gutter so its rows line up exactly with the code.
/// Default-13px constants (kept untouched so existing tests reference them).
/// Live values come from [EditorMetrics.forFontSize] via [EditorSettingsService].
const double editorFontSize = 13.0;

/// Height of one rendered line of code, in logical pixels.
///
/// Flutter rounds a paragraph's line height to the nearest **whole** logical
/// pixel, so a nominal `13 * 1.45 = 18.85` actually paints as `19`. Using the
/// nominal value made every gutter row 0.15px shorter than the code line beside
/// it, and the error accumulated (~1.4px by line 10, ~4.5px by line 30) until
/// the numbers visibly detached from their lines.
const double editorLineHeight = 19.0;

/// Line-height multiplier passed to `TextStyle.height` / `StrutStyle.height`.
///
/// Derived from [editorLineHeight] so the multiplier and the gutter's row
/// height can never disagree.
const double editorLineHeightFactor = editorLineHeight / editorFontSize;

/// Letter spacing that the editor text really renders with.
///
/// [CodeField] merges its `textStyle` onto the ambient Material `bodyLarge`
/// style, which contributes `letterSpacing: 0.5`. That extra half pixel per
/// character is *not* part of a default `TextStyle`, so measuring wrap width
/// with a bare `TextStyle(fontFamily: 'Menlo', fontSize: 13)` under-reported
/// each character as 7.827px instead of the 8.327px the editor really paints.
/// The gutter then believed ~92 characters fit on a line while the editor
/// wrapped at ~87, so every long line gained an invisible extra row and pushed
/// the numbering below it out of step. Pinned explicitly so the value cannot
/// drift again and so the gutter can measure with it.
const double editorLetterSpacing = 0.5;

/// The one text style the code is measured *and* rendered with.
///
/// Both the gutter's wrap measurement and the editor field must use this, so
/// the two can never disagree about how wide a character is.
const TextStyle editorTextStyle = TextStyle(
  fontFamily: 'Menlo',
  fontSize: editorFontSize,
  height: editorLineHeightFactor,
  letterSpacing: editorLetterSpacing,
);

/// The strut that pins every line to exactly [editorLineHeight].
const StrutStyle editorStrutStyle = StrutStyle(
  fontFamily: 'Menlo',
  fontSize: editorFontSize,
  height: editorLineHeightFactor,
  forceStrutHeight: true,
);

/// Gutter width and the gap between the gutter and the editor surface.
const double gutterWidth = 52.0;
const double gutterGap = 4.0;

/// Space reserved at the right edge of every gutter row.
///
/// On desktop, Material's scroll behaviour wraps the gutter's [ListView] in a
/// [Scrollbar], so that slider is painted on the right edge of the gutter.
/// Reserving this strip keeps the slider from painting over the breakpoint
/// bullet; the line numbers sit on the left of the row, out of its way.
const double gutterScrollbarInset = 10.0;

/// Font size of the gutter's line numbers.
const double lineNumberFontSize = 11.0;

/// Memoised wrap measurement for the gutter (see `_gutterRows`).
///
/// The font family is part of the key: two families at the same size measure a
/// different character advance, so a family switch that kept the cached rows
/// would leave the gutter predicting the wrong number of wrapped rows.
class _GutterRowsCache {
  final String text;
  final double maxWidth;
  final TextScaler scaler;
  final List<int> rows;
  final double fontSize;
  final String fontFamily;

  /// True when [rows] came from the renderer's own line metrics. A cache built
  /// by the first-frame prediction is replaced as soon as the renderer can be
  /// measured (see `_queueGutterRowsRebuild`).
  final bool fromRenderer;

  const _GutterRowsCache(
    this.text,
    this.maxWidth,
    this.scaler,
    this.rows,
    this.fontSize,
    this.fontFamily, {
    this.fromRenderer = false,
  });
}

/// The main code-editor area.
class CodeEditorPanel extends StatefulWidget {
  final FileService fileService;
  final LspService lspService;
  final BaseDebugger? debugger;
  final CodeController? controller;

  /// Called with the 1-based logical line and column whenever the caret moves,
  /// so the shell can show `Ln 12, Col 5` in the status bar.
  final void Function(int line, int column)? onCaretChanged;

  const CodeEditorPanel({
    super.key,
    required this.fileService,
    required this.lspService,
    this.debugger,
    this.controller,
    this.onCaretChanged,
  });

  @override
  State<CodeEditorPanel> createState() => CodeEditorPanelState();
}

/// Public so the shell can drive the caret/scroll for "Go to Line"
/// (`GlobalKey<CodeEditorPanelState>`).
class CodeEditorPanelState extends State<CodeEditorPanel> {
  late final CodeController _controller;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _editorKey = GlobalKey();

  Offset _cursorScreenOffset = Offset.zero;
  List<CompletionItem> _completionItems = [];
  int _selectedCompletionIndex = 0;
  HoverInfo? _hoverInfo;

  Timer? _completionDebounce;
  Timer? _hoverDebounce;
  Timer? _typingTimer;
  bool _isTyping = false;
  int _completionRequestId = 0;
  String? _programmaticText;

  /// Last buffer contents seen by [_onTextChanged], so a selection-only change
  /// (a mouse click) never opens the completion popup.
  String? _lastCompletionText;

  /// Kept in sync with the editor so the gutter never scrolls out of step.
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _gutterScrollController = ScrollController();

  /// Memoised result of the last gutter wrap measurement.
  _GutterRowsCache? _gutterRowsCache;

  /// Measured advance of one monospace character, and the size/family/scale it
  /// was measured at. See `_charAdvance`.
  double? _charAdvanceCache;
  TextScaler? _charAdvanceScaler;
  double? _charAdvanceFontSize;
  String? _charAdvanceFontFamily;

  /// 1-based logical line the caret currently sits on, used to paint the
  /// "current line" band behind the code.
  int _caretLine = 1;

  bool get _showAutocomplete => _completionItems.isNotEmpty;
  bool get _showHover => _hoverInfo != null;
  String get _filePath =>
      widget.fileService.currentFilePath ?? widget.fileService.fileName;
  int? _lastActiveTabIndex;

  @override
  void initState() {
    super.initState();
    registerHighlightLanguages();
    _controller =
        widget.controller ??
        MultiLanguageHighlighter.createController(
          text: widget.fileService.fileContent,
          filePath: _filePath,
        );
    // A controller handed in by the shell (`CodeController()` with no language)
    // renders every token in the default text color, so the initial file needs
    // its grammar applied here — not only on the next tab switch.
    _controller.language = MultiLanguageHighlighter.getModeForLanguage(
      LanguageConfig.fromPathOrContent(
        _filePath,
        widget.fileService.fileContent,
      ).highlightLanguage,
    );
    _controller.addListener(_onTextChanged);
    _controller.addListener(_onCaretMoved);
    _controller.addListener(_queueBandUpdate);
    _editorScrollController.addListener(_syncGutterScroll);
    _editorScrollController.addListener(_queueBandUpdate);
    widget.fileService.addListener(_onFileServiceChanged);
    widget.debugger?.addListener(_onDebuggerChanged);
    EditorSettingsService.instance.addListener(_onEditorSettingsChanged);
    _lastActiveTabIndex = widget.fileService.activeTabIndex;
  }

  @override
  void didUpdateWidget(covariant CodeEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The shell swaps the active debugger when the language changes; keep our
    // listener attached to the current one so the gutter keeps repainting.
    if (oldWidget.debugger != widget.debugger) {
      oldWidget.debugger?.removeListener(_onDebuggerChanged);
      widget.debugger?.addListener(_onDebuggerChanged);
    }
    if (oldWidget.fileService != widget.fileService ||
        oldWidget.lspService != widget.lspService) {
      oldWidget.fileService.removeListener(_onFileServiceChanged);
      widget.fileService.addListener(_onFileServiceChanged);
      _updateControllerText();
    }
  }

  @override
  void dispose() {
    _completionDebounce?.cancel();
    _hoverDebounce?.cancel();
    _typingTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.removeListener(_onCaretMoved);
    widget.fileService.removeListener(_onFileServiceChanged);
    widget.debugger?.removeListener(_onDebuggerChanged);
    EditorSettingsService.instance.removeListener(_onEditorSettingsChanged);
    _editorScrollController.dispose();
    _gutterScrollController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_programmaticText != null && _controller.text == _programmaticText) {
      _programmaticText = null;
      return;
    }

    final newText = _controller.text;
    widget.fileService.updateContent(newText);

    // An untitled buffer has no extension, so its grammar can only come from
    // the content: keep re-sniffing while it is typed instead of staying on the
    // Dart fallback (which painted Python as plain text).
    final mode = MultiLanguageHighlighter.getModeForLanguage(
      LanguageConfig.fromPathOrContent(_filePath, newText).highlightLanguage,
    );
    if (mode != _controller.language) {
      _controller.language = mode;
    }

    // Auto-clean breakpoints when text is cleared or lines are deleted
    if (widget.debugger != null) {
      if (newText.trim().isEmpty) {
        widget.debugger!.clearBreakpointsForFile(_filePath);
      } else {
        final lineCount = newText.split('\n').length;
        widget.debugger!.breakpoints.removeWhere(
          (bp) =>
              (bp.filePath == _filePath ||
                  bp.filePath == widget.fileService.currentFilePath ||
                  bp.filePath == widget.fileService.fileName) &&
              bp.line > lineCount,
        );
      }
    }

    // A mouse click only changes the SELECTION, but the controller notifies on
    // every value change — which used to pop the completion list wherever the
    // caret landed. Only real text edits may trigger completion.
    final text = _controller.text;
    final textChanged = text != _lastCompletionText;
    _lastCompletionText = text;
    if (!textChanged) {
      _dismissHover();
      return;
    }

    setState(() {
      _isTyping = true;
    });
    // The text changed, so the wrap model must be re-measured from the renderer
    // (a new long line can re-wrap every row below it).
    _queueGutterRowsRebuild();

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isTyping = false;
        });
      }
    });

    _completionDebounce?.cancel();
    _completionDebounce = Timer(const Duration(milliseconds: 150), () {
      _requestCompletion();
    });

    _dismissHover();
  }

  /// Tracks the caret so the current-line band follows clicks, arrow keys and
  /// typing. Only the logical line is stored; the wrap-aware row is resolved in
  /// `build`, where the gutter rows for the current width are known.
  void _onCaretMoved() {
    final selection = _controller.selection;
    if (!selection.isValid) return;
    final text = _controller.text;
    final offset = selection.extentOffset.clamp(0, text.length);
    var line = 1;
    var lineStart = 0;
    for (var i = 0; i < offset; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        line++;
        lineStart = i + 1;
      }
    }
    if (line != _caretLine) {
      setState(() => _caretLine = line);
    }
    widget.onCaretChanged?.call(line, offset - lineStart + 1);
    _queueBandUpdate();
  }

  /// Offset of the first character of the logical line containing [offset].
  int _lineStartOffset(int offset) {
    final text = _controller.text;
    final clamped = offset.clamp(0, text.length);
    var start = clamped;
    while (start > 0 && text.codeUnitAt(start - 1) != 0x0A) {
      start--;
    }
    return start;
  }

  /// Recomputes the band position in a post-frame callback.
  ///
  /// The position must come from the frame's **final** layout: when a click or
  /// an edit makes the field reveal the caret (`scrollPadding`), the internal
  /// scroll offset changes after `build`, so a value measured during build is a
  /// row off - the band then sits below/above the caret it is highlighting.
  void _queueBandUpdate() {
    if (_bandUpdateQueued) return;
    _bandUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bandUpdateQueued = false;
      if (!mounted) return;
      final rect = _bandRectForCaret(_metrics.lineHeight);
      final sameTop =
          (rect.top - (_bandTop ?? double.negativeInfinity)).abs() < 0.01;
      final sameHeight =
          (rect.height - (_bandHeight ?? double.negativeInfinity)).abs() < 0.01;
      if (sameTop && sameHeight) return;
      setState(() {
        _bandTop = rect.top;
        _bandHeight = rect.height;
      });
    });
  }

  bool _bandUpdateQueued = false;
  double? _bandTop;
  double? _bandHeight;

  /// Geometry of the current-line band, in the editor Stack's local coords.
  ///
  /// * The **row** comes from the renderer (so a stale row cache can never move
  ///   the band), but the position is snapped to the row grid
  ///   (`row * lineHeight`) instead of using the caret rect's own `top`:
  ///   Flutter inflates that rect ~1px above its line box, so a band built from
  ///   it sat one pixel higher than the gutter numbers of the very same row
  ///   (measured in the app: `numberRow - caretRow = +1` at 8/13/32, both fonts).
  /// * The **height** covers every visual row of the logical line, the way
  ///   desktop editors highlight a wrapped line as a whole instead of marking
  ///   only its first segment.
  ({double top, double height}) _bandRectForCaret(double lineHeight) {
    if (lineHeight <= 0) return (top: 0, height: 0);
    final editable = _renderEditable();
    final selection = _controller.selection;
    var row = -1;
    var span = 1;
    if (editable != null &&
        editable.hasSize &&
        !editable.debugNeedsLayout &&
        selection.isValid) {
      final text = _controller.text;
      Rect caretAt(int offset) => editable.getLocalRectForCaret(
        TextPosition(offset: offset.clamp(0, text.length)),
      );

      final first = caretAt(0);
      final lineStart = _lineStartOffset(selection.extentOffset);
      final start = caretAt(lineStart);
      // The caret inflation is identical on every rect, so both differences are
      // true pixel distances between rows.
      row = ((start.top - first.top) / lineHeight).round();

      // The first character *after* this line's newline: its caret sits on the
      // first row below the whole line, wrapped rows included. (The offset of
      // the `\n` itself belongs to the line's last row.)
      final newline = text.indexOf('\n', lineStart);
      final end = newline < 0 ? caretAt(text.length) : caretAt(newline + 1);
      span = ((end.top - start.top) / lineHeight).round().clamp(1, 1000);
    }
    if (row < 0) {
      // Before the first layout: the wrap-aware rows of the gutter cache.
      final rows = _gutterRowsCache?.rows ?? const <int>[];
      row = _visualRowForLine(rows, _caretLine);
      var i = row + 1;
      span = 1;
      while (i < rows.length && rows[i] == 0) {
        span++;
        i++;
      }
    }
    final scrollOffset = _editorScrollController.hasClients
        ? _editorScrollController.offset
        : 0.0;
    return (top: row * lineHeight - scrollOffset, height: span * lineHeight);
  }

  /// The live [RenderEditable] of the editor, used to position the
  /// current-line band from the caret the renderer actually painted.
  RenderEditable? _renderEditable() {
    final root = _editorKey.currentContext?.findRenderObject();
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

  /// Visual row of [line] in the wrap-aware [rows] produced by `_gutterRows`.
  ///
  /// [rows] holds the logical line number on the first visual row of a line and
  /// `0` on every continuation row, so the index of [line] is its first row.
  static int _visualRowForLine(List<int> rows, int line) {
    final index = rows.indexOf(line);
    if (index >= 0) return index;
    return rows.isEmpty ? 0 : rows.length - 1;
  }

  /// Total number of logical lines in the buffer.
  int get lineCount => '\n'.allMatches(_controller.text).length + 1;

  /// Moves the caret to the start of the 1-based [line], scrolls it into view
  /// (about one third from the top) and gives focus back to the editor.
  ///
  /// The scroll offset is `visualRow * lineHeight` with the *live*
  /// [EditorMetrics] and the wrap-aware gutter rows, so the gutter (which
  /// follows the same controller through `_syncGutterScroll`) stays aligned.
  void goToLine(int line) {
    final target = line.clamp(1, lineCount);
    final text = _controller.text;

    var offset = 0;
    for (var current = 1; current < target; current++) {
      final next = text.indexOf('\n', offset);
      if (next < 0) break;
      offset = next + 1;
    }
    _controller.selection = TextSelection.collapsed(offset: offset);

    final cache = _gutterRowsCache;
    final rows = cache?.rows ?? const <int>[];
    final row = rows.isEmpty ? target - 1 : _visualRowForLine(rows, target);
    final lineHeight = _metrics.lineHeight;

    if (_editorScrollController.hasClients) {
      final position = _editorScrollController.position;
      final desired = (row * lineHeight - position.viewportDimension / 3).clamp(
        0.0,
        position.maxScrollExtent,
      );
      _editorScrollController.jumpTo(desired);
    }
    _focusNode.requestFocus();
  }

  void _onDebuggerChanged() {
    if (mounted) setState(() {});
  }

  /// Fires for **both** settings that change the metrics: the size and the font
  /// family.
  ///
  /// Every cache is dropped unconditionally rather than compared, because a
  /// stale advance or row list is invisible until the gutter has drifted a few
  /// lines down the file - the exact failure TASK-019 had to chase.
  void _onEditorSettingsChanged() {
    _charAdvanceCache = null;
    _charAdvanceScaler = null;
    _charAdvanceFontSize = null;
    _charAdvanceFontFamily = null;
    _gutterRowsCache = null;
    if (mounted) {
      setState(() {});
      // Schedule scroll sync after layout rebuild, then re-measure the wrap
      // model at the new metrics.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncGutterScroll();
        _queueGutterRowsRebuild();
      });
    }
  }

  void _onFileServiceChanged() {
    if (widget.fileService.activeTabIndex != _lastActiveTabIndex) {
      _lastActiveTabIndex = widget.fileService.activeTabIndex;
      _updateControllerText();
    }
  }

  void _updateControllerText() {
    final newContent = widget.fileService.fileContent;
    final config = LanguageConfig.fromPathOrContent(_filePath, newContent);
    _controller.language = MultiLanguageHighlighter.getModeForLanguage(
      config.highlightLanguage,
    );
    if (_controller.text != newContent) {
      _programmaticText = newContent;
      _controller.text = newContent;
      _controller.selection = TextSelection.collapsed(
        offset: newContent.length,
      );
    }
    if (widget.debugger != null) {
      if (newContent.trim().isEmpty) {
        widget.debugger!.clearBreakpointsForFile(_filePath);
      } else {
        final lineCount = newContent.split('\n').length;
        widget.debugger!.breakpoints.removeWhere(
          (bp) =>
              (bp.filePath == _filePath ||
                  bp.filePath == widget.fileService.currentFilePath ||
                  bp.filePath == widget.fileService.fileName) &&
              bp.line > lineCount,
        );
      }
    }
    setState(() {});
  }

  bool _hasBreakpoint(int line) {
    final path = _filePath;
    if (widget.debugger == null) return false;
    return widget.debugger!.breakpoints.any(
      (bp) =>
          (bp.filePath == path ||
              bp.filePath == widget.fileService.currentFilePath ||
              bp.filePath == widget.fileService.fileName) &&
          bp.line == line,
    );
  }

  void _toggleBreakpoint(int line) {
    // A wrapped line's continuation row carries no line number (`0`); tapping
    // it used to set a breakpoint on line 0 - an entry every debugger rejects.
    if (line <= 0) return;
    final path = _filePath;
    if (widget.debugger == null) return;
    if (_hasBreakpoint(line)) {
      widget.debugger!.removeBreakpoint(path, line);
      if (widget.fileService.currentFilePath != null) {
        widget.debugger!.removeBreakpoint(
          widget.fileService.currentFilePath!,
          line,
        );
      }
    } else {
      widget.debugger!.setBreakpoint(path, line);
    }
    setState(() {});
  }

  Offset _computeCursorScreenPosition() {
    try {
      final RenderBox? box =
          _editorKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return const Offset(100, 100);

      final editorGlobalPosition = box.localToGlobal(Offset.zero);
      final text = _controller.text;
      final selection = _controller.selection;
      final offset = selection.isValid && selection.start >= 0
          ? selection.start
          : 0;
      final (lineNumber, _) = _offsetToLineColumn(text, offset);

      final Offset cursorPosition =
          editorGlobalPosition +
          Offset(8, 8 + lineNumber * _metrics.lineHeight);

      return cursorPosition + const Offset(0, 24);
    } catch (_) {
      return const Offset(100, 100);
    }
  }

  void _requestCompletion() async {
    // Only suggest while the user is actually typing. Opening a file (or the
    // first mouse move over the editor) must not pop the list on its own.
    if (!_isTyping) {
      _dismissCompletion();
      return;
    }

    final filePath = _filePath;
    final config = LanguageConfig.fromPathOrContent(filePath, _controller.text);
    final language = config.highlightLanguage;

    final selection = _controller.selection;
    final offset =
        (selection.isValid && selection.isCollapsed && selection.start >= 0)
        ? selection.start
        : _controller.text.length;

    final currentWord = CompletionFilter.currentWord(_controller.text, offset);
    final prevChar = CompletionFilter.previousChar(_controller.text, offset);

    if (!CompletionFilter.isTriggering(currentWord, previousChar: prevChar)) {
      _dismissCompletion();
      return;
    }

    final requestId = ++_completionRequestId;
    final (line, column) = _offsetToLineColumn(_controller.text, offset);

    List<CompletionItem> items = [];
    if (widget.lspService.isConnected) {
      items = await widget.lspService.requestCompletion(
        filePath,
        line + 1,
        column + 1,
      );
    }

    if (!mounted || requestId != _completionRequestId) return;

    List<CompletionItem> filtered = CompletionFilter.filter(items, currentWord);

    if (filtered.isEmpty && items.isEmpty) {
      filtered = CompletionFilter.generateFallbackCompletions(
        _controller.text,
        currentWord,
        language,
      );
    }

    if (filtered.isEmpty) {
      _dismissCompletion();
      return;
    }

    setState(() {
      _completionItems = filtered;
      _selectedCompletionIndex = 0;
      _cursorScreenOffset = _computeCursorScreenPosition();
    });
  }

  String _currentWordAtCursor() => CompletionFilter.currentWord(
    _controller.text,
    _controller.selection.start,
  );

  (int, int) _offsetToLineColumn(String text, int offset) {
    int line = 0;
    int lastNewline = -1;
    for (int i = 0; i < offset && i < text.length; i++) {
      if (text[i] == '\n') {
        line++;
        lastNewline = i;
      }
    }
    final column = offset - (lastNewline + 1);
    return (line, column);
  }

  void _moveSelection(int delta) {
    setState(() {
      final newIndex = _selectedCompletionIndex + delta;
      _selectedCompletionIndex = newIndex.clamp(0, _completionItems.length - 1);
    });
  }

  void _acceptSelected() {
    if (_completionItems.isEmpty) return;

    final item = _completionItems[_selectedCompletionIndex];
    final insertText = item.effectiveInsert;
    if (insertText.isEmpty) return;

    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _dismissCompletion();
      return;
    }

    final text = _controller.text;
    final offset = selection.start;

    int wordStart = offset;
    while (wordStart > 0) {
      final char = text[wordStart - 1];
      if (RegExp(r'[a-zA-Z0-9_]').hasMatch(char)) {
        wordStart--;
      } else {
        break;
      }
    }

    final newText = text.replaceRange(wordStart, offset, insertText);
    final newOffset = wordStart + insertText.length;

    _programmaticText = newText;
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: newOffset);

    _dismissCompletion();
  }

  void _dismissCompletion() {
    _completionRequestId++;
    _completionDebounce?.cancel();
    if (_completionItems.isEmpty && _selectedCompletionIndex == 0) return;
    setState(() {
      _completionItems = [];
      _selectedCompletionIndex = 0;
    });
  }

  void _dismissHover() {
    _hoverDebounce?.cancel();
    setState(() {
      _hoverInfo = null;
    });
  }

  void _requestHover() {
    final filePath = widget.fileService.currentFilePath;
    if (filePath == null || !widget.lspService.isConnected) return;

    if (_isTyping || _showAutocomplete) {
      _hoverDebounce?.cancel();
      _dismissHover();
      return;
    }

    _hoverDebounce?.cancel();
    _hoverDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (_isTyping || _showAutocomplete) {
        _dismissHover();
        return;
      }
      if (_controller.selection.isValid && _controller.selection.isCollapsed) {
        final offset = _controller.selection.start;
        final (line, column) = _offsetToLineColumn(_controller.text, offset);

        final hoverInfo = await widget.lspService.requestHover(
          filePath,
          line + 1,
          column + 1,
        );

        if (hoverInfo != null && mounted && !_isTyping && !_showAutocomplete) {
          setState(() {
            _hoverInfo = hoverInfo;
            _cursorScreenOffset = _computeCursorScreenPosition();
          });
        }
      }
    });
  }

  void _handleEnterPressed() {
    final selection = _controller.selection;
    if (!selection.isValid) return;

    final text = _controller.text;
    final start = selection.start;
    final end = selection.end;

    int lineStart = text.lastIndexOf('\n', start - 1);
    lineStart = (lineStart == -1) ? 0 : lineStart + 1;

    final currentLine = text.substring(lineStart, start);
    final match = RegExp(r'^(\s*)').firstMatch(currentLine);
    final currentIndent = match?.group(1) ?? '';

    final trimmed = currentLine.trimRight();
    final shouldIncrease =
        trimmed.endsWith('{') || trimmed.endsWith('(') || trimmed.endsWith('[');

    String newIndent = currentIndent;
    if (shouldIncrease) {
      newIndent += '  ';
    }

    final restOfText = text.substring(end);
    final trimmedRest = restOfText.trimLeft();
    final isBeforeClosingBracket =
        shouldIncrease &&
        (trimmedRest.startsWith('}') ||
            trimmedRest.startsWith(')') ||
            trimmedRest.startsWith(']'));

    String insertContent;
    int newCursorOffset;

    if (isBeforeClosingBracket) {
      insertContent = '\n$newIndent\n$currentIndent';
      newCursorOffset = start + 1 + newIndent.length;
    } else {
      insertContent = '\n$newIndent';
      newCursorOffset = start + insertContent.length;
    }

    final newText = text.replaceRange(start, end, insertContent);
    _programmaticText = newText;
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: newCursorOffset);

    _dismissCompletion();
    _dismissHover();
  }

  bool _tryHandleClosingBracket(String bracket) {
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return false;

    final text = _controller.text;
    final offset = selection.start;

    int lineStart = text.lastIndexOf('\n', offset - 1);
    lineStart = (lineStart == -1) ? 0 : lineStart + 1;

    final lineBeforeCursor = text.substring(lineStart, offset);

    if (RegExp(r'^\s+$').hasMatch(lineBeforeCursor) &&
        lineBeforeCursor.length >= 2) {
      final dedentedLine = lineBeforeCursor.substring(2) + bracket;
      final newText = text.replaceRange(lineStart, offset, dedentedLine);
      final newOffset = lineStart + dedentedLine.length;

      _programmaticText = newText;
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(offset: newOffset);

      _dismissCompletion();
      _dismissHover();
      return true;
    }
    return false;
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
          _showAutocomplete) {
        _moveSelection(1);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
          _showAutocomplete) {
        _moveSelection(-1);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_showAutocomplete) {
          _acceptSelected();
        } else {
          _handleEnterPressed();
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.escape &&
          _showAutocomplete) {
        _dismissCompletion();
        return KeyEventResult.handled;
      } else {
        final char = event.character;
        if (char != null && (char == '}' || char == ')' || char == ']')) {
          if (_tryHandleClosingBracket(char)) {
            return KeyEventResult.handled;
          }
        }
      }
    }
    return KeyEventResult.ignored;
  }

  /// Text metrics shared with the editor. Wrapping must be measured with the
  /// exact style the field renders with — including its letter spacing — or
  /// the gutter predicts the wrong number of wrapped rows.
  EditorMetrics get _metrics => EditorMetrics.forFontSize(
    EditorSettingsService.instance.fontSize,
    family: EditorSettingsService.instance.fontFamily,
  );

  TextStyle get _editorTextStyle => _metrics.textStyle;

  /// Width the editor gives one character, measured with the exact style the
  /// code is rendered in (see [editorTextStyle]) instead of guessed.
  ///
  /// Menlo is monospace, so this single number lets `_gutterRows` decide which
  /// lines are short enough to skip text layout. Guessing it is what caused the
  /// gutter to drift: a `fontSize * 0.62` estimate gave 8.06px per character
  /// while the editor really paints 8.33px (the glyph advance plus the theme's
  /// 0.5px letter spacing), so a line of, say, 90 characters looked like it fit
  /// on one row when the editor had already wrapped it onto two — and every
  /// line number below it came up one row short.
  ///
  /// Measuring keeps the gate exact even if the font, size or letter spacing
  /// change, because it uses the same style the editor does.
  double _charAdvance(TextScaler scaler) {
    if (_charAdvanceCache != null &&
        _charAdvanceScaler == scaler &&
        _charAdvanceFontSize == _metrics.fontSize &&
        _charAdvanceFontFamily == _metrics.fontFamily) {
      return _charAdvanceCache!;
    }
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    );
    painter.text = TextSpan(text: '0000000000', style: _metrics.textStyle);
    painter.layout();
    final advance = painter.width / 10;
    painter.dispose();
    _charAdvanceCache = advance;
    _charAdvanceScaler = scaler;
    _charAdvanceFontSize = _metrics.fontSize;
    _charAdvanceFontFamily = _metrics.fontFamily;
    return advance;
  }

  /// Flat gutter rows: the logical line number for the first visual row of a
  /// line, and `0` for every continuation row produced by wrapping.
  ///
  /// The editor wraps long logical lines onto several visual rows, so drawing
  /// exactly one gutter row per logical line pushed the code one row further
  /// down for every wrapped line — very visible on long files.
  List<int> _gutterRows(String text, double maxWidth, TextScaler scaler) {
    final cached = _gutterRowsCache;
    if (cached != null &&
        cached.text == text &&
        cached.maxWidth == maxWidth &&
        cached.scaler == scaler &&
        cached.fontSize == _metrics.fontSize &&
        cached.fontFamily == _metrics.fontFamily) {
      // A cache filled by the renderer is authoritative; one filled by the
      // fallback below is only a stopgap until the next post-frame pass.
      if (cached.fromRenderer) return cached.rows;
      return cached.rows;
    }

    return _predictedGutterRows(text, maxWidth, scaler);
  }

  /// Queues an exact rebuild of the gutter rows from the renderer.
  ///
  /// The rows used to be *predicted* here (character advance × line length,
  /// then a `TextPainter` for the long lines). A prediction cannot be exact:
  /// Persian text is set in the fallback font, where a glyph is wider than the
  /// measured monospace advance, and the painter's width is not the TextField's
  /// real text width, so a line predicted as one row could render as two - and
  /// every number below it then sat one row too high. The renderer already knows
  /// the answer: `computeLineMetrics()` returns one entry per visual row, and
  /// each entry says whether it ended in a hard (`\n`) or a soft (wrap) break.
  void _queueGutterRowsRebuild() {
    if (_gutterRebuildQueued) return;
    _gutterRebuildQueued = true;
    _gutterRebuildAttempts = 0;
    _runGutterRowsRebuild();
  }

  /// One post-frame attempt; retries (bounded) while the renderer cannot be
  /// measured yet.
  ///
  /// The retry is the whole point: on the very first frame after the app opens
  /// with a large pasted document the editable is either absent or still
  /// `debugNeedsLayout`, and returning without rescheduling used to freeze the
  /// *predicted* rows - the numbers stayed a row off until any resize threw them
  /// away. Nothing else would ever have rebuilt them.
  void _runGutterRowsRebuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _gutterRebuildQueued = false;
        return;
      }
      final editable = _renderEditable();
      final ready =
          editable != null && editable.hasSize && !editable.debugNeedsLayout;
      final rows = ready ? _rowsFromRenderer(editable) : const <int>[];
      if (rows.isEmpty) {
        if (_gutterRebuildAttempts++ < 5) {
          // Ask for another frame, otherwise the callback would never fire.
          WidgetsBinding.instance.ensureVisualUpdate();
          _runGutterRowsRebuild();
          return;
        }
        _gutterRebuildQueued = false;
        return;
      }
      _gutterRebuildQueued = false;
      // The editor's own width is the wrap width, so it doubles as the key.
      final text = _controller.text;
      final scaler = _textScalerFor(_editorKey.currentContext);
      final maxWidth = editable!.size.width;
      final cache = _gutterRowsCache;
      if (cache != null &&
          cache.text == text &&
          cache.maxWidth == maxWidth &&
          cache.scaler == scaler &&
          cache.fontSize == _metrics.fontSize &&
          cache.fontFamily == _metrics.fontFamily &&
          cache.fromRenderer &&
          _sameRows(cache.rows, rows)) {
        return;
      }
      setState(() {
        _gutterRowsCache = _GutterRowsCache(
          text,
          maxWidth,
          scaler,
          rows,
          _metrics.fontSize,
          _metrics.fontFamily,
          fromRenderer: true,
        );
      });
    });
  }

  bool _gutterRebuildQueued = false;
  int _gutterRebuildAttempts = 0;

  static TextScaler _textScalerFor(BuildContext? context) {
    if (context == null) return TextScaler.noScaling;
    return MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
  }

  static bool _sameRows(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The gutter rows exactly as the editor laid them out.
  ///
  /// One entry per visual row: the 1-based logical line number on the first row
  /// of a line, `0` on every continuation row produced by wrapping.
  ///
  /// Both halves come from the renderer, never from a prediction:
  /// * the row *count* is the caret travel from the first to the last offset
  ///   divided by the (uniform) line height;
  /// * the row of each logical line is where that line's caret actually is.
  List<int> _rowsFromRenderer(RenderEditable editable) {
    final text = _controller.text;
    final lineHeight = _metrics.lineHeight;
    if (lineHeight <= 0) return const <int>[1];

    // `getLocalRectForCaret` is in the editor's viewport space, so add the
    // scroll offset back to land in content space (row 0 = first line).
    final scrollOffset = _editorScrollController.hasClients
        ? _editorScrollController.offset
        : 0.0;
    double contentTop(int offset) =>
        editable
            .getLocalRectForCaret(
              TextPosition(offset: offset.clamp(0, text.length)),
            )
            .top +
        scrollOffset;

    final firstTop = contentTop(0);
    final lastTop = contentTop(text.length);
    final totalRows = (((lastTop - firstTop) / lineHeight).round() + 1).clamp(
      1,
      1000000,
    );
    // Sanity check against a stale layout: a line can never occupy less than one
    // row, so fewer rows than logical lines means the renderer is still showing
    // the *previous* text and the caller must retry (see
    // `_runGutterRowsRebuild`).
    final logicalLines = '\n'.allMatches(text).length + 1;
    if (totalRows < logicalLines) return const <int>[];
    final rows = List<int>.filled(totalRows, 0);

    var line = 1;
    var offset = 0;
    while (true) {
      final row = ((contentTop(offset) - firstTop) / lineHeight).round().clamp(
        0,
        totalRows - 1,
      );
      rows[row] = line;
      final next = text.indexOf('\n', offset);
      if (next < 0) break;
      offset = next + 1;
      line++;
    }
    return rows;
  }

  /// First-frame stopgap only: approximate the wrap count with a `TextPainter`.
  ///
  /// `_queueGutterRowsRebuild` replaces this with the renderer's own model on
  /// the next frame.
  List<int> _predictedGutterRows(
    String text,
    double maxWidth,
    TextScaler scaler,
  ) {
    final lines = text.split('\n');
    final rows = <int>[];
    // Menlo is monospace, so a line can only wrap once its character count
    // exceeds what fits; this cheap gate keeps most lines out of text layout.
    // The limit uses the *measured* character advance, so a line this short is
    // guaranteed to fit on one row — over-estimating the advance can only cost
    // a little extra layout, never an unmeasured wrapped line.
    final unwrappedCharLimit = (maxWidth / _charAdvance(scaler)).floor();
    TextPainter? painter;

    for (var i = 0; i < lines.length; i++) {
      // flutter_code_editor converts tabs to 2 spaces for display.
      final line = lines[i].replaceAll('\t', '  ');
      var visualRows = 1;

      if (line.length > unwrappedCharLimit) {
        painter ??= TextPainter(
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        );
        painter.text = TextSpan(
          text: line.isEmpty ? ' ' : line,
          style: _editorTextStyle,
        );
        painter.layout(maxWidth: maxWidth);
        visualRows = painter.computeLineMetrics().length.clamp(1, 1000);
      }

      rows.add(i + 1);
      for (var r = 1; r < visualRows; r++) {
        rows.add(0);
      }
    }
    painter?.dispose();

    _gutterRowsCache = _GutterRowsCache(
      text,
      maxWidth,
      scaler,
      rows,
      _metrics.fontSize,
      _metrics.fontFamily,
    );
    return rows;
  }

  /// Mirrors the editor's scroll offset onto the gutter so the numbers never
  /// scroll out of step with the code.
  void _syncGutterScroll() {
    if (!_gutterScrollController.hasClients ||
        !_editorScrollController.hasClients) {
      return;
    }
    final target = _editorScrollController.offset.clamp(
      _gutterScrollController.position.minScrollExtent,
      _gutterScrollController.position.maxScrollExtent,
    );
    if ((_gutterScrollController.offset - target).abs() > 0.5) {
      _gutterScrollController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = widget.fileService.activeTab;

    if (activeTab == null) {
      return Container(
        color: ThemeService.instance.colors.editorBackground,
        alignment: Alignment.center,
        child: Text(
          'No file open. Click Open or select a file.',
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'Arial',
            color: ThemeService.instance.colors.editorText.withValues(
              alpha: 0.6,
            ),
          ),
        ),
      );
    }

    return CodeTheme(
      // The palette follows View > Syntax Colors. `CodeThemeData` compares by
      // its style map and the panel rebuilds on every settings notification, so
      // a scheme change repaints the field without recreating the controller
      // (no analysis, cursor or undo history is lost).
      data: CodeThemeData(
        styles: MultiLanguageHighlighter.getThemeStyles(
          EditorSettingsService.instance.syntaxScheme,
        ),
      ),
      child: Stack(
        children: [
          Container(
            color: ThemeService.instance.colors.editorBackground,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // How the editor really wraps at this width, so every
                        // visual row gets a gutter row of its own.
                        final metrics = _metrics;
                        final editorWidth =
                            (constraints.maxWidth -
                                    metrics.gutterWidth -
                                    gutterGap)
                                .clamp(1.0, double.infinity);
                        // Once the renderer has been measured its width is the
                        // key, so the exact rows survive rebuilds; before that
                        // (first frame) the computed width is the best guess.
                        final measured = _gutterRowsCache;
                        final keyWidth =
                            measured != null && measured.fromRenderer
                            ? measured.maxWidth
                            : editorWidth;
                        final gutterRows = _gutterRows(
                          _controller.text,
                          keyWidth,
                          MediaQuery.textScalerOf(context),
                        );
                        // The exact rows come from the renderer's own line
                        // metrics; schedule that pass for every width/text
                        // change (the value above is a one-frame stopgap).
                        //
                        // It is queued on *every* build, not just on text/width
                        // changes: on first open a big paste could be measured
                        // against the width the editor had before the panel
                        // settled, and the retry in `_runGutterRowsRebuild`
                        // plus this unconditional queue is what makes the model
                        // converge without the user resizing the window.
                        _queueGutterRowsRebuild();

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Gutter for breakpoints & line numbers
                            Container(
                              width: metrics.gutterWidth,
                              color: ThemeService
                                  .instance
                                  .colors
                                  .editorLineNumberBg,
                              // The gutter never scrolls on its own: it only
                              // mirrors the editor. A user-scrollable gutter
                              // used to slide the numbers while the code stayed
                              // put, so scrolling is disabled here and the
                              // editor owns the scroll.
                              child: ListView.builder(
                                controller: _gutterScrollController,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: gutterRows.length,
                                itemExtent: _metrics.lineHeight,
                                itemBuilder: (context, index) {
                                  final lineNumber = gutterRows[index];
                                  if (lineNumber == 0) {
                                    // Continuation row of a wrapped line: keep the
                                    // height so everything below stays aligned.
                                    return SizedBox(
                                      height: _metrics.lineHeight,
                                    );
                                  }
                                  // `lineNumber` is `0` on the continuation rows
                                  // of a wrapped line: they carry no number, no
                                  // breakpoint and can never be the paused line.
                                  final hasBp =
                                      lineNumber > 0 &&
                                      _hasBreakpoint(lineNumber);
                                  final debugger = widget.debugger;
                                  // Keep the marker while the debugger owns a
                                  // paused line and has not been torn down, so it
                                  // also survives a plain `running` step.
                                  final isPausedLine =
                                      debugger != null &&
                                      lineNumber > 0 &&
                                      debugger.currentPausedLine ==
                                          lineNumber &&
                                      debugger.state != DebugState.inactive;
                                  // Twice the size the old `●` glyph painted
                                  // (a 12px glyph draws a ~7px dot), kept inside
                                  // one row so it never overlaps its neighbours.
                                  final markerDiameter =
                                      _metrics.lineHeight * 0.7;
                                  // The caret's row is tinted in the gutter as
                                  // well (IntelliJ does this), but the paused
                                  // line keeps its own stronger colour so the
                                  // two never fight.
                                  final gutterTint = isPausedLine
                                      ? ThemeService.instance.colors.pausedLine
                                      : lineNumber == _caretLine
                                      ? ThemeService.instance.colors.selection
                                            .withValues(alpha: 0.10)
                                      : null;
                                  return GestureDetector(
                                    onTap: lineNumber > 0
                                        ? () => _toggleBreakpoint(lineNumber)
                                        : null,
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      height: _metrics.lineHeight,
                                      color: gutterTint,
                                      padding: const EdgeInsets.only(
                                        left: 2,
                                        right: gutterScrollbarInset,
                                      ),
                                      // Top-aligned: the number's line box
                                      // starts on the same row grid as the
                                      // code, so line 1 of both begin at the
                                      // same y and every row below matches.
                                      alignment: Alignment.topLeft,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          // Numbers first: the gutter's own
                                          // scrollbar owns the right edge, so
                                          // digits stay clear of it.
                                          Text(
                                            '$lineNumber',
                                            // The very same strut the code uses:
                                            // it fixes the row height AND the
                                            // baseline position, so the digit
                                            // sits on the code's baseline by
                                            // construction.
                                            strutStyle: _metrics.strutStyle,
                                            // Proportional leading, set
                                            // explicitly so the ambient
                                            // `TextHeightBehavior` cannot move
                                            // the digit off the code's baseline.
                                            textHeightBehavior:
                                                const TextHeightBehavior(
                                                  leadingDistribution:
                                                      TextLeadingDistribution
                                                          .proportional,
                                                ),
                                            // The caret's line is emphasised in
                                            // the gutter too, the way Xcode and
                                            // VS Code show the active line.
                                            style: TextStyle(
                                              // Same family as the code, so a
                                              // number never looks foreign
                                              // beside the text it labels.
                                              fontFamily: _metrics.fontFamily,
                                              fontFamilyFallback: const [
                                                EditorMetrics.fallbackFamily,
                                              ],
                                              fontSize:
                                                  _metrics.lineNumberFontSize,
                                              height:
                                                  _metrics.lineHeight /
                                                  _metrics.lineNumberFontSize,
                                              fontWeight:
                                                  lineNumber == _caretLine
                                                  ? FontWeight.bold
                                                  : null,
                                              color: lineNumber == _caretLine
                                                  ? ThemeService
                                                        .instance
                                                        .colors
                                                        .selection
                                                  : ThemeService
                                                        .instance
                                                        .colors
                                                        .editorLineNumberText,
                                            ),
                                          ),
                                          // Flexible so a three-digit line
                                          // number can never overflow the row.
                                          Flexible(
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: !isPausedLine && !hasBp
                                                  ? null
                                                  : FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          // The paused-line arrow
                                                          // and the breakpoint
                                                          // bullet are drawn
                                                          // together, so pausing on
                                                          // a breakpoint never
                                                          // hides the fact that it
                                                          // is a breakpoint.
                                                          if (isPausedLine)
                                                            Text(
                                                              '▶',
                                                              style: TextStyle(
                                                                color: ThemeService
                                                                    .instance
                                                                    .colors
                                                                    .selection,
                                                                fontSize: _metrics
                                                                    .markerFontSize,
                                                              ),
                                                            ),
                                                          if (hasBp)
                                                            Container(
                                                              width:
                                                                  markerDiameter,
                                                              height:
                                                                  markerDiameter,
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    ThemeService
                                                                        .instance
                                                                        .colors
                                                                        .error,
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Text Editor Area
                            Expanded(
                              child: Focus(
                                onKeyEvent: (node, event) =>
                                    _handleKeyEvent(event),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTapUp: (details) {
                                    _focusNode.requestFocus();
                                    _hoverDebounce?.cancel();
                                  },
                                  onSecondaryTapDown: (details) {
                                    _requestHover();
                                  },
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // Current-line band. Clicking anywhere on
                                      // a row - including the empty space past
                                      // the last character - puts the caret on
                                      // that line, and this paints the whole row
                                      // behind the code so the selection is
                                      // visible across the full editor width.
                                      //
                                      // The row comes from the renderer's own
                                      // caret rect, not from the gutter's wrap
                                      // model: if the cached rows ever lag behind
                                      // the text (an edit, a resize, a paste) the
                                      // band used to be painted a few rows above
                                      // the caret while the numbers still looked
                                      // aligned. Reading the caret rect makes that
                                      // disagreement impossible. Its height spans
                                      // every row of the logical line, so a
                                      // wrapped line is highlighted as a whole.
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: Builder(
                                            builder: (context) {
                                              final accent = ThemeService
                                                  .instance
                                                  .colors
                                                  .selection;
                                              // Measured here for an instant
                                              // response; a post-frame pass
                                              // corrects it when the field
                                              // scrolled after build (see
                                              // _queueBandUpdate).
                                              final band = _bandRectForCaret(
                                                metrics.lineHeight,
                                              );
                                              return Stack(
                                                clipBehavior: Clip.hardEdge,
                                                children: [
                                                  Positioned(
                                                    left: 0,
                                                    right: 0,
                                                    top: band.top,
                                                    height: band.height,
                                                    // Fill plus a hairline
                                                    // outline, the equivalent
                                                    // of VS Code's
                                                    // `editor.lineHighlightBackground`
                                                    // and
                                                    // `editor.lineHighlightBorder`.
                                                    child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        color: accent
                                                            .withValues(
                                                              alpha: 0.14,
                                                            ),
                                                        border: Border.all(
                                                          color: accent
                                                              .withValues(
                                                                alpha: 0.45,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      MouseRegion(
                                        onHover: (event) {
                                          // No manual offset here:
                                          // `_requestHover` derives the popup
                                          // anchor from the caret, and this
                                          // handler used to clobber it with
                                          // `event.position + 24` before that
                                          // ran, so a hover that found nothing
                                          // left the tooltip/autocomplete
                                          // anchored 24px below the mouse.
                                          _requestHover();
                                        },
                                        onExit: (event) {
                                          _hoverDebounce?.cancel();
                                          Timer(
                                            const Duration(milliseconds: 100),
                                            () {
                                              if (mounted) {
                                                setState(() {
                                                  _hoverInfo = null;
                                                });
                                              }
                                            },
                                          );
                                        },
                                        child: TextField(
                                          key: _editorKey,
                                          controller: _controller,
                                          focusNode: _focusNode,
                                          scrollController:
                                              _editorScrollController,
                                          maxLines: null,
                                          expands: true,
                                          // Pin every line to exactly
                                          // [editorLineHeight]; Flutter rounds
                                          // a paragraph's line height to a whole
                                          // logical pixel, so the strut keeps
                                          // the render and the gutter on the
                                          // same grid.
                                          strutStyle: _metrics.strutStyle,
                                          style: _metrics.textStyle.copyWith(
                                            color: ThemeService
                                                .instance
                                                .colors
                                                .editorText,
                                          ),
                                          decoration:
                                              const InputDecoration.collapsed(
                                                hintText:
                                                    '// Type code here...',
                                              ),
                                        ),
                                      ),
                                      if (_showAutocomplete)
                                        Positioned.fill(
                                          child: TapRegion(
                                            onTapOutside: (_) =>
                                                _dismissCompletion(),
                                            child: const SizedBox.expand(),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showAutocomplete)
            AutocompletePopup(
              items: _completionItems,
              position: _cursorScreenOffset,
              selectedIndex: _selectedCompletionIndex,
              maxWidth: 300,
              currentWord: _currentWordAtCursor(),
              onSelect: (index) {
                if (index == _selectedCompletionIndex) {
                  _acceptSelected();
                } else {
                  setState(() {
                    _selectedCompletionIndex = index;
                  });
                }
              },
              onDismiss: _dismissCompletion,
            ),
          if (_showHover && _hoverInfo != null)
            HoverTooltip(
              hoverInfo: _hoverInfo!,
              position: _cursorScreenOffset,
              maxWidth: 300,
            ),
        ],
      ),
    );
  }
}
