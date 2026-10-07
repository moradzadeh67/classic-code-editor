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
  StreamSubscription<String>? _subscription;

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
    super.dispose();
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
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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
                  final isError =
                      line.contains('[Error') ||
                      line.contains('stderr') ||
                      line.contains('Error:');
                  return Text(
                    line,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Courier New',
                      color: isError
                          ? ThemeService.instance.uiColors['error']
                          : const Color(0xFF1F7D00),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
