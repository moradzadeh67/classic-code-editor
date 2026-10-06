# ARCHITECTURE.md — borland_dart

## Overview
borland_dart is a Flutter Desktop app for macOS.
It provides a retro-styled environment to write, run, and debug Dart code.
Supports three themes: VC++ 6.0 (gray), Borland Delphi (beige), and
Visual Basic 6.0.

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
  View menu toggles the explorer/console and switches themes.
- `retro_toolbar.dart` — 28px; New / Open / Save | Run / Stop, plus the theme
  selector (short labels: `VC++ 6.0` / `Delphi` / `VB6`). The selector lives in
  an `Expanded` + horizontal `SingleChildScrollView` so it can never overflow.
- `panel_layout.dart` — file explorer (200px) + editor + bottom panel (150px),
  toggleable from the View menu. The bottom panel switches between Console and
  Diagnostics via an internal retro tab strip.
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

### macOS sandbox note
RetroDart spawns the Dart SDK (`dart run`, `dart language-server`) as a child
process. App Sandbox forbids exec'ing external binaries, so
`macos/Runner/*.entitlements` set `com.apple.security.app-sandbox` to `false`.
Without this, both `DartRunnerService` and `LspService` fail with
"Operation not permitted".

## Approved Dependencies

| Package | Purpose | Status |
|---------|---------|--------|
| flutter_code_editor | Code editing | Phase 04 |
| file_picker | File open/save | Phase 07 |
| path_provider | File paths | Phase 07 |

## Services

| Service | Phase | Status | Purpose |
|---------|-------|--------|---------|
| ThemeService | 02.5 | ✅ | Theme management |
| DartRunnerService | 05 | ✅ | Execute Dart code |
| FileService | 07 | ✅ | Open/Save files |
| AnalyzerService | 09 | ✅ | Static analysis (fallback) |
| LspService | 10 | ✅ | Real-time diagnostics via LSP |
| DebuggerService | 13 | ⬜ | Debugging |
| TerminalService | 12 | ⬜ | Integrated terminal |

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
- Button height: 22.0 (fixed) — 1px gap above/below inside the toolbar
- Bar heights (px): menu bar 24, toolbar 28, status bar 24

### Retro widget inventory (lib/ui/retro/)
| Widget | Notes |
|--------|-------|
| `RetroBorder` | `raised()` / `sunken()` / `flat()`; 2px border, `BorderRadius.zero` |
| `RetroButton` | Fixed 22px height; forces Arial 12 / w500 via `DefaultTextStyle` |
| `RetroPanel` | Raised container with margin/padding |
| `RetroColors` | All getters delegate to `ThemeService.instance.colors.*` |
| `SyntaxColors` | 8 syntax slots + `forTheme(ThemeType)` |
| `RetroTheme` | `ThemeData(useMaterial3: false)` + global `TextTheme` |

### Theme persistence
`ThemeService` writes the active theme to `.retro_theme_config.json` and
restores it on launch. `enum ThemeType { vc6, delphi, vb6 }`.
