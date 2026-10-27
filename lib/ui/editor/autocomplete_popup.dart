import 'package:flutter/material.dart';

import '../../models/syntax_scheme.dart';
import '../../models/lsp_models.dart';
import '../../services/editor_settings_service.dart';
import '../../services/theme_service.dart';
import '../../utils/completion_kind.dart';
import '../retro/retro_border.dart';
import 'completion_doc_panel.dart';

/// A retro-styled autocomplete dropdown that appears below the editor
/// cursor when the language server provides completion suggestions.
///
/// This widget is intentionally **purely presentational**: it owns no
/// [FocusNode] and installs no [Focus] / [KeyboardListener] of its own.
///
/// Why: the editor's `TextField` is the sole owner of the editor's
/// `FocusNode`, and an ancestor [Focus] widget handles Up/Down/Enter/Escape
/// navigation. Attaching a second focus node here (or reusing the editor's
/// node) previously created a cycle in the focus tree, which made Flutter
/// assert `child != this` in `FocusNode._reparent` and showed the red error
/// screen. Selection changes are therefore driven entirely through the
/// [onSelect] callback — keyboard from the ancestor [Focus], mouse from the
/// taps below.
class AutocompletePopup extends StatelessWidget {
  /// The completion candidates to display.
  ///
  /// These are already filtered client-side by [CodeEditorPanel] to only
  /// include labels that start with [currentWord], so the popup never shows
  /// irrelevant suggestions (e.g. typing "prin" surfaces "print", not
  /// "pragma").
  final List<CompletionItem> items;

  /// The caret rectangle, in the editor's own (Stack) coordinates.
  ///
  /// Placement is derived from this and [bounds]; the window size is never
  /// consulted, so a popup anchored near the bottom of a short editor cannot
  /// end up behind the Console panel.
  final Rect anchor;

  /// Size of the editor area the popup and its documentation panel must stay
  /// inside.
  final Size bounds;

  /// Index of the currently highlighted item.
  final int selectedIndex;

  /// Maximum width of the dropdown.
  final double maxWidth;

  /// Called with the index of the item the user highlighted or tapped.
  final ValueChanged<int> onSelect;

  /// Called when the user dismisses the dropdown.
  final VoidCallback onDismiss;

  /// The identifier fragment the user is currently typing (e.g. "prin").
  ///
  /// Used purely to style the matching prefix of each label in bold, mirroring
  /// the retro IDEs where the typed portion is visually distinguished.
  final String currentWord;

  /// Plain-text documentation for the highlighted item, or `null` when there
  /// is nothing to show (the panel is then hidden).
  final String? documentation;

  /// Key of the dropdown container, so tests can measure its real rectangle.
  static const Key listKey = Key('completion-popup-list');

  /// Key of the documentation panel container.
  static const Key docPanelKey = Key('completion-doc-panel-box');

