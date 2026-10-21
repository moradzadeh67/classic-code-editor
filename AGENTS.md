# AGENTS.md — classic_code_editor

## Project Identity
- Name: classic_code_editor (Classic Code Editor)
- Platform: macOS ONLY (Flutter Desktop)
- Style: Retro 1990s (Borland C++, Visual C++ 6, Windows 95/98)
- Language: Dart
- Framework: Flutter
- Themes (3): VC++ 6.0 (gray), Borland Delphi (beige), Visual Basic 6.0
- UI metrics are tuned to authentic Windows 9x / Delphi 6 (96-DPI) values.

## Critical Rules

### Rule 1: One Task at a Time
- Only implement what is described in the CURRENT task
- Do NOT jump ahead to future phases
- Do NOT add features that are not in the current task
- After completing a task, STOP and report

### Rule 2: Architecture Compliance
- UI widgets NEVER call Dart SDK or Process directly
- All SDK interaction goes through Services layer
- Follow the file structure below exactly
- Every new file must be in the correct folder

### Rule 3: Retro Design
- NO rounded corners anywhere (`BorderRadius.zero`) — this applies to every
  INTERNAL widget (buttons, panels, status bar, console, editor, menus).
  The macOS window chrome corners are system-level and stay rounded.
- Buttons must have a 3D raised/sunken effect (see `RetroBorder`)
- Fonts: Arial for UI labels, monospace (Menlo) for the code editor
- All borders are 2px, sharp, no BoxShadow
- Colors come from `ThemeService` (NOT hardcoded)
- Four themes: VC++ 6.0, Borland Delphi, Visual Basic 6.0, Turbo Pascal 7.0
- Vertical UI metrics (px): menu bar 24, toolbar 28, button 22 (fixed), status bar 24

### Rule 4: No Fabrication
- If something does not work, say so
- Do not invent APIs or packages
- Do not guess file paths
- If unsure, ask before implementing

### Rule 5: Code Quality
- Follow Dart naming conventions
- Add doc comments to public classes and methods
- No empty catch blocks
- Handle errors explicitly

### Rule 6: Dependencies
- Do NOT add new packages without explicit approval
- Current approved packages are listed in ARCHITECTURE.md
- If you think a new package is needed, PROPOSE it first, do not add it

### Rule 7: Respect .aiexclude
- Read .aiexclude before scanning project
- NEVER read/modify files in excluded paths
- Only work with: lib/, test/, pubspec.yaml, README.md, AGENTS.md, ARCHITECTURE.md, TASKS.md, ROADMAP.md

### Rule 8: Theme-aware rebuilds (important)
- Do NOT mark a widget that renders theme-dependent content as `const`
- A canonicalized `const` widget is the *same instance*, so Flutter skips its
  `build()` and theme changes go stale
- Wrap such subtree roots in `ListenableBuilder(listenable: ThemeService.instance)`
  and keep their children NON-const

### Rule 9: Editor rows are pinned by the strut
- Every line must render exactly `EditorMetrics.lineHeight`; the gutter
  `itemExtent`, the current-line band, scrolling and click-to-line mapping all
  assume it
- Keep `forceStrutHeight: true` for **every** font. Unforced, the row height
  follows the fallback font of whichever glyph is on the line (a Persian string
  literal grows it by 1-2 px) and the code drifts away from the numbers
- Never "calibrate" the strut factor per font: `TextPainter.height` floors the
  strut halves while `RenderEditable` rounds `fontSize * height`. Assert on a
  real `EditableText` (`editor_font_fallback_drift_test.dart`) and verify in the
  running app with `flutter run -d macos -t tool/probe_font_drift.dart` —
  `flutter_tester` has no system fonts, so a green suite proves nothing here
- `View > Font` rows must be built when the popup opens (not in `build()`),
  or the check mark goes stale

