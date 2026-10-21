# Classic Code Editor — v1.4.0 release notes

**A retro IDE that stopped losing breakpoints, gained a font picker, and finally maps Assembly source lines.**

## Highlights

- **Breakpoints in C/C++/ARM64 assembly can no longer be silently lost.** lldb's stdin is a pipe: a command
  written while lldb was still printing a stop report arrived split (`breakpoint set -a 0x…` reached lldb as
  `b` + `reakpoint set -a 0x…`), the breakpoint was never installed and the program ran to completion. All
  stdin now goes through one queue (`LldbCommandQueue`) — one command in flight, gated on a 40 ms quiet
  window, verified with a `script print("@@ACK n")` sentinel, and retried once (idempotently) when the ack is
  lost. Continue/Step jump the queue. Stop closes the queue, then `process kill` + `quit`, waits 2 s, SIGKILLs
  lldb and finally the inferior pid — no more orphaned `borland_*_exec` processes.
- **ARM64 Assembly source-line debugging.** Clicking the gutter of a hand-written `.s` file sets a breakpoint
  that stops on exactly that line — anywhere in the file, including code assembled *before* `_main`.
  `Arm64AsmParser` maps every instruction to a 4-byte offset **relative to the entry symbol** (negative
  before it, because Apple's toolchain ships no DWARF line table for `.s`), and `AsmDebugger` installs the
  breakpoints with `breakpoint set -a <main + offset>` once the entry stop reveals the load address.
- **Editor font choice (`View > Font`)** — **Menlo** (default, pixel-identical to before) or
  **Recursive Mono Casual**, with a check mark on the active one. The choice is persisted next to `fontSize`
  in `editor_settings.json` as a stable id (`menlo` | `recursive`); an unknown or corrupt value falls back to
  Menlo. It applies to the code **and** the gutter line numbers, while the rest of the UI stays on Arial.
  Monaco is gone — it ships no real bold/italic and its metrics made the row height follow the fallback font
  of a Persian glyph.
- **Recursive Mono Casual is bundled** (`assets/fonts/`, four static faces + `OFL.txt`, ~1.5 MB) and declared
  in `pubspec.yaml` under the alias `RecursiveMonoCasual`, so the lookup never depends on a font installed on
  the host. New `THIRD_PARTY_NOTICES.md`; README gained a *Fonts and licensing* section.
- **Correct gutter numbering on the first frame.** The row model is measured from the renderer in a
  post-frame pass, and that pass used to give up silently when the editable was not measurable yet — exactly
  the first frame after opening a big pasted, wrapping document. It now retries (bounded) until the renderer
  is measurable and rejects a measurement that reports fewer rows than the document has logical lines.
- **Continuation rows are inert.** A wrapped line's second and later rows have no line number, but the
  gutter row was still tappable and called `setBreakpoint(path, 0)`. Continuation rows no longer accept a
  breakpoint, and `_toggleBreakpoint` ignores non-positive lines.
- **The hover tooltip/autocomplete anchor no longer jumps on mouse move.**
- **The opt-in ARM64 entry-stop test can actually pass** — it now sets `DebuggerEnvironment.allowRealProcesses`
  and polls for the pause instead of asserting immediately, then asserts the pausing line, `mainAddress`, the
  register file (`x0`..`x28`, `fp`, `lr`, `sp`, `pc`, `cpsr`) and a `pc=0x` Console line.
- Turbo Pascal + ARM64 Assembly screenshots in the README gallery, and refreshed architecture diagrams
  (SVG sources + PNG exports).

## Requirements

- macOS 12+ (Monterey or later), Universal (Intel and Apple Silicon Macs); ARM64 assembly run/debug requires Apple Silicon.
- Unsigned and not notarized: macOS blocks the first launch — right-click > Open or System Settings > Privacy & Security > Open Anyway.

## Verification

- `flutter analyze` clean.
- `flutter test` — **329 tests pass**, 6 opt-in real-process tests skipped (see
  `BORLAND_REAL_*_TEST=1`).
- Release gate: `scripts/release_gate/01_analyze.sh` → `05_make_dmg.sh`.
- DMG: `Classic Code Editor-1.4.0+6.dmg` (universal build).
