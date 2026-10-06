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

## File Structure (MUST follow)

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
│   │   └── syntax_colors.dart       (per-theme syntax palette)
│   │
│   ├── shell/ ← IDE shell
│   │   ├── ide_shell.dart           (layout + theme-aware rebuild root)
│   │   ├── retro_menu_bar.dart      (24px, File/Edit/View/Run/Tools/Help)
│   │   ├── retro_toolbar.dart       (28px, New/Open/Save/Run/Stop + theme selector)
│   │   ├── retro_status_bar.dart    (24px)
│   │   └── panel_layout.dart        (explorer + editor + console)
│   │
│   ├── editor/
│   │   └── code_editor_panel.dart   (placeholder editor surface)
│   │
│   ├── explorer/ ← File explorer panel (future)
│   └── console/ ← Console/output panel (future)
│
├── services/ ← Business logic, SDK interaction
│   └── theme_service.dart           (3 themes + persistence)
│
├── models/ ← Data classes
└── utils/ ← Helpers, constants
