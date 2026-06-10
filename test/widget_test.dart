import 'package:flutter_test/flutter_test.dart';

import 'package:gps_drivers/main.dart';

void main() {
  testWidgets('shows login role selection', (WidgetTester tester) async {
    await tester.pumpWidget(const GPSApp());

    expect(find.text('מערכת GPS נהגים'), findsOneWidget);
    expect(find.text('מנהל'), findsOneWidget);
    expect(find.text('נהג'), findsOneWidget);
  });
}