  const AutocompletePopup({
    super.key,
    required this.items,
    required this.anchor,
    required this.bounds,
    required this.selectedIndex,
    required this.maxWidth,
    required this.onSelect,
    required this.onDismiss,
    this.currentWord = '',
    this.documentation,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    // Fills the editor area so every child can be positioned in its
    // coordinates; the Stack clips anything that would leave the editor.
    return Positioned.fill(
      child: ListenableBuilder(
        // The badges take their colours from the shared syntax palette, so the
        // list must also repaint when the scheme changes.
        listenable: Listenable.merge([
          ThemeService.instance,
          EditorSettingsService.instance,
        ]),
        builder: (context, _) {
          final uiColors = ThemeService.instance.uiColors;
          final scheme = EditorSettingsService.instance.syntaxScheme;
          final placement = _CompletionPlacement.compute(
            anchor: anchor,
            bounds: bounds,
            itemCount: items.length,
            maxWidth: maxWidth,
            hasDocumentation:
                documentation != null && documentation!.trim().isNotEmpty,
          );

          final list = MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              key: listKey,
              width: placement.listWidth,
              constraints: BoxConstraints(maxHeight: placement.listHeight),
              decoration: RetroBorder.raised(
                backgroundColor: uiColors['editorBackground'],
              ),
              child: Material(
                color: Colors.transparent,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = index == selectedIndex;
                    return GestureDetector(
                      onTap: () => onSelect(index),
                      behavior: HitTestBehavior.opaque,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? uiColors['menuActive']
                                : Colors.transparent,
                            borderRadius: BorderRadius.zero,
                          ),
                          // One fixed-height line: kind badge, label, then the
                          // server's detail pinned to the right and dimmed.
                          child: Row(
                            children: [
                              CompletionBadgeChip(
                                kind: item.kindInt,
                                scheme: scheme,
                                backgroundColor: uiColors['editorBackground']!,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: _LabelWithPrefix(
                                        label: item.displayLabel,
                                        prefix: currentWord,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontFamily: 'Menlo',
                                          color: isSelected
                                              ? uiColors['menuActiveText']
                                              : uiColors['editorText'],
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (item.detail != null) ...[
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          item.detail!,
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'Menlo',
                                            color: isSelected
                                                ? uiColors['menuActiveText']
                                                : uiColors['editorText']!
                                                      .withValues(alpha: 0.7),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );

          final docRect = placement.docRect;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              Positioned(
                left: placement.listRect.left,
                top: placement.listRect.top,
                child: list,
              ),
              if (docRect != null && documentation != null)
                Positioned(
                  left: docRect.left,
                  top: docRect.top,
                  width: docRect.width,
                  child: CompletionDocPanel(
                    key: docPanelKey,
                    text: documentation!,
                    maxWidth: docRect.width,
                    maxHeight: docRect.height,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Placement of the completion list and its documentation panel inside the
/// editor area.
///
/// Pure geometry: anchored at the caret, flipped above when there is no room
/// below, narrowed/clamped to the editor, and the doc panel goes right, then
/// left, then below/above — always inside [bounds].
class _CompletionPlacement {
  final Rect listRect;
  final double listWidth;
  final double listHeight;
  final Rect? docRect;

  const _CompletionPlacement({
    required this.listRect,
    required this.listWidth,
    required this.listHeight,
    this.docRect,
  });

  /// Every row is one line now (the detail sits inline, right-aligned), so the
  /// height estimate no longer depends on whether an item carries a detail.
  static const double _rowPlain = 24;
  static const double _maxListHeight = 200;
  static const double _minListHeight = 72;
  static const double _minDocWidth = 200;
  static const double _maxDocWidth = 320;
  static const double _gap = 4;

  static _CompletionPlacement compute({
    required Rect anchor,
    required Size bounds,
    required int itemCount,
    required double maxWidth,
    required bool hasDocumentation,
  }) {
    final width = maxWidth.clamp(120.0, bounds.width).toDouble();
    final left = anchor.left
        .clamp(0.0, (bounds.width - width).clamp(0.0, double.infinity))
        .toDouble();

    final contentHeight = itemCount * _rowPlain + _gap;
    final preferred = contentHeight.clamp(_minListHeight, _maxListHeight);

    final belowRoom = bounds.height - (anchor.bottom + _gap);
    final aboveRoom = anchor.top - _gap;

    double height;
    double top;
    if (belowRoom >= preferred) {
      height = preferred;
      top = anchor.bottom + _gap;
    } else if (aboveRoom >= preferred) {
      height = preferred;
      top = anchor.top - _gap - preferred;
    } else if (belowRoom >= aboveRoom) {
      // Neither side fits the whole list: use the larger side and let the list
      // scroll instead of drawing over the caret.
      height = belowRoom.clamp(1.0, _maxListHeight).toDouble();
      top = anchor.bottom + _gap;
    } else {
      height = aboveRoom.clamp(1.0, _maxListHeight).toDouble();
      top = anchor.top - _gap - height;
    }

    height = height.clamp(1.0, bounds.height).toDouble();
    top = top.clamp(0.0, (bounds.height - height).clamp(0.0, double.infinity));

    final listRect = Rect.fromLTWH(left, top, width, height);
    if (!hasDocumentation) {
      return _CompletionPlacement(
        listRect: listRect,
        listWidth: width,
        listHeight: height,
      );
    }

    final rightRoom = bounds.width - (left + width) - _gap;
    final leftRoom = left - _gap;
    final rightDocWidth = rightRoom.clamp(0.0, _maxDocWidth).toDouble();
    final leftDocWidth = leftRoom.clamp(0.0, _maxDocWidth).toDouble();

    if (rightDocWidth >= _minDocWidth) {
      final docHeight = (bounds.height - top).clamp(0.0, 200.0).toDouble();
      return _CompletionPlacement(
        listRect: listRect,
        listWidth: width,
        listHeight: height,
        docRect: Rect.fromLTWH(
          left + width + _gap,
          top,
          rightDocWidth,
          docHeight,
        ),
      );
    }

    if (leftDocWidth >= _minDocWidth) {
      final docHeight = (bounds.height - top).clamp(0.0, 200.0).toDouble();
      return _CompletionPlacement(
        listRect: listRect,
        listWidth: width,
        listHeight: height,
        docRect: Rect.fromLTWH(
          left - _gap - leftDocWidth,
          top,
          leftDocWidth,
          docHeight,
        ),
      );
    }

    // No horizontal room: stack the panel under (or above) the list, still
    // inside the editor.
    final docWidth = (bounds.width - 2 * _gap).clamp(0.0, _maxDocWidth)
        .toDouble();
    final docLeft = (bounds.width - docWidth) / 2;
    final belowDoc = bounds.height - (top + height) - _gap;
    final aboveDoc = top - _gap;
    double docTop;
    double docHeight;
    if (belowDoc >= 40) {
      docTop = top + height + _gap;
      docHeight = belowDoc.clamp(0.0, 200.0).toDouble();
    } else if (aboveDoc >= 40) {
      docHeight = aboveDoc.clamp(0.0, 200.0).toDouble();
      docTop = top - _gap - docHeight;
    } else {
      return _CompletionPlacement(
        listRect: listRect,
        listWidth: width,
        listHeight: height,
      );
    }

    return _CompletionPlacement(
      listRect: listRect,
      listWidth: width,
      listHeight: height,
      docRect: Rect.fromLTWH(docLeft, docTop, docWidth, docHeight),
    );
  }
}

/// Renders [label] with the leading [prefix] in bold, mirroring the retro
/// IDEs where the portion the user has typed is visually distinguished.
///
/// If [prefix] is empty or not a prefix of [label], the whole label is
/// rendered as a single run of normal weight.
class _LabelWithPrefix extends StatelessWidget {
  final String label;
  final String prefix;
  final TextStyle style;

  const _LabelWithPrefix({
    required this.label,
    required this.prefix,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final p = prefix.toLowerCase();
    if (p.isEmpty || !label.toLowerCase().startsWith(p)) {
      // The detail now shares the row, so a long label is truncated instead of
      // wrapping onto a second line.
      return Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    final head = label.substring(0, prefix.length);
    final tail = label.substring(prefix.length);

    return RichText(
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: head, style: style),
          TextSpan(
            text: tail,
            style: style.copyWith(fontWeight: FontWeight.normal),
          ),
        ],
      ),
    );
  }
}

/// The small square at the start of every completion row: one letter for the
/// item's LSP kind, painted with the active syntax scheme's own token colour.
///
/// Sized 16x16 with a 2 px retro border so it reads like a key cap without
/// making the row taller (the row's text is ~19 px).
class CompletionBadgeChip extends StatelessWidget {
  /// Raw LSP `CompletionItemKind` of the row, or `null` when unknown.
  final int? kind;

  /// The active syntax scheme; the letter colour comes from its palette.
  final SyntaxScheme scheme;

  /// Fill behind the letter: the editor surface, so the badge stays legible on
  /// a selected (dark) row in every theme.
  final Color backgroundColor;

  const CompletionBadgeChip({
    super.key,
    required this.kind,
    required this.scheme,
    required this.backgroundColor,
  });

  static const double size = 16;

  /// The mapped letter, exposed so tests need not re-derive it.
  String get letter => completionKindBadge(kind).letter;

  /// The palette colour of the letter and its border.
  Color get color =>
      completionBadgeColor(completionKindBadge(kind).category, scheme);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: RetroBorder.flat(
        backgroundColor: backgroundColor,
        borderColor: color,
      ),
      child: Text(
        letter,
        maxLines: 1,
        style: TextStyle(
          fontSize: 10,
          height: 1.0,
          fontWeight: FontWeight.bold,
          fontFamily: 'Menlo',
          color: color,
        ),
      ),
    );
  }
}
