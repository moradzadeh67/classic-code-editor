# Changelog

All notable changes to Classic Code Editor are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.1.0] — 2026-10-14

### Added
- `docs/RELEASE.md`, `docs/PRIVACY.md`, `SECURITY.md` and this changelog.
- CI workflow (`ci.yml`): `flutter analyze` + `flutter test` on every push and PR to `main`.
- A crawlable project site on GitHub Pages (landing page with download links, screenshots and metadata).
- Demo GIF in the README, captured from the running macOS app.

### Changed
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
