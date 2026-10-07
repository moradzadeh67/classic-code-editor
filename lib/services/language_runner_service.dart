import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/language_config.dart';
import 'file_service.dart';

/// A unified service responsible for executing code in multiple languages
/// (Dart, Python, C, C++) by determining the configuration based on file extension,
/// compiling if necessary, capturing stdout/stderr streams, and managing process lifecycle.
class LanguageRunnerService extends ChangeNotifier {
  Process? _process;
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  bool _isRunning = false;
  int? _exitCode;
  String _preferredLanguage = 'Auto';

  Stream<String> get outputStream => _outputController.stream;
  bool get isRunning => _isRunning;
  int? get exitCode => _exitCode;

  void setPreferredLanguage(String language) {
    _preferredLanguage = language;
    notifyListeners();
  }

  Future<void> runActiveFile(FileService fileService) async {
    final path = fileService.currentFilePath;
    final content = fileService.activeTab?.content ?? fileService.fileContent;
    if (content.isNotEmpty) {
      await runCode(path, content);
    }
  }

  LanguageConfig _resolveLanguage(String? filePath, String content) {
    if (_preferredLanguage != 'Auto') {
      switch (_preferredLanguage) {
        case 'Dart':
          return LanguageConfig.fromExtension('test.dart');
        case 'Python':
          return LanguageConfig.fromExtension('test.py');
        case 'C':
          return LanguageConfig.fromExtension('test.c');
        case 'C++':
          return LanguageConfig.fromExtension('test.cpp');
        default:
          return LanguageConfig.fromExtension(filePath);
      }
    }

    // Check extension if filePath exists
    if (filePath != null && filePath.contains('.')) {
      final ext = filePath.toLowerCase().split('.').last;
      if (ext == 'dart' ||
          ext == 'c' ||
          ext == 'cpp' ||
          ext == 'cc' ||
          ext == 'cxx' ||
          ext == 'py') {
        return LanguageConfig.fromExtension(filePath);
      }
    }

    // Automatic content-based detection for unsaved tabs ("Untitled *")
    final trimmed = content.trim();
    if (trimmed.contains('#include') ||
        trimmed.contains('std::') ||
        trimmed.contains('cout') ||
        trimmed.contains('cin')) {
      return LanguageConfig.fromExtension('test.cpp');
    }
    if (trimmed.contains('#include <stdio.h>') || trimmed.contains('printf(')) {
      return LanguageConfig.fromExtension('test.c');
    }
    if (trimmed.contains('def ') ||
        trimmed.contains('import sys') ||
        trimmed.contains('import os') ||
        (trimmed.contains('print(') && !trimmed.contains(';'))) {
      return LanguageConfig.fromExtension('test.py');
    }
    if (trimmed.contains('void main(') || trimmed.contains('import \'dart:')) {
      return LanguageConfig.fromExtension('test.dart');
    }

    return LanguageConfig.fromExtension(filePath);
  }

  /// Sends user input to stdin of the active process.
  void sendInput(String input) {
    if (_process != null && _isRunning) {
      try {
        _process!.stdin.writeln(input);
        _outputController.add('> $input\n');
      } catch (e) {
        debugPrint('Error sending input to stdin: $e');
      }
    }
  }

