# PHASE_DETAILS.md

## Phase 01: Project Skeleton
See TASKS.md → TASK-001

## Phase 02: Retro UI Design System
Create reusable retro widgets:
- RetroButton (raised/sunken)
- RetroBorder (3D border painter)
- RetroColors (color constants)
- RetroTheme (ThemeData)
- Demo screen showing all components

## Phase 03: IDE Shell
Main window layout:
- Menu Bar (File, Edit, View, Run, Tools, Help)
- Toolbar (New, Open, Save, Run, Stop)
- Panel areas (Editor, Explorer, Console)
- Status Bar

## Phase 04: Code Editor
- Integrate flutter_code_editor
- Dart syntax highlighting
- Line numbers

## Phase 05: Dart Runner
- DartRunnerService
- Execute dart code via Process
- Capture stdout/stderr

## Phase 06: Console
- Console panel
- Display stdout (black) and stderr (red)
- Clear button

## Phase 07: File Management
- FileService
- Open/Save/SaveAs
- file_picker package

## Phase 08: Tabs & Projects
- Tab bar
- Multiple files
- Modified indicator

## Phase 09: Dart Analyzer
- Run dart analyze
- Parse output
- Show diagnostics

## Phase 10: Dart LSP
- Connect to dart language-server
- LSP protocol over stdio

## Phase 11: IDE Intelligence
- Autocomplete
- Hover docs
- Real-time diagnostics

## Phase 12: Terminal
- Integrated terminal
- Shell command execution

## Phase 13: Debugger
- Breakpoints
- Step over/into/out
- Variable inspection

## Phase 14: Multi-Language Support
- LanguageConfig model (Dart, C, C++, Python)
- LanguageRunnerService: run/compile per language
- MultiLanguageHighlighter (highlight package)
- Format on save (dart format, clang-format, black)

## Phase 15: Multi-Language Debugging
- BaseDebugger contract (output stream, currentPausedLine)
- DartDebugger over the real Dart VM Service (VmServiceClient)
- PythonDebugger via sys.settrace
- CDebugger via clang -g -O0 + lldb
- DebuggerFactory language dispatch + DebuggerManager tab sync
- Console output bridge

## Phase 16: Debugger Hardening & Test Coverage
- Gutter paused arrow for all four languages
- Shared editor/gutter line height (no row drift)
- Breakpoint auto-cleanup
- Language-sniffing fix (untitled C vs C++)
- Dart/Python/C debugger fixes
- Opt-in real-VM integration test
- About dialog & Help menu

## Phase 17: Release Smoke Gate
- `scripts/release_gate/` 01 analyze / 02 test / 03 build / 04 launch smoke / 05 DMG

## Phase 18: Editor Zoom & Gutter Metrics
- EditorSettingsService (persisted font size) + EditorMetrics
- Cmd +/-/0 shortcuts, View-menu items, About shortcuts tab
- Dynamic editor panel; gutter alignment tests across sizes

## Phase 19: ARM64 Assembly, Theme & Editor UX
- ARM64 Assembly (`.s`): language config, `arm64Asm` grammar, runner
  (`clang -g -arch arm64`), ASM icon, manual dropdown entry, sample file
- `AsmDebugger`: LLDB stop-hook publishing `x0`..`x28`/`fp`/`lr`/`sp`/`pc`/`cpsr`
  plus one-instruction disassembly; instruction-level stepping
- Editor UX: numbers left / scrollbar right in the gutter, 2x breakpoint bullet,
  current-line band with hairline border, click-past-end-of-line selects the row
- Debugger sidebar only while a session is running/paused
- Fourth theme: Turbo Pascal 7.0 (DOS navy) with the shared syntax palette
- Deterministic settings save (removed a save/load ordering race)

## Phase 20/21: Multi-Language Hardening & Assembly Line Mapping
- Debugger hardening per language; ARM64 asm line breakpoints relative to `_main`

