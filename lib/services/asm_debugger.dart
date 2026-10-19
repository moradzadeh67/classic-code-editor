import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/debugger_models.dart';
import 'c_debugger.dart';
import 'debugger_environment.dart';

/// A debugger implementation for ARM64 Assembly (`.s` files) on Apple Silicon macOS.
///
/// Drives LLDB for Assembly code, extracting CPU registers (`x0`..`x28`, `fp`, `lr`,
/// `sp`, `pc`, `cpsr`) and single-instruction disassembly at PC, and providing
/// instruction-level stepping (`thread step-inst`, `thread step-inst-over`).
class AsmDebugger extends CDebugger {
  AsmDebugger({super.clangPath = 'clang', super.lldbPath = 'lldb'});

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
    // A finished/stopped session may be restarted; only a live one may not.
    // (The old `state != inactive` guard made the second Debug click a silent
    // no-op, so nothing was logged and no arrow ever appeared.)
    if (state == DebugState.running || state == DebugState.paused) {
      debugPrint('AsmDebugger: already $state, ignoring start');
      return;
    }
    debugPrint('AsmDebugger: start ($state) for $filePath');

    if (DebuggerEnvironment.shouldShortCircuit) {
      // Match CDebugger: in unit tests no real clang/lldb is spawned, so the
      // session is announced and left running rather than paused at a line the
      // debugger never actually reached.
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
      sourcePath = filePath;
      final source = await _prepareSourceAsm(filePath, content);
      if (source == null) {
        emitOutput(
          '[Assembly debugging failed: no source available for "$filePath"]',
        );
        state = DebugState.stopped;
        notifyListeners();
        return;
      }
      compiledSource = source;
      _entryLine = await _findEntryLine(source);

      final executable = await _compileAsm(source);
      if (executable == null) {
        state = DebugState.stopped;
        notifyListeners();
        return;
      }

      final process = await Process.start(lldbPath, <String>[executable]);
      lldbProcess = process;
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

    writeLldb('command script import "${scriptFile.path}"');
    writeLldb(
      'command script add -f borland_lldb_asm.borland_snapshot borland_snapshot',
    );
    writeLldb('target stop-hook add -o borland_snapshot');
    resyncBreakpoints();
    awaitingEntryBreakpointId = true;
    writeLldb('breakpoint set --name _main');
    writeLldb('breakpoint set --name main');
    writeLldb('run');
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

  /// Line of the `_main:` label, used as the pause marker.
  ///
  /// Reason: macOS cannot emit a DWARF line table for a hand-written `.s`
  /// (verified against clang / as / llvm-mc), so LLDB has no source lines and
  /// line breakpoints never resolve. Instruction stepping, registers and the
  /// paused marker therefore come from our own bookkeeping instead.
  int? _entryLine;

  /// True while a `register read --all` block is being collected.
  bool _collectingRegisters = false;

  /// TODO(1.3.1): replace this whole mechanism once a toolchain can give us a
  /// DWARF line table for `.s` files (then line breakpoints work again).
  Future<int?> _findEntryLine(String sourcePath) async {
    try {
      final lines = await File(sourcePath).readAsLines();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed == '_main:' || trimmed == 'main:') return i + 1;
      }
    } on FileSystemException catch (e) {
      debugPrint('AsmDebugger: cannot read $sourcePath: $e');
    }
    return null;
  }

  /// Marks the session paused and asks LLDB for the register file.
  void _onStopReached() {
    currentPausedLine = _entryLine;
    if (state != DebugState.paused) state = DebugState.paused;
    notifyListeners();
    final process = lldbProcess;
    if (process == null) return;
    _collectingRegisters = true;
    variables.clear();
    process.stdin.writeln('register read --all');
    process.stdin.writeln('script print("@@ASMREGS_END")');
  }

  static final RegExp _registerLine = RegExp(
    r'^\s*(x\d+|w\d+|fp|lr|sp|pc|cpsr|d\d+|v\d+)\s*=\s*(.+?)\s*$',
  );

  @override
  void handleStdoutLine(String line) {
    final trimmed = line.trim();

    // LLDB marks the stopped frame with `->  0x…`.
    if (trimmed.startsWith('->')) {
      _onStopReached();
    } else if (_collectingRegisters) {
      if (trimmed.contains('@@ASMREGS_END')) {
        _collectingRegisters = false;
        notifyListeners();
        return;
      }
      final match = _registerLine.firstMatch(line);
      if (match != null) {
        variables.add(
          Variable(
            name: match.group(1)!,
            value: match.group(2)!.trim(),
            type: 'register',
          ),
        );
        return;
      }
    }

    if (line.startsWith(CDebugger.snapshotMarker)) {
      final jsonPayload = line.substring(CDebugger.snapshotMarker.length);
      try {
        final decoded = json.decode(jsonPayload) as Map<String, dynamic>;
        final disasm = decoded['disasm'] as String?;
        if (disasm != null && disasm.isNotEmpty) {
          emitOutput(disasm);
        }
      } catch (_) {}
    }
    super.handleStdoutLine(line);
  }

  static String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }
}

const String _asmLldbHelperSource = r'''import json
import sys

def _path_of(entry):
    # The FULL path matters: the editor compares it with the open document to
    # decide which row gets the paused-line arrow. A bare file name never
    # matched, so the "▶" marker never appeared for assembly.
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
    # Any exception inside a stop-hook is otherwise swallowed by LLDB, which is
    # why the register snapshot silently never reached the IDE. Report it on
    # stdout so the Console shows what actually failed.
    try:
        _emit_snapshot(debugger)
    except Exception as error:  # noqa: BLE001 - diagnostic path
        sys.stdout.write(f"@@BORLAND_SNAP_ERR {error}\n")
        sys.stdout.flush()


def _emit_snapshot(debugger):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess() if target else None
    if process is None:
        return
    thread = process.GetSelectedThread()
    if thread is None:
        return
    frame = thread.GetSelectedFrame()

    reg_names = set([f"x{i}" for i in range(29)] + ["fp", "lr", "sp", "pc", "cpsr"])
    variables = []
    if frame is not None:
        for reg_set in frame.GetRegisters():
            for reg in reg_set:
                rname = reg.GetName()
                if rname in reg_names:
                    val = reg.GetValue() or ""
                    variables.append({
                        "name": rname,
                        "value": val,
                        "type": "register",
                    })

    pc_disasm = ""
    if frame is not None:
        addr = frame.GetPCAddress()
        if addr and addr.IsValid():
            load_addr = addr.GetLoadAddress(target)
            insts = target.ReadInstructions(addr, 1)
            if insts and len(insts) > 0:
                ins = insts[0]
                mnemonic = ins.GetMnemonic(target) or ""
                operands = ins.GetOperands(target) or ""
                pc_disasm = f"pc=0x{load_addr:x}  {mnemonic} {operands}".strip()

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
        "reason": str(thread.GetStopReason()),
        "vars": variables,
        "stack": stack,
        "disasm": pc_disasm,
    }
    line = "@@BORLAND_SNAP " + json.dumps(payload)
    # In prompt mode LLDB often swallows Python's sys.stdout, so the snapshot
    # never reached the IDE even though the hook ran. Write to the debugger's
    # own output file (the stream the IDE reads) and fall back to stdout.
    written = False
    try:
        out = debugger.GetOutputFile() if debugger is not None else None
        if out is not None and out.IsValid():
            out.Write(line + "\n")
            out.Flush()
            written = True
    except Exception:
        written = False
    if not written:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()
''';
