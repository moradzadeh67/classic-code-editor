<p align="center">
  <a href="https://github.com/moradzadeh67/classic-code-editor">
    <img src="assets/branding/readme-banner.png" width="100%" alt="Classic Code Editor Banner">
  </a>
</p>

<p align="center">
  <a href="https://github.com/moradzadeh67/classic-code-editor/releases/latest">
    <img src="https://img.shields.io/github/v/release/moradzadeh67/classic-code-editor?style=for-the-badge&color=2e7d32" alt="Latest Release">
  </a>
  <a href="https://opensource.org/licenses/MIT">
    <img src="https://img.shields.io/badge/License-MIT-orange.svg?style=for-the-badge" alt="License MIT">
  </a>
  <a href="https://www.apple.com/macos/">
    <img src="https://img.shields.io/badge/Platform-macOS-black?style=for-the-badge&logo=apple" alt="Platform macOS">
  </a>
  <a href="https://flutter.dev">
    <img src="https://img.shields.io/badge/Flutter-3.47.2-02569B?style=for-the-badge&logo=flutter" alt="Flutter">
  </a>
  <a href="https://dart.dev">
    <img src="https://img.shields.io/badge/Dart-3.13.2-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  </a>
  <a href="https://github.com/moradzadeh67/classic-code-editor/actions/workflows/ci.yml">
    <img src="https://github.com/moradzadeh67/classic-code-editor/actions/workflows/ci.yml/badge.svg" alt="CI Status">
  </a>
</p>

<p align="center">
  <a href="https://github.com/moradzadeh67/classic-code-editor/releases/latest"><b>📥 Download for macOS</b></a> •
  <a href="https://moradzadeh67.github.io/classic-code-editor/"><b>🌐 Website</b></a> •
  <a href="#-features"><b>✨ Features</b></a> •
  <a href="#-architecture"><b>🏗️ Architecture</b></a> •
  <a href="#-installation"><b>🚀 Installation</b></a> •
  <a href="#-troubleshooting--faq"><b>❓ FAQ</b></a>
</p>

---

## 🌍 What is Classic Code Editor?

**Classic Code Editor** is a **free, open-source IDE for macOS** that brings back the dense, functional
UI of the 90s — Borland C++, Visual C++ 6.0, Delphi — without giving up modern tooling.

It is a real IDE, not a mock-up:

- ✅ **100% free** — no accounts, no telemetry, no backend
- ✅ **MIT licensed** — read it, fork it, ship it
- ✅ **Real language intelligence** — the actual Dart language server over LSP (diagnostics, hover, completion)
- ✅ **Real debuggers** — Dart VM Service, Python `sys.settrace`, C/C++ via `clang` + `lldb`, with breakpoints and variable inspection
- ✅ **Three authentic retro themes** — VC++ 6.0, Borland Delphi, Visual Basic 6.0
- ✅ **Everything stays on your machine** — code is run and debugged locally

## 💡 Why I Built This

I grew up fascinated by the golden age of IDEs — Borland C++, Visual C++ 6.0, Delphi. They had a **dense, functional, no-nonsense UI** that modern editors have lost in favor of rounded corners and minimalism.

I wanted to build a **real IDE** — not a toy — that:
- Runs natively on macOS (my daily driver)
- Supports multiple languages (Dart, Python, C, C++)
- Has **real LSP integration** and a **real debugger** with breakpoints and variable inspection
- Brings back the **retro 3D UI** of the 90s

Classic Code Editor is my attempt at a **production-quality IDE** with a retro soul.

## 🎬 Demo

<p align="center">
  <img src="assets/demo/demo.gif" width="620" alt="Classic Code Editor demo: switching between the VC++ 6.0, Borland Delphi and Visual Basic 6.0 themes">
</p>

Switching between the three authentic themes — the same IDE shell, restyled to each 90s environment.

## 📸 Screenshots

### VC++ 6.0

| Editor | Debugger | Terminal |
|:---:|:---:|:---:|
| <img src="assets/screenshots/vc6-editor.png" width="280" /> | <img src="assets/screenshots/vc6-debugger.png" width="280" /> | <img src="assets/screenshots/vc6-terminal.png" width="280" /> |