### Rule 10: Vertical layout is derived from the renderer, never predicted
- Gutter rows come from `_rowsFromRenderer()` (caret travel for the row
  *count*, caret position for each logical line). Do **not** re-introduce a
  character-count or `TextPainter` wrap prediction as the model: Persian glyphs
  come from the fallback font and are wider than a measured monospace advance,
  so a line counted as one row renders as two and every number below it is off
- That measurement runs in a post-frame pass and must **never give up
  silently**: retry while the editable is absent or `debugNeedsLayout`, and
  reject any result with fewer rows than logical lines (a stale layout)
- The current-line band is `row * lineHeight` (a grid row) and spans every row
  of the logical line. Do not position it from `caretRect.top`: Flutter inflates
  that rect ~1px above its line box, which puts the highlight above the numbers
- Continuation rows (`rows[i] == 0`) are inert: no number, no breakpoint, never
  the paused line
- The status bar's `Ln/Col` comes from `onCaretChanged`; it is live, not a
  placeholder
- `flutter_tester` always has a clean layout after `pump`, so the first-frame
  races can only be seen in the app:
  `flutter run -d macos -t tool/probe_click_line.dart` and
  `flutter run -d macos -t tool/probe_baseline.dart`

### Rule 11: Debugger Architecture
- Debugger classes extend `BaseDebugger` and NEVER touch the UI or the runner
  directly
- All debugging activity is surfaced through the broadcast `output` stream;
  `IDEShell` forwards every line to `LanguageRunnerService.emitOutput`, the
  stream `ConsolePanel` listens to
- Language dispatch goes through `DebuggerFactory` — the shell must not switch
  on file extensions itself
- Debuggers must short-circuit real process spawns under `FLUTTER_TEST` via
  `DebuggerEnvironment`, so the unit suite never launches `dart`, `python`,
  `clang` or `lldb`
- An opt-in gate (`BORLAND_REAL_*_TEST=1`) is **not** enough for a real-process
  test: it must also set `DebuggerEnvironment.allowRealProcesses = true` in
  `setUp` and restore it in `tearDown`, or the debugger short-circuits and the
  test asserts against `state == running` forever
- **Never write to lldb's stdin directly.** Everything goes through
  `LldbCommandQueue` (`enqueueLldbUnit`), because lldb's stdin is a pipe and
  splits lines wherever it happens to be reading: a command written during the
  stop report arrived as `b` + `reakpoint set -a 0x…` and the breakpoint was
  silently lost. Each non-resuming command is verified with a
  `script print("@@ACK n")` sentinel; a lost ack retries the unit **once**, so a
  unit must be idempotent (delete your own breakpoint ids before adding them)
- `Stop` owns the kill order: `process kill` -> `quit` -> wait 2 s -> SIGKILL
  lldb -> SIGKILL the inferior pid parsed from `Process <pid> launched`. Killing
  lldb alone leaves `borland_*_exec` running; `lldb_session_lifecycle_test`
  asserts `pgrep` is empty afterwards

## File Structure (MUST follow)

