# Changelog

All notable changes to Classic Code Editor are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

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
