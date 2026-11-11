import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/git_models.dart';
import 'git_service.dart';

/// Owns the read-only Git snapshot the status bar shows.
///
/// The controller never runs a command of its own: every read goes through
/// [GitService], which uses `Process.start` with an argument lists only, so a
/// refresh can neither prompt nor take the index lock. Nothing here knows about
/// a widget, and no timer polls the repository — a refresh happens only when
/// one of the triggers calls [refresh] (debounced) or [refreshNow].
///
/// The repository directory is resolved from the open explorer folder first,
/// else from the directory of the active file-backed tab. When neither exists
/// the state is "no repository" and **no** Git command is run.
class GitController extends ChangeNotifier {
  GitController({GitService? service, this.debounce = defaultDebounce})
    : _service = service ?? GitService();

  /// How long [refresh] waits before the first command runs.
  ///
  /// A burst of triggers (a tab switch, a save, a window focus) collapses into
  /// a single refresh, which keeps `git status` off the interaction path. The
  /// production value is [defaultDebounce]; tests may shorten it.
  static const Duration defaultDebounce = Duration(milliseconds: 400);

  /// The debounce this controller was built with.
  final Duration debounce;

  final GitService _service;

  /// The open folder of the File Explorer, or null when none is open.
  String? _explorerFolder;

  /// Absolute path of the active tab when it is backed by a file.
  String? _activeFilePath;

  GitAvailability? _availability;
  String? _repoRoot;
  GitRepoInfo? _repoInfo;
  List<GitChange> _changes = const <GitChange>[];
  bool _hasRepo = false;

  Timer? _debounceTimer;
  GitCancelToken? _cancelToken;
  bool _running = false;
  bool _pending = false;
  bool _disposed = false;

  /// Bumped whenever the directory inputs change.
  ///
  /// A refresh that reads the previous directory can finish after the change;
  /// its result is discarded instead of being painted over the new one.
  int _generation = 0;

  /// Whether Git is usable at all (resolved alongside the last refresh).
  GitAvailability? get availability => _availability;

  /// Whether a usable `git` was found (false while nothing was resolved yet).
  bool get isAvailable => _availability?.isAvailable ?? false;

  /// Root of the repository the status bar is showing, or null.
  String? get repoRoot => _repoRoot;

  /// Branch, upstream, ahead/behind and remotes of the repository, or null.
  GitRepoInfo? get repoInfo => _repoInfo;

  /// `git status` for the repository (empty when there is no repository).
  List<GitChange> get changes => _changes;

  /// Whether a repository is currently shown.
  bool get hasRepo => _hasRepo;

  /// Number of changed paths (`git status` entries).
  int get changeCount => _changes.length;

  /// The open explorer folder, as last pushed by the shell.
  String? get explorerFolder => _explorerFolder;

  /// The active tab's file path, as last pushed by the shell.
  String? get activeFilePath => _activeFilePath;

  /// Segment text for the status bar.
  ///
  /// `⎇ <branch>` (`⎇ <short sha>` on a detached HEAD), then ` ● <n>` when there
  /// are changed paths, then ` ↑<ahead> ↓<behind>` for the parts that are not
  /// zero. Returns null when the segment must be hidden: no repository, no
  /// summary, or Git unavailable.
  String? get statusLabel {
    if (!_hasRepo || !isAvailable) return null;
    final info = _repoInfo;
    if (info == null) return null;

    final buffer = StringBuffer('⎇ ');
    buffer.write(info.branch.isEmpty ? 'HEAD' : info.branch);
    if (_changes.isNotEmpty) buffer.write(' ● ${_changes.length}');
    if (info.ahead > 0) buffer.write(' ↑${info.ahead}');
    if (info.behind > 0) buffer.write(' ↓${info.behind}');
    return buffer.toString();
  }

  /// Tooltip text: the repository root, the upstream (or "no upstream") and the
  /// credential-stripped fetch URLs. Empty when nothing is shown.
  String get tooltipText {
    if (!_hasRepo || !isAvailable) return '';
    final info = _repoInfo;
    if (info == null) return '';

    final lines = <String>[
      info.root,
      if (info.isDetached) 'detached HEAD',
      'upstream: ${info.upstream ?? 'no upstream'}',
      for (final remote in info.remotes) '${remote.name}: ${remote.url}',
    ];
    return lines.join('\n');
  }

