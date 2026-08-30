import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_assistant/main.dart';

void main() {
  testWidgets('Smart Assistant renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Logo(),
        ),
      ),
    );

    expect(find.byType(Logo), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
  });
}
