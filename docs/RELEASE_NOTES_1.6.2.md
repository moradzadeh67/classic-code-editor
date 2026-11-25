# Classic Code Editor — v1.6.2 release notes

**A small maintenance release: the completion popup stops getting in your way, and interpolated variables get their own color.**

No new menus, no new dependencies. The changes are in how the completion popup behaves while you type.

## Changes

- **The autocomplete popup no longer pre-selects its first suggestion.** A stray `Enter` or `Tab` used to
  insert a symbol you never picked. Now the list opens with nothing highlighted: `↓` selects the first row,
  `↑` the last, `Tab` highlights the first row and the next `Tab` accepts it, `Escape` dismisses, and a bare
  `Enter` types a newline. The documentation panel appears once a row is highlighted.
- **No suggestions inside an empty `{}` or `()`.** Right after `{}`, `{ }`, an auto-indented `{` + newline,
  or an auto-paired `()` / `foo(`, the popup waits for the first character instead of listing every keyword.
  Typing a prefix (`{pri`, `print(pri`) completes as before. This applies to every language.
- **Accepting a function no longer types its parameter list.** `print` used to become `print(Object? object)`.
  It now becomes `print()` with the caret between the parentheses. Snippets with real code keep their body
  (`setState(() { … })`), and declaration snippets such as `stless` keep their defaults.

## Fixes

- **String interpolation variables are colored as variables.** In `'I am $name, $age years old'`, `$name` and
  `$age` used to share the string color. They now use the variable color, so they stand out from the text.

## Requirements

- macOS 12+ (Monterey or later)
- Dart SDK / Flutter for Dart
- `clangd` for the C/C++ language server, `clang` + `lldb` for debugging
- `pyright` or `pylsp` for the Python language server
- Apple Silicon Mac for ARM64 Assembly & debugging
- `git` only for the Source Control panel

## Known Limitations

- There is still no language server for ARM64 Assembly (`LSP: Off`); completion there is the offline
  AArch64 list, offered from three typed characters.
- The build is unsigned and not notarized (needs a paid Apple Developer account): first launch requires
  **System Settings → Privacy & Security → Open Anyway**, or one command from a terminal:
  `xattr -dr com.apple.quarantine "/Applications/Classic Code Editor.app"`.

## Verification

- `flutter analyze` — clean (0 issues).
- `flutter test` — **693 pass**, 8 opt-in/real-process tests skipped by design.
- Release gate in order: `01_analyze` → `02_test` → `03_build_macos` → `04_launch_smoke` (alive after
  8 s) → `05_make_dmg`. All five passed.
- DMG: 21,723,077 bytes, `hdiutil verify` valid,
  SHA-256 `1a9dbd08660b59118493303ac71adba544ee0fb8cb2f4ea68a1d7a31cd0ab9a4`.

## Install

1. Download `Classic.Code.Editor-1.6.2+13.dmg` from the release page — the built file is
   `Classic Code Editor-1.6.2+13.dmg`; GitHub replaces the spaces with dots, and the bytes are identical.
2. Drag **Classic Code Editor** into `Applications`.
3. First launch: right-click the app → **Open** (the build is unsigned and not notarized), then confirm.

Upgrading? Quit the old app and replace it in `Applications`; settings, theme, the recent files list and
the remembered project folder live in `~/Library/Application Support/com.moradzadeh67.classicCodeEditor`
and are kept.
