import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../ui/retro/syntax_colors.dart';

enum ThemeType { vc6, delphi, vb6 }

class ThemeColorsData {
  final Color background;
  final Color panel;
  final Color borderDark;
  final Color borderLight;
  final Color highlight;
  final Color shadow;
  final Color selection;
  final Color text;
  final Color error;
  final Color menuActive;
  final Color menuActiveText;

  final Color editorBackground;
  final Color editorText;
  final Color editorSelection;
  final Color editorSelectionText;
  final Color editorLineNumberBg;
  final Color editorLineNumberText;
  final Color editorCursor;

  /// Background tint painted on the line execution is currently paused on.
  final Color pausedLine;

  const ThemeColorsData({
    required this.background,
    required this.panel,
    required this.borderDark,
    required this.borderLight,
    required this.highlight,
    required this.shadow,
    required this.selection,
    required this.text,
    required this.error,
    required this.menuActive,
    required this.menuActiveText,
    required this.editorBackground,
    required this.editorText,
    required this.editorSelection,
    required this.editorSelectionText,
    required this.editorLineNumberBg,
    required this.editorLineNumberText,
    required this.editorCursor,
    required this.pausedLine,
  });

  Map<String, Color> toMap() => {
    'background': background,
    'panel': panel,
    'borderDark': borderDark,
    'borderLight': borderLight,
    'highlight': highlight,
    'shadow': shadow,
    'selection': selection,
    'text': text,
    'error': error,
    'menuActive': menuActive,
    'menuActiveText': menuActiveText,
    'editorBackground': editorBackground,
    'editorText': editorText,
    'editorSelection': editorSelection,
    'editorSelectionText': editorSelectionText,
    'editorLineNumberBg': editorLineNumberBg,
    'editorLineNumberText': editorLineNumberText,
    'editorCursor': editorCursor,
    'pausedLine': pausedLine,
  };
}

class ThemeService extends ChangeNotifier {
  static final ThemeService instance = ThemeService._internal();

  ThemeService._internal() {
    _loadTheme();
  }

  factory ThemeService() => instance;

  ThemeType _currentTheme = ThemeType.vc6;

  ThemeType get currentTheme => _currentTheme;

  String get currentThemeName {
    switch (_currentTheme) {
      case ThemeType.delphi:
        return 'Delphi';
      case ThemeType.vb6:
        return 'VB6';
      case ThemeType.vc6:
        return 'VC++ 6.0';
    }
  }

  ThemeColorsData get colors => _colorsForTheme(_currentTheme);

  Map<String, Color> get uiColors => colors.toMap();

  SyntaxColors get syntaxColors => SyntaxColors.forTheme(_currentTheme);

  Map<String, Color> get syntaxColorsMap => syntaxColors.toMap();

  void switchTheme(ThemeType type) {
    if (_currentTheme != type) {
      _currentTheme = type;
      _saveTheme();
      notifyListeners();
    }
  }

  void setTheme(String themeName) {
    if (themeName == 'Delphi') {
      switchTheme(ThemeType.delphi);
    } else if (themeName == 'VB6') {
      switchTheme(ThemeType.vb6);
    } else {
      switchTheme(ThemeType.vc6);
    }
  }

