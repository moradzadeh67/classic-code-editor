/// Syntax color scheme offered by `View > Syntax Colors`.
///
/// The palette itself lives in `MultiLanguageHighlighter`; this enum only
/// carries the stable id that `editor_settings.json` persists and the label the
/// menu shows. Renaming a label can never invalidate a saved choice.
enum SyntaxScheme {
  /// The classic palette the editor has always used (the default).
  standard('standard', 'Standard'),

  /// A higher-contrast, eleven-color palette for long sessions.
  colorful('colorful', 'Colorful');

  const SyntaxScheme(this.id, this.label);

  /// Stable id persisted in `editor_settings.json`.
  final String id;

  /// Label shown under View > Syntax Colors.
  final String label;

  /// Resolves a persisted [id].
  ///
  /// A missing key (an older settings file), a corrupt value or an id from a
  /// scheme removed later all fall back to [standard], so the editor can never
  /// end up without a palette.
  static SyntaxScheme fromId(Object? id) {
    for (final scheme in values) {
      if (scheme.id == id) return scheme;
    }
    return standard;
  }
}
