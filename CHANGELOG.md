# Changelog

All notable changes to Classic Code Editor are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.4.1] — 2026-10-25

### Added
- **Language servers for C/C++ and Python.** The LSP layer no longer hard-codes `dart language-server`.
  `LspServerSpec` declares each server (binary candidates, arguments, language ids, install hint) and
  `LspServerManager` keeps **one warm instance per language**, swapping with the active tab instead of
  restarting a process on every switch: `clangd` for `.c`/`.cpp`, `pyright` then `pylsp` for `.py`, the Dart
  server for `.dart`. Nothing is installed automatically — a missing server prints its install hint to the
  Console **once** (`xcode-select --install`, `npm install -g pyright`, `python3 -m pip install
  python-lsp-server`) and the editor falls back to offline completion; ARM64 Assembly gets no server at all
  (`Off`). Apple's clangd is launched without `--stdio` (it rejects the flag), pyright with it.
  Tests: `lsp_server_spec_test`, `lsp_server_manager_test` (reuse, fallback order, one-time hint),
  opt-in `clangd_presence_test` (real `initialize` handshake, 8 ms on this Mac).
- **`compile_flags.txt` is generated for clangd** on the first C/C++ file, with a comment header and
  `-isysroot $(xcrun --show-sdk-path)`, so clangd sees the macOS SDK headers instead of reporting
  `'stdio.h' file not found`. An existing file is never overwritten. Tests: `compile_flags_test`.
- **Completion warm-up retry.** An empty completion is retried once after 200 ms, because the first request
  after `initialized` lands while clangd/pyright are still indexing. Tests: `lsp_service_test`.
- The status bar's LSP segment now has a tooltip naming the active server and the reason it is not running.
- **`View > Syntax Colors` with two palettes: Standard (the classic colors, default) and Colorful (11
  high-contrast colors). The choice applies live in all four themes for every language and is remembered in
  `editor_settings.json` (`syntaxScheme: "standard" | "colorful"`, unknown values fall back to Standard).

### Fixed
- **Python syntax highlighting was black in the editor.** Three separate gaps: the shell hands the panel a
  bare `CodeController()` (no language), and `CodeEditorPanel.initState` never applied one — so a file open
  when the panel mounted rendered every token in the default text color; unsaved tabs called `Untitled` had no
  extension, so `LanguageConfig` fell back to the Dart grammar; and the Python grammar's own gaps left
  `print`/`exec` (a bare rule without `className`) and f-string `{...}` interpolations (`subst` class, absent
  from the style map) black. The editor now applies the grammar on mount, resolves the language with shared
  extension→content sniffing (`LanguageConfig.fromPathOrContent`, also used by Run/Debug), styles `subst` from
  the existing string color and colors Python builtins through a rule added before the bare one. Tests:
  `python_syntax_colors_test` (real `SpanBuilder` path, one case per theme).
- **Parentheses in C++ and Python signatures were not the bracket color.** The bundled grammars give a
  parameter list its own `params` mode that owns its `(` and `)`, so those two characters were painted in the
  params color while every other bracket was blue; patching such a mode with a bracket rule made it worse,
  because a `contains` rule wins over the mode's `end` and the mode then never closed (in C++ that swallowed
  the rest of the file and made call parentheses switch colors mid-line). The paren-owning modes are removed
  and their inner rules kept, so the shared bracket rule colors every parenthesis; the rules added to a mode
  now never contain its own end character.
- **ARM64 Assembly labels and separators were mis-colored.** Labels (`msg:`, `_main:`) were tagged `symbol`, which the
  palette resolves to the operator green — they read like operators — and while `,` / `[` / `]` / `!` stayed in the
  default text color. Labels now use the shared label/function color (`title`), and commas, writebacks and brackets
  pick up the operator / bracket colors already used by the other languages.
- **The first file opened during server startup could never reach the language server.** `startServer` is now
  a shared future, so `openFile` waits for the handshake instead of returning while the status was still
  `starting` (the document was silently dropped until the next keystroke).
- **The static-analysis fallback ran `dart analyze` on C and Python files.** It is now limited to Dart; other
  languages rely on offline completion and the Console hint instead.

