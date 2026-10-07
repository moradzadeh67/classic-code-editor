import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/dart_runner_service.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';
import '../retro/retro_button.dart';

class ConsolePanel extends StatefulWidget {
  final DartRunnerService dartRunnerService;

  const ConsolePanel({super.key, required this.dartRunnerService});

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  final List<String> _outputLines = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  StreamSubscription<String>? _subscription;
  String _selectedLanguage = 'Auto';

  @override
  void initState() {
    super.initState();
    debugPrint('ConsolePanel initState, listening to outputStream...');

    _subscription = widget.dartRunnerService.outputStream.listen((line) {
      debugPrint('ConsolePanel received: $line');
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
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Color _getLineColor(String line) {
    final trimmed = line.trim();

    // User input echo line
    if (trimmed.startsWith('> ')) {
      return const Color(0xFF0000CC); // Bold Navy Blue for user input
    }

    // Error / exception line
    if (trimmed.toLowerCase().contains('error') ||
        trimmed.toLowerCase().contains('exception') ||
        trimmed.toLowerCase().contains('failed') ||
        trimmed.startsWith('[Process exited with code: 1]') ||
        trimmed.startsWith('[Process exited with code: 254]')) {
      return Colors.red;
    }

    // System / Status / Compilation message line
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      return const Color(0xFF0055CC); // Blue for system status messages
    }

    // Normal program output - Richer, bolder green
    return const Color(0xFF006600);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: RetroBorder.sunken(
        backgroundColor: ThemeService.instance.uiColors['panel'],
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Console',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: ThemeService.instance.uiColors['text'],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: DropdownButton<String>(
                  value: _selectedLanguage,
                  items: ['Auto', 'Dart', 'Python', 'C', 'C++'].map((
                    String lang,
                  ) {
                    return DropdownMenuItem<String>(
                      value: lang,
                      child: Text(
                        lang,
                        style: TextStyle(
                          fontSize: 11,
                          color: ThemeService.instance.uiColors['text'],
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedLanguage = newValue ?? 'Auto';
                    });
                    widget.dartRunnerService.setPreferredLanguage(
                      _selectedLanguage,
                    );
                  },
                  style: TextStyle(
                    fontSize: 11,
                    color: ThemeService.instance.uiColors['text'],
                  ),
                  dropdownColor: ThemeService.instance.uiColors['panel'],
                  underline: const SizedBox(),
                ),
              ),
              const SizedBox(width: 8),
              RetroButton(
                onPressed: () {
                  setState(() {
                    _outputLines.clear();
                  });
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: RetroBorder.sunken(
                backgroundColor: const Color(0xFFFFFFFF),
              ),
              padding: const EdgeInsets.all(8),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _outputLines.length,
                itemBuilder: (context, index) {
                  final line = _outputLines[index];
                  final textColor = _getLineColor(line);

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Courier New',
                        color: textColor,
                        fontWeight: line.trim().startsWith('> ')
                            ? FontWeight.bold
                            : (!line.trim().startsWith('[')
                                  ? FontWeight.w600
                                  : FontWeight.normal),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Interactive Stdin Input Bar
          ListenableBuilder(
            listenable: widget.dartRunnerService,
            builder: (context, _) {
              final isRunning = widget.dartRunnerService.isRunning;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: RetroBorder.sunken(
                  backgroundColor: isRunning
                      ? const Color(0xFFFFFFFF)
                      : const Color(0xFFF0F0F0),
                ),
                child: Row(
                  children: [
                    Text(
                      'Input > ',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Courier New',
                        fontWeight: FontWeight.bold,
                        color: isRunning
                            ? const Color(0xFF0000CC)
                            : const Color(0xFF808080),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocusNode,
                        enabled: isRunning,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'Courier New',
                          color: Color(0xFF000000),
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintText: isRunning
                              ? 'Type input for stdin and press Enter...'
                              : 'Program is not running',
                          hintStyle: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'Courier New',
                            color: Color(0xFFA0A0A0),
                          ),
                        ),
                        onSubmitted: (value) {
                          if (value.isNotEmpty && isRunning) {
                            widget.dartRunnerService.sendInput(value);
                            _inputController.clear();
                            _inputFocusNode.requestFocus();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    RetroButton(
                      onPressed: isRunning
                          ? () {
                              final value = _inputController.text;
                              if (value.isNotEmpty) {
                                widget.dartRunnerService.sendInput(value);
                                _inputController.clear();
                                _inputFocusNode.requestFocus();
                              }
                            }
                          : null,
                      child: const Text('Send'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
