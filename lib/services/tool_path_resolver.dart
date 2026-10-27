// The optional test seams are nullable providers assigned in the initializer
// list on purpose.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

/// Result of looking one tool up: the path (or `null`) plus every location
/// that was tried, in order.
///
/// The tried list is what the status-bar tooltip and the Console hint show when
/// a server cannot be found, so a user can see *why* a build launched from
/// Finder behaves differently from one launched from a terminal.
class ToolLookup {
  const ToolLookup(this.path, this.tried);

  /// Absolute path of the executable, or `null` when it was not found.
  final String? path;

  /// Human-readable descriptions of the locations that were checked.
  final List<String> tried;

  bool get found => path != null;
}

/// Finds external command-line tools (`dart`, `clangd`, `pyright-langserver`,
/// `clang`, `python3`, …) the way the user's terminal would.
///
/// macOS starts an app opened from Finder/`open` with launchd's minimal
/// environment (`PATH=/usr/bin:/bin:/usr/sbin:/sbin`), not the shell's `PATH`.
/// A tool installed under `/opt/homebrew/bin` or inside a Flutter SDK is then
/// invisible even though it works in Terminal. The resolver therefore looks in
/// three places, in this order:
///
/// 1. the absolute candidates the caller already knows (handled by callers),
/// 2. the user's **login shell** (`/bin/zsh -lc 'command -v <name>'`), asked at
///    most once per tool, with a 2 s timeout and the answer cached — a login
///    script that hangs can never freeze the app,
/// 3. common install locations, including `~/.pub-cache/bin` and the Dart SDK
///    shipped with Flutter.
///
/// Every lookup is asynchronous and cached; nothing here blocks the UI thread.
class ToolPathResolver {
  ToolPathResolver({
    Future<String?> Function(String name)? loginShellWhich,
    Future<String?> Function()? loginShellPath,
    bool Function(String path)? fileExists,
    Map<String, String>? environment,
    String? home,
  }) : _loginShellWhich = loginShellWhich,
       _loginShellPath = loginShellPath,
       _fileExists = fileExists ?? _defaultFileExists,
       _environment = environment,
       _home = home;

  /// The resolver the app uses; tests construct their own with fakes.
  static final ToolPathResolver instance = ToolPathResolver();

  /// Longest a lookup may wait for the login shell.
  static const Duration shellTimeout = Duration(seconds: 2);

  final Future<String?> Function(String name)? _loginShellWhich;
  final Future<String?> Function()? _loginShellPath;
  final bool Function(String path) _fileExists;
  final Map<String, String>? _environment;
  final String? _home;

  final Map<String, Future<String?>> _whichCache = {};
  Future<String?>? _loginPathCache;

  static bool _defaultFileExists(String path) => File(path).existsSync();

  Map<String, String> get _env => _environment ?? Platform.environment;

  String? get _homeDir => _home ?? _env['HOME'];

  /// Looks [name] up (login shell first, then the common locations).
  Future<ToolLookup> lookup(String name) async {
    final tried = <String>[];

    // The Dart server must match the SDK the user builds with, so the Dart
    // that sits next to the `flutter` on their login-shell PATH wins. Both
    // shell lookups are started together (each may take a second) so the
    // first completion is not waiting for two login shells in a row.
    final flutterLookup = name == 'dart' ? _which('flutter') : null;
    final nameLookup = _which(name);
    if (flutterLookup != null) {
      final flutter = await flutterLookup;
      if (flutter != null) {
        final dart = '${_dirname(flutter)}/dart';
        tried.add('$dart (next to $flutter)');
        if (_fileExists(dart)) return ToolLookup(dart, tried);
      }
    }

    final loginHit = await nameLookup;
    tried.add('login-shell PATH (`command -v $name`)');
    if (loginHit != null) return ToolLookup(loginHit, tried);

    for (final directory in await searchDirectories()) {
      final path = '$directory/$name';
      tried.add(path);
      if (_fileExists(path)) return ToolLookup(path, tried);
    }
    return ToolLookup(null, tried);
  }

  /// [lookup] reduced to the path, or `null` when [name] was not found.
  Future<String?> find(String name) async => (await lookup(name)).path;

