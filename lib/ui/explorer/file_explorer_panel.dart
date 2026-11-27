import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../models/file_node.dart';
import '../../services/file_explorer_service.dart';
import '../../services/theme_service.dart';
import '../retro/language_logo.dart';
import '../retro/retro_border.dart';
import '../retro/retro_button.dart';
import '../retro/retro_colors.dart';
import '../retro/retro_confirm_dialog.dart';
import '../retro/retro_input_dialog.dart';
import '../shell/retro_menu_item.dart';

/// Height of the empty state's "Open Folder..." button.
///
/// A little taller than a panel-header button ([kRetroHeaderButtonHeight]) so
/// the panel's only action reads as the main action.
const double kOpenFolderButtonHeight = 28;

/// Commands of the explorer's right-click menu.
enum ExplorerAction {
  open,
  newFile,
  newFolder,
  cut,
  copy,
  paste,
  duplicate,
  rename,
  delete,
  copyPath,
  copyRelativePath,
  revealInFinder,
  refresh,
}

/// Sunken retro file explorer: lazy tree, single click selects, clicking a
/// folder opens it, double-clicking a file asks the shell to open it, and a
/// right click opens a menu of file operations (new, rename, delete, …).
class FileExplorerPanel extends StatefulWidget {
  const FileExplorerPanel({
    super.key,
    required this.service,
    required this.activeFilePath,
    required this.onOpenFile,
    this.onOpenFolder,
    this.onOpenPath,
    this.onPathMoved,
    this.onBeforeDelete,
  });

  /// An entry was renamed or moved on disk (Rename, Cut + Paste): the shell
  /// points the open tabs at the new path.
  final void Function(String from, String to)? onPathMoved;

  /// Asked before an entry goes to the Trash: the shell closes the tabs of the
  /// file (or of the files inside the folder), asking about unsaved edits.
  /// Returning false cancels the delete.
  final Future<bool> Function(String path)? onBeforeDelete;

  final FileExplorerService service;

  /// "Open Folder..." buttons. When null the panel just asks the service.
  final VoidCallback? onOpenFolder;

  /// A folder typed into the path bar (already checked to exist). The shell
  /// uses it to keep the session and language servers in step; when null the
  /// panel opens it on the service directly.
  final ValueChanged<String>? onOpenPath;

  /// Path of the active tab, highlighted in the tree.
  final String? activeFilePath;

  /// Called for a double-clicked file (the shell applies the open guards).
  final ValueChanged<String> onOpenFile;

  @override
  State<FileExplorerPanel> createState() => _FileExplorerPanelState();
}

