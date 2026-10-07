import 'package:flutter/material.dart';

import '../../services/base_debugger.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';
import '../../models/debugger_models.dart';

class VariablesPanel extends StatelessWidget {
  final BaseDebugger debugger;

  const VariablesPanel({super.key, required this.debugger});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([debugger, ThemeService.instance]),
      builder: (context, _) {
        final uiColors = ThemeService.instance.uiColors;
        final isActive = debugger.state != DebugState.inactive;
        final variables = debugger.variables;

        return Container(
          decoration: RetroBorder.sunken(backgroundColor: uiColors['panel']),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: uiColors['highlight'],
                child: Text(
                  'Variables',
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
                    : variables.isEmpty
                    ? Center(
                        child: Text(
                          'No variables in scope.',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Arial',
                            color: uiColors['text']?.withValues(alpha: 0.6),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: variables.length,
                        itemBuilder: (context, index) {
                          final v = variables[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              '${v.name} (${v.type}): ${v.value}',
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
