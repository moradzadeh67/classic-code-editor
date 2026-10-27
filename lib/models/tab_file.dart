class TabFile {
  final String? filePath;
  final String fileName;
  String content;
  final String originalContent;

  /// Language chosen for THIS tab from the toolbar dropdown.
  ///
  /// In memory only (never part of the saved session): `'Auto'` means the one
  /// resolver decides from the extension and, for unsaved buffers, the content.
  /// A tab keeps its own choice so switching tabs cannot run one file as
  /// another file's language.
  String languageOverride;

  TabFile({
    this.filePath,
    required this.fileName,
    required this.content,
    this.languageOverride = 'Auto',
  }) : originalContent = content;

  bool get isModified => content != originalContent;

  String get displayName => isModified ? '$fileName *' : fileName;
}
