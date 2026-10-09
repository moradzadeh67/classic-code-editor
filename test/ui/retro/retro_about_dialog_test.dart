import 'package:borland_dart/ui/retro/retro_about_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('renders RetroAboutDialog with developer and app info', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => showRetroAboutDialog(context),
              child: const Text('Open About'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open About'));
    await tester.pumpAndSettle();

    // Verify Title and Developer Name
    expect(find.text('About Classic Code Editor'), findsOneWidget);
    expect(find.text('Reza Moradzadeh (moradzadeh67)'), findsOneWidget);
    expect(find.text('Lead Flutter & Systems Engineer'), findsOneWidget);

    // Switch to Shortcuts tab
    await tester.tap(find.text('Shortcuts'));
    await tester.pumpAndSettle();
    expect(find.text('⌨️ Keyboard Shortcuts'), findsOneWidget);
    expect(find.text('Run Active Code File'), findsOneWidget);

    // Switch to System tab
    await tester.tap(find.text('System Info'));
    await tester.pumpAndSettle();
    expect(find.text('🛠️ Tech Stack & System Specs'), findsOneWidget);

    // Close Dialog
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('About Classic Code Editor'), findsNothing);
  });
}