## [1.4.0] — 2026-10-21

### Fixed
- **A gutter breakpoint in C/C++/assembly could be silently lost, and stopping a session could leave the program
  running.** lldb's stdin is a pipe, so a command written while lldb was still printing a stop report arrived
  split (`breakpoint set -a 0x…` reached lldb as `b` + `reakpoint set -a 0x…`), the breakpoint was never
  installed and the program ran to completion; separately, SIGKILLing lldb alone left `borland_*_exec` alive.
  All stdin now goes through one queue (`LldbCommandQueue`): one command in flight, gated on a 40 ms quiet
  window, verified with a `script print("@@ACK n")` sentinel, and retried once - idempotently, because a
  resync deletes the ids it owns first - when the ack is lost. Continue/Step jump the queue. Stop closes the
  queue, then sends `process kill` + `quit`, waits 2 s, SIGKILLs lldb and finally the inferior pid.
  Tests: `lldb_command_queue_test` (fake-lldb transcripts) and the opt-in
  `lldb_session_lifecycle_test` (C, C++ and stop-while-paused; asserts `pgrep` is empty afterwards).
- **The opt-in ARM64 entry-stop test could never pass.** Its gate (`BORLAND_REAL_ASM_TEST=1`) was not enough:
  every debugger short-circuits under `FLUTTER_TEST`, so `startDebugging` returned with `state == running`
  after one banner line and lldb was never started. It now sets `DebuggerEnvironment.allowRealProcesses`
  (restored in `tearDown`), polls for the pause instead of asserting immediately, and asserts the pausing
  line, `mainAddress`, `x0..x28`/`fp`/`lr`/`sp`/`pc`/`cpsr` and a `pc=0x` Console line.

### Changed
- **Monaco removed — `View > Font` now offers two faces: Menlo (default) and Recursive Mono Casual.**
  Monaco ships no real bold or italic (macOS synthesizes both), and its metrics made the row height follow
  the fallback font of a Persian glyph. `EditorFontFamily` lost the `monaco` value, the menu lost its row,
  and a settings file that still says `"fontFamily": "monaco"` resolves to `menlo` through `fromId`'s
  fallback - nobody is left without a font. All font tests, the probe and the docs were narrowed to two
  families; `editor_font_settings_test` gained the migration case.

### Added
- **Editor font choice (`View > Font`)** — **Menlo** (default, pixel-identical to before) or
  **Recursive Mono Casual**, with a check mark on the active one. The choice is persisted next to `fontSize`
  in `editor_settings.json` as a stable id (`menlo` | `recursive`); an unknown or corrupt value
  falls back to Menlo, and older files without the key keep working. It applies to the code **and** the
  gutter line numbers, while the rest of the UI stays on Arial: the glyph advance and the wrapped-row
  measurement are now keyed by **both** size and family, so switching fonts cannot leave the gutter
  carrying a stale cache (the TASK-019 drift). Ligatures are disabled for both.
- **Recursive Mono Casual is bundled** (`assets/fonts/`, four static faces + `OFL.txt`, ~1.5 MB) and
  declared in `pubspec.yaml` under the alias `RecursiveMonoCasual`, so the lookup never depends on a font
  installed on the host. New `THIRD_PARTY_NOTICES.md`; README gained a *Fonts and licensing* section.
- New tests: `editor_font_settings_test.dart`, `editor_font_metrics_test.dart`, `editor_font_gutter_test.dart`
  (both families × sizes 8/13/32, arrow marker, cache invalidation), `view_menu_font_test.dart`, and
  `editor_font_measure_test.dart`, which measures the **real** glyph advance and line height per family and
  documents the strut finding below.
