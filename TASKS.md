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
**Completed:** Created `FileService` (`lib/services/file_service.dart`) using `file_picker` and `path_provider`, integrated with the code editor (showing modified indicator `*` and file name), toolbar ("Open", "Save"), and menu bar ("Save As").

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

### TASK-011: IDE Intelligence
**Phase:** 11
**Status:** ✅ DONE
**Completed:**
- Implemented client-side completion filtering and ranking in `CompletionFilter`.
- Added LSP `filterText` and `displayLabel` support so signature labels (`print(...)`) display cleanly as `print`.
- Fixed popup visibility gating: minimum 3-character prefix required before triggering autocomplete, debounced, with stale response discarding and out-of-focus dismissal.
- Fixed hover tooltip interference (suppressed during typing and when autocomplete is visible).
- Added auto-indentation on Enter, between-braces expansion, and closing bracket dedent.
- Added automatic format on save (`dart format` via process stdin/stdout).
- Verified clean `flutter analyze` (0 issues) and 26/26 unit checks passing.

### TASK-012: Terminal
**Phase:** 12
**Status:** ✅ DONE
**Completed:**
- Created `TerminalService` (`lib/services/terminal_service.dart`) managing subprocess execution (`bash`/`cmd`), working directory tracking (`cd`), command output streaming, and command history (Up/Down arrow navigation).
- Created `TerminalPanel` (`lib/ui/terminal/terminal_panel.dart`) featuring a retro 3D sunken terminal output area (black background with green monospace text), interactive command input, and clear action.
- Added "Terminal" tab to bottom panel in `PanelLayout` alongside Console and Diagnostics.
- Wired `TerminalService` in `IDEShell` with proper lifecycle management (`dispose`).
- Verified clean `flutter analyze` (0 issues) and macOS debug build.

---

## Current Active Task

### TASK-013: Debugger
**Phase:** 13
**Status:** ✅ DONE
**Completed:** Implemented debugging sidebar, variable panels, call stack panels, breakpoints panels, and Dart debugger service.

---

## Current Active Task

### TASK-014: Multi-Language Support
**Phase:** 14
**Status:** ✅ DONE
**Completed:**
- Created `LanguageConfig` model (`lib/models/language_config.dart`) defining language rules per file extension for Dart, C, C++, and Python.
- Created `LanguageRunnerService` (`lib/services/language_runner_service.dart`) supporting execution and compilation for Dart (`dart run`), Python (`python3`), C (`clang`), and C++ (`clang++`) with live console streaming.
- Updated `FileService` (`lib/services/file_service.dart`) to support formatting on save for Dart (`dart format`), C/C++ (`clang-format`), and Python (`black`).
- Created `MultiLanguageHighlighter` (`lib/utils/multi_language_highlighter.dart`) using the `highlight` package with registered languages for Dart, C, C++, and Python.
- Wired multi-language configuration, syntax highlighting, formatting, and running into `CodeEditorPanel`, `RetroToolbar`, `RetroMenuBar`, and `IDEShell`.
- Verified clean `flutter analyze` with 0 issues.

---

## Current Active Task

### TASK-015: Multi-Language Debugging
**Phase:** 15
**Status:** ✅ DONE
**Completed:**
- Extended `BaseDebugger` with `currentPausedLine`, a broadcast `output`
  stream, the `@protected emitOutput` helper, and `clearBreakpointsForFile`.
- Created `DartDebugger` on the real **Dart VM Service**: spawns
  `dart --enable-vm-service=0 --disable-service-auth-codes
  --pause-isolates-on-start --enable-asserts <script>`, awaits the isolate
  `rootLib`, installs an entry breakpoint in the user's `main`
  (`getIsolate` → `scripts` → `getObject` → `source` → `findMainLine`), mirrors
  gutter breakpoints with `addBreakpointWithScriptUri`, and fills
  `variables`/`callStack` from `getStack`.
- Created `VmServiceClient` (`lib/utils/vm_service_client.dart`): hand-rolled
  JSON-RPC 2.0 over a `dart:io` `WebSocket` (no new package).
