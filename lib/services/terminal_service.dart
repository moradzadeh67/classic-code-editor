import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

class TerminalService extends ChangeNotifier {
  Process? _process;
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  bool _isRunning = false;
  String _currentDirectory;
  final List<String> _commandHistory = [];
  int _historyIndex = -1;

  TerminalService() : _currentDirectory = Directory.current.path;

  Stream<String> get outputStream => _outputController.stream;
  bool get isRunning => _isRunning;
  String get currentDirectory => _currentDirectory;
  List<String> get commandHistory => _commandHistory;

  Future<void> executeCommand(String command) async {
    if (_isRunning) return;
    if (command.trim().isEmpty) return;

    if (!Directory(_currentDirectory).existsSync()) {
      final current = Directory.current;
      if (current.existsSync()) {
        _currentDirectory = current.path;
      } else {
        _currentDirectory =
            Platform.environment['HOME'] ?? Directory.systemTemp.path;
      }
    }

    _commandHistory.add(command);
    _historyIndex = _commandHistory.length;
    _isRunning = true;
    notifyListeners();

    _outputController.add('\n\$ $command\n');

    try {
      // Handle built-in commands
      if (command.trim() == 'clear' || command.trim() == 'cls') {
        _outputController.add('\x1B[2J\x1B[H'); // Clear screen ANSI code
        _isRunning = false;
        notifyListeners();
        return;
      }

      if (command.startsWith('cd ')) {
        final path = command.substring(3).trim();
        final newDir = Directory(
          path.startsWith('/') ? path : '$_currentDirectory/$path',
        );
        if (await newDir.exists()) {
          _currentDirectory = newDir.absolute.path;
          _outputController.add('Changed directory to: $_currentDirectory\n');
        } else {
          _outputController.add('Directory not found: $path\n');
        }
        _isRunning = false;
        notifyListeners();
        return;
      }

      // Execute external command via bash on macOS/Linux or cmd on Windows
      final executable = Platform.isWindows ? 'cmd.exe' : 'bash';
      final arguments = Platform.isWindows
          ? ['/c', command]
          : ['-l', '-c', command];

      _process = await Process.start(
        executable,
        arguments,
        workingDirectory: _currentDirectory,
      );

      _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((output) {
            _outputController.add(output);
          });

      _process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((output) {
            _outputController.add(output);
          });

      await _process!.exitCode;
    } catch (e) {
      _outputController.add('Error: $e\n');
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  String getPreviousCommand() {
    if (_historyIndex > 0) {
      _historyIndex--;
      return _commandHistory[_historyIndex];
    }
    return '';
  }

  String getNextCommand() {
    if (_historyIndex < _commandHistory.length - 1) {
      _historyIndex++;
      return _commandHistory[_historyIndex];
    }
    return '';
  }

  @override
  void dispose() {
    _outputController.close();
    super.dispose();
  }
}
