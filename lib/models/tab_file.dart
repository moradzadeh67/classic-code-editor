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
    String? originalContent,
  }) : originalContent = originalContent ?? content;

  bool get isModified => content != originalContent;

  String get displayName => isModified ? '$fileName *' : fileName;

  /// The same tab after its file was renamed or moved to [path].
  ///
  /// Unsaved edits stay unsaved: [originalContent] is carried over.
  TabFile movedTo(String path) => TabFile(
    filePath: path,
    fileName: path.split('/').last,
    content: content,
    languageOverride: languageOverride,
    originalContent: originalContent,
  );
}
