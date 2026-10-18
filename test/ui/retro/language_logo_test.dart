import 'package:classic_code_editor/ui/retro/language_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the asset path of the single [Image] the logo resolved to.
String? assetNameOf(WidgetTester tester) {
  final images = find.byType(Image);
  if (images.evaluate().isEmpty) return null;
  final image = tester.widget<Image>(images.first).image;
  return image is AssetImage ? image.assetName : null;
}

Future<void> pumpLogo(WidgetTester tester, String language) {
  return tester.pumpWidget(
    MaterialApp(
      home: Center(child: LanguageLogo(language: language)),
    ),
  );
}

void main() {
  group('LanguageLogo', () {
    testWidgets('every spelling of ARM64 assembly uses the ASM icon', (
      tester,
    ) async {
      for (final language in ['s', 'asm', 'arm64', 'ARM64 Assembly']) {
        await pumpLogo(tester, language);
        expect(assetNameOf(tester), 'assets/icons/asm.png', reason: language);
      }
    });

    testWidgets('the existing languages keep their own icons', (tester) async {
      const expected = {
        'dart': 'assets/icons/dart.png',
        'py': 'assets/icons/python.png',
        'python': 'assets/icons/python.png',
        'c': 'assets/icons/c.png',
        'cpp': 'assets/icons/cpp.png',
      };
      for (final entry in expected.entries) {
        await pumpLogo(tester, entry.key);
        expect(assetNameOf(tester), entry.value, reason: entry.key);
      }
    });

    testWidgets('an unknown language renders nothing', (tester) async {
      await pumpLogo(tester, 'cobol');
      expect(find.byType(Image), findsNothing);
    });
  });
}
