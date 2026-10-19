# Classic Code Editor — v1.3.0 release notes

**A retro IDE that now speaks Assembly, wears a fourth theme, and protects your unsaved work.**

## Highlights

- **ARM64 Assembly (`.s`) end to end** — purpose-built AArch64 grammar (64-bit registers, `//` comments,
  labels, directives), Run via `clang -arch arm64`, and a real LLDB debugger that lists the register file
  (`x0`..`x28`, `fp`, `lr`, `sp`, `pc`, `cpsr`) as Variables plus a one-instruction disassembly, with
  instruction-level stepping.
- **Turbo Pascal 7.0 theme** — DOS-blue desktop, gray-cyan Turbo Vision chrome and a cyan line-number
  column. Four authentic themes now, with the same syntax palette everywhere.
- **Unsaved-changes guard** — closing a modified tab (✕, `Cmd + W`, File › Close Tab) asks
  Save / Don't Save / Cancel; a cancelled Save As counts as Cancel.
- **Session restore + recent files** — your tabs and a 10-entry `File › Open Recent` list come back on
  launch (`session.json` in Application Support; buffer contents are never stored).
- **New editing commands** — Select All, Go to Line (`Cmd + L`), Toggle Comment (`Cmd + /`),
  Duplicate Line (`Cmd + Shift + D`), `Cmd + O`, `Cmd + Shift + S`.
- **Polished retro menus** — 22px rows, right-aligned shortcut column, ✓ on the active theme, etched
  separators, hover *and* keyboard highlight.

## Fixes

- Saving a Dart file no longer spawns a second IDE window (the formatter now runs `dart format` from
  `PATH` instead of the app binary).
- Save As no longer opens an extra un-themed panel window.
- Editor settings writes are deterministic after the first path resolve.

## Requirements

- macOS 12+ (Monterey or later); **Apple Silicon** for the ARM64 Assembly support.
- `dart`, `python3`, `clang` and `lldb` on `PATH` for Run/Debug (Xcode Command Line Tools provide
  `clang`/`lldb`).
- The `.dmg` is **unsigned and not notarized**: on first launch use right-click › Open (or
  *System Settings › Privacy & Security › Open Anyway*).

## Tests

`flutter analyze` is clean and the offline suite is **230 tests** (1 opt-in integration test skipped;
`BORLAND_REAL_VM_TEST=1` and `BORLAND_REAL_ASM_TEST=1` enable the real-process runs).
