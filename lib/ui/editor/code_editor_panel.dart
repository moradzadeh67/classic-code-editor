import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/lsp_models.dart';
import '../../services/file_service.dart';
import '../../services/lsp_service.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';
import 'autocomplete_popup.dart';
import 'hover_tooltip.dart';

/// The main code-editor area.
///
/// This widget intentionally has **no fixed height**. It expands to fill all
/// of the space given to it by its parent (it is placed inside an [Expanded]),
/// so the editor always stretches from the top of the middle area down to the
/// top of the console — with no leftover gap or vertical cutoff.
///
/// Integrates with [LspService] to provide autocomplete suggestions and hover
/// documentation tooltips in the retro 1990s style.
class CodeEditorPanel extends StatefulWidget {
  final FileService fileService;
  final LspService lspService;

  const CodeEditorPanel({
    super.key,
    required this.fileService,
    required this.lspService,
  });

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _editorKey = GlobalKey();

  /// Current offset of the cursor in screen coordinates, for popup/hover.
  Offset _cursorScreenOffset = Offset.zero;

  /// Completion items from the LSP server.
  List<CompletionItem> _completionItems = [];
  int _selectedCompletionIndex = 0;

  /// Hover info from the LSP server.
  HoverInfo? _hoverInfo;

  /// Timers for debouncing.
  Timer? _completionDebounce;
  Timer? _hoverDebounce;

  /// Whether autocomplete popup is currently visible.
  bool get _showAutocomplete => _completionItems.isNotEmpty;

  /// Whether hover tooltip is currently visible.
  bool get _showHover => _hoverInfo != null;

  /// The current file path for LSP requests.
  String? get _filePath => widget.fileService.currentFilePath;

