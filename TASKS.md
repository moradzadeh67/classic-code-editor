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
- Added the `pausedLine` design token to all three themes that existed then (four now).
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
  `#031CFC` — in all themes (the palette is shared, four themes now).
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

### TASK-032: ARM64 Assembly Language Support
**Phase:** 19
**Status:** ✅ DONE
**Completed:** `LanguageConfig` `.s` entry; `arm64Asm` grammar (64-bit registers, `//` comments,
labels, directives, immediates) wired as `armasm`; `LanguageRunnerService` assembles and runs `.s`
with `clang -g -arch arm64` behind an Apple-Silicon check; `.s` added to open/save filters and to
content sniffing; ARM64 option in the manual language dropdown; `samples/hello_arm64.s`.

### TASK-033: AsmDebugger (registers + instruction stepping)
**Phase:** 19
**Status:** ✅ DONE
**Completed:** `AsmDebugger extends CDebugger` with its own LLDB stop-hook that publishes
`x0`..`x28`/`fp`/`lr`/`sp`/`pc`/`cpsr` as Variables plus a one-instruction disassembly; Step
Into/Over/Out → `thread step-inst` / `thread step-inst-over` / `thread step-out`; factory dispatch
(four debuggers); protected accessors added to `CDebugger` without changing C/C++ behaviour.

### TASK-034: ASM Logo & Language Icons
**Phase:** 19
**Status:** ✅ DONE
**Completed:** `assets/icons/asm.png` (blue heptagon `ASM`) + vector fallback painter; `LanguageLogo`
map for `s` / `asm` / `arm64` / `ARM64 Assembly`; icon test.

### TASK-035: Gutter Layout, Bullet Size & Current-Line Highlight
**Phase:** 19
**Status:** ✅ DONE
**Completed:** line numbers on the left, 10px reserved for the gutter scrollbar; breakpoint bullet
painted at `0.7 × lineHeight` (~2× the old glyph); full-width current-line band with hairline border,
emphasised gutter number, and click-past-end-of-line selecting that row.

### TASK-036: Debugger Sidebar Visibility
**Phase:** 19
**Status:** ✅ DONE
**Completed:** `PanelLayout` shows `DebuggerSidebar` only for a `running`/`paused` session and listens
to the active debugger, so a lone breakpoint no longer opens the panel.

### TASK-037: Fourth Theme — Turbo Pascal 7.0
**Phase:** 19
**Status:** ✅ DONE
**Completed:** `ThemeType.turboPascal` + DOS palette + `SyntaxColors` entry (palette shared with the
other themes); View-menu item and toolbar dropdown; persistence key `turbopascal`.

### TASK-038: Deterministic Settings Save
**Phase:** 19
**Status:** ✅ DONE
**Completed:** `EditorSettingsService` caches its file and writes synchronously after the first
resolve, removing the save/load ordering race that made `editor_settings_service_test` flaky.

### TASK-040: Unsaved-Changes Guard
**Phase:** 20
**Status:** ✅ DONE
**Completed:** `retro_confirm_dialog.dart`, `close_guard.dart` (`confirmClose` / `confirmExit`), tab ✕, Cmd+W,
File > Close Tab, `AppLifecycleListener.onExitRequested` for Cmd+Q and the window close button;
`FileService.saveTab` + bool results from `saveFile`/`saveFileAs`.

### TASK-041: Edit Menu & Shortcuts
**Phase:** 20
**Status:** ✅ DONE
**Completed:** Select All (Cmd+A), Go to Line (Cmd+L, retro prompt + `CodeEditorPanelState.goToLine`),
Toggle Comment (Cmd+/), Duplicate Line (Cmd+Shift+D), Cmd+O; `LanguageConfig.commentPrefix`;
About > Shortcuts updated.

### TASK-042: Session Restore & Recent Files
**Phase:** 20
**Status:** ✅ DONE
**Completed:** `SessionService` (`session.json`, active tab by path, 10-entry MRU), restore on launch,
persist on open/close/switch, File > numbered MRU + Clear Recent Files.

### TASK-043: Docs & Verification (Phase 20)
**Phase:** 20
**Status:** ✅ DONE
**Completed:** CHANGELOG [Unreleased], TASKS/ARCHITECTURE/AGENTS/PRIVACY/README; analyze clean; 230 tests.

## Phase 22 — Editor fonts (unreleased)

