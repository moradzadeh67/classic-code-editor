# AGENTS.md — borland_dart

## Project Identity
- Name: borland_dart (RetroDart IDE)
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
- Three themes: VC++ 6.0, Borland Delphi, Visual Basic 6.0
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
- Only work with: lib/, test/, pubspec.yaml, AGENTS.md, ARCHITECTURE.md, TASKS.md, ROADMAP.md

### Rule 8: Theme-aware rebuilds (important)
- Do NOT mark a widget that renders theme-dependent content as `const`
- A canonicalized `const` widget is the *same instance*, so Flutter skips its
  `build()` and theme changes go stale
- Wrap such subtree roots in `ListenableBuilder(listenable: ThemeService.instance)`
  and keep their children NON-const

### Rule 9: Debugger Architecture
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
│   ├── theme_service.dart           (3 themes + persistence)
│   ├── file_service.dart            (open/save, multi-tab, format-on-save)
│   ├── dart_runner_service.dart     (execute Dart code)
│   ├── language_runner_service.dart (run/compile Dart/Python/C/C++ + output stream)
│   ├── analyzer_service.dart        (static analysis fallback)
│   ├── lsp_service.dart             (Dart language server over stdio)
│   ├── terminal_service.dart        (shell commands)
│   ├── debug_service.dart           (live variable watcher)
│   ├── base_debugger.dart           (abstract debugger contract + output stream)
│   ├── dart_debugger.dart           (Dart VM Service debugger)
│   ├── python_debugger.dart         (Python sys.settrace debugger)
│   ├── c_debugger.dart              (C/C++ clang + lldb debugger)
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
    ├── multi_language_highlighter.dart
    └── vm_service_client.dart
```