  int? _lastActiveTabIndex;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.fileService.fileContent);
    _controller.addListener(_onTextChanged);
    widget.fileService.addListener(_onFileServiceChanged);
    _lastActiveTabIndex = widget.fileService.activeTabIndex;
  }

  @override
  void didUpdateWidget(covariant CodeEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _controller.removeListener(_onTextChanged);
    widget.fileService.removeListener(_onFileServiceChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_controller.text != widget.fileService.fileContent) {
      widget.fileService.updateContent(_controller.text);
    }

    // Trigger autocomplete on text change (debounced)
    _completionDebounce?.cancel();
    _completionDebounce = Timer(const Duration(milliseconds: 300), () {
      _requestCompletion();
    });
  }

  void _onFileServiceChanged() {
    final newIndex = widget.fileService.activeTabIndex;
    if (_lastActiveTabIndex != newIndex ||
        _controller.text != widget.fileService.fileContent) {
      _lastActiveTabIndex = newIndex;
      _updateControllerText();
    }
    setState(() {});
  }

  void _updateControllerText() {
    final newText = widget.fileService.fileContent;
    if (_controller.text != newText) {
      final selection = _controller.selection;
      _controller.text = newText;
      if (selection.isValid && selection.end <= newText.length) {
        _controller.selection = selection;
      }
    }
    _dismissCompletion();
    _dismissHover();
  }

  /// Computes the current cursor position in screen coordinates.
  Offset _computeCursorScreenPosition() {
    final editorContext = _editorKey.currentContext;
    if (editorContext == null) return Offset.zero;

    final RenderBox? renderBox = editorContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return Offset.zero;

    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return Offset.zero;

    // Get global position of the editor
    final Offset editorGlobalPosition = renderBox.localToGlobal(Offset.zero);

    // Count lines before cursor to estimate Y position
    final text = _controller.text;
    final offset = selection.start;

    const double lineHeight = 16.0; // Approximate line height for 13px font
    int lineNumber = 0;

    for (int i = 0; i < offset && i < text.length; i++) {
      if (text[i] == '\n') {
        lineNumber++;
      }
    }

    // Calculate position relative to editor content area (accounting for padding)
    final Offset cursorPosition =
        editorGlobalPosition + Offset(8, 8 + lineNumber * lineHeight);

    return cursorPosition + const Offset(0, 24); // Position below cursor
  }

  void _requestCompletion() async {
    final filePath = _filePath;
    if (filePath == null || !widget.lspService.isConnected) return;

    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;

    final offset = selection.start;
    final (line, column) = _offsetToLineColumn(_controller.text, offset);

    final items = await widget.lspService.requestCompletion(
      filePath,
      line + 1,
      column + 1,
    );

    if (items.isNotEmpty && mounted) {
      setState(() {
        _completionItems = items;
        _selectedCompletionIndex = 0;
        _cursorScreenOffset = _computeCursorScreenPosition();
      });
    }
  }

  /// Converts a character offset into (line, column) — 0-based.
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

    // Find the word boundary before the cursor so we replace it
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

    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: newOffset);

    _dismissCompletion();
  }

  void _dismissCompletion() {
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

  /// Request hover info from the LSP server.
  void _requestHover() {
    final filePath = _filePath;
    if (filePath == null || !widget.lspService.isConnected) return;

    // Debounce: wait 500ms before requesting hover
    _hoverDebounce?.cancel();
    _hoverDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (_controller.selection.isValid && _controller.selection.isCollapsed) {
        final offset = _controller.selection.start;
        final (line, column) = _offsetToLineColumn(_controller.text, offset);

        final hoverInfo = await widget.lspService.requestHover(
          filePath,
          line + 1,
          column + 1,
        );

        if (hoverInfo != null && mounted) {
          setState(() {
            _hoverInfo = hoverInfo;
            _cursorScreenOffset = _computeCursorScreenPosition();
          });
        }
      }
    });
  }

  /// Handles keyboard navigation for autocomplete.
  void _handleKeyEvent(KeyEvent event) {
    if (!_showAutocomplete) return;

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _moveSelection(1);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _moveSelection(-1);
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        _acceptSelected();
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _dismissCompletion();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = widget.fileService.activeTab;

    if (activeTab == null) {
      return Container(
        decoration: RetroBorder.sunken(
          backgroundColor: ThemeService.instance.colors.editorBackground,
        ),
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

    return Stack(
      children: [
        Container(
          decoration: RetroBorder.sunken(
            backgroundColor: ThemeService.instance.colors.editorBackground,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Focus(
                    focusNode: _focusNode,
                    child: KeyboardListener(
                      focusNode: _focusNode,
                      onKeyEvent: _handleKeyEvent,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (details) {
                          // Request focus so we can capture key events
                          _focusNode.requestFocus();

                          // Reset hover timer since we're interacting with the editor
                          _hoverDebounce?.cancel();
                        },
                        onSecondaryTapDown: (details) {
                          // Trigger hover request on hold/press
                          _requestHover();
                        },
                        child: MouseRegion(
                          onHover: (event) {
                            _cursorScreenOffset =
                                event.position + const Offset(0, 24);
                            _requestHover();
                          },
                          onExit: (event) {
                            _hoverDebounce?.cancel();
                            Timer(const Duration(milliseconds: 100), () {
                              if (mounted) {
                                setState(() {
                                  _hoverInfo = null;
                                });
                              }
                            });
                          },
                          child: TextField(
                            key: _editorKey,
                            controller: _controller,
                            focusNode: _focusNode,
                            maxLines: null,
                            expands: true,
                            style: TextStyle(
                              fontFamily: 'Menlo',
                              fontSize: 13,
                              color: ThemeService.instance.colors.editorText,
                            ),
                            decoration: const InputDecoration.collapsed(
                              hintText: '// Type code here...',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Autocomplete popup overlay
        if (_showAutocomplete)
          AutocompletePopup(
            items: _completionItems,
            position: _cursorScreenOffset,
            selectedIndex: _selectedCompletionIndex,
            maxWidth: 300,
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
        // Hover tooltip overlay
        if (_showHover && _hoverInfo != null)
          HoverTooltip(
            hoverInfo: _hoverInfo!,
            position: _cursorScreenOffset,
            maxWidth: 300,
          ),
      ],
    );
  }
}