class _FileExplorerPanelState extends State<FileExplorerPanel> {
  /// Row the user clicked, highlighted alongside the active tab.
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceChanged);
    _revealActiveFile();
  }

  @override
  void didUpdateWidget(covariant FileExplorerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service.removeListener(_onServiceChanged);
      widget.service.addListener(_onServiceChanged);
    }
    if (oldWidget.activeFilePath != widget.activeFilePath) {
      _revealActiveFile();
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  /// Opens the folders leading to the active tab's file.
  void _revealActiveFile() {
    final path = widget.activeFilePath;
    if (path == null) return;
    widget.service.revealFile(path).catchError((_) {});
  }

  List<_Row> _visibleRows() {
    final rows = <_Row>[];
    void walk(List<FileNode> nodes, int depth) {
      for (final node in nodes) {
        rows.add(_Row(node, depth));
        if (node.isDirectory && node.expanded) {
          walk(node.children, depth + 1);
        }
      }
    }

    // The open folder is the first row of the tree, like in any file browser;
    // its entries hang below it, indented one level.
    final root = widget.service.root;
    if (root != null) {
      rows.add(_Row(root, 0));
      if (root.expanded) {
        if (root.children.isEmpty) {
          rows.add(
            _Row(
              FileNode(
                path: '',
                name: '(empty)',
                isDirectory: false,
                isTruncationNotice: true,
              ),
              1,
            ),
          );
        } else {
          walk(root.children, 1);
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final uiColors = ThemeService.instance.uiColors;
    final rootPath = widget.service.rootPath;
    final rows = _visibleRows();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: RetroBorder.sunken(backgroundColor: uiColors['panel']),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rootPath == null ? 'File Explorer' : widget.service.rootName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: uiColors['text'],
                  ),
                ),
              ),
              RetroButton(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                onPressed: _openFolderDialog,
                child: Tooltip(
                  message: 'Open Folder...',
                  child: Icon(
                    Icons.folder_open_sharp,
                    size: 15,
                    color: uiColors['folderIcon'],
                  ),
                ),
              ),
              if (rootPath != null) const SizedBox(width: 4),
              if (rootPath != null)
                RetroButton(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  onPressed: () => widget.service.refresh(),
                  child: Tooltip(
                    message: 'Refresh',
                    child: Text(
                      '⟳',
                      style: TextStyle(fontSize: 15, color: uiColors['text']),
                    ),
                  ),
                ),
            ],
          ),
          if (rootPath != null) ...[
            const SizedBox(height: 4),
            _PathBar(
              path: rootPath,
              service: widget.service,
              onSubmit: _openTyped,
            ),
          ],
          const SizedBox(height: 6),
          if (rootPath == null)
            // The empty state's primary action: full panel width, a little
            // taller than a header button, label centered both ways.
            SizedBox(
              width: double.infinity,
              child: RetroButton(
                height: kOpenFolderButtonHeight,
                onPressed: _openFolderDialog,
                child: const Text(
                  'Open Folder...',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                primary: false,
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return _FileTreeRow(
                    key: ValueKey<String>(
                      'explorer-row-${row.node.path}-${row.depth}',
                    ),
                    node: row.node,
                    depth: row.depth,
                    isActive:
                        widget.activeFilePath != null &&
                        row.node.path == widget.activeFilePath,
                    isSelected:
                        _selectedPath != null && row.node.path == _selectedPath,
                    onTap: () => _onTap(row.node),
                    onDoubleTap: row.node.isDirectory
                        ? null
                        : () => widget.onOpenFile(row.node.path),
                    onContextMenu: (position) =>
                        _showContextMenu(row.node, position),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _openFolderDialog() {
    final callback = widget.onOpenFolder;
    if (callback != null) {
      callback();
    } else {
      widget.service.pickFolder();
    }
  }

  void _openTyped(String path) {
    final callback = widget.onOpenPath;
    if (callback != null) {
      callback(path);
    } else {
      widget.service.openFolder(path);
    }
  }

  void _onTap(FileNode node) {
    if (node.isTruncationNotice) return;
    setState(() {
      _selectedPath = node.isDirectory ? null : node.path;
    });
    if (node.isDirectory) {
      widget.service.toggleFolder(node);
    }
  }

  // ---------------------------------------------------------------------------
  // Right-click menu
  // ---------------------------------------------------------------------------

  /// Rows of the menu for [node]; built when the menu opens, so Paste reflects
  /// the clipboard right now.
  List<PopupMenuEntry<ExplorerAction>> _menuEntries(FileNode node) {
    final isRoot = node.path == widget.service.rootPath;
    final isFolder = node.isDirectory;
    RetroMenuItem<ExplorerAction> item(
      ExplorerAction value,
      String label, {
      bool enabled = true,
    }) => RetroMenuItem<ExplorerAction>(
      key: ValueKey<String>('explorer-menu-${value.name}'),
      value: value,
      label: label,
      enabled: enabled,
    );
    const separator = RetroMenuSeparator<ExplorerAction>();

    return <PopupMenuEntry<ExplorerAction>>[
      if (isFolder) ...[
        item(ExplorerAction.newFile, 'New File...'),
        item(ExplorerAction.newFolder, 'New Folder...'),
      ] else
        item(ExplorerAction.open, 'Open'),
      separator,
      if (!isRoot) item(ExplorerAction.cut, 'Cut'),
      item(ExplorerAction.copy, 'Copy'),
      item(ExplorerAction.paste, 'Paste', enabled: widget.service.hasClipboard),
      if (!isRoot) item(ExplorerAction.duplicate, 'Duplicate'),
      if (!isRoot) ...[
        separator,
        item(ExplorerAction.rename, 'Rename...'),
        item(ExplorerAction.delete, 'Move to Trash'),
      ],
      separator,
      item(ExplorerAction.copyPath, 'Copy Path'),
      if (!isRoot) item(ExplorerAction.copyRelativePath, 'Copy Relative Path'),
      item(ExplorerAction.revealInFinder, 'Reveal in Finder'),
      if (isFolder) ...[separator, item(ExplorerAction.refresh, 'Refresh')],
    ];
  }

  Future<void> _showContextMenu(FileNode node, Offset position) async {
    if (node.isTruncationNotice) return;
    setState(() => _selectedPath = node.path);

    final built = _menuEntries(node);
    final rows = built.whereType<RetroMenuItem<ExplorerAction>>().toList(
      growable: false,
    );
    // One measured width for every row, as in the menu bar's dropdowns.
    final rowWidth = RetroMenuMetrics.menuWidth(
      rows.map((row) => row.label),
      0,
    );
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<ExplorerAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: built
          .map(
            (entry) => entry is RetroMenuItem<ExplorerAction>
                ? entry.withMetrics(rowWidth: rowWidth, shortcutColumnWidth: 0)
                : entry,
          )
          .toList(growable: false),
      color: RetroColors.panel,
      elevation: 0,
      shape: const RetroPopupShape(),
      menuPadding: const EdgeInsets.symmetric(vertical: 2),
      constraints: const BoxConstraints(
        minWidth: RetroMenuMetrics.minMenuWidth,
        maxWidth: RetroMenuMetrics.maxMenuWidth,
      ),
    );
    if (action == null || !mounted) return;
    await _run(action, node);
  }

  /// Runs one menu command; any failure is shown to the user.
  Future<void> _run(ExplorerAction action, FileNode node) async {
    final service = widget.service;
    final path = node.path;
    // New items and pasted items go into the folder itself, or next to a file.
    final targetFolder = node.isDirectory
        ? path
        : FileExplorerService.parentOf(path);
    try {
      switch (action) {
        case ExplorerAction.open:
          widget.onOpenFile(path);
        case ExplorerAction.newFile:
          final name = await _askName(
            title: 'New File',
            label: 'File name:',
            folder: targetFolder,
          );
          if (name == null) return;
          final created = await service.createFile(targetFolder, name);
          _select(created);
          widget.onOpenFile(created);
        case ExplorerAction.newFolder:
          final name = await _askName(
            title: 'New Folder',
            label: 'Folder name:',
            folder: targetFolder,
          );
          if (name == null) return;
          _select(await service.createFolder(targetFolder, name));
        case ExplorerAction.cut:
          service.cutToClipboard(path);
        case ExplorerAction.copy:
          service.copyToClipboard(path);
        case ExplorerAction.paste:
          final result = await service.paste(targetFolder);
          if (result == null) return;
          if (result.moved) widget.onPathMoved?.call(result.from, result.to);
          _select(result.to);
        case ExplorerAction.duplicate:
          _select(await service.duplicate(path));
        case ExplorerAction.rename:
          final folder = FileExplorerService.parentOf(path);
          final name = await _askName(
            title: node.isDirectory ? 'Rename Folder' : 'Rename File',
            label: 'New name:',
            folder: folder,
            initialValue: node.name,
            currentName: node.name,
            okLabel: 'Rename',
          );
          if (name == null || name == node.name) return;
          final renamed = await service.rename(path, name);
          widget.onPathMoved?.call(path, renamed);
          _select(renamed);
        case ExplorerAction.delete:
          await _moveToTrash(node);
        case ExplorerAction.copyPath:
          await Clipboard.setData(ClipboardData(text: path));
        case ExplorerAction.copyRelativePath:
          await Clipboard.setData(
            ClipboardData(text: service.relativePath(path)),
          );
        case ExplorerAction.revealInFinder:
          await service.revealInFinder(path);
        case ExplorerAction.refresh:
          await service.refresh();
      }
    } on FileOperationException catch (error) {
      _showError(error.message);
    }
  }

  Future<void> _moveToTrash(FileNode node) async {
    final confirmed = await showRetroConfirmDialog(
      context,
      message: node.isDirectory
          ? 'Move the folder "${node.name}" and its contents to the Trash?'
          : 'Move "${node.name}" to the Trash?',
      detail: 'You can restore it from the Trash in Finder.',
      confirmLabel: 'Move to Trash',
    );
    if (!confirmed || !mounted) return;
    final canDelete = await widget.onBeforeDelete?.call(node.path) ?? true;
    if (!canDelete || !mounted) return;
    await widget.service.moveToTrash(node.path);
    if (_selectedPath == node.path) setState(() => _selectedPath = null);
  }

  Future<String?> _askName({
    required String title,
    required String label,
    required String folder,
    String initialValue = '',
    String? currentName,
    String okLabel = 'OK',
  }) {
    return showRetroInputDialog(
      context,
      title: title,
      label: label,
      initialValue: initialValue,
      okLabel: okLabel,
      selectBaseName: currentName != null,
      validator: (value) =>
          widget.service.nameError(folder, value, currentName: currentName),
    );
  }

  void _select(String path) {
    if (mounted) setState(() => _selectedPath = path);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

/// Editable path of the open folder, in a sunken box.
///
/// Shows the full path from the filesystem root. Typing a path and pressing
/// Enter opens that folder; a path that is not an existing folder is refused
/// with a message and the box goes back to the open folder.
class _PathBar extends StatefulWidget {
  const _PathBar({
    required this.path,
    required this.service,
    required this.onSubmit,
  });

  final String path;
  final FileExplorerService service;
  final ValueChanged<String> onSubmit;

  @override
  State<_PathBar> createState() => _PathBarState();
}

class _PathBarState extends State<_PathBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.path,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant _PathBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new folder was opened (tree, dialog, menu): show it, unless the user
    // is in the middle of typing something else.
    if (oldWidget.path != widget.path &&
        (!_focusNode.hasFocus || _controller.text == oldWidget.path)) {
      _controller.text = widget.path;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String typed) {
    final resolved = widget.service.resolveDirectory(typed);
    if (resolved == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Not a folder', style: TextStyle(fontSize: 13)),
          duration: Duration(seconds: 2),
        ),
      );
      _controller.text = widget.path;
      return;
    }
    _controller.text = resolved;
    _focusNode.unfocus();
    if (resolved != widget.path) widget.onSubmit(resolved);
  }

  @override
  Widget build(BuildContext context) {
    final uiColors = ThemeService.instance.uiColors;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.centerLeft,
      decoration: RetroBorder.sunken(
        backgroundColor: uiColors['editorBackground'],
      ),
      child: TextField(
        key: const ValueKey<String>('explorer-path-bar'),
        controller: _controller,
        focusNode: _focusNode,
        maxLines: 1,
        onSubmitted: _submit,
        style: TextStyle(fontSize: 13, color: uiColors['editorText']),
        cursorColor: uiColors['editorCursor'],
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _Row {
  const _Row(this.node, this.depth);
  final FileNode node;
  final int depth;
}

class _FileTreeRow extends StatelessWidget {
  const _FileTreeRow({
    super.key,
    required this.node,
    required this.depth,
    required this.isActive,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onContextMenu,
  });

  final FileNode node;
  final int depth;
  final bool isActive;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  /// Right click, with the pointer's global position.
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final uiColors = ThemeService.instance.uiColors;
    final accent = ThemeService.instance.colors.selection;
    final background = isActive
        ? accent.withValues(alpha: 0.35)
        : isSelected
        ? accent.withValues(alpha: 0.18)
        : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapUp: (details) => onContextMenu(details.globalPosition),
      child: Container(
        height: 24,
        color: background,
        padding: EdgeInsets.only(left: 4 + depth * 16.0),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: node.isDirectory && !node.isTruncationNotice
                  ? Text(
                      node.expanded ? '▾' : '▸',
                      style: TextStyle(fontSize: 13, color: uiColors['text']),
                    )
                  : null,
            ),
            const SizedBox(width: 2),
            _icon(),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: uiColors['text'],
                  fontStyle: node.isTruncationNotice
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon() {
    final uiColors = ThemeService.instance.uiColors;
    if (node.isDirectory) {
      return Icon(
        node.expanded ? Icons.folder_open_sharp : Icons.folder_sharp,
        size: 18,
        color: uiColors['folderIcon'],
      );
    }
    if (node.isTruncationNotice) return const SizedBox(width: 16, height: 16);
    final language = _languageFor(node.name);
    if (language != null) return LanguageLogo(language: language, size: 16);
    return Icon(
      Icons.insert_drive_file_sharp,
      size: 18,
      color: uiColors['fileIcon'],
    );
  }

  /// The language whose logo should label this file, if any.
  static String? _languageFor(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    switch (name.substring(dot + 1).toLowerCase()) {
      case 'dart':
        return 'dart';
      case 'c':
        return 'c';
      case 'cpp' || 'cc' || 'cxx' || 'h' || 'hpp':
        return 'cpp';
      case 'py':
        return 'python';
      case 's' || 'asm':
        return 'asm';
      default:
        return null;
    }
  }
}
