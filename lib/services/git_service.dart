import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/git_models.dart';
import 'tool_path_resolver.dart';

/// A cancel handle for one or more Git commands.
///
/// The service hands the same token to every child process it starts, so a
/// caller can stop a long `status`/`repoInfo` sequence with one [cancel] call.
class GitCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Marks the token cancelled and kills every process listening to it.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  /// Registers [listener] to run on [cancel].
  ///
  /// A token that is already cancelled calls [listener] immediately.
  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// Removes a listener registered with [addListener].
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}

/// The process-runner seam used by [GitService].
///
/// Implementations receive an executable and an argument **list**; no command
/// is ever passed through a shell. Tests substitute a fake to inspect the
/// exact arguments, environment, timeout and cancellation token.
abstract class GitProcessRunner {
  /// Runs [executable] with [arguments] and captures its output.
  Future<GitResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    GitCancelToken? cancel,
  });
}

/// The real runner: [Process.start] with an argument list (never a shell),
/// output capped at 5 MB per stream, plus timeout and cancellation support.
class SystemGitProcessRunner implements GitProcessRunner {
  const SystemGitProcessRunner();

  /// Maximum bytes kept from each of stdout and stderr.
  static const int maxCaptureBytes = 5 * 1024 * 1024;

  @override
  Future<GitResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    GitCancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      return const GitResult(-1, '', 'Cancelled', false, true);
    }

    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: false,
      );
    } on ProcessException catch (error) {
      return GitResult(-1, '', error.message, false, false);
    } catch (error) {
      return GitResult(-1, '', '$error', false, false);
    }

    var timedOut = false;
    var cancelled = false;
    var finished = false;
    Timer? timeoutTimer;
    Timer? killTimer;

    void terminate() {
      if (finished) return;
      process.kill(ProcessSignal.sigterm);
      killTimer ??= Timer(const Duration(seconds: 1), () {
        if (!finished) process.kill(ProcessSignal.sigkill);
      });
    }

    void onCancel() {
      if (finished) return;
      cancelled = true;
      terminate();
    }

    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        if (finished) return;
        timedOut = true;
        terminate();
      });
    }
    cancel?.addListener(onCancel);

    try {
      final streams = await Future.wait(<Future<String>>[
        _capture(process.stdout),
        _capture(process.stderr),
      ]);
      final exitCode = await process.exitCode;
      finished = true;
      return GitResult(exitCode, streams[0], streams[1], timedOut, cancelled);
    } catch (error) {
      finished = true;
      process.kill(ProcessSignal.sigkill);
      return GitResult(-1, '', '$error', timedOut, cancelled);
    } finally {
      timeoutTimer?.cancel();
      killTimer?.cancel();
      cancel?.removeListener(onCancel);
    }
  }

  /// Reads [stream] as UTF-8, keeping at most [maxCaptureBytes].
  ///
  /// The stream keeps draining after the cap so the child can exit instead of
  /// blocking on a full pipe. Invalid UTF-8 bytes become the replacement
  /// character rather than throwing.
  Future<String> _capture(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    var captured = 0;
    await for (final chunk in stream) {
      if (captured >= maxCaptureBytes) continue;
      final room = maxCaptureBytes - captured;
      if (chunk.length <= room) {
        bytes.add(chunk);
        captured += chunk.length;
      } else {
        bytes.add(chunk.sublist(0, room));
        captured = maxCaptureBytes;
      }
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }
}

/// Read-only access to a Git repository.
///
/// Every method takes a directory path, so nothing here is coupled to the
/// File Explorer or any widget. Commands run with an argument list (never a
/// shell), a resolved login-shell `PATH`, `GIT_TERMINAL_PROMPT=0`,
/// `GIT_OPTIONAL_LOCKS=0`, `LC_ALL=C` and `-c core.quotepath=false`, so a
/// refresh can neither prompt, take the index lock nor leave the UI waiting.
class GitService {
  GitService({
    GitProcessRunner? runner,
    ToolPathResolver? resolver,
    Map<String, String>? environment,
    bool Function(String path)? fileExists,
    Duration readTimeout = const Duration(seconds: 15),
  }) : _runner = runner ?? const SystemGitProcessRunner(),
       _resolver = resolver ?? ToolPathResolver.instance,
       // ignore: prefer_initializing_formals
       _environment = environment,
       _fileExists = fileExists ?? _defaultFileExists,
       // ignore: prefer_initializing_formals
       _readTimeout = readTimeout;

  /// Hint shown when Apple's `/usr/bin/git` stub cannot run.
  static const String installHint =
      'Install Xcode Command Line Tools (run `xcode-select --install`) '
      'or `brew install git`';

  static const String _appleGitPath = '/usr/bin/git';
  static const String _xcodeSelectPath = '/usr/bin/xcode-select';

