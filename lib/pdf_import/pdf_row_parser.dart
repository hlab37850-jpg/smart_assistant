import 'pdf_text_extractor.dart';

class PdfParsedRow {
  final Map<String, dynamic> data;
  final bool requiresReview;
  final String? reviewReason;

  PdfParsedRow({
    required this.data,
    this.requiresReview = false,
    this.reviewReason,
  });
}

class PdfRowParser {
  static List<PdfParsedRow> parse(
      PdfExtractionResult extractionResult, String type) {
    if (extractionResult.isScanned || extractionResult.lines.isEmpty) {
      if (extractionResult.rawText.isNotEmpty) {
        return _parseFromRawTextFallback(extractionResult.rawText, type);
      }
      return [];
    }

    final List<PdfParsedRow> rows = [];

    final Map<int, List<PdfExtractionLine>> pageLinesMap = {};
    for (final line in extractionResult.lines) {
      pageLinesMap.putIfAbsent(line.pageIndex, () => []).add(line);
    }

    for (final pageLines in pageLinesMap.values) {
      final List<List<PdfExtractionLine>> rowClusters = [];
      const double yTolerance = 5.0;

      for (final line in pageLines) {
        bool added = false;
        for (final cluster in rowClusters) {
          final avgY =
              cluster.map((e) => e.y).reduce((a, b) => a + b) / cluster.length;
          if ((line.y - avgY).abs() <= yTolerance) {
            cluster.add(line);
            added = true;
            break;
          }
        }
        if (!added) {
          rowClusters.add([line]);
        }
      }

      rowClusters.sort((a, b) {
        final avgYA = a.map((e) => e.y).reduce((x, y) => x + y) / a.length;
        final avgYB = b.map((e) => e.y).reduce((x, y) => x + y) / b.length;
        return avgYA.compareTo(avgYB);
      });

      for (final cluster in rowClusters) {
        cluster.sort((a, b) => a.x.compareTo(b.x));

        final lineText = cluster.map((l) => l.text.trim()).join(' ').trim();
        if (lineText.isEmpty) continue;

        final lowerText = lineText.toLowerCase();
        if (lowerText.contains('name') ||
            lineText.contains('الاسم') ||
            lineText.contains('الصنف') ||
            lowerText.contains('phone') ||
            lowerText.contains('category')) {
          continue;
        }

        final parts = lineText
            .split(RegExp(r'[,;\t|]'))
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();

        if (type == 'customers') {
          if (parts.length >= 2) {
            final name = parts[0];
            final phone = parts[1];
            final balStr = parts.length > 2
                ? parts[2].replaceAll(RegExp(r'[^\d.-]'), '')
                : '0';
            final notes = parts.length > 3 ? parts[3] : '';

            final bal = double.tryParse(balStr);
            bool review = false;
            String? reason;
            if (bal == null && parts.length > 2) {
              review = true;
              reason = 'Uncertain balance format: "${parts[2]}"';
            }

            rows.add(
              PdfParsedRow(
                data: {
                  'name': name,
                  'phone': phone,
                  'balance': bal ?? 0.0,
                  'notes': notes,
                },
                requiresReview: review,
                reviewReason: reason,
              ),
            );
          } else {
            final doubleSpaces = lineText
                .split(RegExp(r'\s{2,}'))
                .map((p) => p.trim())
                .where((p) => p.isNotEmpty)
                .toList();
            if (doubleSpaces.length >= 2) {
              final name = doubleSpaces[0];
              final phone = doubleSpaces[1];
              final balStr = doubleSpaces.length > 2
                  ? doubleSpaces[2].replaceAll(RegExp(r'[^\d.-]'), '')
                  : '0';
              final notes = doubleSpaces.length > 3 ? doubleSpaces[3] : '';

              rows.add(
                PdfParsedRow(
                  data: {
                    'name': name,
                    'phone': phone,
                    'balance': double.tryParse(balStr) ?? 0.0,
                    'notes': notes,
                  },
                ),
              );
            } else {
              rows.add(
                PdfParsedRow(
                  data: {
                    'name': lineText,
                    'phone': '',
                    'balance': 0.0,
                    'notes': '',
                  },
                  requiresReview: true,
                  reviewReason: 'Single text segment without clear fields',
                ),
              );
            }
          }
        } else {
          if (parts.length >= 2) {
            final name = parts[0];
            final category = parts[1];
            final qtyStr = parts.length > 2
                ? parts[2].replaceAll(RegExp(r'[^\d.-]'), '')
                : '0';
            final minStr = parts.length > 3
                ? parts[3].replaceAll(RegExp(r'[^\d.-]'), '')
                : '5';
            final priceStr = parts.length > 4
                ? parts[4].replaceAll(RegExp(r'[^\d.-]'), '')
                : '0';
            final unit = parts.length > 5 ? parts[5] : 'قطعة';

            rows.add(
              PdfParsedRow(
                data: {
                  'name': name,
                  'category': category.isEmpty ? 'عام' : category,
                  'qty': double.tryParse(qtyStr) ?? 0.0,
                  'minimum': double.tryParse(minStr) ?? 5.0,
                  'price': double.tryParse(priceStr) ?? 0.0,
                  'unit': unit.isEmpty ? 'قطعة' : unit,
                },
              ),
            );
          } else {
            final doubleSpaces = lineText
                .split(RegExp(r'\s{2,}'))
                .map((p) => p.trim())
                .where((p) => p.isNotEmpty)
                .toList();

            if (doubleSpaces.length >= 2) {
              final name = doubleSpaces[0];
              final category = doubleSpaces[1];
              final qtyStr = doubleSpaces.length > 2
                  ? doubleSpaces[2].replaceAll(RegExp(r'[^\d.-]'), '')
                  : '0';
              final minStr = doubleSpaces.length > 3
                  ? doubleSpaces[3].replaceAll(RegExp(r'[^\d.-]'), '')
                  : '5';
              final priceStr = doubleSpaces.length > 4
                  ? doubleSpaces[4].replaceAll(RegExp(r'[^\d.-]'), '')
                  : '0';
              final unit = doubleSpaces.length > 5 ? doubleSpaces[5] : 'قطعة';

              rows.add(
                PdfParsedRow(
                  data: {
                    'name': name,
                    'category': category.isEmpty ? 'عام' : category,
                    'qty': double.tryParse(qtyStr) ?? 0.0,
                    'minimum': double.tryParse(minStr) ?? 5.0,
                    'price': double.tryParse(priceStr) ?? 0.0,
                    'unit': unit.isEmpty ? 'قطعة' : unit,
                  },
                ),
              );
            } else {
              rows.add(
                PdfParsedRow(
                  data: {
                    'name': lineText,
                    'category': 'عام',
                    'qty': 0.0,
                    'minimum': 5.0,
                    'price': 0.0,
                    'unit': 'قطعة',
                  },
                  requiresReview: true,
                  reviewReason: 'Single product string without clear fields',
                ),
              );
            }
          }
        }
      }
    }

    return rows;
  }

