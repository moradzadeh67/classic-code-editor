import 'package:flutter/material.dart';

import 'retro_colors.dart';
import 'retro_border.dart';

class RetroPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? backgroundColor;

  const RetroPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(8.0),
    this.margin = EdgeInsets.zero,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: RetroBorder.raised(
        backgroundColor: backgroundColor ?? RetroColors.panel,
      ),
      child: child,
    );
  }
}