### TASK-046: Editor font choice, two faces
**Phase:** 22
**Status:** ✅ DONE
**Completed:** `View > Font` offers **Menlo** (default, pixel-identical to before) and **Recursive Mono
Casual**, persisted as a stable id in `editor_settings.json` next to `fontSize`; unknown/corrupt/retired ids
resolve to Menlo. The bundled Recursive faces live under the alias `RecursiveMonoCasual` in `pubspec.yaml`
with `OFL.txt` and `THIRD_PARTY_NOTICES.md`. Glyph advance and wrapped-row caches are keyed by **both** size
and family, and the line-number style follows the code font.

### TASK-046a: Real-app font defects (row drift, stale check mark)
**Phase:** 22
**Status:** ✅ DONE
**Fixed:** two defects that the green `flutter_tester` suite could not see:
- **E1** Monaco's code rows drifted away from the gutter (~4 rows by line 400; gutter numbers between code
  rows; click on 304 selected 302). **Cause:** the row was left to the *fallback* font, so a Persian line grew
  it (13/20/49 px instead of 12/19/47 at sizes 8/13/32). **Fix:** the strut is now forced for every family at
  the plain `lineHeight / fontSize` factor. Measured in the running app over 1000 lines: `d=0.0` for
  ASCII/Persian/mixed at 8/13/32.
- **E2** `View > Font` applied the new font but kept the check mark on the previous one. **Cause:** the rows
  were built in `RetroMenuBar.build()` and captured by `itemBuilder`, and the bar listens only to
  `SessionService`. **Fix:** build the rows when the popup opens (also fixes the theme rows).
- **Trap recorded:** `TextPainter.height` floors the strut halves (a forced Monaco *looks* 1-3 px short) while
  `RenderEditable` rounds `fontSize * height` and renders exactly; tuning the factor for the painter produced
  20 px rows at size 13. The invariant is asserted on a real `EditableText`
  (`editor_font_fallback_drift_test.dart`) and measured in the app with `tool/probe_font_drift.dart`.
**Verified:** analyze clean; **306 tests pass, 2 opt-in skipped**.

### TASK-046b: Monaco removed
**Phase:** 22
**Status:** ✅ DONE
**Why:** no real bold/italic (both synthesized) and metrics that depend on the fallback font.
**Done:** `EditorFontFamily.monaco` and its menu row are gone; a saved `"monaco"` id migrates to `menlo`;
tests, probe and docs narrowed to the two remaining faces.

### TASK-047: lldb stdin queue, readiness gate and kill order
**Phase:** 22
**Status:** ✅ DONE
**Why:** `BORLAND_REAL_ASM_TEST=1`. The entry-stop test failed (`paused` vs `running`) and, once it could run,
`a breakpoint after _main stops on its exact line` failed 1 in ~4 runs: lldb echoed
`error: 'reakpoint' is not a valid command` - one of our writes, split on the wire.
**Measured:** byte-level trace of every stdin write (caller, µs, exact bytes) and every **raw** stdout chunk:
our side wrote exactly one line (`breakpoint set -a 0x…`, `len=29`), lldb received `b` + `reakpoint …`, i.e.
cause (b): a single write read in pieces while lldb was still printing the stop report/prompt. The pipe prompt
is printed when lldb *reads*, so "wait for the prompt" can never be the gate.
**Done:** `LldbCommandQueue` (one command in flight, 40 ms quiet gate, `@@ACK n` sentinel as its own gated
write, one idempotent retry for non-resume units, Continue/Step to the front, Stop closes the queue);
`_finalize` = `process kill` + `quit` + 2 s wait + SIGKILL lldb + SIGKILL the parsed inferior pid.
**Tests:** `lldb_command_queue_test` (6 fake-lldb transcripts; the gate test fails if the gate is removed),
opt-in `lldb_session_lifecycle_test` (C, C++, stop-while-paused, `pgrep` must be empty).
**Verified:** opt-in suite **20/20 idle** and **23 consecutive under 4×`yes` load** (one unexplained failure in
the very first load batch of 10, not reproduced in 23 later runs); default suite 329 pass / 6 skipped;
analyze clean.

## Phase 21 — v1.4.0

### TASK-044: Assembly source-line mapping / line breakpoints
**Phase:** 21
**Status:** ✅ DONE
**Completed:** `Arm64AsmParser` / `Arm64AsmMap` maps source lines (1-indexed) to 4-byte instruction offsets relative to `_main`/`main`. `AsmDebugger` maps paused `pc` load addresses back to exact source lines. Unit tests and release gates pass cleanly.