  static ThemeColorsData _colorsForTheme(ThemeType type) {
    switch (type) {
      case ThemeType.vc6:
        // ۱. تم VC++ 6.0 با استایل Windows XP (Luna Blue)
        return const ThemeColorsData(
          background: Color(0xFF0055EA), // آبی کلاسیک ویندوز اکس‌پی
          panel: Color(0xFFECE9D8), // رنگ بدنه و پنجره‌های Windows XP
          borderDark: Color(0xFF716F64),
          borderLight: Color(0xFFFFFFFF),
          highlight: Color(0xFFF4F2E8),
          shadow: Color(0xFFACA899),
          selection: Color(0xFF316AC5), // آبی انتخاب اکتیو در ویندوز اکس‌پی
          text: Color(0xFF000000),
          error: Color(0xFFCC0000),
          menuActive: Color(0xFF316AC5),
          menuActiveText: Color(0xFFFFFFFF),
          editorBackground: Color(0xFFE8F1FF),
          editorText: Color(0xFF000000),
          editorSelection: Color(0xFF000080),
          editorSelectionText: Color(0xFFFFFFFF),
          editorLineNumberBg: Color(0xFFECE9D8),
          editorLineNumberText: Color(0xFF000000),
          editorCursor: Color(0xFF000000),
          pausedLine: Color(0xFFFFF0A0),
        );

      case ThemeType.delphi:
        // تم Delphi / MPLAB IDE (تن زرد-بژ/خردلی گرم کلاسیک)
        return const ThemeColorsData(
          background: Color(0xFFD2BA7E), // بژ/خردلی گرم زمینه اصلی
          panel: Color(0xFFDFCD9B), // بژ ملایم بدنه پنجره‌ها و پنل‌ها
          borderDark: Color(0xFF7A683E), // سایه‌های تیره خردلی/قهوه‌ای
          borderLight: Color(0xFFFAF0C5), // هایلایت‌های روشن بالای پنجره‌ها
          highlight: Color(0xFFEAD8AA), // پنل‌های هایلایت‌شده
          shadow: Color(0xFFA08B53), // سایه‌های متوسط
          selection: Color(0xFFA08035), // رنگ انتخاب فعال (خردلی تیره/قهوه‌ای)
          text: Color(0xFF000000),
          error: Color(0xFFCC0000),
          menuActive: Color(0xFFA08035),
          menuActiveText: Color(0xFFFFFFFF),
          editorBackground: Color(0xFFE8F1FF),
          editorText: Color(0xFF000000),
          editorSelection: Color(0xFF000080),
          editorSelectionText: Color(0xFFFFFFFF),
          editorLineNumberBg: Color(0xFFDFCD9B),
          editorLineNumberText: Color(0xFF000000),
          editorCursor: Color(0xFF000000),
          pausedLine: Color(0xFFE9D9A5),
        );

      case ThemeType.vb6:
        // ۳. تم Borland Kylix / Retro Linux Desktop (پس‌زمینه آبی‌سرمه‌ای عمیق)
        return const ThemeColorsData(
          background: Color(0xFF2C4A8E),
          panel: Color(0xFFC0C0C0),
          borderDark: Color(0xFF303030),
          borderLight: Color(0xFFE0E0E0),
          highlight: Color(0xFFD8D8D8),
          shadow: Color(0xFF707070),
          selection: Color(0xFF1B3260),
          text: Color(0xFF000000),
          error: Color(0xFFCC0000),
          menuActive: Color(0xFF1B3260),
          menuActiveText: Color(0xFFFFFFFF),
          editorBackground: Color(0xFFE8F1FF),
          editorText: Color(0xFF000000),
          editorSelection: Color(0xFF000080),
          editorSelectionText: Color(0xFFFFFFFF),
          editorLineNumberBg: Color(0xFFC0C0C0),
          editorLineNumberText: Color(0xFF000000),
          editorCursor: Color(0xFF000000),
          pausedLine: Color(0xFFDCDCA8),
        );
    }
  }

  File get _configFile => File('.retro_theme_config.json');

  void _loadTheme() {
    try {
      if (_configFile.existsSync()) {
        final content = _configFile.readAsStringSync();
        final data = jsonDecode(content);
        final themeName = data['theme'];
        if (themeName == 'delphi') {
          _currentTheme = ThemeType.delphi;
        } else if (themeName == 'vb6') {
          _currentTheme = ThemeType.vb6;
        } else {
          _currentTheme = ThemeType.vc6;
        }
      }
    } catch (_) {
      _currentTheme = ThemeType.vc6;
    }
  }

  void _saveTheme() {
    try {
      String themeName = 'vc6';
      if (_currentTheme == ThemeType.delphi) {
        themeName = 'delphi';
      } else if (_currentTheme == ThemeType.vb6) {
        themeName = 'vb6';
      }
      final content = jsonEncode({'theme': themeName});
      _configFile.writeAsStringSync(content);
    } catch (_) {}
  }
}
