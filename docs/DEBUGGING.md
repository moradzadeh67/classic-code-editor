# DEBUGGING.md — Multi-Language Debugging

This document explains how the Classic Code Editor debugger works: the
shared contract, the per-language engines, the wire protocols, how to test it,
and the known limitations.

The debugger is designed around one rule: **the shell never learns which
languages exist.** The UI talks to a single `DebuggerManager`, which delegates to
a `BaseDebugger` chosen by `DebuggerFactory` for the active file's language.

---

## 1. Architecture at a glance

```text
RetroToolbar / RetroMenuBar
        │ Debug / Stop / Step / Continue
        ▼
DebuggerManager ── keeps the active debugger in sync with the active tab
        │
        ▼
DebuggerFactory ── LanguageConfig.extension → concrete debugger
        │
        ├─ DartDebugger    (.dart) ─────────► Dart VM Service (JSON-RPC / WebSocket)
        ├─ PythonDebugger  (.py)  ─────────► python3 + sys.settrace driver
        └─ CDebugger       (.c/.cpp/…) ────► clang -g -O0 + lldb
        │
        ▼
BaseDebugger.output (broadcast Stream<String>)
        │
        ▼
IDEShell ──► LanguageRunnerService.emitOutput ──► ConsolePanel
```

`BaseDebugger extends ChangeNotifier`, so panels rebuild reactively as
`state`, `currentPausedLine`, `variables` and `callStack` change.

### Components

| File | Responsibility |
|------|----------------|
| `lib/services/base_debugger.dart` | Abstract contract + shared helpers. |
| `lib/services/debugger_factory.dart` | Language dispatch; reuses instances. |
| `lib/services/debugger_manager.dart` | Follows the active tab; stops on language change. |
| `lib/services/debugger_snapshot.dart` | Shared stop-payload JSON decoder. |
| `lib/services/debugger_environment.dart` | Test seam for real-process gating. |
| `lib/services/dart_debugger.dart` | Dart engine (VM Service). |
| `lib/services/python_debugger.dart` | Python engine (`sys.settrace`). |
| `lib/services/c_debugger.dart` | C/C++ engine (`clang` + `lldb`). |
| `lib/utils/vm_service_client.dart` | Minimal JSON-RPC 2.0 VM Service client. |

---

## 2. The `BaseDebugger` contract

Every engine implements the same surface.

**Observable state**

| Member | Type | Meaning |
|--------|------|---------|
| `state` | `DebugState` | `inactive` / `running` / `paused` / `stopped` (see `lib/models/debugger_models.dart`). |
| `currentPausedLine` | `int?` | 1-based line the program is paused on, or `null`. |
| `breakpoints` | collection of `Breakpoint` | User gutter breakpoints, per file. |
| `variables` | list | Variables at the paused frame. |
| `callStack` | list | Frames from the paused point outward. |
| `output` | `Stream<String>` | Broadcast log of debugger activity. |

**Abstract methods**

```dart
Future<void> startDebugging(String filePath, {String? content});
Future<void> stopDebugging();
Future<void> stepOver();
Future<void> stepInto();
Future<void> stepOut();
Future<void> continueExecution();
```

**Shared helpers**

- `@protected void emitOutput(String line)` — pushes a line to the `output`
  stream. The emit path drops writes after `dispose()`, so late events from a
  torn-down process can never throw "used after dispose".
- `void clearBreakpointsForFile(String filePath)` — removes breakpoints for one
  file only (used when a tab closes), leaving other files untouched.

---

## 3. Dispatch: `DebuggerFactory` and `DebuggerManager`

`DebuggerFactory` maps a `LanguageConfig` to a concrete debugger by extension:

| Extension(s) | Debugger |
|--------------|----------|
| `.py` | `PythonDebugger` |
| `.c`, `.cpp`, `.cc`, `.cxx` | `CDebugger` |
| `.s` | `AsmDebugger` (ARM64 Assembly) |
| anything else (default) | `DartDebugger` |

Instances are created **once and reused**. This is what lets breakpoints survive
switching between tabs and between languages: the breakpoint set lives on the
debugger instance, not on the document.

`DebuggerManager` watches the active tab and:

