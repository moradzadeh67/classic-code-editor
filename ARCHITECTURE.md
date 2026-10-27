# ARCHITECTURE.md — classic_code_editor

## Overview
classic_code_editor is a Flutter Desktop app for macOS.
It provides a retro-styled environment to write, run, and debug Dart, Python,
C, C++, and ARM64 Assembly code. Supports four themes: VC++ 6.0 (gray),
Borland Delphi (beige), Visual Basic 6.0, and Turbo Pascal 7.0 (DOS navy).

## Layers

### 1. UI Layer (lib/ui/)
- Pure Flutter widgets
- No business logic
- No SDK calls
- Observes state from Services via ThemeService or ChangeNotifier
- `explorer/file_explorer_panel.dart` — the retro folder tree (see *File Explorer* below)

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
- `close_guard.dart` — one helper (`TabCloseGuard.confirmClose` / `confirmExit`) used by the tab's ✕,
  `Cmd + W`, File > Close Tab and the platform exit request.
- `retro_menu_item.dart` — shared dropdown chrome: `RetroMenuItem` (22px rows, check gutter, shortcut
  column, hover *and* keyboard highlight), `RetroMenuSeparator`, `RetroPopupShape`.
- `retro_menu_bar.dart` — 24px; File / Edit / View / Run / Tools / Help. The
  View menu toggles the explorer/console and switches themes; the Help menu
  opens the About dialog (`About` / `Keyboard Shortcuts` / `System Info` tabs).
- `retro_toolbar.dart` — 28px; New / Open / Save | Run / Debug / Stop, plus the
  theme selector (short labels: `VC++ 6.0` / `Delphi` / `VB6` / `Turbo Pascal`,
  built from `ThemeType.values`). The selector lives
  in an `Expanded` + horizontal `SingleChildScrollView` so it can never overflow.
- `panel_layout.dart` — file explorer (200px) + editor + bottom panel (150px),
  toggleable from the View menu. `PanelLayout` listens to the active debugger and
  shows `DebuggerSidebar` only while a session is `running` or `paused` — a
  gutter breakpoint alone no longer opens the panel. The bottom panel switches between Console,
  Diagnostics and Terminal via an internal retro tab strip.
- `retro_status_bar.dart` — 24px; status text + analysis counts + LSP status +
  `Ln x, Col y`.

### File Explorer
`File > Open Folder...` (`Cmd+Shift+O`), the panel's empty-state button or a
restored session gives `FileExplorerService` a root path; a double-clicked file
goes through `onOpenFile` to the shell, which applies the guards and then calls
the same `FileService` path *Open Recent* uses (open tabs are reused).

- **Model.** `lib/models/file_node.dart` — `path`, `name`, `isDirectory`,
  `children`, `childrenLoaded`, `expanded`, `isTruncationNotice`. Plain Dart.
- **Service.** `lib/services/file_explorer_service.dart` — reads **one**
  directory per call, synchronously (a widget callback cannot await a
  `Directory.list()` future under the test clock), so a folder's `children` stay
  empty until it is expanded. Each level is sorted folders-first then
  case-insensitively; dot names and `build` / `.dart_tool` / `node_modules` /
  `__pycache__` / `.DS_Store` are hidden; more than `maxEntries` (2000) entries
  collapse into one "… N more not shown" row; a `FileSystemException` yields an
  empty folder instead of a crash. `refresh()` re-reads what was expanded;
  `revealFile()` opens the folders leading to the active tab.
- **Open guards.** `readFileForOpen()` refuses files over 2 MB and files with a
  NUL byte in their first 4 KB; the shell prints one Console line
  (`Not opened: binary or too large`) and opens nothing.
- **Persistence.** `SessionService` keeps `openFolderPath` next to the tab list
  and the session reopens it only when the directory still exists.
- **Refresh on save.** `IDEShell._handleSave()` re-reads the tree when the saved
  file lives inside the open folder; the header also has a ⟳ button.
- **No mutations.** Create / rename / delete / drag-and-drop are out of scope:
  the explorer is read-only apart from opening files and toggling folders.

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
- `completion_docs.dart` — `completionItem` documentation (String or
  MarkupContent, `markdown`/`plaintext`) → the plain text the panel renders
- `snippet_expander.dart` — LSP snippet syntax (`$1`, `${1:name}`, `$0`) → text
  plus caret offset, used for both server snippets and built-in ones
