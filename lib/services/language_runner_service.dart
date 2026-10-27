import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/language_config.dart';
import 'file_service.dart';
import 'tool_path_resolver.dart';

/// A unified service responsible for executing code in multiple languages
/// (Dart, Python, C, C++) by determining the configuration based on file extension,
/// compiling if necessary, capturing stdout/stderr streams, and managing process lifecycle.
class LanguageRunnerService extends ChangeNotifier {
  Process? _process;
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();

  /// Fires when the Console must drop everything it is showing. Kept apart from
  /// [outputStream] so a listener can never mistake it for program output.
  final StreamController<void> _clearController =
      StreamController<void>.broadcast();
  bool _isRunning = false;
  int? _exitCode;
  String _preferredLanguage = 'Auto';

  Stream<String> get outputStream => _outputController.stream;

  /// Emits whenever the Console should be emptied (before a new run starts).
  Stream<void> get clearStream => _clearController.stream;
  bool get isRunning => _isRunning;
  int? get exitCode => _exitCode;

  /// The language currently forced from the toolbar dropdown, or `'Auto'`.
  String get preferredLanguage => _preferredLanguage;

  void setPreferredLanguage(String language) {
    _preferredLanguage = language;
    notifyListeners();
  }

  /// Pushes a single line of externally produced text (for example a debugger
  /// tracing notice) onto the shared [outputStream] so the Console panel shows
  /// it alongside normal program output.
  ///
  /// This is an additive hook: the runner keeps owning its process, while other
  /// services can contribute to the same console stream without touching it.
  void emitOutput(String line) {
    if (!_outputController.isClosed) {
      _outputController.add(line);
    }
  }

  /// Empties the Console.
  ///
  /// Every run calls this first, so the previous program's output — and the blue
  /// `[Running C++ ...]` banner that belongs to it — can never sit above the new
  /// program's output, even when the language changed in between.
  void clearConsole() {
    if (!_clearController.isClosed) {
      _clearController.add(null);
    }
  }

  Future<void> runActiveFile(FileService fileService) async {
    final tab = fileService.activeTab;
    final content = tab?.content ?? fileService.fileContent;
    if (content.isNotEmpty) {
      // The tab's own choice, not an app-wide one: another tab's dropdown
      // value can never be applied to this buffer.
      await runCode(
        tab?.filePath ?? fileService.currentFilePath,
        content,
        preferredLanguage: tab?.languageOverride ?? 'Auto',
      );
    }
  }

  LanguageResolution _resolve(
    String? filePath,
    String content, {
    String? preferredLanguage,
  }) => resolve(
    filePath,
    content,
    preferredLanguage: preferredLanguage ?? _preferredLanguage,
  );

  /// Resolves the [LanguageConfig] for [filePath]/[content].
  ///
  /// When [preferredLanguage] is not `'Auto'` the manual dropdown selection
  /// wins; otherwise the file extension is consulted and, for unsaved buffers,
  /// the content is sniffed. Exposed statically so the debugger dispatcher can
  /// reuse the exact same rules and Run/Debug never disagree about a file.
  static LanguageConfig resolveLanguage(
    String? filePath,
    String content, {
    String preferredLanguage = 'Auto',
  }) => resolve(
    filePath,
    content,
    preferredLanguage: preferredLanguage,
  ).language;

