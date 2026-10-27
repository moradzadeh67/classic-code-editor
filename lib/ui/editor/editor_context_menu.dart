import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/theme_service.dart';
import '../retro/retro_border.dart';
import '../shell/retro_menu_item.dart';

/// Height of one row of the editor's context menu.
const double kEditorMenuRowHeight = 26;

/// Smallest and largest width the panel may take (it is sized by its content
/// inside these bounds).
const double kEditorMenuMinWidth = 180;
const double kEditorMenuMaxWidth = 280;

/// The code editor's right-click menu: Cut, Copy, Paste, Select All.
///
/// Supplied to the editor's `TextField` as its `contextMenuBuilder`. Flutter
/// hands the toolbar slot to this widget with tight, window-sized constraints,
/// so the widget is a full-area [Stack] whose only full-size child is a
/// **transparent tap barrier** (a click outside closes the menu); the visible
/// panel is a `Positioned` child sized by its content and anchored at the
/// pointer, clamped so it always stays inside the editor.
///
/// Actions run through the field's own [EditableTextState], never a private copy
/// of the clipboard or selection logic.
class EditorContextMenu extends StatefulWidget {
  const EditorContextMenu({
    super.key,
    required this.state,
    required this.anchor,
    required this.boundary,
  });

  /// The field's own editing state: its selection, clipboard actions and
  /// toolbar visibility.
  final EditableTextState state;

  /// Top-left of the menu in this widget's coordinate space (the secondary
  /// click, already converted to the editor's space).
  final Offset anchor;

  /// Size of the editor area the panel must stay inside.
  final Size boundary;

  static const Key menuKey = ValueKey<String>('editor-context-menu');
  static const Key barrierKey = ValueKey<String>('editor-context-menu-barrier');

  static const String cutLabel = 'Cut';
  static const String copyLabel = 'Copy';
  static const String pasteLabel = 'Paste';
  static const String selectAllLabel = 'Select All';

  /// Key of one row, so tests can read its enabled state.
  static Key rowKey(String label) =>
      ValueKey<String>('editor-context-menu-row-$label');

  @override
  State<EditorContextMenu> createState() => _EditorContextMenuState();
}

class _EditorContextMenuState extends State<EditorContextMenu> {
  /// Whether the clipboard holds text; `null` until the platform answers.
  bool? _canPaste;