- Created `PythonDebugger` (generated `sys.settrace` tracer driver) and
  `CDebugger` (`clang -g -O0` + `lldb` with an injected `borland_lldb.py`
  stop-hook).
- Created `DebuggerFactory` (language → debugger), `DebuggerManager` (active
  debugger follows the active tab), `DebugSnapshot` (shared stop decoder) and
  `DebuggerEnvironment` (test seam).
- Bridged debug output: `IDEShell` pipes every debugger's `output` stream into
  `LanguageRunnerService.emitOutput`, the stream `ConsolePanel` listens to.
- `RetroToolbar`'s Debug now passes the live buffer content, so unsaved and
  untitled files can be debugged.
- Added the `pausedLine` design token to all three themes.
- Verified clean `flutter analyze` (0 issues) and `flutter test` (suite green).

---

## Current Active Task

### TASK-016: Debugger Hardening & Test Coverage
**Phase:** 16
**Status:** ✅ DONE
**Completed:**
- Fixed silent debug sessions (public `emitOutput` bridge).
- Fixed Debug being dead for unsaved buffers (live content + temp file).
- Fixed C/C++ never pausing (reject lldb's `LLDB_INVALID_LINE_NUMBER`
  `0xFFFFFFFF` and empty files, filter unusable frames, add
  `breakpoint set --name main`).
- Fixed the Dart arrow pointing into `dart:isolate-patch` internals (publish a
  pause only when the top frame is real user code).
- Fixed the Dart startup race (`_awaitIsolateReady` polls until `rootLib`
  exists).
- Fixed untitled C files compiling as C++ (reordered content sniffing).
- Fixed gutter rows drifting from the editor (shared `editorLineHeight`
  `18.85` instead of a hardcoded `19.0`) and the paused arrow hiding the
  breakpoint bullet.
- Added tests: `dart_debugger_test`, `python_debugger_test`, `c_debugger_test`,
  `debugger_factory_test`, `vm_service_client_test`, `console_panel_test`,
  `debugger_gutter_test`, `debugger_language_switch_test`,
  `debugger_arrow_all_languages_test`.
- Added an opt-in end-to-end test (`test/integration/dart_vm_pause_test.dart`)
  that really spawns a Dart VM and attaches over a real WebSocket; skipped by
  default so the suite stays offline.
- Verified `flutter analyze` clean (0 issues) and `flutter test` green
  (106 tests, 1 opt-in integration test skipped).

---

## Current Active Task

### TASK-017: Release Smoke Gate
**Phase:** 17
**Status:** ✅ DONE
**Completed:**
- Added `scripts/release_gate/` with four self-contained gate scripts that any
  agent can run unattended before cutting a release:
  - `01_analyze.sh` — `flutter analyze` must report 0 issues.
  - `02_test.sh` — `flutter test` must report "All tests passed".
  - `03_build_macos.sh` — `flutter build macos --release` must succeed and
    produce `build/macos/Build/Products/Release/Classic Code Editor.app`.
  - `04_launch_smoke.sh` — launches the built release app, verifies it stays
    alive for 8 seconds (no startup crash), then kills it; log kept at
    `/tmp/borland_launch_smoke.log`.
- Each script prints a clear `PASS: <name>` / `FAIL: <name>` line and exits
  0/1, so an agent can chain them and gate the release on the exit codes.
- Release rule for agents: run the four scripts in order (01 → 02 → 03 → 04);
  a release (v1) may only be cut when all four report PASS.
- Verified locally: all four gates pass (analyze clean, 106 tests green,
  release build succeeds, app launches and survives the 8s smoke window).

---

## Current Active Task

### TASK-018: Colored Operators & Brackets
**Phase:** post-17 polish
**Status:** ✅ DONE
**Completed:**
- Operators/symbols (`! @ # $ % ^ & * + = - ~ < > / | ? : ; , .` and `=>`)
  now render dark green `#0B6E00`; brackets `() { } [ ]` render blue
  `#031CFC` — in all three themes.