- `completion_insert.dart` — one accept path: plain insert, snippet expansion,
  `textEdit` range replacement, then the item's `additionalTextEdits`
- `completion_edit_applier.dart` — pure helper that applies completion
  `TextEdit`s (including `insert`-only forms) to a buffer and returns the new
  text + selection
- `dart_snippets.dart` — the built-in Dart/Flutter snippet list merged into the
  server's answer (`mergeSnippets`)

## Data Flow

### Theme Change:
User clicks theme button
→ ThemeService.switchTheme(newTheme)
→ ThemeService notifies listeners
→ UI widgets rebuild with new colors
→ Theme saved to file for persistence

### Real-time diagnostics (Phase 10/23):
User types in the editor
→ FileService.updateContent() notifies listeners
→ IDEShell asks LspServerManager for the server of the active file
  (Dart → `dart language-server`, C/C++ → `clangd`, Python → `pyright`/`pylsp`)
→ LspService sends textDocument/didChange over JSON-RPC stdio
→ the server publishes textDocument/publishDiagnostics
→ LspService parses them into Diagnostic models and notifies listeners
→ PanelLayout / RetroStatusBar rebuild (LSP diagnostics take precedence)

### Language server selection (Phase 23):
`LspServerSpec.candidatesForLanguage()` is the only place that knows which
binary serves which `highlightLanguage`. `LspServerManager` caches one
`LspService` per spec id, so switching between a `.c` and a `.dart` tab does not
restart anything. When no candidate connects, the manager prints the install
hint to the Console **once** and switches to the `Off` spec; `AnalyzerService`
then covers Dart and offline completion covers the rest. clangd gets a
generated `compile_flags.txt` (never overwriting a user file; one argument per
line and no comment header — clangd has no comment syntax there and a `#` line
silently breaks the whole command) before its `initialize`, and an empty first completion is retried once while a server is
still indexing.

### Completion (Phase 24):
Typing (or `Ctrl+Shift+Space` / Edit > Trigger Completion)
→ `CompletionFilter` decides the trigger and the current word
→ `LspService.requestCompletion()` (after a `didChange` flush, so the server
  answers for the text on screen) or the offline keyword/API list
→ `mergeSnippets()` adds the built-in Dart/Flutter snippets, `CompletionFilter`
  filters and ranks (server `sortText`, then match tier, then MRU)
→ `AutocompletePopup` paints the list inside the editor's own bounds (below the
  caret, flipped above, clamped horizontally) with the documentation panel to the
  right, left, or below/above

Accepting goes through `CompletionInsert` only: `textEdit` range replacement or
plain insert, snippet expansion (`SnippetExpander`), and finally the item's
`additionalTextEdits` — the auto-import. `CompletionEditApplier` keeps that pure
and testable.

Two clocks, on purpose:

| Clock | Delay | What it does |
|---|---|---|
| resolve | 150 ms | `completionItem/resolve` → docs + `additionalTextEdits`, cached per popup, so Accept never waits |
| display | `kCompletionDocPanelDelay` = 2 s | shows the doc panel, but only if the same row is still selected and no key was pressed |

Any selection change, key press or popup close calls `_hideCompletionDoc()`:
both timers are cancelled, in-flight answers invalidated, the panel hidden at
once — the resolve cache is kept, so moving away and back needs no new request.
A late answer for a row that is no longer selected is dropped.

