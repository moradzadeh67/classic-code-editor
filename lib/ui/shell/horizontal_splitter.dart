import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

class HorizontalSplitter extends StatefulWidget {
  final ValueChanged<double> onDragUpdate;

  const HorizontalSplitter({super.key, required this.onDragUpdate});

  @override
  State<HorizontalSplitter> createState() => _HorizontalSplitterState();
}

class _HorizontalSplitterState extends State<HorizontalSplitter> {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          widget.onDragUpdate(details.delta.dy);
        },
        child: Container(
          height: 6,
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
