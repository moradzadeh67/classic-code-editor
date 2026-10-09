import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../models/debugger_models.dart';
import '../../models/language_config.dart';
import '../../models/lsp_models.dart';
import '../../services/file_service.dart';
import '../../services/lsp_service.dart';
import '../../services/theme_service.dart';
import '../../services/base_debugger.dart';
import '../../utils/completion_filter.dart';
import '../../utils/multi_language_highlighter.dart';
import 'autocomplete_popup.dart';
import 'hover_tooltip.dart';

/// Font size of the code editor's text.
///
/// Shared with the gutter so its rows line up exactly with the code. The gutter
/// used to hardcode a row height of `19.0` while the editor renders
/// `13 * 1.45 = 18.85` per line, which drifts about 0.15px per line (roughly
/// 45px over a 300-line file) and makes the breakpoint bullets and the
/// paused-line marker land on the wrong row.
const double editorFontSize = 13.0;

/// Line-height multiplier applied to [editorFontSize].
const double editorLineHeightFactor = 1.45;

/// Height of a single line of code, in logical pixels.
const double editorLineHeight = editorFontSize * editorLineHeightFactor;

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
    widget.fileService.addListener(_onFileServiceChanged);
    widget.debugger?.addListener(_onDebuggerChanged);
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
    widget.fileService.removeListener(_onFileServiceChanged);
    widget.debugger?.removeListener(_onDebuggerChanged);
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

  void _onDebuggerChanged() {
    if (mounted) setState(() {});
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
          editorGlobalPosition + Offset(8, 8 + lineNumber * editorLineHeight);

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

    final lineCount = (_controller.text.split('\n').length).clamp(1, 9999);

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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Gutter for breakpoints & line numbers
                        Container(
                          width: 52,
                          color:
                              ThemeService.instance.colors.editorLineNumberBg,
                          child: ListView.builder(
                            itemCount: lineCount,
                            itemBuilder: (context, index) {
                              final lineNumber = index + 1;
                              final hasBp = _hasBreakpoint(lineNumber);
                              final debugger = widget.debugger;
                              // Keep the marker while the debugger owns a
                              // paused line and has not been torn down, so it
                              // also survives a plain `running` step.
                              final isPausedLine =
                                  debugger != null &&
                                  debugger.currentPausedLine == lineNumber &&
                                  debugger.state != DebugState.inactive;
                              return GestureDetector(
                                onTap: () => _toggleBreakpoint(lineNumber),
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  height: editorLineHeight,
                                  color: isPausedLine
                                      ? ThemeService.instance.colors.pausedLine
                                      : null,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        child: Center(
                                          child: !isPausedLine && !hasBp
                                              ? null
                                              : FittedBox(
                                                  fit: BoxFit.scaleDown,
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
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      if (hasBp)
                                                        Text(
                                                          '●',
                                                          style: TextStyle(
                                                            color: ThemeService
                                                                .instance
                                                                .colors
                                                                .error,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                        ),
                                      ),
                                      Text(
                                        '$lineNumber',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontFamily: 'Menlo',
                                          color: ThemeService
                                              .instance
                                              .colors
                                              .editorLineNumberText,
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
                            onKeyEvent: (node, event) => _handleKeyEvent(event),
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
                                  MouseRegion(
                                    onHover: (event) {
                                      _cursorScreenOffset =
                                          event.position + const Offset(0, 24);
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
                                      maxLines: null,
                                      expands: true,
                                      style: TextStyle(
                                        fontFamily: 'Menlo',
                                        fontSize: editorFontSize,
                                        height: editorLineHeightFactor,
                                        color: ThemeService
                                            .instance
                                            .colors
                                            .editorText,
                                      ),
                                      decoration:
                                          const InputDecoration.collapsed(
                                            hintText: '// Type code here...',
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