  /// Directories searched after the login shell, most specific first.
  Future<List<String>> searchDirectories() async {
    final home = _homeDir;
    final directories = <String>[
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
      if (home != null && home.isNotEmpty) ...<String>[
        '$home/.pub-cache/bin',
        '$home/flutter/bin/cache/dart-sdk/bin',
      ],
    ];
    // Every directory on the login-shell PATH is a legitimate install place
    // (the user's Flutter SDK, ~/bin, a version manager, …).
    final loginPath = await this.loginPath();
    if (loginPath != null) {
      for (final directory in loginPath.split(':')) {
        if (directory.isEmpty) continue;
        if (!directories.contains(directory)) directories.add(directory);
      }
    }
    return directories;
  }

  /// The user's login-shell `PATH`, resolved at most once (2 s timeout).
  Future<String?> loginPath() {
    return _loginPathCache ??= () async {
      final provider = _loginShellPath;
      if (provider != null) return _clean(await provider());
      return _runShell(r'printf %s "$PATH"', validateAbsolute: false);
    }();
  }

  /// The environment handed to child processes (language servers, `dart run`,
  /// compilers, debuggers): the login-shell PATH first, then the app's own
  /// PATH, then the common tool directories — de-duplicated, order preserved.
  ///
  /// Without this an app started from Finder cannot find `dart`, `clang` or
  /// `python3` even though the same command works in Terminal.
  Future<Map<String, String>> processEnvironment() async {
    final directories = <String>[];
    void addAll(String? path) {
      if (path == null || path.isEmpty) return;
      for (final directory in path.split(':')) {
        if (directory.isEmpty) continue;
        if (!directories.contains(directory)) directories.add(directory);
      }
    }

    addAll(await loginPath());
    addAll(_env['PATH']);
    for (final directory in await searchDirectories()) {
      addAll(directory);
    }
    return <String, String>{'PATH': directories.join(':')};
  }

  /// `command -v <name>` through the login shell, cached (including misses).
  Future<String?> _which(String name) {
    return _whichCache.putIfAbsent(name, () async {
      final provider = _loginShellWhich;
      if (provider != null) return _cleanExecutable(await provider(name));
      return _runShell('command -v $name');
    });
  }

  /// Runs [command] through the user's shell, bounded by [shellTimeout].
  ///
  /// `zsh -lic` first (interactive login: the shell Terminal gives the user, so
  /// `~/.zshrc` — where most machines put `PATH` — is sourced), then `zsh -lc`
  /// for setups whose rc files refuse to run without a terminal. Both answers
  /// are cached by the caller. Never throws; a timeout is just a miss.
  Future<String?> _runShell(
    String command, {
    bool validateAbsolute = true,
  }) async {
    for (final flags in const <String>['-lic', '-lc']) {
      try {
        final result = await Process.run('/bin/zsh', <String>[
          flags,
          command,
        ]).timeout(shellTimeout);
        if (result.exitCode != 0) continue;
        final stdout = result.stdout;
        final value = _clean(stdout is String ? stdout : null);
        if (value == null) continue;
        if (!validateAbsolute) return value;
        final executable = _lastAbsoluteLine(stdout as String?);
        if (executable != null) return executable;
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// The last line of a shell answer that is a plausible absolute path.
  ///
  /// Interactive shells may print a banner before the real answer, so the last
  /// matching line (rather than the first) is the safe choice.
  static String? _lastAbsoluteLine(String? value) {
    if (value == null) return null;
    for (final line in value.split('\n').reversed) {
      final trimmed = line.trim();
      if (trimmed.startsWith('/') && !trimmed.contains(' ')) return trimmed;
    }
    return null;
  }

  /// Trims a shell answer to its last non-empty line (`null` when empty).
  static String? _clean(String? value) {
    if (value == null) return null;
    for (final line in value.split('\n').reversed) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// Like [_clean], but only accepts an absolute path: `command -v` can also
  /// answer with an alias, a function or a builtin, none of which can be
  /// spawned.
  static String? _cleanExecutable(String? value) {
    final line = _clean(value);
    if (line == null || !line.startsWith('/')) return null;
    return line;
  }

  static String _dirname(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? path : path.substring(0, index);
  }
}
