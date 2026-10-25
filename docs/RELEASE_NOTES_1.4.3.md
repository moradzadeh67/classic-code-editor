# Classic Code Editor — v1.4.3 release notes

**Real diagnostics for C, C++ and Python again: the invented errors are gone, and an unsaved `Untitled` tab is
analyzed like a saved file.**

## Fixes

- **C and C++ reported dozens of errors for code that compiles and runs.** The `compile_flags.txt` the editor
  generates for clangd was written in a format clangd does not accept: that file has **no comment syntax**, so
  the `# …` header lines were passed to the compiler as arguments. The command became invalid, clangd lost the
  macOS SDK headers (`'iostream' file not found`, `'stdio.h' file not found`) and every `std::` use was reported
  as an error — 21 errors on a correct C++ program, 3 on a correct C program. The file now carries one argument
  per line (`-isysroot` and the SDK path on separate lines) and nothing else; it is not written when the SDK
  path cannot be resolved, and a file this app generated in the old broken format is repaired automatically.
  Measured against the real clangd: **21 → 0** diagnostics for the C++ sample, **3 → 0** for the C sample.
- **No more invented diagnostics for unsaved buffers.** A language server derives the grammar, the package
  context and the build flags from the document path, so an `Untitled` tab used to be analyzed as a fake file in
  the editor's working directory — clangd reported missing SDK headers and the Dart server flagged
  `Untitled.dart` as *"isn't a lower_case_with_underscores identifier"*. Those warnings are gone.

## Added

- **Unsaved buffers are now analyzed properly.** Every `Untitled` tab is exposed to the language server as
  `untitled.<ext>` — the extension its content resolved to — inside a per-session temp workspace that also
  contains `compile_flags.txt`. `clangd`, `pyright` and the Dart server therefore analyze it exactly like a
  saved file: real diagnostics, hover and completion *before* you press Save. Nothing is written for the buffer
  itself (`textDocument/didOpen` carries the text), nothing outside that temp directory is touched, and the
  directory is removed when the app exits. If the OS refuses to create it, the editor reports **LSP: Off** with a
  tooltip instead of guessing.
  - The Diagnostics panel labels such an entry `untitled.cpp` / `untitled.py` — that is the virtual document the
    language server sees, not a file on disk.

## Changed

- **The blue Console guide lines are lighter again.** w600 was too heavy; `[Running Python 3...]` and
  `[Compiling C++ code with clang++...]` now sit at w500 — clearly legible, still lighter than the w600 program
  output.

## Verification

- `flutter analyze` — clean.
- `flutter test` — **368 pass**, 8 opt-in/real-process tests skipped by design.
- Real servers against the virtual unsaved paths: clangd **0** diagnostics for valid C++ (was 21), pyright **1**
  real diagnostic (`"undefined_name" is not defined`), the Dart server **0** (no filename lint, no fake warning).
- Manual: a C++ buffer with Persian literals runs and shows `Errors: 0`; the same for the Fibonacci C sample.

## Install

1. Download `Classic Code Editor-1.4.3+9.dmg` (universal build) below.
2. Drag **Classic Code Editor** into `Applications`.
3. First launch: right-click the app → **Open** (the build is unsigned and not notarized), then confirm.

Requires macOS 12+ (Monterey or later); ARM64 assembly run/debug needs Apple Silicon.
