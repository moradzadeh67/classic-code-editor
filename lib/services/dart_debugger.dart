import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'base_debugger.dart';
import '../models/debugger_models.dart';

class DartDebugger extends BaseDebugger {
  Process? _process;
  String? _vmServiceUri;

  @override
  Future<void> startDebugging(String filePath) async {
    if (state != DebugState.inactive) return;

    // Start Dart VM in debug mode
    try {
      _process = await Process.start('dart', [
        '--enable-vm-service=0',
        '--pause-isolates-on-start',
        filePath,
      ]);

      state = DebugState.running;
      notifyListeners();

      // Listen for VM service URI in stdout
      _process!.stdout.listen((data) {
        final output = String.fromCharCodes(data);
        debugPrint('[DartDebugger] $output');

        // Look for VM service URI pattern
        final uriMatch = RegExp(r'Observatory listening on (http://\S+)')
            .firstMatch(output);
        if (uriMatch != null) {
          _vmServiceUri = uriMatch.group(1);
          debugPrint('[DartDebugger] VM Service: $_vmServiceUri');
        }
      });

      _process!.stderr.listen((data) {
        debugPrint('[DartDebugger Error] ${String.fromCharCodes(data)}');
      });

      _process!.exitCode.then((code) {
        state = DebugState.stopped;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[DartDebugger] Error starting debug: $e');
      state = DebugState.stopped;
      notifyListeners();
    }
  }

  @override
  Future<void> stopDebugging() async {
    _process?.kill();
    _process = null;
    _vmServiceUri = null;
    state = DebugState.inactive;
    variables.clear();
    callStack.clear();
    notifyListeners();
  }

  @override
  Future<void> stepOver() async {
    debugPrint('[DartDebugger] Step Over - VM service integration needed');
  }

  @override
  Future<void> stepInto() async {
    debugPrint('[DartDebugger] Step Into - VM service integration needed');
  }

  @override
  Future<void> stepOut() async {
    debugPrint('[DartDebugger] Step Out - VM service integration needed');
  }

  @override
  Future<void> continueExecution() async {
    state = DebugState.running;
    notifyListeners();
  }
}
