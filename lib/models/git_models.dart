/// Data structures for the read-only Git helpers.
///
/// A shared set of read-only repository views: the result of a single
/// invocation ([GitResult]), whether Git can be used at all
/// ([GitAvailability]), a remote ([GitRemote]), one path from status
/// ([GitChange]) and a summary snapshot of a repository ([GitRepoInfo]).
class GitResult {
  const GitResult(
    this.exitCode,
    this.stdout,
    this.stderr,
    this.timedOut,
    this.cancelled,
  );

  /// Exit code from the process (`-1` when it could not be started).
  final int exitCode;

  /// Standard output captured (at most 5 MB).
  final String stdout;

  /// Standard error captured (at most 5 MB).
  final String stderr;

  /// Whether the command exceeded the configured timeout.
  final bool timedOut;

  /// Whether the process was killed by the caller.
  final bool cancelled;

  /// True only when the command finished successfully in time.
  bool get succeeded => exitCode == 0 && !timedOut && !cancelled;
}

/// The outcome of looking for a usable `git` executable.
class GitAvailability {
  const GitAvailability.available(this.path) : hint = null;

  const GitAvailability.unavailable(this.hint) : path = null;

  /// Absolute path of the `git` that may be executed, or `null`.
  final String? path;

  /// What the user should do when Git is not usable.
  final String? hint;

  /// Whether [path] can be executed.
  bool get isAvailable => path != null;
}

/// A remote host exposed by `git remote -v`.
class GitRemote {
  const GitRemote(this.name, this.url);

  /// Remote name, e.g. `origin`.
  final String name;

  /// Fetch URL with a `user:password@` part removed.
  final String url;
}

/// One path tracked by `git status --porcelain=v1 -z`.
class GitChange {
  GitChange({
    required this.path,
    this.originalPath,
    required this.indexStatus,
    required this.worktreeStatus,
    bool? isUntracked,
    bool? isConflicted,
  }) : isUntracked =
           isUntracked ?? (indexStatus == '?' && worktreeStatus == '?'),
       isConflicted =
           isConflicted ??
           conflictStatuses.contains('$indexStatus$worktreeStatus');

  /// Status pairs that mean an unresolved merge: `DD`, `AU`, `UD`, `UA`,
  /// `DU`, `AA` and `UU`.
  static const Set<String> conflictStatuses = <String>{
    'DD',
    'AU',
    'UD',
    'UA',
    'DU',
    'AA',
    'UU',
  };

  /// Path relative to the repository root (the new path for a rename/copy).
  final String path;

  /// Original path for renames/copies.
  final String? originalPath;

  /// Status character in the index (`' '` when unchanged).
  final String indexStatus;

  /// Status character in the worktree (`' '` when unchanged).
  final String worktreeStatus;

  /// Whether this is an untracked file (`??`).
  final bool isUntracked;

  /// Whether this is an unresolved merge conflict.
  final bool isConflicted;

  /// Whether the index holds a change for this path.
  bool get isStaged =>
      !isConflicted && indexStatus != ' ' && indexStatus != '?';

  /// Whether the worktree holds a change for this path.
  ///
  /// Untracked files are not "unstaged": they have their own group and
  /// [isUntracked] flag.
  bool get isUnstaged =>
      !isConflicted &&
      !isUntracked &&
      worktreeStatus != ' ' &&
      worktreeStatus != '?';
}

/// Summary information about a Git repository.
class GitRepoInfo {
  const GitRepoInfo({
    required this.root,
    required this.branch,
    required this.isDetached,
    required this.hasCommits,
    this.upstream,
    required this.ahead,
    required this.behind,
    required this.remotes,
  });

  /// Absolute root path of the repository.
  final String root;

  /// Current branch name, or the short SHA when [isDetached].
  final String branch;

  /// Whether HEAD is detached.
  final bool isDetached;

  /// Whether the repository contains at least one commit.
  final bool hasCommits;

  /// Upstream ref (e.g. `origin/main`), or `null` when none is configured.
  final String? upstream;

  /// Commits ahead of [upstream] (`0` when there is no upstream).
  final int ahead;

  /// Commits behind [upstream] (`0` when there is no upstream).
  final int behind;

  /// Fetch URLs of every remote, with credentials removed.
  final List<GitRemote> remotes;
}
