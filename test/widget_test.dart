import 'package:flutter_test/flutter_test.dart';
import 'package:borland_dart/app.dart';

void main() {
  testWidgets('RetroDartApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RetroDartApp());
    expect(find.text('RetroDart IDE'), findsOneWidget);
  });
}
