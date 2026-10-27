import 'package:flutter/material.dart';

import '../../models/file_node.dart';
import '../../services/file_explorer_service.dart';
import '../../services/theme_service.dart';
import '../retro/language_logo.dart';
import '../retro/retro_border.dart';
import '../retro/retro_button.dart';

/// Height of the empty state's "Open Folder..." button.
///
/// A little taller than a panel-header button ([kRetroHeaderButtonHeight]) so
/// the panel's only action reads as the main action.
const double kOpenFolderButtonHeight = 28;

/// Sunken retro file explorer: lazy tree, single click selects, clicking a
/// folder opens it, double-clicking a file asks the shell to open it.
class FileExplorerPanel extends StatefulWidget {
  const FileExplorerPanel({
    super.key,
    required this.service,
    required this.activeFilePath,
    required this.onOpenFile,
  });

  final FileExplorerService service;

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

    final root = widget.service.root;
    if (root != null) walk(root.children, 0);
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
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: uiColors['text'],
                  ),
                ),
              ),
              if (rootPath != null)
                RetroButton(
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onPressed: () => widget.service.refresh(),
                  child: Tooltip(
                    message: 'Refresh',
                    child: Text(
                      '⟳',
                      style: TextStyle(fontSize: 12, color: uiColors['text']),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (rootPath == null)
            // The empty state's primary action: full panel width, a little
            // taller than a header button, label centered both ways.
            SizedBox(
              width: double.infinity,
              child: RetroButton(
                height: kOpenFolderButtonHeight,
                onPressed: () => widget.service.pickFolder(),
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
                    key: ValueKey<String>('explorer-row-${row.node.path}-${row.depth}'),
                    node: row.node,
                    depth: row.depth,
                    isActive:
                        widget.activeFilePath != null &&
                        row.node.path == widget.activeFilePath,
                    isSelected: _selectedPath != null &&
                        row.node.path == _selectedPath,
                    onTap: () => _onTap(row.node),
                    onDoubleTap: row.node.isDirectory
                        ? null
                        : () => widget.onOpenFile(row.node.path),
                  );
                },
              ),
            ),
        ],
      ),
    );
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
  });

  final FileNode node;
  final int depth;
  final bool isActive;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

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
      child: Container(
        height: 20,
        color: background,
        padding: EdgeInsets.only(left: 4 + depth * 12.0),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              child: node.isDirectory && !node.isTruncationNotice
                  ? Text(
                      node.expanded ? '▾' : '▸',
                      style: TextStyle(fontSize: 10, color: uiColors['text']),
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
                  fontSize: 11,
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
        size: 12,
        color: uiColors['text'],
      );
    }
    if (node.isTruncationNotice) return const SizedBox(width: 12, height: 12);
    final language = _languageFor(node.name);
    if (language != null) return LanguageLogo(language: language, size: 12);
    return Icon(
      Icons.insert_drive_file_sharp,
      size: 12,
      color: uiColors['text'],
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
