import '../models/language_config.dart';
import 'base_debugger.dart';
import 'c_debugger.dart';
import 'dart_debugger.dart';
import 'language_runner_service.dart';
import 'python_debugger.dart';

/// Maps a [LanguageConfig] to the [BaseDebugger] that knows how to drive it.
///
/// The IDE supports four languages (Dart, Python, C, C++). Instead of teaching
/// the shell about each runtime, the shell asks the factory for the debugger
/// responsible for the active tab. Instances are created once and reused, so
/// breakpoints set for a file survive tab and language switches.
class DebuggerFactory {
  DebuggerFactory({
    DartDebugger? dartDebugger,
    PythonDebugger? pythonDebugger,
    CDebugger? cDebugger,
  }) : dartDebugger = dartDebugger ?? DartDebugger(),
       pythonDebugger = pythonDebugger ?? PythonDebugger(),
       cDebugger = cDebugger ?? CDebugger();

  final DartDebugger dartDebugger;
  final PythonDebugger pythonDebugger;
  final CDebugger cDebugger;

  /// The debugger that handles [config]'s language.
  BaseDebugger forLanguage(LanguageConfig config) {
    switch (config.extension) {
      case '.py':
        return pythonDebugger;
      case '.c':
      case '.cpp':
      case '.cc':
      case '.cxx':
        return cDebugger;
      default:
        return dartDebugger;
    }
  }

  /// Resolves the language from [filePath]/[content] - reusing the runner's own
  /// sniffing so Run and Debug never disagree - and returns its debugger.
  BaseDebugger forCode(
    String? filePath,
    String content, {
    String preferredLanguage = 'Auto',
  }) => forLanguage(
    LanguageRunnerService.resolveLanguage(
      filePath,
      content,
      preferredLanguage: preferredLanguage,
    ),
  );

  /// Every debugger owned by this factory, for iteration and teardown.
  List<BaseDebugger> get all => <BaseDebugger>[
    dartDebugger,
    pythonDebugger,
    cDebugger,
  ];

  /// Disposes every debugger, closing their output streams.
  void dispose() {
    for (final debugger in all) {
      debugger.dispose();
    }
  }
}
