import 'package:sqflite/sqflite.dart';
import 'pdf_import_mapper.dart';

class PdfImportResult {
  final int inserted;
  final int updated;
  final int ignored;
  final int errors;
  final List<String> logs;

  PdfImportResult({
    required this.inserted,
    required this.updated,
    required this.ignored,
    required this.errors,
    required this.logs,
  });
}

class PdfImportService {
  static Future<PdfImportResult> saveRowsToDb({
    required Database db,
    required String type,
    required List<Map<String, dynamic>> rows,
  }) async {
    int insertedCount = 0;
    int updatedCount = 0;
    int ignoredCount = 0;
    int errorCount = 0;
    final List<String> errorLogs = [];

    await db.transaction((txn) async {
      for (final row in rows) {
        final act = row['action'];
        if (act == 'ignore') {
          ignoredCount++;
          continue;
        }

        final String originalName = (row['name'] as String).trim();

        try {
          if (type == 'customers') {
            if (act == 'add') {
              await txn.insert('customers', {
                'name': originalName,
                'phone': row['phone'] ?? '',
                'balance': row['balance'] ?? 0.0,
                'notes': row['notes'] ?? '',
                'created': DateTime.now().toIso8601String(),
              });
              insertedCount++;
            } else if (act == 'update') {
              final existingRows = await txn.query('customers');
              int? targetId;
              for (final ex in existingRows) {
                final exName = (ex['name'] as String).trim();
                if (PdfImportMapper.isMatch(exName, originalName)) {
                  targetId = ex['id'] as int?;
                  break;
                }
              }

              if (targetId != null) {
                final affected = await txn.update(
                  'customers',
                  {
                    'phone': row['phone'] ?? '',
                    'balance': row['balance'] ?? 0.0,
                    'notes': row['notes'] ?? '',
                  },
                  where: 'id = ?',
                  whereArgs: [targetId],
                );
                if (affected > 0) {
                  updatedCount++;
                } else {
                  await txn.insert('customers', {
                    'name': originalName,
                    'phone': row['phone'] ?? '',
                    'balance': row['balance'] ?? 0.0,
                    'notes': row['notes'] ?? '',
                    'created': DateTime.now().toIso8601String(),
                  });
                  insertedCount++;
                }
              } else {
                await txn.insert('customers', {
                  'name': originalName,
                  'phone': row['phone'] ?? '',
                  'balance': row['balance'] ?? 0.0,
                  'notes': row['notes'] ?? '',
                  'created': DateTime.now().toIso8601String(),
                });
                insertedCount++;
              }
            }
          } else {
            if (act == 'add') {
              await txn.insert('products', {
                'name': originalName,
                'category': row['category'] ?? 'عام',
                'qty': row['qty'] ?? 0.0,
                'minimum': row['minimum'] ?? 5.0,
                'price': row['price'] ?? 0.0,
                'unit': row['unit'] ?? 'قطعة',
                'created': DateTime.now().toIso8601String(),
              });
              insertedCount++;
            } else if (act == 'update') {
              final existingRows = await txn.query('products');
              int? targetId;
              for (final ex in existingRows) {
                final exName = (ex['name'] as String).trim();
                if (PdfImportMapper.isMatch(exName, originalName)) {
                  targetId = ex['id'] as int?;
                  break;
                }
              }

              if (targetId != null) {
                final affected = await txn.update(
                  'products',
                  {
                    'category': row['category'] ?? 'عام',
                    'qty': row['qty'] ?? 0.0,
                    'minimum': row['minimum'] ?? 5.0,
                    'price': row['price'] ?? 0.0,
                    'unit': row['unit'] ?? 'قطعة',
                  },
                  where: 'id = ?',
                  whereArgs: [targetId],
                );
                if (affected > 0) {
                  updatedCount++;
                } else {
                  await txn.insert('products', {
                    'name': originalName,
                    'category': row['category'] ?? 'عام',
                    'qty': row['qty'] ?? 0.0,
                    'minimum': row['minimum'] ?? 5.0,
                    'price': row['price'] ?? 0.0,
                    'unit': row['unit'] ?? 'قطعة',
                    'created': DateTime.now().toIso8601String(),
                  });
                  insertedCount++;
                }
              } else {
                await txn.insert('products', {
                  'name': originalName,
                  'category': row['category'] ?? 'عام',
                  'qty': row['qty'] ?? 0.0,
                  'minimum': row['minimum'] ?? 5.0,
                  'price': row['price'] ?? 0.0,
                  'unit': row['unit'] ?? 'قطعة',
                  'created': DateTime.now().toIso8601String(),
                });
                insertedCount++;
              }
            }
          }
        } catch (e) {
          errorCount++;
          errorLogs.add('Failed to save record "$originalName": $e');
        }
      }
    });

    return PdfImportResult(
      inserted: insertedCount,
      updated: updatedCount,
      ignored: ignoredCount,
      errors: errorCount,
      logs: errorLogs,
    );
  }

  static Future<List<Map<String, dynamic>>> queryAll(
      Database db, String type) async {
    if (type == 'customers') {
      return await db.query('customers', orderBy: 'id ASC');
    } else {
      return await db.query('products', orderBy: 'id ASC');
    }
  }
}
