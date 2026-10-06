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

## Phase 14: Final Polish
- Consistent retro styling
- Keyboard shortcuts
- Window state persistence
- About dialog