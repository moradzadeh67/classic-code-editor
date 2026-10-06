import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/lsp_models.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';

/// A retro-styled autocomplete dropdown that appears below the editor
/// cursor when the language server provides completion suggestions.
///
/// Supports keyboard navigation (Up/Down to move, Enter to accept, Escape
/// to dismiss) and mouse selection. Uses sharp corners and theme colors
/// consistent with the rest of the IDE.
class AutocompletePopup extends StatelessWidget {
  final List<CompletionItem> items;
  final Offset position;
  final int selectedIndex;
  final double maxWidth;
  final ValueChanged<int> onSelect;
  final VoidCallback onDismiss;

  const AutocompletePopup({
    super.key,
    required this.items,
    required this.position,
    required this.selectedIndex,
    required this.maxWidth,
    required this.onSelect,
    required this.onDismiss,
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

          return KeyboardListener(
            autofocus: true,
            focusNode: FocusNode()..requestFocus(),
            onKeyEvent: (event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  final newIndex = (selectedIndex - 1).clamp(
                    0,
                    items.length - 1,
                  );
                  if (newIndex != selectedIndex) {
                    onSelect(newIndex);
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  final newIndex = (selectedIndex + 1).clamp(
                    0,
                    items.length - 1,
                  );
                  if (newIndex != selectedIndex) {
                    onSelect(newIndex);
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                  onSelect(selectedIndex);
                } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                  onDismiss();
                }
              }
            },
            child: MouseRegion(
              child: Container(
                constraints: BoxConstraints(maxHeight: 200, maxWidth: maxWidth),
                decoration: RetroBorder.raised(
                  backgroundColor: uiColors['editorBackground'],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = index == selectedIndex;
                      return GestureDetector(
                        onTap: () => onSelect(index),
                        behavior: HitTestBehavior.translucent,
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
                              Text(
                                item.label,
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
                                          : uiColors['editorText']?.withValues(
                                              alpha: 0.7,
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
              ),
            ),
          );
        },
      ),
    );
  }
}