  @override
  void initState() {
    super.initState();
    _checkClipboard();
    // Esc closes the menu without stealing focus from the editor.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _dismiss();
      return true;
    }
    return false;
  }

  void _dismiss() {
    if (!mounted) return;
    widget.state.hideToolbar();
  }

  Future<void> _checkClipboard() async {
    var hasText = false;
    try {
      hasText = await Clipboard.hasStrings();
    } catch (_) {
      // A platform without the clipboard channel: leave Paste disabled.
      hasText = false;
    }
    if (!mounted) return;
    setState(() => _canPaste = hasText);
  }

  TextEditingValue get _value => widget.state.textEditingValue;

  bool get _hasSelection {
    final selection = _value.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  void _run(VoidCallback action) {
    widget.state.hideToolbar();
    action();
  }

  static const List<String> _labels = <String>[
    EditorContextMenu.cutLabel,
    EditorContextMenu.copyLabel,
    EditorContextMenu.pasteLabel,
    EditorContextMenu.selectAllLabel,
  ];

  static const List<String> _shortcuts = <String>[
    'Cmd X',
    'Cmd C',
    'Cmd V',
    'Cmd A',
  ];

  /// Width the panel will take, measured from its own labels/shortcuts (the
  /// same `RetroMenuMetrics` the menu bar uses), inside the allowed bounds.
  static double get menuWidth => RetroMenuMetrics.menuWidth(
    _labels,
    RetroMenuMetrics.shortcutColumnWidth(_shortcuts),
  ).clamp(kEditorMenuMinWidth, kEditorMenuMaxWidth);

  /// Height of one separator: a single hairline with air above and below.
  static const double separatorHeight = 7;

  /// Height of the panel: four rows, one separator, plus the 2 px bevel and the
  /// 2 px padding on both sides (8 px in total).
  static double get menuHeight =>
      _labels.length * kEditorMenuRowHeight + separatorHeight + 8;

  /// The clamped top-left: never outside [boundary] (4 px margin).
  Offset get _clampedAnchor {
    const margin = 4.0;
    final maxLeft = (widget.boundary.width - menuWidth - margin).clamp(
      margin,
      double.infinity,
    );
    final maxTop = (widget.boundary.height - menuHeight - margin).clamp(
      margin,
      double.infinity,
    );
    return Offset(
      widget.anchor.dx.clamp(margin, maxLeft),
      widget.anchor.dy.clamp(margin, maxTop),
    );
  }

  @override
  Widget build(BuildContext context) {
    final panelAnchor = _clampedAnchor;

    return Stack(
      children: [
        // The full-size part is only this invisible barrier.
        Positioned.fill(
          child: GestureDetector(
            key: EditorContextMenu.barrierKey,
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: const ColoredBox(color: Color(0x00000000)),
          ),
        ),
        Positioned(
          left: panelAnchor.dx,
          top: panelAnchor.dy,
          child: _buildPanel(context),
        ),
      ],
    );
  }

  Widget _buildPanel(BuildContext context) {
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: kEditorMenuMinWidth,
          maxWidth: kEditorMenuMaxWidth,
        ),
        child: Container(
          key: EditorContextMenu.menuKey,
          height: menuHeight,
          decoration: RetroBorder.raised(
            backgroundColor: ThemeService.instance.uiColors['panel'],
          ),
          // 2 px frame inside the retro bevel, like the menu bar popups.
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row(
                label: EditorContextMenu.cutLabel,
                shortcut: 'Cmd X',
                enabled: _hasSelection,
                onTap: () => _run(
                  () =>
                      widget.state.cutSelection(SelectionChangedCause.toolbar),
                ),
              ),
              _row(
                label: EditorContextMenu.copyLabel,
                shortcut: 'Cmd C',
                enabled: _hasSelection,
                onTap: () => _run(
                  () =>
                      widget.state.copySelection(SelectionChangedCause.toolbar),
                ),
              ),
              _row(
                label: EditorContextMenu.pasteLabel,
                shortcut: 'Cmd V',
                enabled: _canPaste ?? false,
                onTap: () => _run(
                  () => widget.state.pasteText(SelectionChangedCause.toolbar),
                ),
              ),
              // One neutral hairline: the old two-etched-line separator used
              // `borderLight`, which is a pale yellow in some themes and read as
              // a stray yellow rule.
              SizedBox(
                height: separatorHeight,
                child: Center(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: RetroMenuMetrics.dividerInset,
                    ),
                    color: ThemeService.instance.colors.borderDark,
                  ),
                ),
              ),
              _row(
                label: EditorContextMenu.selectAllLabel,
                shortcut: 'Cmd A',
                enabled: _value.text.isNotEmpty,
                onTap: () => _run(
                  () => widget.state.selectAll(SelectionChangedCause.toolbar),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row({
    required String label,
    required String shortcut,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return EditorContextMenuRow(
      key: EditorContextMenu.rowKey(label),
      label: label,
      shortcut: shortcut,
      enabled: enabled,
      onTap: onTap,
    );
  }
}

/// One row: label on the left, shortcut column on the right, `menuActive`
/// highlight on hover — the same metrics and colours as [RetroMenuItem].
class EditorContextMenuRow extends StatefulWidget {
  const EditorContextMenuRow({
    super.key,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.shortcut,
  });

  final String label;
  final String? shortcut;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<EditorContextMenuRow> createState() => _EditorContextMenuRowState();
}

class _EditorContextMenuRowState extends State<EditorContextMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = ThemeService.instance.colors;
    final active = widget.enabled && _hovered;
    final foreground = !widget.enabled
        ? colors.shadow
        : active
        ? colors.menuActiveText
        : colors.text;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: Container(
            height: kEditorMenuRowHeight,
            color: active ? colors.menuActive : Colors.transparent,
            padding: EdgeInsets.only(
              left:
                  RetroMenuMetrics.leftPadding +
                  RetroMenuMetrics.checkGutterWidth,
              right: RetroMenuMetrics.rightPadding,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RetroMenuMetrics.textStyle.copyWith(
                      color: foreground,
                      // Without this the row inherits whatever decoration the
                      // toolbar's ambient text style carries (it painted a
                      // yellow underline under every label and shortcut).
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                if (widget.shortcut != null) ...[
                  const SizedBox(width: RetroMenuMetrics.shortcutGap),
                  Text(
                    widget.shortcut!,
                    style: RetroMenuMetrics.textStyle.copyWith(
                      color: foreground,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