The client advertises `workspace.applyEdit` but never applies a server edit (the
completion item's `additionalTextEdits` are applied by the editor itself); it
answers `workspace/applyEdit` with
`{"applied": false, "failureReason": "not supported by this client"}`. The
capability has to stay advertised: the Dart server only offers completions from
libraries that are not imported yet when it can ask the client to add the import.

Position-based requests use `LspService.activeDocumentPath` — the document the
server actually has open — not the tab's display name. An Untitled buffer lives
as `untitled.<ext>` in `UnsavedBufferWorkspace`; asking the server about
`Untitled` returns no items at all, and a synthesized offline list has no `raw`
item to resolve, so the documentation panel could never appear.

### Language resolution (TASK-054)
`LanguageConfig.resolve(filePath, content, preferredLanguage:)` is the single
source of truth and returns a `LanguageResolution` — the language **plus** a
`mismatch` (`null` when none). The extension stays authoritative; an explicit
toolbar selection wins before it, and paths with no recognised extension keep
content sniffing. A mismatch needs a recognised extension and one unambiguous
foreign signal (Dart `import 'dart:` / `import 'package:` / `void main(`;
Python `def `, `import sys|os`, `from … import` with no `{`/`;` line ending in
the first 20 lines; C/C++ `#include <` with `int main(`), and is suppressed for
content plausible to the extension (a bare `#include` in `.s`, C++ in `.c`, two
conflicting signals). An assembly buffer is special-cased: `#include <` together
with `int main(` / `void main(`, `std::`, `using namespace` or a C++ header is
reported as C++ (or C when no C++ marker exists) instead of being compiled as
assembly. Consumers: `LanguageRunnerService.runCode()` (refuses before spawning,
prints one Console line, stays idle), the Debug button, the highlighter's
`createController` and `PanelLayout._detectLanguageExt` — so colors, logo and
Run/Debug can never disagree.

### Per-tab language selection (TASK-079)
`TabFile.languageOverride` (default `Auto`, memory only) holds the toolbar
choice for that tab. `LanguageConfig.resolveTab(tab)` is the single entry point:
the tab's selection wins, otherwise it delegates to `resolve()`. Run
(`runActiveFile` and the toolbar callback), Debug, the highlighter and the logo
all read it; `PanelLayout` writes it through `FileService.setActiveLanguage()`
and rebuilds only when the active tab or its override changes. The editor swaps
only the grammar (`_applyGrammar`) so text, caret and scroll survive.

The **language server follows the same effective language** (TASK-087):
`TabLanguageServerSync` takes `LanguageConfig.resolveTab(tab)`, keeps the real
path only when the extension already means that language, and otherwise exposes
the buffer as `<basename>.<effective ext>` inside
`UnsavedBufferWorkspace` (the same per-session temp workspace, with clangd's
`compile_flags.txt`). On a change of document or server it sends `didClose` to
the old service first — which drops that URI's diagnostics, so no stale
Errors/Warnings count survives — then `didOpen` on the new one. Saving still
writes the real path and name. Tab names are unique (`Untitled`,
`Untitled 2`, …) and `UnsavedBufferWorkspace.pathFor(config, bufferName:)`
derives a distinct virtual document path from the name, so two untitled buffers
never share diagnostics.

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
Classic Code Editor spawns the Dart SDK (`dart run`, `dart language-server`) as a child
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
| `asm_debugger.dart` | ARM64 Assembly: assembles with `clang -g -arch arm64` and drives the same `lldb` driver, reporting `x0`..`x28`/`fp`/`lr`/`sp`/`pc`/`cpsr` as Variables plus a one-instruction disassembly. |
| `c_debugger.dart` | Compiles with `clang -g -O0` and attaches `lldb`, injecting a helper stop-hook. |
| `lldb_command_queue.dart` | The only writer to lldb's stdin: one command in flight behind a quiet-window gate, an `@@ACK n` sentinel per non-resuming command, one idempotent retry, and `close()` for Stop. Owns the inferior pid parsed from `Process <pid> launched`. |
| `debugger_factory.dart` | Maps a `LanguageConfig` (extension) to one of the four debuggers (Dart, Python, C/C++, ARM64); instances are reused so breakpoints survive tab/language switches. |
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
| highlight | Syntax highlighting (Dart/C/C++/Python) | Phase 14 |

> `cupertino_icons` also appears in `pubspec.yaml` but is the unused Flutter
> template default, not an approved dependency.

> No new packages were added for the debugger work — the Dart VM Service client
> is hand-rolled over `dart:io`.

## Services

| Service | Phase | Status | Purpose |
|---------|-------|--------|---------|
| ThemeService | 02.5 | ✅ | Theme management |
| DartRunnerService | 05 | ✅ | Execute Dart code |
| FileService | 07 | ✅ | Open/Save files |
| AnalyzerService | 09 | ✅ | Static analysis (fallback) |
| LspService | 10 | ✅ | Real-time diagnostics via LSP (one server) |
| LspServerSpec | 23 | ✅ | Server registry: binary names, args, language ids, install hint |
| LspServerManager | 23 | ✅ | One warm server per language; follows the active tab |
| CompileFlagsEnsurer | 23 | ✅ | Creates `compile_flags.txt` for clangd when missing (repairs its own old format) |
| UnsavedBufferWorkspace | 24 | ✅ | `untitled.<ext>` documents in a temp workspace so servers can analyze unsaved buffers |
| TerminalService | 12 | ✅ | Integrated terminal |
| LanguageRunnerService | 14 | ✅ | Execute Python/C/C++ |
| DartDebugger | 13/15 | ✅ | Dart debugging via the VM Service |
| PythonDebugger | 15 | ✅ | Python debugging via `sys.settrace` |
| CDebugger | 15 | ✅ | C/C++ debugging via `clang` + `lldb` |
| AsmDebugger | 19 | ✅ | ARM64 Assembly debugging (registers + instruction stepping) |
| DebuggerFactory | 15/19 | ✅ | Language → debugger dispatch (four engines) |
| DebuggerManager | 15 | ✅ | Active debugger follows the active tab |
| EditorSettingsService | 18/22 | ✅ | Font size + font family persistence + ChangeNotifier |
| SessionService | 20 | ✅ | Open tabs + 10-entry MRU in `session.json` |
| EditorMetrics | 18/22 | ✅ | Font-size + family driven line-height / gutter metrics |
| CodeEditorPanel rows | 22 | ✅ | Renderer-owned gutter rows, grid-snapped full-line band, Ln/Col reporting |

### Editor zoom and font data flow
`EditorSettingsService.instance.fontSize` + `.fontFamily` -> `EditorMetrics.forFontSize(size, family:)` -> `metrics.textStyle/strutStyle/fontFamily/gutterWidth/lineHeight/markerFontSize/lineNumberFontSize`. `CodeEditorPanel` subscribes to the service, rebuilds with new metrics, invalidates `_charAdvance` and `_gutterRows` caches keyed by **both** `metrics.fontSize` and `metrics.fontFamily` (a new family changes the glyph advance at the same size), and schedules `_syncGutterScroll()` post-frame.

`EditorFontFamily` (in `editor_settings_service.dart`) maps a stable persisted id (`menlo` | `recursive`) to the Flutter family name. Menlo is a macOS system family used by name; Recursive ships as four static faces under the alias `RecursiveMonoCasual` (`pubspec.yaml` `fonts:`), with `fontFamilyFallback: ['Menlo']`. Ligatures (`calt`/`liga`) are disabled for both. An unknown id - including the retired `monaco` - resolves to `menlo`.

The strut is **forced for every family** at the plain `lineHeight / fontSize` factor. Unforced, the row height follows the font of whichever glyph is on the line, so a line with Persian text (fallback font) grew the row by 1-2px while the gutter still reserved `lineHeight` - the code drifted away from the numbers over a long file. Do not "calibrate" the factor per family: `TextPainter.height` floors the strut halves and looks short, while the editor's `RenderEditable` rounds and renders exactly; the invariant is asserted on a real `EditableText` in `test/ui/editor/editor_font_fallback_drift_test.dart`, and `tool/probe_font_drift.dart` measures the running app.

### Gutter rows, current-line band and caret reporting
Everything vertical is derived from the renderer, never predicted:

- **Rows.** `_rowsFromRenderer()` builds one entry per visual row (the logical line on a line's first row, `0` on continuation rows). The row *count* is the caret travel `(caret(last) - caret(first)) / lineHeight + 1`; each logical line is placed at the row its caret occupies. A `TextPainter` prediction survives only as a one-frame stopgap, because a character-count/wrap guess is wrong as soon as a glyph comes from the fallback font (a Persian line counted as one row renders as two, and every number below it sits one row high). The rebuild runs post-frame, retries while the editable is not measurable, and rejects a measurement with fewer rows than logical lines.
- **Band.** `_bandRectForCaret()` returns `(top, height)`: `top` = `row * lineHeight` (a *grid* row, because Flutter's caret rect is inflated ~1px above its line box and using it put the highlight above the numbers), `height` = every row of the logical line, so a wrapped line is highlighted as a whole.
- **Caret reporting.** `CodeEditorPanel.onCaretChanged(line, column)` -> `IDEShell` -> `RetroStatusBar.positionText`, so the status bar shows a live `Ln n, Col m`.
- **Caret painting.** Uses Flutter's built-in caret with `cursorWidth: 5.0` (`kEditorCaretWidth`) for a prominent 5 px retro cursor bar, blinking at Flutter's default 500 ms period. Accent color matches the theme editor cursor color.
- **Separator.** A 1 px retro sunken edge on the gutter's right side: `borderDark` then `borderLight`, painted inside the gutter's own width (`Positioned` overlay), so the width, the row model and the number advance never change.
- **Emphasis.** The caret's line number is bold in `colors.text` and its row is tinted with the very same `selection @ 0.14` fill as the band. Every other number is `editorLineNumberText @ 0.7` so the code stays the focus; a line with a diagnostic marker (or the paused line) keeps full strength.
- **Diagnostic markers.** For the active document only, `LspService.activeDiagnostics` is grouped per 1-based line; the worst severity of a line paints an 8x8 square at the inner edge of the gutter — error `#D32F2F`, warning `#F9A825` (`kGutterErrorMarkerColor` / `kGutterWarningMarkerColor`) — only on the first row of a logical line. The panel listens to the server, so `publishDiagnostics` (including an empty list) and a tab switch repaint them without any new analysis. The marker is last in the row's right-hand group, so the breakpoint bullet keeps its place to its left and never overlaps; it has no gesture handler, so a tap still toggles the breakpoint.
- **Marker tooltip.** Hovering a marker shows up to three messages (errors first, each ellipsized at 60 characters) in a `GutterDiagnosticTooltip` — `RetroBorder.raised` on the editor surface, the same look as `HoverTooltip`. It is `IgnorePointer` inside the editor Stack, so it never takes focus or a tap.
- **Continuation rows are inert:** no number, no breakpoint, no diagnostic marker, never the paused line.

The invariants are locked by `editor_click_line_test`, `editor_wrapped_gutter_test` and `editor_gutter_baseline_test`, and measured in the running app by `tool/probe_click_line.dart` and `tool/probe_baseline.dart`.

## Retro Design Tokens

### VC++ 6.0 Theme (Windows XP Luna-inspired):
UI Background: #0055EA (Luna blue)
UI Panel: #ECE9D8
UI Border Dark: #716F64
UI Border Light: #FFFFFF
UI Highlight: #F4F2E8
UI Shadow: #ACA899
UI Selection: #316AC5 (XP active-selection blue)
UI Text: #000000
UI Error: #CC0000
Menu Active: #316AC5 / Menu Active Text: #FFFFFF
Editor Background: #fbfbf9 (light neutral, shared)
Editor Text: #000000
Editor Selection: #000080 / Selection Text: #FFFFFF
Editor Line-Number BG: #ECE9D8 / Text: #000000
Editor Cursor: #000000
Paused Line: #FFF0A0
Syntax Colors:
Keywords: #0000FF (blue)
Types: #2B91AF (teal)
Strings: #A31515 (dark red)
Comments: #008000 (green)
Numbers: #098658 (dark green)
Functions: #000000 (black)
Preprocessor: #800080 (purple)
Operators: #000000 (black)

### Borland Delphi Theme (warm mustard-beige):
UI Background: #D2BA7E
UI Panel: #DFCD9B
UI Border Dark: #7A683E
UI Border Light: #FAF0C5
UI Highlight: #EAD8AA
UI Shadow: #A08B53
UI Selection: #A08035 (dark mustard)
UI Text: #000000
UI Error: #CC0000
Menu Active: #A08035 / Menu Active Text: #FFFFFF
Editor Background: #fbfbf9 (light neutral, shared)
Editor Text: #000000
Editor Selection: #000080 / Selection Text: #FFFFFF
Editor Line-Number BG: #DFCD9B / Text: #000000
Editor Cursor: #000000
Paused Line: #E9D9A5
Syntax Colors:
Keywords: #0000FF (blue)
Types: #0000FF (blue)
Strings: #0000FF (blue)
Comments: #008000 (green)
Numbers: #0000FF (blue)
Functions: #000000 (black)
Preprocessor: #800080 (purple)
Operators: #000000 (black)

### Visual Basic 6.0 Theme (deep navy desktop):
UI Background: #2C4A8E (deep navy)
UI Panel: #C0C0C0
UI Border Dark: #303030
UI Border Light: #E0E0E0
UI Highlight: #D8D8D8
UI Shadow: #707070
UI Selection: #1B3260
UI Text: #000000
UI Error: #CC0000
Menu Active: #1B3260 / Menu Active Text: #FFFFFF
Editor Background: #fbfbf9 (light neutral, shared)
Editor Text: #000000
Editor Selection: #000080 / Selection Text: #FFFFFF
Editor Line-Number BG: #C0C0C0 / Text: #000000
Editor Cursor: #000000
Paused Line: #DCDCA8
Syntax Colors:
Keywords: #0000FF (blue)
Types: #0000FF (blue)
Strings: #FF0000 (red)
Comments: #008000 (green)
Numbers: #0000FF (blue)
Functions: #000000 (black)
Preprocessor: #800080 (purple)
Operators: #000000 (black)

### Turbo Pascal 7.0 Theme (DOS navy desktop):
UI Background: #0000A8 (DOS blue)
UI Panel: #C0C0C0
UI Border Dark: #404040
UI Border Light: #FFFFFF
UI Highlight: #A8A8A8
UI Shadow: #808080
UI Selection: #0000A8
UI Text: #000000
UI Error: #CC0000
Menu Active: #00A8A8 / Menu Active Text: #000000
Editor Background: #fbfbf9 (light neutral, shared)
Editor Text: #000000
Editor Selection: #000080 / Selection Text: #FFFFFF
Editor Line-Number BG: #C8D0D8 / Text: #000080
Editor Cursor: #000000
Paused Line: #DCDCA8

> NOTE: In every theme `Editor Background` is intentionally `#fbfbf9`
> (near-white), held by the single constant `kEditorBackgroundColor` in
> `ThemeService` — kept by design decision so the editor reads clearly against
> each theme's chrome, and so both syntax schemes are tuned against one surface.
> The console's output area paints the very same constant, so the code pane and
> the console pane are the same surface; neither is per-theme.
> This is why Turbo Pascal keeps a light editor surface even though its desktop
> is DOS blue: the syntax palette is shared by all four themes and must stay
> readable.

### Editor syntax palette (applies to all four themes)
The editor surface does not read the per-theme `SyntaxColors` tables above; it
loads `MultiLanguageHighlighter.getThemeStyles(scheme)`
(`lib/utils/multi_language_highlighter.dart`) through `CodeThemeData`.
`View > Syntax Colors` picks the scheme (`SyntaxScheme.standard` — the default —
or `SyntaxScheme.colorful`), persisted as `syntaxScheme` in
`editor_settings.json` and applied live: only the `CodeThemeData` changes, the
`CodeController`, its highlighted nodes, the cursor and the undo history are
reused.

Internally there is **one** token-class → category map (`_categoryByClass`) and
one color map per scheme, so no language owns a palette:

| Category | Standard | Colorful |
|---|---|---|
| keyword (`keyword`, `selector-tag`) | `#C842F5` bold | `#A800E0` bold |
| literal (`literal`) | `#E65100` bold | `#8F5A00` bold |
| string (`string`, `quote`, `meta-string`, `subst`) | `#C62828` | `#007A1F` |
| number (`number`) | `#E65100` w600 | `#B34A00` |
| type (`type`), C++ class name (`class`) | `#00796B` w600 / `#006699` bold | `#00718F` |
| built-ins / registers (`built_in`) | `#00796B` w600 | `#C2185B` |
| function (`function`, `title`, `title.function`) | `#0D47A1` | `#0050E6` |
| annotation (`meta`, `meta-keyword`; `#include`, `@decorator`, `.globl`) | `#7B1FA2` bold | `#4B3FE0` |
| operator (`operator`, `symbol`; `= + - * / % \ | & ^ ~ ! ? < > , . ; :` and combined `==`, `!=`, `<=`, `>=`, `=>`, `??`, `++`, `--`, `&&`, `||`, `->`, `::`, `..`, `...`, `@` when standalone) | `#00BF69` bold | `#687d01` bold |
| curly braces (`{`, `}`) | `#031CFC` bold (same as brackets) | `#1e64d8` bold |
| square brackets (`[`, `]`) | `#031CFC` bold (same as brackets) | `#00796f` bold |
| brackets (`(` `)`) — parentheses unchanged | `#031CFC` bold | `#031CFC` bold |
| comment (`comment`) | `#596E48` italic | `#666666` italic |
| identifiers (`params`, `variable`) | `#283593` / `#1A237E` | default text |

Standard reproduces the classic palette byte for byte (an untouched settings file
always resolves to it); `doctag` (Dart `///`) is deliberately unstyled there and
only mapped in Colorful.

> highlight 0.7's Dart / C / C++ / Python grammars emit no `operator` /
> `punctuation` classes of their own, so
> `MultiLanguageHighlighter.patchSymbolModes()` appends single-character
> rules to each grammar before any controller compiles it (no extra package).
> Two rules learned the hard way:
> 1. **A `contains` rule wins over the enclosing mode's `end` match.** Never add
>    a bracket rule that can match a mode's own end character — the mode then
>    never closes (a `)` rule inside a `params` mode swallowed the rest of a C++
>    file). Each patch therefore uses a rule set without that character
>    (`operatorsNoColon`, `operatorsNoSemiEq`).
> 2. **Paren-owning modes are removed, not patched.** The bundled grammars wrap
>    a parameter list in a `params` mode (`begin: "\(", end: "\)"`) that owns
>    its own parentheses, so those two characters could never be the bracket
>    color. Python's `def`/`class` mode and C++'s `function` mode drop that
>    child, keep its literal/comment rules, and let the shared paren rule color
>    every parenthesis.
> 3. **Braces and square brackets are their own classes.** The patched rules emit
>    `curlyBrace` / `squareBracket` (not one shared `punctuation` class) so only
>    Colorful can give them their own colors while Standard maps both back onto
>    the old bracket color. Inside plain strings / comments, and inside Dart
>    `${…}` / Python `{…}` interpolation, those characters keep the enclosing
>    string color — the rules are `contains` entries of the grammar, so a string
>    mode still wins.
> Strings, comments, numbers, `#include` (meta) and Python `#` comments keep
> their own colors.

### Syntax scheme change flow
`View > Syntax Colors > Standard | Colorful`
→ `EditorSettingsService.setSyntaxScheme()` (notifies + saves)
→ `CodeEditorPanel` rebuilds on that notification
→ `CodeThemeData(styles: getThemeStyles(scheme))` → `CodeTheme.updateShouldNotify`
→ the `EditableText` re-renders with the new styles. No restart, no re-parse,
no controller recreation.

### Common Rules:
- Border width: 2.0
- Corner radius: 0.0 (NO rounded corners, incl. internal widgets only)
- UI font family: Arial
- Font UI size: 12.0 (buttons/menus/labels), 11.0 (status bar)
- Font code size: 13.0–14.0 (Menlo)
- Editor line height: `editorFontSize` 13.0 × `editorLineHeightFactor` (19/13 = ~1.46) = **19.0px**
  (shared by the editor text, strut style, and line number gutter so rows and baselines never drift)
- Button height: 22.0 (fixed) — 1px gap above/below inside the toolbar
- Bar heights (px): menu bar 24, toolbar 28, status bar 24
- Paused-line highlight: `ThemeService.colors.pausedLine` (#FFF0A0 VC6 /
  #E9D9A5 Delphi / #DCDCA8 VB6 / #DCDCA8 Turbo Pascal)
- Current-line band: `colors.selection` at alpha 0.14 fill + alpha 0.45 hairline
  border, `height == lineHeight`, positioned from the wrap-aware gutter rows and
  offset by the editor scroll position
- Gutter row: line numbers on the left, marker slot on the right, 10px reserved
  at the right edge for the platform scrollbar the desktop scroll behaviour adds
  to the gutter's `ListView` (`gutterScrollbarInset`)

### Retro widget inventory (lib/ui/retro/)
| Widget | Notes |
|--------|-------|
| `RetroBorder` | `raised()` / `sunken()` / `flat()`; 2px border, `BorderRadius.zero` |
| `RetroButton` | Fixed 22px height; forces Arial 12 / w500 via `DefaultTextStyle` |
| `RetroPanel` | Raised container with margin/padding |
| `RetroColors` | All getters delegate to `ThemeService.instance.colors.*` |
| `SyntaxColors` | 8 syntax slots + `forTheme(ThemeType)` |
| `RetroTheme` | `ThemeData(useMaterial3: false)` + global `TextTheme` |
| `LanguageLogo` | Per-language icon: tries `assets/icons/{lang}.png` (`dart` / `python` / `c` / `cpp` / `asm`), falls back to a vector `CustomPainter` |
| `showRetroAboutDialog()` | Retro Help → About dialog (About & Developer / Shortcuts / System Info) |
| `RetroWatchWindow` | Variables watch window (sunken panel bound to `DebugService`) |

### Theme persistence
`ThemeService` writes the active theme to `.retro_theme_config.json` and
restores it on launch. `enum ThemeType { vc6, delphi, vb6, turboPascal }`.
