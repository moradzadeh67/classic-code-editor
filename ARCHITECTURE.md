# ARCHITECTURE.md — borland_dart

## Overview
borland_dart is a Flutter Desktop app for macOS.
It provides a retro-styled environment to write, run, and debug Dart, Python,
C, and C++ code. Supports three themes: VC++ 6.0 (gray), Borland Delphi
(beige), and Visual Basic 6.0.

## Layers

### 1. UI Layer (lib/ui/)
- Pure Flutter widgets
- No business logic
- No SDK calls
- Observes state from Services via ThemeService or ChangeNotifier

### 2. Services Layer (lib/services/)
- All business logic
- All Process/SDK interaction
- Exposes state via ChangeNotifier or streams
- Independent of UI
- ThemeService manages current theme and colors

### Shell Composition (lib/ui/shell/)
- `ide_shell.dart` — the app root: `RetroMenuBar` / `RetroToolbar` /
  `PanelLayout` / `RetroStatusBar`, wrapped in a `ListenableBuilder` on
  `ThemeService.instance` so a theme switch repaints the whole shell.
- `retro_menu_bar.dart` — 24px; File / Edit / View / Run / Tools / Help. The
  View menu toggles the explorer/console and switches themes; the Help menu
  opens the About dialog (`About` / `Keyboard Shortcuts` / `System Info` tabs).
- `retro_toolbar.dart` — 28px; New / Open / Save | Run / Debug / Stop, plus the
  theme selector (short labels: `VC++ 6.0` / `Delphi` / `VB6`). The selector lives
  in an `Expanded` + horizontal `SingleChildScrollView` so it can never overflow.
- `panel_layout.dart` — file explorer (200px) + editor + bottom panel (150px),
  toggleable from the View menu. The bottom panel switches between Console,
  Diagnostics and Terminal via an internal retro tab strip.
- `retro_status_bar.dart` — 24px; status text + analysis counts + LSP status +
  `Ln x, Col y`.

### 3. Models Layer (lib/models/)
- Plain Dart classes
- No Flutter imports (pure Dart)
- Data structures only

### 4. Utils Layer (lib/utils/)
- Constants, helpers, extensions
- No business logic
- `json_rpc_client.dart` — Content-Length framing + JSON encode/decode for LSP
- `vm_service_client.dart` — minimal JSON-RPC 2.0 client over a `dart:io`
  `WebSocket`, used by `DartDebugger` to talk to the Dart VM Service
- `completion_filter.dart` — client-side completion matching/ranking plus a
  per-language offline fallback list

## Data Flow

### Theme Change:
User clicks theme button
→ ThemeService.switchTheme(newTheme)
→ ThemeService notifies listeners
→ UI widgets rebuild with new colors
→ Theme saved to file for persistence

### Real-time diagnostics (Phase 09/10):
User types in the editor
→ FileService.updateContent() notifies listeners
→ IDEShell pushes the change to LspService
→ LspService sends textDocument/didChange over JSON-RPC stdio
→ Dart language server publishes textDocument/publishDiagnostics
→ LspService parses them into Diagnostic models and notifies listeners
→ PanelLayout / RetroStatusBar rebuild (LSP diagnostics take precedence)

### Static analysis fallback (Phase 09):
Used while the language server is unavailable
→ AnalyzerService runs `dart analyze --format=machine <file>`
→ One-shot diagnostics shown in the same Diagnostics panel

### Debug session (Phase 13/15/16):
User clicks Debug
→ DebuggerManager resolves the active debugger (via DebuggerFactory)
→ debugger.startDebugging(path, content: liveBuffer)
→ entry breakpoint installed in `main`; gutter breakpoints mirrored
→ runtime pauses → `variables` / `callStack` populated, `currentPausedLine` set
→ gutter paints `▶` on the paused line and the panels rebuild
→ every debugger output line → IDEShell → LanguageRunnerService.emitOutput → ConsolePanel

### macOS sandbox note
RetroDart spawns the Dart SDK (`dart run`, `dart language-server`) as a child
process. App Sandbox forbids exec'ing external binaries, so
`macos/Runner/*.entitlements` set `com.apple.security.app-sandbox` to `false`.
Without this, both `DartRunnerService` and `LspService` fail with
"Operation not permitted".

## Debugger Architecture

