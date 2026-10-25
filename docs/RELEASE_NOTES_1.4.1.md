# Classic Code Editor — v1.4.1 release notes

**A color-and-language release: language servers for C/C++, Python and Dart, a second syntax palette, and
highlighting that finally behaves the same in all five languages.**

## Highlights

- **Language servers for C/C++ and Python.** The LSP layer no longer hard-codes `dart language-server`.
  `clangd` serves `.c`/`.cpp`, `pyright` (then `pylsp`) serves `.py`, and the Dart server serves `.dart` — each
  one kept warm while you switch tabs instead of restarting on every file. Nothing is installed automatically:
  a missing server prints its install hint to the Console **once** and the editor falls back to offline
  completion.
- **`compile_flags.txt` is generated for clangd** on the first C/C++ file, with
  `-isysroot $(xcrun --show-sdk-path)`, so `'stdio.h' file not found` stops appearing. An existing file of
  yours is never overwritten.
- **`View > Syntax Colors` — Standard and Colorful.** Standard is the classic palette, unchanged and still the
  default; Colorful is an eleven-color palette tuned for the `#E8F1FF` editor surface. The switch is live in all
  four themes, for every language, and is remembered across restarts (`editor_settings.json`).
- **Python is colored.** `def`, `class`, decorators, f-strings (including the `{...}` interpolations), numbers,
  `True`/`None`, comments and built-ins such as `print` all render in their own colors — in a saved `.py` file
  and in an untitled Python tab alike, because the editor now sniffs an unsaved buffer's content instead of
  assuming Dart.
- **Assembly reads like code.** Labels (`msg:`, `_main:`) use the label/function color instead of the operator
  green, and commas, writebacks (`!`) and brackets are colored like every other language.

## Fixes

- **Every parenthesis is the bracket color.** `int sum = std::accumulate(v.begin(), v.end(), 0);` and
  `def __init__(self, name, grades):` used to paint their own `(` `)` in the parameter-list color; the bundled
  grammars' paren-owning modes are gone, so the shared bracket rule colors them everywhere.
- **Python tokens are no longer black** when the editor mounts with a file already open, in an untitled tab,
  or while typing one.
- **The first file opened during server startup can reach the language server.** `startServer` is a shared
  future, so `openFile` waits for the handshake instead of dropping the document.
- **The static-analysis fallback no longer runs `dart analyze` on C or Python files.**
- **An empty first completion is retried once** (200 ms), because clangd/pyright are still indexing right after
  `initialized`.
- **The status bar's LSP segment** has a tooltip naming the active server and the reason it is not running.

## Under the hood

- One source of truth for colors: a token-class → category map plus one color map per scheme, so Assembly
  registers (`built_in`), directives (`meta`) and labels (`title`) follow the same categories as the other
  languages.
- One source of truth for languages: `LanguageConfig.fromPathOrContent()` does extension-then-content
  resolution for the editor **and** Run/Debug, so colors and the runner can never disagree.
- Documentation: README, CHANGELOG, ARCHITECTURE (palette table + grammar-patch rules), AGENTS (Rule 13),
  PHASE_DETAILS, RELEASE and TASKS updated for this release.

## Verification

- `flutter analyze` — clean.
- `flutter test` — **368 pass**, 8 opt-in/real-process tests skipped by design.
- Manual: all four themes (VC++ 6.0, Delphi, VB6, Turbo Pascal) × `.dart`, `.py`, `.c`, `.cpp`, `.s` × both
  syntax schemes.

## Install

1. Download `Classic Code Editor-1.4.1+7.dmg` (universal build) below.
2. Drag **Classic Code Editor** into `Applications`.
3. First launch: right-click the app → **Open** (the build is unsigned and not notarized), then confirm.

Requires macOS 12+ (Monterey or later); ARM64 assembly run/debug needs Apple Silicon.
