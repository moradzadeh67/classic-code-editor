class TabFile {
  final String? filePath;
  final String fileName;
  String content;
  final String originalContent;

  TabFile({this.filePath, required this.fileName, required this.content})
    : originalContent = content;

  bool get isModified => content != originalContent;

  String get displayName => isModified ? '$fileName *' : fileName;
}