### Borland Delphi

| Editor | Debugger | Terminal |
|:---:|:---:|:---:|
| <img src="assets/screenshots/delphi-editor.png" width="280" /> | <img src="assets/screenshots/delphi-debugger.png" width="280" /> | <img src="assets/screenshots/delphi-terminal.png" width="280" /> |

### Visual Basic 6.0

| Editor | Debugger | Terminal |
|:---:|:---:|:---:|
| <img src="assets/screenshots/vb6-editor.png" width="280" /> | <img src="assets/screenshots/vb6-debugger.png" width="280" /> | <img src="assets/screenshots/vb6-terminal.png" width="280" /> |

## ✨ Features

### 🎨 Authentic Retro UI
- **3 Classic Themes:** VC++ 6.0 (gray), Borland Delphi (beige), Visual Basic 6.0
- **3D Raised/Sunken Borders:** Authentic Windows 95/98 look — no rounded corners
- **Theme Persistence:** Your theme choice is saved across restarts
- **Retro Panels:** Console, Terminal, Diagnostics, Debugger, Variables, Breakpoints

### ℹ️ Help & About
- **Help menu:** About, Keyboard Shortcuts, and System Info
- **About dialog:** three retro tabs — *About & Developer*, *Shortcuts*, and
  *System Info* (Flutter/Dart versions, active theme, platform)

### ⌨️ Smart Code Editor
- **Multi-Language Support:** Dart, Python, C, C++
- **Syntax Highlighting:** Per-language syntax colors, IntelliJ-style —
  operators dark green (`#0B6E00`), brackets blue (`#031CFC`)
- **Language Logos:** Real per-language icons in the panel header (with a
  vector fallback when an asset is missing)
- **Auto-Indentation:** Smart indentation on Enter, auto-dedent on closing brackets
- **LSP Integration:** Real-time diagnostics, hover tooltips, autocomplete
- **Offline Completion:** Falls back to a built-in per-language keyword/API list
  when the language server is unavailable
- **Breakpoint Gutter:** Click line number to toggle breakpoints
- **Tab Bar:** Multiple files with modified indicators
- **Editor Zoom:** `Cmd +` / `Cmd -` / `Cmd 0` changes font size (8..32) with live gutter alignment

### 🐛 Real Multi-Language Debuggers
- **Debug Controls:** Debug, Stop, Step Over, Step Into, Step Out, Continue
- **Breakpoint Gutter:** Click a line number to set/unset a breakpoint; the
  paused line shows a `▶` marker drawn alongside the `●` bullet
- **Breakpoints Panel:** Set, remove, clear all breakpoints (auto-cleaned when
  the surrounding code is edited away)
- **Variables Panel:** Live variable inspection at the paused frame
- **Call Stack Panel:** Full call stack visualization
- **Per-language engines:** Dart drives a real **Dart VM Service** client
  (JSON-RPC over WebSocket — no extra package), Python runs a `sys.settrace`
  tracer, and C/C++ compile with `clang -g -O0` and attach **lldb**
- **Stops in *your* code:** every language installs an entry breakpoint in your
  `main`, so Debug pauses inside your file instead of VM or linker internals
- **Modular Architecture:** `BaseDebugger` interface + `DebuggerFactory`
  dispatch — the shell never learns which languages exist

### 🖥️ Integrated Terminal & Console
- **Terminal:** Full shell access with colored output
- **Console:** Live program output with color-coded lines
- **Debug Output Bridge:** Debugger banners, pauses and exit codes stream into
  the Console, so a session is never silent
- **Interactive Stdin:** Send input to running programs
- **Copy All / Copy Errors:** One-click clipboard export

### ⌨️ Keyboard Shortcuts
- `F5` — Run code
- `Cmd+S` — Save & auto-format
- `Cmd+N` — New file
- `Cmd+Z` / `Cmd+Y` — Undo / Redo
- `↑` / `↓` — Navigate autocomplete
- `Enter` — Accept autocomplete
- `Esc` — Dismiss autocomplete

## 🛠️ Tech Stack

