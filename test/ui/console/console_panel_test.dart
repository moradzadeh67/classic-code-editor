import 'dart:async';

import 'package:borland_dart/services/dart_runner_service.dart';
import 'package:borland_dart/services/debugger_factory.dart';
import 'package:borland_dart/ui/console/console_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end check of the debugger -> Console chain, wired exactly the way
/// IDEShell wires it: every language debugger feeds the runner's output stream,
/// and the Console panel renders that stream.
void main() {
  testWidgets('renders debugger output forwarded through the runner', (
    tester,
  ) async {
    final runner = DartRunnerService();
    addTearDown(runner.dispose);

    final factory = DebuggerFactory();
    addTearDown(factory.dispose);

    // Mirrors IDEShell.initState.
    final subscriptions = <StreamSubscription<String>>[
      for (final debugger in factory.all)
        debugger.output.listen(runner.emitOutput),
    ];
    addTearDown(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConsolePanel(dartRunnerService: runner)),
      ),
    );

    await factory.pythonDebugger.startDebugging(
      '/tmp/main.py',
      content: 'print("hi")',
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data == '[Debugging Python: main.py]',
      ),
      findsOneWidget,
    );
  });
}
