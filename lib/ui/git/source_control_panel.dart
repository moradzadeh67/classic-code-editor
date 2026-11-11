import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/git_models.dart';
import '../../services/dart_runner_service.dart';
import '../../services/file_explorer_service.dart';
import '../../services/file_service.dart';
import '../../services/git_controller.dart';
import '../../services/git_service.dart';
import '../../services/theme_service.dart';
import '../retro/retro_border.dart';
import '../retro/retro_button.dart';

/// The Source Control bottom-panel tab widget.
///
/// Shows branch header, staged & unstaged/untracked changes, stage/unstage buttons,
/// "Stage All" & "Unstage All" header actions, empty states, and handles double-click to open.
class SourceControlPanel extends StatefulWidget {
  final GitController gitController;
  final DartRunnerService dartRunnerService;
  final FileService? fileService;
  final FileExplorerService? explorerService;
  final ValueChanged<String> onOpenFile;

  /// What the panel tells the user when the repository has no remote at all.
  static const String noRemoteHint =
      'No remote is configured. In a terminal run: git remote add origin <url>';

  /// What the panel tells the user when the branch tracks nothing.
  static const String noUpstreamHint =
      'This branch has no upstream. Set one with: git push -u <remote> <branch>';

  /// What the panel tells the user on a detached HEAD, where there is no branch
  /// to pull into.
  static const String detachedHint =
      'HEAD is detached. Check out a branch to '
      'pull.';

  const SourceControlPanel({
    super.key,
    required this.gitController,
    required this.dartRunnerService,
    this.fileService,
    this.explorerService,
    required this.onOpenFile,
  });

  @override
  State<SourceControlPanel> createState() => _SourceControlPanelState();
}

class _SourceControlPanelState extends State<SourceControlPanel> {
  bool _busy = false;
  String? _errorMessage;

  /// The commit message; its first line is the subject.
  final TextEditingController _messageController = TextEditingController();

  /// The inline identity form's fields (shown when git has no identity).
  final TextEditingController _identityNameController = TextEditingController();
  final TextEditingController _identityEmailController =
      TextEditingController();

  /// Non-null while a commit process is running; the Cancel button kills it.
  GitCancelToken? _commitToken;

  /// Non-null while a push process is running; the Cancel button kills it.
  GitCancelToken? _pushToken;

  /// Non-null while a pull process is running; the Cancel button kills it.
  GitCancelToken? _pullToken;

  /// Whether the "no git identity" form is on screen.
  bool _showIdentityForm = false;

