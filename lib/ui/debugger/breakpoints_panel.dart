import 'package:flutter/material.dart';

import '../../services/base_debugger.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';
import '../retro/retro_button.dart';

class BreakpointsPanel extends StatelessWidget {
  final BaseDebugger debugger;

  const BreakpointsPanel({super.key, required this.debugger});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([debugger, ThemeService.instance]),
      builder: (context, _) {
        final uiColors = ThemeService.instance.uiColors;
        final breakpoints = debugger.breakpoints;

        return Container(
          decoration: RetroBorder.sunken(backgroundColor: uiColors['panel']),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: uiColors['highlight'],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Breakpoints (${breakpoints.length})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Arial',
                        color: uiColors['text'],
                      ),
                    ),
                    if (breakpoints.isNotEmpty)
                      SizedBox(
                        height: 36,
                        child: RetroButton(
                          height: 36,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0,
                          ),
                          onPressed: () => debugger.clearBreakpoints(),
                          child: const Text(
                            'Clear All',
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: breakpoints.isEmpty
                    ? Center(
                        child: Text(
                          'No breakpoints set.\nClick line gutter to add.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Arial',
                            color: uiColors['text']?.withValues(alpha: 0.6),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: breakpoints.length,
                        itemBuilder: (context, index) {
                          final bp = breakpoints[index];
                          final fileName = bp.filePath.split('/').last;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: uiColors['borderDark'] ?? Colors.grey,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '$fileName : line ${bp.line}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'Arial',
                                      color: uiColors['text'],
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => debugger.removeBreakpoint(
                                    bp.filePath,
                                    bp.line,
                                  ),
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: uiColors['text'],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