- activates the debugger for the language of the newly active file,
- **stops a *running* session** when the language moves away,
- **never clears breakpoints** as a side effect of that switch.

---

## 4. The shared stop payload: `DebugSnapshot`

Python and C/C++ both report a stop by printing a single JSON line to their
driver's stdout, and both are decoded by `DebugSnapshot.tryParse` — one contract,
two producers.

```json
{
  "file": "/path/to/program.py",
  "line": 12,
  "reason": "breakpoint",
  "vars": [
    { "name": "count", "value": "3", "type": "int" }
  ],
  "stack": [
    { "name": "main", "file": "/path/to/program.py", "line": 12 }
  ]
}
```

| Field | Notes |
|-------|-------|
| `file` | Absolute path the stop belongs to. |
| `line` | 1-based line within `file`. |
| `reason` | Free-form reason (e.g. `breakpoint`, `step`, `entry`). |
| `vars` | Locals at the paused frame (`name` / `value` / `type`). |
| `stack` | Call stack, innermost frame first (`name` / `file` / `line`). |

`DartDebugger` does **not** use this payload — it receives structured events
directly from the VM Service.

---

## 5. Dart: the VM Service engine

`DartDebugger` is a real debugger: it launches a Dart VM with the VM Service
enabled and speaks the Dart VM Service protocol.

### Launch

```text
dart --enable-vm-service=0 --disable-service-auth-codes
     --pause-isolates-on-start --enable-asserts <script.dart>
```

`--pause-isolates-on-start` is why the session does not run away before
breakpoints are installed.

### Startup sequence

1. Parse the `The Dart VM service is listening on http://127.0.0.1:PORT/…` line
   from stdout to get the service URI.
2. Open a WebSocket to the VM Service and call `getVM`.
3. **Await the isolate `rootLib`.** `_awaitIsolateReady` polls `getIsolate`
   until `rootLib` exists — until the root library is loaded there is no script
   to set a breakpoint in, and racing here is the classic cause of "Debug does
   nothing".
4. Resolve the entry script:
   `getIsolate(rootLib)` → root library's `scripts` → match the script whose
   URI ends with the launched filename → `getObject(scriptId)` → read `source`.
5. Locate the line of `main` (`findMainLine`) and install the entry breakpoint
   with `addBreakpointWithScriptUri(uri, mainLine)`.
6. `resume`. Execution stops on the breakpoint inside **your** `main`.

### Gutter breakpoints

Gutter breakpoints are mirrored to the VM with `addBreakpointWithScriptUri`.
When a line has no executable code the VM returns an error; the debugger keeps
the user's intent locally and re-applies it if the line becomes executable, so
toggling a breakpoint on a blank line is harmless.

The **entry breakpoint id** is tracked separately from the user's breakpoints.
Because of that, editing the gutter during a session can never delete the
breakpoint that keeps the program paused in `main`.

### Events

`DartDebugger` subscribes to the VM Service `streamNotify` notifications and
reacts to these pause kinds:

| Event | Handling |
|-------|----------|
| `PauseBreakpoint` | Real breakpoint hit → publish the pause. |
| `PauseInterrupted` | Pause from "pause" / step. |
| `PauseException` | Unhandled exception → publish. |
| `PausePostRequest` | Internal; not surfaced as a user pause. |
| `PauseExit` | Program exited. |
| `IsolateExit` | Isolate gone → teardown. |
| `Resume` | Execution resumed → clear `currentPausedLine`. |

On a pause the debugger calls `getStack` to fill `callStack`, then reads the
locals of the top frame to fill `variables`.

> **Only real user frames are published.** A pause whose top frame lives in
> `dart:isolate-patch` / VM internals (which happens before `main`) is ignored,
> so the `▶` marker never points into SDK internals.

### Transport: `VmServiceClient`

`lib/utils/vm_service_client.dart` is a deliberately small JSON-RPC 2.0 client:

- converts the HTTP service URI to `ws://…/ws` (and `wss://…/ws` for `https`),
- correlates requests and responses by `id`,
- surfaces `streamNotify` events to a callback,
- defaults to a 15-second call timeout so a dead VM fails fast instead of
  hanging the UI.

No package was added for this — `dart:io`'s `WebSocket` is enough.

