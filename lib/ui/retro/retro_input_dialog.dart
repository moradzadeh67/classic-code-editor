import 'package:material_ui/material_ui.dart';

import '../../services/theme_service.dart';
import 'retro_border.dart';
import 'retro_button.dart';

/// Shows a retro one-line text prompt (New File…, Rename…).
///
/// [validator] returns an error for the typed text (shown under the field,
/// the dialog stays open) or null to accept it. When [selectBaseName] is true
/// the text before the last `.` is pre-selected, like Finder's rename, so the
/// extension survives typing a new name.
///
/// Returns the accepted text, or null when cancelled.
Future<String?> showRetroInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
  String okLabel = 'OK',
  bool selectBaseName = false,
  String? Function(String value)? validator,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _RetroInputDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      okLabel: okLabel,
      selectBaseName: selectBaseName,
      validator: validator,
    ),
  );
}

class _RetroInputDialog extends StatefulWidget {
  const _RetroInputDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.okLabel,
    required this.selectBaseName,
    required this.validator,
  });

  final String title;
  final String label;
  final String initialValue;
  final String okLabel;
  final bool selectBaseName;
  final String? Function(String value)? validator;

  @override
  State<_RetroInputDialog> createState() => _RetroInputDialogState();
}

class _RetroInputDialogState extends State<_RetroInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    final text = widget.initialValue;
    final dot = text.lastIndexOf('.');
    final end = widget.selectBaseName && dot > 0 ? dot : text.length;
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: end);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text;
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop<String>(value);
  }

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

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 320,
        child: Container(
          decoration: RetroBorder.raised(backgroundColor: colors.panel),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: textStyle.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(widget.label, style: textStyle),
              const SizedBox(height: 6),
              Container(
                decoration: RetroBorder.sunken(
                  backgroundColor: colors.editorBackground,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: TextField(
                  key: const ValueKey<String>('retro-input-field'),
                  controller: _controller,
                  autofocus: true,
                  maxLines: 1,
                  style: textStyle.copyWith(color: colors.editorText),
                  cursorColor: colors.editorText,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
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
                    child: Text(widget.okLabel, style: textStyle),
                  ),
                  const SizedBox(width: 6),
                  RetroButton(
                    onPressed: () => Navigator.of(context).pop<String>(null),
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
