import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import '../retro/retro_border.dart';
import '../retro/retro_button.dart';

/// Which answer the user gave to the "Save changes to …?" prompt.
enum RetroSaveChoice { save, dontSave, cancel }

/// Shows the classic retro prompt: `Save changes to <fileName>?`
///
/// Returns [RetroSaveChoice.cancel] when the dialog is dismissed with Escape, so
/// callers can treat "escaped out of it" exactly like an explicit cancel.
Future<RetroSaveChoice> showRetroUnsavedDialog(
  BuildContext context, {
  required String fileName,
}) async {
  final choice = await showDialog<RetroSaveChoice>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _RetroUnsavedDialog(fileName: fileName),
  );
  return choice ?? RetroSaveChoice.cancel;
}

class _RetroUnsavedDialog extends StatelessWidget {
  const _RetroUnsavedDialog({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    // Rule 8: colors come from the live theme, so nothing here is const.
    final colors = ThemeService.instance.colors;
    final textStyle = TextStyle(
      fontFamily: 'Arial',
      fontSize: 12,
      height: 1.2,
      color: colors.text,
    );

    void answer(RetroSaveChoice choice) =>
        Navigator.of(context).pop<RetroSaveChoice>(choice);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 340,
        child: Container(
          decoration: RetroBorder.raised(backgroundColor: colors.panel),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Save changes to $fileName?', style: textStyle),
              const SizedBox(height: 6),
              Text(
                "Your changes will be lost if you don't save them.",
                style: textStyle.copyWith(color: colors.shadow),
              ),
              const SizedBox(height: 14),
              // Wrap, not Row: three retro buttons never overflow a narrow
              // window (they drop to a second line instead).
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  RetroButton(
                    onPressed: () => answer(RetroSaveChoice.save),
                    child: Text('Save', style: textStyle),
                  ),
                  RetroButton(
                    onPressed: () => answer(RetroSaveChoice.dontSave),
                    child: Text("Don't Save", style: textStyle),
                  ),
                  RetroButton(
                    onPressed: () => answer(RetroSaveChoice.cancel),
                    child: Text('Cancel', style: textStyle),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
