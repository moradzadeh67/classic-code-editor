import 'package:flutter/material.dart';

import 'retro_colors.dart';
import 'retro_border.dart';

/// A retro (3D raised / sunken) push button.
///
/// Height defaults to the authentic VCL tool-button height (22px) or can be customized.
/// Sharp corners only ([RetroBorder] uses [BorderRadius.zero]).
class RetroButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool isPressed;
  final EdgeInsetsGeometry padding;
  final double? height;

  const RetroButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isPressed = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
    this.height,
  });

  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    final bool pressed = widget.isPressed || _isDown;
    final enabled = widget.onPressed != null;
    final buttonHeight = widget.height ?? 22.0;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _isDown = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _isDown = false);
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _isDown = false) : null,
      child: Container(
        constraints: BoxConstraints.tightFor(height: buttonHeight),
        padding: widget.padding,
        decoration: pressed ? RetroBorder.sunken() : RetroBorder.raised(),
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: 12.0,
            fontWeight: FontWeight.w500,
            fontFamily: 'Arial',
            height: 1.2,
            color: enabled ? RetroColors.text : RetroColors.shadow,
          ),
          child: Center(widthFactor: 1.0, child: widget.child),
        ),
      ),
    );
  }
}