Debugging is one small contract (`BaseDebugger`) plus one engine per language, so
the shell never needs to know which languages exist. See
[docs/DEBUGGING.md](docs/DEBUGGING.md) for the full guide.

### Components

| File | Role |
|------|------|
| `base_debugger.dart` | Abstract surface: `state`, `breakpoints`, `variables`, `callStack`, `currentPausedLine`, and a broadcast `output` stream. Owns shared breakpoint bookkeeping (`clearBreakpointsForFile`) and the `@protected emitOutput` helper. |
| `dart_debugger.dart` | Drives the real **Dart VM Service** through `VmServiceClient`. |
| `python_debugger.dart` | Runs a generated `sys.settrace` tracer driver. |
| `c_debugger.dart` | Compiles with `clang -g -O0` and attaches `lldb`, injecting a helper stop-hook. |
| `debugger_factory.dart` | Maps a `LanguageConfig` (extension) to its debugger; instances are reused so breakpoints survive tab/language switches. |
| `debugger_manager.dart` | Keeps the active debugger in sync with the active tab. Stops a *running* session when the language changes; never clears breakpoints. |
| `debugger_snapshot.dart` | One shared JSON decoder for the `@@BORLAND_SNAP` / `@@BORLAND_PAUSED` stop payloads. |
| `debugger_environment.dart` | Test seam: short-circuits real process spawns while `FLUTTER_TEST` is set (`BORLAND_REAL_VM_TEST=1` opts back in). |
| `utils/vm_service_client.dart` | Minimal JSON-RPC client over `dart:io` `WebSocket` for the VM Service. |

### Session flow

```
start → attach / compile → install entry breakpoint → mirror gutter breakpoints
      → pause events → fill variables + call stack → resume / step → teardown
```

### Entry-breakpoint strategy

Every language deliberately stops in the **user's** `main` on the first Debug,
mirroring how a classic IDE breaks at the entry point:

- **Dart:** the isolate is launched with `--pause-isolates-on-start`; the debugger
  polls `getIsolate` until `rootLib` exists, reads the root library's `scripts`,
  loads the entry script source, locates `main`'s line and installs a breakpoint
  with `addBreakpointWithScriptUri`, then resumes.
- **Python:** the tracer stops on the first line of the user's script.
- **C/C++:** `breakpoint set --name main`.

The entry breakpoint id is tracked separately from the user's gutter breakpoints,
so editing the gutter mid-session can never delete it.

### Stop protocols

| Language | Marker | Decoder |
|----------|--------|---------|
| Python | `@@BORLAND_PAUSED <json>` | `DebugSnapshot.tryParse` |
| C/C++ | `@@BORLAND_SNAP <json>` | `DebugSnapshot.tryParse` |
| Dart | VM Service stream events | handled in `dart_debugger.dart` |

Dart pause event kinds handled: `PauseBreakpoint`, `PauseInterrupted`,
`PauseException`, `PausePostRequest`, `PauseExit`, `IsolateExit`, `Resume`.

### Console output bridge

Each debugger owns a broadcast `output` stream. `IDEShell` subscribes to every
debugger and forwards each line to `LanguageRunnerService.emitOutput`, the stream
`ConsolePanel` already listens to — so debug output appears alongside program
output and a session is never silent.

## Approved Dependencies

| Package | Purpose | Status |
|---------|---------|--------|
| flutter_code_editor | Code editing | Phase 04 |
| file_picker | File open/save | Phase 07 |
| path_provider | File paths | Phase 07 |

> No new packages were added for the debugger work — the Dart VM Service client
> is hand-rolled over `dart:io`.

## Services

| Service | Phase | Status | Purpose |
|---------|-------|--------|---------|
| ThemeService | 02.5 | ✅ | Theme management |
| DartRunnerService | 05 | ✅ | Execute Dart code |
| FileService | 07 | ✅ | Open/Save files |
| AnalyzerService | 09 | ✅ | Static analysis (fallback) |
| LspService | 10 | ✅ | Real-time diagnostics via LSP |
| TerminalService | 12 | ✅ | Integrated terminal |
| LanguageRunnerService | 14 | ✅ | Execute Python/C/C++ |
| DartDebugger | 13/15 | ✅ | Dart debugging via the VM Service |
| PythonDebugger | 15 | ✅ | Python debugging via `sys.settrace` |
| CDebugger | 15 | ✅ | C/C++ debugging via `clang` + `lldb` |
| DebuggerFactory | 15 | ✅ | Language → debugger dispatch |
| DebuggerManager | 15 | ✅ | Active debugger follows the active tab |

