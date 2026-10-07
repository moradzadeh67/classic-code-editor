import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../services/dart_runner_service.dart';
import '../../services/file_service.dart';
import '../../services/analyzer_service.dart';
import '../../services/theme_service.dart';
import '../retro/retro_colors.dart';
import '../retro/retro_border.dart';

class RetroMenuBar extends StatelessWidget {
  final VoidCallback? onToggleFileExplorer;
  final VoidCallback? onToggleConsole;
  final VoidCallback? onToggleDiagnostics;
  final VoidCallback? onRun;
  final VoidCallback? onStop;
  final FileService? fileService;
  final AnalyzerService? analyzerService;
  final DartRunnerService? dartRunnerService;
  final CodeController? codeEditorController;

  const RetroMenuBar({
    super.key,
    this.onToggleFileExplorer,
    this.onToggleConsole,
    this.onToggleDiagnostics,
    this.onRun,
    this.onStop,
    this.fileService,
    this.analyzerService,
    this.dartRunnerService,
    this.codeEditorController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: RetroBorder.raised(backgroundColor: RetroColors.panel),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _buildMenuHeader(
            context: context,
            label: 'File',
            items: [
              const PopupMenuItem(
                value: 'new',
                child: Text(
                  'New File',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'open',
                child: Text(
                  'Open File',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'save',
                child: Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'save_as',
                child: Text(
                  'Save As',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'exit',
                child: Text(
                  'Exit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'open') {
                fileService?.openFile();
              } else if (value == 'save') {
                if (fileService != null) {
                  fileService!.saveFile(fileService!.fileContent);
                }
              } else if (value == 'save_as') {
                if (fileService != null) {
                  fileService!.saveFileAs(fileService!.fileContent);
                }
              } else if (value == 'new') {
                fileService?.createNewFile();
              }
            },
          ),
          _buildMenuHeader(
            context: context,
            label: 'Edit',
            items: [
              const PopupMenuItem(
                value: 'undo',
                child: Text(
                  'Undo',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'redo',
                child: Text(
                  'Redo',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'cut',
                child: Text(
                  'Cut',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: Text(
                  'Copy',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'paste',
                child: Text(
                  'Paste',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'undo') {
                _undoText();
              } else if (value == 'redo') {
                _redoText();
              } else if (value == 'cut') {
                _cutSelectedText();
              } else if (value == 'copy') {
                _copySelectedText();
              } else if (value == 'paste') {
                _pasteText();
              }
            },
          ),
          _buildMenuHeader(
            context: context,
            label: 'View',
            items: [
              const PopupMenuItem(
                value: 'toggle_explorer',
                child: Text(
                  'Toggle File Explorer',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'toggle_console',
                child: Text(
                  'Toggle Console',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'toggle_diagnostics',
                child: Text(
                  'Toggle Diagnostics',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'theme_vc6',
                child: Text(
                  'Theme: VC++ 6.0',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'theme_delphi',
                child: Text(
                  'Theme: Borland Delphi',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'theme_vb6',
                child: Text(
                  'Theme: Visual Basic 6.0',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'toggle_explorer') {
                onToggleFileExplorer?.call();
              } else if (value == 'toggle_console') {
                onToggleConsole?.call();
              } else if (value == 'toggle_diagnostics') {
                onToggleDiagnostics?.call();
              } else if (value == 'theme_vc6') {
                ThemeService.instance.switchTheme(ThemeType.vc6);
              } else if (value == 'theme_delphi') {
                ThemeService.instance.switchTheme(ThemeType.delphi);
              } else if (value == 'theme_vb6') {
                ThemeService.instance.switchTheme(ThemeType.vb6);
              }
            },
          ),
          _buildMenuHeader(
            context: context,
            label: 'Run',
            items: [
              const PopupMenuItem(
                value: 'run',
                child: Text(
                  'Run',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'stop',
                child: Text(
                  'Stop',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'run') {
                if (onRun != null) {
                  onRun!();
                } else if (dartRunnerService != null && fileService != null) {
                  final path = fileService!.currentFilePath;
                  final content =
                      fileService!.activeTab?.content ??
                      fileService!.fileContent;
                  if (content.isNotEmpty) {
                    debugPrint('Run menu clicked, executing code...');
                    dartRunnerService!.runCode(path, content);
                  }
                }
              } else if (value == 'stop') {
                if (onStop != null) {
                  onStop!();
                } else {
                  dartRunnerService?.stopExecution();
                }
              }
            },
          ),
          _buildMenuHeader(
            context: context,
            label: 'Tools',
            items: [
              const PopupMenuItem(
                value: 'run_analysis',
                child: Text(
                  'Run Analysis',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'run_analysis') {
                final path = fileService?.currentFilePath;
                if (path != null) {
                  analyzerService?.analyzeFile(path);
                }
              }
            },
          ),
          _buildMenuHeader(
            context: context,
            label: 'Help',
            items: [
              const PopupMenuItem(
                value: 'about',
                child: Text(
                  'About',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Arial',
                    height: 1.2,
                  ),
                ),
              ),
            ],
            onSelected: (_) {},
          ),
        ],
      ),
    );
  }

  void _undoText() {
    // CodeController in this version of flutter_code_editor does not expose
    // undo/redo programmatically. The editor still supports Cmd/Ctrl+Z via
    // the native text input on platform views.
  }

  void _redoText() {
    // See comment in _undoText.
  }

  void _copySelectedText() async {
    final controller = codeEditorController;
    if (controller == null) return;
    final selectedText = controller.selection.textInside(controller.text);
    if (selectedText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: selectedText));
    }
  }

  void _cutSelectedText() async {
    final controller = codeEditorController;
    if (controller == null || !controller.selection.isValid) return;
    final selectedText = controller.selection.textInside(controller.text);
    if (selectedText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: selectedText));
      final buffer = controller.text;
      final start = controller.selection.start;
      final end = controller.selection.end;
      if (start >= 0 && end >= start && end <= buffer.length) {
        final newText = buffer.substring(0, start) + buffer.substring(end);
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: start),
        );
      }
    }
  }

  void _pasteText() async {
    final controller = codeEditorController;
    if (controller == null) return;
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      final buffer = controller.text;
      final start = controller.selection.start;
      final end = controller.selection.end;
      if (start < 0 || end < start) return;
      final newText =
          buffer.substring(0, start) +
          data!.text! +
          buffer.substring(end.clamp(0, buffer.length));
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: (start + data.text!.length).clamp(0, newText.length),
        ),
      );
    }
  }

  Widget _buildMenuHeader({
    required BuildContext context,
    required String label,
    required List<PopupMenuEntry<String>> items,
    required PopupMenuItemSelected<String> onSelected,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: RetroColors.panel,
          elevation: 0,
          shape: Border(
            top: BorderSide(color: RetroColors.borderLight, width: 2),
            left: BorderSide(color: RetroColors.borderLight, width: 2),
            right: BorderSide(color: RetroColors.borderDark, width: 2),
            bottom: BorderSide(color: RetroColors.borderDark, width: 2),
          ),
        ),
      ),
      child: PopupMenuButton<String>(
        onSelected: onSelected,
        itemBuilder: (context) => items,
        offset: const Offset(0, 22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFamily: 'Arial',
              height: 1.2,
              color: RetroColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