  final GitProcessRunner _runner;
  final ToolPathResolver _resolver;
  final Map<String, String>? _environment;
  final bool Function(String path) _fileExists;
  final Duration _readTimeout;

  static bool _defaultFileExists(String path) => File(path).existsSync();

  Map<String, String> get _baseEnvironment =>
      _environment ?? Platform.environment;

  /// Looks for a usable `git` without ever executing Apple's stub.
  ///
  /// When the only `git` on the machine is `/usr/bin/git` and
  /// `xcode-select -p` fails (no Command Line Tools), running it would pop up
  /// an installer dialog. The method reports "not available" with
  /// [installHint] instead, unless another `git` (Homebrew, `/usr/local`)
  /// exists, in which case that one is returned.
  Future<GitAvailability> gitAvailability({GitCancelToken? cancel}) async {
    if (cancel?.isCancelled ?? false) {
      return const GitAvailability.unavailable('Cancelled');
    }

    final gitPath = await _resolver.find('git');
    if (gitPath == null) {
      return const GitAvailability.unavailable(installHint);
    }
    if (gitPath != _appleGitPath) {
      return GitAvailability.available(gitPath);
    }
    if (await _commandLineToolsInstalled(cancel: cancel)) {
      return const GitAvailability.available(_appleGitPath);
    }
    if (cancel?.isCancelled ?? false) {
      return const GitAvailability.unavailable('Cancelled');
    }

    final alternative = await _alternativeGit();
    if (alternative != null) {
      return GitAvailability.available(alternative);
    }
    return const GitAvailability.unavailable(installHint);
  }

  /// Finds the repository root for [directory], or `null` when it is not a
  /// repository (or Git is not available).
  Future<String?> findRepoRoot(
    String directory, {
    GitCancelToken? cancel,
  }) async {
    final gitPath = await _resolver.find('git');
    if (gitPath == null) return null;
    final result = await _runGit(
      gitPath,
      const <String>['rev-parse', '--show-toplevel'],
      workingDirectory: directory,
      environment: await _gitEnvironment(),
      cancel: cancel,
    );
    if (!result.succeeded) return null;
    final root = result.stdout.trim();
    return root.isEmpty ? null : root;
  }

  /// Reads the summary of the repository at [root].
  ///
  /// Returns `null` only when Git cannot be found; a directory that is not a
  /// repository yields an empty summary instead of throwing.
  Future<GitRepoInfo?> repoInfo(String root, {GitCancelToken? cancel}) async {
    final gitPath = await _resolver.find('git');
    if (gitPath == null) return null;
    final environment = await _gitEnvironment();

    var stopped = cancel?.isCancelled ?? false;
    Future<GitResult> run(List<String> arguments) async {
      if (stopped) {
        return const GitResult(-1, '', 'Cancelled', false, true);
      }
      final result = await _runGit(
        gitPath,
        arguments,
        workingDirectory: root,
        environment: environment,
        cancel: cancel,
      );
      if (result.cancelled || result.timedOut) stopped = true;
      return result;
    }

    var branch = '';
    var isDetached = false;
    final branchResult = await run(const <String>[
      'symbolic-ref',
      '--short',
      '-q',
      'HEAD',
    ]);
    if (branchResult.succeeded) {
      branch = branchResult.stdout.trim();
    } else if (!stopped) {
      final shortResult = await run(const <String>[
        'rev-parse',
        '--short',
        'HEAD',
      ]);
      if (shortResult.succeeded) {
        branch = shortResult.stdout.trim();
        isDetached = true;
      }
    }

    final commitResult = await run(const <String>[
      'rev-parse',
      '--verify',
      '-q',
      'HEAD',
    ]);
    final hasCommits = commitResult.succeeded;

    String? upstream;
    final upstreamResult = await run(const <String>[
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '@{u}',
    ]);
    if (upstreamResult.succeeded) {
      final value = upstreamResult.stdout.trim();
      if (value.isNotEmpty) upstream = value;
    }

    var ahead = 0;
    var behind = 0;
    if (upstream != null) {
      final counts = await run(const <String>[
        'rev-list',
        '--left-right',
        '--count',
        'HEAD...@{u}',
      ]);
      if (counts.succeeded) {
        final parts = counts.stdout.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          ahead = int.tryParse(parts[0]) ?? 0;
          behind = int.tryParse(parts[1]) ?? 0;
        }
      }
    }

    final remotes = <GitRemote>[];
    final remotesResult = await run(const <String>['remote', '-v']);
    if (remotesResult.succeeded) {
      remotes.addAll(parseRemotes(remotesResult.stdout));
    }

