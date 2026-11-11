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
  ///
  /// When [stdinInput] is given it is written to the child's standard input
  /// (UTF-8) and the pipe is closed, so data never has to travel as an
  /// argument — a commit message with newlines or Persian text goes this way.
  Future<GitResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    GitCancelToken? cancel,
    String? stdinInput,
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
    String? stdinInput,
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

    // Write the payload and close the pipe, concurrently with the output
    // capture (a large write must not wait for a reader that drains stdout
    // first). A child that exits without reading everything — because it
    // rejected an argument, say — makes the write fail; the exit code already
    // reports that failure, so the write error is only recorded, never shown
    // in place of the real one.
    final writing = stdinInput == null
        ? null
        : _writeStdin(process, stdinInput);

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
      String? stdinNote;
      if (writing != null) stdinNote = await writing;
      finished = true;
      var stderr = streams[1];
      if (stdinNote != null && stderr.trim().isEmpty) stderr = stdinNote;
      return GitResult(exitCode, streams[0], stderr, timedOut, cancelled);
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

  /// Writes [payload] to [process.stdin] and closes the pipe.
  ///
  /// Returns a description of a write failure, or `null` on success. A broken
  /// pipe means the child exited before reading (git then reports the real
  /// problem on its own stderr), so the note is only surfaced when there is
  /// no real stderr to show.
  Future<String?> _writeStdin(Process process, String payload) async {
    try {
      process.stdin.add(utf8.encode(payload));
      await process.stdin.flush();
    } catch (error) {
      return 'git message could not be written to stdin: $error';
    }
    try {
      await process.stdin.close();
    } catch (error) {
      return 'git stdin could not be closed: $error';
    }
    return null;
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

  /// Stages [paths] using `git add -- <paths>`.
  Future<GitResult> stage(
    String root,
    List<String> paths, {
    GitCancelToken? cancel,
  }) async {
    final gitPath = await _resolver.find('git');
    if (gitPath == null) {
      return const GitResult(-1, '', installHint, false, false);
    }
    if (paths.isEmpty) {
      return const GitResult(0, '', '', false, false);
    }
    return _runGit(
      gitPath,
      <String>['add', '--', ...paths],
      workingDirectory: root,
      environment: await _gitEnvironment(),
      cancel: cancel,
    );
  }

  /// Unstages [paths].
  ///
  /// Uses `git restore --staged -- <paths>` when [hasCommits] is true, or
  /// `git rm --cached -- <paths>` when [hasCommits] is false (unborn branch).
  Future<GitResult> unstage(
    String root,
    List<String> paths, {
    required bool hasCommits,
    GitCancelToken? cancel,
  }) async {
    final gitPath = await _resolver.find('git');
    if (gitPath == null) {
      return const GitResult(-1, '', installHint, false, false);
    }
    if (paths.isEmpty) {
      return const GitResult(0, '', '', false, false);
    }
    final arguments = hasCommits
        ? <String>['restore', '--staged', '--', ...paths]
        : <String>['rm', '--cached', '--', ...paths];
    return _runGit(
      gitPath,
      arguments,
      workingDirectory: root,
      environment: await _gitEnvironment(),
      cancel: cancel,
    );
  }

  /// The default timeout for a commit: 60 s, because a pre-commit hook may be
  /// slow and must not be killed mid-run by the shorter read timeout.
  static const Duration commitTimeout = Duration(seconds: 60);

  /// Commits the staged changes by running `git commit -F -`.
  ///
  /// [message] is written to the process's standard input — never passed as
  /// an argument or through a shell — so multi-line messages and Persian
  /// text survive byte for byte. Hooks run (no `--no-verify`); `--amend` and
  /// `--all` are never used. The commit gets [timeout] (60 s by default) and
  /// can be killed through [cancel].
  Future<GitResult> commit(
    String root,
    String message, {
    GitCancelToken? cancel,
    Duration timeout = commitTimeout,
  }) async {
    final gitPath = await _resolver.find('git');
    if (gitPath == null) {
      return const GitResult(-1, '', installHint, false, false);
    }
    return _runGit(
      gitPath,
      const <String>['commit', '-F', '-'],
      workingDirectory: root,
      environment: await _gitEnvironment(),
      cancel: cancel,
      timeout: timeout,
      stdinInput: message,
    );
  }

  /// The default timeout for a push: 120 s, because a remote over a slow
  /// network must not be killed mid-transfer by the shorter read timeout.
  static const Duration pushTimeout = Duration(seconds: 120);

  /// Pushes the current branch to [remote].
  ///
  /// With [setUpstream] true the command is `git push -u <remote> <branch>`
  /// (the first push of a branch that has no upstream yet); otherwise it is a
  /// plain `git push`, which uses the branch's configured upstream. Only the
  /// plain form ever runs: no `--force`, `--force-with-lease`, `--delete`,
  /// `--mirror`, `--all` or `--tags` exists anywhere in the call, and an
  /// option-looking remote or branch name is refused before any process
  /// starts. The call carries the usual G1 hygiene plus [timeout] (120 s by
  /// default) and can be killed through [cancel].
  Future<GitResult> push(
    String root, {
    required String remote,
    required String branch,
    bool setUpstream = false,
    GitCancelToken? cancel,
    Duration timeout = pushTimeout,
  }) async {
    final gitPath = await _resolver.find('git');
    if (gitPath == null) {
      return const GitResult(-1, '', installHint, false, false);
    }
    // A refspec must never double as an option: a remote or branch that
    // starts with `-` is refused before any process starts, so no input can
    // turn the call into `git push --force` or friends.
    if (remote.startsWith('-')) {
      return const GitResult(
        -1,
        '',
        'Refusing to push to an option-looking remote name',
        false,
        false,
      );
    }
    if (branch.startsWith('-')) {
      return const GitResult(
        -1,
        '',
        'Refusing to push an option-looking branch name',
        false,
        false,
      );
    }
    final arguments = setUpstream
        ? <String>['push', '-u', remote, branch]
        : <String>['push'];
    return _runGit(
      gitPath,
      arguments,
      workingDirectory: root,
      environment: await _gitEnvironment(),
      cancel: cancel,
      timeout: timeout,
    );
  }

  /// The default timeout for a fetch: 60 s.
  ///
  /// Shorter than [pullTimeout] on purpose: a fetch runs when the Source
  /// Control panel opens rather than when the user asked for a transfer, so an
  /// unreachable remote must not keep the Pull button stale for two minutes.
  static const Duration fetchTimeout = Duration(seconds: 60);

  /// Updates the remote-tracking refs of [root] so that `ahead`/`behind` are
  /// real rather than as stale as the last fetch.
  ///
  /// Runs exactly `git fetch`: no `--prune`, no `--tags`, no `--all`, no
  /// `--force`, and it only ever writes the remote-tracking refs — the
  /// repository's own branches, index and worktree are untouched. This is what
  /// makes the Pull button reachable at all: [repoInfo] counts `HEAD...@{u}`
  /// against those refs, and nothing else in the app moves them.
  ///
  /// It is never called from a refresh trigger, which must stay instant and
  /// offline (see [GitController.fetchNow]).
  Future<GitResult> fetch(
    String root, {
    GitCancelToken? cancel,
    Duration timeout = fetchTimeout,
  }) async {
    final gitPath = await _resolver.find('git');
    if (gitPath == null) {
      return const GitResult(-1, '', installHint, false, false);
    }
    return _runGit(
      gitPath,
      const <String>['fetch'],
      workingDirectory: root,
      environment: await _gitEnvironment(),
      cancel: cancel,
      timeout: timeout,
    );
  }

  /// The default timeout for a pull: 120 s, because a remote over a slow
  /// network must not be killed mid-transfer by the shorter read timeout.
  static const Duration pullTimeout = Duration(seconds: 120);

  /// Pulls fast-forward only from the current branch's upstream.
  ///
  /// Runs exactly `git pull --ff-only`. No `--rebase`, `--merge`, or `--force`
  /// is ever used. The call carries the usual G1 hygiene plus [timeout] (120 s
  /// by default) and can be killed through [cancel].
  Future<GitResult> pull(
    String root, {
    GitCancelToken? cancel,
    Duration timeout = pullTimeout,
  }) async {
    final gitPath = await _resolver.find('git');
    if (gitPath == null) {
      return const GitResult(-1, '', installHint, false, false);
    }
    return _runGit(
      gitPath,
      const <String>['pull', '--ff-only'],
      workingDirectory: root,
      environment: await _gitEnvironment(),
      cancel: cancel,
      timeout: timeout,
    );
  }

  /// Reads the effective value of `git config <key>` for [root], or `null`
  /// when it is unset (a read-only command).
  Future<String?> configValue(
    String root,
    String key, {
    GitCancelToken? cancel,
  }) async {
    final gitPath = await _resolver.find('git');
    if (gitPath == null) return null;
    final result = await _runGit(
      gitPath,
      <String>['config', '--get', key],
      workingDirectory: root,
      environment: await _gitEnvironment(),
      cancel: cancel,
    );
    if (!result.succeeded) return null;
    final value = result.stdout.trim();
    return value.isEmpty ? null : value;
  }

  /// The only keys [setLocalConfig] may write.
  static const Set<String> _configurableKeys = <String>{
    'user.name',
    'user.email',
  };

  /// Writes [key] = [value] to the **repository-local** config of [root].
  ///
  /// The command never carries `--global` or `--system`: the value lands in
  /// `.git/config` of this repository only. [key] must be one of the commit
  /// identity keys (`user.name` / `user.email`).
  Future<GitResult> setLocalConfig(
    String root,
    String key,
    String value, {
    GitCancelToken? cancel,
  }) async {
    if (!_configurableKeys.contains(key)) {
      return GitResult(
        -1,
        '',
        'Refusing to write git config key "$key"',
        false,
        false,
      );
    }
    if (value.trim().isEmpty) {
      return const GitResult(
        -1,
        '',
        'Refusing to write an empty git config value',
        false,
        false,
      );
    }
    final gitPath = await _resolver.find('git');
    if (gitPath == null) {
      return const GitResult(-1, '', installHint, false, false);
    }
    return _runGit(
      gitPath,
      <String>['config', key, value],
      workingDirectory: root,
      environment: await _gitEnvironment(),
      cancel: cancel,
    );
  }

  /// The short SHA of the current HEAD, or `null` when it cannot be read
  /// (an unborn branch, or a failed command).
  Future<String?> headShortSha(String root, {GitCancelToken? cancel}) async {
    final gitPath = await _resolver.find('git');
    if (gitPath == null) return null;
    final result = await _runGit(
      gitPath,
      const <String>['rev-parse', '--short', 'HEAD'],
      workingDirectory: root,
      environment: await _gitEnvironment(),
      cancel: cancel,
    );
    if (!result.succeeded) return null;
    final sha = result.stdout.trim();
    return sha.isEmpty ? null : sha;
  }

  /// Maps a failed `git commit` to one clear line for the panel.
  ///
  /// The full output still goes to the Console; this is only the one line the
  /// panel can show. A failing pre-commit hook produces no message of its
  /// own — git just forwards the hook's output — so the hook's first output
  /// line is what the panel shows.
  static String commitFailureMessage(GitResult result) {
    if (result.cancelled) return 'Commit cancelled.';
    if (result.timedOut) {
      return 'Commit timed out after 60 s (a hook may be slow).';
    }
    final output = '${result.stdout}\n${result.stderr}';
    if (output.contains('index.lock')) {
      return 'Another git process is running; if none is, delete '
          '.git/index.lock yourself.';
    }
    if (output.contains('no changes added to commit') ||
        output.contains('nothing to commit')) {
      return 'Nothing staged to commit.';
    }
    if (output.contains('Author identity unknown') ||
        output.contains('Please tell me who you are') ||
        output.contains('unable to auto-detect email')) {
      return 'Git identity unknown — set user.name and user.email.';
    }
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return 'git commit failed (exit ${result.exitCode}).';
    }
    return lines.first;
  }

  /// Maps a failed `git push` to one clear line for the panel.
  ///
  /// The full output still goes to the Console; this is only the one line the
  /// panel can show. The mappings cover the failures a push can actually hit:
  /// an unreachable host, a key whose passphrase ssh-agent does not hold, an
  /// authentication rejection and a remote that moved ahead.
  static String pushFailureMessage(GitResult result) {
    if (result.cancelled) return 'Push cancelled.';
    if (result.timedOut) {
      return 'Push timed out after 120 s (the network may be slow).';
    }
    final output = '${result.stdout}\n${result.stderr}';
    if (output.contains('Could not resolve host') ||
        output.contains('Could not resolve hostname') ||
        output.contains('ssh: connect to host')) {
      return 'Could not reach the remote. Check the network and the remote '
          'URL.';
    }
    if (output.contains('passphrase')) {
      return 'Add your key to ssh-agent (ssh-add --apple-use-keychain).';
    }
    if (output.contains('Permission denied') ||
        output.toLowerCase().contains('authentication failed')) {
      return 'Authentication failed. Push once from a terminal or run '
          '`gh auth login`, or check your SSH key';
    }
    if (output.contains('[rejected]') ||
        output.contains('non-fast-forward') ||
        output.contains('Updates were rejected') ||
        output.contains('fetch first')) {
      return 'The remote has new commits. Pull first';
    }
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return 'git push failed (exit ${result.exitCode}).';
    }
    return lines.first;
  }

  /// Maps a failed background `git fetch` to one line for the Console.
  ///
  /// A fetch is not a user-initiated command, so its failure is reported as a
  /// console line rather than a panel banner: the panel's own error area is
  /// reserved for what the user pressed.
  static String fetchFailureMessage(GitResult result) {
    if (result.cancelled) return 'Fetch cancelled.';
    if (result.timedOut) {
      return 'Fetch timed out after 60 s (the network may be slow).';
    }
    final output = '${result.stdout}\n${result.stderr}';
    if (output.contains('Could not resolve host') ||
        output.contains('Could not resolve hostname') ||
        output.contains('ssh: connect to host')) {
      return 'Could not reach the remote. Check the network and the remote '
          'URL.';
    }
    if (output.contains('passphrase')) {
      return 'Add your key to ssh-agent (ssh-add --apple-use-keychain).';
    }
    if (output.contains('Permission denied') ||
        output.toLowerCase().contains('authentication failed')) {
      return 'Authentication failed. Fetch once from a terminal or run '
          '`gh auth login`, or check your SSH key';
    }
    if (output.contains('does not appear to be a git repository')) {
      return 'The remote is not a Git repository. Check the remote URL.';
    }
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return 'git fetch failed (exit ${result.exitCode}).';
    return lines.first;
  }

  /// Maps a failed `git pull` to one clear line for the panel.
  ///
  /// The full output still goes to the Console; this is only the one line the
  /// panel can show.
  static String pullFailureMessage(GitResult result) {
    if (result.cancelled) return 'Pull cancelled.';
    if (result.timedOut) {
      return 'Pull timed out after 120 s (the network may be slow).';
    }
    final output = '${result.stdout}\n${result.stderr}';
    if (output.contains('Not possible to fast-forward') ||
        output.contains('divergent branches') ||
        output.contains('Not fast-forward') ||
        output.contains('Diverging branches') ||
        output.contains('not possible to fast-forward')) {
      return 'Branches have diverged. Resolve this in a terminal (merge or rebase).';
    }
    if (output.contains(
          'Your local changes to the following files would be overwritten',
        ) ||
        output.contains('Please commit your changes or stash them')) {
      return 'Commit or stash your changes first.';
    }
    if (output.contains('Could not resolve host') ||
        output.contains('Could not resolve hostname') ||
        output.contains('ssh: connect to host')) {
      return 'Could not reach the remote. Check the network and the remote URL.';
    }
    if (output.contains('passphrase')) {
      return 'Add your key to ssh-agent (ssh-add --apple-use-keychain).';
    }
    if (output.contains('Permission denied') ||
        output.toLowerCase().contains('authentication failed')) {
      return 'Authentication failed. Push once from a terminal or run `gh auth login`, or check your SSH key';
    }
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return 'git pull failed (exit ${result.exitCode}).';
    }
    return lines.first;
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
    Duration? timeout,
    String? stdinInput,
  }) async {
    if (cancel?.isCancelled ?? false) {
      return const GitResult(-1, '', 'Cancelled', false, true);
    }
    return _runner.run(
      gitPath,
      <String>['-c', 'core.quotepath=false', ...arguments],
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: timeout ?? _readTimeout,
      cancel: cancel,
      stdinInput: stdinInput,
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