## Phase 22: Editor Fonts
- `View > Font`: **Menlo** (default) and **Recursive Mono Casual** (bundled, SIL OFL 1.1)
- Stable ids in `editor_settings.json`; unknown/retired ids (e.g. `monaco`) fall back to Menlo
- Gutter advance + wrapped-row caches keyed by size **and** family; line numbers use the code font
- Strut forced for every family (unforced rows follow the fallback font of a Persian glyph)
- Removed: Monaco (synthesized bold/italic, fallback-dependent metrics)
- Tooling: `tool/probe_font_drift.dart` measures the running app (flutter_tester has no system fonts)
- Gutter rows come from the renderer (`_rowsFromRenderer`), never from a wrap prediction; the current-line band
  is grid-snapped (`row * lineHeight`) and spans every row of a wrapped line; the status bar shows a live
  `Ln, Col` (`onCaretChanged`)
- lldb sessions write only through `LldbCommandQueue`: quiet-window gate + `@@ACK n` sentinel + one idempotent
  retry; Stop kills in order (`process kill`, `quit`, 2 s wait, SIGKILL lldb, SIGKILL inferior), so no
  `borland_*_exec` survives
- Tests: 329 pass / 6 opt-in skipped; real-process suites are `BORLAND_REAL_VM_TEST=1` (Dart VM) and
  `BORLAND_REAL_ASM_TEST=1` (asm, C, C++, session lifecycle)

## Phase 23: Multi-Language Language Servers (v1.4.1)
- `LspServerSpec` registry: binary candidates + arguments + language ids + install hint for
  `dart language-server`, `clangd`, `pyright-langserver` and `pylsp` (pyright is preferred for Python)
- `LspServerManager` keeps one warm `LspService` per spec id and swaps with the active tab; no restart when
  alternating `.c` / `.dart` / `.py`. `active` is never null — the `Off` spec covers Assembly/unknown files
- Missing server degrades loudly: one Console hint per language, then offline completion; `dart analyze` is
  now limited to Dart files
- `compile_flags.txt` is created for clangd (comment header + `-isysroot $(xcrun --show-sdk-path)`); a
  user-authored file is never touched
- Empty first completion is retried once (200 ms) while clangd/pyright are indexing
- `startServer` is a shared future, so `openFile` waits for `initialize` instead of losing the first document
- Status bar LSP segment gained a tooltip naming the active server and the failure reason
- Tests: 354 pass / 8 opt-in skipped; opt-in `BORLAND_REAL_CLANGD_TEST=1` runs against the real Apple clangd
  21.0.0 (`initialize` answered in 8 ms)

## Phase 24: Completion, Workspace & Editor Polish (v1.5.0)
- **Autocomplete & IntelliSense:** Immediate triggers on `.` and 1st character for LSP-backed files; manual trigger `Ctrl+Shift+Space` (and Edit > Trigger Completion); `Tab` accepts suggestions; function calls insert `()` with caret inside; LSP snippets expanded (`$0`, `$1`); built-in Dart/Flutter snippets (`stless`, `stful`, `main`, etc.); ranking by match quality + MRU; documentation panel after 2 s idle; auto-import of unimported libraries (`Timer` -> `import 'dart:async';`); LSP kind badges with detail; popup anchored to caret inside editor.
- **Diagnostics & Language Server Sync:** `TabLanguageServerSync` aligns language server with effective tab language, dropping stale diagnostics on switch; unsaved buffers analyzed in `UnsavedBufferWorkspace`.
- **Gutter & Editor Polish:** Gutter error/warning markers with hover tooltips, 1px retro separator line, bold current line number; 5px thicker caret; `#fbfbf9` near-white surface shared with Console; Colorful syntax scheme (operators `#687d01`, curly braces `#1e64d8`, square brackets `#00796f`, comments `#666666`, strings `#409175`); retro right-click context menu (Cut/Copy/Paste/Select All).
- **Workspace & Navigation:** File Explorer (`Cmd+Shift+O`, Open Folder, lazy tree, double-click to open file), `+` new tab button, per-tab language selection dropdown, mismatch protection prevents compiling mismatched files, launches with a fresh empty Untitled tab.
- **Finder Launch Fixes:** Immediate editor focus on launch; tool binary resolution via user's login shell (`zsh -lic` / `-lc`, Homebrew, Dart SDK, Flutter) when launched from macOS Finder.
- **Tests:** 520 pass / 8 opt-in skipped; analyze clean.

