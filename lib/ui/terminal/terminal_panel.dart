import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/terminal_service.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';

class TerminalPanel extends StatefulWidget {
  final TerminalService terminalService;

  const TerminalPanel({super.key, required this.terminalService});

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<String> _outputLines = [];
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.terminalService.outputStream.listen((line) {
      if (!mounted) return;
      setState(() {
        _outputLines.add(line);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final uiColors = ThemeService.instance.uiColors;
        return Container(
          decoration: RetroBorder.sunken(backgroundColor: uiColors['panel']),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Output area
              Expanded(
                child: Container(
                  decoration: RetroBorder.sunken(
                    backgroundColor: const Color(0xFF000000),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _outputLines.length,
                    itemBuilder: (context, index) {
                      final line = _outputLines[index];
                      Color textColor;

                      if (line.startsWith('\$') || line.contains('>')) {
                        // This is a command prompt
                        textColor = Colors.white;
                      } else if (line.contains('Error') ||
                          line.contains('error')) {
                        // This is an error
                        textColor = Colors.red;
                      } else {
                        // Normal output
                        textColor = const Color(0xFF1F7D00);
                      }

                      return Text(
                        line,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Courier New',
                          color: textColor,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Input field with history navigation
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: RetroBorder.sunken(
                  backgroundColor: const Color(0xFFFFFFFF),
                ),
                child: Row(
                  children: [
                    Text(
                      '${widget.terminalService.currentDirectory.split('/').last}> ',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'Courier New',
                        color: Color(0xFF1F7D00),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: KeyboardListener(
                        focusNode: _inputFocusNode,
                        onKeyEvent: (event) {
                          if (event is KeyDownEvent) {
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowUp) {
                              final cmd = widget.terminalService
                                  .getPreviousCommand();
                              _inputController.text = cmd;
                              _inputController.selection =
                                  TextSelection.collapsed(offset: cmd.length);
                            } else if (event.logicalKey ==
                                LogicalKeyboardKey.arrowDown) {
                              final cmd = widget.terminalService
                                  .getNextCommand();
                              _inputController.text = cmd;
                              _inputController.selection =
                                  TextSelection.collapsed(offset: cmd.length);
                            }
                          }
                        },
                        child: TextField(
                          controller: _inputController,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'Courier New',
                            color: Color(0xFF000000),
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (command) {
                            widget.terminalService.executeCommand(command);
                            _inputController.clear();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
