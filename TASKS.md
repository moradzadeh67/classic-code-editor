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

### TASK-052: Console polish, content-aware LSP selection, v1.4.2 release
**Phase:** 24
**Status:** ✅ DONE
**Fixed:**
- **Console started each run with the previous program's output.** `LanguageRunnerService` gained a dedicated
  `clearStream` / `clearConsole()` (kept apart from `outputStream` so no listener mistakes it for output);
  `runCode` calls it before printing anything and the Debug button does the same, and `ConsolePanel` clears its
  lines and resets the scroll on that event.
- **An untitled C++/Python buffer said "Dart language server: connected".** Server selection and the
  `languageId` in `textDocument/didOpen` now use `LanguageConfig.fromPathOrContent`, and an extensionless
  buffer is opened with the resolved extension (`Untitled` → `Untitled.cpp`) so clangd picks the right grammar.
  Verified with the real clangd (publishes diagnostics for the in-memory document).
- **`dart analyze` fallback** is no longer triggered for an untitled C++ buffer (same resolver).
**Changed:** the bracketed Console guide lines (`[Running Python 3...]`, `[Compiling ...]`) now use w600 like
the output they introduce, instead of the washed-out normal weight.
**Tooling:** `pyright` 1.1.414 installed (`npm install -g pyright`) and verified end to end (handshake +
`publishDiagnostics` on an unsaved Python buffer).
**Docs:** CHANGELOG `[1.4.2]`, README (Console feature + version refs), RELEASE.md, `docs/RELEASE_NOTES_1.4.2.md`.
**Release:** version `1.4.2+8`, tag `v1.4.2`, GitHub release titled **Classic Code Editor v1.4.2** with the
universal DMG. `flutter analyze` clean, **367 tests pass / 8 opt-in skipped**.

### TASK-053: Unsaved-buffer analysis, compile_flags format fix, v1.4.3 release
**Phase:** 24
**Status:** ✅ DONE
**Added:**
- `UnsavedBufferWorkspace` (NEW): every `Untitled` tab is exposed to the language server as
  `untitled.<ext>` (extension resolved from the content) inside one per-session temp directory that also holds
  `compile_flags.txt`, so clangd / pyright / the Dart server analyze it exactly like a saved file — real
  diagnostics, hover and completion before Save. Nothing is written for the buffer itself (`didOpen` carries
  the text), the directory is removed on dispose, and a failed temp directory falls back to `LSP: Off` with a
  tooltip.
**Fixed:**
- `compile_flags.txt` was written with a `#` comment header and a one-line `-isysroot <path>`. clangd has **no
  comment syntax** there: the comment lines became compiler arguments, the command broke, the SDK headers were
  lost and a correct C++ file reported 21 errors (C: 3). The file is now one argument per line, is skipped when
  the SDK path is unknown, and a file this app generated in the old format is repaired (`upgraded`). Verified
  against the real clangd: 21 → 0 (C++) and 3 → 0 (C).
