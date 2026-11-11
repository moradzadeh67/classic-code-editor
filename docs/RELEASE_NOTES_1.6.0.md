# Classic Code Editor — v1.6.0 release notes

**Git inside the IDE: a repository in the status bar, a Source Control panel that stages,
commits, pushes and pulls — and nothing that can destroy your work.**

## Highlights

- **Source Control panel.** A fifth tab in the bottom strip lists what the status bar has been
  reporting: `Staged Changes (n)` and `Changes (n)`, each row with its coloured status letter
  (staged `A`/`M`/`D`/`R`, worktree `U` for untracked, `M`, `D`, `A`, `R`, `!` for a conflicted pair)
  and its own action button. Stage and Unstage work per row and in bulk (`Stage All` / `Unstage All`);
  a conflicted row is disabled with a "Resolve conflicts in a terminal" tooltip and is excluded from
  the bulk action; a double-click opens the file — only while it still exists on disk. Four empty
  states explain themselves (`Git is not installed`, `No folder open`, `Not a Git repository`,
  `No changes`).
- **Commit.** A message box (first line is the subject, with a soft hint past 72 characters) and a
  `Commit` button that is enabled only when something is staged and the message is non-blank.
  `Cmd+Enter` commits. Git identity is read first; when `user.name`/`user.email` are unset, an inline
  form writes them **repository-locally** — never `--global`. The message reaches git on **stdin**
  (`git commit -F -`), never through a shell or an argument.
- **Push.** The button carries the ahead count (`Push ↑2`) and is enabled only when the repository can
  actually be pushed. The confirmation dialog shows the remote, its credential-stripped URL, the
  `local → remote` branch line and the exact command that will run; a branch without an upstream runs
  `git push -u <remote> <branch>`. Real git output streams to the Console; failures collapse to one
  readable line (unreachable host, `ssh-add --apple-use-keychain`, authentication, "the remote has new
  commits — pull first", cancelled, timed out).
- **Pull.** The button carries the upstream distance (`Pull ↓3`) and explains why it is disabled
  (`HEAD is detached`, `No remote is configured`, `This branch has no upstream`, `Already up to date`).
  Git runs `git pull --ff-only`, so a diverged history stops instead of silently merging.
  **The bug this release fixes:** `↓behind` is counted from the remote-tracking refs, and nothing in
  the app ever moved them, so a remote that had genuinely moved on still reported `0` and the button
  stayed dead forever. Opening Source Control now runs exactly one `git fetch` (refs only — no
  `--prune`, `--tags`, `--all`, `--depth`; the worktree is untouched), and a status-only refresh
  (folder opened, tab switched, file saved, window focused) never fetches.
- **Post-pull reload, without losing edits.** After a pull, every open file-backed tab is re-read from
  disk through an injectable reader. An unmodified tab takes the new content and stays clean; a tab
  with unsaved edits keeps them and the Console prints
  `<path> changed on disk but has unsaved edits; not reloaded`; a file that vanished is skipped rather
  than emptied.
- **Status-bar repository segment.** `⎇ <branch>` (the short SHA on a detached HEAD), `● n` when the
  index or worktree has changes, and `↑ahead` / `↓behind` against the upstream, in a fixed 150 px box
  so the rest of the bar never shifts. Clicking it opens the Source Control tab. Its tooltip carries
  the repository root, the detached flag, the upstream and the credential-stripped remote URLs. It is
  not laid out at all when there is no repository or no `git`.
- **Safe by construction.** `GitService` is the only place a `git` process is started. Every command is
  an argument list with a resolved `PATH`, `GIT_TERMINAL_PROMPT=0`, `GIT_OPTIONAL_LOCKS=0`, `LC_ALL=C`,
  `-c core.quotepath=false`, `--` before paths, a timeout, a Cancel button that kills the process and a
  memory cap. Apple's `/usr/bin/git` stub is never executed (it would open an installer dialog) — the
  real binary is resolved first. No forcing flag (`--force`, `--force-with-lease`, `--delete`,
  `--mirror`, `--all`, `--tags`) can be emitted, and an option-looking remote or branch name is refused
  before a process starts. `GitController` owns the snapshot, debounces the refresh trigger burst,
  never polls, and discards a late result from a previous directory.
- **Documentation.** The README gained a "Source Control (Git)" media block with
  `docs/media/git-panel.png`, a real capture of the Release build. `ARCHITECTURE.md` documents the Git
  status path end to end, and the three diagrams were corrected (v1.6.0+11, 26 phases, 31 services, the
  real `Process` transport, inline icons instead of emoji).

## Requirements

- macOS 12+ (Monterey or later)
- `git` for the Source Control panel (Xcode Command Line Tools or Homebrew). Without it the panel says
  so and nothing else in the IDE changes.
- Dart SDK / Flutter for Dart
- `clangd` for C/C++ language server and `clang` + `lldb` for debugging
- `pyright` or `pylsp` for Python language server
- Apple Silicon Mac for ARM64 Assembly assembly & debugging

## Known Limitations

- There is **no conflict editor**: a conflicted path is listed but its Stage button is disabled until
  you resolve it in a terminal. There is no history/branch browser and no discard — those are
  deliberately out of scope for this release.
- The panel reloads tabs after a pull, but it does not watch the disk while you edit (external changes
  are picked up when you pull, save or switch tabs).
- Caret blink speed is 500 ms (Flutter default).
- Build is unsigned and unnotarized (requires right-click -> Open, or System Settings -> Privacy &
  Security -> Open Anyway, on first launch). From a terminal the same is one command:
  `xattr -dr com.apple.quarantine "/Applications/Classic Code Editor.app"`.

## Verification

- `flutter analyze` — clean (0 issues).
- `flutter test` — **671 pass**, 8 opt-in/real-process tests skipped by design.
- Release gate in order: `01_analyze` → `02_test` → `03_build_macos` → `04_launch_smoke` (alive after
  8 s) → `05_make_dmg`.
- DMG: 22,568,204 bytes, `hdiutil verify` valid,
  SHA-256 `2f59a4c62433ebdb65ab1f860bd30c18e31f75488106132e8b5aef3b27638448`.

## Install

1. Download `Classic.Code.Editor-1.6.0+11.dmg` (universal build) below — the built file is
   `Classic Code Editor-1.6.0+11.dmg`; GitHub replaces the spaces with dots, and the bytes are identical.
2. Drag **Classic Code Editor** into `Applications`.
3. First launch: right-click the app → **Open** (the build is unsigned and not notarized), then confirm.
