import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import 'retro_border.dart';
import 'retro_button.dart';

/// Shows a retro 90s-styled "About Classic Code Editor" dialog.
void showRetroAboutDialog(BuildContext context, {int initialTab = 0}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => _RetroAboutDialogWidget(initialTab: initialTab),
  );
}

class _RetroAboutDialogWidget extends StatefulWidget {
  final int initialTab;

  const _RetroAboutDialogWidget({this.initialTab = 0});

  @override
  State<_RetroAboutDialogWidget> createState() =>
      _RetroAboutDialogWidgetState();
}

class _RetroAboutDialogWidgetState extends State<_RetroAboutDialogWidget> {
  late int _activeTab;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeService.instance.colors;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 560,
        decoration: RetroBorder.raised(backgroundColor: colors.panel),
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Retro Title Bar
            Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: colors.selection,
              child: Row(
                children: [
                  const Icon(Icons.code, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'About Classic Code Editor',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Arial',
                        color: colors.menuActiveText,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: RetroBorder.raised(
                        backgroundColor: colors.panel,
                      ),
                      child: Center(
                        child: Text(
                          '×',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                            color: colors.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 2. Tab Bar (About / Shortcuts / System)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabButton('About & Developer', 0, colors),
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: _buildTabButton('Shortcuts', 1, colors)),
                  const SizedBox(width: 4),
                  Expanded(child: _buildTabButton('System Info', 2, colors)),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // 3. Main Content Panel
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                height: 280,
                decoration: RetroBorder.sunken(
                  backgroundColor: colors.editorBackground,
                ),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: switch (_activeTab) {
                    1 => _buildShortcutsTab(colors),
                    2 => _buildSystemTab(colors),
                    _ => _buildAboutTab(colors),
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),

            // 4. Footer OK Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  RetroButton(
                    onPressed: () => Navigator.of(context).pop(),
                    height: 26,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 4,
                    ),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, int index, ThemeColorsData colors) {
    final isActive = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: isActive
            ? RetroBorder.sunken(backgroundColor: colors.panel)
            : RetroBorder.raised(backgroundColor: colors.panel),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'Arial',
            color: colors.text,
          ),
        ),
      ),
    );
  }

  Widget _buildAboutTab(ThemeColorsData colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // App Banner / Logo
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: RetroBorder.raised(backgroundColor: colors.panel),
              child: Center(
                child: Icon(Icons.terminal, size: 32, color: colors.selection),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Classic Code Editor',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Arial',
                      color: colors.editorText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Version 1.0.0 (macOS Edition)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Arial',
                      color: colors.editorText.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A 90s retro-styled multi-language IDE inspired by Borland C++, Visual C++ 6.0, and Delphi.',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Arial',
                      height: 1.3,
                      color: colors.editorText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 20),

        // Developer Information Box
        Container(
          padding: const EdgeInsets.all(8),
          decoration: RetroBorder.flat(
            backgroundColor: colors.panel.withValues(alpha: 0.3),
            borderColor: colors.borderDark,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '👨‍💻 Developer Information',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Arial',
                  color: colors.editorText,
                ),
              ),
              const SizedBox(height: 6),
              _buildInfoRow(
                'Lead Developer:',
                'Reza Moradzadeh (moradzadeh67)',
                colors,
              ),
              _buildInfoRow('Role:', 'Lead Flutter & Systems Engineer', colors),
              _buildInfoRow(
                'GitHub Repository:',
                'github.com/moradzadeh67/borland_dart',
                colors,
              ),
              _buildInfoRow(
                'License:',
                'MIT License (Copyright © 2026)',
                colors,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Description
        Text(
          'Classic Code Editor was built to recreate the dense, functional, and productive workflow of 90s IDEs with modern LSP support, interactive terminal, real-time debugging, and syntax highlighting across Dart, Python, C, and C++.',
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Arial',
            height: 1.35,
            color: colors.editorText.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutsTab(ThemeColorsData colors) {
    final shortcuts = [
      ('F5', 'Run Active Code File'),
      ('Cmd + S', 'Save Current File'),
      ('Cmd + N', 'New File'),
      ('↑ / ↓', 'Navigate Autocomplete Suggestions'),
      ('Enter / Tab', 'Accept Selected Completion'),
      ('Escape', 'Dismiss Autocomplete / Tooltip'),
      ('Cmd + Z', 'Undo'),
      ('Cmd + Y', 'Redo'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '⌨️ Keyboard Shortcuts',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'Arial',
            color: colors.editorText,
          ),
        ),
        const SizedBox(height: 8),
        ...shortcuts.map(
          (s) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 120,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: RetroBorder.raised(backgroundColor: colors.panel),
                  child: Text(
                    s.$1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Menlo',
                      color: colors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.$2,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Arial',
                      color: colors.editorText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSystemTab(ThemeColorsData colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🛠️ Tech Stack & System Specs',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'Arial',
            color: colors.editorText,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow(
          'Framework:',
          'Flutter 3.x Desktop (macOS Native)',
          colors,
        ),
        _buildInfoRow('Language:', 'Dart 3.13.2+', colors),
        _buildInfoRow(
          'Supported Languages:',
          'Dart (.dart), Python (.py), C (.c), C++ (.cpp)',
          colors,
        ),
        _buildInfoRow(
          'Language Server:',
          'LSP via stdio JSON-RPC (Dart Language Server)',
          colors,
        ),
        _buildInfoRow(
          'Compilers / Run-Times:',
          'dart, python3, clang, clang++',
          colors,
        ),
        _buildInfoRow(
          'Editor Engine:',
          'flutter_code_editor + highlight',
          colors,
        ),
        _buildInfoRow(
          'Themes Available:',
          'VC++ 6.0, Borland Delphi, Visual Basic 6.0',
          colors,
        ),
      ],
    );
  }

  Widget _buildInfoRow(String title, String value, ThemeColorsData colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'Arial',
                color: colors.editorText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Arial',
                color: colors.editorText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
