import 'package:flutter/material.dart';

import 'services/theme_service.dart';
import 'ui/retro/retro_theme.dart';
import 'ui/shell/ide_shell.dart';

class RetroDartApp extends StatelessWidget {
  const RetroDartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'RetroDart IDE',
          debugShowCheckedModeBanner: false,
          theme: RetroTheme.theme,
          home: const IDEShell(),
        );
      },
    );
  }
}
