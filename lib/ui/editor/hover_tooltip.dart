import 'package:flutter/material.dart';

import '../../models/lsp_models.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';

/// A retro-styled tooltip that appears near the mouse cursor when the
/// user hovers over an identifier for 500ms.
///
/// Uses sharp corners and theme colors consistent with the rest of the IDE.
class HoverTooltip extends StatelessWidget {
  final HoverInfo hoverInfo;
  final Offset position;
  final double maxWidth;

  const HoverTooltip({
    super.key,
    required this.hoverInfo,
    required this.position,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: ListenableBuilder(
        listenable: ThemeService.instance,
        builder: (context, _) {
          final uiColors = ThemeService.instance.uiColors;

          return Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.all(8),
            decoration: RetroBorder.raised(
              backgroundColor: uiColors['editorBackground'],
            ),
            child: Text(
              hoverInfo.content,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Menlo',
                color: uiColors['editorText'],
              ),
            ),
          );
        },
      ),
    );
  }
}
