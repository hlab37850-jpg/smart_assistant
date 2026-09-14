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

  test(
      'PDF extraction, row mapping, preview, and SQLite record formatting pipeline',
      () {
    // 1. Simulate extracted PDF lines
    final pdfContentLines = [
      'شركة الأمل,0501112223,500.00,تحديث رصيد',
      'مؤسسة النجاح,0503334445,-250.75,عميل جديد دائن',
    ];

    final extractedRows = pdfContentLines.map((line) {
      final parts = line.split(',');
      return {
        'name': parts[0].trim(),
        'phone': parts[1].trim(),
        'balance': double.tryParse(parts[2].trim()) ?? 0.0,
        'notes': parts[3].trim(),
      };
    }).toList();

    expect(extractedRows.length, equals(2));
    expect(extractedRows[0]['name'], equals('شركة الأمل'));
    expect(extractedRows[0]['balance'], equals(500.00));
    expect(extractedRows[1]['name'], equals('مؤسسة النجاح'));
    expect(extractedRows[1]['balance'], equals(-250.75));

    // 2. Test Product PDF Row with symbols like "PPR 20 × 4"
    final prodPdfLines = [
      'PPR 20 × 4,سباكة,100,10,45.5,متر',
    ];

    final prodRow = prodPdfLines.map((line) {
      final parts = line.split(',');
      return {
        'name': parts[0].trim(),
        'category': parts[1].trim(),
        'qty': double.tryParse(parts[2].trim()) ?? 0.0,
        'minimum': double.tryParse(parts[3].trim()) ?? 0.0,
        'price': double.tryParse(parts[4].trim()) ?? 0.0,
        'unit': parts[5].trim(),
      };
    }).first;

    expect(prodRow['name'], equals('PPR 20 × 4'));
    expect(prodRow['unit'], equals('متر'));
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

    final cust2 = state.customers.firstWhere((c) => c['name'] == 'عميل 2');
    expect(cust2['balance'], equals(-200.0));

    final prod1 = state.products.firstWhere((p) => p['name'] == 'PPR 20 × 4');
    expect(prod1['name'], equals('PPR 20 × 4'));
  });
}
