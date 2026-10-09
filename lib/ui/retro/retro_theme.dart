import 'package:flutter/material.dart';

import 'retro_colors.dart';

class RetroTheme {
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: false,
      scaffoldBackgroundColor: RetroColors.background,
      primaryColor: RetroColors.selection,
      // Classic Windows 9x / Delphi UI typography: Tahoma / MS Sans Serif.
      fontFamily: 'Tahoma',
      textTheme: const TextTheme(
        labelLarge: TextStyle(
          fontSize: 12.0,
          fontWeight: FontWeight.w500,
          fontFamily: 'Tahoma',
          color: Color(0xFF000000),
        ),
        labelMedium: TextStyle(
          fontSize: 11.0,
          fontWeight: FontWeight.w400,
          fontFamily: 'Tahoma',
          color: Color(0xFF000000),
        ),
        bodyMedium: TextStyle(
          fontSize: 11.0,
          fontFamily: 'Tahoma',
          color: Color(0xFF000000),
        ),
      ),
      colorScheme: ColorScheme.light(
        primary: RetroColors.selection,
        surface: RetroColors.panel,
        error: RetroColors.error,
        onSurface: RetroColors.text,
      ),
    );
  }
}
