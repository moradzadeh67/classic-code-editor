import 'dart:io';

/// Gate that decides whether a debugger may spawn a *real* runtime process.
///
/// `flutter test` always runs with the `FLUTTER_TEST` environment variable set,
/// and every debugger short-circuits under it so the unit suite never launches
/// `dart`, `python` or `clang`/`lldb`. Opt-in end-to-end tests that need to
/// exercise the real attach/pause chain (which no unit test can) flip
/// [allowRealProcesses] on - or simply run with `BORLAND_REAL_VM_TEST=1`, which
/// sets it at start-up.
///
/// Production code never touches either switch, so the short-circuit remains in
/// force for every normal run.
class DebuggerEnvironment {
  DebuggerEnvironment._();

  /// When true, debuggers spawn real processes even under `FLUTTER_TEST`.
  ///
  /// Defaults to true only when the process was started with
  /// `BORLAND_REAL_VM_TEST=1`, so a plain `flutter test` keeps the guard.
  static bool allowRealProcesses =
      Platform.environment['BORLAND_REAL_VM_TEST'] == '1';

  /// Whether a debugger must skip spawning a real runtime process.
  ///
  /// True for the unit suite (real processes forbidden) and false in the app
  /// and in opt-in end-to-end tests.
  static bool get shouldShortCircuit =>
      !allowRealProcesses && Platform.environment.containsKey('FLUTTER_TEST');
}
