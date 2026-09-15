import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_assistant/main.dart';
import 'package:smart_assistant/pdf_import/pdf_text_extractor.dart';
import 'package:smart_assistant/pdf_import/pdf_row_parser.dart';
import 'package:smart_assistant/pdf_import/pdf_import_mapper.dart';
import 'package:smart_assistant/pdf_import/pdf_import_service.dart';

Future<List<int>> createCustomersPdfBytes() async {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      build: (pw.Context context) {
        return pw.Column(
          children: [
            pw.Text('Sharekat Al Amal,0501112223,500.00,Regular Customer'),
            pw.Text('Mouassasat Al Najah,0503334445,-250.75,Credit Customer'),
            pw.Text('Ahmad Mahmoud,0509998887,1250.50,VIP'),
          ],
        );
      },
    ),
  );
  pdf.addPage(
    pw.Page(
      build: (pw.Context context) {
        return pw.Column(
          children: [
            pw.Text('Sami Al Hassan,0504445556,-100.00,Page 2 Customer'),
          ],
        );
      },
    ),
  );
  return await pdf.save();
}

Future<List<int>> createProductsPdfBytes() async {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      build: (pw.Context context) {
        return pw.Column(
          children: [
            pw.Text('PPR 20 × 4,Plumbing,100,10,45.5,Meter'),
            pw.Text('Copper Wire 2.5mm,Electrical,250,20,12.0,Roll'),
          ],
        );
      },
    ),
  );
  return await pdf.save();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    final custPdf = await createCustomersPdfBytes();
    await File('test/fixtures/sample_customers.pdf').writeAsBytes(custPdf);

    final prodPdf = await createProductsPdfBytes();
    await File('test/fixtures/sample_products.pdf').writeAsBytes(prodPdf);
  });

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

  test('PdfImportMapper Arabic normalization and string matching', () {
    expect(PdfImportMapper.normalizeName('أحمد'), equals('احمد'));
    expect(PdfImportMapper.normalizeName('مؤسسة الأمل'), equals('مؤسسه الامل'));
    expect(PdfImportMapper.isMatch('أحمد  مُحَمَّد', 'احمد محمد'), isTrue);
  });

  test(
      'E2E PDF Customer Pipeline with Multi-Page, Negative Balance & SQLite Persistence',
      () async {
    final bytes =
        await File('test/fixtures/sample_customers.pdf').readAsBytes();

    final extraction = PdfTextExtractor.extractFromBytes(bytes);
    expect(extraction.isScanned, isFalse);
    expect(extraction.pageCount, equals(2));

    final parsedRows = PdfRowParser.parse(extraction, 'customers');
    expect(parsedRows.length, greaterThanOrEqualTo(4));

    final negRow = parsedRows.firstWhere(
        (r) => r.data['name'].toString().contains('Mouassasat Al Najah'));
    expect(negRow.data['balance'], equals(-250.75));

    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 2,
      onCreate: (d, v) async {
        await d.execute(
          'CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, balance REAL DEFAULT 0, notes TEXT, created TEXT)',
        );
      },
    );

    final List<Map<String, dynamic>> importPayload = parsedRows.map((r) {
      final map = Map<String, dynamic>.from(r.data);
      map['action'] = 'add';
      return map;
    }).toList();

    final stats = await PdfImportService.saveRowsToDb(
      db: db,
      type: 'customers',
      rows: importPayload,
    );

    expect(stats.inserted, equals(parsedRows.length));
    expect(stats.errors, equals(0));

    final initialQuery = await PdfImportService.queryAll(db, 'customers');
    expect(initialQuery.length, equals(parsedRows.length));

    final updatePayload = [
      {
        'name': 'Mouassasat Al Najah',
        'phone': '0503334445',
        'balance': -300.0,
        'notes': 'Updated Balance',
        'action': 'update',
      }
    ];

    final updateStats = await PdfImportService.saveRowsToDb(
      db: db,
      type: 'customers',
      rows: updatePayload,
    );

    expect(updateStats.updated, equals(1));

    final requery = await PdfImportService.queryAll(db, 'customers');
    final updatedItem = requery.firstWhere(
        (r) => r['name'].toString().contains('Mouassasat Al Najah'));
    expect(updatedItem['balance'], equals(-300.0));

    await db.close();
  });

  test('E2E PDF Product Pipeline with PPR 20 × 4, Symbols & SQLite Persistence',
      () async {
    final bytes = await File('test/fixtures/sample_products.pdf').readAsBytes();

    final extraction = PdfTextExtractor.extractFromBytes(bytes);
    expect(extraction.isScanned, isFalse);
    expect(extraction.pageCount, equals(1));

    final parsedRows = PdfRowParser.parse(extraction, 'products');
    expect(parsedRows.length, greaterThanOrEqualTo(2));

    final pprRow = parsedRows
        .firstWhere((r) => r.data['name'].toString().contains('PPR 20 × 4'));
    expect(pprRow.data['name'], equals('PPR 20 × 4'));
    expect(pprRow.data['category'], equals('Plumbing'));
    expect(pprRow.data['qty'], equals(100.0));
    expect(pprRow.data['price'], equals(45.5));

    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 2,
      onCreate: (d, v) async {
        await d.execute(
          'CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT, qty REAL DEFAULT 0, minimum REAL DEFAULT 0, unit TEXT DEFAULT "قطعة", price REAL DEFAULT 0, created TEXT)',
        );
      },
    );

    final List<Map<String, dynamic>> importPayload = parsedRows.map((r) {
      final map = Map<String, dynamic>.from(r.data);
      map['action'] = 'add';
      return map;
    }).toList();

    final stats = await PdfImportService.saveRowsToDb(
      db: db,
      type: 'products',
      rows: importPayload,
    );

    expect(stats.inserted, equals(parsedRows.length));
    expect(stats.errors, equals(0));

    final queriedProds = await PdfImportService.queryAll(db, 'products');
    expect(queriedProds.length, equals(parsedRows.length));

    final dbPpr = queriedProds
        .firstWhere((p) => p['name'].toString().contains('PPR 20 × 4'));
    expect(dbPpr['name'], equals('PPR 20 × 4'));

    await db.close();
  });
}