- **Framework:** Flutter 3.x (macOS Desktop)
- **Language:** Dart 3.13.2+
- **Code Editor:** [`flutter_code_editor`](https://pub.dev/packages/flutter_code_editor)
- **Syntax Highlighting:** [`highlight`](https://pub.dev/packages/highlight)
- **File Picker:** [`file_picker`](https://pub.dev/packages/file_picker)
- **Path Handling:** [`path_provider`](https://pub.dev/packages/path_provider)
- **State Management:** Service-oriented + `ChangeNotifier`
- **LSP:** JSON-RPC over stdio via custom `JsonRpcClient`
- **Debugger:** Dart VM Service (JSON-RPC over WebSocket), Python `sys.settrace`, C/C++ `clang` + `lldb`
- **Architecture:** Layered (UI / Services / Models / Utils)

### Key Dependencies

| Package | Version | Purpose |
|---|:---:|---|
| `flutter_code_editor` | `^0.3.5` | The code editor surface (with the `highlight` language modes) |
| `highlight` | `^0.7.0` | Syntax highlighting for Dart, Python, C and C++ |
| `file_picker` | `^8.0.0` | Native macOS open/save dialogs |
| `path_provider` | `^2.1.0` | Locating the app's support directory |
| `cupertino_icons` | `^1.0.8` | macOS-style icon set |

> 💡 **Note:** Versions are the constraints declared in `pubspec.yaml`. The LSP, VM-service and debugger
> clients are **hand-written** on `dart:io` (`WebSocket`, `Process`) — no extra package is pulled in for
> them ([Technical Decisions](#-technical-decisions)).

## ✅ Testing

The suite runs fully offline — no language server, compiler or VM is spawned.

```bash
# Static analysis must report zero issues
flutter analyze

# Unit + widget tests (119 tests; 1 opt-in integration test is skipped)
flutter test

# Opt-in: really spawn a Dart VM and attach over a real WebSocket
BORLAND_REAL_VM_TEST=1 flutter test test/integration/dart_vm_pause_test.dart
```

`DebuggerEnvironment` short-circuits every debugger while `FLUTTER_TEST` is set,
so the default `flutter test` run never launches `dart`, `python` or
`clang`/`lldb`. The opt-in test above flips that guard on for a single run so the
real attach/pause chain can be exercised. See [docs/DEBUGGING.md](docs/DEBUGGING.md)
for the full debugging architecture and troubleshooting guide.

## 🔧 Build & Release

The macOS DMG is produced by the release gate in `scripts/release_gate/`, which runs the whole chain in
order — analyze → test → release build → launch smoke test → package:

```bash
scripts/release_gate/01_analyze.sh      # flutter analyze (must be clean)
scripts/release_gate/02_test.sh         # flutter test (offline)
scripts/release_gate/03_build_macos.sh  # flutter build macos --release
scripts/release_gate/04_launch_smoke.sh # launch the built app
scripts/release_gate/05_make_dmg.sh     # package the .app into a DMG (hdiutil)
```

`05_make_dmg.sh` names the artifact `Classic.Code.Editor-<version>.dmg` from `pubspec.yaml`, so **the
pubspec version, the git tag and the DMG name stay in sync** (`1.1.0+3` → tag `v1.1.0` →
`Classic.Code.Editor-1.1.0+3.dmg`).

> [!NOTE]
> The app is **unsigned and not notarized** (that needs a paid Apple Developer account). Every user must
> therefore use **System Settings → Privacy & Security → Open Anyway** once on first launch.

Full details and the pre-release checklist: [docs/RELEASE.md](docs/RELEASE.md).

## 🔄 CI/CD

| Workflow | Trigger | What it does |
|---|---|---|
| [`ci.yml`](.github/workflows/ci.yml) | push & PR to `main` | Runs `flutter analyze` and `flutter test` on `macos-latest` (Flutter 3.47.2) |

The DMG is **not** built in CI yet — releases are produced locally by the release gate above.

## 🏗️ Architecture

Classic Code Editor follows a clean layered architecture with strict separation of concerns:

### Project Structure

<img src="assets/diagrams/project-structure.png" alt="Project Structure" width="600">

### Architecture Layers

<img src="assets/diagrams/architecture-layers.png" alt="Architecture Layers" width="800">

### Data Flow

<img src="assets/diagrams/data-flow.png" alt="Data Flow" width="600">

### Layer Breakdown

```text
lib/
├── main.dart                        → Entry point
├── app.dart                         → MaterialApp + ThemeService
│
├── models/                          → Pure Dart data classes
│   ├── debugger_models.dart
│   ├── diagnostic.dart
│   ├── language_config.dart
│   ├── lsp_models.dart
│   └── tab_file.dart
│
├── services/                        → Business logic + SDK interaction
│   ├── analyzer_service.dart        → Static analysis (dart analyze)
│   ├── base_debugger.dart           → Abstract debugger (+ output stream, paused line)
│   ├── c_debugger.dart              → C/C++ debugger (clang + lldb)
│   ├── dart_debugger.dart           → Dart debugger (VM Service)
│   ├── dart_runner_service.dart     → Execute Dart code
│   ├── debug_service.dart           → Live variable watcher
│   ├── debugger_environment.dart    → Test seam (real-process gate)
│   ├── debugger_factory.dart        → Language → debugger dispatch
│   ├── debugger_manager.dart        → Active debugger follows the active tab
│   ├── debugger_snapshot.dart       → Shared stop-payload decoder
│   ├── file_service.dart            → Open/Save files
│   ├── language_runner_service.dart → Execute Python/C/C++
│   ├── lsp_service.dart             → Language Server Protocol
│   ├── python_debugger.dart         → Python debugger (sys.settrace tracer)
│   ├── terminal_service.dart        → Shell commands
│   └── theme_service.dart           → 3 themes + persistence
│
├── ui/                              → Pure Flutter widgets
│   ├── analyzer/                    → Diagnostics panel
│   ├── console/                     → Console output
│   ├── debugger/                    → Variables, call stack, breakpoints panels
│   ├── editor/                      → Code editor, tabs, autocomplete, hover
│   ├── explorer/                    → (placeholder - the file explorer lives in shell/panel_layout.dart)
│   ├── retro/                       → Retro design system (+ about dialog, logos)
│   ├── shell/                       → IDE shell (menu, toolbar, status)
│   └── terminal/                    → Integrated terminal
│
└── utils/                           → Helpers, constants
    ├── app_shortcuts.dart
    ├── completion_filter.dart
    ├── dart_highlighter.dart
    ├── json_rpc_client.dart
    ├── multi_language_highlighter.dart
    └── vm_service_client.dart
```

## 🎨 Retro Design System

### Themes

| Theme | Background | Panel | Editor BG |
|-------|:---:|:---:|:---:|
| **VC++ 6.0** | `#0055EA` (blue XP) | `#ECE9D8` | `#E8F1FF` |
| **Borland Delphi** | `#D2BA7E` (warm beige) | `#DFCD9B` | `#E8F1FF` |
| **Visual Basic 6.0** | `#2C4A8E` (dark blue) | `#C0C0C0` | `#E8F1FF` |

### Design Rules
- **NO rounded corners** (`BorderRadius.zero`) — internal widgets only
- **2px borders** for 3D raised/sunken effects
- **No gradients, no transparency**
- **Dense spacing** (4-8px padding)
- **Fonts:** Arial for UI, Menlo for code
- **Button height:** 22px (fixed)
- **Colors come from ThemeService** — never hardcoded

## 📱 Platform Support

| Platform | Status | Notes |
|---|:---:|---|
| 🖥️ macOS | ✅ Released | macOS 12+ (Monterey or later) — v1.1.0 · [download the DMG](https://github.com/moradzadeh67/classic-code-editor/releases/latest) |
| 🪟 Windows | 🔜 Planned | Next major target (v1.x) |
| 🐧 Linux | 🔜 Planned | After Windows |
| 📱 iOS / Android | ❌ Not planned | An IDE needs a keyboard and a real shell |
| 🌐 Web | ❌ Not planned | Requires a backend — out of scope |

> **Note:** This app spawns external processes (`dart`, `python3`, `clang`, `lldb`). The macOS App Sandbox is **disabled** (`com.apple.security.app-sandbox = false`) to allow `Process.start`.

## 🔒 Privacy & Security

> [!IMPORTANT]
> - **Local only.** No accounts, no analytics, no crash reporting, no backend. Your code, file names and terminal output never leave your machine.
> - **Local processes.** Running, debugging and the language server all start processes on *your* machine; the VM Service connection is bound to `localhost`.
> - **Sandbox disabled by design.** An IDE must be able to spawn compilers, debuggers and shells, so `com.apple.security.app-sandbox = false`. The app has the same file access as any normal unsigned macOS app — only run code you trust.
> - **No secrets in this repository**, and the app needs none.

Details: [docs/PRIVACY.md](docs/PRIVACY.md) · Vulnerability reports: [SECURITY.md](SECURITY.md).

## 🚀 Installation

### Download Pre-built Release

1. Download the latest `.dmg` (`Classic.Code.Editor-1.1.0+3.dmg`) from [Releases](https://github.com/moradzadeh67/classic-code-editor/releases/latest)
2. Open the `.dmg` and drag `Classic Code Editor.app` to `Applications`
3. **First launch (Gatekeeper):** the app is not notarized, so macOS blocks it — click **Done** on the dialog, then open **System Settings → Privacy & Security → Open Anyway** ([Apple: Safely open apps on your Mac](https://support.apple.com/en-us/102445))

### Build from Source

```bash
# Clone
git clone https://github.com/moradzadeh67/classic-code-editor.git
cd classic-code-editor

# Install dependencies
flutter pub get

# Run
flutter run -d macos

# Build release
flutter build macos --release
```

### System Requirements

- macOS 12+ (Monterey or later)
- Dart SDK (bundled with Flutter — used at runtime for executing Dart code)
- Python 3 (for running Python code)
- Clang (for running C/C++ code — comes with Xcode Command Line Tools)
- LLDB (for debugging C/C++ code — ships with the Xcode Command Line Tools)

## ⚠️ Known Limitations

- **Unsigned / not notarized** — Gatekeeper blocks the first launch until you choose *Open Anyway*.
- **External toolchain required** — running and debugging needs `dart`, `python3`, `clang` and `lldb` on your `PATH`; without them the editor still works but Run/Debug fails with a clear message.
- **LSP today is Dart-only** — Python and C/C++ language servers (pyright/clangd) are on the roadmap.
- **macOS only** — Windows and Linux are planned; iOS/Android/Web are out of scope for an IDE.
- **Not sandboxed** — see [Privacy & Security](#-privacy--security) for why.

## ❓ Troubleshooting & FAQ

<details>
<summary><b>1. macOS says the app "can't be opened because Apple cannot check it for malicious software".</b></summary>

The DMG is unsigned. Click **Done** on the dialog, then open **System Settings → Privacy & Security**,
scroll to the security section and choose **Open Anyway** for *Classic Code Editor*. You only need to do
this once. See [Apple's guide](https://support.apple.com/en-us/102445).
</details>

<details>
<summary><b>2. Run / Debug does nothing or reports a missing tool.</b></summary>

Install the toolchain: Xcode Command Line Tools give you `clang` and `lldb`
(`xcode-select --install`); Python 3 comes from python.org, Homebrew or Xcode; `dart` is used at runtime
for Dart programs. Verify with `which dart python3 clang lldb` in a terminal.
</details>

<details>
<summary><b>3. The status bar says "LSP: Disconnected".</b></summary>

The language server starts when a Dart file is open. Open a `.dart` file from *File → Open* and give it a
moment; if it stays disconnected, make sure `dart` is on `PATH` (the app spawns `dart language-server`).
</details>

<details>
<summary><b>4. Why does everything look like Windows 95/98?</b></summary>

That is the point. The retro design system uses **2px raised/sunken borders, zero rounded corners, no
gradients and no transparency**, and the three themes are colour-matched to Visual C++ 6.0, Borland Delphi
and Visual Basic 6.0. See [Retro Design System](#-retro-design-system).
</details>

<details>
<summary><b>5. How do I change the theme?</b></summary>

Use the **Theme ▾** button in the toolbar (or the View menu). The choice is saved to a small
`.retro_theme_config.json` next to where you launched the app.
</details>

## 💻 Development Environment

This project is actively developed and tested using:

- **Hardware:** MacBook Pro (Apple M3 Pro)
- **OS:** macOS 27.0.1
- **IDE:** VS Code / Android Studio
- **Xcode:** 27.0
- **Flutter:** 3.47.2 (stable)
- **Dart SDK:** 3.13.2

### Requirements

- Dart SDK: `^3.13.2`
- macOS 12+ (Monterey or later)
- Xcode Command Line Tools (for `clang` and `lldb`)

## 🗺️ Roadmap

- [x] Phase 01 — Project Skeleton
- [x] Phase 02 — Retro UI Design System
- [x] Phase 03 — IDE Shell
- [x] Phase 04 — Code Editor
- [x] Phase 05 — Dart Runner
- [x] Phase 06 — Console
- [x] Phase 07 — File Management
- [x] Phase 08 — Tabs & Projects
- [x] Phase 09 — Dart Analyzer (Static)
- [x] Phase 10 — Dart LSP (Real-time)
- [x] Phase 11 — IDE Intelligence (Autocomplete, Hover)
- [x] Phase 12 — Terminal
- [x] Phase 13 — Debugger
- [x] Phase 14 — Multi-Language Support
- [x] Phase 15 — Multi-Language Debugging
- [x] Phase 16 — Debugger Hardening & Test Coverage
- [ ] Python LSP support
- [ ] C/C++ LSP support (clangd)
- [ ] On-device ML for code suggestions

See [ROADMAP.md](ROADMAP.md) for the canonical phase list and
[docs/PHASE_DETAILS.md](docs/PHASE_DETAILS.md) for per-phase scope.

## 🛠️ Technical Decisions

Every technical choice was made with simplicity, performance, and authenticity in mind:

- **Flutter Desktop for macOS:** The only way to get a native macOS app with a single Dart codebase.
- **Service-oriented architecture:** All business logic lives in `lib/services/`. UI widgets never call Process or the Dart SDK directly — they observe services via ChangeNotifier.
- **BaseDebugger + DebuggerFactory:** A single abstract debugger surface lets `DebuggerFactory` map a language to the right engine, so adding a language never touches the UI.
- **Hand-rolled Dart VM Service client:** The VM Service speaks JSON-RPC over a WebSocket; `VmServiceClient` wraps `dart:io`'s `WebSocket`, avoiding a new package while giving real breakpoints, stepping and call stacks.
- **LSP over JSON-RPC:** Connects to the official Dart language server via stdio, giving real diagnostics, autocomplete, and hover.
- **flutter_code_editor over custom:** Building a code editor from scratch is a project on its own — we layer syntax highlighting via `highlight`.
- **macOS App Sandbox disabled:** Required because the app spawns external processes.
- **No rounded corners:** Authentic to the 90s aesthetic.

## 🤖 Development Approach

This project was built with a **phase-gated, specification-first workflow**: the scope of each
phase was written before implementation, the file structure and coding rules were fixed up front
(`AGENTS.md`, `ARCHITECTURE.md`), and nothing moved forward without explicit approval.

Implementation was carried out by **AI coding agents** operating under those written rules — they
implement, run the checks, and report back for review. Architecture, scope, and the final call
stayed with me. This is honest AI-assisted development: agents accelerate the work, humans own
the design.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the
[issues page](https://github.com/moradzadeh67/classic-code-editor/issues). Please read
[CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to get started.
Security problems: please **do not** open a public issue — see [SECURITY.md](SECURITY.md).
Release history: [CHANGELOG.md](CHANGELOG.md).

## 🙏 Credits & Attribution

Built on top of [Flutter](https://flutter.dev), 
[flutter_code_editor](https://pub.dev/packages/flutter_code_editor), 
[highlight](https://pub.dev/packages/highlight), 
the [Dart Language Server](https://github.com/dart-lang/sdk/tree/main/pkg/analysis_server), 
the [Dart VM Service](https://github.com/dart-lang/sdk/tree/main/pkg/vm_service), 
and [LLDB](https://lldb.llvm.org/). 
Design inspired by Visual C++ 6.0, Borland Delphi, and Visual Basic 6.0.

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

Copyright © 2026 Mohammadreza Moradzadeh ([@moradzadeh67](https://github.com/moradzadeh67))