```text
lib/
├── main.dart
├── app.dart
│
├── ui/
│   ├── retro/ ← Retro design system widgets
│   │   ├── retro_colors.dart        (delegates to ThemeService)
│   │   ├── retro_border.dart        (raised/sunken/flat, BorderRadius.zero)
│   │   ├── retro_button.dart        (fixed 22px, Arial 12/w500)
│   │   ├── retro_panel.dart
│   │   ├── retro_theme.dart         (ThemeData + global TextTheme)
│   │   ├── syntax_colors.dart       (per-theme syntax palette)
│   │   ├── language_logo.dart       (per-language icon + vector fallback)
│   │   ├── retro_about_dialog.dart  (showRetroAboutDialog — 3 tabs)
│   │   └── retro_watch_window.dart  (variables watch window)
│   │
│   ├── shell/ ← IDE shell
│   │   ├── ide_shell.dart           (layout + theme-aware rebuild root)
│   │   ├── retro_menu_bar.dart      (24px, File/Edit/View/Run/Tools/Help)
│   │   ├── retro_toolbar.dart       (28px, New/Open/Save/Run/Stop + theme selector)
│   │   ├── retro_status_bar.dart    (24px)
│   │   ├── panel_layout.dart        (explorer + editor + bottom panel)
│   │   ├── vertical_splitter.dart
│   │   └── horizontal_splitter.dart
│   │
│   ├── editor/ ← Editor surface
│   │   ├── code_editor_panel.dart   (editor + gutter: lines, breakpoints, ▶)
│   │   ├── editor_metrics.dart      (font-size driven metrics)
│   │   ├── tab_bar.dart             (multi-file tab strip)
│   │   ├── autocomplete_popup.dart  (LSP + offline completion popup)
│   │   └── hover_tooltip.dart       (LSP hover docs)
│   │
│   ├── console/ ← ConsolePanel (program + debug output)
│   ├── terminal/ ← TerminalPanel (integrated shell)
│   ├── analyzer/ ← DiagnosticsPanel
│   ├── debugger/ ← variables / call stack / breakpoints panels
│   └── explorer/ ← File explorer panel
│
├── services/ ← Business logic, SDK interaction
│   ├── theme_service.dart           (4 themes + persistence)
│   ├── session_service.dart         (open tabs + 10-entry MRU, session.json)
│   ├── file_service.dart            (open/save, multi-tab, format-on-save)
│   ├── dart_runner_service.dart     (execute Dart code)
│   ├── language_runner_service.dart (run/compile Dart/Python/C/C++/ARM64 + output stream)
│   ├── analyzer_service.dart        (static analysis fallback)
│   ├── lsp_service.dart             (Dart language server over stdio)
│   ├── terminal_service.dart        (shell commands)
│   ├── editor_settings_service.dart (font-size persistence + ChangeNotifier)
│   ├── debug_service.dart           (live variable watcher)
│   ├── base_debugger.dart           (abstract debugger contract + output stream)
│   ├── dart_debugger.dart           (Dart VM Service debugger)
│   ├── python_debugger.dart         (Python sys.settrace debugger)
│   ├── c_debugger.dart              (C/C++ clang + lldb debugger)
│   ├── asm_debugger.dart            (ARM64 assembly debugger: registers + step-inst)
│   ├── debugger_factory.dart        (language → debugger dispatch)
│   ├── debugger_manager.dart        (active debugger follows the active tab)
│   ├── debugger_snapshot.dart       (shared stop-payload decoder)
│   └── debugger_environment.dart    (FLUTTER_TEST real-process gate)
│
├── models/ ← Pure Dart data classes
│   ├── tab_file.dart
│   ├── diagnostic.dart
│   ├── lsp_models.dart
│   ├── language_config.dart
│   └── debugger_models.dart
│
└── utils/ ← Helpers, constants
    ├── app_shortcuts.dart
    ├── completion_filter.dart
    ├── dart_highlighter.dart
    ├── json_rpc_client.dart
    ├── line_edit.dart               (pure: duplicate line / selection)
    ├── multi_language_highlighter.dart
    ├── toggle_comment.dart          (pure: line comments per language)
    └── vm_service_client.dart

assets/
├── icons/                           (toolbar + file-type icons)
├── branding/                        (app mark)
└── fonts/                           (bundled editor fonts, see below)
    ├── RecursiveMonoCslSt-{Regular,Bold,Italic,BdItalic}.ttf
    └── OFL.txt                      (SIL OFL 1.1 — ship with the fonts)
```

`assets/fonts/` holds the four static Recursive Mono Casual faces declared in
`pubspec.yaml` under the family alias `RecursiveMonoCasual` (OFL 1.1; never
redistribute a face without `OFL.txt`). Menlo is a macOS system font and is
**not** bundled. `EditorFontFamily` offers exactly two faces (`menlo`,
`recursive`); adding a third means updating the enum, the View > Font rows, the
font tests and this file. Details: `THIRD_PARTY_NOTICES.md`, README > Fonts and
licensing. Font drift is measured on the real app with
`flutter run -d macos -t tool/probe_font_drift.dart`.