    return GitRepoInfo(
      root: root,
      branch: branch,
      isDetached: isDetached,
      hasCommits: hasCommits,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
      remotes: remotes,
    );
  }

  /// Reads `git status --porcelain=v1 -z` for [root].
  ///
  /// Returns an empty list when Git is unavailable or the command fails.
  Future<List<GitChange>> status(String root, {GitCancelToken? cancel}) async {
    final gitPath = await _resolver.find('git');
    if (gitPath == null) return const <GitChange>[];
    final result = await _runGit(
      gitPath,
      const <String>[
        'status',
        '--porcelain=v1',
        '-z',
        '--untracked-files=normal',
      ],
      workingDirectory: root,
      environment: await _gitEnvironment(),
      cancel: cancel,
    );
    if (!result.succeeded) return const <GitChange>[];
    return parseStatus(result.stdout);
  }

  /// Parses the NUL-separated output of `git status --porcelain=v1 -z`.
  ///
  /// A rename/copy entry is followed by a second NUL field holding the
  /// original path. Paths are taken verbatim, so spaces and non-ASCII names
  /// survive; `-z` never quotes them.
  static List<GitChange> parseStatus(String output) {
    final fields = output.split('\u0000');
    final changes = <GitChange>[];
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      if (field.length < 4) continue;
      final indexStatus = field[0];
      final worktreeStatus = field[1];
      final path = field.substring(3);
      String? originalPath;
      if (indexStatus == 'R' ||
          indexStatus == 'C' ||
          worktreeStatus == 'R' ||
          worktreeStatus == 'C') {
        if (i + 1 < fields.length && fields[i + 1].isNotEmpty) {
          originalPath = fields[++i];
        }
      }
      changes.add(
        GitChange(
          path: path,
          originalPath: originalPath,
          indexStatus: indexStatus,
          worktreeStatus: worktreeStatus,
        ),
      );
    }
    return changes;
  }

  /// Parses `git remote -v`, keeping fetch URLs only.
  static List<GitRemote> parseRemotes(String output) {
    const suffix = ' (fetch)';
    final remotes = <GitRemote>[];
    for (final rawLine in output.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) continue;
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final rest = line.substring(tab + 1);
      if (!rest.endsWith(suffix)) continue;
      final name = line.substring(0, tab);
      final url = rest.substring(0, rest.length - suffix.length);
      remotes.add(GitRemote(name, stripCredentials(url)));
    }
    return remotes;
  }

  /// Removes a `user:password@` part from [url].
  ///
  /// A bare `user@` (the normal SSH form, e.g. `git@github.com:...`) is kept:
  /// it is not a secret. Only userinfo that carries a password is removed.
  static String stripCredentials(String url) {
    final match = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*://)([^/@]*@)(.*)$')
        .firstMatch(url);
    if (match == null) return url;
    final userInfo = match.group(2)!;
    if (!userInfo.contains(':')) return url;
    return '${match.group(1)}${match.group(3)}';
  }

  Future<bool> _commandLineToolsInstalled({GitCancelToken? cancel}) async {
    final executable = _fileExists(_xcodeSelectPath)
        ? _xcodeSelectPath
        : 'xcode-select';
    final result = await _runner.run(
      executable,
      const <String>['-p'],
      environment: await _gitEnvironment(),
      timeout: const Duration(seconds: 5),
      cancel: cancel,
    );
    return result.succeeded;
  }

  Future<String?> _alternativeGit() async {
    for (final directory in await _resolver.searchDirectories()) {
      final candidate = '$directory/git';
      if (candidate == _appleGitPath) continue;
      if (_fileExists(candidate)) return candidate;
    }
    return null;
  }

  Future<GitResult> _runGit(
    String gitPath,
    List<String> arguments, {
    required String workingDirectory,
    required Map<String, String> environment,
    GitCancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      return const GitResult(-1, '', 'Cancelled', false, true);
    }
    return _runner.run(
      gitPath,
      <String>['-c', 'core.quotepath=false', ...arguments],
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: _readTimeout,
      cancel: cancel,
    );
  }

  /// The environment for every Git command: the caller's environment, the
  /// resolved login-shell `PATH`, and the read-only/quiet flags.
  Future<Map<String, String>> _gitEnvironment() async {
    final environment = <String, String>{..._baseEnvironment};
    final resolved = await _resolver.processEnvironment();
    final path = resolved['PATH'];
    if (path != null && path.isNotEmpty) environment['PATH'] = path;
    environment['GIT_TERMINAL_PROMPT'] = '0';
    environment['GIT_OPTIONAL_LOCKS'] = '0';
    environment['LC_ALL'] = 'C';
    if (!environment.containsKey('GIT_SSH_COMMAND')) {
      environment['GIT_SSH_COMMAND'] = 'ssh -o BatchMode=yes';
    }
    return environment;
  }
}
