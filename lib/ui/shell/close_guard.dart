import 'package:flutter/material.dart';

import '../../services/file_service.dart';
import '../retro/retro_confirm_dialog.dart';

/// The one place that decides whether a modified tab may be discarded.
///
/// Used by the tab's X button, `Cmd + W`, File > Close Tab and the app-exit
/// flow, so the "Save / Don't Save / Cancel" rule lives in exactly one helper.
class TabCloseGuard {
  const TabCloseGuard._();

  /// Asks the user (when needed) and closes tab [index] if allowed.
  ///
  /// Returns true when the tab was closed (or nothing had to be asked), false
  /// when the user cancelled — including a cancelled/failed Save As, which is
  /// treated as a cancel so nothing is lost.
  static Future<bool> confirmClose(
    BuildContext context, {
    required FileService fileService,
    required int index,
  }) async {
    if (index < 0 || index >= fileService.openTabs.length) return false;

    final tab = fileService.openTabs[index];
    if (!tab.isModified) {
      fileService.closeTab(index);
      return true;
    }

    final choice = await showRetroUnsavedDialog(
      context,
      fileName: tab.fileName,
    );
    switch (choice) {
      case RetroSaveChoice.cancel:
        return false;
      case RetroSaveChoice.dontSave:
        fileService.closeTab(index);
        return true;
      case RetroSaveChoice.save:
        final saved = await fileService.saveTab(index);
        if (!saved) return false;
        fileService.closeTab(index);
        return true;
    }
  }

  /// Walks the modified tabs in tab order for the exit flow.
  ///
  /// Returns true when quitting may continue; the first Cancel aborts it.
  static Future<bool> confirmExit(
    BuildContext context, {
    required FileService fileService,
  }) async {
    final modified = <int>[
      for (var i = 0; i < fileService.openTabs.length; i++)
        if (fileService.openTabs[i].isModified) i,
    ];

    for (final index in modified) {
      // The list may shrink as tabs are closed between prompts.
      if (index >= fileService.openTabs.length) continue;
      if (!fileService.openTabs[index].isModified) continue;
      // The dialog is awaited: the shell may be gone by the next prompt.
      if (!context.mounted) return false;

      final tab = fileService.openTabs[index];
      final choice = await showRetroUnsavedDialog(
        context,
        fileName: tab.fileName,
      );
      if (choice == RetroSaveChoice.cancel) return false;
      if (choice == RetroSaveChoice.save) {
        final saved = await fileService.saveTab(index);
        if (!saved) return false;
      }
    }
    return true;
  }
}
