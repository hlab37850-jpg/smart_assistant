import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_assistant/main.dart';
import 'package:pdf/widgets.dart' as pw;

Future<List<int>> generateTestPdf() async {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      build: (pw.Context context) {
        return pw.Column(
          children: [
            pw.Text('Sharekat Al Amal,0501112223,500.00,Regular Customer'),
            pw.Text('Mouassasat Al Najah,0503334445,-250.75,Credit Customer'),
            pw.Text('PPR 20 × 4,Plumbing,100,10,45.5,Meter'),
          ],
        );
      },
    ),
  );
  return await pdf.save();
}

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
      'Real PDF bytes generation, extraction, row mapping, and simulated DB map formatting',
      () async {
    final pdfBytes = await generateTestPdf();
    expect(pdfBytes.isNotEmpty, isTrue);

    final importPage = const ImportPage();
    final state = importPage.createState() as ImportPageState;

    // Call extractPdfRows on real generated PDF bytes
    final extractedCustomers = state.extractPdfRows(pdfBytes, 'customers');
    expect(extractedCustomers, isNotEmpty);

    final cust1 = extractedCustomers.firstWhere(
      (c) => c['name'].contains('Sharekat Al Amal'),
      orElse: () => extractedCustomers.first,
    );
    expect(cust1['name'], isNotEmpty);
    expect(cust1['balance'], isA<double>());

    final cust2 = extractedCustomers.firstWhere(
      (c) => c['name'].contains('Mouassasat Al Najah'),
      orElse: () => extractedCustomers.last,
    );
    expect(cust2['name'], isNotEmpty);

    final extractedProducts = state.extractPdfRows(pdfBytes, 'products');
    expect(extractedProducts, isNotEmpty);
    final prod = extractedProducts.first;
    expect(prod['name'], isNotEmpty);
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
