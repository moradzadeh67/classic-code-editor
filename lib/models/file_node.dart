/// One entry of the file explorer's tree.
///
/// Deliberately plain Dart: no Flutter imports, no I/O. [FileExplorerService]
/// fills it in from disk, the panel only reads it.
class FileNode {
  FileNode({
    required this.path,
    required this.name,
    required this.isDirectory,
    List<FileNode>? children,
    this.childrenLoaded = false,
    this.expanded = false,
    this.isTruncationNotice = false,
  }) : children = children ?? <FileNode>[];

  /// Absolute path on disk. Empty for the synthetic truncation row.
  final String path;

  /// Last path segment, shown in the tree.
  final String name;

  final bool isDirectory;

  /// Children, read lazily the first time a directory is expanded.
  List<FileNode> children;

  /// Whether [children] were read from disk already.
  bool childrenLoaded;

  /// Whether the tree shows this directory's children.
  bool expanded;

  /// `true` on the "… N more not shown" row, which is not a real entry.
  final bool isTruncationNotice;
}