  Future<String> _findExecutable(String name) async {
    try {
      final result = await Process.run('which', [name]);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty) return path;
      }
    } catch (e) {
      debugPrint('Error finding executable $name: $e');
    }
    return name;
  }

  /// Executes code for the given [filePath] and [content].
  /// Supports Dart, Python, C, and C++.
  Future<void> runCode(String? filePath, String content) async {
    debugPrint('=== LanguageRunnerService.runCode called ===');
    debugPrint('File path: $filePath, content length: ${content.length}');

    if (_isRunning) {
      debugPrint('Already running, returning');
      return;
    }

    _isRunning = true;
    _exitCode = null;
    notifyListeners();

    final config = _resolveLanguage(filePath, content);
    debugPrint('Using language config: ${config.displayName}');

    Directory? tempDir;
    try {
      tempDir = Directory.systemTemp.createTempSync('borland_runner_');

      switch (config.extension) {
        case '.dart':
          await _runDart(tempDir, content);
          break;
        case '.py':
          await _runPython(tempDir, filePath, content);
          break;
        case '.c':
          await _runC(tempDir, content);
          break;
        case '.cpp':
          await _runCpp(tempDir, content);
          break;
        default:
          await _runDart(tempDir, content);
          break;
      }
    } catch (e) {
      debugPrint('Error in runCode: $e');
      _outputController.add('\n[Error: $e]\n');
    } finally {
      _isRunning = false;
      _process = null;
      notifyListeners();

      try {
        if (tempDir != null && tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  }

  Future<void> _runDart(Directory tempDir, String content) async {
    final tempFile = File('${tempDir.path}/main.dart');
    await tempFile.writeAsString(content);

    final dartExec = await _findExecutable('dart');
    _outputController.add('[Running Dart...]\n');

    _process = await Process.start(dartExec, [
      'run',
      tempFile.path,
    ], workingDirectory: tempDir.path);

    await _listenToProcess(_process!);
  }

  Future<void> _runPython(
    Directory tempDir,
    String? filePath,
    String content,
  ) async {
    final pythonExec = await _findExecutable('python3');

    // Verify python3 exists
    try {
      final check = await Process.run(pythonExec, ['--version']);
      if (check.exitCode != 0) {
        _outputController.add(
          '\n[Error: python3 not found. Please ensure Python 3 is installed and in your PATH.]\n',
        );
        return;
      }
    } catch (e) {
      _outputController.add(
        '\n[Error: python3 command not found ($e). Please install Python 3.]\n',
      );
      return;
    }

    String scriptPath;
    final String runWorkDir;
    if (filePath != null && File(filePath).existsSync()) {
      scriptPath = filePath;
      runWorkDir = File(filePath).parent.path;
    } else {
      final tempFile = File('${tempDir.path}/main.py');
      await tempFile.writeAsString(content);
      scriptPath = tempFile.path;
      runWorkDir = tempDir.path;
    }

    _outputController.add('[Running Python 3...]\n');

    _process = await Process.start(pythonExec, [
      scriptPath,
    ], workingDirectory: runWorkDir);

    await _listenToProcess(_process!);
  }

  Future<void> _runC(Directory tempDir, String content) async {
    final clangExec = await _findExecutable('clang');

    final sourceFile = File('${tempDir.path}/main.c');
    await sourceFile.writeAsString(content);
    final execFile = '${tempDir.path}/main_c_exec';

    _outputController.add('[Compiling C code with clang...]\n');

    try {
      final compileProcess = await Process.run(clangExec, [
        '-o',
        execFile,
        sourceFile.path,
      ], workingDirectory: tempDir.path);

      if (compileProcess.stdout.toString().isNotEmpty) {
        _outputController.add(compileProcess.stdout.toString());
      }
      if (compileProcess.stderr.toString().isNotEmpty) {
        _outputController.add(compileProcess.stderr.toString());
      }

      if (compileProcess.exitCode != 0) {
        _outputController.add(
          '\n[Compilation failed with code ${compileProcess.exitCode}]\n',
        );
        return;
      }
    } catch (e) {
      _outputController.add(
        '\n[Error: clang compiler not found ($e). Please install clang/GCC.]\n',
      );
      return;
    }

    _outputController.add('[Running C executable...]\n');

    _process = await Process.start(
      execFile,
      [],
      workingDirectory: tempDir.path,
    );

    await _listenToProcess(_process!);
  }

  Future<void> _runCpp(Directory tempDir, String content) async {
    final clangCppExec = await _findExecutable('clang++');

    final sourceFile = File('${tempDir.path}/main.cpp');
    await sourceFile.writeAsString(content);
    final execFile = '${tempDir.path}/main_cpp_exec';

    _outputController.add('[Compiling C++ code with clang++...]\n');

    try {
      final compileProcess = await Process.run(clangCppExec, [
        '-std=c++17',
        '-o',
        execFile,
        sourceFile.path,
      ], workingDirectory: tempDir.path);

      if (compileProcess.stdout.toString().isNotEmpty) {
        _outputController.add(compileProcess.stdout.toString());
      }
      if (compileProcess.stderr.toString().isNotEmpty) {
        _outputController.add(compileProcess.stderr.toString());
      }

      if (compileProcess.exitCode != 0) {
        _outputController.add(
          '\n[Compilation failed with code ${compileProcess.exitCode}]\n',
        );
        return;
      }
    } catch (e) {
      _outputController.add(
        '\n[Error: clang++ compiler not found ($e). Please install clang/GCC.]\n',
      );
      return;
    }

    _outputController.add('[Running C++ executable...]\n');

    _process = await Process.start(
      execFile,
      [],
      workingDirectory: tempDir.path,
    );

    await _listenToProcess(_process!);
  }

  Future<int> _listenToProcess(Process process) async {
    process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((
      output,
    ) {
      _outputController.add(output);
    });

    process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((
      output,
    ) {
      _outputController.add(output);
    });

    final code = await process.exitCode;
    _exitCode = code;
    _outputController.add('\n[Process exited with code: $_exitCode]\n');
    _isRunning = false;
    notifyListeners();
    return code;
  }

  /// Stops the currently running execution process if active.
  void stopExecution() {
    if (_process != null && _isRunning) {
      _process!.kill();
      _isRunning = false;
      _outputController.add('\n[Process stopped by user]\n');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopExecution();
    _outputController.close();
    super.dispose();
  }
}
