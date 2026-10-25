# Classic Code Editor — v1.4.2 release notes

**A small polish release: the Console starts clean on every run, the blue guide lines are readable, and an
unsaved C++/Python tab is served by the right language server.**

## Fixes

- **Every run starts on an empty Console.** Running C++ and then a Python buffer used to leave the previous
  program's output — and its blue `[Compiling C++ code with clang++ ...]` banner — above the new program's
  output. The runner now fires a dedicated *clear* event that the Console obeys before it prints anything, so
  the same language or a different one, Run always begins on a blank Console. Starting a debug session clears
  it too.
- **An unsaved C++ (or Python) tab no longer claims to be served by the Dart server.** The server used to be
  chosen from the file path alone, and an untitled buffer has none — so the status bar said
  *Dart language server: connected* while the editor colored the buffer as C++ and Run compiled it with
  `clang++`. Server selection and the `languageId` sent in `textDocument/didOpen` now use the same
  content-aware resolver as coloring, and an extensionless buffer is opened with the resolved extension
  (`Untitled` → `Untitled.cpp`) because clangd picks the grammar from the file name. Verified against the real
  clangd: it publishes diagnostics for such an in-memory document.

## Changed

- **The blue Console guide lines are a little bolder.** `[Running Python 3...]`, `[Compiling C++ code with
  clang++...]` and the other bracketed status lines were the only Console text at normal weight next to w600
  program output, which made them look washed out. They now match the weight of the output they introduce.

## Python tooling

`pyright` (`npm install -g pyright`, 1.1.414) was installed and verified end to end on macOS: `initialize`
handshake, `publishDiagnostics` and real error reporting for a `.py` buffer, saved or untitled. If the server is
ever missing, the Console prints the install hint **once** and the editor falls back to offline completion.

## Verification

- `flutter analyze` — clean.
- `flutter test` — **367 pass**, 8 opt-in/real-process tests skipped by design.
- Console clearing and the guide-line weight were checked on the real `ConsolePanel` widget.
- Manual: C++ buffer run followed by a Python buffer run (Console empty each time); untitled C++ tab shows
  `clangd language server: connected`; `.py` file gets pyright diagnostics and hover.

## Install

1. Download `Classic Code Editor-1.4.2+8.dmg` (universal build) below.
2. Drag **Classic Code Editor** into `Applications`.
3. First launch: right-click the app → **Open** (the build is unsigned and not notarized), then confirm.

Requires macOS 12+ (Monterey or later); ARM64 assembly run/debug needs Apple Silicon.
