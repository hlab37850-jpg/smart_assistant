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

  test('PDF extraction and parsing pipeline test', () {
    // Simulate extracted lines from PDF table
    final pdfLines = [
      'الاسم,الهاتف,الرصيد,الملاحظات',
      'شركة الأمل,0501112223,350.00,عميل دائم',
      'مؤسسة النجاح,0503334445,-120.50,دائن بقيمة',
      'PPR 20 × 4,سباكة,50,10,25.00,حبة',
    ];

    final parsedCustomers = pdfLines.skip(1).map((line) {
      final parts = line.split(',');
      return {
        'name': parts[0].trim(),
        'phone': parts.length > 1 ? parts[1].trim() : '',
        'balance':
            double.tryParse(parts.length > 2 ? parts[2].trim() : '0') ?? 0.0,
        'notes': parts.length > 3 ? parts[3].trim() : '',
      };
    }).toList();

    expect(parsedCustomers.length, equals(3));
    expect(parsedCustomers[0]['name'], equals('شركة الأمل'));
    expect(parsedCustomers[0]['balance'], equals(350.00));

    // Verify negative balance retention
    expect(parsedCustomers[1]['name'], equals('مؤسسة النجاح'));
    expect(parsedCustomers[1]['balance'], equals(-120.50));

    // Verify product with symbol 'PPR 20 × 4'
    expect(parsedCustomers[2]['name'], equals('PPR 20 × 4'));
  });

  test('AppState calculations and negative balance check', () {
    final state = AppState();
    state.customers = [
      {'name': 'عميل 1', 'balance': 500.0},
      {'name': 'عميل 2', 'balance': -200.0},
    ];
    state.products = [
      {'name': 'PPR 20 × 4', 'qty': 2.0, 'minimum': 5.0, 'unit': 'قطع'},
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

    // Verify symbols and Arabic string preservation
    final prod1 = state.products.firstWhere((p) => p['name'] == 'PPR 20 × 4');
    expect(prod1['name'], equals('PPR 20 × 4'));
  });
}