---

## 6. Python: the tracer engine

`PythonDebugger` runs `python3` on a generated driver that installs a tracer and
reports pauses as marker lines. It does not need `debugpy` or any third-party
package.

- **Stop marker:** `@@BORLAND_PAUSED <json>` — one line, decoded by
  `DebugSnapshot.tryParse`.
- **IDE → driver commands** (written to the driver's stdin):

  | Command | Meaning |
  |---------|---------|
  | `BPS <csv>` | Replace the set of active breakpoint lines. |
  | `CONT` | Continue to the next breakpoint. |
  | `STEP` | Step into. |
  | `OUT` | Step out. |
  | `QUIT` | Terminate the session. |

Entry strategy: the tracer stops on the first line of the user's script, so the
first Debug always lands in the user's code.

---

## 7. C/C++: the lldb engine

`CDebugger` compiles and drives a native debugger.

### Compile

```text
clang  -g -O0 <source> -o <out>     # C
clang++ -g -O0 <source> -o <out>    # C++
```

`-g` preserves debug info and `-O0` keeps the mapping from source lines to
instructions honest.

### lldb driver and the injected helper

The debugger writes a helper module, `borland_lldb.py`, into the working
directory and injects it into `lldb` over stdio. The helper registers
`borland_snapshot`, and a stop-hook runs it on every stop:

```text
command script import borland_lldb.py
target stop-hook add -o borland_snapshot
```

The helper walks the frames and prints a single line:

```text
@@BORLAND_SNAP <json>
```

…which is the same `DebugSnapshot` payload Python emits, so one decoder serves
both engines.

### Entry breakpoint and the `0xFFFFFFFF` trap

The entry breakpoint is `breakpoint set --name main`. Before `main` executes,
there is a stop at `_dyld_start` whose line number is
**`0xFFFFFFFF` (`LLDB_INVALID_LINE_NUMBER`)**. `CDebugger` rejects that value
(and any empty file), filters out frames without a usable location, and only
then publishes a pause — otherwise the first stop would report a nonsense line.

### Requirements

`clang`, `clang++` and `lldb` must be on `PATH` (they ship with the Xcode
Command Line Tools). If compilation or the debugger binary is missing,
`CDebugger` reports it through `output` rather than failing silently.

---

## 8. ARM64 Assembly: the instruction engine

`AsmDebugger` (`lib/services/asm_debugger.dart`) subclasses `CDebugger` and reuses
its lldb process handling, breakpoint resync and output plumbing — only the
things that differ are overridden.

### Compile

```bash
clang -g -arch arm64 -o <temp>/program <temp>/program.s
```

`.s` sources are first written to a temp copy, so an unsaved buffer debugs the
same way a saved file does. On a non-arm64 host the debugger refuses up front
with `[ARM64 Assembly requires Apple Silicon macOS and clang/lldb.]` instead of
producing a binary it cannot debug.

### Register + disassembly stop-hook

Where `CDebugger` reports variables, `AsmDebugger` writes its own helper
(`borland_lldb_asm.py`) that is imported and hooked exactly like the C/C++ one:

```
command script import "<temp>/borland_lldb_asm.py"
command script add -f borland_lldb_asm.borland_snapshot borland_snapshot
target stop-hook add -o borland_snapshot
breakpoint set --name main
run
```

Exactly one entry breakpoint: lldb already knows the symbol as `main`, so a
second `--name _main` breakpoint could only answer `no locations (pending)` plus
a warning.

At every stop it prints one `@@BORLAND_SNAP {json}` line containing:

- `vars` — the register file as Variables with `type: "register"`:
  `x0`..`x28`, `fp`, `lr`, `sp`, `pc`, `cpsr` (read from `frame.GetRegisters()`);
- `disasm` — one line built from `target.ReadInstructions(frame.GetPCAddress(), 1)`,
  formatted `pc=0x<addr>  <mnemonic> <operands>`, emitted to the Console before the
  pause banner;
- `file` / `line` / `reason` / `stack` — the same keys the shared
  `DebugSnapshot` decoder already understands.

Because the register names arrive as ordinary Variables, the Variables panel
needs no special case: it renders `x19 (register): 0x000000000000000f` on its own.

### Stepping

| UI action | lldb command |
|---|---|
| Step Into | `thread step-inst` |
| Step Over | `thread step-inst-over` |
| Step Out | `thread step-out` |

### Source lines without a DWARF line table

`clang` cannot emit a line table for a hand-written `.s` file, so LLDB has no
source lines for it and `breakpoint set --line` never resolves. `AsmDebugger`
supplies the mapping itself:

1. **`Arm64AsmParser`** walks the source and gives every instruction a 4-byte
   offset **relative to the entry symbol** (`_main:`/`main:`), so a helper
   assembled *before* `_main` gets a **negative** offset. Only the `__text`
   section counts — `.section __TEXT,__cstring,…` is data, even though its
   *segment* is also called `__TEXT`.
2. **The entry stop supplies the base.** Every session first stops in the
   dynamic loader (`_dyld_start`, `signal SIGSTOP`); that snapshot is ignored.
   The first stop whose frame is `main` sets `base = pc`.
3. **Gutter breakpoints** are then installed as absolute addresses:
   `breakpoint set -a <base + offset>`. `-a` is used instead of `-R` because
   `-R` takes an *unsigned* slide — `-n main -R -20` silently becomes
   `0x2000004bc` and never resolves.
4. **A stop maps back** with `line = offsetToLine(pc - base)`, which is why the
   `▶` lands on the executed instruction, including inside `sum_loop`.

A bare label (`loop:`) maps to the instruction that follows it, and a
comment/blank line snaps forward up to 10 lines, so clicking almost anywhere in
the gutter does something sensible.

### Requirements

Apple Silicon (arm64) macOS with `clang` and `lldb` on `PATH`. Stops whose `pc`
falls outside the assembled unit (stepping into `printf`, a signal, the process
epilogue) keep the arrow on the entry line instead of guessing.

---

## 9. Console output bridge

Debug sessions are never silent. Each debugger writes lifecycle and event
messages through `emitOutput`. `IDEShell` subscribes to every debugger's `output`
stream and forwards each line to `LanguageRunnerService.emitOutput` — the same
stream `ConsolePanel` already listens to. That means banners like "compiling…",
"paused at …", and exit codes appear interleaved with the program's own output.

An engine whose `emitOutput` is not wired to the console looks broken even when
it works, so this bridge is the first thing to check when a session seems dead.

---

## 10. Testing strategy

The suite runs **fully offline**. It never launches `dart`, `python`, `clang` or
`lldb`.

### The gate: `DebuggerEnvironment`

```text
shouldShortCircuit == !allowRealProcesses && FLUTTER_TEST is set
```

- Under a plain `flutter test`, `FLUTTER_TEST` is set and `allowRealProcesses`
  is `false`, so every debugger returns early instead of spawning a process.
- `allowRealProcesses` is `true` only when **`BORLAND_REAL_VM_TEST=1`** (Dart)
  or **`BORLAND_REAL_ASM_TEST=1`** (ARM64 Assembly) is present.

This keeps CI deterministic and headless-safe.

### Commands

```bash
flutter analyze                 # must report "No issues found!"
flutter test                    # 310 tests; 2 opt-in integration tests skipped

# Opt-in: really spawn a Dart VM and attach over a real WebSocket
BORLAND_REAL_VM_TEST=1 flutter test test/integration/dart_vm_pause_test.dart

# Opt-in: really compile + lldb samples/array_sum_arm64.s
BORLAND_REAL_ASM_TEST=1 flutter test test/integration/arm64_asm_breakpoint_test.dart
```

### What the tests cover

| Test | Focus |
|------|-------|
| `dart_debugger_test` | Startup, `main` breakpoint resolution, pause events. |
| `python_debugger_test` | `@@BORLAND_PAUSED` parsing, command emission. |
| `c_debugger_test` | `@@BORLAND_SNAP` parsing, `0xFFFFFFFF` rejection, `main` breakpoint. |
| `debugger_factory_test` | Extension → debugger mapping and instance reuse. |
| `vm_service_client_test` | JSON-RPC correlation, URI→WebSocket conversion, timeouts. |
| `console_panel_test` | Output rendering. |
| `debugger_gutter_test` | Gutter row alignment with the editor. |
| `debugger_language_switch_test` | `DebuggerManager` tab/language switching. |
| `debugger_arrow_all_languages_test` | The `▶` marker shows for every language. |
| `arm64_asm_parser_test` | Line ⇄ offset mapping, labels, comments, data sections. |
| `arm64_asm_map_test` | Offsets relative to `_main` (negative before it), `__cstring` vs `__text`. |
| `asm_debugger_test` | Snapshot parsing, registers, address→line mapping. |
| `asm_debugger_transcript_test` | Replayed real lldb transcript: entry stop, breakpoint hit, restart, noise. |
| `editor_font_settings_test` | Font id persistence, notify-on-change, retired/unknown id → Menlo. |
| `editor_font_metrics_test` | Family plumbing, forced strut, canonical factor, equality. |
| `editor_font_gutter_test` | Gutter/code alignment for both fonts × sizes 8/13/32, `▶`, cache invalidation. |
| `editor_font_fallback_drift_test` | **Authoritative** row-height check on a real `EditableText`: 1000 lines, ASCII/Persian/mixed, wrapped docs. |
| `editor_click_line_test` | Click → selected line, reported `Ln/Col`, band top and gutter number must all agree (wrapped, Persian). |
| `view_menu_font_test` / `font_menu_live_check_test` | `View > Font` rows, live check mark (choose → reopen, no rebuild), theme switch. |
| `test/integration/dart_vm_pause_test.dart` | End-to-end real VM attach (opt-in). |
| `test/integration/arm64_asm_breakpoint_test.dart` | Real `clang`+`lldb`: breakpoint on `add x2, x2, x3` hits 5× with `x2=0,10,30,60,100` (opt-in). |

### Manual probe scripts (`tool/`)

- `tool/probe_real_pipeline.dart` — drives the real compile/run pipeline.
- `tool/probe_lsp_completion.dart` — inspects LSP completion responses.
- `tool/verify_completion_filter.dart` — checks completion filtering/ranking.
- `tool/verify_ux_fixes.dart` — regression checks for the UX fixes.
- `tool/probe_click_line.dart` — clicks a row of a generated wrapped document with a synthetic pointer in
  the running app and prints the selected line, the bold gutter number and the caret rows (the instrument
  for "the click selected the wrong line").
- `tool/probe_font_drift.dart` — **run it in the real app**, not under `flutter test`:
  `flutter run -d macos -t tool/probe_font_drift.dart`. It prints a painter table
  (diagnostic only) and then a widget-phase table that measures caret rects of a
  real `TextField` for every font × size × text kind over 1000 lines, one
  `OK` / `WRAP` / `DRIFT` line each. `flutter_tester` cannot answer font
  questions at all: it has no system fonts and no CoreText.

---

## 11. Gutter and editor alignment

The breakpoint gutter and the editor text must share one line height, or the
`●` / `▶` markers, the current-line band and click-to-line mapping all drift
away from their lines.

- `editor_metrics.dart` derives **one** number per size:
  `lineHeight = (fontSize * 19 / 13).roundToDouble()` and
  `lineHeightFactor = lineHeight / fontSize`. At the default 13 px that is
  **19.0 / 1.4615** — not the old `1.45`/`18.85`, which rounded to 19 in the
  renderer and drifted 0.15 px per line (TASK-019).
- The gutter's `itemExtent`, the band, the scroll math and the hit-testing all
  use that same `lineHeight` — never a hardcoded `19.0`.
- **The gutter's row model comes from the renderer, never from a prediction.**
  `_rowsFromRenderer()` takes the row *count* from the caret travel
  (`caret(last).top - caret(first).top) / lineHeight + 1`) and places each
  logical line at the row its caret occupies, adding `0` for continuation rows
  produced by wrapping. `_predictedGutterRows()` (character advance × length,
  then a `TextPainter`) is only a one-frame stopgap while the first layout is
  pending — it used to be the real model, and it broke as soon as the editor
  wrapped: a Persian line is set in the fallback font, where a glyph is wider
  than the measured monospace advance, so a line counted as one row rendered as
  two, every number below it sat one row high, and the wrapped row had no number.
  Locked by `test/ui/editor/editor_wrapped_gutter_test.dart` (both fonts, 520px
  and 400px editors that provably wrap).
- **That measurement must never give up silently.** `_runGutterRowsRebuild()` runs one post-frame attempt and
  **retries** (bounded, with `ensureVisualUpdate()`) while the editable is absent or still
  `debugNeedsLayout`; returning without rescheduling froze the predicted rows on the first frame after the app
  opened with a large pasted, wrapping document, and only a window resize corrected the numbers.
  `_rowsFromRenderer()` also returns empty when it measures *fewer* rows than the document has logical lines -
  a line can never occupy less than one row, so that is a stale layout, not an answer.
- **Gutter digits must sit on the code's baseline, not merely inside the row.**
  The number is an 11 px font in a `lineHeight`-tall row while the code is the
  editor size with a forced strut, so the digit's baseline is set by
  `height: lineHeight / lineNumberFontSize` **plus** an explicit
  `TextHeightBehavior(leadingDistribution: proportional)`. Leaving the leading
  to the ambient editor theme (`even`) lifts the digit above the code, and the
  gap grows with the font size — the user-visible "numbers are not level with
  the code", worst with Recursive. Do **not** use
  `RenderEditable.computeDistanceToActualBaseline` as the reference: under a
  forced strut it reports ~1 px less than where the glyphs are painted, which is
  why the old baseline assertion stayed green while the screen disagreed.
  Reference geometry for both: baseline = `ascentRatio × lineHeight`. Locked by
  `test/ui/editor/editor_gutter_baseline_test.dart` (both fonts × 8/13/32).
- The strut is **forced for every font** (`forceStrutHeight: true`) at that same
  factor. Unforced, a line whose glyphs come from the fallback font (e.g. a
  Persian string literal) is taller than `lineHeight`, and over ~400 lines the
  code visibly separates from the numbers.
- **Do not "calibrate" the strut factor per font.** `TextPainter.height` floors
  the strut's ascent and descent halves and can report a row 1–3 px shorter than
  `lineHeight`, while the editor's `RenderEditable` rounds `fontSize * height`
  and renders it exactly. Tuning for the painter once produced 20 px rows at
  size 13 — the very drift it meant to cure. Assert on a real `EditableText`
  (`editor_font_fallback_drift_test.dart`), and confirm in the running app with
  `flutter run -d macos -t tool/probe_font_drift.dart`, which prints
  `OK`/`WRAP`/`DRIFT` for every font × size × text kind over 1000 lines.
- `_charAdvance` and `_gutterRows` are cached by **both** size and font family,
  so switching fonts cannot leave a stale advance behind.
- Markers: `'▶'` marks the current paused line and is shown when
  `debugger.currentPausedLine == lineNumber && debugger.state != DebugState.inactive`;
  `'●'` marks a breakpoint. A line can be both paused and a breakpoint, so the
  two markers are drawn so that one never hides the other.
- **Continuation rows (`rows[i] == 0`) must be inert.** They have no number, so they must not show a
  bullet, never match `currentPausedLine`, and never toggle a breakpoint — each of those used to happen for
  line `0` because the row was built from `lineNumber` without checking it. The guard lives in three places
  (`hasBp`, `isPausedLine`, the row's `onTap`) plus `_toggleBreakpoint` itself.
- **Popup anchors come from the caret, not from the mouse.** `_requestHover()` recomputes
  `_cursorScreenOffset` from the caret; `MouseRegion.onHover` must not pre-set it (it used to add a magic
  `+24px`, which left the tooltip anchored below the pointer whenever the hover found nothing).
- **The current-line band covers every row of the logical line.** `_bandRectForCaret()` returns
  `(top, height)`: `top` is the grid row (see below) and `height` is
  `(caret(first character after the newline) - caret(line start)) / lineHeight` rows, so a wrapped line is
  highlighted as a whole instead of only its first segment. Mind the offset: the `\n` itself belongs to the
  line's **last** visual row, so the end of the line must be measured at `newline + 1`.
- **The current-line band snaps to the row grid, using the renderer for the row.**
  `_bandTopForCaret()` takes the *row* from the caret rects
  (`(caret(lineStart).top - caret(0).top) / lineHeight`, so a stale row cache can never move it) and then
  positions the band at `row * lineHeight`, **not** at the caret rect's own `top`: Flutter inflates the caret
  rect ~1px above its line box, so a band built from `caretRect.top` sat one pixel higher than the gutter
  numbers of the very same row ("the selected line is 1px above the numbers"; measured
  `numberRow - caretRow = +1` at 8/13/32 for both fonts, while the grid is exact). `_queueBandUpdate()`
  repeats the measurement in a post-frame callback because the field may scroll to reveal the caret *after*
  `build`. Do not go back to `_visualRowForLine(rows, _caretLine) * lineHeight`: a row cache that lags the text
  (an edit, a paste, a resize) moved the band a few rows above the caret while every number still looked
  aligned, which read as "I clicked line 400 and line 396 got selected". The invariant is locked by
  `test/ui/editor/editor_click_line_test.dart` (click line → selection, reported `Ln/Col`, band top and
  gutter number must all agree) and measured in the running app with
  `flutter run -d macos -t tool/probe_click_line.dart`, which clicks a row through a synthetic pointer and
  prints the resulting line, the bold gutter number and the caret rows.
- **Gutter digits sit on the code's baseline, not merely in its row.** The number is an 11px font in a
  `lineHeight`-tall row while the code is 13px with a forced strut, so its baseline is set by
  `height: lineHeight / lineNumberFontSize` **plus** an explicit
  `TextHeightBehavior(leadingDistribution: proportional)`. Leaving the leading to the ambient editor theme
  (`even`) lifts the digit above the code, and the gap grows with the font size - the user-visible "numbers
  are not level with the code", worst with Recursive. Do not trust
  `RenderEditable.computeDistanceToActualBaseline` as the reference: under a forced strut it reports ~1px less
  than where the glyphs are painted (that is why the old baseline test passed while the screen disagreed).
  Reference geometry: baseline = `ascentRatio × lineHeight` for both. Locked by
  `test/ui/editor/editor_gutter_baseline_test.dart` (both fonts × 8/13/32).
- The status bar's `Ln n, Col m` comes from `CodeEditorPanel.onCaretChanged` → `IDEShell` →
  `RetroStatusBar.positionText`; it is not a placeholder.
- The paused line is tinted with `ThemeService.colors.pausedLine`.

---

## 12. Known limitations

### ARM64 Assembly

Line breakpoints work, but they are computed by us rather than by DWARF (see
section 8), which leaves a few honest gaps:

- **Instructions are assumed to be 4 bytes** and `.p2align`/`.align` padding is
  not modelled. Hand-written samples only align to 4 or 8 bytes, which never
  inserts padding between two consecutive instructions, but a hand-mixed
  `.p2align 4` in the middle of a function would shift every following line by
  the padding size.
- **Only the `__text` section is mapped.** Instructions emitted into another
  section would not be reachable by a gutter breakpoint.
- **Macros are invisible.** A `.macro` body is one source line but several
  instructions.
- **The base address comes from the entry stop**, so gutter breakpoints are
  installed after `run` pauses at `main`. They are in place before the user
  continues, so the first Continue already honours them; there is no way to
  break *inside* the dynamic loader before `main`.
- **Stops outside the assembled unit** (stepping into `printf`, a signal, the
  process epilogue) keep the arrow on the entry line.

- **C/C++ requires a native toolchain.** `clang`/`clang++`/`lldb` must be on
  `PATH`; without the Xcode Command Line Tools the engine cannot start.
- **Python needs `python3` on `PATH`** and is a tracer, not a full debugger: it
  stops on lines it is told about, so it is a breakpoint/step debugger rather
  than an attach-to-running-process debugger.
- **Dart is the most complete engine.** Python and C/C++ expose
  variables/call-stack through the shared snapshot contract; advanced features
  (conditional breakpoints, watch expressions evaluated by the language runtime,
  data breakpoints) are not implemented.
- **Only macOS is supported.** The app targets Flutter Desktop on macOS.
- **The macOS App Sandbox is disabled** (`com.apple.security.app-sandbox =
  false`) because every engine spawns a child process.
- **`DebugSnapshot` is line-oriented.** A driver must print the whole JSON on a
  single line; multi-line output will not be parsed.
