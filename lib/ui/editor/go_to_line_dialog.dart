import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import '../retro/retro_border.dart';
import '../retro/retro_button.dart';

/// Shows the retro "Go to Line" prompt.
///
/// Returns the 1-based target line number, or `null` if cancelled.
Future<int?> showGoToLineDialog(
  BuildContext context, {
  required int maxLines,
}) async {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => _GoToLineDialog(maxLines: maxLines),
  );
}

class _GoToLineDialog extends StatefulWidget {
  const _GoToLineDialog({required this.maxLines});

  final int maxLines;

  @override
  State<_GoToLineDialog> createState() => _GoToLineDialogState();
}

class _GoToLineDialogState extends State<_GoToLineDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 1 || value > widget.maxLines) {
      setState(() {
        _error = 'Please enter a number between 1 and ${widget.maxLines}';
      });
      return;
    }
    Navigator.of(context).pop<int>(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ThemeService.instance.colors;
    final textStyle = TextStyle(
      fontFamily: 'Arial',
      fontSize: 12,
      color: colors.text,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SizedBox(
        width: 280,
        child: Container(
          decoration: RetroBorder.raised(backgroundColor: colors.panel),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Line Number (1 - ${widget.maxLines}):', style: textStyle),
              const SizedBox(height: 6),
              Container(
                decoration: RetroBorder.sunken(
                  backgroundColor: colors.editorBackground,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  style: textStyle.copyWith(color: colors.editorText),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: textStyle.copyWith(color: colors.error, fontSize: 11),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  RetroButton(
                    onPressed: _submit,
                    child: Text('OK', style: textStyle),
                  ),
                  const SizedBox(width: 6),
                  RetroButton(
                    onPressed: () => Navigator.of(context).pop<int>(null),
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