### TASK-044b: Phase 21 WIP fixes (ARM64 asm breakpoints, registers, entry arrow)
**Phase:** 21
**Status:** ✅ DONE
**Fixed:** six defects found in a real run on `samples/array_sum_arm64.s`:
- **E1** parser counted offsets from the top of the file, so a helper assembled before `_main` shifted every
  breakpoint. Offsets are now relative to the entry symbol (negative before it).
- **E2** the duplicate `breakpoint set --name _main` is gone (lldb knows the symbol as `main`).
- **E3** the stop snapshot never reached `AsmDebugger`: `_watchStreams` subscribed to `CDebugger`'s private
  `_onStdoutLine`, so the override was bypassed and the C-shaped parser dropped the asm payload. The stream
  now goes through the virtual `handleStdoutLine`, so registers, `pc=…` and `▶` come back.
- **E4** `_finalize` kept the dead breakpoint ids, so a second session deleted them and lldb answered
  `error: No breakpoints exist to be deleted.` nine times. Ids are cleared on teardown and at session start.
- **E5** the Console said `[C debugging stopped]`; `CDebugger` now exposes an overridable `debuggerLabel`.
- **E6** `.section __TEXT,__cstring,…` was treated as code because the *segment* name contains `__TEXT`;
  the second comma-separated token decides now.
**Also:** `-R` (address slide) rejects a negative slide (`-R -20` becomes `0x2000004bc`), so gutter
breakpoints are installed as `breakpoint set -a <main + offset>` once the entry stop reveals the base.
**Verified:** `BORLAND_REAL_ASM_TEST=1` runs clang+lldb on `samples/array_sum_arm64.s`; a breakpoint on
`add x2, x2, x3` stops 5× with `x2=0,10,30,60,100`, `x3=10,20,30,40,50`, `▶` on line 33 each time.

### TASK-045: ARM64-only release build
**Phase:** 21
**Status:** 🛑 DROPPED
**Why:** Owner decision: DMG stays Universal (Intel and Apple Silicon) so it runs on Intel Macs. ARM64 assembly run/debug remains Apple-Silicon-only.

### TASK-048: Docs, Version & Release Gate (v1.4.0+6)
**Phase:** 22
**Status:** ✅ DONE
**Completed:** Version 1.4.0+6, tag v1.4.0, release notes, docs updated, analyze clean, 329 tests pass (6 opt-in skipped). Universal DMG verified.

### TASK-039: Docs, Version, Release Gate
**Phase:** 19
**Status:** ✅ DONE
**Completed:** README/CHANGELOG/ARCHITECTURE/TASKS/PHASE_DETAILS/DEBUGGING/RELEASE/RETRO_DESIGN
updated; version 1.3.0+5; analyze + 204 tests PASS (1 opt-in skipped). Later raised to 230 by Phase 20.