  /// The one resolver: language **and** mismatch reason.
  ///
  /// The runner, `MultiLanguageHighlighter.createController` and
  /// `PanelLayout._detectLanguageExt` all call this, so Run/Debug, the colors
  /// and the logo can never disagree about a buffer.
  static LanguageResolution resolve(
    String? filePath,
    String content, {
    String preferredLanguage = 'Auto',
  }) => LanguageConfig.resolve(
    filePath,
    content,
    preferredLanguage: preferredLanguage,
  );

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
    // Same lookup the language servers use: absolute candidates, the user's
    // login-shell PATH, then the common install locations. An app opened from
    // Finder never inherits the shell PATH, so a bare `which` misses `dart`.
    final resolved = await ToolPathResolver.instance.find(name);
    if (resolved != null) return resolved;
    return name;
  }

  /// The PATH every child process gets, so `dart`, `clang` and `python3`
  /// resolve as they do in the user's terminal.
  Future<Map<String, String>> _childEnvironment() =>
      ToolPathResolver.instance.processEnvironment();

  /// Executes code for the given [filePath] and [content].
  /// Supports Dart, Python, C, and C++.
  Future<void> runCode(
    String? filePath,
    String content, {
    String? preferredLanguage,
  }) async {
    debugPrint('=== LanguageRunnerService.runCode called ===');
    debugPrint('File path: $filePath, content length: ${content.length}');

    if (_isRunning) {
      debugPrint('Already running, returning');
      return;
    }

    // A new run starts from a clean Console (see [clearConsole]).
    clearConsole();

    // A buffer whose content clearly belongs to another language is never
    // compiled or run: one line instead of a compiler shouting at foreign text.
    final resolution = _resolve(
      filePath,
      content,
      preferredLanguage: preferredLanguage,
    );
    if (resolution.hasMismatch) {
      _isRunning = false;
      _exitCode = null;
      notifyListeners();
      _outputController.add(
        resolution.mismatchMessage(
          fileName: filePath?.split('/').last ?? filePath,
        ),
      );
      return;
    }

    _isRunning = true;
    _exitCode = null;
    notifyListeners();

    final config = resolution.language;
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
        case '.s':
          await _runAsm(tempDir, content);
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
    ], workingDirectory: tempDir.path, environment: await _childEnvironment());

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
      final check = await Process.run(
        pythonExec,
        ['--version'],
        environment: await _childEnvironment(),
      );
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
    ], workingDirectory: runWorkDir, environment: await _childEnvironment());

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
      ], workingDirectory: tempDir.path, environment: await _childEnvironment());

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
      environment: await _childEnvironment(),
      includeParentEnvironment: true,
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
      ], workingDirectory: tempDir.path, environment: await _childEnvironment());

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
      environment: await _childEnvironment(),
      includeParentEnvironment: true,
    );

    await _listenToProcess(_process!);
  }

  Future<bool> _isAppleSilicon() async {
    if (!Platform.isMacOS) return false;
    try {
      final res = await Process.run('uname', ['-m']);
      return res.stdout.toString().trim() == 'arm64';
    } catch (_) {
      return false;
    }
  }

  Future<void> _runAsm(Directory tempDir, String content) async {
    if (!await _isAppleSilicon()) {
      _outputController.add(
        '[ARM64 Assembly requires Apple Silicon macOS and clang.]\n',
      );
      return;
    }

    final clangExec = await _findExecutable('clang');
    if (clangExec.isEmpty) {
      _outputController.add(
        '[ARM64 Assembly requires clang. clang not found in PATH.]\n',
      );
      return;
    }

    final sourceFile = File('${tempDir.path}/main.s');
    await sourceFile.writeAsString(content);
    final execFile = '${tempDir.path}/main_asm_exec';

    _outputController.add('[Compiling ARM64 assembly with clang...]\n');

    try {
      final compileProcess = await Process.run(clangExec, [
        '-arch',
        'arm64',
        '-g',
        '-o',
        execFile,
        sourceFile.path,
      ], workingDirectory: tempDir.path, environment: await _childEnvironment());

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
      _outputController.add('\n[Error: clang compiler failed ($e)]\n');
      return;
    }

    _outputController.add('[Running ARM64 assembly executable...]\n');

    _process = await Process.start(
      execFile,
      [],
      workingDirectory: tempDir.path,
      environment: await _childEnvironment(),
      includeParentEnvironment: true,
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
    _clearController.close();
    super.dispose();
  }
}
