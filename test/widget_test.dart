import 'package:flutter_test/flutter_test.dart';
import 'package:classic_code_editor/app.dart';

void main() {
  testWidgets('RetroDartApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RetroDartApp());
    expect(find.text('File'), findsOneWidget);
  });
}