  /// Sets the File Explorer's open folder and refreshes when it changed.
  void setExplorerFolder(String? path) {
    if (_explorerFolder == path) return;
    _explorerFolder = path;
    _generation++;
    refresh();
  }

  /// Sets the active tab's file path (null for an untitled buffer) and
  /// refreshes when it changed.
  void setActiveFilePath(String? path) {
    if (_activeFilePath == path) return;
    _activeFilePath = path;
    _generation++;
    refresh();
  }

  /// Refreshes as the answer to a save or a regained window focus.
  ///
  /// Same as [refresh]; named for the trigger so the call sites read clearly.
  void refreshForExternalChange() => refresh();

  /// Exposes the underlying [GitService] for direct service tests.
  GitService get service => _service;

  /// Stages [paths] in the current repository and refreshes immediately.
  Future<GitResult> stage(List<String> paths) async {
    final root = _repoRoot;
    if (root == null || !_hasRepo) {
      return const GitResult(-1, '', 'No repository', false, false);
    }
    final result = await _service.stage(root, paths);
    await refreshNow();
    return result;
  }

  /// Unstages [paths] in the current repository and refreshes immediately.
  Future<GitResult> unstage(List<String> paths) async {
    final root = _repoRoot;
    if (root == null || !_hasRepo) {
      return const GitResult(-1, '', 'No repository', false, false);
    }
    final hasCommits = _repoInfo?.hasCommits ?? true;
    final result = await _service.unstage(root, paths, hasCommits: hasCommits);
    await refreshNow();
    return result;
  }

  /// Commits the staged changes with [message] and refreshes immediately.
  ///
  /// [cancel] kills the commit process (a slow hook, or the user pressed
  /// Cancel). The refresh also runs after a failure, so a hook that modified
  /// the worktree is reflected at once.
  Future<GitResult> commit(String message, {GitCancelToken? cancel}) async {
    final root = _repoRoot;
    if (root == null || !_hasRepo) {
      return const GitResult(-1, '', 'No repository', false, false);
    }
    final result = await _service.commit(root, message, cancel: cancel);
    await refreshNow();
    return result;
  }

  /// Pushes the current branch to [remote] and refreshes immediately.
  ///
  /// [setUpstream] selects the `git push -u <remote> <branch>` form for a
  /// branch that has no upstream yet. [cancel] kills the push process (a slow
  /// network, or the user pressed Cancel). The refresh also runs after a
  /// failure, so a partial transfer is reflected at once.
  Future<GitResult> push({
    required String remote,
    required bool setUpstream,
    GitCancelToken? cancel,
  }) async {
    final root = _repoRoot;
    if (root == null || !_hasRepo) {
      return const GitResult(-1, '', 'No repository', false, false);
    }
    final branch = _repoInfo?.branch ?? '';
    if (branch.isEmpty) {
      return const GitResult(-1, '', 'No branch to push', false, false);
    }
    final result = await _service.push(
      root,
      remote: remote,
      branch: branch,
      setUpstream: setUpstream,
      cancel: cancel,
    );
    await refreshNow();
    return result;
  }

  /// Fetches the remote-tracking refs, then refreshes immediately.
  ///
  /// [repoInfo] derives `behind` from `HEAD...@{u}`, so it is only as fresh as
  /// the last fetch — and a stale `behind` keeps the Pull button disabled. The
  /// Source Control panel therefore calls this once when it opens.
  ///
  /// Deliberately **not** wired to a refresh trigger: a refresh must stay
  /// instant and offline, while this talks to the network.
  ///
  /// Returns null — and starts no process — when there is nothing to fetch: no
  /// repository, or a repository whose remotes are all missing.
  Future<GitResult?> fetchNow({GitCancelToken? cancel}) async {
    if (_disposed) return null;
    if (!_hasRepo || _repoRoot == null) await refreshNow();
    final root = _repoRoot;
    if (root == null || !_hasRepo) return null;
    if ((_repoInfo?.remotes ?? const <GitRemote>[]).isEmpty) return null;
    final result = await _service.fetch(root, cancel: cancel);
    await refreshNow();
    return result;
  }

