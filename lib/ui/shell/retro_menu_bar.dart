import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../services/dart_runner_service.dart';
import '../../services/file_service.dart';
import '../../services/analyzer_service.dart';
import '../../services/theme_service.dart';
import '../../models/syntax_scheme.dart';
import '../../services/editor_settings_service.dart';
import '../../services/session_service.dart';
import '../../utils/line_edit.dart';
import '../../utils/toggle_comment.dart';
import '../retro/retro_colors.dart';
import '../retro/retro_border.dart';
import '../retro/retro_about_dialog.dart';
import 'retro_menu_item.dart';

class RetroMenuBar extends StatelessWidget {
  final VoidCallback? onToggleFileExplorer;
  final VoidCallback? onToggleConsole;
  final VoidCallback? onToggleDiagnostics;
  final VoidCallback? onRun;
  final VoidCallback? onStop;

  /// Closes the active tab through the unsaved-changes guard.
  final VoidCallback? onCloseTab;

  /// Opens the retro "Go to Line" prompt (Cmd+L).
  final VoidCallback? onGoToLine;

  /// Opens a file from the "Open Recent" section of the File menu.
  final ValueChanged<String>? onOpenRecent;

  /// File > "Open Folder..." (Cmd+Shift+O).
  final VoidCallback? onOpenFolder;

