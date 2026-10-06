import 'package:flutter/material.dart';

import 'retro_colors.dart';

class RetroBorder {
  static BoxDecoration raised({Color? backgroundColor}) {
    return BoxDecoration(
      color: backgroundColor ?? RetroColors.panel,
      borderRadius: BorderRadius.zero,
      border: Border(
        top: BorderSide(color: RetroColors.borderLight, width: 2),
        left: BorderSide(color: RetroColors.borderLight, width: 2),
        right: BorderSide(color: RetroColors.borderDark, width: 2),
        bottom: BorderSide(color: RetroColors.borderDark, width: 2),
      ),
    );
  }

  static BoxDecoration sunken({Color? backgroundColor}) {
    return BoxDecoration(
      color: backgroundColor ?? RetroColors.panel,
      borderRadius: BorderRadius.zero,
      border: Border(
        top: BorderSide(color: RetroColors.borderDark, width: 2),
        left: BorderSide(color: RetroColors.borderDark, width: 2),
        right: BorderSide(color: RetroColors.borderLight, width: 2),
        bottom: BorderSide(color: RetroColors.borderLight, width: 2),
      ),
    );
  }

  static BoxDecoration flat({Color? backgroundColor, Color? borderColor}) {
    return BoxDecoration(
      color: backgroundColor ?? RetroColors.panel,
      borderRadius: BorderRadius.zero,
      border: Border.all(
        color: borderColor ?? RetroColors.borderDark,
        width: 2,
      ),
    );
  }
}
