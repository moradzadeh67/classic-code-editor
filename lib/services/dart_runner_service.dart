import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';

/// A service responsible for executing Dart code via the Dart SDK CLI process,
/// capturing stdout/stderr streams, and managing process lifecycle (execution,
/// cancellation, cleanup).
class DartRunnerService extends ChangeNotifier {
  Process? _process;
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  bool _isRunning = false;
  int? _exitCode;

  Stream<String> get outputStream => _outputController.stream;
  bool get isRunning => _isRunning;
  int? get exitCode => _exitCode;

  /// Executes the provided [dartCode] by writing it to a temporary file and
  /// running `dart run <temp_file>` in a separate process.
  Future<void> runCode(String dartCode) async {
    debugPrint('=== DartRunnerService.runCode called ===');
    debugPrint('Code length: ${dartCode.length}');

    if (_isRunning) {
      debugPrint('Already running, returning');
      return;
    }

    _isRunning = true;
    _exitCode = null;
    notifyListeners();

    Directory? tempDir;
    try {
      tempDir = Directory.systemTemp.createTempSync('borland_dart_');
      final tempFile = File('${tempDir.path}/main.dart');
      await tempFile.writeAsString(dartCode);
      debugPrint('Temp file created: ${tempFile.path}');

      String dartExecutable = 'dart';
      try {
        final whichResult = await Process.run('which', ['dart']);
        if (whichResult.exitCode == 0) {
          dartExecutable = (whichResult.stdout as String).trim();
          debugPrint('Dart executable found: $dartExecutable');
        }
      } catch (e) {
        debugPrint('Error finding dart: $e');
      }

      debugPrint('Starting process: $dartExecutable run ${tempFile.path}');

      _process = await Process.start(dartExecutable, [
        'run',
        tempFile.path,
      ], workingDirectory: tempDir.path);

      debugPrint('Process started, PID: ${_process!.pid}');

      _process!.stdout.listen((data) {
        final output = String.fromCharCodes(data);
        debugPrint('STDOUT: $output');
        _outputController.add(output);
      });

      _process!.stderr.listen((data) {
        final output = String.fromCharCodes(data);
        debugPrint('STDERR: $output');
        _outputController.add(output);
      });

      _exitCode = await _process!.exitCode;
      debugPrint('Process exited with code: $_exitCode');
      _outputController.add('\n[Process exited with code: $_exitCode]\n');
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