### TASK-049: Multi-language LSP — clangd, pyright/pylsp
**Phase:** 23
**Status:** ✅ DONE
**Completed:**
- `LspServerSpec` (NEW) is now the single source of truth for a server's binary names, arguments, language
  ids and install hint: Dart, clangd (no `--stdio` — Apple's build rejects it), pyright (`--stdio`) and pylsp
  (fallback). `candidatesForLanguage` maps `c`/`cpp` → clangd, `python` → pyright then pylsp, `armasm` → none.
- `LspServerManager` (NEW) caches one `LspService` per spec id, so alternating `.c`/`.dart`/`.py` tabs never
  restart a server; `active` is always non-null (`Off` spec when nothing applies). A missing server prints its
  install hint to the Console once and the UI falls back to offline completion.
- `CompileFlagsEnsurer` (NEW) writes `compile_flags.txt` (comment header + `-isysroot $(xcrun --show-sdk-path)`)
  before clangd's `initialize`; an existing file is never overwritten.
- `LspService` is parameterised by `LspServerSpec`, resolves binaries from launchd's minimal PATH, shares one
  startup future (so `openFile` can wait for `initialize`), and retries an empty first completion once (200 ms).
- Status bar LSP segment has a tooltip naming the active server and the failure reason.
- `dart analyze` fallback is limited to Dart files.
- Docs: README (install table + known limitation), ARCHITECTURE (services + selection flow), AGENTS.md (Rule 12
  + file structure), CHANGELOG, PHASE_DETAILS.
- Tests: `lsp_server_spec_test`, `lsp_server_manager_test`, `compile_flags_test`, completion warm-up retries in
  `lsp_service_test`, opt-in `clangd_presence_test` (real handshake). Suite: **354 pass / 8 opt-in skipped**
  (was 329/6; the two new skips are the opt-in clangd tests). Analyze clean.

### TASK-050: View > Syntax Colors — Standard / Colorful palettes
**Phase:** 24
**Status:** ✅ DONE
**Completed:**
- `SyntaxScheme` (NEW, `models/syntax_scheme.dart`) with the stable ids `standard` / `colorful`; `fromId` falls
  back to `standard` for a missing key, a corrupt value or an id from a scheme removed later.
- `EditorSettingsService` stores it next to `fontSize` / `fontFamily` (`syntaxScheme` in
  `editor_settings.json`), resolves it through the same `fromId` pattern as the font id, and
  `setSyntaxScheme` notifies listeners so the editor repaints with no restart.
- `MultiLanguageHighlighter` now owns **one** token-class → category map (`_categoryByClass`) plus one color map
  per scheme, and `getThemeStyles([scheme])` builds the class map from them (default argument = Standard, so
  every existing caller and test is unchanged). Standard reproduces the classic palette exactly (verified
  key-by-key in the app); Colorful is the 11-color palette from the owner spec.
- `CodeEditorPanel` passes `EditorSettingsService.instance.syntaxScheme` into `CodeThemeData`; the panel already
  rebuilds on that service's notifications, so only the theme data changes — the `CodeController`, its
  highlighted nodes, analysis, cursor and undo history are reused (verified live in all four themes).
- `View > Syntax Colors`: a disabled group row plus `Standard` / `Colorful` with the check mark on the active
  one (same style as the View > Font rows, built when the popup opens).
- Assembly needed **no** palette work: registers are `built_in`, directives `meta`, labels `title` (functions),
  so they follow their categories in both schemes.

**Token classes that had no category before (mapped by judgement, closest category):**
- `doctag` (emitted by the Dart grammar for `///` doc comments) → **comment**. Standard deliberately keeps it
  unstyled (it was plain text before, so nothing changes); only Colorful paints it.
- `params` and `variable` → **plain text**. Standard keeps its own two colors (`#283593`, `#1A237E`); Colorful
  has no identifier color in the spec, so both are written as the default text color `#000000` — explicit, not
  inherited, because a parameter list nests inside the (colored) function node.
- `selector-tag` → keyword, `symbol` → operator, `meta-keyword` → annotation, `meta-string`/`quote`/`subst` →
  string, `title`/`title.function` → function, `type` → types (all pre-existing classes, no guesswork).
**No new tests** (owner verifies manually); existing suite + `flutter analyze` clean. No commit, no version bump.

### TASK-051: Color fixes (Python black, Assembly labels, C/C++/Python parens) + v1.4.1 release
**Phase:** 24
**Status:** ✅ DONE
**Fixed (all verified through the real `SpanBuilder` + `CodeThemeData` path):**
- **Python rendered black.** Three gaps at once: the shell hands `CodeEditorPanel` a bare `CodeController()`
  (no language) and `initState` never applied one, so a file open when the panel mounted painted every token
  in the default color; `LanguageConfig` had no content sniffing, so an `Untitled` buffer fell back to the Dart
  grammar; and the Python grammar left `print`/`exec` (bare rule, no `className`) plus f-string `{...}`
  (`subst`, missing from the style map) unstyled. Languages now resolve through one shared
  `LanguageConfig.fromPathOrContent` (also used by Run/Debug), the grammar is applied on mount and re-sniffed
  while typing, `subst` maps to the string color and Python builtins get a rule before the bare one.
- **C++/Python parentheses were not the bracket color.** The bundled grammars wrap a parameter list in a
  `params` mode that owns its `(`/`)`. Those modes are now removed (their literal/comment rules kept) so the
  shared bracket rule colors every bracket. Patching such a mode instead made it worse: a `contains` rule wins
  over the mode's `end`, so the mode never closed and C++ call parentheses changed color mid-line.
- **Assembly labels/separators.** Labels were tagged `symbol` (operator green) instead of `title`, and
  `,` `[` `]` `!` stayed in the default color; they now use the operator/bracket categories.
- **`View > Syntax Colors`** (`TASK-050`) shipped in the same release.
**Docs:** CHANGELOG `[1.4.1]`, README (feature + version refs), ARCHITECTURE (palette table, scheme flow,
grammar-patch rules), AGENTS Rule 13, PHASE_DETAILS, RELEASE.md, `docs/RELEASE_NOTES_1.4.1.md`.
**Release:** version `1.4.1+7`, tag `v1.4.1`, GitHub release titled **Classic Code Editor v1.4.1** with the
universal DMG. `flutter analyze` clean, **368 tests pass / 8 opt-in skipped**.