- Invented diagnostics for unsaved buffers (clangd missing headers, Dart's "file name isn't
  lower_case_with_underscores") are gone with the virtual workspace above.
**Changed:** the blue Console guide lines dropped from w600 to w500 (w600 was too heavy).
**Docs:** CHANGELOG `[1.4.3]`, README (LSP + compile_flags notes, version refs), ARCHITECTURE (service table +
compile_flags format rule), AGENTS (Rule 12 notes + file structure), RELEASE.md, `docs/RELEASE_NOTES_1.4.3.md`.
**Release:** version `1.4.3+9`, tag `v1.4.3`, GitHub release **Classic Code Editor v1.4.3** with the universal
DMG. `flutter analyze` clean, **368 tests pass / 8 opt-in skipped**.

### TASK-054: Replacing a saved `.s` buffer with another language no longer runs it as Assembly
**Phase:** 24
**Status:** ✅ DONE (no version bump — bugfix, not a release)
**Reported:** an ARM64 assembly tab's content was replaced with a Dart program; the language logo stayed
`ASM`, and Run compiled the Dart text as assembly (`main.s`, `error: invalid operand`,
`unrecognized instruction mnemonic`, `[Compilation failed with code 1]`).

**Root cause (verified, not a guess):** for a buffer that has a real path, `LanguageConfig.fromPathOrContent`
returns the **extension match and never sniffs the content** — by design, so a `.h` file is not re-guessed on
every keystroke. Three consumers therefore all follow the stale `.s` name:
- `LanguageRunnerService.resolveLanguage` → runs `clang … main.s` (the console above),
- `MultiLanguageHighlighter.createController` → assembly grammar (wrong colors),
- `PanelLayout._detectLanguageExt()` → the `ASM` logo (path only, never content).
Measured: `fromPathOrContent(null, dartSource)` → Dart, `fromPathOrContent('Untitled', …)` → Dart,
`fromPathOrContent('/tmp/main.s', dartSource)` → **ARM64 Assembly**.
**Not** a sniffing bug: the content sniffer handles this exact program correctly once the path is null.

**Workaround today:** set the toolbar language dropdown from `Auto` to `Dart` (or `Save As` a `.dart` file) —
`resolveLanguage` honours an explicit selection before any extension.

**Resolved (safe variant):** `LanguageConfig.resolve(filePath, content, preferredLanguage:)` is now the one
resolver and returns a `LanguageResolution` carrying **both** the language and a `mismatch` (`null` when none).
The extension stays authoritative and an explicit toolbar selection still wins; a mismatch is reported only for a
recognised extension and an unambiguous signal (Dart: `import 'dart:` / `import 'package:` / a `void main(` line;
Python: a `def ` line or `import sys` / `import os` / `from … import` with no `{`/`;` line ending in the first 20
lines; C/C++: `#include <` together with `int main(`), and never when the content is plausible for the extension
(`#include` in `.s`, C++ markers in `.c`, or the extension's own language). Two different signals at once means
"no mismatch". `LanguageRunnerService.runCode()` refuses such a buffer before spawning anything — it clears the
Console, prints one line (`main.s looks like Dart, not ARM64 Assembly. Use Save As with a .dart extension, or
choose Dart in the language dropdown.`) and stays idle (`isRunning == false`); the Debug button answers the same
way through the same resolver, as do `MultiLanguageHighlighter.createController` and
`PanelLayout._detectLanguageExt` (so colors and logo can never disagree with Run/Debug). Untitled buffers and
paths with no recognised extension keep today's sniffing.

### TASK-055: ✅ DONE — a fresh install opens with the ARM64 sample instead of an empty editor
**Phase:** 24
**Status:** ✅ DONE (no version bump — bugfix, not a release cut)
**Reported:** after installing the app and opening it, the editor already contains
`samples/array_sum_arm64.s`; it should start empty.

**Root cause (verified):** no sample is bundled and no code opens one — `find` over the release
`Classic Code Editor.app` finds no `.s` file, and `pubspec.yaml` ships no sample asset. The text comes from
**session restore**: `IDEShell._restoreSession()` replays `session.json` from
`~/Library/Application Support/com.moradzadeh67.classicCodeEditor/`, and the app-support folder is shared by
every build (dev `flutter run` and the DMG app use the same bundle id). Measured on this Mac:
```json
{"openPaths":["/Users/reza/Developer/classic_code_editor/samples/array_sum_arm64.s"],
 "activePath":"/Users/reza/Developer/classic_code_editor/samples/array_sum_arm64.s", …}
```
So a re-install on a machine that ever ran the app restores the last tab; only a machine that never ran it
starts empty. The same mechanism is why the sample's tab appears with the `ASM` logo immediately.

**Options (owner pick):**
1. First-launch flag (`hasLaunched` in `editor_settings.json`) → the first launch of a build opens an empty
   editor and only later launches restore tabs;
2. Scope/clear `session.json` when the build number changes (`CFBundleShortVersionString`), so an update starts
   clean while a plain restart still restores;
3. Ignore restored paths that are outside the current project root (the sample lives in the developer's repo,
   not in a user folder);
4. A `View`/`File` preference "Restore tabs on launch" (default off) — most explicit, most UI work.
**Recommendation:** (1) + (3): a genuinely fresh install is empty, and a stale path from another machine/build
can never reopen. Keep the recent-files list (it is a separate, useful feature).

**Resolution:** resolved by always starting empty; tab restore was removed.
- A first attempt added an opt-in `View > Restore Tabs on Launch` preference, but the toggle did not work in
  manual testing and the owner only wants a clean empty start. The setting (`restoreTabsOnLaunch` in
  `editor_settings.json`), its View-menu row and `SessionService.pathsToRestore()` are gone again.
- `IDEShell._restoreSession()` now never replays tabs: it reopens only the File Explorer's folder (when it still
  exists) and then calls `FileService.createNewFile()`, so every launch shows exactly one empty **Untitled** tab.
- `session.json` is still written (open paths + MRU list) and still read, so an older file that contains
  `openPaths`/`activePath` loads without error and simply has no effect; the recent-files list is untouched.
- Test: `test/ui/shell/launch_empty_editor_test.dart` seeds a session with `openPaths` and asserts the shell opens
  no tab from it and shows one empty Untitled buffer; the explorer-folder and recent-files tests are unchanged.

### TASK-056: Fix stale / false diagnostics — active-document source of truth
**Phase:** 24
**Status:** ✅ DONE (no version bump — bugfix, not a release)
**Symptoms:** (a) healthy code sometimes shows a phantom error + warnings; (b) after deleting ALL code in a file the error/warning counts do not return to zero.

**Step A — Root causes confirmed (verified from code; not guessed):**
1. `PanelLayout._mergedDiagnostics` / `RetroStatusBar`: fallback triggered by `lspService.isConnected` (not by whether an active document exists) — so an empty LSP result was treated the same as "no server" and replaced with `AnalyzerService.diagnostics`, which is stale because `analyzeFile` is one-shot and never cleared on content change.
2. `LspService.updateFile`: skipped when `_documentContents[uri] == content` (even if the document changed back), had no document version tracking, and never debounced `didChange`; an empty document (`''`) was sent only when different, so deleting all text often never reached the server.
3. `LspService._handlePublishDiagnostics`: stored all diagnostics in `_diagnosticsByUri` keyed by URI with no version check and no active-document filter — a late `publishDiagnostics` for any file replaced the visible list.
4. `AnalyzerService`: no `clearDiagnostics()` called when file content changed or tab closed; `ide_shell.dart` only cleared on `path != _lastAnalyzedPath` (path change), not on text change.

**Step B — Fix (smallest matching change):**
- New `diagostics_source.dart`: single `resolveDiagnostics({lsp, analyzer})` that picks LSP when `isConnected && activeDocumentPath != null` (even when the LSP list is empty — authoritative), else Analyzer. Both `PanelLayout` and `RetroStatusBar` use it.
- `LspService`: per-document `Map<String, List<Diagnostic>>` retained; added `_activeUri`; `openFile`/`updateFile` send incrementing `version`; `_handlePublishDiagnostics` drops URIs not in `_documentVersions` and drops `version < current`; `closeDocument` clears the document's list and resets `_activeUri`; `updateFile` sends immediately for `content.isEmpty`; debounced by 250 ms (`Timer`); flushed by save/run via `_flushPendingDocumentChange()` in `ide_shell.dart`; `openFile` announces `_safeNotify()` so empty result is visible immediately.
- `ide_shell.dart`: `_onFileServiceChanged()` clears `AnalyzerService` when path/content differs from snapshot; `_syncLanguageServer()` debounces `updateFile`; `_flushPendingDocumentChange()` before save/run; `clearConsole()` preserved (not mixed with output).
- `LspService`: kept original `diagnostics` / `errorCount` / `warningCount` (global aggregate for backward compatibility); added `activeDiagnostics` / `activeErrorCount` / `activeWarningCount` / `activeDocumentPath` for the active document only.
- Tests added to `test/services/lsp_service_test.dart`: "a valid empty LSP list does not fall back to AnalyzerService" + "a stale-version publishDiagnostics is dropped" (11 pass / 0 fail).

**Verified:** `flutter analyze` clean; `flutter test` all green; real server probe (`clangd` / `dart language-server`) confirmed empty-document `version=2` answer clears counts and stale version-1 publish is dropped.

**Not reproduced / not needed:** debugger, gutter, font metrics, syntax colors, compile_flags/untitled-buffer work untouched (explicitly excluded by rules).

### TASK-057: Open autocomplete on trigger characters and from first typed character
**Phase:** 24
**Status:** ✅ DONE

**Requirements (from user prompt):**
1. `LspService` reads `capabilities.completionProvider.triggerCharacters` from `initialize` response; stored with default `['.']`; `parseTriggerCharacters` test seam added.
2. Editor trigger logic (`CompletionFilter.decide`) fires immediately (`triggerKind=2`, `triggerCharacter` set) on server trigger chars (`.` / server-advertised); debounced (`triggerKind=1`) when an identifier prefix reaches `minimumPrefixLength`. 
3. LSP connected → `minimumPrefixLength = 1`; LSP not connected → `offlineMinimumPrefixLength = 3`. Existing debounce / stale-response / out-of-focus preserved.
4. Offline fallback list keeps existing 3-char minimum unchanged.
5. Skip whitespace / closing bracket contexts (`_endsWithNonTrigger` logic replaced by `CompletionFilter.decide`; whitespace words have length < min, closing brackets don't match word); if editor already knows comment/string, skip (editor's existing token-class check not altered; no new logic needed because `isTriggering` already relies on word/prefix only and the editor does not expose comment/state to filter).

**Tests added:** `test/utils/completion_filter_test.dart` — `decide()` cases (`.` trigger, `a` prefix, whitespace skip, closing-bracket skip, offline single/two/three-letter, server-advertised trigger chars) + `parseTriggerCharacters` (default, list read, non-string ignored, empty falls back).

**Verified:** `flutter analyze` clean (0 errors); `flutter test test/utils/completion_filter_test.dart` 19 pass.

### TASK-058: Manual "Trigger Completion" command (Ctrl+Space / Edit menu / About shortcuts)
**Phase:** 24
**Status:** ✅ DONE

**Requirements:**
1. `CodeEditorPanel.triggerCompletion()` — public method calling same code path as automatic triggering but with `triggerKind=1` (Invoked), ignoring minimum-prefix/debounce rules. If caret is on empty prefix it still requests.
2. `RetroMenuBar`: `Edit > "Trigger Completion"` item (`value: 'trigger_completion'`, label: 'Trigger Completion', shortcut: 'Ctrl + Space'), wired through `onTriggerCompletion` callback.
3. `IDEShell`: keyboard listener handles `LogicalKeyboardKey.space` + `isControlOrMeta` (`isControlOrMeta` covers both platforms) and calls `_editorKey.currentState?.triggerCompletion()`.
4. If popup already open, `triggerCompletion()` refreshes it (same `requestId` increment / `setState` flow as automatic path); if closed, opens it.
5. `retro_about_dialog.dart`: 'Ctrl + Space / Cmd + Space' added to `_buildShortcutsTab` shortcuts list.
6. `README.md`: added to keyboard shortcuts section.

**Tests added:** `test/ui/editor/code_editor_panel_test.dart` — `triggerCompletion() opens popup with empty prefix (manual trigger)` (10 existing + 1 new = 11 pass for that file). `flutter test` full suite passes.

**Verified:** `flutter analyze` clean (2 info-only null-aware lint comments, 0 errors); full `flutter test` 383 pass (including new widget test).

### TASK-059: Accept selected completion with Tab (same as Enter)
**Phase:** 24
**Status:** ✅ DONE

**Requirements:** When popup visible, `Tab` calls `_acceptSelected()` same as `Enter`; when hidden, `Tab` lets Flutter's default indentation work (ignored event).

**Changes:** `_handleKeyEvent()` added `LogicalKeyboardKey.tab` branch; `README.md` updated (`Enter` / `Tab`); `About` already has `Enter / Tab`.

**Tests:** `test/ui/editor/code_editor_panel_test.dart` — 'Tab accepts selected completion when popup is visible' + 'Tab keeps current behavior (indent) when popup is hidden' (both pass).

**Verified:** `flutter analyze` clean; full `flutter test` 385 pass.

### TASK-060: Correct caret placement after accepting a completion (function calls and server snippets)
**Phase:** 24
**Status:** ✅ DONE

**Requirements:**
1. `snippet_expander.dart`: pure helper that expands LSP snippet syntax (`$0`, `$1`, `${1:default}`, `$$`). Multi-line: prefix new lines with current indentation.
2. When item `insertTextFormat == 2`, expand `insertText` through expander; caret at first tab stop (`$1` before `$2`, before `$0`); if none, at `$0`; if none, at end.
3. When item is callable (`kind` = method/function/constructor = 2/3/4/5/6/22) and text doesn't already contain `(`, insert `()` with caret between parens; skip if next char is `(`.
4. Keep `textEdit` behavior (replace range) unchanged.

**Changes:** `lib/utils/snippet_expander.dart` (new); `lib/models/lsp_models.dart` (+`insertTextFormat`); `lib/services/lsp_service.dart` (parse `insertTextFormat`); `lib/ui/editor/code_editor_panel.dart` (`_acceptSelected()` now uses expander + callable logic + `_currentLineIndent()`); `README.md` updated (`Enter` / `Tab` for autocomplete).

**Tests:** `test/utils/snippet_expander_test.dart` (7 tests — plain, $0, $1, ${1:default}, same-index, escaped $, multi-line+indent); `test/ui/editor/code_editor_panel_test.dart` — callable method test (`accepting a callable method inserts paren pair with caret inside`).

**Verified:** `flutter analyze` clean (0 errors); full `flutter test` 386 pass.

### TASK-061: Improve completion ranking (CompletionFilter) — match tiers, MRU, sortText
**Phase:** 24
**Status:** ✅ DONE

**Requirements:**
1. Keep current filtering (`startsWith` case-insensitive). Change only ranking order:
   a. tier: exact case-sensitive prefix (1) < case-insensitive prefix (2) < word-start/camelCase (3) < subsequence (4)
   b. recently accepted first (in-memory MRU)
   c. server `sortText` (fall back to label)
   d. label alphabetical
2. MRU: `Map<String,int>` label → counter, capped at 200 (drop oldest, lowest counter), session-only.
3. Pure helper/class in `lib/utils/completion_filter.dart`. No UI changes.

**Changes:** `lib/utils/completion_filter.dart` (+`_CompletionMru`, `recordCompletion()`, `_matchTier()`, `_isSubsequence()`, updated `filter()` ranking); `lib/models/lsp_models.dart` (+`sortText`); `lib/services/lsp_service.dart` (parse `sortText`); `lib/ui/editor/code_editor_panel.dart` (`_acceptSelected()` calls `recordCompletion()`); `CHANGELOG.md` updated.

**Tests:** `test/utils/completion_filter_test.dart` — ranking tier test + MRU move-up test + MRU cap-200 test (all pass). Full suite: 397 pass, 0 fail.

**Verified:** `flutter analyze` clean; full `flutter test` 397 pass.

### TASK-062: Built-in Dart/Flutter snippets in the completion list
**Phase:** 24
**Status:** ✅ DONE

**Requirements:**
1. New `lib/utils/dart_snippets.dart` with a const list of snippets (prefix, label, description, LSP-syntax body) — exactly 8: `stless`, `stful`, `main`, `fori`, `forin`, `try`, `init`, `dispose`.
2. Append matching snippets in the completion pipeline for Dart files only, both with an LSP server and offline, kind = Snippet (15).
3. Accepting a snippet expands it through `SnippetExpander` with the current line's indentation.
4. No snippets for other languages, and none after member access (`.`).

**Changes:** `lib/utils/dart_snippets.dart` (new: `DartSnippet`, `dartSnippets`, `snippetCompletions()`, `mergeSnippets()`); `lib/ui/editor/code_editor_panel.dart` (both completion paths — `_requestCompletion()` and `_requestCompletionWithTrigger()` — now fall back to the offline list when the item pool is empty, then merge snippets, then filter); `CHANGELOG.md` updated.

**Tests:** `test/utils/dart_snippets_test.dart` (8 tests — prefix match case-insensitive, empty prefix, snippet kind/format, non-Dart excluded, `.` excluded, `stless` expansion + caret on class name, `fori` expansion + first tab stop, `mergeSnippets` dedupe); `test/ui/editor/code_editor_panel_test.dart` — `typing stless and pressing Enter inserts a StatelessWidget snippet`.

**Verified:** `flutter analyze` clean; full `flutter test` passing.

### TASK-063: Completion documentation panel (completionItem/resolve)
**Phase:** 24
**Status:** ✅ DONE

**Requirements:**
1. `LspService` stores `completionProvider.resolveProvider` and sends `completionItem/resolve` only when true; each item keeps its original JSON (including `data`) so it can be sent back unchanged.
2. Selected row change → 150 ms debounce → resolve; a stale answer is ignored; results cached per item for the popup's lifetime.
3. Documentation may be a String or `MarkupContent {kind, value}`; rendered as plain text (backticks, `**`, link targets, heading markers stripped; line breaks kept; 12 lines then `…`).
4. Retro sunken panel, theme colours, `maxWidth` 320, right of the list (below when there is no horizontal room), hidden without documentation, no focus or keyboard changes.
5. Resolve unsupported/failed → fall back to the item's own `documentation`, else nothing.

**Changes:** `lib/models/lsp_models.dart` (`CompletionTextEdit`, `ResolvedCompletionItem`, `CompletionItem.documentation`/`additionalTextEdits`/`raw`/`needsResolve`); `lib/services/lsp_service.dart` (`parseCompletionResolveProvider`, `parseDocumentation`, `parseTextEdits`, `resolveCompletionItem()`, `supportsCompletionResolve`, `debugSetCompletionResolveProvider()`); `lib/utils/completion_docs.dart` (new); `lib/ui/editor/completion_doc_panel.dart` (new); `lib/ui/editor/autocomplete_popup.dart` (`documentation` parameter, right/below placement); `lib/ui/editor/code_editor_panel.dart` (150 ms doc debounce, stale-response guard, per-popup resolve cache, fallback docs); `CHANGELOG.md` updated.

**Tests:** `test/utils/completion_docs_test.dart` (6 — inline code/bold/links, headings + line breaks, fenced code, 12-line truncation, plain text, empty); `test/services/lsp_service_test.dart` — resolve group (5 — capability parse, String/MarkupContent docs, no call without capability, raw item echoed back + docs/import parsed, null answer); `test/ui/editor/code_editor_panel_test.dart` — 5 widget tests (docs after pause + follows selection, stale answer ignored, auto-import insertion, no panel without docs, fallback to item documentation).

**Verified:** `flutter analyze` clean; full `flutter test` passing.

### TASK-064: Useful Dart LSP completion options (verified, then enabled)
**Phase:** 24
**Status:** ✅ DONE

**Step A — probe findings** (`tool/probe_dart_completion_options.dart`, installed Dart SDK 3.13.2 at
`/Users/reza/dev/flutter_sdk/bin/cache/dart-sdk/bin/dart`, scratch package in a temp dir so the file is
outside this repo's `tool/**` analysis exclusion):
- Server advertises `completionProvider = {completionItem: {labelDetailsSupport: true}, resolveProvider: true, triggerCharacters: [".", "=", "(", "$", "\"", "'", "{", "/", ":"]}`.
- `workspace.applyEdit` is the gate for unimported symbols: with `applyEdit: false`, typing `Timer` (no `dart:async` import) returned 2 unrelated items; with `applyEdit: true` + `initializationOptions.suggestFromUnimportedLibraries: true`, `Timer`, `Uint8List`, `Random` and `StreamController` all appeared.
- `suggestFromUnimportedLibraries: false` (with `applyEdit: true`) removed them again → the option is honoured.
- The completion list carries **no** `additionalTextEdits`; `completionItem/resolve` on `Timer` returned
  `additionalTextEdits: [{newText: "import 'dart:async';\n\n", range: 0:0–0:0}]`, `detail: "Auto import from 'dart:async'"` and the full dartdoc → resolve is required for the auto-import.
- `dart.enableSnippets: false` via `workspace/configuration` removed all kind-15 items (`for`, `for in`); with `true`/unset they are present → the setting is honoured and defaults to on.
- `dart.completeFunctionCalls: true` produced no observable change (`print` label stayed `print(…)`); the server default is already on. It is therefore **not** sent — the caret task's `()` logic stays the only paren source.

**Step B — changes:**
1. `LspServerSpec.dart.initializationOptions = {'suggestFromUnimportedLibraries': true}` (other specs untouched).
2. `LspService` now advertises `workspace.applyEdit` and `workspace.configuration`; answers `workspace/configuration` with `{'enableSnippets': true}` for the Dart spec only (other servers keep the previous empty answer) and leaves `completeFunctionCalls` alone.
3. Accepting an item applies `additionalTextEdits` (from the resolved item, else the list item) together with the main insertion: LSP ranges → offsets, edits applied bottom-up, caret shifted by every edit above it (`lib/utils/completion_edit_applier.dart`).
4. LSP `CompletionItemKind` 15 now maps to `snippet` (was `module`), so server snippets reach the existing `SnippetExpander`; server snippets themselves are unchanged/default-on.

**Tests:** `test/utils/completion_edit_applier_test.dart` (6 — line/character mapping, clamping, import-above-the-caret caret shift with fixed LSP-shaped input, multi-edit bottom-up, no edits, invalid edit ignored); `test/services/lsp_server_spec_test.dart` (+1 — only Dart asks for unimported libraries); `test/services/lsp_service_test.dart` (+resolve group above); `test/ui/editor/code_editor_panel_test.dart` — `accepting an auto-import item inserts the import above` (document gains `import 'dart:async';` and the caret stays after `Timer`).

**Verified:** `flutter analyze` clean; full `flutter test` passing.

### TASK-065: Answer `workspace/applyEdit` with a spec-shaped result
**Phase:** 24
**Status:** ✅ DONE

**Requirement:** The client advertises `workspace.applyEdit` (the Dart server needs it before it offers completions from unimported libraries), but every server-initiated request other than `workspace/configuration` was answered with `result: null`. The LSP spec requires an `ApplyWorkspaceEditResult` object for `workspace/applyEdit`.

**Changes:** `lib/services/lsp_service.dart` — new `applyEditResult()` (static, unit-testable) returning `{'applied': false, 'failureReason': 'not supported by this client'}`; `_handleMessage` now sends that object for `workspace/applyEdit` and keeps the existing `null` answer for any other server request. The edit itself is deliberately **not** applied: accepting a completion already applies the item's `additionalTextEdits` in the editor, and the advertised capability is kept unchanged so unimported-library completions keep working.

**Tests:** `test/services/lsp_service_test.dart` — one unit test asserting the exact response shape (`applied` false, `failureReason` text).

**Verified:** `flutter analyze` clean; full `flutter test` passing.

### TASK-066: Sync the document before position-based requests (-32004 / auto-import in Untitled buffers)
**Phase:** 24
**Status:** ✅ DONE

**Problem:** the debounced `didChange` lived in `ide_shell` (250 ms), so a completion / `completionItem/resolve` / hover request for the newest text could reach the server while it still had the previous version → `[LSP] request failed: code -32004, invalid line number`, and `Timer` in an Untitled Dart buffer never offered its `dart:async` import.

**Changes:**
1. The debounce moved into `LspService.updateFile` (same 250 ms), which also makes it the service's own pending state. `_ensureSynced(uri)` is the one helper that flushes that pending change and completes after the notification is written; it is called first by `requestCompletion`, `resolveCompletionItem(item, filePath:)` and `requestHover`. (Signature help does not exist in this client yet, so there is nothing to call it from.)
2. `resolveCompletionItem` records the document version it resolved against (`ResolvedCompletionItem.documentVersion`); the editor applies `additionalTextEdits` only while `LspService.documentVersion(path)` still equals it, otherwise the auto-import is skipped instead of corrupting text.
3. A `-32004` answer now prints one line per method + document: method, line, character, document version and the server message (`_reportRequestError`, `_requestErrors` context map).
4. `ide_shell` no longer keeps its own timer/pending fields: `updateFile` is called on every change (debounced inside the service), empty buffers are flushed at once, and Run/Save flush through `flushPendingChange`.

**Probe (real Dart server 3.13.2, `tool/probe_untitled_import.dart`), virtual `untitled.dart` in a temp workspace:**

| scenario | `Timer` in list | resolve `additionalTextEdits` |
|---|---|---|
| A. bare temp dir (`compile_flags.txt` only), `rootUri` = temp dir | **yes** (9 items) | `import 'dart:async';\n\n` (0:0) |
| B. A + `pubspec.yaml` + `dart pub get` | yes (9 items) | `import 'dart:async';\n\n` (0:0) |
| C. bare temp dir, `rootUri` = repository (app's workspaceRoot) | no (2 unrelated items) | — |
| D. C + temp dir added via `workspace/didChangeWorkspaceFolders` | **yes** (9 items) | `import 'dart:async';\n\n` (0:0) |
| E. D + pubspec | yes (9 items) | same |

**Conclusion:** the temp workspace does **not** need a `pubspec.yaml` — `compile_flags.txt` plus registering the temp directory as a workspace folder (which `_ensureWorkspaceFolder` already does in `openFile`, before `didOpen`) is enough. Scenario C is what the request looked like before the folder registration/debounce fixes could take effect.

**Tests:** `test/services/lsp_service_test.dart` — new group (3): pending `didChange` is sent before `completion`; before `completionItem/resolve` (plus the version recorded on the resolved item); an unchanged document sends no extra `didChange`. `test/ui/editor/code_editor_panel_test.dart` keeps the auto-import insertion test green.

**Verified:** `flutter analyze` clean; full `flutter test` passing.

### TASK-067: Tab/Shift+Tab belong to the editor
**Phase:** 24
**Status:** ✅ DONE

**Problem:** with the popup hidden the Tab key returned `KeyEventResult.ignored`, so Flutter's default focus traversal moved focus out of the `TextField` and the caret disappeared.

**Changes:** `_handleKeyEvent` now always returns `handled` for Tab. With the popup open it accepts the selected item (same path as Enter); otherwise `_handleTabPressed` inserts two spaces at the caret, indents every line of a multi-line selection, and Shift+Tab outdents those lines by up to two spaces (one `\t` or up to two spaces per line, selection offsets adjusted). Enter, Esc, arrows and the closing-bracket logic are untouched.

**Tests:** four widget tests in `test/ui/editor/code_editor_panel_test.dart` — Tab inserts two spaces and the editor keeps `hasPrimaryFocus`; Shift+Tab outdents `    four` to `  four`; Tab indents both lines of a selection; the pre-existing "Tab accepts selected completion" test still passes.

**Verified:** `flutter analyze` clean; full `flutter test` passing.

### TASK-068: Parentheses for function/method completions
**Phase:** 24
**Status:** ✅ DONE

**Changes:** `CompletionItem.kindInt` now keeps the raw LSP `CompletionItemKind` (plus `detail`/`insertText`/`insertTextFormat` as before); the accept logic moved into a pure helper, `lib/utils/completion_insert.dart` (`buildCompletionInsertion`): a plain item whose raw kind is 2/3/4 gets `()` with the caret between unless the text already has `(`, the document already has `(` after the caret, or the item is a snippet (the server's snippet is authoritative — `setState` arrives as a snippet with its own parentheses). Built-in snippets now carry `kindInt: 15`. `print`/`setState` log their raw payload once per session.

**What the server actually sends (probe `tool/probe_print_setstate_items.dart`, Flutter scratch package):**

| label | kind | insertText | insertTextFormat | textEdit.newText | detail |
|---|---|---|---|---|---|
| `print(…)` (`filterText: print`) | 3 | — | — | `print` | `(Object? object) → void` |
| `setState(() {});` (`filterText: setState`) | 2 | — | 2 | `setState(() {\n      $0\n    });` | `(void Function() fn) → void` |

So `print` needs the pair added by the client (kind 3, no parentheses anywhere) while `setState` is a snippet that already contains them and must not get another pair.

**Tests:** `test/utils/completion_insert_test.dart` (11): table for `print`, `setState`, a field, a class, an existing `(` after the caret, text that already has `(`, snippet with parentheses, snippet without, plus kind-name fallback, kinds 3/4, snippet indentation. Existing widget accept tests stay green.

**Verified:** `flutter analyze` clean; full `flutter test` passing.

### TASK-069: Completion popup and doc panel anchored inside the editor
**Phase:** 24
**Status:** ✅ DONE

**Problem:** `AutocompletePopup` was a `Positioned` child of the editor Stack but received a **global** caret offset, and the doc panel decided "right or below" from the window width. The list appeared shifted by the panel's global origin and its lower rows could be hidden under the Console.

**Changes:** `CodeEditorPanelState` now has `_editorStackKey`; `_caretAnchorRect()` converts the renderer's caret rect into Stack-local coordinates and `_editorBounds()` supplies the Stack's size. `AutocompletePopup` takes `anchor` + `bounds` instead of `position` and computes everything with `_CompletionPlacement` (pure geometry): left clamped inside the editor, below the caret, flipped above when below does not fit, otherwise the larger side with a scrolling list; the doc panel goes right, else left, else below/above, always inside the bounds. The popup is a `Positioned.fill` Stack with `Clip.hardEdge`, so nothing can paint outside the editor. Gutter, line height and `EditorMetrics` untouched.

**Tests:** two widget tests in `test/ui/editor/code_editor_panel_test.dart` — a 160 px-tall editor with the caret on the last line puts the list above the caret and inside the panel; a 700 px editor with the caret near the right edge puts the doc panel left of the list and inside the panel.

**Verified:** `flutter analyze` clean; full `flutter test` passing.

### TASK-070: "Trigger Completion" that actually works
**Phase:** 24
**Status:** ✅ DONE

**Problems:** macOS consumes `Cmd+Space` (input-source switch), the shell's key handler tested `isControlOrMeta` *before* the completion branch (so Ctrl+Space fell into the zoom branch and did nothing), and the menu callback could not reopen the popup because the menu had taken the focus.

**Changes:**
1. New main shortcut **Ctrl+Shift+Space**; Ctrl+Space stays bound. The completion branch now runs before the zoom branch and checks `HardwareKeyboard.instance.isControlPressed`, so Cmd+Space is no longer bound. Menu label and About shortcuts tab show `Ctrl + Shift + Space`; README updated.
2. Edit > Trigger Completion calls `CodeEditorPanelState.triggerCompletionFromCommand()`, which restores the editor's focus and, after the next frame (scheduled explicitly, since an idle editor has no frame pending), opens completion at the last known caret.
3. With a connected LSP, an empty server answer now means an empty list: no offline fallback and no error. The offline keyword list is still used when no server is attached.

**Tests:** two widget tests — the command refocuses an unfocused editor (primary focus restored, `triggerKind = 1`, popup visible) and an empty server answer shows no popup and no exception.

**Verified:** `flutter analyze` clean; full `flutter test` passing.

### TASK-071: Documentation panel after 2 s idle — and why it never appeared for an Untitled buffer
**Phase:** 24
**Status:** ✅ DONE

**Cause found (probe `tool/probe_untitled_resolve_docs.dart`):** the panel was not a timing problem at all — for an Untitled tab the editor asked the server about the document path `Untitled` (the tab's display name), while the server has that buffer open under its virtual temp path (`.../untitled.dart`), so completion returned 0 items and the list shown was the offline keyword/token fallback with no `raw` JSON to resolve; the same probe resolves `print`, `List` and `DateTime` on the open document and gets `documentation` (538 / 3974 / 4304 chars) with `detail` only as the signature (`(Object? object) → void`), i.e. the server sends the text in `documentation`, never in `detail` alone.

**Changes:** `CodeEditorPanelState._lspDocumentPath` (the service's `activeDocumentPath`, falling back to the tab path) is now used for completion and `completionItem/resolve`, so Untitled buffers talk to the document the server really has open. (Hover was left untouched: it does not feed the panel.) The doc pipeline was split into two clocks: resolve after the existing 150 ms debounce (so docs and `additionalTextEdits` are cached before an accept — accept unchanged), display after `kCompletionDocPanelDelay` = 2 s. `_hideCompletionDoc()` cancels both timers, invalidates pending answers and hides the panel immediately on any selection change, key press or popup close. Documentation resolves from `documentation`, then the resolved `detail`, then the item's own `documentation`. A `[completion-doc] "<label>" resolved=… documentation=… detail=…` line is printed once per resolved item.

**Tests:** `test/ui/editor/code_editor_panel_test.dart` — panel absent at 1.9 s and present at 2.0 s idle (plus selection change hides it and restarts the clock); a key press hides it and restarts the clock; `detail` fallback; and an Untitled buffer requests completion/resolve with the virtual `.../untitled.dart` path instead of `Untitled`. Previous doc-panel tests updated for the new delay.

**Verified:** `flutter analyze` clean; full `flutter test` passing (454 pass, 8 skipped).

### TASK-072: Colorful scheme: own colors for operators, curly braces and square brackets
**Phase:** 24
**Status:** ✅ DONE

**Changes:** in the Colorful scheme only, split the shared bracket/punctuation category into three — parentheses keep `punctuation` (`#031CFC`, unchanged), while `{` `}` and `[` `]` now resolve to new `curlyBrace` / `squareBracket` categories via the patched single-character rules in `MultiLanguageHighlighter.patchSymbolModes()` (applied to Dart, C, C++, Python and the ARM64 grammar, so the split is consistent for all five languages and survives inside Python/C f-string/interpolation substitution). Named constants `colorfulOperatorColor = #687d01`, `colorfulCurlyBraceColor = #1e64d8` and `colorfulSquareBracketColor = #00796f` hold the Colorful accents in one place; Standard maps the new categories onto the old bracket color so it stays byte-for-byte identical.

**Tests:** new `test/utils/colorful_syntax_colors_test.dart` paints the three sample lines through the real `SpanBuilder` path and asserts operators `#687d01`, braces `#1e64d8`, square brackets `#00796f`, parentheses still `#031CFC` (Dart, Python, C), that Standard stays on `#031CFC`/`#00BF69`, and that text inside plain strings and comments is never recolored. One existing assertion in `asm_syntax_colors_test.dart` was updated to the new category (still `bracketColor` there) — no test was weakened.

**Note:** the task brief listed `#408fff` / `#06baab` in the "verify manually" sentence but `#1e64d8` / `#00796f` in the NEW COLORS block; the NEW COLORS block was followed.

**Verified:** `flutter analyze` clean; full `flutter test` passing (454 pass, 8 skipped).

### TASK-073: Editor surface `#fbfbf9` for every theme, grey Colorful comments
**Phase:** 24
**Status:** ✅ DONE

**Changes:** the code surface moved from `#E8F1FF` to `#fbfbf9` in all four themes and both syntax schemes, and now lives in one named constant — `kEditorBackgroundColor` in `lib/services/theme_service.dart` — which every `ThemeColorsData` and therefore every `editorBackground` reader (editor container, empty-editor message, tab bar, hover tooltip, completion popup, doc panel, About/Go-to-Line fields) picks up. In the Colorful scheme only, comments moved from `#596E48` to `#666666` (new `colorfulCommentColor`, still italic); Standard is byte-for-byte identical.

**Untouched on purpose:** everything tuned against the old surface — current-line band (`colors.selection` at alpha 0.14 fill + 0.45 hairline: `#316AC5` / `#A08035` / `#1B3260` / `#000080`), editor selection `#000080` + `#FFFFFF`, paused line `#FFF0A0` / `#E9D9A5` / `#DCDCA8` / `#DCDCA8`, popup/doc-panel/hover borders and backgrounds (they inherit `kEditorBackgroundColor`), and every other token color.

**Docs:** ARCHITECTURE (four theme blocks, the shared-surface note, palette comment row), README (theme table, syntax bullet), `docs/RETRO_DESIGN.md`, and one CHANGELOG `[Unreleased]` line.

**Tests:** no new tests; no assertion pinned the old values (the Standard comment assertion `#596E48` still holds). `flutter analyze` clean; full `flutter test` passing (460 pass, 8 skipped).


### TASK-074: The editor surface is the console surface — and why it is one constant
**Phase:** 24
**Status:** ✅ DONE

**What was tried and reverted:** binding `editorBackground` to each theme's `panel` color (`#ECE9D8` / `#DFCD9B` / `#C0C0C0` / `#8FB8B8`) looked wrong and made the gutter disappear, because the gutter already paints `editorLineNumberBg` with those same three values (`#ECE9D8` / `#DFCD9B` / `#C0C0C0`) and has no separator line of its own — editor and gutter became one flat block. Reverted to the single shared `kEditorBackgroundColor`; the gutter colors are untouched and visible again.

**What stayed:** the editor surface is one constant for all four themes and both schemes — `kEditorBackgroundColor` = `#fbfbf9` — and the console's output area paints that same constant instead of a hard-coded pure `#FFFFFF`. The two panes are therefore exactly the same near-white surface; there is no second constant to drift.

**Untouched:** gutter (`editorLineNumberBg`: `#ECE9D8` / `#DFCD9B` / `#C0C0C0` / `#00A8A8`), current-line band, selection, paused line, popup/hover/doc-panel borders, the console chrome (`panel`) and the stdin bar (`#FFFFFF` while running, `#F0F0F0` when idle). Colorful strings stayed `#409175`, Colorful comments `#666666`, Standard byte-for-byte identical.

**Tests:** no new tests, no assertion pinned these values. `flutter analyze` clean; full `flutter test` passing (460 pass, 8 skipped).

### TASK-075: 2.5 px caret that blinks 300 ms on / 300 ms off — superseded by TASK-084
**Phase:** 24
**Status:** ⚠️ SUPERSEDED — the 300 ms custom overlay was removed in TASK-084 (it did not
paint in the release build); the built-in caret with `cursorWidth: 2.5` and Flutter's own
blink is used instead. Blink speed is not configurable in Flutter.

**Step A — findings:**
1. The editor is a plain Material `TextField` (`code_editor_panel.dart`, inside the editor `Stack`), not a `CodeField`, so the public `cursorWidth` and `showCursor` parameters are available; the controller is a `CodeController` and the theme/strut come from `EditorMetrics`.
2. In the installed Flutter 3.47.2 SDK the blink period is **not** configurable: `packages/flutter/lib/src/widgets/editable_text.dart` declares `const Duration _kCursorBlinkHalfPeriod = Duration(milliseconds: 500)` and only exposes it through a `@visibleForTesting` getter (`cursorBlinkInterval`). There is no `TextField`/`EditableText` parameter for it.

**Step B — implementation (historical; the overlay was removed in TASK-084):** `cursorWidth: kEditorCaretWidth` (2.5) on the field, and `showCursor: false` because the period cannot be retimed. A new `EditorCaret` stateful widget paints the caret into the editor's inner `Stack` with `Positioned` + `IgnorePointer`:
- a `Timer.periodic(kEditorCaretBlinkInterval)` (300 ms) toggles it on/off;
- `resetToken` (a counter bumped by every text change in `_onTextChanged` and every caret move in `_onCaretMoved`) makes it solid again and restarts the clock, so typing never shows a blinking-off caret;
- `active` is false without focus or with a non-collapsed selection, so no caret is painted then (and the timer stops);
- the rect is `_caretAnchorRect()` — the same live `RenderEditable` measurement used for the popup anchor — refreshed in the existing `_queueBandUpdate()` post-frame pass, which is already wired to text, caret, scroll, zoom and font-change notifications, so it follows scrolling, zoom, fonts and RTL;
- the color is `RenderEditable.cursorColor`, i.e. exactly what the built-in caret painted; the timer is cancelled in `dispose()`.

**Tests:** new `test/ui/editor/editor_caret_blink_test.dart` — visible at 0 ms, hidden at 300 ms, visible again at 600 ms, and visible immediately after a key press. `flutter analyze` clean; full `flutter test` passing (462 pass, 8 skipped). *(That test was deleted with the overlay in TASK-084: it asserted the widget's size/visibility, never the painted colour, which is why it passed while the release app showed no caret.)*

### TASK-076: Gutter separator, current-line emphasis, diagnostic markers and marker tooltip
**Phase:** 24
**Status:** ✅ DONE

**Scope guard:** the gutter's width (`EditorMetrics.gutterWidth`), row height, line-number advance and the `_rowsFromRenderer()` row model are untouched; every existing gutter alignment/baseline test passes unchanged. No change to the debugger, completion, syntax colors or `EditorMetrics`.

**Changes:**
- **Separator** — the gutter `Container` now holds a `Stack`: the existing `ListView` plus a `Positioned` 1 px pair (`borderDark`, then `borderLight`) on its right edge. It is drawn *inside* the gutter's width, so nothing moves, and it derives from the theme borders already in `ThemeColorsData`, so all four themes get it with no new palette entry.
- **Current line** — its number is bold in `colors.text`; its row tint changed from `selection @ 0.10` to `selection @ 0.14`, the exact band fill. Other numbers paint `editorLineNumberText.withValues(alpha: 0.7)`, but lines carrying a diagnostic marker (or the paused line) keep full strength.
- **Diagnostic markers** — `_diagnosticsByLine()` groups `LspService.activeDiagnostics` (the existing per-URI map; no new analysis) by 1-based line, errors sorting before warnings. The worst severity paints an 8x8 square at the inner edge — `kGutterErrorMarkerColor` `#D32F2F`, `kGutterWarningMarkerColor` `#F9A825` — appended last in the row's right-hand group so the breakpoint bullet stays to its left. Continuation rows (`gutterRows[index] == 0`) still return early, so a wrapped line has exactly one marker. `CodeEditorPanel` now listens to the `LspService` (added/replaced/removed in `initState`/`didUpdateWidget`/`dispose`), so a `publishDiagnostics` — including an empty list — and a tab switch both repaint.
- **Tooltip** — the marker is wrapped in a `MouseRegion` (hover only, no gesture handler, so the row's opaque `GestureDetector` still toggles the breakpoint). `GutterDiagnosticTooltip` paints up to three messages, errors first, each collapsed to one line and ellipsized at 60 characters, with `RetroBorder.raised` on the editor surface (the `HoverTooltip` look) and an `IgnorePointer`, so it takes neither focus nor taps.

**Tests:** new `test/ui/editor/gutter_diagnostics_test.dart` — a fake `LspService` publishes an error line, a warning line, a clean line and a 600-character line that really wraps (asserted via the gutter's own geometry); the markers are red/amber/absent/single, and all disappear when the list is cleared. Two old assertions that pinned the previous look were updated (`editor_current_line_test.dart`): gutter tint `0.10` -> `0.14` and the caret-line number colour `selection` -> `colors.text`. `flutter analyze` clean; full `flutter test` passing (463 pass, 8 skipped).

### TASK-077: Real File Explorer — lazy tree, open folder, markers of the active tab
**Phase:** 24
**Status:** ✅ DONE

**Built:**
- `lib/models/file_node.dart` — `path`, `name`, `isDirectory`, `children`, `childrenLoaded`, `expanded`, `isTruncationNotice`; pure Dart.
- `lib/services/file_explorer_service.dart` — one directory per call (children read only when a folder is expanded), folders first then case-insensitive names, dot names + `build` / `.dart_tool` / `node_modules` / `__pycache__` / `.DS_Store` hidden, `maxEntries = 2000` plus a "… N more not shown" row, `FileSystemException` → empty folder and never a crash. Also `refresh()`, `revealFile()`, `contains()` and `readFileForOpen()` (2 MB / NUL-in-first-4-KB guard). Reads are **synchronous internally** with async signatures: a `Directory.list()` future created inside a widget callback never completes under the widget test's fake clock, which made the tree untestable and could stall the UI pass.
- `lib/ui/explorer/file_explorer_panel.dart` — sunken retro panel: folder name header, ⟳ refresh, `Open Folder...` empty state, rows with disclosure triangle, language logo (`LanguageLogo`) or folder/file glyph and depth indentation, single click selects + toggles a folder, double-click opens a file through `onOpenFile`, active tab bold + tinted, parents expanded.
- Shell: `FileExplorerService` instance, `File > Open Folder...` (`Cmd+Shift+O`, bound before the plain `Cmd+O` branch) and `Close Folder`, explorer double-click → guards → `FileService.restoreFile` (the one existing open path, so an already-open file just switches tab), Console line `Not opened: binary or too large` on refusal, refresh after a save, session restore of the folder.
- `SessionService.openFolderPath` — persisted in `session.json`, restored only when the directory still exists.

**Scope:** no create / rename / delete / drag-and-drop.

**Tests:** `test/services/file_explorer_service_test.dart` (sorting, hidden names, lazy children, 2000 cap, unreadable folder, binary/oversized refusal) and `test/ui/explorer/file_explorer_panel_test.dart` (folder click expands, double-click calls the open callback, active file bold). `flutter analyze` clean; full `flutter test` passing (470 pass, 8 skipped).

### TASK-078: A `.s` file holding C/C++ is reported as C/C++, not compiled as assembly
**Phase:** 24
**Status:** ✅ DONE

**Cause:** TASK-054's blanket guard ("`#include` in an assembly file is never a mismatch") also swallowed a
real C/C++ program: `#include <iostream>` + `std::` was handed to `clang -arch arm64` as assembly and failed
with `'iostream' file not found`.

**Fix (resolver only):** `_assemblyMismatch()` replaces that guard for `armasm` buffers. A bare `#include` —
quoted (`#include "macros.h"`) or angle-bracket alone — is still preprocessed assembly and reports nothing.
`#include <` **together with** `int main(` / `void main(`, `std::`, `using namespace`, `<iostream>`, `<vector>`
or `<string>` is a C/C++ mismatch: **C++** when one of those C++ markers is present, otherwise **C**. Dart
(`import 'dart:` / `import 'package:` / `void main(`) and Python signals remain mismatches exactly as before.
All other extensions go through the unchanged TASK-054 path. The Console message is still the one
`LanguageResolution.mismatchMessage()` line and now names the detected language.

**Tests:** `test/models/language_resolution_test.dart` — `#include "macros.h"` alone → none; `#include <iostream>`
+ `int main()` → C++; `#include <cstdio>` + `using namespace std` → C++; `#include <stdio.h>` + `int main()` → C;
the real `samples/array_sum_arm64.s` → none; Dart in `main.s` → Dart (unchanged). `flutter analyze` clean; full
`flutter test` passing (487 pass, 8 skipped).

### TASK-079: Per-tab language selection drives Run, Debug, colors and the logo
**Phase:** 24
**Status:** ✅ DONE

**Symptoms:** the toolbar dropdown was app-wide, so choosing Python on one tab left "Python" selected on a `.c`
tab and Run executed the C file as Python; an explicit choice on `main.s` steered Run but not the colors or the
language logo, which still came from the extension.

**Changes:**
- `TabFile.languageOverride` (default `'Auto'`, **in memory only**, never in the session). `FileService`
  exposes `activeLanguageOverride` / `setActiveLanguage()` and preserves the value across `saveFile`,
  `saveTab` and `saveFileAs`; a new tab starts at Auto and a closed tab drops it.
- One function — `LanguageConfig.resolveTab(tab)` — returns `LanguageResolution` with the tab's explicit
  selection first, otherwise the existing extension/content resolver (and its mismatch rules, unchanged).
- Consumers: `LanguageRunnerService.runActiveFile()`, the toolbar's Run callback (`runCode(...,
  preferredLanguage:)`), the Debug button, `MultiLanguageHighlighter.createController(preferredLanguage:)`,
  `CodeEditorPanel` (`languageOverride`) and `PanelLayout._detectLanguageExt` (logo).
- The dropdown reads/writes the active tab. Changing it swaps only the grammar through `_applyGrammar()` —
  text, caret and scroll position are untouched — and the logo repaints in the same frame. `PanelLayout`
  rebuilds only when the active tab index or its override changes, not on every keystroke.
- **Follow-up (owner feedback):** Material's `DropdownButton` enforces a 48 px item height, taller than the
  44 px panel header. It is now a compact `PopupMenuButton`: a sunken 28 px field (12 px label + 18 px caret,
  `popupMenuPosition.under`) and 30 px retro menu rows with the current value in bold. Keys:
  `kLanguageDropdownKey` / `kLanguageDropdownLabelKey`.
- **Follow-up (TASK-086):** the code editor now has its own retro right-click menu (Cut / Copy / Paste /
  Select All) built on the field's `contextMenuBuilder`, so a secondary click — including on an empty,
  unfocused buffer — always opens it. See TASK-086.

**Known limitation (fixed in TASK-087):** at the time, the language server for a tab was still chosen from its
extension/content (`LspServerManager.activateFor`), not from the per-tab selection: choosing Dart on `main.s`
changed Run, colors and the logo, but diagnostics kept coming from the server the `.s` extension picked. Since
TASK-087 the server, the language id sent in `textDocument/didOpen` and the diagnostics all follow the effective
language, through a virtual document for the mismatching cases.

**Tests:** new `test/ui/shell/per_tab_language_test.dart` — tab A (Python) + tab B (Auto, `.c`): B shows Auto and
its Run path resolves to C; switching back to A shows Python and passes it to Run; selecting Dart on a `.s` tab
changes `controller.language` and the logo to Dart while keeping text and caret, and Auto returns to assembly.
`flutter analyze` clean; full `flutter test` passing (487 pass, 8 skipped).

### TASK-080: Explorer "Open Folder..." matches the Console header buttons
**Phase:** 24
**Status:** ✅ DONE

`RetroButton` now owns `kRetroHeaderButtonHeight = 22` (its own default), and the Console header's
Copy All / Copy Errors / Clear pass that constant instead of a literal `22`. The explorer label dropped its
local `fontSize: 11` override so it uses the same `RetroButton` text style. **Follow-up (owner feedback):** the
empty-state **Open Folder...** button must read as the panel's main action, so it now fills the panel width and
is a little taller — `kOpenFolderButtonHeight = 28` — with the label centered horizontally and vertically by
`RetroButton`. Verified in all four themes. No new tests.

### TASK-081: "+" tab button, distinct Untitled names and distinct virtual documents
**Phase:** 24
**Status:** ✅ DONE

- `TabBarWidget` draws a `RetroButton` "+" (`kNewTabButtonKey`, tooltip **New File**) in a `Row` outside the
  horizontal tab `SingleChildScrollView`, so it stays pinned at the strip's right edge when tabs overflow. Its
  height is `kEditorTabHeight` (28), the same constant the tab container now uses; the glyph itself was made
  bigger on owner feedback (bold, 18 px, `height: 1.0`).
- The click calls `fileService.createNewFile()` — the same path as **File > New** and the toolbar's New button.
- `createNewFile()` names tabs `Untitled`, `Untitled 2`, `Untitled 3`, … (first free name among open tabs).
- `UnsavedBufferWorkspace.pathFor(config, bufferName:)` slugifies the tab name, so two Untitled tabs are
  `untitled.dart` and `untitled-2.dart` (and `untitled.py` / `untitled-2.py`): separate LSP documents, so
  neither overwrites the other's diagnostics. The shell passes `_fileService.activeTab?.fileName`.

**Tests:** new `test/ui/editor/tab_bar_new_file_test.dart` — tapping "+" adds and activates an Untitled tab,
tapping twice gives `Untitled` + `Untitled 2`; the two get `untitled` / `untitled-2` virtual documents; closing
a tab drops its language selection; with 12 tabs the "+" stays inside the strip at `kEditorTabHeight`.
`flutter analyze` clean; full `flutter test` passing (487 pass, 8 skipped).

### TASK-082: Completion rows show a kind badge and the item's detail
**Phase:** 24
**Status:** ✅ DONE

- The model already kept what the badge needs: `CompletionItem.kindInt` (the raw LSP `CompletionItemKind`) and
  `CompletionItem.detail`. No model change was required.
- New pure helper `lib/utils/completion_kind.dart`: `completionKindBadge(int? kind)` maps
  Method/Function/Constructor (2/3/4) → **M**, Field/Property (5/10) → **F**, Variable (6) → **V**,
  Class/Interface/Struct (7/8/22) → **C**, Enum/EnumMember (13/20) → **E**, Keyword (14) → **K**,
  Snippet (15) → **S**, Constant (21) → **#**, Module (9) → **P**, anything else (including `null`) → **·**,
  and groups them into `callable` / `value` / `type` / `keyword` / `plain`.
- `completionBadgeColor(category, scheme)` resolves its colour through
  `MultiLanguageHighlighter.completionColor()` — the same per-category styles the editor paints with — so a
  badge is never hardcoded: callable = function colour, value = number colour, type = type colour,
  keyword = keyword colour, plain = identifier colour. The popup listens to both `ThemeService` and
  `EditorSettingsService`, so switching `View > Syntax Colors` repaints the badges live.
- Each row is a single `Row`: `CompletionBadgeChip` (16x16, 2 px `RetroBorder.flat` square, near-white
  `editorBackground` fill so it stays legible on a selected dark row, 10 px bold letter) + label + the detail
  right-aligned, dimmed (70 %) and ellipsized (`maxLines: 1`, `softWrap: false`). The row keeps a single line, so
  its height does not change and nothing wraps; `_CompletionPlacement` now estimates every row at 24 px.
- **Tests:** `test/utils/completion_kind_test.dart` (full kind → letter table, unknown/null, colour categories,
  palette-derived colours per scheme) and `test/ui/editor/completion_badge_test.dart` (badge letters and detail
  text in one row, ellipsis/right alignment, colours follow the scheme, no overflow in all four themes).

### TASK-083: No caret and no autocomplete in the built .app after "always start empty"
**Phase:** 24
**Status:** ✅ DONE

**Step A — investigation (two independent causes, both confirmed):**

1. **Focus.** Nothing requested focus on launch or on a tab change. `CodeEditorPanel`
   only called `_focusNode.requestFocus()` from a click (`onTapUp`), `goToLine` and
   `triggerCompletion`; `_showEditorCaret` is `_focusNode.hasFocus && …`, so the custom
   caret overlay painted a 0×0 box (and ran no blink timer) until the first click, and
   keys went nowhere. This is not release-specific — it was simply invisible while a
   restored file made the app look "already working". Verified with a widget test: with
   the tree pumped and no tap, the editor's `focusNode.hasFocus` is now true and
   `FocusManager.instance.primaryFocus` is that node.
2. **PATH.** A .app opened from Finder/`open` inherits launchd's minimal
   `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, not the login shell's. Reproduced exactly as
   asked:
   ```
   env -i HOME=… build/macos/Build/Products/Release/"Classic Code Editor.app"/Contents/MacOS/"Classic Code Editor"
   flutter: LspService (dart) failed to start: ProcessException: No such file or directory
   flutter:   Command: dart language-server --client-id=ClassicCodeEditor …
   ```
   `dart` lives in the Flutter SDK (`…/dev/flutter_sdk/bin`), so the Dart server never
   started; the empty Untitled buffer then had no server and completion fell back to
   `CompletionFilter.generateFallbackCompletions`, which offers only keywords and words
   already in the document — no `print`, no members. That is why "autocomplete does not
   work" rather than "no Dart suggestions". `Run`/`Debug` of Dart would have failed the
   same way (`_findExecutable('dart')` → bare `dart` → `Process.start` error), and
   `clang`/`python3` were only reachable because of `/usr/bin` / absolute candidates.
   With `flutter run -d macos` the app inherits the terminal's PATH, so the server
   connects and completion works: the difference is the environment, not the build mode.
3. **Something else (contributing).** On this machine `zsh -lc 'command -v dart'` *also*
   returns nothing, because `~/.zshrc` (interactive only) is where the Flutter SDK is
   added to `PATH`. So a login-shell lookup limited to `-lc` would still miss `dart`;
   the resolver therefore tries `zsh -lic` (the shell Terminal gives the user) first and
   falls back to `-lc`, both bounded by the 2 s timeout.

**Step B — fix:**
- **Focus:** `CodeEditorPanel._requestFocusAfterFrame()` runs in `initState` and on every
  active-tab change (`_onFileServiceChanged`), posts a frame, gives the caret a valid
  position if it had none (a focused field otherwise jumps to the end of the buffer;
  marking the text programmatic keeps this from being mistaken for an edit) and calls
  `_focusNode.requestFocus()`. Clicking the editor behaves exactly as before.
- **PATH:** new `lib/services/tool_path_resolver.dart`. Order: the caller's absolute
  candidates → `zsh -lic`/`-lc` `command -v` (cached per tool, 2 s timeout, always off
  the UI thread) → common locations (`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`,
  `~/.pub-cache/bin`, `~/flutter/bin/cache/dart-sdk/bin`, every login-PATH directory).
  For `dart` the SDK that sits next to the `flutter` on the login PATH wins, so the
  server matches the SDK the user builds with. `LspService` reports every tried location
  in the thrown `ProcessException`, so the status-bar tooltip and the one-line Console
  hint name them; when nothing is found the old fallback (offline completion) is intact.
  `ToolPathResolver.processEnvironment()` builds the child `PATH` (login first, then the
  app's own, then the common dirs) and is passed to the language-server process, the Run
  runner (`dart run`, `python3`, `clang`, `clang++`, assembly) and the Dart/Python/C/ASM
  debugger spawns. `LanguageRunnerService._findExecutable` uses the same resolver instead
  of a bare `which`.

**Tests:** `test/services/tool_path_resolver_test.dart` (login-shell hit, common-location
fallback, Dart-next-to-Flutter preference, nothing found with every tried location, alias
answers ignored, child `PATH` order + de-duplication — shells and file existence faked);
`test/ui/editor/editor_focus_test.dart` (after the first frame the editor has primary
focus; a tab change takes focus back after something else stole it). Verified against the
real environment under `env -i PATH=/usr/bin:/bin`: the resolver returns
`…/dev/flutter_sdk/bin/dart`, `/usr/bin/clangd`, `/opt/homebrew/bin/pyright-langserver`,
`/usr/bin/clang`, `/opt/homebrew/bin/python3`.

### TASK-084: Release-build caret investigation, completion warm-up and server provenance
**Phase:** 24
**Status:** ✅ DONE

**Step A — caret, measured in the real release binary** (`flutter build macos --release`,
then `open build/macos/Build/Products/Release/Classic Code Editor.app` and
`screencapture -x /tmp/ccedit.png` + region captures at ~100 ms intervals; temporary
`debugPrint`s in the caret overlay and in the band's post-frame pass recorded focus,
rect, visible flag, timer ticks and painted size, and were removed afterwards):
1. **Focus was never granted at launch.** `IDEShell` wrapped the app in
   `KeyboardListener(focusNode: _shellFocusNode, autofocus: true)`, so the shell node won
   the initial focus and the editor's `FocusNode.hasFocus` stayed false — the overlay's
   `active` gate (`hasFocus && …`) meant nothing was painted and no timer ran. Widget
   tests never saw it because they pump the panel alone, without the shell's autofocus.
2. **After a click the bar was painted fully transparent.** With focus the log showed
   `active=true visible=true on=true rect=…,2.5,22`, yet the screen never changed between
   blink phases. The colour came from `_renderEditable()?.cursorColor`, and
   `RenderEditable` reports its cursor colour with **alpha 0 whenever `showCursor` is
   false** — which was exactly the case, since the overlay replaced the built-in caret.
   A temporary `Positioned.fill` + `CustomPaint` probe proved the subtree did paint, so
   the invisible result was the transparent colour, not clipping or geometry.
3. **Conclusion:** the custom overlay cannot be relied on in a release build, and Flutter
   offers no public blink-period knob. The overlay (widget, painter, timer, rect/colour
   bookkeeping, `showCursor: false`) was **removed**; the built-in `EditableText` caret is
   back with `cursorWidth: kEditorCaretWidth` (2.5) and Flutter's default blink.
   `editor_caret_blink_test.dart` was deleted; `editor_focus_test.dart` keeps the
   "primary focus after the first frame" guarantee.
4. **Focus kept fixed:** the shell's `autofocus: true` is gone (key events still bubble to
   its `KeyboardListener`), and `CodeEditorPanel._requestFocusAfterFrame()` focuses the
   editor after the first frame and after every tab change.

**Step B — completion warm-up (same round):**
- Tool paths resolve in parallel (`flutter`/`dart` lookups start together) and the Dart
  server is started from `IDEShell.initState` instead of waiting for the first tab, so
  `initialize` overlaps the first frame; status shows **LSP: Starting…** until it answers.
- If the popup is showing the local list, it **re-queries automatically** on a bounded
  backoff (300 ms → 1 s → 2 s → every 2 s, 20 s window; `lib/utils/completion_retry.dart`)
  while the prefix is unchanged, and replaces the list when a non-empty answer arrives —
  without touching focus.
- `kindInt`/`detail`/`documentation` survive the whole pipeline (they are never copied);
  offline keywords now carry LSP kind 14 so local words alone use the neutral "·" badge,
  and a server item shows its real `M/F/C/…` badge and signature detail.
- The exact word being typed is never offered as a candidate (`CompletionFilter.filter`),
  case-insensitively; snippets are exempt so `stless` still expands.
- One `debugPrint` per completion request: elapsed ms since launch, round-trip ms,
  document path, source (`lsp`/`local`), item count and the first three kind/label/detail.

**Verification in the real app:** with the overlay removed, the release build paints the
built-in caret at the caret offset (checked in screenshots of the running app while
typing), and `[completion]` lines show the first server answer arriving once, with
`source=lsp` and `kind 3` for `print`; before the fix the same buffer produced only
`source=local` items (`pri`/`print`, both "·") for the first ~10 s.

### TASK-085: Editor caret thickness 2.5 → 5.0 px
**Phase:** 24
**Status:** ✅ DONE

The caret is the built-in `EditableText` one (TASK-084), so this is a one-line change:
`kEditorCaretWidth` in `code_editor_panel.dart` goes from `2.5` to `5.0` and stays the only
place the width is set (`cursorWidth: kEditorCaretWidth` on the field). Blink logic, the
gutter, completion and everything else are untouched; no test asserts the width, so the
suite is unchanged.

### TASK-086: Right-click Cut / Copy / Paste / Select All in the code editor
**Phase:** 24
**Status:** ✅ DONE

**Step A — how the editor's field is built:** `CodeEditorPanel` uses a plain Material
`TextField` (`code_editor_panel.dart`, keyed `_editorKey`) inside the editor `Stack`; no
`contextMenuBuilder` was supplied, so a secondary click fell through to Flutter's
`AdaptiveTextSelectionToolbar`. Two things kept the app's own menu from ever appearing:
the toolbar was the generic Material one (not the retro look) and the surrounding
`GestureDetector` registered `onSecondaryTapDown` (for diagnostics hover), which competed
for the same gesture. A probe test confirmed the framework *does* build a toolbar for a
secondary tap on an empty, not-yet-focused buffer — the tap handling was fine, the menu
was simply not ours.

**Step B — implementation:**
- New `lib/ui/editor/editor_context_menu.dart`: `EditorContextMenu`, supplied through
  `TextField.contextMenuBuilder`, so Flutter shows it at the pointer for every secondary
  click (right click and Control+click on macOS) — empty document, no selection, existing
  selection, unfocused editor, after a tab switch. Rows: **Cut** (`Cmd X`), **Copy**
  (`Cmd C`), **Paste** (`Cmd V`), a separator, then **Select All** (`Cmd A`).
- Enabled states: Cut/Copy only with a non-collapsed selection; Paste whenever
  `Clipboard.hasStrings()` is true (checked in `initState`, so a slow platform answer
  simply enables the row a frame later); Select All only when the buffer has text.
- Every action calls the field's own `EditableTextState` (`cutSelection`,
  `copySelection`, `pasteText`, `selectAll`, then `hideToolbar`), so the app never keeps a
  second copy of clipboard/selection logic.
- Chrome is the menu bar's: `RetroBorder.raised` on the panel colour,
  `RetroMenuMetrics` row height/typography/shortcut column, `menuActive` hover row and the
  two etched lines of `RetroMenuSeparator`. Theme colours are read per build, so all four
  themes follow.
- The `GestureDetector`'s `onSecondaryTapDown` is gone (hover already comes from
  `MouseRegion.onHover`). A `Listener` (invisible to the gesture arena) now dismisses the
  completion popup and the hover tooltip and focuses the editor on a secondary press — so
  the popup closes first and the tap still reaches the field, which keeps an existing
  selection where it is.

**Follow-up (owner report — the menu surface filled the whole window, items stuck in the
top-left):** Flutter hands the `contextMenuBuilder` slot **window-sized, tight
constraints**, so the panel's `Container(width: …)` was stretched to the window and the
column sat at its origin. The widget is now a full-area `Stack` whose only full-size child
is a **transparent tap barrier** (click outside closes it; `Esc` closes it through a
`HardwareKeyboard` handler that leaves the editor's focus alone); the panel is a
`Positioned` child sized by its content (`IntrinsicWidth` clamped to 180…280 px wide, four
26 px rows + one 7 px separator + the 2 px bevel/padding = 119 px high) and anchored at the
pointer. The separator above Select All is a **single** hairline in `borderDark`: the old
two-etched-line version (`borderDark` + `borderLight`) drew a pale-yellow `borderLight` rule
that read as a stray yellow line. Each row's text also sets `decoration: TextDecoration.none`
explicitly — without it the row inherited the toolbar's ambient text style and every label and
shortcut was painted with a yellow underline in all four themes.
Its top-left is the secondary click's global position (the toolbar slot starts at the window
origin, measured), shifted left/up when the panel would leave the window so it always stays
fully inside with a 4 px margin. Chrome, rows, shortcuts and enabled rules are unchanged.

**Tests:** `test/ui/editor/editor_context_menu_test.dart` with a mocked clipboard channel and
one case that opens the menu in each of the four themes and asserts every row text has
`TextDecoration.none`:
an empty, unfocused buffer opens the menu with Paste enabled and Select All/Cut/Copy
disabled; a selection enables Cut/Copy and survives the right click untouched; tapping
Paste inserts the clipboard text through the field and closes the menu; in an 800x600
window a click at (100,100) puts the panel's top-left exactly there at less than 300x200;
a click in the bottom-right corner keeps the panel fully inside the window; a click outside
the panel closes it.

**Verified in the release build:** right click in the editor shows the compact retro panel
at the pointer (Cut/Copy greyed on an empty buffer, Paste and Select All enabled, shortcuts
right-aligned) — screenshot of `flutter build macos --release` while running.

### TASK-087: The language server follows the tab's effective language
**Phase:** 24
**Status:** ✅ DONE

Fixes the TASK-079 limitation: `Untitled 23.c` holding Dart, with the dropdown set to Dart,
kept 8 errors/3 warnings from clangd while Run, colours and the logo were Dart.

- New `lib/services/tab_language_server_sync.dart` (`TabLanguageServerSync`) owns the
  whole open/close/switch lifecycle that used to be inline in `IDEShell`. `IDEShell`
  passes `LanguageConfig.resolveTab(tab).language` — the same resolver Run, the highlighter
  and the logo use.
- `needsVirtualDocument()` compares the effective language with
  `LanguageConfig.fromExtensionOrNull(realPath)`: the real path is used only when they
  agree. Untitled buffers, an explicit selection for another language, a resolved
  mismatch and unknown extensions are documented as
  `<basename>.<effective ext>` inside `UnsavedBufferWorkspace` (the per-session temp
  workspace, including clangd's `compile_flags.txt`). Nothing is written next to the user's
  file, and Save still writes the real path with its real name.
- Because the virtual document carries the effective extension, `LspServerManager.activateFor`
  picks the matching server and `didOpen` sends the matching language id.
- On a switch (dropdown change, or back to Auto) the old document is closed on the **old**
  service before the new one opens, which sends `didClose` and drops that URI's
  diagnostics, so a stale count can never stay on screen; the panel, status bar and gutter
  repaint from the manager's notifications. The Diagnostics panel shows the virtual name,
  as it already did for untitled buffers.

**Tests:** `test/services/tab_language_server_sync_test.dart` with a fake manager and a
fake workspace: a `.c` tab set to Dart is opened as `untitled-23-c.dart` on the Dart
service only; switching to C closes the old document (its diagnostics list is empty and
the service has no active document) and opens the real path on clangd; an untitled buffer
still gets `untitled.c`; an explicit language that matches the extension keeps the real
path; the decision table for `needsVirtualDocument`.
