import 'package:borland_dart/models/debugger_models.dart';
import 'package:borland_dart/services/dart_debugger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the Dart debugger's local state machine.
///
/// Under the `FLUTTER_TEST` environment [DartDebugger] never spawns a real VM;
/// these tests therefore exercise the state transitions, breakpoint bookkeeping
/// and listener notifications that the UI relies on.
void main() {
  group('DartDebugger', () {
    late DartDebugger debugger;

    setUp(() {
      debugger = DartDebugger();
    });

    tearDown(() {
      debugger.dispose();
    });

    test('starts in the inactive state with empty collections', () {
      expect(debugger.state, DebugState.inactive);
      expect(debugger.currentPausedLine, isNull);
      expect(debugger.breakpoints, isEmpty);
      expect(debugger.variables, isEmpty);
      expect(debugger.callStack, isEmpty);
    });

    test('startDebugging transitions to running', () async {
      await debugger.startDebugging(
        '/tmp/borland_does_not_exist.dart',
        content: 'void main() {}',
      );
      expect(debugger.state, DebugState.running);
    });

    test(
      'startDebugging is a no-op when a session is already active',
      () async {
        await debugger.startDebugging('/tmp/a.dart', content: 'void main() {}');
        await debugger.startDebugging('/tmp/b.dart', content: 'void main() {}');
        expect(debugger.state, DebugState.running);
      },
    );

    test('stopDebugging resets state and clears captured data', () async {
      await debugger.startDebugging('/tmp/a.dart', content: 'void main() {}');
      debugger.setBreakpoint('/tmp/a.dart', 3);

      await debugger.stopDebugging();

      expect(debugger.state, DebugState.inactive);
      expect(debugger.currentPausedLine, isNull);
      expect(debugger.variables, isEmpty);
      expect(debugger.callStack, isEmpty);
    });

    test('breakpoints can be added, removed and cleared per file', () {
      debugger.setBreakpoint('/tmp/a.dart', 2);
      debugger.setBreakpoint('/tmp/a.dart', 5);
      debugger.setBreakpoint('/tmp/b.dart', 1);
      expect(debugger.breakpoints.length, 3);

      debugger.removeBreakpoint('/tmp/a.dart', 2);
      expect(debugger.breakpoints.length, 2);

      debugger.clearBreakpointsForFile('/tmp/a.dart');
      expect(debugger.breakpoints.single.filePath, '/tmp/b.dart');

      debugger.clearBreakpoints();
      expect(debugger.breakpoints, isEmpty);
    });

    test('start and stop notify listeners', () async {
      var notifications = 0;
      debugger.addListener(() => notifications++);

      await debugger.startDebugging('/tmp/a.dart', content: 'void main() {}');
      await debugger.stopDebugging();

      expect(notifications, greaterThanOrEqualTo(2));
    });

    test('startDebugging publishes a session banner to the Console', () async {
      final output = <String>[];
      final subscription = debugger.output.listen(output.add);
      addTearDown(subscription.cancel);

      await debugger.startDebugging('/tmp/a.dart', content: 'void main() {}');
      await Future<void>.delayed(Duration.zero);

      expect(output, contains('[Debugging Dart: a.dart]'));
    });

    test('stopDebugging publishes the teardown notice', () async {
      await debugger.startDebugging('/tmp/a.dart', content: 'void main() {}');
      final output = <String>[];
      final subscription = debugger.output.listen(output.add);
      addTearDown(subscription.cancel);

      await debugger.stopDebugging();
      await Future<void>.delayed(Duration.zero);

      expect(output, contains('[Dart debugging stopped]'));
    });

    // The gutter paints its paused-line arrow from `currentPausedLine`, so the
    // Dart pause path must be verified too - not just the Python and C ones.
    group('paused frame mapping (drives the gutter arrow)', () {
      Map<String, dynamic> pausedFrame({
        required int line,
        String function = 'main',
      }) => <String, dynamic>{
        'function': <String, dynamic>{'name': function},
        'location': <String, dynamic>{
          'line': line,
          'column': 3,
          'script': <String, dynamic>{'uri': 'file:///tmp/main.dart'},
        },
        'vars': <dynamic>[
          <String, dynamic>{
            'name': 'greeting',
            'value': <String, dynamic>{
              'class': <String, dynamic>{'name': 'String'},
              'valueAsString': 'Hello',
            },
          },
        ],
      };

      test('a paused VM frame publishes the line the gutter paints', () {
        debugger.applyStackSnapshot(<String, dynamic>{
          'frames': <dynamic>[pausedFrame(line: 8)],
        });

        expect(debugger.state, DebugState.paused);
        expect(debugger.currentPausedLine, 8);
        expect(debugger.variables.single.name, 'greeting');
        expect(debugger.variables.single.value, 'Hello');
        expect(debugger.variables.single.type, 'String');
        expect(debugger.callStack.single.name, 'main');
        expect(debugger.callStack.single.line, 8);
      });

      test('resuming without an attached VM leaves the paused line untouched', () async {
        debugger.applyStackSnapshot(<String, dynamic>{
          'frames': <dynamic>[pausedFrame(line: 8)],
        });
        expect(debugger.currentPausedLine, 8);

        // Under `FLUTTER_TEST` no VM is attached, so the resume command is
        // dropped rather than clearing a session that is not there. In the
        // running app this same call resets the state to running and hides the
        // gutter arrow.
        await debugger.continueExecution();

        expect(debugger.state, DebugState.paused);
        expect(debugger.currentPausedLine, 8);
      });

      test('publishes a paused notice to the Console', () async {
        final output = <String>[];
        final subscription = debugger.output.listen(output.add);
        addTearDown(subscription.cancel);

        debugger.applyStackSnapshot(<String, dynamic>{
          'frames': <dynamic>[pausedFrame(line: 8)],
        });
        await Future<void>.delayed(Duration.zero);

        expect(output, contains('[Paused at main.dart:8]'));
      });

      test('notifies listeners so the gutter repaints', () {
        var notifications = 0;
        debugger.addListener(() => notifications++);

        debugger.applyStackSnapshot(<String, dynamic>{
          'frames': <dynamic>[pausedFrame(line: 4)],
        });

        expect(notifications, greaterThanOrEqualTo(1));
        expect(debugger.currentPausedLine, 4);
      });

      test('a frame without a source location does not fake a pause', () {
        debugger.applyStackSnapshot(<String, dynamic>{
          'frames': <dynamic>[
            <String, dynamic>{
              'function': <String, dynamic>{'name': 'main'},
              'vars': <dynamic>[],
            },
          ],
        });

        // No usable user frame: the gutter must never be told about a pause.
        expect(debugger.state, isNot(DebugState.paused));
        expect(debugger.currentPausedLine, isNull);
      });

      test('an empty stack does not fake a pause', () {
        debugger.applyStackSnapshot(<String, dynamic>{'frames': <dynamic>[]});

        expect(debugger.state, isNot(DebugState.paused));
        expect(debugger.currentPausedLine, isNull);
        expect(debugger.callStack, isEmpty);
      });

      test('a stack of VM-internal dart: frames is rejected', () async {
        final output = <String>[];
        final subscription = debugger.output.listen(output.add);
        addTearDown(subscription.cancel);

        // Exactly what the isolate reports when paused on start, before the
        // Dart entrypoint runs: only framework internals, no user frame.
        debugger.applyStackSnapshot(<String, dynamic>{
          'frames': <dynamic>[
            <String, dynamic>{
              'function': <String, dynamic>{'name': '_portMap'},
              'location': <String, dynamic>{
                'line': 227,
                'column': 1,
                'script': <String, dynamic>{
                  'uri': 'dart:isolate-patch/isolate_patch.dart',
                },
              },
            },
            <String, dynamic>{
              'function': <String, dynamic>{'name': '_startMainIsolate'},
              'location': <String, dynamic>{
                'line': 270,
                'column': 1,
                'script': <String, dynamic>{
                  'uri': 'dart:isolate-patch/isolate_patch.dart',
                },
              },
            },
          ],
        });
        await Future<void>.delayed(Duration.zero);

        expect(debugger.state, isNot(DebugState.paused));
        expect(debugger.currentPausedLine, isNull);
        expect(debugger.callStack, isEmpty);
        expect(output, isEmpty);
      });

      test('a user top frame keeps only the user frames', () {
        debugger.applyStackSnapshot(<String, dynamic>{
          'frames': <dynamic>[
            pausedFrame(line: 8),
            <String, dynamic>{
              'function': <String, dynamic>{'name': '_startMainIsolate'},
              'location': <String, dynamic>{
                'line': 270,
                'column': 1,
                'script': <String, dynamic>{
                  'uri': 'dart:isolate-patch/isolate_patch.dart',
                },
              },
            },
          ],
        });

        expect(debugger.state, DebugState.paused);
        expect(debugger.currentPausedLine, 8);
        expect(debugger.callStack.single.name, 'main');
      });

      test('stopDebugging clears the paused line afterwards', () async {
        debugger.applyStackSnapshot(<String, dynamic>{
          'frames': <dynamic>[pausedFrame(line: 6)],
        });
        expect(debugger.currentPausedLine, 6);

        await debugger.stopDebugging();

        expect(debugger.currentPausedLine, isNull);
        expect(debugger.state, DebugState.inactive);
      });
    });

    // The entry breakpoint that makes Debug pause at the user's `main` must be
    // tracked separately from the gutter breakpoints, so editing or clearing
    // them mid-session cannot silently delete it.
    group('entry breakpoint bookkeeping', () {
      test('survives gutter breakpoint edits and clears', () {
        debugger.entryBreakpointId = 'bp-main';

        debugger.setBreakpoint('/tmp/a.dart', 3);
        debugger.setBreakpoint('/tmp/a.dart', 4);
        debugger.removeBreakpoint('/tmp/a.dart', 3);
        debugger.clearBreakpointsForFile('/tmp/a.dart');
        debugger.clearBreakpoints();

        expect(debugger.entryBreakpointId, 'bp-main');
      });

      test('is cleared when the session stops', () async {
        debugger.entryBreakpointId = 'bp-main';

        await debugger.stopDebugging();

        expect(debugger.entryBreakpointId, isNull);
      });
    });

    group('findMainLine (locates `main` in the entry script)', () {
      test('finds a plain void main declaration', () {
        expect(DartDebugger.findMainLine('void main() {\n  print(1);\n}'), 1);
      });

      test('finds an async main returning a Future', () {
        expect(
          DartDebugger.findMainLine(
            "import 'dart:async';\n\nFuture<void> main() async {\n  run();\n}",
          ),
          3,
        );
      });

      test('finds a main without a return type', () {
        expect(DartDebugger.findMainLine('main() {\n  print(1);\n}'), 1);
      });

      test('finds an expression-bodied main', () {
        expect(DartDebugger.findMainLine('void main() => print(1);'), 1);
      });

      test('returns null when there is no main', () {
        expect(
          DartDebugger.findMainLine('int add(int a, int b) => a + b;'),
          isNull,
        );
      });

      test('ignores indented calls that merely mention main', () {
        expect(
          DartDebugger.findMainLine(
            'void helper() {\n  runApp(main);\n  x.main();\n  main();\n}',
          ),
          isNull,
        );
      });
    });
  });
}
