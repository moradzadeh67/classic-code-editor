import 'package:flutter/material.dart';

import '../../services/base_debugger.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';
import '../retro/retro_button.dart';
import 'breakpoints_panel.dart';
import 'variables_panel.dart';
import 'call_stack_panel.dart';

class DebuggerSidebar extends StatefulWidget {
  final BaseDebugger debugger;

  const DebuggerSidebar({super.key, required this.debugger});

  @override
  State<DebuggerSidebar> createState() => _DebuggerSidebarState();
}

class _DebuggerSidebarState extends State<DebuggerSidebar> {
  int _selectedTab = 0; // 0: Breakpoints, 1: Variables, 2: Call Stack

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final uiColors = ThemeService.instance.uiColors;

        return Container(
          width: 240,
          decoration: RetroBorder.raised(backgroundColor: uiColors['panel']),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title / Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: uiColors['menuActive'],
                child: Text(
                  'DEBUGGER',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Arial',
                    color: uiColors['menuActiveText'],
                  ),
                ),
              ),
              // Sub-tabs for Debugger panels
              Container(
                padding: const EdgeInsets.all(4),
                color: uiColors['panel'],
                child: Row(
                  children: [
                    Expanded(
                      child: RetroButton(
                        isPressed: _selectedTab == 0,
                        onPressed: () => setState(() => _selectedTab = 0),
                        child: const Text(
                          'Bps',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: RetroButton(
                        isPressed: _selectedTab == 1,
                        onPressed: () => setState(() => _selectedTab = 1),
                        child: const Text(
                          'Vars',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: RetroButton(
                        isPressed: _selectedTab == 2,
                        onPressed: () => setState(() => _selectedTab = 2),
                        child: const Text(
                          'Stack',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Active panel
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: _selectedTab == 0
                      ? BreakpointsPanel(debugger: widget.debugger)
                      : _selectedTab == 1
                      ? VariablesPanel(debugger: widget.debugger)
                      : CallStackPanel(debugger: widget.debugger),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
