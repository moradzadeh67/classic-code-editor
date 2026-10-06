import 'package:flutter/material.dart';

import 'retro_colors.dart';
import 'retro_border.dart';

/// A retro (3D raised / sunken) push button.
///
/// Height is fixed at the authentic VCL tool-button height (22px) so it sits
/// with a 1px gap above and below inside the 24px toolbar content region, and
/// the label uses the standard Windows 9x size (Arial 12 / MS Sans Serif 8pt).
/// Sharp corners only ([RetroBorder] uses [BorderRadius.zero]).
class RetroButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool isPressed;
  final EdgeInsetsGeometry padding;

  const RetroButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isPressed = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
  });

  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  /// Delphi/VCL default tool-button height = 22px. Sits with a 1px gap above
  /// and below inside the 24px toolbar content region.
  static const double _height = 22;

  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    final bool pressed = widget.isPressed || _isDown;
    final enabled = widget.onPressed != null;

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
        // Fixed 22px → 1px breathing room top/bottom inside the 24px row.
        constraints: const BoxConstraints.tightFor(height: _height),
        padding: widget.padding,
        decoration: pressed ? RetroBorder.sunken() : RetroBorder.raised(),
        // Normal-weight, standard-size UI label (see class doc).
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