- highlight 0.7's Dart/C/C++/Python grammars emit no `operator` /
  `punctuation` classes, so `MultiLanguageHighlighter.patchSymbolModes()`
  appends single-character rules to each grammar before first compile
  (no new packages; strings/comments/numbers/`#include` keep their colors).
- Verified: `flutter analyze` clean and `flutter test` green (109 tests,
  including a real-parse test that asserts the colored token classes).

---

### TASK-019: Gutter Line Number Alignment Fix
**Phase:** post-17 polish
**Status:** ✅ DONE
**Completed:**
- Resolved line number drift in code editor gutter on long files, wrapped lines, and narrow window widths:
  - Accounted for `letterSpacing: 0.5` in character advance calculations.
  - Replaced rough `fontSize * 0.62` estimate in `_gutterRows` with exact measured `_charAdvance`.
  - Applied `editorStrutStyle` to line numbers so digits share the code's exact baseline and row height (19.0px).
- Expanded test suite in `gutter_alignment_test.dart` to verify line number alignment across window widths (420px to 1600px) and target platforms (macOS/Android).
- Verified: `flutter analyze` reports 0 issues, all 151 tests passing.

---

### TASK-020 & TASK-021 & TASK-022: Syntax Color Palette Refinement
**Phase:** post-17 polish
**Status:** ✅ DONE
**Completed:**
- Inspected and updated the multi-language editor syntax palette in `MultiLanguageHighlighter`:
  - Keywords: `#C842F5` (purple/magenta, bold)
  - Operators: `#00BF69` (emerald green, bold), matching `! @ # $ % ^ & * + = - ~ < > / | ? : ; , . \ ` and `=>`
  - Comments: `#596E48` (muted green, italic)
- Added `\` and `` ` `` to `patchSymbolModes()` while keeping identifier underscores (`_controller`, `my_var`), strings, comments, numbers, and `#include` preprocessor directives cleanly tokenized in their respective classes.
- Added real-parse assertions for Dart, Python, C, and C++ verifying operator, comment, meta, and string tokenization.
- Updated `ARCHITECTURE.md`, `CHANGELOG.md`, and `TASKS.md`.
- Verified: `flutter analyze` clean (0 issues) and full test suite passing (151 tests).


### TASK-023: EditorSettingsService
**Phase:** 18
**Status:** ✅ DONE
**Completed:** ChangeNotifier singleton with clamp/load/save JSON.

### TASK-024: EditorMetrics
**Phase:** 18
**Status:** ✅ DONE
**Completed:** Pure value class with formulas for line height, gutter, markers.

### TASK-025: Editor Panel Dynamic
**Phase:** 18
**Status:** ✅ DONE
**Completed:** Dynamic metrics + cache invalidation + listener in panel.

### TASK-026: Gutter Alignment Tests Across Sizes
**Phase:** 18
**Status:** ✅ DONE
**Completed:** Parametrized tests over {8, 13, 20, 32} with zoom change test.

### TASK-027: Editor Zoom Interaction Tests
**Phase:** 18
**Status:** ✅ DONE
**Completed:** Breakpoint and arrow tests at sizes 8/13/32; zoom-while-paused.

### TASK-028: Zoom Shortcuts
**Phase:** 18
**Status:** ✅ DONE
**Completed:** App shortcuts + keyboard listener branch + helper tests.

### TASK-029: View Menu Items
**Phase:** 18
**Status:** ✅ DONE
**Completed:** Three font-size PopupMenuItems in View menu.

### TASK-030: About Dialog Shortcuts Tab
**Phase:** 18
**Status:** ✅ DONE
**Completed:** Added zoom shortcuts rows; test updated.

### TASK-031: Docs, Version, Release Gate
**Phase:** 18
**Status:** ✅ DONE
**Completed:** README/CHANGELOG/ARCHITECTURE.md/AGENTS.md/TASKS.md updated; version 1.2.0+4; gate 01-04 PASS.
