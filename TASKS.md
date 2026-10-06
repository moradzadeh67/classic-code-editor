# TASKS.md

## Completed Tasks

### TASK-001: Project Skeleton
**Phase:** 01
**Status:** ✅ DONE
**Completed:** Phase 01 skeleton created successfully.

### TASK-002: Retro UI Design System
**Phase:** 02
**Status:** ✅ DONE
**Completed:** Phase 02 retro design system components and demo screen created successfully.

### TASK-002.5: Theme System
**Phase:** 02.5
**Status:** ✅ DONE
**Completed:** Phase 02.5 theme system with VC++ 6.0 and Borland Delphi themes created successfully.

### TASK-003: IDE Shell
**Phase:** 03
**Status:** ✅ DONE
**Completed:** Phase 03 IDE shell layout, menu bar, toolbar, panel layout, and status bar created successfully.

### TASK-003.1: Theme Selector & Third Theme (VB6)
**Phase:** 03.1
**Status:** ✅ DONE
**Completed:**
- Added `ThemeType.vb6` and the full Visual Basic 6.0 color set to `ThemeService`.
- Toolbar theme selector (`VC++ 6.0` / `Delphi` / `VB6`) with sunken "active" state,
  wrapped in `ListenableBuilder(listenable: ThemeService.instance)` so the pressed
  state refreshes on every theme switch.
- View-menu theme entries (VC++ 6.0 / Borland Delphi / Visual Basic 6.0).
- VB6 syntax colors added in `syntax_colors.dart`.
- Active theme persisted to `.retro_theme_config.json`.

### TASK-003.2: Shell Visual Polish
**Phase:** 03.2
**Status:** ✅ DONE
**Completed:**
- Fixed button-label clipping (descenders in "Open"/"Stop") by giving the button a
  fixed **22px** height with 1px breathing room above/below.
- Typography unified: **Arial** for UI (was thin system default), UI labels 12px
  (w500), status bar 11px (w400).
- Verified **square corners** everywhere: no `BorderRadius.circular`/`RoundedRectangleBorder`
  exists in `lib/`; `RetroBorder` uses `BorderRadius.zero` and the menu popup uses a
  square `Border` shape.
- Removed the toolbar **overflow** (yellow/black hazard stripes) by shortening the
  theme labels and placing the selector in an `Expanded` + horizontal scroll guard.
- Reduced bar heights to authentic Windows 9x / Delphi 6 metrics:
  toolbar **28px**, menu bar **24px**, status bar **24px**, button **22px**.
- Added `code_editor_panel.dart` placeholder (editor surface) plus explorer/console
  panels in `panel_layout.dart`.

### TASK-004: Code Editor
**Phase:** 04
**Status:** ✅ DONE
**Completed:** Integrated placeholder code editor panel into editor area (`code_editor_panel.dart`).

### TASK-005: Dart Runner
**Phase:** 05
**Status:** ✅ DONE
**Completed:** Created `DartRunnerService` in `lib/services/dart_runner_service.dart` supporting temporary file execution, stdout/stderr streams, process cancellation, and dynamic SDK path resolution without hardcoding or adding packages.

### TASK-006: Console
**Phase:** 06
**Status:** ✅ DONE
**Completed:** Created `ConsolePanel` (`lib/ui/console/console_panel.dart`) connected to `DartRunnerService`, supporting stdout/stderr output, auto-scrolling, clear action, and execution status indicators styled with retro 3D sunken borders and theme colors.

### TASK-007: File Management
**Phase:** 07
**Status:** ✅ DONE
**Completed:** Created `FileService` (`lib/services/file_service.dart`) utilizing `file_picker` and `path_provider`, integrated with the code editor (showing modified indicator `*` and file name), toolbar ("Open", "Save"), and menu bar ("Save As").

### TASK-008: Tabs & Projects
**Phase:** 08
**Status:** ✅ DONE
**Completed:** Created `TabFile` model (`lib/models/tab_file.dart`) and `TabBarWidget` (`lib/ui/editor/tab_bar.dart`), refactored `FileService` for multi-tab management (open, close, switch, save, modified tracking), and integrated tab-aware `CodeEditorPanel` and layout in `PanelLayout`.

### TASK-009: Dart Analyzer
**Phase:** 09
**Status:** ✅ DONE
**Completed:** Integrated `AnalyzerService` with automatic file analysis on open/save/switch, created `DiagnosticsPanel` with retro styling, wired error/warning counts into `RetroStatusBar`, added Analyze toolbar button and View/Tools menu items, verified with zero static analysis issues.

### TASK-010: Dart LSP
**Phase:** 10
**Status:** ✅ DONE
**Completed:**
- Created `JsonRpcClient` (`lib/utils/json_rpc_client.dart`) implementing
  `Content-Length` framing plus JSON encode/decode, resilient to arbitrarily
  split byte chunks.
- Created `LspService` (`lib/services/lsp_service.dart`): spawns
  `dart language-server`, performs the `initialize`/`initialized` handshake,
  sends `textDocument/didOpen` and `textDocument/didChange` (full-document
  sync), parses `textDocument/publishDiagnostics` into `Diagnostic` models,
  and answers server-initiated requests. Lifecycle is fully managed
  (`shutdown` -> `exit` -> kill, subscriptions cancelled, state reset).
- Registered the opened file's directory dynamically via
  `workspace/didChangeWorkspaceFolders` so files outside the app's cwd are
  analysed too.
- Wired into `IDEShell`: server starts eagerly on launch, documents are pushed
  on open/switch/type (via the `FileService` listener), and the service is
  disposed on exit.
- `DiagnosticsPanel` refactored to accept a plain `List<Diagnostic>` so
  `PanelLayout` can prefer real-time LSP results and fall back to
  `AnalyzerService` while the server is starting.
- `RetroStatusBar` gained an `LSP: Starting... / Connected / Stopped` indicator
  with a square status light.
- Fixed a blocking platform issue: the macOS app was sandboxed, so
  `Process.start` failed with "Operation not permitted" (this also silently
  broke `DartRunnerService`). Set `com.apple.security.app-sandbox` to `false` in
  `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`.
- Verified: `flutter analyze` clean (0 issues), macOS debug build succeeds, the
  `dart language-server` child process spawns on launch and is reaped on quit,
  and a protocol probe confirmed `initialize` -> `didOpen` -> diagnostics ->
  `didChange` -> updated diagnostics.

---

## Current Active Task

### TASK-011: IDE Intelligence
**Phase:** 11
**Status:** ⬜ TODO
**Priority:** HIGH

**Description:**
Autocomplete, hover docs, and real-time diagnostics in the editor.
