import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_assistant/main.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<List<int>> createRealSamplePdf() async {
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

  test('PdfTextExtractor and PdfRowParser pipeline with real PDF file',
      () async {
    final pdfBytes = await createRealSamplePdf();
    final file = File('test/fixtures/sample.pdf');
    await file.writeAsBytes(pdfBytes);

    expect(file.existsSync(), isTrue);

    final extracted = PdfTextExtractor.extractTextFromPdf(pdfBytes);
    expect(extracted['success'], isTrue);
    expect(extracted['pageCount'], equals(1));
    expect((extracted['charCount'] as int) > 0, isTrue);

    final rawText = extracted['text'] as String;
    expect(rawText, isNotEmpty);

    final customerRows = PdfRowParser.parseRows(rawText, 'customers');
    expect(customerRows, isList);

    final productRows = PdfRowParser.parseRows(rawText, 'products');
    expect(productRows, isList);
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

  test('ImportMapper Arabic normalization and string matching', () {
    expect(ImportMapper.normalizeName('أحمد'), equals('احمد'));
    expect(ImportMapper.normalizeName('مؤسسة الأمل'), equals('مؤسسه الامل'));
    expect(ImportMapper.isMatch('أحمد  مُحَمَّد', 'احمد محمد'), isTrue);
  });

  test('Full end-to-end SQLite persistence test: PDF extraction to DB write and reopen', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 2,
      onCreate: (d, v) async {
        await d.execute(
          'CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, balance REAL DEFAULT 0, notes TEXT, created TEXT)',
        );
        await d.execute(
          'CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT, qty REAL DEFAULT 0, minimum REAL DEFAULT 0, unit TEXT DEFAULT "قطعة", price REAL DEFAULT 0, created TEXT)',
        );
      },
    );

    final pdfBytes = await createRealSamplePdf();
    final extractionResult = PdfTextExtractor.extractTextFromPdf(pdfBytes);
    expect(extractionResult['success'], isTrue);

    final extractedText = extractionResult['text'] as String;
    final customerRows = PdfRowParser.parseRows(extractedText, 'customers');
    expect(customerRows.length, greaterThanOrEqualTo(2));

    for (var r in customerRows) {
      r['action'] = 'add';
    }

    final saveStats = await SQLiteImportService.saveRowsToDb(
      db: db,
      type: 'customers',
      rows: customerRows,
    );

    expect(saveStats['inserted'], equals(customerRows.length));
    expect(saveStats['errors'], equals(0));

    final queriedBeforeClose = await db.query('customers');
    expect(queriedBeforeClose.length, equals(customerRows.length));

    await db.close();
  });
}
