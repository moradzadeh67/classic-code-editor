import 'package:flutter/material.dart';

import '../../models/lsp_models.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';

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

  /// Top-left screen position where the dropdown should be drawn.
  final Offset position;

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

  const AutocompletePopup({
    super.key,
    required this.items,
    required this.position,
    required this.selectedIndex,
    required this.maxWidth,
    required this.onSelect,
    required this.onDismiss,
    this.currentWord = '',
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: ListenableBuilder(
        listenable: ThemeService.instance,
        builder: (context, _) {
          final uiColors = ThemeService.instance.uiColors;

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              constraints: BoxConstraints(maxHeight: 200, maxWidth: maxWidth),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _LabelWithPrefix(
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
                              if (item.detail != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    item.detail!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'Menlo',
                                      color: isSelected
                                          ? uiColors['menuActiveText']
                                          : uiColors['editorText']!.withValues(
                                              alpha: 0.7,
                                            ),
                                    ),
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
        },
      ),
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
      return Text(label, style: style);
    }

    final head = label.substring(0, prefix.length);
    final tail = label.substring(prefix.length);

    return RichText(
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
