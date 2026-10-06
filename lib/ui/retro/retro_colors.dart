import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

class RetroColors {
  static Color get background => ThemeService.instance.colors.background;
  static Color get panel => ThemeService.instance.colors.panel;
  static Color get borderDark => ThemeService.instance.colors.borderDark;
  static Color get borderLight => ThemeService.instance.colors.borderLight;
  static Color get highlight => ThemeService.instance.colors.highlight;
  static Color get shadow => ThemeService.instance.colors.shadow;
  static Color get selection => ThemeService.instance.colors.selection;
  static Color get text => ThemeService.instance.colors.text;
  static Color get error => ThemeService.instance.colors.error;
  static Color get menuActive => ThemeService.instance.colors.menuActive;
  static Color get menuActiveText =>
      ThemeService.instance.colors.menuActiveText;

  static Color get editorBackground =>
      ThemeService.instance.colors.editorBackground;
  static Color get editorText => ThemeService.instance.colors.editorText;
  static Color get editorSelection =>
      ThemeService.instance.colors.editorSelection;
  static Color get editorSelectionText =>
      ThemeService.instance.colors.editorSelectionText;
  static Color get editorLineNumberBg =>
      ThemeService.instance.colors.editorLineNumberBg;
  static Color get editorLineNumberText =>
      ThemeService.instance.colors.editorLineNumberText;
  static Color get editorCursor => ThemeService.instance.colors.editorCursor;
}
