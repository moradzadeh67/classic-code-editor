import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import '../retro/retro_border.dart';

/// How long the completion selection must stay on the same item — idle, with
/// no key press — before the documentation panel appears.
///
/// Resolving stays fast (150 ms) so the documents and the automatic import are
/// cached before the user accepts; only the *display* waits this long.
const Duration kCompletionDocPanelDelay = Duration(seconds: 2);

/// The documentation box shown next to the autocomplete list.
///
/// Purely presentational: no focus node, no keyboard handling, no scrolling
/// policy of its own beyond the plain [SingleChildScrollView] — the editor's
/// `TextField` keeps the focus and all keys keep working exactly as before.
class CompletionDocPanel extends StatelessWidget {
  /// Documentation already converted to plain text (see
  /// `formatCompletionDocumentation`).
  final String text;

  /// Maximum width in logical pixels. The panel is drawn with a retro sunken
  /// border, matching the other popups.
  final double maxWidth;

  /// Maximum height in logical pixels, chosen by the popup so the panel never
  /// leaves the editor area.
  final double maxHeight;

  const CompletionDocPanel({
    super.key,
    required this.text,
    this.maxWidth = 320,
    this.maxHeight = 200,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final uiColors = ThemeService.instance.uiColors;

        return Container(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          padding: const EdgeInsets.all(8),
          decoration: RetroBorder.sunken(
            backgroundColor: uiColors['editorBackground'],
          ),
          child: SingleChildScrollView(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Menlo',
                height: 1.3,
                color: uiColors['editorText'],
              ),
            ),
          ),
        );
      },
    );
  }
}
