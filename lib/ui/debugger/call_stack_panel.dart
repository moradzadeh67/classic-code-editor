import 'package:flutter/material.dart';

import '../../services/base_debugger.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';
import '../../models/debugger_models.dart';

class CallStackPanel extends StatelessWidget {
  final BaseDebugger debugger;

  const CallStackPanel({super.key, required this.debugger});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([debugger, ThemeService.instance]),
      builder: (context, _) {
        final uiColors = ThemeService.instance.uiColors;
        final isActive = debugger.state != DebugState.inactive;
        final callStack = debugger.callStack;

        return Container(
          decoration: RetroBorder.sunken(backgroundColor: uiColors['panel']),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: uiColors['highlight'],
                child: Text(
                  'Call Stack',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Arial',
                    color: uiColors['text'],
                  ),
                ),
              ),
              Expanded(
                child: !isActive
                    ? Center(
                        child: Text(
                          'No active debug session.',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Arial',
                            color: uiColors['text']?.withValues(alpha: 0.6),
                          ),
                        ),
                      )
                    : callStack.isEmpty
                    ? Center(
                        child: Text(
                          'Call stack is empty.',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Arial',
                            color: uiColors['text']?.withValues(alpha: 0.6),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: callStack.length,
                        itemBuilder: (context, index) {
                          final frame = callStack[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              '${frame.name} at ${frame.filePath}:${frame.line}',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'Menlo',
                                color: uiColors['text'],
                              ),
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
