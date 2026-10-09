# DEBUGGING.md — Multi-Language Debugging

This document explains how the borland_dart (RetroDart IDE) debugger works: the
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

## 8. Console output bridge

Debug sessions are never silent. Each debugger writes lifecycle and event
messages through `emitOutput`. `IDEShell` subscribes to every debugger's `output`
stream and forwards each line to `LanguageRunnerService.emitOutput` — the same
stream `ConsolePanel` already listens to. That means banners like "compiling…",
"paused at …", and exit codes appear interleaved with the program's own output.

An engine whose `emitOutput` is not wired to the console looks broken even when
it works, so this bridge is the first thing to check when a session seems dead.

---

## 9. Testing strategy

The suite runs **fully offline**. It never launches `dart`, `python`, `clang` or
`lldb`.

### The gate: `DebuggerEnvironment`

```text
shouldShortCircuit == !allowRealProcesses && FLUTTER_TEST is set
```

- Under a plain `flutter test`, `FLUTTER_TEST` is set and `allowRealProcesses`
  is `false`, so every debugger returns early instead of spawning a process.
- `allowRealProcesses` is `true` only when the environment variable
  **`BORLAND_REAL_VM_TEST=1`** is present.

This keeps CI deterministic and headless-safe.

### Commands

```bash
flutter analyze                 # must report "No issues found!"
flutter test                    # 106 tests; 1 opt-in integration test skipped

# Opt-in: really spawn a Dart VM and attach over a real WebSocket
BORLAND_REAL_VM_TEST=1 flutter test test/integration/dart_vm_pause_test.dart
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
| `test/integration/dart_vm_pause_test.dart` | End-to-end real VM attach (opt-in). |

### Manual probe scripts (`tool/`)

- `tool/probe_real_pipeline.dart` — drives the real compile/run pipeline.
- `tool/probe_lsp_completion.dart` — inspects LSP completion responses.
- `tool/verify_completion_filter.dart` — checks completion filtering/ranking.
- `tool/verify_ux_fixes.dart` — regression checks for the UX fixes.

---

## 10. Gutter and editor alignment

The breakpoint gutter and the editor text must share one line height, or the
`●` / `▶` markers drift away from their lines as you scroll.

- `code_editor_panel.dart` defines `editorFontSize = 13.0` and
  `editorLineHeightFactor = 1.45`, giving `editorLineHeight = 18.85`.
- Both the editor rows and the gutter rows use that same value — never a
  hardcoded `19.0`.
- Markers: `'▶'` marks the current paused line and is shown when
  `debugger.currentPausedLine == lineNumber && debugger.state != DebugState.inactive`;
  `'●'` marks a breakpoint. A line can be both paused and a breakpoint, so the
  two markers are drawn so that one never hides the other.
- The paused line is tinted with `ThemeService.colors.pausedLine`.

---

## 11. Known limitations

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
