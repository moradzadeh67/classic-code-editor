import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

class SyntaxColors {
  final Color keywords;
  final Color types;
  final Color strings;
  final Color comments;
  final Color numbers;
  final Color functions;
  final Color preprocessor;
  final Color operators;

  const SyntaxColors({
    required this.keywords,
    required this.types,
    required this.strings,
    required this.comments,
    required this.numbers,
    required this.functions,
    required this.preprocessor,
    required this.operators,
  });

  Map<String, Color> toMap() => {
    'keywords': keywords,
    'types': types,
    'strings': strings,
    'comments': comments,
    'numbers': numbers,
    'functions': functions,
    'preprocessor': preprocessor,
    'operators': operators,
  };

  factory SyntaxColors.forTheme(ThemeType type) {
    switch (type) {
      case ThemeType.vc6:
        return const SyntaxColors(
          keywords: Color(0xFF0000FF),
          types: Color(0xFF2B91AF),
          strings: Color(0xFFA31515),
          comments: Color(0xFF008000),
          numbers: Color(0xFF098658),
          functions: Color(0xFF000000),
          preprocessor: Color(0xFF800080),
          operators: Color(0xFF000000),
        );
      case ThemeType.delphi:
        return const SyntaxColors(
          keywords: Color(0xFF0000FF),
          types: Color(0xFF0000FF),
          strings: Color(0xFF0000FF),
          comments: Color(0xFF008000),
          numbers: Color(0xFF0000FF),
          functions: Color(0xFF000000),
          preprocessor: Color(0xFF800080),
          operators: Color(0xFF000000),
        );
      case ThemeType.vb6:
        return const SyntaxColors(
          keywords: Color(0xFF0000FF),
          types: Color(0xFF0000FF),
          strings: Color(0xFFFF0000),
          comments: Color(0xFF008000),
          numbers: Color(0xFF0000FF),
          functions: Color(0xFF000000),
          preprocessor: Color(0xFF800080),
          operators: Color(0xFF000000),
        );
    }
  }
}
