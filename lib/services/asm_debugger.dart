import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    if (state != DebugState.inactive) return;

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

  @override
  void handleStdoutLine(String line) {
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

def _location(entity):
    entry = entity.GetLineEntry() if entity else None
    if entry and entry.IsValid():
        return {
            "file": entry.GetFileSpec().GetFilename() or "",
            "line": entry.GetLine(),
        }
    return {"file": "", "line": 0}

def borland_snapshot(debugger, command, result, internal_dict):
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
            "file": entry.GetFileSpec().GetFilename() if entry and entry.IsValid() else "",
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
    sys.stdout.write("@@BORLAND_SNAP " + json.dumps(payload) + "\n")
    sys.stdout.flush()
''';
