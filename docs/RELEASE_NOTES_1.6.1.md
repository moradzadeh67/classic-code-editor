# Classic Code Editor — v1.6.1 release notes

**A maintenance release: the same app, with three things that only broke once it left the IDE fixed.**

No new features, no new dependencies, no changed menus. If 1.6.0 worked for you, nothing here changes
it; if a downloaded copy misbehaved, this is the build to use.

## Fixes

- **Completion inside the installed `.app`.** A copy opened from Finder, Launchpad or `/Applications`
  starts with `Directory.current == "/"` and launchd's minimal `PATH`. The language servers were rooted
  there, spent minutes indexing the whole filesystem (94 % CPU) and never answered a completion in
  time, so the popup stayed empty — while `flutter run`, which inherits the project directory, looked
  fine. The servers are now rooted at **the project folder** (or, with no folder open, at the active
  file's folder, and otherwise at the per-user temp folder — never `/`, never `$HOME`) *before* the
  first document is opened, and re-rooting a warm server stays a no-op while the file already belongs
  to it.
- **`dart` / `clangd` / `pyright-langserver` are found outside a terminal.** The binaries are resolved
  through your login shell and the common install locations (the Dart next to your `flutter` wins),
  the resolved `PATH` is handed to every child process, and the status-bar tooltip plus the Console
  hint now list every location that was tried when one is missing.
- **A slow server no longer looks like a missing feature.** The local keyword list appears after
  700 ms and is replaced by the server's answer when it arrives, instead of an empty popup for up to
  20 seconds.
- ***Open File*, *Save As* and *Open Folder* did nothing at all.** `file_picker` 13 (macOS part
  `file_picker_darwin`) refuses to build a panel without
  `com.apple.security.files.user-selected.read-only`/`.read-write`, sandbox or not, and turns that
  refusal into a silent `null` — a cancelled dialog and a refused one looked identical. Both
  entitlements files now declare `user-selected.read-write`, and the picker's documented
  `skipEntitlementsChecks()` runs before each panel so the dialogs open even if a configuration drops
  the key. The App Sandbox itself stays **off**: the IDE must still spawn `dart`, `clang` and `lldb`.
- **ARM64 Assembly stops offering Dart keywords.** An `.s` buffer has no language server, so the
  offline list used to fall through to the Dart branch (`cl` → `class`). It now speaks AArch64:
  `mov`/`movz`/`movk`, `ldr`/`ldp`/`ldrb`, `stp`, `add`/`subs`, `adrp`, `cbz`/`tbz`, `csel`, SIMD
  `ld1`/`zip1`/`tbl`, `paciasp`/`autiasp`, and the special registers `sp`/`wsp`/`xzr`/`wzr`/`lr`/`fp`/`pc`.

## Requirements

- macOS 12+ (Monterey or later)
- Dart SDK / Flutter for Dart
- `clangd` for the C/C++ language server, `clang` + `lldb` for debugging
- `pyright` or `pylsp` for the Python language server
- Apple Silicon Mac for ARM64 Assembly & debugging
- `git` only for the Source Control panel

## Known Limitations

- There is still no language server for ARM64 Assembly (`LSP: Off`); completion there is the offline
  AArch64 list above, offered from three typed characters.
- With a project folder open, a file opened from *Open Recent* in a **different** project keeps the
  servers rooted at the open folder, so that file is analyzed without its own package context. Opening
  the other project (or closing the folder) re-roots them.
- Caret blink speed is 500 ms (Flutter default).
- The build is unsigned and not notarized (needs a paid Apple Developer account): first launch requires
  **System Settings → Privacy & Security → Open Anyway**, or one command from a terminal:
  `xattr -dr com.apple.quarantine "/Applications/Classic Code Editor.app"`.

## Verification

- `flutter analyze` — clean (0 issues).
- `flutter test` — **678 pass**, 8 opt-in/real-process tests skipped by design.
- Release gate in order: `01_analyze` → `02_test` → `03_build_macos` → `04_launch_smoke` (alive after
  8 s) → `05_make_dmg`.
- Manually, on the installed Release bundle launched with a launchd-shaped environment
  (`cd / && env -i HOME=… PATH=/usr/bin:/bin:/usr/sbin:/sbin`): the Dart language server starts with
  its working directory at the project folder (temp folder when no project is open) and **0.0 % CPU**
  instead of `/` and 94 %, and *Open Folder* opens its sheet with no `[FilePickerDarwin]` error.
- DMG: 21,719,348 bytes, `hdiutil verify` valid,
  SHA-256 `8ccb96e85f96e12ae9ff1fc678e120be473e3a8e907d5bcd6fee84e66d1b664c`.

## Install

1. Download `Classic.Code.Editor-1.6.1+12.dmg` (universal build) below — the built file is
   `Classic Code Editor-1.6.1+12.dmg`; GitHub replaces the spaces with dots, and the bytes are identical.
2. Drag **Classic Code Editor** into `Applications`.
3. First launch: right-click the app → **Open** (the build is unsigned and not notarized), then confirm.

Upgrading from 1.6.0? Quit the old app and replace it in `Applications`; settings, theme, the recent
files list and the remembered project folder live in
`~/Library/Application Support/com.moradzadeh67.classicCodeEditor` and are kept.