  static List<PdfParsedRow> _parseFromRawTextFallback(
      String rawText, String type) {
    final List<PdfParsedRow> list = [];
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (final line in lines) {
      final parts = line
          .split(RegExp(r'[,;\t|]'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      if (parts.isEmpty) continue;

      final name = parts[0];
      if (name.isEmpty ||
          name.toLowerCase().contains('name') ||
          name.contains('الاسم') ||
          name.contains('الصنف')) {
        continue;
      }

      if (type == 'customers') {
        final balStr = parts.length > 2
            ? parts[2].replaceAll(RegExp(r'[^\d.-]'), '')
            : '0';
        list.add(
          PdfParsedRow(
            data: {
              'name': name,
              'phone': parts.length > 1 ? parts[1] : '',
              'balance': double.tryParse(balStr) ?? 0.0,
              'notes': parts.length > 3 ? parts[3] : '',
            },
          ),
        );
      } else {
        final qtyStr = parts.length > 2
            ? parts[2].replaceAll(RegExp(r'[^\d.-]'), '')
            : '0';
        final minStr = parts.length > 3
            ? parts[3].replaceAll(RegExp(r'[^\d.-]'), '')
            : '5';
        final priceStr = parts.length > 4
            ? parts[4].replaceAll(RegExp(r'[^\d.-]'), '')
            : '0';
        final unit = parts.length > 5 ? parts[5] : 'قطعة';

        list.add(
          PdfParsedRow(
            data: {
              'name': name,
              'category':
                  parts.length > 1 && parts[1].isNotEmpty ? parts[1] : 'عام',
              'qty': double.tryParse(qtyStr) ?? 0.0,
              'minimum': double.tryParse(minStr) ?? 5.0,
              'price': double.tryParse(priceStr) ?? 0.0,
              'unit': unit.isEmpty ? 'قطعة' : unit,
            },
          ),
        );
      }
    }
    return list;
  }
}
