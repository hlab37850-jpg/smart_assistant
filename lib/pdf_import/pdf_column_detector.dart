import 'pdf_text_extractor.dart';

class PdfColumnBoundary {
  final String name;
  final double startX;
  final double endX;

  PdfColumnBoundary({
    required this.name,
    required this.startX,
    required this.endX,
  });
}

class PdfColumnDetector {
  static List<PdfColumnBoundary> detectColumns(
      List<PdfExtractionLine> lines, String type) {
    if (lines.isEmpty) return [];

    double minX = double.infinity;
    double maxX = 0;

    for (final l in lines) {
      if (l.x < minX) minX = l.x;
      if (l.x + l.width > maxX) maxX = l.x + l.width;
    }

    if (minX == double.infinity || maxX <= minX) {
      minX = 0;
      maxX = 500;
    }

    final totalWidth = maxX - minX;

    if (type == 'customers') {
      final colWidth = totalWidth / 4;
      return [
        PdfColumnBoundary(
            name: 'name', startX: minX, endX: minX + colWidth * 1.5),
        PdfColumnBoundary(
            name: 'phone',
            startX: minX + colWidth * 1.5,
            endX: minX + colWidth * 2.5),
        PdfColumnBoundary(
            name: 'balance',
            startX: minX + colWidth * 2.5,
            endX: minX + colWidth * 3.3),
        PdfColumnBoundary(
            name: 'notes', startX: minX + colWidth * 3.3, endX: maxX + 100),
      ];
    } else {
      final colWidth = totalWidth / 6;
      return [
        PdfColumnBoundary(
            name: 'name', startX: minX, endX: minX + colWidth * 1.8),
        PdfColumnBoundary(
            name: 'category',
            startX: minX + colWidth * 1.8,
            endX: minX + colWidth * 3.0),
        PdfColumnBoundary(
            name: 'qty',
            startX: minX + colWidth * 3.0,
            endX: minX + colWidth * 3.8),
        PdfColumnBoundary(
            name: 'minimum',
            startX: minX + colWidth * 3.8,
            endX: minX + colWidth * 4.6),
        PdfColumnBoundary(
            name: 'price',
            startX: minX + colWidth * 4.6,
            endX: minX + colWidth * 5.4),
        PdfColumnBoundary(
            name: 'unit', startX: minX + colWidth * 5.4, endX: maxX + 100),
      ];
    }
  }
}
