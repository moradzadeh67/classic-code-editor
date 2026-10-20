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
class AsmDebugger extends CDebugger {
  AsmDebugger({super.clangPath = 'clang', super.lldbPath = 'lldb'});

  Arm64AsmMap? _asmMap;
  int? _mainAddress;
  int? _entryLine;

  /// Parsed address map for the active assembly source.
  @visibleForTesting
  Arm64AsmMap? get asmMap => _asmMap;

  /// Base address of `_main` entry in the running process.
  @visibleForTesting
  int? get mainAddress => _mainAddress;

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

    try {
      sourcePath = filePath;
      final source = await _prepareSourceAsm(filePath, content);
      if (source != null) {
        compiledSource = source;
        try {
          final fileContent = await File(source).readAsString();
          _asmMap = Arm64AsmParser.parse(fileContent);
          _entryLine = _asmMap!.entryLine;
        } catch (e) {
          debugPrint('AsmDebugger: error parsing asm source: $e');
        }
      }
    } catch (e) {
      debugPrint('AsmDebugger: error preparing source: $e');
    }
    _mainAddress = null;

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
  void resyncBreakpoints() {
    final lldb = lldbProcess;
    if (lldb == null) return;

    final entryId = entryBreakpointId;
    for (final id in lldbBreakpointIds) {
      if (id == entryId) continue;
      writeLldb('breakpoint delete $id');
    }
    lldbBreakpointIds.clear();

    final map = _asmMap;
    final source = compiledSource;
    if (map == null || source == null) return;

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

    for (final line in lines) {
      final offset = map.lineToOffset(line);
      if (offset != null) {
        writeLldb('breakpoint set -n main -R $offset');
        writeLldb('breakpoint set -n _main -R $offset');
      }
    }
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
      } else {
        lldbBreakpointIds.add(breakpointId);
      }
      emitOutput(line);
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

  static bool _isLldbChatter(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('(lldb)')) return true;
    if (trimmed.startsWith('* thread #')) return true;
    if (trimmed.startsWith('frame #')) return true;
    if (RegExp(r'^\d+\s+\t').hasMatch(trimmed)) return true;
    if (trimmed.startsWith('^')) return true;
    if (RegExp(r'^Target \d+: \(.*\) stopped\.$').hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^Process \d+ stopped$').hasMatch(trimmed)) return true;
    return false;
  }

  void _handleAsmSnapshot(String jsonPayload) {
    try {
      final decoded = json.decode(jsonPayload) as Map<String, dynamic>;

      final pcHex = decoded['pc'] as String? ?? '';
      int? currentPc;
      if (pcHex.isNotEmpty) {
        final cleanHex = pcHex.toLowerCase().replaceAll('0x', '');
        currentPc = int.tryParse(cleanHex, radix: 16);
      }

      if (currentPc != null) {
        _mainAddress ??= currentPc;
        final offset = currentPc - _mainAddress!;
        final mappedLine = _asmMap?.offsetToLine(offset);
        if (mappedLine != null && mappedLine > 0) {
          currentPausedLine = mappedLine;
        } else if (_entryLine != null) {
          currentPausedLine = _entryLine;
        }
      } else if (decoded['line'] != null && (decoded['line'] as num) > 0) {
        currentPausedLine = (decoded['line'] as num).toInt();
      } else if (_entryLine != null) {
        currentPausedLine = _entryLine;
      }

      final rawVars = decoded['vars'] as List<dynamic>? ?? const [];
      variables
        ..clear()
        ..addAll(
          rawVars.map((v) {
            final m = v as Map<String, dynamic>;
            return Variable(
              name: m['name'] as String? ?? '',
              value: m['value'] as String? ?? '',
              type: m['type'] as String? ?? 'register',
            );
          }),
        );

      final rawStack = decoded['stack'] as List<dynamic>? ?? const [];
      callStack
        ..clear()
        ..addAll(
          rawStack.map((s) {
            final m = s as Map<String, dynamic>;
            return StackFrame(
              name: m['name'] as String? ?? '<unknown>',
              filePath: m['file'] as String? ?? '',
              line: (m['line'] as num?)?.toInt() ?? 0,
              column: 0,
            );
          }),
        );

      final disasm = decoded['disasm'] as String?;
      if (disasm != null && disasm.isNotEmpty) {
        emitOutput(disasm);
      }

      final reason = decoded['reason'] as String? ?? 'stop';
      final file = decoded['file'] as String? ?? '';
      final displayFile = file.isNotEmpty
          ? _basename(file)
          : (sourcePath != null ? _basename(sourcePath!) : 'main.s');
      emitOutput('[Paused at $displayFile:$currentPausedLine ($reason)]');

      state = DebugState.paused;
      notifyListeners();
    } catch (e) {
      emitOutput(
        '[ARM64 Assembly debugger received a malformed stop payload: $e]',
      );
    }
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


def _emit_snapshot(debugger):
    target = debugger.GetSelectedTarget()
    process = target.GetProcess() if target else None
    if process is None:
        return
    thread = process.get_selected_thread() if hasattr(process, "get_selected_thread") else process.GetSelectedThread()
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
    pc_hex = ""
    if frame is not None:
        addr = frame.GetPCAddress()
        if addr and addr.IsValid():
            load_addr = addr.GetLoadAddress(target)
            pc_hex = f"0x{load_addr:x}"
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
        "reason": str(thread.GetStopReason()),
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
    except Exception:
        written = False
    if not written:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()
''';
