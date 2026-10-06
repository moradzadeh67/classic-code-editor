import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

class VerticalSplitter extends StatefulWidget {
  final ValueChanged<double> onDragUpdate;

  const VerticalSplitter({super.key, required this.onDragUpdate});

  @override
  State<VerticalSplitter> createState() => _VerticalSplitterState();
}

class _VerticalSplitterState extends State<VerticalSplitter> {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          widget.onDragUpdate(details.delta.dx);
        },
        child: Container(
          width: 6,
          decoration: BoxDecoration(
            color: ThemeService.instance.uiColors['shadow'],
            border: Border.all(
              color: ThemeService.instance.uiColors['borderDark']!,
              width: 1,
            ),
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
    );
  }
}
