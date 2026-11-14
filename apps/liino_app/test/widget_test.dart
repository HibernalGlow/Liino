import 'package:flutter_test/flutter_test.dart';
import 'package:liino_app/main.dart';

void main() {
  testWidgets('LiinoApp renders FlClash-style MD3E dashboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LiinoApp());
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Ready to Connect'), findsOneWidget);
  });
}