  /// File > "Close Folder".
  final VoidCallback? onCloseFolder;
  final VoidCallback? onTriggerCompletion;
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
    this.onCloseTab,
    this.onGoToLine,
    this.onOpenRecent,
    this.onOpenFolder,
    this.onCloseFolder,
    this.fileService,
    this.analyzerService,
    this.dartRunnerService,
    this.codeEditorController,
    this.onTriggerCompletion,
  });

  @override
  Widget build(BuildContext context) {
    // The File menu shows the MRU list, so rebuild when the session changes.
    return ListenableBuilder(
      listenable: SessionService.instance,
      builder: (context, _) => Container(
        height: 32,
        decoration: RetroBorder.raised(backgroundColor: RetroColors.panel),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _buildMenuHeader(
              context: context,
              label: 'File',
              items: _fileMenuItems,
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
                } else if (value == 'close_tab') {
                  onCloseTab?.call();
                } else if (value == 'open_folder') {
                  onOpenFolder?.call();
                } else if (value == 'close_folder') {
                  onCloseFolder?.call();
                } else if (value == 'clear_recent') {
                  SessionService.instance.clearRecentFiles();
                } else if (value.startsWith('recent_')) {
                  final index = int.tryParse(value.substring('recent_'.length));
                  final recents = SessionService.instance.recentFiles;
                  if (index != null && index < recents.length) {
                    onOpenRecent?.call(recents[index]);
                  }
                } else if (value == 'exit') {
                  // Asking the engine for a *cancelable* exit routes through
                  // AppLifecycleListener.onExitRequested, i.e. the same guard.
                  unawaited(
                    ServicesBinding.instance.exitApplication(
                      AppExitType.cancelable,
                    ),
                  );
                }
              },
            ),
            _buildMenuHeader(
              context: context,
              label: 'Edit',
              items: () => const <PopupMenuEntry<String>>[
                RetroMenuItem<String>(
                  value: 'undo',
                  label: 'Undo',
                  shortcut: 'Cmd + Z',
                ),
                RetroMenuItem<String>(
                  value: 'redo',
                  label: 'Redo',
                  shortcut: 'Cmd + Y',
                ),
                RetroMenuSeparator<String>(),
                RetroMenuItem<String>(value: 'cut', label: 'Cut'),
                RetroMenuItem<String>(value: 'copy', label: 'Copy'),
                RetroMenuItem<String>(value: 'paste', label: 'Paste'),
                RetroMenuSeparator<String>(),
                RetroMenuItem<String>(
                  value: 'select_all',
                  label: 'Select All',
                  shortcut: 'Cmd + A',
                ),
                RetroMenuItem<String>(
                  value: 'go_to_line',
                  label: 'Go to Line',
                  shortcut: 'Cmd + L',
                ),
                RetroMenuItem<String>(
                  value: 'trigger_completion',
                  label: 'Trigger Completion',
                  shortcut: 'Ctrl + Shift + Space',
                ),
                RetroMenuItem<String>(
                  value: 'toggle_comment',
                  label: 'Toggle Comment',
                  shortcut: 'Cmd + /',
                ),
                RetroMenuItem<String>(
                  value: 'duplicate_line',
                  label: 'Duplicate Line',
                  shortcut: 'Cmd + Shift + D',
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
                } else if (value == 'select_all') {
                  _selectAllText();
                } else if (value == 'go_to_line') {
                  onGoToLine?.call();
                } else if (value == 'trigger_completion') {
                  onTriggerCompletion?.call();
                } else if (value == 'toggle_comment') {
                  _toggleComment();
                } else if (value == 'duplicate_line') {
                  _duplicateLine();
                }
              },
            ),
            _buildMenuHeader(
              context: context,
              label: 'View',
              items: () => <PopupMenuEntry<String>>[
                const RetroMenuItem<String>(
                  value: 'toggle_explorer',
                  label: 'Toggle File Explorer',
                ),
                const RetroMenuItem<String>(
                  value: 'toggle_console',
                  label: 'Toggle Console',
                ),
                const RetroMenuItem<String>(
                  value: 'toggle_diagnostics',
                  label: 'Toggle Diagnostics',
                ),
                const RetroMenuSeparator<String>(),
                const RetroMenuItem<String>(
                  value: 'font_increase',
                  label: 'Increase Font Size',
                  shortcut: 'Cmd +',
                ),
                const RetroMenuItem<String>(
                  value: 'font_decrease',
                  label: 'Decrease Font Size',
                  shortcut: 'Cmd -',
                ),
                const RetroMenuItem<String>(
                  value: 'font_reset',
                  label: 'Reset Font Size',
                  shortcut: 'Cmd 0',
                ),
                const RetroMenuSeparator<String>(),
                // Rule 8: the check mark depends on the live font choice, so
                // these rows are intentionally not const.
                RetroMenuItem<String>(
                  value: 'font_menlo',
                  label: 'Font: Menlo',
                  checked:
                      EditorSettingsService.instance.fontFamily ==
                      EditorFontFamily.menlo,
                ),
                RetroMenuItem<String>(
                  value: 'font_recursive',
                  label: 'Font: Recursive Mono Casual',
                  checked:
                      EditorSettingsService.instance.fontFamily ==
                      EditorFontFamily.recursive,
                ),
                RetroMenuSeparator<String>(),
                // A non-selectable group label, then the two schemes. Rule 8:
                // the check mark depends on the live setting, so these rows are
                // intentionally not const.
                const RetroMenuItem<String>(
                  value: 'syntax_header',
                  label: 'Syntax Colors',
                  enabled: false,
                ),
                for (final scheme in SyntaxScheme.values)
                  RetroMenuItem<String>(
                    value: 'syntax_${scheme.id}',
                    label: scheme.label,
                    checked:
                        EditorSettingsService.instance.syntaxScheme == scheme,
                  ),
                const RetroMenuSeparator<String>(),
                // Rule 8: the check mark depends on the live theme, so these rows
                // are intentionally not const.
                RetroMenuItem<String>(
                  value: 'theme_vc6',
                  label: 'Theme: VC++ 6.0',
                  checked: ThemeService.instance.currentTheme == ThemeType.vc6,
                ),
                RetroMenuItem<String>(
                  value: 'theme_delphi',
                  label: 'Theme: Borland Delphi',
                  checked:
                      ThemeService.instance.currentTheme == ThemeType.delphi,
                ),
                RetroMenuItem<String>(
                  value: 'theme_vb6',
                  label: 'Theme: Visual Basic 6.0',
                  checked: ThemeService.instance.currentTheme == ThemeType.vb6,
                ),
                RetroMenuItem<String>(
                  value: 'theme_tp',
                  label: 'Theme: Turbo Pascal',
                  checked:
                      ThemeService.instance.currentTheme ==
                      ThemeType.turboPascal,
                ),
              ],
              onSelected: (value) {
                if (value == 'toggle_explorer') {
                  onToggleFileExplorer?.call();
                } else if (value == 'toggle_console') {
                  onToggleConsole?.call();
                } else if (value == 'toggle_diagnostics') {
                  onToggleDiagnostics?.call();
                } else if (value == 'font_increase') {
                  EditorSettingsService.instance.increase();
                } else if (value == 'font_decrease') {
                  EditorSettingsService.instance.decrease();
                } else if (value == 'font_reset') {
                  EditorSettingsService.instance.reset();
                } else if (value == 'font_menlo') {
                  EditorSettingsService.instance.setFontFamily(
                    EditorFontFamily.menlo,
                  );
                } else if (value == 'font_recursive') {
                  EditorSettingsService.instance.setFontFamily(
                    EditorFontFamily.recursive,
                  );
                } else if (SyntaxScheme.values.any(
                  (scheme) => value == 'syntax_${scheme.id}',
                )) {
                  EditorSettingsService.instance.setSyntaxScheme(
                    SyntaxScheme.fromId(value.substring('syntax_'.length)),
                  );
                } else if (value == 'theme_vc6') {
                  ThemeService.instance.switchTheme(ThemeType.vc6);
                } else if (value == 'theme_delphi') {
                  ThemeService.instance.switchTheme(ThemeType.delphi);
                } else if (value == 'theme_vb6') {
                  ThemeService.instance.switchTheme(ThemeType.vb6);
                } else if (value == 'theme_tp') {
                  ThemeService.instance.switchTheme(ThemeType.turboPascal);
                }
              },
            ),
            _buildMenuHeader(
              context: context,
              label: 'Run',
              items: () => const <PopupMenuEntry<String>>[
                RetroMenuItem<String>(
                  value: 'run',
                  label: 'Run',
                  shortcut: 'F5',
                ),
                RetroMenuItem<String>(value: 'stop', label: 'Stop'),
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
              items: () => const <PopupMenuEntry<String>>[
                RetroMenuItem<String>(
                  value: 'run_analysis',
                  label: 'Run Analysis',
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
              items: () => const <PopupMenuEntry<String>>[
                RetroMenuItem<String>(
                  value: 'about',
                  label: 'About Classic Code Editor',
                ),
                RetroMenuItem<String>(
                  value: 'shortcuts',
                  label: 'Keyboard Shortcuts',
                ),
                RetroMenuItem<String>(
                  value: 'system',
                  label: 'System & Tech Info',
                ),
              ],
              onSelected: (value) {
                if (value == 'about') {
                  showRetroAboutDialog(context, initialTab: 0);
                } else if (value == 'shortcuts') {
                  showRetroAboutDialog(context, initialTab: 1);
                } else if (value == 'system') {
                  showRetroAboutDialog(context, initialTab: 2);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// File menu, including the numbered "Open Recent" section.
  ///
  /// The list is read while the menu is built (and the bar rebuilds whenever
  /// the session changes), so there is no nested popup: exactly the classic
  /// numbered MRU block, then "Clear Recent Files", then Exit.
  List<PopupMenuEntry<String>> _fileMenuItems() {
    final recents = SessionService.instance.recentFiles;
    return <PopupMenuEntry<String>>[
      const RetroMenuItem<String>(
        value: 'new',
        label: 'New File',
        shortcut: 'Cmd + N',
      ),
      const RetroMenuItem<String>(
        value: 'open',
        label: 'Open File',
        shortcut: 'Cmd + O',
      ),
      const RetroMenuItem<String>(
        value: 'open_folder',
        label: 'Open Folder...',
        shortcut: 'Cmd + Shift + O',
      ),
      const RetroMenuItem<String>(
        value: 'close_folder',
        label: 'Close Folder',
      ),
      const RetroMenuItem<String>(
        value: 'save',
        label: 'Save',
        shortcut: 'Cmd + S',
      ),
      const RetroMenuItem<String>(
        value: 'save_as',
        label: 'Save As',
        shortcut: 'Cmd + Shift + S',
      ),
      const RetroMenuItem<String>(
        value: 'close_tab',
        label: 'Close Tab',
        shortcut: 'Cmd + W',
      ),
      const RetroMenuSeparator<String>(),
      if (recents.isEmpty)
        const RetroMenuItem<String>(
          value: 'no_recent',
          label: '(No recent files)',
          enabled: false,
        )
      else ...[
        for (var i = 0; i < recents.length; i++)
          RetroMenuItem<String>(
            value: 'recent_$i',
            label: '${i + 1}  ${recents[i].split('/').last}',
          ),
        const RetroMenuItem<String>(
          value: 'clear_recent',
          label: 'Clear Recent Files',
        ),
      ],
      const RetroMenuSeparator<String>(),
      const RetroMenuItem<String>(value: 'exit', label: 'Exit'),
    ];
  }

  void _undoText() {
    // CodeController in this version of flutter_code_editor does not expose
    // undo/redo programmatically. The editor still supports Cmd/Ctrl+Z via
    // the native text input on platform views.
  }

  /// Selects the whole buffer (same action as the editor's own Cmd+A).
  void _selectAllText() {
    final controller = codeEditorController;
    if (controller == null) return;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  /// Adds or removes the language's line comment on the selected lines.
  void _toggleComment() {
    final controller = codeEditorController;
    if (controller == null) return;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : 0;
    final end = selection.isValid ? selection.end : 0;

    final result = toggleComment(
      text: controller.text,
      selectionStart: start,
      selectionEnd: end,
      filePath: fileService?.currentFilePath,
    );
    controller.value = TextEditingValue(
      text: result.text,
      selection: TextSelection(
        baseOffset: result.selectionStart,
        extentOffset: result.selectionEnd,
      ),
    );
  }

  /// Duplicates the current line (or selected lines) right below itself.
  void _duplicateLine() {
    final controller = codeEditorController;
    if (controller == null) return;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : 0;
    final end = selection.isValid ? selection.end : 0;

    final result = duplicateLines(
      text: controller.text,
      selectionStart: start,
      selectionEnd: end,
    );
    controller.value = TextEditingValue(
      text: result.text,
      selection: TextSelection(
        baseOffset: result.selectionStart,
        extentOffset: result.selectionEnd,
      ),
    );
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

  /// Builds one dropdown with the shared retro look.
  ///
  /// [items] is a **builder**, not a list: the rows are constructed when the
  /// popup opens, because their `checked` flag reflects live state (the active
  /// theme, the active font). Building them in `build()` froze the check marks
  /// at the last rebuild of this bar - which only listens to [SessionService] -
  /// so choosing a font updated the editor but left the check on the previous
  /// row. All rows also get the same shortcut-column width (measured from the
  /// real text) so labels and shortcuts line up across the whole menu.
  Widget _buildMenuHeader({
    required BuildContext context,
    required String label,
    required List<PopupMenuEntry<String>> Function() items,
    required PopupMenuItemSelected<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) {
        final built = items();
        final rows = built.whereType<RetroMenuItem<String>>().toList(
          growable: false,
        );
        final shortcutColumn = RetroMenuMetrics.shortcutColumnWidth(
          rows.map((row) => row.shortcut).whereType<String>(),
        );
        // One measured width for the whole dropdown, so labels and the
        // shortcut column line up and no row can ever overflow.
        final rowWidth = RetroMenuMetrics.menuWidth(
          rows.map((row) => row.label),
          rows.any((row) => row.shortcut != null) ? shortcutColumn : 0,
        );
        return built
            .map(
              (item) => item is RetroMenuItem<String>
                  ? item.withMetrics(
                      rowWidth: rowWidth,
                      shortcutColumnWidth: shortcutColumn,
                    )
                  : item,
            )
            .toList(growable: false);
      },
      offset: const Offset(0, 22),
      color: RetroColors.panel,
      elevation: 0,
      shape: const RetroPopupShape(),
      menuPadding: const EdgeInsets.symmetric(vertical: 2),
      constraints: const BoxConstraints(
        minWidth: RetroMenuMetrics.minMenuWidth,
        maxWidth: RetroMenuMetrics.maxMenuWidth,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: RetroMenuMetrics.textStyle.copyWith(color: RetroColors.text),
        ),
      ),
    );
  }
}