  /// `Committed <short sha>` after a successful commit.
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    // Every keystroke re-evaluates the Commit button's enablement and the
    // subject-length hint.
    _messageController.addListener(_onMessageChanged);
    _identityNameController.addListener(_onMessageChanged);
    _identityEmailController.addListener(_onMessageChanged);
    // Opening Source Control is where a fetch belongs: `behind` is only as
    // fresh as the remote-tracking refs, so without this the Pull button could
    // never enable. One fetch per mount — never from a refresh trigger, which
    // must stay instant and offline.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_fetchAndRefresh());
    });
  }

  /// Fetches the remote-tracking refs, then refreshes — and reports a failure
  /// to the Console.
  ///
  /// This runs when the panel mounts and whenever `Refresh` is pressed. Both
  /// are needed: without the mount call a freshly opened panel cannot know it
  /// is behind, and without the button `behind` would never change again while
  /// the panel stays open — leaving Pull permanently disabled after one use.
  ///
  /// Silent on success: `git fetch` prints a line per updated ref, and the
  /// panel's job is to show the resulting `↓behind`, not the transfer.
  Future<void> _fetchAndRefresh() async {
    final result = await widget.gitController.fetchNow();
    if (!mounted || result == null || result.succeeded) return;
    widget.dartRunnerService.emitOutput(
      '[Git fetch] ${GitService.fetchFailureMessage(result)}',
    );
  }

  @override
  void dispose() {
    _messageController.removeListener(_onMessageChanged);
    _messageController.dispose();
    _identityNameController.removeListener(_onMessageChanged);
    _identityNameController.dispose();
    _identityEmailController.removeListener(_onMessageChanged);
    _identityEmailController.dispose();
    super.dispose();
  }

  void _onMessageChanged() {
    if (mounted) setState(() {});
  }

  /// The first line of the message — the subject.
  String get _subject => _messageController.text.split('\n').first.trim();

  /// A soft (non-blocking) style check on the subject line.
  bool get _subjectTooLong => _subject.length > 72;

  /// The Commit button is enabled only with at least one staged file, a
  /// non-blank message, and no operation in flight.
  bool _canCommit(List<GitChange> staged) =>
      !_busy &&
      !_showIdentityForm &&
      staged.isNotEmpty &&
      _messageController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.gitController,
        ThemeService.instance,
      ]),
      builder: (context, _) {
        final uiColors = ThemeService.instance.uiColors;
        final availability = widget.gitController.availability;
        final isAvailable = widget.gitController.isAvailable;
        final hasRepo = widget.gitController.hasRepo;
        final explorerFolder = widget.gitController.explorerFolder;
        final activeFilePath = widget.gitController.activeFilePath;

        return Container(
          key: const Key('source-control-panel'),
          decoration: RetroBorder.sunken(backgroundColor: uiColors['panel']),
          child: _buildBody(
            context,
            uiColors: uiColors,
            availability: availability,
            isAvailable: isAvailable,
            hasRepo: hasRepo,
            explorerFolder: explorerFolder,
            activeFilePath: activeFilePath,
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required Map<String, Color> uiColors,
    required GitAvailability? availability,
    required bool isAvailable,
    required bool hasRepo,
    required String? explorerFolder,
    required String? activeFilePath,
  }) {
    final textColor = uiColors['text'] ?? Colors.black;

    // 1. Empty state: Git is not installed
    if (availability != null && !isAvailable) {
      return _buildEmptyState(
        key: const Key('empty-state-git-not-installed'),
        title: 'Git is not installed',
        subtitle: availability.hint ?? GitService.installHint,
        textColor: textColor,
      );
    }

    // 2. Empty state: No folder open
    if (explorerFolder == null && activeFilePath == null) {
      return _buildEmptyState(
        key: const Key('empty-state-no-folder'),
        title: 'No folder open',
        subtitle: 'Open a folder or file to view source control status.',
        textColor: textColor,
      );
    }

    // 3. Empty state: Not a Git repository
    if (!hasRepo) {
      return _buildEmptyState(
        key: const Key('empty-state-not-repo'),
        title: 'Not a Git repository',
        subtitle: 'The open folder is not managed by Git.',
        textColor: textColor,
      );
    }

    final changes = widget.gitController.changes;
    final staged = changes.where((c) => c.isStaged).toList();
    final unstaged = changes
        .where((c) => c.isUnstaged || c.isUntracked || c.isConflicted)
        .toList();
    final stageable = unstaged.where((c) => !c.isConflicted).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with branch name, Refresh, Stage All, Unstage All.
        //
        // A `Wrap` rather than a `Row`: the panel can be dragged very narrow and
        // the three labels have no way to shrink, so the buttons move to a
        // second line instead of being clipped with the overflow stripes.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: uiColors['highlight'],
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(
                message: widget.gitController.repoInfo?.branch ?? 'HEAD',
                child: Text(
                  '⎇ ${widget.gitController.repoInfo?.branch.isNotEmpty == true ? widget.gitController.repoInfo!.branch : 'HEAD'}',
                  key: const Key('git-branch-header'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Arial',
                    color: textColor,
                  ),
                ),
              ),
              RetroButton(
                key: const Key('git-refresh-button'),
                // Refresh fetches as well as reads: `behind` comes from the
                // remote-tracking refs, so a status-only refresh would leave
                // the Pull button stale for as long as the panel stays open.
                onPressed: _busy ? null : () => unawaited(_fetchAndRefresh()),
                child: const Text('Refresh'),
              ),
              RetroButton(
                key: const Key('git-stage-all-button'),
                onPressed: (_busy || stageable.isEmpty)
                    ? null
                    : () => _stageAll(stageable),
                child: const Text('Stage All'),
              ),
              RetroButton(
                key: const Key('git-unstage-all-button'),
                onPressed: (_busy || staged.isEmpty)
                    ? null
                    : () => _unstageAll(staged),
                child: const Text('Unstage All'),
              ),
              _buildPullButton(uiColors),
              _buildPushButton(uiColors),
            ],
          ),
        ),
        // One-line error message if an operation failed
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            color: const Color(0xFFFFCCCC),
            child: Text(
              _errorMessage!,
              key: const Key('git-error-banner'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'Arial',
                color: Color(0xFFCC0000),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        // Body: "No changes" empty state or change sections
        Expanded(
          child: changes.isEmpty
              ? _buildEmptyState(
                  key: const Key('empty-state-no-changes'),
                  title: 'No changes',
                  subtitle: 'Working tree is clean.',
                  textColor: textColor,
                )
              : ListView(
                  children: [
                    if (staged.isNotEmpty) ...[
                      _buildSectionHeader(
                        'Staged Changes',
                        staged.length,
                        textColor,
                        uiColors,
                        const Key('staged-changes-header'),
                      ),
                      for (final change in staged)
                        _buildRow(
                          change: change,
                          statusLetter: _stagedStatusLetter(change),
                          letterColor: _statusColor(change, isStaged: true),
                          isStagedRow: true,
                          uiColors: uiColors,
                        ),
                    ],
                    if (unstaged.isNotEmpty) ...[
                      _buildSectionHeader(
                        'Changes',
                        unstaged.length,
                        textColor,
                        uiColors,
                        const Key('changes-header'),
                      ),
                      for (final change in unstaged)
                        _buildRow(
                          change: change,
                          statusLetter: _unstagedStatusLetter(change),
                          letterColor: _statusColor(change, isStaged: false),
                          isStagedRow: false,
                          uiColors: uiColors,
                        ),
                    ],
                  ],
                ),
        ),
        // Commit area: multi-line message box + Commit / Cancel, below the
        // lists.
        _buildCommitArea(staged: staged, uiColors: uiColors),
      ],
    );
  }

  Widget _buildEmptyState({
    required Key key,
    required String title,
    required String subtitle,
    required Color textColor,
  }) {
    return Center(
      key: key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'Arial',
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Arial',
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// The Pull button in the header: `Pull` or `Pull ↓<behind>`, enabled only
  /// when the repository can actually be pulled (see [_canPull]).
  Widget _buildPullButton(Map<String, Color> uiColors) {
    final info = widget.gitController.repoInfo;
    Widget button = RetroButton(
      key: const Key('git-pull-button'),
      onPressed: _canPull(info) ? _onPullPressed : null,
      child: Text(
        info != null && info.behind > 0 ? 'Pull ↓${info.behind}' : 'Pull',
      ),
    );
    // A disabled Pull is otherwise a dead end: say which condition is missing.
    // The transient "an operation is already running" case stays silent, as in
    // the Push button.
    final reason = _pullDisabledReason(info);
    if (reason != null) {
      button = Tooltip(message: reason, child: button);
    }
    return button;
  }

  /// Why Pull cannot run right now, or null when it can (or is merely busy).
  String? _pullDisabledReason(GitRepoInfo? info) {
    if (info == null) return null;
    if (_busy ||
        _pullToken != null ||
        _pushToken != null ||
        _commitToken != null) {
      return null;
    }
    if (info.isDetached) return SourceControlPanel.detachedHint;
    if (info.remotes.isEmpty) return SourceControlPanel.noRemoteHint;
    if (info.upstream == null) return SourceControlPanel.noUpstreamHint;
    if (info.behind == 0) {
      return 'Already up to date with ${info.upstream}.';
    }
    return null;
  }

  /// Whether Pull may run: not busy, not pulling/pushing/committing, not detached,
  /// on an upstream-backed branch with behind > 0.
  bool _canPull(GitRepoInfo? info) {
    if (info == null) return false;
    if (_busy ||
        _pullToken != null ||
        _pushToken != null ||
        _commitToken != null) {
      return false;
    }
    if (info.isDetached) return false;
    if (info.upstream == null) return false;
    if (info.behind == 0) return false;
    return true;
  }

  /// The Push button in the header: `Push` or `Push ↑<ahead>`, enabled only
  /// when the repository can actually be pushed (see [_canPush]).
  Widget _buildPushButton(Map<String, Color> uiColors) {
    final info = widget.gitController.repoInfo;
    Widget button = RetroButton(
      key: const Key('git-push-button'),
      onPressed: _canPush(info) ? _onPushPressed : null,
      child: Text(
        info != null && info.ahead > 0 ? 'Push ↑${info.ahead}' : 'Push',
      ),
    );
    if (!_canPush(info) && info != null && info.remotes.isEmpty) {
      button = Tooltip(message: SourceControlPanel.noRemoteHint, child: button);
    }
    return button;
  }

  /// Whether Push may run: not busy, not already pushing, not detached, on a
  /// born branch, with at least one remote — and, when an upstream exists,
  /// only with commits ahead of it.
  bool _canPush(GitRepoInfo? info) {
    if (info == null) return false;
    if (_busy ||
        _pushToken != null ||
        _pullToken != null ||
        _commitToken != null) {
      return false;
    }
    if (info.isDetached) return false;
    if (!info.hasCommits) return false;
    if (info.remotes.isEmpty) return false;
    if (info.upstream != null && info.ahead == 0) return false;
    return true;
  }

  /// The commit area below the change lists: the multi-line message box, the
  /// Commit / Cancel buttons, the soft subject hint, the success line and the
  /// inline identity form.
  Widget _buildCommitArea({
    required List<GitChange> staged,
    required Map<String, Color> uiColors,
  }) {
    final textColor = uiColors['text'] ?? Colors.black;
    final canCommit = _canCommit(staged);
    final isCommitting = _commitToken != null;

    return Container(
      key: const Key('git-commit-area'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: uiColors['shadow'] ?? Colors.grey),
        ),
        color: uiColors['panel'],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_subjectTooLong)
            Text(
              'Subject is longer than 72 characters.',
              key: const Key('git-commit-subject-hint'),
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Arial',
                fontStyle: FontStyle.italic,
                color: textColor.withValues(alpha: 0.7),
              ),
            ),
          CallbackShortcuts(
            // Cmd+Enter (and Ctrl+Enter) commits when the button would.
            bindings: {
              if (canCommit) ...{
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    _onCommitPressed,
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _onCommitPressed,
              },
            },
            child: TextField(
              key: const Key('git-commit-message-field'),
              controller: _messageController,
              minLines: 2,
              maxLines: 4,
              enabled: !isCommitting,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Arial',
                color: textColor,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Commit message (first line is the subject)',
                hintStyle: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Arial',
                  color: textColor.withValues(alpha: 0.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                filled: true,
                fillColor: uiColors['highlight'],
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              RetroButton(
                key: const Key('git-commit-button'),
                onPressed: canCommit ? _onCommitPressed : null,
                child: const Text('Commit'),
              ),
              if (isCommitting)
                RetroButton(
                  key: const Key('git-commit-cancel-button'),
                  onPressed: _cancelCommit,
                  child: const Text('Cancel'),
                ),
              if (_pushToken != null)
                RetroButton(
                  key: const Key('git-push-cancel-button'),
                  onPressed: () => _pushToken?.cancel(),
                  child: const Text('Cancel'),
                ),
              if (_pullToken != null)
                RetroButton(
                  key: const Key('git-pull-cancel-button'),
                  onPressed: () => _pullToken?.cancel(),
                  child: const Text('Cancel'),
                ),
            ],
          ),
          if (_successMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _successMessage!,
                key: const Key('git-success-line'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'Arial',
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF006600),
                ),
              ),
            ),
          if (_showIdentityForm) _buildIdentityForm(uiColors: uiColors),
        ],
      ),
    );
  }

  /// The inline form for a missing git identity: two small fields, the
  /// explanation that the values are stored only in this repository, and the
  /// "Save and commit" action.
  Widget _buildIdentityForm({required Map<String, Color> uiColors}) {
    final textColor = uiColors['text'] ?? Colors.black;
    final name = _identityNameController.text.trim();
    final email = _identityEmailController.text.trim();
    final canSave = !_busy && name.isNotEmpty && email.isNotEmpty;

    return Container(
      key: const Key('git-identity-form'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(6),
      decoration: RetroBorder.sunken(backgroundColor: uiColors['panel']),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Git identity is not configured. Both values are stored only in '
            'this repository.',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Arial',
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('git-identity-name'),
                  controller: _identityNameController,
                  enabled: !_busy,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Arial',
                    color: textColor,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Name',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Arial',
                      color: textColor.withValues(alpha: 0.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    filled: true,
                    fillColor: uiColors['highlight'],
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: const Key('git-identity-email'),
                  controller: _identityEmailController,
                  enabled: !_busy,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Arial',
                    color: textColor,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Email',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Arial',
                      color: textColor.withValues(alpha: 0.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    filled: true,
                    fillColor: uiColors['highlight'],
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              RetroButton(
                key: const Key('git-identity-save-button'),
                onPressed: canSave ? _onSaveIdentityAndCommit : null,
                child: const Text(
                  'Save and commit',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Commit pressed: check the identity first, then run the commit.
  Future<void> _onCommitPressed() async {
    if (_busy || !_canCommit(_currentStaged())) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final name = await widget.gitController.configValue('user.name');
    final email = await widget.gitController.configValue('user.email');
    if (!mounted) return;

    if (name == null || email == null) {
      // Show the inline form, prefilled with whatever git already knows.
      setState(() {
        _busy = false;
        _showIdentityForm = true;
        if (_identityNameController.text.isEmpty && name != null) {
          _identityNameController.text = name;
        }
        if (_identityEmailController.text.isEmpty && email != null) {
          _identityEmailController.text = email;
        }
      });
      return;
    }
    await _performCommit();
  }

  /// Saves the form's identity **repository-locally** (never --global) and
  /// continues with the commit.
  Future<void> _onSaveIdentityAndCommit() async {
    final name = _identityNameController.text.trim();
    final email = _identityEmailController.text.trim();
    if (_busy || name.isEmpty || email.isEmpty) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final nameResult = await widget.gitController.setLocalConfig(
      'user.name',
      name,
    );
    if (!nameResult.succeeded) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = _firstLineOf(nameResult);
      });
      return;
    }
    final emailResult = await widget.gitController.setLocalConfig(
      'user.email',
      email,
    );
    if (!emailResult.succeeded) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = _firstLineOf(emailResult);
      });
      return;
    }

    if (!mounted) return;
    setState(() => _showIdentityForm = false);
    await _performCommit();
  }

  /// Runs the commit with the message from the box, keeping the buttons
  /// disabled and the Cancel button alive until it finishes.
  Future<void> _performCommit() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final token = GitCancelToken();
    setState(() => _commitToken = token);

    final result = await widget.gitController.commit(
      _messageController.text,
      cancel: token,
    );
    if (!mounted) return;
    setState(() => _commitToken = null);

    // The real git output always goes to the Console.
    _emitCommitOutput(result);

    if (!result.succeeded) {
      _reportFailure(result);
      return;
    }

    final sha = await widget.gitController.headShortSha();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _showIdentityForm = false;
      _successMessage = sha == null ? 'Committed' : 'Committed $sha';
      _messageController.clear();
    });
  }

  /// The Cancel button: kills the commit process (60 s is also the timeout).
  void _cancelCommit() {
    _commitToken?.cancel();
  }

  /// Push pressed: resolve the remote (asking the user when there are several
  /// and no upstream is set), always show the confirmation dialog first, then
  /// run the push. With no remote nothing runs and the panel explains how to
  /// add one.
  Future<void> _onPushPressed() async {
    final info = widget.gitController.repoInfo;
    if (info == null || _busy || _pushToken != null) return;

    if (info.remotes.isEmpty) {
      setState(() => _errorMessage = SourceControlPanel.noRemoteHint);
      return;
    }

    final upstreamRemote = _remoteForUpstream(info);
    final hasUpstream = info.upstream != null && upstreamRemote != null;
    final names = info.remotes.map((r) => r.name).toList();
    final defaultRemote = hasUpstream
        ? upstreamRemote
        : (names.contains('origin') ? 'origin' : names.first);

    final remote = await showDialog<String>(
      context: context,
      builder: (_) => _PushConfirmDialog(
        info: info,
        remotes: info.remotes,
        initialRemote: defaultRemote,
        canChooseRemote: !hasUpstream && names.length > 1,
        setUpstream: !hasUpstream,
      ),
    );
    if (remote == null || !mounted) return;
    await _performPush(remote, setUpstream: !hasUpstream);
  }

  /// The remote an upstream ref like `origin/main` belongs to, matched
  /// against the configured remotes first (a branch may contain `/` itself),
  /// falling back to the first path segment.
  String? _remoteForUpstream(GitRepoInfo info) {
    final upstream = info.upstream;
    if (upstream == null) return null;
    for (final remote in info.remotes) {
      if (upstream == remote.name || upstream.startsWith('${remote.name}/')) {
        return remote.name;
      }
    }
    final segment = upstream.split('/').first;
    return segment.isEmpty ? null : segment;
  }

  /// Runs the push with the confirmed remote, keeping the buttons disabled
  /// and the Cancel button alive until it finishes.
  Future<void> _performPush(String remote, {required bool setUpstream}) async {
    setState(() {
      _busy = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final token = GitCancelToken();
    setState(() => _pushToken = token);

    final result = await widget.gitController.push(
      remote: remote,
      setUpstream: setUpstream,
      cancel: token,
    );
    if (!mounted) return;
    setState(() => _pushToken = null);

    // The real git output always goes to the Console.
    _emitPushOutput(result);

    if (!result.succeeded) {
      setState(() {
        _busy = false;
        _errorMessage = GitService.pushFailureMessage(result);
      });
      return;
    }
    setState(() {
      _busy = false;
      _successMessage = 'Pushed';
    });
  }

  /// Forwards every line of git's own push output to the Console.
  void _emitPushOutput(GitResult result) {
    widget.dartRunnerService.emitOutput('[Git push]');
    for (final line in [
      ...result.stdout.trim().split('\n'),
      ...result.stderr.trim().split('\n'),
    ]) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) widget.dartRunnerService.emitOutput(trimmed);
    }
  }

  /// Pull pressed: check uncommitted tracked changes first, then show the
  /// confirmation dialog, then run the pull.
  Future<void> _onPullPressed() async {
    final info = widget.gitController.repoInfo;
    if (info == null || !_canPull(info)) return;

    // Check for uncommitted tracked changes (staged or unstaged)
    final changes = widget.gitController.changes;
    final hasUncommittedTracked = changes.any((c) => !c.isUntracked);
    if (hasUncommittedTracked) {
      setState(() {
        _errorMessage = 'Commit or stash your changes first.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _PullConfirmDialog(info: info),
    );
    if (confirmed != true || !mounted) return;
    await _performPull();
  }

  /// Runs the pull with `--ff-only`, keeping the buttons disabled and the
  /// Cancel button alive until it finishes.
  Future<void> _performPull() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final token = GitCancelToken();
    setState(() => _pullToken = token);

    final result = await widget.gitController.pull(cancel: token);
    if (!mounted) return;
    setState(() => _pullToken = null);

    // The real git output always goes to the Console.
    _emitPullOutput(result);

    if (!result.succeeded) {
      setState(() {
        _busy = false;
        _errorMessage = GitService.pullFailureMessage(result);
      });
      return;
    }

    // The pull rewrote the working tree: a tab without unsaved edits takes the
    // new content, a tab with unsaved edits keeps them and is reported here
    // instead of being overwritten. The disk reads live in FileService so this
    // panel never touches the file system itself.
    final reload = await widget.fileService?.reloadTabsFromDisk();
    for (final path in reload?.skipped ?? const <String>[]) {
      widget.dartRunnerService.emitOutput(
        '$path changed on disk but has unsaved edits; not reloaded',
      );
    }

    // Refresh File Explorer tree and GitController
    await widget.explorerService?.refresh();
    await widget.gitController.refreshNow();

    if (!mounted) return;
    setState(() {
      _busy = false;
      _successMessage = 'Pulled';
    });
  }

  /// Forwards every line of git's own pull output to the Console.
  void _emitPullOutput(GitResult result) {
    widget.dartRunnerService.emitOutput('[Git pull]');
    for (final line in [
      ...result.stdout.trim().split('\n'),
      ...result.stderr.trim().split('\n'),
    ]) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) widget.dartRunnerService.emitOutput(trimmed);
    }
  }

  /// The staged rows as they are right now (read outside build).
  List<GitChange> _currentStaged() =>
      widget.gitController.changes.where((c) => c.isStaged).toList();

  /// Forwards every line of git's own output to the Console.
  void _emitCommitOutput(GitResult result) {
    widget.dartRunnerService.emitOutput('[Git commit]');
    for (final line in [
      ...result.stdout.trim().split('\n'),
      ...result.stderr.trim().split('\n'),
    ]) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) widget.dartRunnerService.emitOutput(trimmed);
    }
  }

  /// Shows one clear line in the panel; the real output is already in the
  /// Console.
  void _reportFailure(GitResult result) {
    setState(() {
      _busy = false;
      _errorMessage = GitService.commitFailureMessage(result);
    });
  }

  /// The first non-empty line of a git result (for failures that are not
  /// commits and have no mapping of their own).
  String _firstLineOf(GitResult result) {
    final detail = result.stderr.trim().isNotEmpty
        ? result.stderr.trim()
        : result.stdout.trim();
    return detail
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => detail);
  }

  Widget _buildSectionHeader(
    String title,
    int count,
    Color textColor,
    Map<String, Color> uiColors,
    Key key,
  ) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: uiColors['panel'],
      child: Text(
        '$title ($count)',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'Arial',
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildRow({
    required GitChange change,
    required String statusLetter,
    required Color letterColor,
    required bool isStagedRow,
    required Map<String, Color> uiColors,
  }) {
    final isConflicted = change.isConflicted;

    return Container(
      key: Key('git-row-${change.path}-${isStagedRow ? 'staged' : 'changes'}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () => _onRowDoubleTap(change),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Text(
                      statusLetter,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Courier',
                        color: letterColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        change.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Arial',
                          color: uiColors['text'],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isStagedRow)
            RetroButton(
              key: Key('git-unstage-button-${change.path}'),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              onPressed: _busy ? null : () => _unstage([change.path]),
              child: const Text('Unstage', style: TextStyle(fontSize: 11)),
            )
          else if (isConflicted)
            Tooltip(
              message: 'Resolve conflicts in a terminal',
              child: RetroButton(
                key: Key('git-stage-button-${change.path}'),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                onPressed: null,
                child: const Text('Stage', style: TextStyle(fontSize: 11)),
              ),
            )
          else
            RetroButton(
              key: Key('git-stage-button-${change.path}'),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              onPressed: _busy ? null : () => _stage([change.path]),
              child: const Text('Stage', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  String _stagedStatusLetter(GitChange change) {
    if (change.indexStatus == 'A') return 'A';
    if (change.indexStatus == 'M') return 'M';
    if (change.indexStatus == 'D') return 'D';
    if (change.indexStatus == 'R') return 'R';
    return change.indexStatus.trim().isEmpty ? 'M' : change.indexStatus;
  }

  String _unstagedStatusLetter(GitChange change) {
    if (change.isConflicted) return '!';
    if (change.isUntracked) return 'U';
    if (change.worktreeStatus == 'M') return 'M';
    if (change.worktreeStatus == 'D') return 'D';
    if (change.worktreeStatus == 'A') return 'A';
    if (change.worktreeStatus == 'R') return 'R';
    return change.worktreeStatus.trim().isEmpty ? 'M' : change.worktreeStatus;
  }

  Color _statusColor(GitChange change, {required bool isStaged}) {
    if (change.isConflicted) return const Color(0xFFCC0000);
    if (!isStaged && change.isUntracked) return const Color(0xFF00AA88);
    final letter = isStaged
        ? _stagedStatusLetter(change)
        : _unstagedStatusLetter(change);
    switch (letter) {
      case 'A':
        return const Color(0xFF00AA00);
      case 'M':
        return const Color(0xFFD0A000);
      case 'D':
        return const Color(0xFFCC0000);
      case 'R':
        return const Color(0xFFA000A0);
      default:
        return const Color(0xFF00AA88);
    }
  }

  void _onRowDoubleTap(GitChange change) {
    final root = widget.gitController.repoRoot;
    if (root == null) return;
    final fullPath = '$root/${change.path}';
    if (File(fullPath).existsSync()) {
      widget.onOpenFile(fullPath);
    }
  }

  /// Runs one Git operation with the buttons disabled, then reports a failure
  /// both to the Console (the real message) and to the panel (one line).
  Future<void> _runOperation(
    Future<GitResult> Function() operation,
    List<String> paths,
  ) async {
    if (_busy || paths.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final result = await operation();
    if (!mounted) return;

    if (!result.succeeded) {
      final detail = result.stderr.trim().isNotEmpty
          ? result.stderr.trim()
          : result.stdout.trim();
      widget.dartRunnerService.emitOutput('[Git] $detail');
      setState(() {
        _busy = false;
        _errorMessage = detail
            .split('\n')
            .firstWhere((line) => line.trim().isNotEmpty, orElse: () => detail);
      });
      return;
    }

    setState(() {
      _busy = false;
    });
  }

  Future<void> _stage(List<String> paths) =>
      _runOperation(() => widget.gitController.stage(paths), paths);

  Future<void> _unstage(List<String> paths) =>
      _runOperation(() => widget.gitController.unstage(paths), paths);

  void _stageAll(List<GitChange> stageable) {
    _stage(stageable.map((c) => c.path).toList());
  }

  void _unstageAll(List<GitChange> staged) {
    _unstage(staged.map((c) => c.path).toList());
  }
}

/// The confirmation dialog shown before every push: the remote (picked when
/// several exist and no upstream is set), its credential-stripped URL, the
/// local → remote branch and either the number of commits to push or — for a
/// branch with no upstream — the exact command that will run.
class _PushConfirmDialog extends StatefulWidget {
  const _PushConfirmDialog({
    required this.info,
    required this.remotes,
    required this.initialRemote,
    required this.canChooseRemote,
    required this.setUpstream,
  });

  final GitRepoInfo info;
  final List<GitRemote> remotes;
  final String initialRemote;

  /// Whether the user may pick a remote here (several remotes, no upstream).
  final bool canChooseRemote;

  /// Whether the push will run `git push -u <remote> <branch>` (no upstream).
  final bool setUpstream;

  @override
  State<_PushConfirmDialog> createState() => _PushConfirmDialogState();
}

class _PushConfirmDialogState extends State<_PushConfirmDialog> {
  late String _remote = widget.initialRemote;

  GitRemote? get _selected {
    for (final remote in widget.remotes) {
      if (remote.name == _remote) return remote;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final uiColors = ThemeService.instance.uiColors;
        final textColor = uiColors['text'] ?? Colors.black;
        final info = widget.info;
        final targetBranch = widget.setUpstream
            ? '$_remote/${info.branch}'
            : info.upstream ?? '$_remote/${info.branch}';
        final url = GitService.stripCredentials(_selected?.url ?? '');

        return AlertDialog(
          key: const Key('git-push-dialog'),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          backgroundColor: uiColors['panel'],
          title: const Text('Push'),
          titleTextStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'Arial',
            color: textColor,
          ),
          contentTextStyle: TextStyle(
            fontSize: 12,
            fontFamily: 'Arial',
            color: textColor,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.canChooseRemote)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Remote:',
                      style: TextStyle(
                        fontFamily: 'Arial',
                        fontSize: 12,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    DropdownButton<String>(
                      key: const Key('git-push-remote-picker'),
                      value: _remote,
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      dropdownColor: uiColors['panel'],
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Arial',
                        color: textColor,
                      ),
                      items: [
                        for (final remote in widget.remotes)
                          DropdownMenuItem<String>(
                            value: remote.name,
                            child: Text(
                              remote.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Arial',
                                color: textColor,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _remote = value);
                      },
                    ),
                  ],
                )
              else
                Text(
                  'Remote: $_remote',
                  key: const Key('git-push-dialog-remote'),
                ),
              if (url.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      url,
                      key: const Key('git-push-dialog-url'),
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Arial',
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '${info.branch} → $targetBranch',
                    key: const Key('git-push-dialog-branch'),
                  ),
                ),
              ),
              if (widget.setUpstream)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'will run: git push -u $_remote ${info.branch}',
                    key: const Key('git-push-dialog-will-run'),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${info.ahead} ${info.ahead == 1 ? 'commit' : 'commits'} '
                    'will be pushed.',
                    key: const Key('git-push-dialog-count'),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            RetroButton(
              key: const Key('git-push-dialog-cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            RetroButton(
              key: const Key('git-push-dialog-confirm'),
              onPressed: () => Navigator.of(context).pop(_remote),
              child: const Text('Push'),
            ),
          ],
        );
      },
    );
  }
}

