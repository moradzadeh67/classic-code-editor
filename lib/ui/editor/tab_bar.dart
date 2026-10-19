import 'package:flutter/material.dart';

import '../../services/file_service.dart';
import '../shell/close_guard.dart';
import '../../services/theme_service.dart';

class TabBarWidget extends StatelessWidget {
  final FileService fileService;

  const TabBarWidget({super.key, required this.fileService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: fileService,
      builder: (context, child) {
        if (fileService.openTabs.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          height: 30,
          color: ThemeService.instance.uiColors['panel'],
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < fileService.openTabs.length; i++)
                  _buildTab(context, i),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTab(BuildContext context, int index) {
    final tab = fileService.openTabs[index];
    final isActive = index == fileService.activeTabIndex;

    return GestureDetector(
      onTap: () => fileService.switchTab(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        margin: const EdgeInsets.only(right: 2, top: 2),
        decoration: BoxDecoration(
          color: isActive
              ? ThemeService.instance.uiColors['editorBackground']
              : ThemeService.instance.uiColors['panel'],
          border: Border(
            top: BorderSide(
              color: isActive
                  ? ThemeService.instance.uiColors['borderDark']!
                  : ThemeService.instance.uiColors['borderLight']!,
              width: 2,
            ),
            left: BorderSide(
              color: isActive
                  ? ThemeService.instance.uiColors['borderDark']!
                  : ThemeService.instance.uiColors['borderLight']!,
              width: 2,
            ),
            right: BorderSide(
              color: ThemeService.instance.uiColors['borderDark']!,
              width: 2,
            ),
            bottom: BorderSide(
              color: isActive
                  ? ThemeService.instance.uiColors['editorBackground']!
                  : ThemeService.instance.uiColors['borderDark']!,
              width: 2,
            ),
          ),
          borderRadius: BorderRadius.zero,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tab.displayName,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Arial',
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: ThemeService.instance.uiColors['text'],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              // Going through the shared guard means a modified tab asks
              // "Save changes to …?" instead of dropping silently.
              onTap: () => TabCloseGuard.confirmClose(
                context,
                fileService: fileService,
                index: index,
              ),
              child: const SizedBox(
                height: 12,
                width: 12,
                child: Center(
                  child: Text(
                    '×',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
