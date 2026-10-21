import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../models/debugger_models.dart';
import 'arm64_asm_parser.dart';
import 'c_debugger.dart';
import 'debugger_environment.dart';

/// A debugger implementation for ARM64 Assembly (`.s` files) on Apple Silicon macOS.
///
/// Drives LLDB for Assembly code, extracting CPU registers (`x0`..`x28`, `fp`, `lr`,
/// `sp`, `pc`, `cpsr`) and single-instruction disassembly at PC, providing
/// instruction-level stepping (`thread step-inst`, `thread step-inst-over`),
/// and resolving line breakpoints and pause locations via source address mapping.
///
/// # Why we map addresses ourselves
///
/// Apple's toolchain cannot emit a DWARF line table for a hand-written `.s`
/// file, so LLDB has no source lines for it and `breakpoint set --line` never
/// resolves. [Arm64AsmParser] therefore computes the byte offset of every
/// instruction relative to the entry symbol (`_main`/`main`), and this class
/// translates those offsets into absolute addresses once the program is
/// running:
///
/// ```text
/// entry stop (breakpoint on `main`)   ->  base = <load address of main>
/// gutter breakpoint on line N         ->  breakpoint set -a <base + offset(N)>
/// reached stop with pc                ->  line = offsetToLine(pc - base)
/// ```
///
/// `-a` (absolute address) is used instead of `-R` (address slide) because
/// `-R` only accepts an *unsigned* slide: a breakpoint on a helper assembled
/// before `_main` needs a negative delta, which `-R` mangles into an unrelated
/// address.
class AsmDebugger extends CDebugger {
  AsmDebugger({super.clangPath = 'clang', super.lldbPath = 'lldb'});

  Arm64AsmMap? _asmMap;
  int? _baseAddress;
  int? _entryLine;
  int? _minOffset;
  int? _maxOffset;

  /// Source line -> lldb breakpoint id, for the breakpoints this session owns.
  ///
  /// Only these ids are ever deleted, so a resync can never hit lldb's
  /// "No breakpoints exist to be deleted" path or remove the entry breakpoint.
  final Map<int, int> _lineBreakpointIds = <int, int>{};

  /// Lines whose `breakpoint set` reply has not arrived yet, in issue order.
  final List<int> _pendingBreakpointLines = <int>[];

  /// Absolute addresses the current gutter breakpoints resolve to.
  ///
  /// Exposed so a test can prove the offset base without driving lldb.
  @visibleForTesting
  final List<int> plannedBreakpointAddresses = <int>[];

  /// Parsed address map for the active assembly source.
  @visibleForTesting
  Arm64AsmMap? get asmMap => _asmMap;

  /// Load address of `main` in the running process, known after the entry stop.
  @visibleForTesting
  int? get mainAddress => _baseAddress;

  /// lldb id of the implicit entry breakpoint, null until lldb reports it.
  @visibleForTesting
  int? get entryBreakpointLldbId => entryBreakpointId;

  @override
  String get debuggerLabel => 'ARM64 Assembly';