  /// Pulls fast-forward only from the current branch's upstream and refreshes
  /// immediately.
  ///
  /// [cancel] kills the pull process (a slow network, or the user pressed
  /// Cancel). The refresh also runs after a failure.
  Future<GitResult> pull({GitCancelToken? cancel}) async {
    final root = _repoRoot;
    if (root == null || !_hasRepo) {
      return const GitResult(-1, '', 'No repository', false, false);
    }
    final result = await _service.pull(root, cancel: cancel);
    await refreshNow();
    return result;
  }

  /// Reads the effective `git config` value of [key] for the repository, or
  /// `null` when there is no repository or the key is unset.
  Future<String?> configValue(String key) async {
    final root = _repoRoot;
    if (root == null || !_hasRepo) return null;
    return _service.configValue(root, key);
  }

  /// Writes a repository-local `git config` value ([key] restricted by
  /// [GitService.setLocalConfig]) and refreshes nothing — config values do
  /// not change the status.
  Future<GitResult> setLocalConfig(String key, String value) async {
    final root = _repoRoot;
    if (root == null || !_hasRepo) {
      return const GitResult(-1, '', 'No repository', false, false);
    }
    return _service.setLocalConfig(root, key, value);
  }

  /// The short SHA of the repository's HEAD, or `null` (shown after a
  /// successful commit as `Committed <sha>`).
  Future<String?> headShortSha() async {
    final root = _repoRoot;
    if (root == null || !_hasRepo) return null;
    return _service.headShortSha(root);
  }

  /// Requests a debounced refresh.
  ///
  /// A refresh requested while another is running is not lost: it runs once
  /// more as soon as the current one finishes.
  void refresh() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(refreshNow());
    });
  }

  /// Runs a refresh immediately (no debounce), single-flight.
  ///
  /// Used by the refresh triggers that must not wait out the debounce, and by
  /// the future Git operations (stage, commit) that need the status bar to
  /// catch up at once.
  Future<void> refreshNow() async {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = null;

    if (_running) {
      // Collapse any number of overlapping requests into one follow-up run.
      _pending = true;
      return;
    }
    _running = true;
    try {
      await _perform();
    } finally {
      _running = false;
    }
    if (_pending && !_disposed) {
      _pending = false;
      await refreshNow();
    }
  }

  Future<void> _perform() async {
    final generation = _generation;
    final directory = _resolveDirectory();
    if (directory == null) {
      _setNoRepo();
      return;
    }

    final token = GitCancelToken();
    _cancelToken = token;

    final availability = await _service.gitAvailability(cancel: token);
    if (_stale(generation, token)) return;
    _availability = availability;
    if (!availability.isAvailable) {
      _setNoRepo();
      return;
    }

    final root = await _service.findRepoRoot(directory, cancel: token);
    if (_stale(generation, token)) return;
    if (root == null) {
      _setNoRepo();
      return;
    }

    final info = await _service.repoInfo(root, cancel: token);
    final changes = await _service.status(root, cancel: token);
    if (_stale(generation, token)) return;

    _repoRoot = root;
    _repoInfo = info;
    _changes = List<GitChange>.unmodifiable(changes);
    _hasRepo = true;
    notifyListeners();
  }

  /// Whether a completed step no longer describes the current directory.
  bool _stale(int generation, GitCancelToken token) =>
      _disposed || generation != _generation || !identical(_cancelToken, token);

  /// The directory a repository is looked up from.
  ///
  /// The explorer's open folder wins; otherwise the active file's own
  /// directory; otherwise nothing (and no command runs).
  String? _resolveDirectory() {
    final folder = _explorerFolder;
    if (folder != null && folder.isNotEmpty) return folder;

    final file = _activeFilePath;
    if (file != null && file.isNotEmpty) {
      final separator = file.lastIndexOf('/');
      if (separator > 0) return file.substring(0, separator);
      if (separator == 0) return '/';
    }
    return null;
  }

  /// Clears the snapshot (a directory with no repository, or no `git`).
  void _setNoRepo() {
    _cancelToken = null;
    if (!_hasRepo &&
        _repoRoot == null &&
        _repoInfo == null &&
        _changes.isEmpty) {
      // The segment was already hidden; nothing to repaint.
      // [availability] is left as resolved, because its own getters
      // ([isAvailable]) may have just changed and callers read it directly.
      return;
    }
    _repoRoot = null;
    _repoInfo = null;
    _changes = const <GitChange>[];
    _hasRepo = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _cancelToken?.cancel();
    _cancelToken = null;
    super.dispose();
  }
}