- **ARM64 Assembly source-line debugging** — clicking the gutter of a hand-written `.s` file now sets a
  breakpoint that stops on exactly that line, anywhere in the file, including code assembled *before*
  `_main`. `Arm64AsmParser` maps every instruction to a 4-byte offset **relative to the entry symbol**
  (negative before it, because Apple's toolchain ships no DWARF line table for `.s`), and `AsmDebugger`
  installs the breakpoints with `breakpoint set -a <main + offset>` once the entry stop reveals the load
  address. The `▶` marker, the register file (`x0`..`x28`, `fp`, `lr`, `sp`, `pc`, `cpsr`) and one
  `pc=0x… <instruction>` Console line now appear at every stop, and Step Into/Step Over move both the
  arrow and the registers by one instruction.
- `samples/array_sum_arm64.s` — a helper function assembled before `_main`, `.data`/`__cstring` sections and
  a real `bl _printf`, used as the fixture for the mapping tests and for the opt-in lldb test.
- New tests: `arm64_asm_map_test.dart`, `asm_debugger_transcript_test.dart` (replayed real lldb transcript)
  and `test/integration/arm64_asm_breakpoint_test.dart` (opt-in, real `clang`+`lldb`).
- Turbo Pascal + ARM64 Assembly screenshots (`assets/screenshots/tp-editor|tp-debugger|tp-terminal.png`)
  in the README gallery, and refreshed architecture diagrams (SVG sources + PNG exports).

### Fixed
- **First open with a big pasted, wrapping document numbered the rows wrong until a resize.** The exact row
  model is measured from the renderer in a post-frame pass, and that pass used to **give up silently** when
  the editable was not measurable yet (absent, or still `debugNeedsLayout`) - which is exactly the first frame
  after the app opens with a large paste. The *predicted* rows then stayed in place, and only a resize threw
  them away and re-measured. The pass now retries (bounded, requesting a frame) until the renderer is
  measurable, and rejects a measurement that reports fewer rows than the document has logical lines (a line
  can never occupy less than one row) - the signature of a layout that still belongs to the previous text.
  Regression test: `editor_wrapped_gutter_test.dart` "a big paste at first open still numbers every row
  correctly".
- **A continuation row in the gutter created a breakpoint on line 0.** A wrapped line's second and later
  rows have no line number (`0`), but the gutter row was still tappable and called `setBreakpoint(path, 0)` —
  an entry every debugger rejects, and one that painted a bullet on a row that has no number. Continuation
  rows are now inert, and `_toggleBreakpoint` ignores non-positive lines. Regression test:
  `editor_wrapped_gutter_test.dart` (tap the continuation row → no breakpoint; tap the numbered row →
  breakpoint on that line).
- **The hover tooltip/autocomplete anchor was clobbered on mouse move.** `MouseRegion.onHover` overwrote
  `_cursorScreenOffset` with `event.position + 24px` before the (debounced) hover request ran, so a hover that
  found nothing left the popup anchored 24px below the pointer. The anchor now comes only from the caret.
- **A wrapped line was highlighted on its first row only.** The current-line band was a fixed `lineHeight`
  tall, so the second and third segments of a wrapped logical line stayed unhighlighted - unlike every
  desktop editor, where the whole line is marked. The band now spans every visual row of the caret's logical
  line (its height is `(caret(after the newline) - caret(line start)) / lineHeight` rows), and stays one row
  for a normal line. Locked by `editor_wrapped_gutter_test.dart` (wrapped line → two rows tall and starting on
  the gutter's number row; normal line → one row) and asserted per-click in `editor_click_line_test`.
- **The current-line band sat 1px above the line numbers.** The band was positioned at the caret rect's
  `top`; Flutter inflates that rect ~1px above its line box, so the highlight always started a pixel higher
  than the number of the same row (measured in the running app: `numberRow - caretRow = +1` for Menlo and
  Recursive at 8/13/32). The band now takes only the *row* from the renderer and draws at `row * lineHeight`,
  the same grid the gutter uses. Verified in the app with `tool/probe_baseline.dart`
  (`bandVsNumber = 0.0` for every font × size) and locked by `editor_click_line_test` (band top must equal the
  number row within 0.01px).
- **Wrapped rows broke the gutter.** Narrowing the editor made the numbers drift and the wrapped (second)
  row of a long line look unselectable. The gutter *predicted* how many rows a line occupies: a monospace
  character-count gate, then a `TextPainter` laid out at an assumed width. A prediction cannot be right - a
  Persian string is set in the fallback font, where a glyph is wider than the measured advance, and the
  painter's width is not the `TextField`'s width - so a line counted as one row rendered as two and every
  number below it sat a row too high. The rows now come from the **renderer**: the row count is the caret
  travel from the first to the last offset divided by `lineHeight`, and each logical line is placed at the row
  its caret actually occupies. The `TextPainter` path survives only as a one-frame stopgap while the first
  layout is still pending. Regression test: `editor_wrapped_gutter_test.dart` (both fonts, 520px and 400px
  editors that provably wrap: numbers on their own row, blank continuation rows, clicking a wrapped row
  selects its line).
- **Gutter numbers sat a pixel or two above the code** (worst with Recursive Mono Casual). The digits were
  laid out with the code's strut but with *their own* font size (11px), so their baseline depended on the
  `height`/leading that the editor theme leaks into the gutter: the theme's `TextHeightBehavior` distributed
  the leading evenly, which lifted the digit above the code's baseline, and the offset grew with the font
  size. The number now sets `height: lineHeight / lineNumberFontSize` and an explicit **proportional**
  `TextHeightBehavior`, so its baseline is `ascentRatio * lineHeight` - the same value the code's forced strut
  uses. Note for future readers: `RenderEditable.computeDistanceToActualBaseline` reports ~1px **less** than
  where a forced strut actually paints, which is how this stayed green in `gutter_alignment_test` while being
  visible on screen; that test now derives the reference from the strut geometry instead.
- **The current-line band could sit a few rows off the caret, and the status bar never showed the caret.**
  The band was positioned from `_caretLine` + the gutter's wrap-aware row cache, and that value was
  measured during `build` - before the field's own "scroll caret into view" (and, after an edit, before the
  new layout existed). The result was the reported "I click line 400, line 396 gets selected": the band (and
  the bold gutter number) were drawn a row per discrepancy above the caret while the numbers still looked
  aligned. The band is now positioned from **the renderer's caret rect** (`getLocalRectForCaret`), measured
  again in a post-frame pass so it uses the frame's final layout. The status bar's `Ln/Col` was never wired
  either - `RetroStatusBar.positionText` kept its `'Ln 1, Col 1'` default - so the editor now reports the
  caret through `CodeEditorPanel.onCaretChanged` and the shell passes `Ln n, Col m` to the status bar.
  Regression tests: `editor_click_line_test.dart` (click → selection, reported position, band top and gutter
  number must agree, in wrapped documents with Persian text; plus `goToLine` and an edit above the caret).
- **Monaco drifted away from the gutter in the real app — fixed by forcing the strut for every family.**
  The earlier Monaco "fix" (letting `height` alone set the row) was wrong: **without** `forceStrutHeight`
  the row is set by the font of whichever glyph is on the line, so a line containing Persian text fell back
  to another face and grew — Monaco's rows became 13/20/49px at sizes 8/13/32 instead of 12/19/47. Measured
  in the running macOS app on a 1000-line document: the caret of line 400 sat **399px** (8/13) and **799px**
  (32) below where the gutter had reserved space, i.e. ~4–8 rows of drift by line 400, plus wrong
  click-to-line hits and a current-line band in the wrong place. Every family now forces the strut at the
  plain `lineHeight / fontSize` factor, and the probe reports `d=0.0` for ASCII, Persian and mixed text at
  8/13/32 over 1000 lines. Menlo is untouched (same style, same factor, pixel-identical); Monaco was later
  removed entirely (see Changed).
  Note for future readers: `TextPainter.height` floors the strut halves, so a painter can report a forced
  row 1–3px short while the editor's `RenderEditable` rounds `fontSize × height` and renders it exactly.
  Calibrating the factor for that painter number is what made the editor render 20px rows at size 13.
- **`View > Font` kept its check mark on the previous font.** The rows were built in the menu bar's
  `build()` and captured by `itemBuilder`, and the bar listens only to `SessionService`, so choosing a font
  changed the editor but nothing rebuilt the bar: the next popup still showed the old row. The rows are now
  built **when the popup opens**, which fixes the theme rows on the same path. Regression test:
  `test/ui/shell/font_menu_live_check_test.dart` (choose → reopen → read the check, with no rebuild).
- **Verification tooling:** `tool/probe_font_drift.dart`
  (`flutter run -d macos -t tool/probe_font_drift.dart`) measures a real `TextField` in the running app for
  every family × size × text kind over 1000 lines and prints `OK`/`DRIFT` per case — the instrument that
  found both bugs, since `flutter_tester` has no CoreText and no system fonts.
- **ARM64 Assembly: the Variables panel and the `▶` marker came back empty.** The lldb stdout stream was
  wired to `CDebugger`'s private line handler, so `AsmDebugger`'s override never saw the `@@BORLAND_SNAP`
  payload and the C-shaped snapshot parser silently dropped it (no `file`, no `line`). The stream now goes
  through the virtual `handleStdoutLine`, and the loader's `_dyld_start` stop is ignored so the arrow never
  flashes onto line 1 before `main`.
- **ARM64 Assembly: breakpoints landed past the end of `main`.** Offsets were counted from the top of the
  file instead of from `_main`, and they were applied with `-R` (address slide), which also rejects a
  negative slide — `-n main -R -20` resolved to the unrelated address `0x2000004bc`. Offsets are now
  entry-relative and applied as absolute addresses with `-a`.
- **ARM64 Assembly: duplicate and pending breakpoints.** The second `breakpoint set --name _main` is gone
  (lldb knows the symbol as `main`), and a breakpoint plan is deduped by address before it is issued.
- **ARM64 Assembly: `error: No breakpoints exist to be deleted.` on every restart.** The ids of the
  previous lldb session survived teardown, so the next session tried to delete them. They are cleared when
  a session ends and when a new one starts, and only ids this session created are ever deleted.
- **ARM64 Assembly: the Console said `[C debugging stopped]`.** `CDebugger` now exposes an overridable
  `debuggerLabel`, so the engine announces itself as `ARM64 Assembly`.
- **ARM64 Assembly: `.section __TEXT,__cstring,…` was parsed as code** because its *segment* name contains
  `__TEXT`; the second comma-separated token now decides, so string literals no longer shift every offset.
- Gutter breakpoints added or removed during a session were not re-synced for the Assembly engine: the
  `setBreakpoint`/`removeBreakpoint` overrides called the private resync instead of the virtual one.
- Saving a **Dart** file spawned a second copy of the IDE instead of the formatter: `_formatCode`
  started `Platform.resolvedExecutable` (the app binary inside a packaged `.app`), which opened an
  empty black "Classic Code Editor" window and left the file unformatted. It now runs `dart format`
  from `PATH`, like `clang-format` and `black`.
- Save As no longer opens the extra un-themed panel window (`FileType.any`, panel deferred to the next
  frame).

### Added
- **Unsaved-changes guard** — closing a modified tab (the tab's ✕, `Cmd + W`, File > Close Tab) or
  quitting (`Cmd + Q`, the red window button, File > Exit) asks `Save changes to <name>?` with
  Save / Don't Save / Cancel. One shared helper (`lib/ui/shell/close_guard.dart`) drives all paths;
  a cancelled or failed Save As counts as Cancel; only the active window's cancel aborts quitting.
- **Edit menu + shortcuts** — Select All (`Cmd + A`), Go to Line (`Cmd + L`), Toggle Comment
  (`Cmd + /`), Duplicate Line (`Cmd + Shift + D`), plus `Cmd + O` (Open) and `Cmd + W` (Close Tab).
  Go to Line uses a retro number prompt, `EditorMetrics` line height and the wrap-aware visual row,
  and gives focus back to the editor. Toggle Comment reads the language's `commentPrefix`
  (`//` Dart/C/C++/ASM, `#` Python) and is a no-op for unknown languages.
- **Session restore + recent files** — new `SessionService` writes `session.json` (open paths, active
  path, 10 most recent files) in Application Support; tabs reopen on launch (missing files skipped,
  untitled buffers never restored) and the File menu shows a numbered MRU block with
  "Clear Recent Files".
- **Retro menu chrome** — `RetroMenuItem` / `RetroMenuSeparator` / `RetroPopupShape`: 22px rows,
  shortcut column sized from the real text, check mark on the active theme, etched separators,
  full-width `menuActive` highlight for both hover and keyboard focus.
- New tests: `retro_menu_bar_test.dart`, `unsaved_guard_test.dart`, `toggle_comment_test.dart`,
  `session_service_test.dart`. Suite: **230 tests** (1 opt-in skipped).

### Changed
- README/ARCHITECTURE/AGENTS/PRIVACY document the session file and the new editor commands.

## [1.3.0] — 2026-10-19

### Added
- **ARM64 Assembly (`.s`) support** — a fifth language, end to end:
  - `language_config.dart`: `.s` → *ARM64 Assembly*, `clang -g -arch arm64`, highlight language `armasm`.
  - `multi_language_highlighter.dart`: a purpose-built `arm64Asm` grammar (AArch64 registers
    `x0`..`x30` / `w0`..`w30` / `sp` / `fp` / `lr` / `pc` / `xzr` / `wzr` / `cpsr`, `//` and `/* */`
    comments, `.directives`, labels, `#immediates`) — `highlight` 0.7's own `armasm` mode targets
    32-bit ARM and has neither the 64-bit registers nor `//` comments. No new package.
  - `language_runner_service.dart`: Run assembles and executes `.s` sources, gated on
    Apple Silicon (`uname -m == arm64`).
  - `asm_debugger.dart` (new): `AsmDebugger extends CDebugger` — assembles with
    `clang -g -arch arm64`, installs a dedicated LLDB stop-hook that reports the register file
    (`x0`..`x28`, `fp`, `lr`, `sp`, `pc`, `cpsr`) as Variables and a one-instruction disassembly,
    and maps Step Into/Over/Out to `thread step-inst` / `thread step-inst-over` / `thread step-out`.
  - `debugger_factory.dart`: dispatch for `.s` (four debuggers now).
  - `assets/icons/asm.png` (new): blue heptagon `ASM` logo in the editor header, with a vector
    fallback painter; `panel_layout.dart` also detects `.s` and sniffs assembler directives.
  - `samples/hello_arm64.s` (new) — runnable sample that sums 1..5 and prints via `_puts`.
  - *ARM64 Assembly* added to the manual language dropdown.
- **Fourth theme: Turbo Pascal 7.0** — DOS navy desktop, gray 3D dialogs and cyan menu highlight;
  selectable from the View menu and the toolbar theme dropdown, persisted like the other three.
  The editor surface and syntax palette stay identical to the other themes by design.
- **Current-line highlight** — the caret's row is tinted full-width with a hairline outline, its
  gutter number is emphasised, and clicking the empty space past the end of a line selects that row.
- Tests: `asm_debugger_test.dart`, `highlighter_asm_test.dart`, `language_runner_asm_test.dart`,
  `editor_current_line_test.dart`, `language_logo_test.dart`, `integration/asm_debug_test.dart`
  (opt-in, `BORLAND_REAL_ASM_TEST=1`). Suite: **204 tests** (1 opt-in skipped).

### Changed
- **Gutter layout:** line numbers moved to the left of the gutter and 10px reserved on the right for
  the gutter's own scrollbar, so the numbers and the slider can no longer overlap.
- **Breakpoint bullet** is now a painted dot at `0.7 × lineHeight` — roughly twice the size of the
  old `●` glyph — while still fitting inside one row.
- **Debugger sidebar only opens while debugging**: `PanelLayout` shows it for a `running`/`paused`
  session instead of "any debugger that has breakpoints", and `PanelLayout` now listens to the
  active debugger so it opens/closes with the session.
- `EditorSettingsService` resolves its settings file once and writes synchronously afterwards;
  this removes an ordering race where a queued async save could land after the file was rewritten.
- `pubspec.yaml` version bumped to `1.3.0+5`.
- Documentation refreshed: `README.md`, `ARCHITECTURE.md`, `TASKS.md`, `docs/PHASE_DETAILS.md`,
  `docs/DEBUGGING.md`, `docs/RELEASE.md`, `docs/RETRO_DESIGN.md`.

## [1.2.0] — 2026-10-18

### Added
- Editor zoom service (`EditorSettingsService`) with persistence (`editor_settings.json`) via `path_provider`.
- `EditorMetrics` pure value class for font-size-driven line height, gutter width, marker sizes, and text/strut styles.
- Dynamic editor panel (`code_editor_panel.dart`) that reacts to font-size changes with cache invalidation.
- Gutter alignment regression tests across sizes {8, 13, 20, 32} (`gutter_alignment_test.dart`).
- Editor zoom interaction tests (`editor_zoom_test.dart`): breakpoint toggle, paused-line arrow, and zoom-while-paused.
- Keyboard zoom shortcuts (`Cmd +` / `Cmd -` / `Cmd 0`) wired through `app_shortcuts.dart` and `ide_shell.dart`.
- View-menu font-size items (`font_increase`, `font_decrease`, `font_reset`) in `retro_menu_bar.dart`.
- About-dialog shortcuts tab updated with zoom shortcuts (`retro_about_dialog.dart`).

### Changed
- Updated documentation (`README.md`, `ARCHITECTURE.md`, `TASKS.md`, `AGENTS.md`) for Phase 18 features.
- `pubspec.yaml` version bumped to `1.2.0+4`.

## [1.1.0] — 2026-10-14

### Fixed
- Fixed code editor gutter line numbers drifting out of alignment with rendered code lines on wrapped lines, long files, and narrow window widths:
  - Accounted for `letterSpacing: 0.5` inherited from Material `bodyLarge` / `titleMedium` in character advance measurements.
  - Replaced the `fontSize * 0.62` character-width estimate in `_gutterRows` with exact, style-measured character advances (`_charAdvance`).
  - Applied `editorStrutStyle` to gutter line numbers so digits sit precisely on the code's baseline across desktop and mobile typography.
  - Added a comprehensive multi-width (420px–1600px) and multi-platform (macOS/Android) regression test suite verifying line number positioning against actual editor caret positions.

### Added
- `docs/RELEASE.md`, `docs/PRIVACY.md`, `SECURITY.md` and this changelog.
- CI workflow (`ci.yml`): `flutter analyze` + `flutter test` on every push and PR to `main`.
- A crawlable project site on GitHub Pages (landing page with download links, screenshots and metadata).
- Demo GIF in the README, captured from the running macOS app.

### Changed
- Refined editor syntax palette across all themes and languages: keywords updated to `#C842F5` (bold), operators to `#00BF69` (bold), and comments to `#596E48` (italic). Added backslash (`\`) and backtick (`` ` ``) to operator symbol patching.
- README restructured: "What is Classic Code Editor?", Demo, Key Dependencies, Privacy & Security,
  Build & Release, CI/CD, Known Limitations, FAQ and Requirements; badges upgraded and a CI badge added.
- Leftover template bundle id for the test target fixed
  (`com.example.borlandDart.RunnerTests` → `com.moradzadeh67.classicCodeEditor.RunnerTests`).

### Notes
- A maintenance release for the macOS app: refreshed documentation and a rebuilt universal DMG.
- No application-source changes that affect runtime behaviour.

## [1.0.1] — 2026-10-13

### Fixed
- LSP stale diagnostics bug.

### Added
- Custom branding: logo, app icon, README banner and social preview.
- 6 new tests (113 → 119 passing).
- Development Environment section in the README.

## [1.0.0] — 2026-10-13

First public release.

### Added
- 🎨 Three authentic retro themes — VC++ 6.0, Borland Delphi, Visual Basic 6.0.
- ⌨️ Multi-language editor — Dart, Python, C, C++ (syntax highlighting + completion).
- 🧠 Real LSP integration — live diagnostics, hover and autocomplete.
- 🐛 Real debuggers — Dart VM Service, Python `sys.settrace`, C/C++ via `clang` + `lldb`, with
  breakpoints and variable inspection.
- 🖥️ Integrated terminal and console, with a debug-output bridge.
- ✅ 113 tests passing on a fully offline test suite.
- macOS DMG packaging (`scripts/release_gate/`).