  bool _isAppleSiliconSync() {
    if (!Platform.isMacOS) return false;
    try {
      final res = Process.runSync('uname', ['-m']);
      return res.stdout.toString().trim() == 'arm64';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> startDebugging(String filePath, {String? content}) async {
    if (state == DebugState.running || state == DebugState.paused) {
      debugPrint('AsmDebugger: already $state, ignoring start');
      return;
    }
    debugPrint('AsmDebugger: start ($state) for $filePath');

    _resetSessionBookkeeping();

    try {
      sourcePath = filePath;
      final source = await _prepareSourceAsm(filePath, content);
      if (source != null) {
        compiledSource = source;
        try {
          final fileContent = await File(source).readAsString();
          _loadAsmMap(fileContent);
        } catch (e) {
          debugPrint('AsmDebugger: error parsing asm source: $e');
        }
      }
    } catch (e) {
      debugPrint('AsmDebugger: error preparing source: $e');
    }

    if (DebuggerEnvironment.shouldShortCircuit) {
      currentPausedLine = null;
      state = DebugState.running;
      emitOutput('[Debugging ARM64 Assembly: ${_basename(filePath)}]');
      notifyListeners();
      return;
    }

    if (!_isAppleSiliconSync()) {
      emitOutput(
        '[ARM64 Assembly requires Apple Silicon macOS and clang/lldb.]',
      );
      state = DebugState.stopped;
      notifyListeners();
      return;
    }

    try {
      final source = compiledSource;
      if (source == null) {
        emitOutput(
          '[Assembly debugging failed: no source available for "$filePath"]',
        );
        state = DebugState.stopped;
        notifyListeners();
        return;
      }

      final executable = await _compileAsm(source);
      if (executable == null) {
        state = DebugState.stopped;
        notifyListeners();
        return;
      }

      final process = await Process.start(lldbPath, <String>[executable]);
      lldbProcess = process;
      resetLldbQueue();
      exitHandled = false;
      state = DebugState.running;
      currentPausedLine = null;
      emitOutput('[Debugging ARM64 Assembly: ${_basename(source)}]');
      notifyListeners();

      watchStreams(process);
      watchExit(process);
      await configureAsm(source);
    } catch (e) {
      emitOutput('[Failed to start ARM64 Assembly debug session: $e]');
      state = DebugState.stopped;
      notifyListeners();
    }
  }

  /// Clears everything that describes a *previous* lldb process.
  ///
  /// Without this a second Debug session tries to delete the first session's
  /// breakpoint ids, and lldb answers with one `error: No breakpoints exist to
  /// be deleted.` per id.
  void _resetSessionBookkeeping() {
    _baseAddress = null;
    _lineBreakpointIds.clear();
    _pendingBreakpointLines.clear();
    entryBreakpointId = null;
    awaitingEntryBreakpointId = false;
    lldbBreakpointIds.clear();
  }

  void _loadAsmMap(String source) {
    final map = Arm64AsmParser.parse(source);
    _asmMap = map;
    _entryLine = map.entryLine;
    if (map.offsetToLineMap.isEmpty) {
      _minOffset = null;
      _maxOffset = null;
    } else {
      final offsets = map.offsetToLineMap.keys;
      _minOffset = offsets.reduce((a, b) => a < b ? a : b);
      _maxOffset = offsets.reduce((a, b) => a > b ? a : b);
    }
  }

  Future<String?> _prepareSourceAsm(String filePath, String? content) async {
    final file = File(filePath);
    if (await file.exists()) return file.absolute.path;
    if (content == null || content.trim().isEmpty) return null;

    final dir = await newTempDirectory('borland_asm_source_');
    final source = File('${dir.path}${Platform.pathSeparator}main.s');
    await source.writeAsString(content);
    return source.path;
  }

  Future<String?> _compileAsm(String source) async {
    final dir = await newTempDirectory('borland_asm_build_');
    final executable = '${dir.path}${Platform.pathSeparator}borland_asm_exec';
    final arguments = <String>[
      '-g',
      '-arch',
      'arm64',
      '-o',
      executable,
      source,
    ];

    emitOutput('[Compiling ARM64 assembly with ${_basename(clangPath)}...]');

    final ProcessResult result;
    try {
      result = await Process.run(clangPath, arguments);
    } catch (e) {
      emitOutput('[ARM64 Assembly requires clang ($e).]');
      return null;
    }

    emitBlock(result.stdout is String ? result.stdout as String : '');
    emitBlock(result.stderr is String ? result.stderr as String : '');

    if (result.exitCode != 0) {
      emitOutput('[Compilation failed with code ${result.exitCode}]');
      return null;
    }
    return executable;
  }

  Future<void> configureAsm(String source) async {
    final scriptDir = await newTempDirectory('borland_asm_lldb_');
    final scriptFile = File(
      '${scriptDir.path}${Platform.pathSeparator}borland_lldb_asm.py',
    );
    await scriptFile.writeAsString(_asmLldbHelperSource);

    // One queued unit: every command waits for lldb to be idle and is verified
    // with an acknowledgement, so `run` can never be written while lldb is
    // still printing its start-up banner. Not retried - a second `run` would
    // restart the program.
    awaitingEntryBreakpointId = true;
    enqueueLldbUnit('configure', <String>[
      'command script import "${scriptFile.path}"',
      'command script add -f borland_lldb_asm.borland_snapshot borland_snapshot',
      'target stop-hook add -o borland_snapshot',
      // Only one entry breakpoint: lldb already knows the symbol as `main`, and
      // a second `--name _main` breakpoint could only report "no locations".
      'breakpoint set --name main',
      'run',
    ], retryOnTimeout: false);
  }

  /// Re-installs every gutter breakpoint at its absolute address.
  ///
  /// Does nothing until the entry stop has told us where `main` was loaded;
  /// [_handleAsmSnapshot] calls it again at that moment.
  @override
  void resyncBreakpoints() {
    final plan = _planBreakpoints();
    plannedBreakpointAddresses
      ..clear()
      ..addAll(plan.keys);

    final lldb = lldbProcess;
    if (lldb == null) return;

    // The whole resync is one unit, so the retry after a lost acknowledgement
    // repeats the deletes too: it can never leave a duplicate breakpoint.
    final commands = <String>[];
    final entryId = entryBreakpointId;
    for (final id in _lineBreakpointIds.values) {
      if (id == entryId) continue;
      commands.add('breakpoint delete $id');
    }
    _lineBreakpointIds.clear();
    _pendingBreakpointLines.clear();

    plan.forEach((address, line) {
      _pendingBreakpointLines.add(line);
      commands.add('breakpoint set -a 0x${address.toRadixString(16)}');
    });

    enqueueLldbUnit('breakpoints', commands);
  }

  /// Absolute address -> source line for every gutter breakpoint.
  ///
  /// Empty until the entry stop has reported where `main` was loaded, because
  /// the address of an instruction can only be computed from that base.
  Map<int, int> _planBreakpoints() {
    final base = _baseAddress;
    final map = _asmMap;
    if (base == null || map == null) return const <int, int>{};

    final path = sourcePath;
    final lines =
        breakpoints
            .where(
              (bp) => path == null || CDebugger.pathsMatch(bp.filePath, path),
            )
            .map((bp) => bp.line)
            .toSet()
            .toList()
          ..sort();

    // Several source lines can resolve to one instruction (a label plus the
    // instruction on the same line, or a label followed by its body). Dedupe by
    // address so a single location never gets two breakpoints.
    final planned = <int, int>{};
    for (final line in lines) {
      final offset = map.lineToOffset(line);
      if (offset == null) continue;
      planned.putIfAbsent(base + offset, () => line);
    }
    return planned;
  }

  @override
  Future<void> stepInto() async {
    resumeWithLldb('thread step-inst');
  }

  @override
  Future<void> stepOver() async {
    resumeWithLldb('thread step-inst-over');
  }

  @override
  Future<void> stepOut() async {
    resumeWithLldb('thread step-out');
  }

  @override
  void handleStdoutLine(String line) {
    if (line.startsWith(CDebugger.snapshotMarker)) {
      final jsonPayload = line.substring(CDebugger.snapshotMarker.length);
      _handleAsmSnapshot(jsonPayload);
      return;
    }

    final breakpointId = CDebugger.parseBreakpointId(line);
    if (breakpointId != null) {
      if (awaitingEntryBreakpointId) {
        entryBreakpointId = breakpointId;
        awaitingEntryBreakpointId = false;
      } else if (_pendingBreakpointLines.isNotEmpty) {
        final bpLine = _pendingBreakpointLines.removeAt(0);
        _lineBreakpointIds[bpLine] = breakpointId;
      }
      // "no locations (pending)" and its WARNING are noise: the address is
      // resolved by us, so a pending breakpoint can only be a mistake.
      if (line.contains('where = ')) emitOutput(line);
      return;
    }

    final exitCode = CDebugger.parseExitCode(line);
    if (exitCode != null) {
      emitOutput(line);
      unawaited(_handleAsmExit(exitCode));
      return;
    }

    if (line.trim().isEmpty) return;
    if (_isLldbChatter(line)) return;
    emitOutput(line);
  }

  /// Commands this class feeds to lldb's stdin, as lldb echoes them back.
  static final RegExp _commandEcho = RegExp(
    r'^(breakpoint (set|delete)\s|thread step-inst|thread step-out|continue$|run$|quit$)',
  );

  static bool _isLldbChatter(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('(lldb)')) return true;
    if (trimmed.startsWith('* thread #')) return true;
    if (trimmed.startsWith('frame #')) return true;
    // lldb's own disassembly at the stop: "->  0x1000004d0 <+0>: stp ...",
    // the following "0x1000004d4 <+4>: ..." lines and the "exe`main:" header.
    // The stop-hook already prints a single `pc=0x…  <instruction>` line.
    if (trimmed.startsWith('->')) return true;
    if (RegExp(r'^0x[0-9a-fA-F]+\s').hasMatch(trimmed)) return true;
    if (RegExp(r'^[\w.$]+`[\w.$]+:$').hasMatch(trimmed)) return true;
    if (RegExp(r'^\d+\s+\t').hasMatch(trimmed)) return true;
    if (trimmed.startsWith('^')) return true;
    if (trimmed.toLowerCase().startsWith('warning:')) return true;
    if (trimmed.contains('no locations')) return true;
    // `breakpoint delete` acknowledgement produced by every resync.
    if (RegExp(r'^\d+ breakpoints? deleted').hasMatch(trimmed)) return true;
    // lldb echoes any command that arrives while the inferior is running, so a
    // resync fired from a paused session would print `breakpoint set -a 0x…`.
    if (_commandEcho.hasMatch(trimmed)) return true;
    if (RegExp(r'^Target \d+: \(.*\) stopped\.$').hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^Process \d+ stopped$').hasMatch(trimmed)) return true;
    return false;
  }

  void _handleAsmSnapshot(String jsonPayload) {
    final int? pc;
    final List<StackFrame> frames;
    final List<Variable> registers;
    final String disasm;
    final String reason;
    final String file;

    try {
      final decoded = json.decode(jsonPayload) as Map<String, dynamic>;
      pc = _parseHex(decoded['pc'] as String?);
      frames = (decoded['stack'] as List<dynamic>? ?? const []).map((s) {
        final m = s as Map<String, dynamic>;
        return StackFrame(
          name: m['name'] as String? ?? '<unknown>',
          filePath: m['file'] as String? ?? '',
          line: (m['line'] as num?)?.toInt() ?? 0,
          column: 0,
        );
      }).toList();
      registers = (decoded['vars'] as List<dynamic>? ?? const []).map((v) {
        final m = v as Map<String, dynamic>;
        return Variable(
          name: m['name'] as String? ?? '',
          value: m['value'] as String? ?? '',
          type: m['type'] as String? ?? 'register',
        );
      }).toList();
      disasm = decoded['disasm'] as String? ?? '';
      reason = decoded['reason'] as String? ?? 'stop';
      file = decoded['file'] as String? ?? '';
    } catch (e) {
      emitOutput(
        '[ARM64 Assembly debugger received a malformed stop payload: $e]',
      );
      return;
    }

    // Before `main` is located we only accept the entry stop. Every session
    // first stops in the dynamic loader (`_dyld_start`, stop reason
    // "signal SIGSTOP"); reporting it would flash the arrow onto line 1 and
    // point the address base at an address that is not a symbol.
    if (_baseAddress == null) {
      if (pc == null || frames.isEmpty || !_isEntryFrame(frames.first.name)) {
        return;
      }
      _baseAddress = pc;
      // The slide is known now, so the gutter breakpoints can finally be
      // translated into absolute addresses - still before the user continues.
      resyncBreakpoints();
    }

    currentPausedLine = _lineForPc(pc);
    state = DebugState.paused;

    variables
      ..clear()
      ..addAll(registers);
    callStack
      ..clear()
      ..addAll(frames);

    if (disasm.isNotEmpty) emitOutput(disasm);

    final displayFile = _displaySourceName(file);
    final where = currentPausedLine == null
        ? displayFile
        : '$displayFile:$currentPausedLine';
    emitOutput('[Paused at $where ($reason)]');

    notifyListeners();
  }

  /// Maps a stopped program counter back to a 1-indexed source line.
  int? _lineForPc(int? pc) {
    final base = _baseAddress;
    final map = _asmMap;
    if (pc == null || base == null || map == null) return _entryLine;

    final offset = pc - base;
    // Stops outside the assembled unit (stepping into `printf`, a signal, the
    // process epilogue) carry no source line; keep the arrow on the entry.
    final min = _minOffset;
    final max = _maxOffset;
    if (min != null && max != null && (offset < min || offset > max)) {
      return _entryLine;
    }
    return map.offsetToLine(offset) ?? _entryLine;
  }

  /// Console-facing file name for a stop.
  ///
  /// lldb reports no file for `.s` stops, so the source is named after the buffer
  /// the user is editing. An unsaved buffer has a *label* as its path
  /// ("Untitled"), which reads badly in the Console, so the temp copy that was
  /// actually compiled ("main.s") is preferred in that case.
  String _displaySourceName(String fromSnapshot) {
    if (fromSnapshot.isNotEmpty) return _basename(fromSnapshot);
    final path = sourcePath;
    if (path != null && (path.contains('/') || path.contains(r'\'))) {
      return _basename(path);
    }
    final compiled = compiledSource;
    if (compiled != null) return _basename(compiled);
    if (path != null && path.isNotEmpty) return _basename(path);
    return 'main.s';
  }

  static bool _isEntryFrame(String name) => name == 'main' || name == '_main';

  static int? _parseHex(String? value) {
    if (value == null) return null;
    final cleaned = value.trim().toLowerCase().replaceFirst('0x', '');
    if (cleaned.isEmpty) return null;
    return int.tryParse(cleaned, radix: 16);
  }

  Future<void> _handleAsmExit(int exitCode) async {
    if (exitHandled) return;
    exitHandled = true;
    emitOutput('[ARM64 Assembly program exited with code $exitCode]');
    await stopDebugging();
  }

  static String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }
}

const String _asmLldbHelperSource = r'''import json
import sys

REGISTER_NAMES = set(
    [f"x{i}" for i in range(29)] + ["fp", "lr", "sp", "pc", "cpsr"]
)


def _path_of(entry):
    spec = entry.GetFileSpec()
    full = getattr(spec, "fullpath", None)
    if not full:
        directory = spec.GetDirectory() or ""
        name = spec.GetFilename() or ""
        full = f"{directory}/{name}" if directory else name
    return full or ""


def _location(entity):
    entry = entity.GetLineEntry() if entity else None
    if entry and entry.IsValid():
        return {
            "file": _path_of(entry),
            "line": entry.GetLine(),
        }
    return {"file": "", "line": 0}


def borland_snapshot(debugger, command, result, internal_dict):
    try:
        _emit_snapshot(debugger)
    except Exception as error:  # noqa: BLE001 - diagnostic path
        sys.stdout.write(f"@@BORLAND_SNAP_ERR {error}\n")
        sys.stdout.flush()


def _stop_reason(thread):
    """Human text for the stop, e.g. "breakpoint 1.1" or "instruction step"."""
    try:
        description = thread.GetStopDescription(256)
    except Exception:  # noqa: BLE001 - older/newer SB API
        description = None
    if description:
        return description
    return f"stop reason {thread.GetStopReason()}"


def _emit_snapshot(debugger):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess() if target else None
    if process is None:
        return
    thread = process.GetSelectedThread()
    if thread is None:
        return
    frame = thread.GetSelectedFrame()

    variables = []
    if frame is not None:
        for reg_set in frame.GetRegisters():
            for reg in reg_set:
                rname = reg.GetName()
                if rname in REGISTER_NAMES:
                    variables.append({
                        "name": rname,
                        "value": reg.GetValue() or "",
                        "type": "register",
                    })

    pc_disasm = ""
    pc_hex = ""
    if frame is not None:
        addr = frame.GetPCAddress()
        if addr and addr.IsValid():
            pc_hex = f"0x{addr.GetLoadAddress(target):x}"
            insts = target.ReadInstructions(addr, 1)
            if insts and len(insts) > 0:
                ins = insts[0]
                mnemonic = ins.GetMnemonic(target) or ""
                operands = ins.GetOperands(target) or ""
                pc_disasm = f"pc={pc_hex}  {mnemonic} {operands}".strip()

    stack = []
    for index in range(thread.GetNumFrames()):
        item = thread.GetFrameAtIndex(index)
        entry = item.GetLineEntry() if item else None
        stack.append({
            "name": (item.GetFunctionName() if item else None) or "<unknown>",
            "file": _path_of(entry) if entry and entry.IsValid() else "",
            "line": entry.GetLine() if entry and entry.IsValid() else 0,
        })

    location = _location(frame)
    payload = {
        "file": location["file"],
        "line": location["line"],
        "pc": pc_hex,
        "reason": _stop_reason(thread),
        "vars": variables,
        "stack": stack,
        "disasm": pc_disasm,
    }
    line = "@@BORLAND_SNAP " + json.dumps(payload)
    written = False
    try:
        out = debugger.GetOutputFile() if debugger is not None else None
        if out is not None and out.IsValid():
            out.Write(line + "\n")
            out.Flush()
            written = True
    except Exception:  # noqa: BLE001 - fall back to stdout below
        written = False
    if not written:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()
''';