## Retro Design Tokens

### VC++ 6.0 Theme:
UI Background: #C0C0C0
UI Panel: #D4D0C8
UI Border Dark: #404040
UI Border Light: #FFFFFF
UI Highlight: #DFDFDF
UI Shadow: #808080
UI Selection: #000080
UI Text: #000000
UI Error: #CC0000
Editor Background: #FFFFFF
Editor Text: #000000
Editor Selection: #000080
Paused Line: #FFF0A0
Syntax Colors:
Keywords: #0000FF (blue)
Types: #2B91AF (teal)
Strings: #A31515 (dark red)
Comments: #008000 (green)
Numbers: #098658 (dark green)
Functions: #000000 (black)
Preprocessor: #800080 (purple)

### Borland Delphi Theme:
UI Background: #D4D0C8
UI Panel: #E8E0D0
UI Border Dark: #808080
UI Border Light: #FFFFFF
UI Highlight: #F0E8D8
UI Shadow: #A09888
UI Selection: #000080
UI Text: #000000
UI Error: #CC0000
Editor Background: #FFFFF0 (ivory)
Editor Text: #000000
Editor Selection: #000080
Paused Line: #E9D9A5
Syntax Colors:
Keywords: #0000FF (blue, bold)
Types: #0000FF (blue)
Strings: #0000FF (blue)
Comments: #008000 (green, italic)
Numbers: #0000FF (blue)
Functions: #000000 (black, bold)
Directives: #800080 (purple)

### Visual Basic 6.0 Theme:
UI Background: #C0C0C0
UI Panel: #D4D0C8
UI Border Dark: #404040
UI Border Light: #FFFFFF
UI Highlight: #DFDFDF
UI Shadow: #808080
UI Selection: #000080
UI Text: #000000
UI Error: #CC0000
Editor Background: #FFFFFF
Editor Text: #000000
Editor Selection: #000080
Paused Line: #DCDCA8
Syntax Colors:
Keywords: #0000FF (blue)
Strings: #FF0000 (red)
Comments: #008000 (green)
Others: #000000 (black)

> NOTE: In every theme `Editor Background` currently resolves to **#E8F1FF**
> (soft blue), set in `ThemeService`.

### Common Rules:
- Border width: 2.0
- Corner radius: 0.0 (NO rounded corners, incl. internal widgets only)
- UI font family: Arial
- Font UI size: 12.0 (buttons/menus/labels), 11.0 (status bar)
- Font code size: 13.0–14.0 (Menlo)
- Editor line height: `editorFontSize` 13.0 × `editorLineHeightFactor` 1.45 = **18.85**
  (shared by the editor text and the breakpoint gutter so rows never drift)
- Button height: 22.0 (fixed) — 1px gap above/below inside the toolbar
- Bar heights (px): menu bar 24, toolbar 28, status bar 24
- Paused-line highlight: `ThemeService.colors.pausedLine` (#FFF0A0 VC6 /
  #E9D9A5 Delphi / #DCDCA8 VB6)

### Retro widget inventory (lib/ui/retro/)
| Widget | Notes |
|--------|-------|
| `RetroBorder` | `raised()` / `sunken()` / `flat()`; 2px border, `BorderRadius.zero` |
| `RetroButton` | Fixed 22px height; forces Arial 12 / w500 via `DefaultTextStyle` |
| `RetroPanel` | Raised container with margin/padding |
| `RetroColors` | All getters delegate to `ThemeService.instance.colors.*` |
| `SyntaxColors` | 8 syntax slots + `forTheme(ThemeType)` |
| `RetroTheme` | `ThemeData(useMaterial3: false)` + global `TextTheme` |
| `LanguageLogo` | Per-language icon: tries `assets/icons/{lang}.png`, falls back to a vector `CustomPainter` |
| `showRetroAboutDialog()` | Retro Help → About dialog (About & Developer / Shortcuts / System Info) |
| `RetroWatchWindow` | Variables watch window (sunken panel bound to `DebugService`) |

### Theme persistence
`ThemeService` writes the active theme to `.retro_theme_config.json` and
restores it on launch. `enum ThemeType { vc6, delphi, vb6 }`.
