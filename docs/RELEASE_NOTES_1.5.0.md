# Classic Code Editor — v1.5.0 release notes

**Complete language intelligence, rich retro workspace, gutter diagnostics, per-tab language control, and Finder launch fixes.**

## Highlights

- **Autocomplete & IntelliSense:** Triggers on `.` and 1st character for LSP-backed files; manual trigger via `Ctrl+Shift+Space` (or Edit > Trigger Completion); `Tab` accepts suggestions; function calls insert `()` with caret placed inside; LSP snippets expanded (`$0`, `$1`); built-in Dart/Flutter snippets (`stless`, `stful`, `main`, etc.); ranked by match tier + MRU; documentation panel appears after 2 s idle; auto-imports unimported libraries (e.g. `Timer` -> `import 'dart:async';`); LSP kind badges (M/F/C/V/K...) with details; popup anchored to caret inside editor.
- **Diagnostics:** No stale or phantom errors; error/warning counts return cleanly to 0 for empty files; language server and diagnostics follow the active tab's effective language.
- **Gutter & Editor Polish:** Gutter error/warning markers with hover tooltips, 1px retro sunken separator line, bold current line number; 5px thicker caret; `#fbfbf9` near-white surface shared with Console; Colorful syntax scheme (operators `#687d01`, curly braces `#1e64d8`, square brackets `#00796f`, comments `#666666`, strings `#409175`); retro right-click context menu (Cut/Copy/Paste/Select All).
- **Workspace & Navigation:** File Explorer (`Cmd+Shift+O`, Open Folder, lazy tree, double-click to open file), `+` new tab button, per-tab language selection dropdown, mismatch protection prevents compiling mismatched files, every launch starts with a fresh empty Untitled tab.
- **Finder Launch & Executable Resolution Fixes:** Immediate editor focus on launch; tool binary resolution via user's login shell (`zsh -lic` / `-lc`, Homebrew, Dart SDK, Flutter) when launched from macOS Finder.
- **Documentation & media:** README now opens with a 12 s inline-completion walkthrough (`docs/media/autocomplete.gif`) and adds an Explorer-with-tabs screenshot and a Dart buffer with its Console output (`docs/media/explorer-tabs.png`, `docs/media/colorful-dart.png`).

## Requirements

- macOS 12+ (Monterey or later)
- Dart SDK / Flutter for Dart
- `clangd` for C/C++ language server and `clang` + `lldb` for debugging
- `pyright` or `pylsp` for Python language server
- Apple Silicon Mac for ARM64 Assembly assembly & debugging

## Known Limitations

- Caret blink speed is 500 ms (Flutter default).
- Build is unsigned and unnotarized (requires right-click -> Open, or System Settings -> Privacy & Security -> Open Anyway, on first launch). From a terminal the same is one command: `xattr -dr com.apple.quarantine "/Applications/Classic Code Editor.app"`.

## Verification

- `flutter analyze` — clean (0 issues).
- `flutter test` — **520 pass**, 8 opt-in/real-process tests skipped by design.

## Install

1. Download `Classic Code Editor-1.5.0+10.dmg` (universal build) below.
2. Drag **Classic Code Editor** into `Applications`.
3. First launch: right-click the app → **Open** (the build is unsigned and not notarized), then confirm.