/// The confirmation dialog shown before every pull: the upstream ref, its
/// credential-stripped URL, the incoming commit count, and the command that
/// will run (`git pull --ff-only`).
class _PullConfirmDialog extends StatelessWidget {
  const _PullConfirmDialog({required this.info});

  final GitRepoInfo info;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final uiColors = ThemeService.instance.uiColors;
        final textColor = uiColors['text'] ?? Colors.black;
        final upstream = info.upstream ?? 'upstream';

        String remoteUrl = '';
        for (final remote in info.remotes) {
          if (upstream.startsWith('${remote.name}/') ||
              upstream == remote.name) {
            remoteUrl = GitService.stripCredentials(remote.url);
            break;
          }
        }

        return AlertDialog(
          key: const Key('git-pull-dialog'),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          backgroundColor: uiColors['panel'],
          title: const Text('Pull'),
          titleTextStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'Arial',
            color: textColor,
          ),
          contentTextStyle: TextStyle(
            fontSize: 12,
            fontFamily: 'Arial',
            color: textColor,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upstream: $upstream',
                key: const Key('git-pull-dialog-upstream'),
              ),
              if (remoteUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      remoteUrl,
                      key: const Key('git-pull-dialog-url'),
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Arial',
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${info.behind} ${info.behind == 1 ? 'commit' : 'commits'} will be pulled.',
                  key: const Key('git-pull-dialog-count'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'will run: git pull --ff-only',
                  key: Key('git-pull-dialog-will-run'),
                ),
              ),
            ],
          ),
          actions: [
            RetroButton(
              key: const Key('git-pull-dialog-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            RetroButton(
              key: const Key('git-pull-dialog-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Pull'),
            ),
          ],
        );
      },
    );
  }
}
