import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/theme_service.dart';

/// Shared sizing/text constants for the retro menu chrome.
///
/// Every dropdown (File / Edit / View / Run / Tools / Help) is built from the
/// widgets in this file so the look is defined exactly once. These values are
/// deliberately NOT tied to the editor font size: the menus keep their classic
/// 9x metrics while `Cmd +` / `Cmd -` only resize the code editor.
class RetroMenuMetrics {
  const RetroMenuMetrics._();

  /// Height of one menu row.
  static const double itemHeight = 22;

  /// Total height of a separator row (2px inset + two 1px etched lines).
  static const double separatorHeight = 6;

  /// Left gutter that holds the check mark of the active theme.
  static const double checkGutterWidth = 20;

  static const double leftPadding = 4;
  static const double rightPadding = 16;

  /// Gap between the label and the right-aligned shortcut column.
  static const double shortcutGap = 12;

  /// Shortcut column is sized from the real text width, within these bounds.
  static const double minShortcutWidth = 48;
  static const double maxShortcutWidth = 68;

  static const double minMenuWidth = 160;
  static const double maxMenuWidth = 320;

  static const double dividerInset = 6;

  static const String uiFontFamily = 'Arial';
  static const double uiFontSize = 12;

  /// Base label/shortcut style: Arial 12 w500, like the rest of the chrome.
  /// The color is supplied per state by [RetroMenuItem].
  static const TextStyle textStyle = TextStyle(
    fontFamily: uiFontFamily,
    fontSize: uiFontSize,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  /// Width of the shortcut column for [shortcuts] (max measured width + gap,
  /// clamped to [minShortcutWidth]..[maxShortcutWidth]).
  static double shortcutColumnWidth(Iterable<String> shortcuts) {
    var widest = 0.0;
    for (final shortcut in shortcuts) {
      final width = measureText(shortcut);
      if (width > widest) widest = width;
    }
    return (widest + 8).clamp(minShortcutWidth, maxShortcutWidth);
  }

  /// Real rendered width of [text] in the menu font.
  static double measureText(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Width every row of one dropdown gets (rows must share it so the labels and
  /// the shortcut column line up). Measured from the real text, then clamped.
  static double menuWidth(Iterable<String> labels, double shortcutColumnWidth) {
    var widestLabel = 0.0;
    for (final label in labels) {
      final width = measureText(label);
      if (width > widestLabel) widestLabel = width;
    }
    final content =
        leftPadding +
        checkGutterWidth +
        widestLabel +
        shortcutGap +
        shortcutColumnWidth +
        rightPadding;
    return content.clamp(minMenuWidth, maxMenuWidth);
  }
}

/// One row of a retro dropdown: check-mark gutter, label, shortcut column.
///
/// Implemented as a [PopupMenuEntry] (instead of `PopupMenuItem`) so the row
/// owns its own hover/keyboard-focus state: both paint a full-width
/// `menuActive` background with `menuActiveText` text, which the Material item
/// cannot do (Material 2 ignores `labelTextStyle`).
class RetroMenuItem<T> extends PopupMenuEntry<T> {
  const RetroMenuItem({
    super.key,
    required this.value,
    required this.label,
    this.shortcut,
    this.checked = false,
    this.enabled = true,
    this.shortcutColumnWidth = RetroMenuMetrics.minShortcutWidth,
    this.rowWidth = 0,
  });

  final T value;
  final String label;
  final String? shortcut;

  /// Draws a check mark in the left gutter (used by the theme entries).
  final bool checked;

  final bool enabled;

  /// Width reserved for [shortcut]; filled in by the menu builder so all rows
  /// of one dropdown line up.
  final double shortcutColumnWidth;

  /// Exact width of this row (0 = let the popup size itself).
  ///
  /// A fixed width is what keeps `IntrinsicWidth` from under-sizing the popup:
  /// the row can then use an `Expanded` label without collapsing the menu.
  final double rowWidth;

  @override
  double get height => RetroMenuMetrics.itemHeight;

  @override
  bool represents(T? other) => other == value;

  /// Returns the same row with the shared metrics of its dropdown.
  RetroMenuItem<T> withMetrics({
    required double rowWidth,
    required double shortcutColumnWidth,
  }) => RetroMenuItem<T>(
    key: key,
    value: value,
    label: label,
    shortcut: shortcut,
    checked: checked,
    enabled: enabled,
    shortcutColumnWidth: shortcutColumnWidth,
    rowWidth: rowWidth,
  );

  @override
  State<RetroMenuItem<T>> createState() => _RetroMenuItemState<T>();
}

class _RetroMenuItemState<T> extends State<RetroMenuItem<T>> {
  bool _hovered = false;
  bool _focused = false;

  bool get _active => widget.enabled && (_hovered || _focused);

  void _select() {
    if (!widget.enabled) return;
    // Closing the route with the value is what PopupMenuButton listens to.
    Navigator.pop<T>(context, widget.value);
  }

  static const Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      };

  @override
  Widget build(BuildContext context) {
    // Rule 8: theme colors are read here (never captured in a const widget).
    final colors = ThemeService.instance.colors;
    final Color background = _active ? colors.menuActive : colors.panel;
    final Color foreground = !widget.enabled
        ? colors.shadow
        : _active
        ? colors.menuActiveText
        : colors.text;

    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.label,
        child: FocusableActionDetector(
          enabled: widget.enabled,
          shortcuts: _shortcuts,
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (intent) {
                _select();
                return null;
              },
            ),
          },
          onShowHoverHighlight: (value) {
            if (_hovered != value) setState(() => _hovered = value);
          },
          onShowFocusHighlight: (value) {
            if (_focused != value) setState(() => _focused = value);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _select,
            // A fixed width (measured by the menu builder) plus a flexible
            // label means a long entry can never overflow its row: it clips
            // instead, and every row of the dropdown stays aligned.
            child: SizedBox(
              width: widget.rowWidth > 0 ? widget.rowWidth : null,
              height: RetroMenuMetrics.itemHeight,
              child: Container(
                color: background,
                padding: const EdgeInsets.only(
                  left: RetroMenuMetrics.leftPadding,
                  right: RetroMenuMetrics.rightPadding,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: RetroMenuMetrics.checkGutterWidth,
                      child: widget.checked
                          ? RetroMenuCheck(color: foreground)
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: RetroMenuMetrics.textStyle.copyWith(
                          color: foreground,
                        ),
                      ),
                    ),
                    if (widget.shortcut != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: RetroMenuMetrics.shortcutGap,
                        ),
                        child: SizedBox(
                          width: widget.shortcutColumnWidth,
                          child: Text(
                            widget.shortcut!,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            softWrap: false,
                            style: RetroMenuMetrics.textStyle.copyWith(
                              color: foreground,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The etched separator used between menu groups (1px dark + 1px light).
class RetroMenuSeparator<T> extends PopupMenuEntry<T> {
  const RetroMenuSeparator({super.key});

  @override
  double get height => RetroMenuMetrics.separatorHeight;

  @override
  bool represents(T? value) => false;

  @override
  State<RetroMenuSeparator<T>> createState() => _RetroMenuSeparatorState<T>();
}

class _RetroMenuSeparatorState<T> extends State<RetroMenuSeparator<T>> {
  @override
  Widget build(BuildContext context) {
    final colors = ThemeService.instance.colors;
    return SizedBox(
      height: RetroMenuMetrics.separatorHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RetroMenuMetrics.dividerInset,
          vertical: 2,
        ),
        child: Column(
          children: [
            Container(height: 1, color: colors.shadow),
            Container(height: 1, color: colors.borderLight),
          ],
        ),
      ),
    );
  }
}

/// Sharp 2px check mark drawn into the item's left gutter.
///
/// Painted instead of using a font glyph so it looks identical on every theme
/// and never depends on icon fonts.
class RetroMenuCheck extends StatelessWidget {
  const RetroMenuCheck({super.key, required this.color, this.size = 11});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CheckPainter(color)),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.10, size.height * 0.55)
      ..lineTo(size.width * 0.40, size.height * 0.85)
      ..lineTo(size.width * 0.92, size.height * 0.15);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => oldDelegate.color != color;
}

/// The 2px raised frame of a dropdown.
///
/// `shape:` on `PopupMenuButton` expects a [ShapeBorder], so the retro frame is
/// expressed as one: sharp corners (no radius), top/left light edge and
/// right/bottom dark edge, no shadow.
class RetroPopupShape extends ShapeBorder {
  const RetroPopupShape({this.width = 2});

  final double width;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect.deflate(width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final colors = ThemeService.instance.colors;
    Border(
      top: BorderSide(color: colors.borderLight, width: width),
      left: BorderSide(color: colors.borderLight, width: width),
      right: BorderSide(color: colors.borderDark, width: width),
      bottom: BorderSide(color: colors.borderDark, width: width),
    ).paint(canvas, rect);
  }

  @override
  ShapeBorder scale(double t) => RetroPopupShape(width: width * t);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => t < 0.5 ? a : this;

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => t < 0.5 ? this : b;
}
