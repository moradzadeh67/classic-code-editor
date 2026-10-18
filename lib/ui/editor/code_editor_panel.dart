import 'dart:async';

import 'package:flutter/material.dart';
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
class _GutterRowsCache {
  final String text;
  final double maxWidth;
  final TextScaler scaler;
  final List<int> rows;
  final double fontSize;

  const _GutterRowsCache(
    this.text,
    this.maxWidth,
    this.scaler,
    this.rows,
    this.fontSize,
  );
}

/// The main code-editor area.
class CodeEditorPanel extends StatefulWidget {
  final FileService fileService;
  final LspService lspService;
  final BaseDebugger? debugger;
  final CodeController? controller;

  const CodeEditorPanel({
    super.key,
    required this.fileService,
    required this.lspService,
    this.debugger,
    this.controller,
  });

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel> {
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

  /// Kept in sync with the editor so the gutter never scrolls out of step.
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _gutterScrollController = ScrollController();

  /// Memoised result of the last gutter wrap measurement.
  _GutterRowsCache? _gutterRowsCache;

  /// Measured advance of one monospace character, and the scale it was
  /// measured at. See `_charAdvance`.
  double? _charAdvanceCache;
  TextScaler? _charAdvanceScaler;
  double? _charAdvanceFontSize;

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
    _controller.addListener(_onTextChanged);
    _controller.addListener(_onCaretMoved);
    _editorScrollController.addListener(_syncGutterScroll);
    widget.fileService.addListener(_onFileServiceChanged);
    widget.debugger?.addListener(_onDebuggerChanged);
    EditorSettingsService.instance.addListener(_onFontSizeChanged);
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
    EditorSettingsService.instance.removeListener(_onFontSizeChanged);
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

    setState(() {
      _isTyping = true;
    });

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
    for (var i = 0; i < offset; i++) {
      if (text.codeUnitAt(i) == 0x0A) line++;
    }
    if (line != _caretLine) {
      setState(() => _caretLine = line);
    }
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

  void _onDebuggerChanged() {
    if (mounted) setState(() {});
  }

  void _onFontSizeChanged() {
    _charAdvanceCache = null;
    _charAdvanceScaler = null;
    _gutterRowsCache = null;
    if (mounted) {
      setState(() {});
      // Schedule scroll sync after layout rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncGutterScroll();
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
    final config = LanguageConfig.fromExtension(_filePath);
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
    final filePath = _filePath;
    final config = LanguageConfig.fromExtension(filePath);
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
  EditorMetrics get _metrics =>
      EditorMetrics.forFontSize(EditorSettingsService.instance.fontSize);

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
        _charAdvanceFontSize == _metrics.fontSize) {
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
        cached.fontSize == _metrics.fontSize) {
      return cached.rows;
    }

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
      data: CodeThemeData(styles: MultiLanguageHighlighter.getThemeStyles()),
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
                        // Measure how the editor really wraps at this width so
                        // every visual row gets a gutter row of its own.
                        final metrics = _metrics;
                        final editorWidth =
                            (constraints.maxWidth -
                                    metrics.gutterWidth -
                                    gutterGap)
                                .clamp(1.0, double.infinity);
                        final gutterRows = _gutterRows(
                          _controller.text,
                          editorWidth,
                          MediaQuery.textScalerOf(context),
                        );

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
                              child: ListView.builder(
                                controller: _gutterScrollController,
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
                                  final hasBp = _hasBreakpoint(lineNumber);
                                  final debugger = widget.debugger;
                                  // Keep the marker while the debugger owns a
                                  // paused line and has not been torn down, so it
                                  // also survives a plain `running` step.
                                  final isPausedLine =
                                      debugger != null &&
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
                                    onTap: () => _toggleBreakpoint(lineNumber),
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
                                            // construction. A bare `height`
                                            // only resizes the box and left the
                                            // digits ~1.8px above the code.
                                            strutStyle: _metrics.strutStyle,
                                            // The caret's line is emphasised in
                                            // the gutter too, the way Xcode and
                                            // VS Code show the active line.
                                            style: TextStyle(
                                              fontFamily: 'Menlo',
                                              fontSize:
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
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: ListenableBuilder(
                                            listenable: _editorScrollController,
                                            builder: (context, _) {
                                              final scrollOffset =
                                                  _editorScrollController
                                                      .hasClients
                                                  ? _editorScrollController
                                                        .offset
                                                  : 0.0;
                                              final accent = ThemeService
                                                  .instance
                                                  .colors
                                                  .selection;
                                              final row = _visualRowForLine(
                                                gutterRows,
                                                _caretLine,
                                              );
                                              return Stack(
                                                clipBehavior: Clip.hardEdge,
                                                children: [
                                                  Positioned(
                                                    left: 0,
                                                    right: 0,
                                                    top:
                                                        row *
                                                            metrics.lineHeight -
                                                        scrollOffset,
                                                    height: metrics.lineHeight,
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
                                          _cursorScreenOffset =
                                              event.position +
                                              const Offset(0, 24);
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
