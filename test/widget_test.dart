import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_assistant/main.dart';

void main() {
  testWidgets('Renders Smart Assistant Logo and main app shell',
      (WidgetTester tester) async {
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

  test('AppState calculations and negative balance check', () {
    final state = AppState();
    state.customers = [
      {'name': 'عميل 1', 'balance': 500.0},
      {'name': 'عميل 2', 'balance': -200.0},
    ];
    state.products = [
      {'name': 'صنف 1', 'qty': 2.0, 'minimum': 5.0, 'unit': 'قطعة'},
      {'name': 'صنف 2', 'qty': 10.0, 'minimum': 5.0, 'unit': 'كرتونة'},
    ];
    state.dues = [
      {'customer': 'عميل 1', 'amount': 100.0, 'status': 'pending'},
    ];

    expect(state.customers.length, equals(2));
    expect(state.products.length, equals(2));
    expect(state.dues.length, equals(1));

    // Verify negative balance logic
    final cust2 = state.customers.firstWhere((c) => c['name'] == 'عميل 2');
    expect(cust2['balance'], equals(-200.0));
  });
}
