import 'dart:convert';

import 'package:flutter/foundation.dart' hide StackFrame;

import '../models/debugger_models.dart';

/// A language-agnostic "the program just stopped here" snapshot.
///
/// Both the Python tracer driver and the LLDB helper script emit the exact same
/// JSON shape:
///
///     { "file": ..., "line": ..., "reason": ...,
///       "vars":  [{ "name": ..., "value": ..., "type": ... }, ...],
///       "stack": [{ "name": ..., "file": ..., "line": ... }, ...] }
///
/// Sharing a single decoder keeps the two protocols honest and makes the
/// parsing path unit-testable without spawning any runtime.
class DebugSnapshot {
  const DebugSnapshot({
    required this.filePath,
    required this.line,
    required this.reason,
    required this.variables,
    required this.stack,
  });

  final String filePath;
  final int line;
  final String reason;
  final List<Variable> variables;
  final List<StackFrame> stack;

  /// Decodes a snapshot payload; returns `null` when it is missing or malformed
  /// so callers can report it gracefully instead of throwing in a callback.
  static DebugSnapshot? tryParse(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;

      final file = decoded['file'] as String? ?? '';
      final line = (decoded['line'] as num?)?.toInt() ?? 0;
      final reason = decoded['reason'] as String? ?? 'stopped';

      final variables = <Variable>[];
      final rawVariables = decoded['vars'];
      if (rawVariables is List) {
        for (final entry in rawVariables) {
          if (entry is Map) {
            variables.add(
              Variable(
                name: entry['name'] as String? ?? '?',
                value: entry['value'] as String? ?? '',
                type: entry['type'] as String? ?? '',
              ),
            );
          }
        }
      }

      final stack = <StackFrame>[];
      final rawStack = decoded['stack'];
      if (rawStack is List) {
        for (final entry in rawStack) {
          if (entry is Map) {
            stack.add(
              StackFrame(
                name: entry['name'] as String? ?? '<unknown>',
                filePath: entry['file'] as String? ?? file,
                line: (entry['line'] as num?)?.toInt() ?? 0,
                column: 0,
              ),
            );
          }
        }
      }

      return DebugSnapshot(
        filePath: file,
        line: line,
        reason: reason,
        variables: variables,
        stack: stack,
      );
    } catch (e) {
      debugPrint('[DebugSnapshot] Malformed payload: $e');
      return null;
    }
  }
}
