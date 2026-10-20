# Changelog

All notable changes to Classic Code Editor are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **ARM64 Assembly Address-to-Line Mapping (`Arm64AsmParser` / `AsmDebugger`)** — parses hand-written `.s` files into 4-byte instruction offset maps relative to `_main`/`main`, enabling precise line breakpoints via `breakpoint set -n main -R <offset>` and accurate pause tracking (`▶`) and register inspection on any line.
- Turbo Pascal + ARM64 Assembly screenshots (`assets/screenshots/tp-editor|tp-debugger|tp-terminal.png`)
  in the README gallery, and refreshed architecture diagrams (SVG sources + PNG exports).

### Fixed
- Saving a **Dart** file spawned a second copy of the IDE instead of the formatter: `_formatCode`
  started `Platform.resolvedExecutable` (the app binary inside a packaged `.app`), which opened an
  empty black "Classic Code Editor" window and left the file unformatted. It now runs `dart format`
  from `PATH`, like `clang-format` and `black`.
- Save As no longer opens the extra un-themed panel window (`FileType.any`, panel deferred to the next
  frame).

### Added
- **Unsaved-changes guard** — closing a modified tab (the tab's ✕, `Cmd + W`, File > Close Tab) or
  quitting (`Cmd + Q`, the red window button, File > Exit) asks `Save changes to <name>?` with
  Save / Don't Save / Cancel. One shared helper (`lib/ui/shell/close_guard.dart`) drives all paths;
  a cancelled or failed Save As counts as Cancel; only the active window's cancel aborts quitting.
- **Edit menu + shortcuts** — Select All (`Cmd + A`), Go to Line (`Cmd + L`), Toggle Comment
  (`Cmd + /`), Duplicate Line (`Cmd + Shift + D`), plus `Cmd + O` (Open) and `Cmd + W` (Close Tab).
  Go to Line uses a retro number prompt, `EditorMetrics` line height and the wrap-aware visual row,
  and gives focus back to the editor. Toggle Comment reads the language's `commentPrefix`
  (`//` Dart/C/C++/ASM, `#` Python) and is a no-op for unknown languages.
- **Session restore + recent files** — new `SessionService` writes `session.json` (open paths, active
  path, 10 most recent files) in Application Support; tabs reopen on launch (missing files skipped,
  untitled buffers never restored) and the File menu shows a numbered MRU block with
  "Clear Recent Files".
- **Retro menu chrome** — `RetroMenuItem` / `RetroMenuSeparator` / `RetroPopupShape`: 22px rows,
  shortcut column sized from the real text, check mark on the active theme, etched separators,
  full-width `menuActive` highlight for both hover and keyboard focus.
- New tests: `retro_menu_bar_test.dart`, `unsaved_guard_test.dart`, `toggle_comment_test.dart`,
  `session_service_test.dart`. Suite: **230 tests** (1 opt-in skipped).

### Changed
- README/ARCHITECTURE/AGENTS/PRIVACY document the session file and the new editor commands.

## [1.3.0] — 2026-10-19

### Added
- **ARM64 Assembly (`.s`) support** — a fifth language, end to end:
  - `language_config.dart`: `.s` → *ARM64 Assembly*, `clang -g -arch arm64`, highlight language `armasm`.
  - `multi_language_highlighter.dart`: a purpose-built `arm64Asm` grammar (AArch64 registers
    `x0`..`x30` / `w0`..`w30` / `sp` / `fp` / `lr` / `pc` / `xzr` / `wzr` / `cpsr`, `//` and `/* */`
    comments, `.directives`, labels, `#immediates`) — `highlight` 0.7's own `armasm` mode targets
    32-bit ARM and has neither the 64-bit registers nor `//` comments. No new package.
  - `language_runner_service.dart`: Run assembles and executes `.s` sources, gated on
    Apple Silicon (`uname -m == arm64`).
  - `asm_debugger.dart` (new): `AsmDebugger extends CDebugger` — assembles with
    `clang -g -arch arm64`, installs a dedicated LLDB stop-hook that reports the register file
    (`x0`..`x28`, `fp`, `lr`, `sp`, `pc`, `cpsr`) as Variables and a one-instruction disassembly,
    and maps Step Into/Over/Out to `thread step-inst` / `thread step-inst-over` / `thread step-out`.
  - `debugger_factory.dart`: dispatch for `.s` (four debuggers now).
  - `assets/icons/asm.png` (new): blue heptagon `ASM` logo in the editor header, with a vector
    fallback painter; `panel_layout.dart` also detects `.s` and sniffs assembler directives.
  - `samples/hello_arm64.s` (new) — runnable sample that sums 1..5 and prints via `_puts`.
  - *ARM64 Assembly* added to the manual language dropdown.
- **Fourth theme: Turbo Pascal 7.0** — DOS navy desktop, gray 3D dialogs and cyan menu highlight;
  selectable from the View menu and the toolbar theme dropdown, persisted like the other three.
  The editor surface and syntax palette stay identical to the other themes by design.
- **Current-line highlight** — the caret's row is tinted full-width with a hairline outline, its
  gutter number is emphasised, and clicking the empty space past the end of a line selects that row.
- Tests: `asm_debugger_test.dart`, `highlighter_asm_test.dart`, `language_runner_asm_test.dart`,
  `editor_current_line_test.dart`, `language_logo_test.dart`, `integration/asm_debug_test.dart`
  (opt-in, `BORLAND_REAL_ASM_TEST=1`). Suite: **204 tests** (1 opt-in skipped).

### Changed
- **Gutter layout:** line numbers moved to the left of the gutter and 10px reserved on the right for
  the gutter's own scrollbar, so the numbers and the slider can no longer overlap.
- **Breakpoint bullet** is now a painted dot at `0.7 × lineHeight` — roughly twice the size of the
  old `●` glyph — while still fitting inside one row.
- **Debugger sidebar only opens while debugging**: `PanelLayout` shows it for a `running`/`paused`
  session instead of "any debugger that has breakpoints", and `PanelLayout` now listens to the
  active debugger so it opens/closes with the session.
- `EditorSettingsService` resolves its settings file once and writes synchronously afterwards;
  this removes an ordering race where a queued async save could land after the file was rewritten.
- `pubspec.yaml` version bumped to `1.3.0+5`.
- Documentation refreshed: `README.md`, `ARCHITECTURE.md`, `TASKS.md`, `docs/PHASE_DETAILS.md`,
  `docs/DEBUGGING.md`, `docs/RELEASE.md`, `docs/RETRO_DESIGN.md`.

## [1.2.0] — 2026-10-18

### Added
- Editor zoom service (`EditorSettingsService`) with persistence (`editor_settings.json`) via `path_provider`.
- `EditorMetrics` pure value class for font-size-driven line height, gutter width, marker sizes, and text/strut styles.
- Dynamic editor panel (`code_editor_panel.dart`) that reacts to font-size changes with cache invalidation.
- Gutter alignment regression tests across sizes {8, 13, 20, 32} (`gutter_alignment_test.dart`).
- Editor zoom interaction tests (`editor_zoom_test.dart`): breakpoint toggle, paused-line arrow, and zoom-while-paused.
- Keyboard zoom shortcuts (`Cmd +` / `Cmd -` / `Cmd 0`) wired through `app_shortcuts.dart` and `ide_shell.dart`.
- View-menu font-size items (`font_increase`, `font_decrease`, `font_reset`) in `retro_menu_bar.dart`.
- About-dialog shortcuts tab updated with zoom shortcuts (`retro_about_dialog.dart`).

### Changed
- Updated documentation (`README.md`, `ARCHITECTURE.md`, `TASKS.md`, `AGENTS.md`) for Phase 18 features.
- `pubspec.yaml` version bumped to `1.2.0+4`.

## [1.1.0] — 2026-10-14

### Fixed
- Fixed code editor gutter line numbers drifting out of alignment with rendered code lines on wrapped lines, long files, and narrow window widths:
  - Accounted for `letterSpacing: 0.5` inherited from Material `bodyLarge` / `titleMedium` in character advance measurements.
  - Replaced the `fontSize * 0.62` character-width estimate in `_gutterRows` with exact, style-measured character advances (`_charAdvance`).
  - Applied `editorStrutStyle` to gutter line numbers so digits sit precisely on the code's baseline across desktop and mobile typography.
  - Added a comprehensive multi-width (420px–1600px) and multi-platform (macOS/Android) regression test suite verifying line number positioning against actual editor caret positions.

### Added
- `docs/RELEASE.md`, `docs/PRIVACY.md`, `SECURITY.md` and this changelog.
- CI workflow (`ci.yml`): `flutter analyze` + `flutter test` on every push and PR to `main`.
- A crawlable project site on GitHub Pages (landing page with download links, screenshots and metadata).
- Demo GIF in the README, captured from the running macOS app.

### Changed
- Refined editor syntax palette across all themes and languages: keywords updated to `#C842F5` (bold), operators to `#00BF69` (bold), and comments to `#596E48` (italic). Added backslash (`\`) and backtick (`` ` ``) to operator symbol patching.
- README restructured: "What is Classic Code Editor?", Demo, Key Dependencies, Privacy & Security,
  Build & Release, CI/CD, Known Limitations, FAQ and Requirements; badges upgraded and a CI badge added.
- Leftover template bundle id for the test target fixed
  (`com.example.borlandDart.RunnerTests` → `com.moradzadeh67.classicCodeEditor.RunnerTests`).

### Notes
- A maintenance release for the macOS app: refreshed documentation and a rebuilt universal DMG.
- No application-source changes that affect runtime behaviour.

## [1.0.1] — 2026-10-13

### Fixed
- LSP stale diagnostics bug.

### Added
- Custom branding: logo, app icon, README banner and social preview.
- 6 new tests (113 → 119 passing).
- Development Environment section in the README.

## [1.0.0] — 2026-10-13

First public release.

### Added
- 🎨 Three authentic retro themes — VC++ 6.0, Borland Delphi, Visual Basic 6.0.
- ⌨️ Multi-language editor — Dart, Python, C, C++ (syntax highlighting + completion).
- 🧠 Real LSP integration — live diagnostics, hover and autocomplete.
- 🐛 Real debuggers — Dart VM Service, Python `sys.settrace`, C/C++ via `clang` + `lldb`, with
  breakpoints and variable inspection.
- 🖥️ Integrated terminal and console, with a debug-output bridge.
- ✅ 113 tests passing on a fully offline test suite.
- macOS DMG packaging (`scripts/release_gate/`).
