import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

class PdfExtractionLine {
  final int pageIndex;
  final String text;
  final double x;
  final double y;
  final double width;
  final double height;
  final List<PdfExtractionWord> words;

  PdfExtractionLine({
    required this.pageIndex,
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.words,
  });
}

class PdfExtractionWord {
  final String text;
  final double x;
  final double y;
  final double width;
  final double height;

  PdfExtractionWord({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class PdfExtractionResult {
  final bool isScanned;
  final int pageCount;
  final List<PdfExtractionLine> lines;
  final String rawText;
  final String? error;

  PdfExtractionResult({
    required this.isScanned,
    required this.pageCount,
    required this.lines,
    required this.rawText,
    this.error,
  });
}

class PdfTextExtractor {
  static PdfExtractionResult extractFromBytes(List<int> bytes) {
    try {
      final sf.PdfDocument document = sf.PdfDocument(inputBytes: bytes);
      final sf.PdfTextExtractor extractor = sf.PdfTextExtractor(document);
      final int pageCount = document.pages.count;
      final List<PdfExtractionLine> allLines = [];
      final StringBuffer rawBuffer = StringBuffer();

      for (int i = 0; i < pageCount; i++) {
        final List textLines = extractor.extractTextLines(startPageIndex: i);

        for (final line in textLines) {
          final lineText = line.text.trim();
          if (lineText.isNotEmpty) {
            rawBuffer.writeln(lineText);
          }

          final List<PdfExtractionWord> words = [];
          for (final w in line.wordCollection) {
            words.add(
              PdfExtractionWord(
                text: w.text,
                x: w.bounds.left,
                y: w.bounds.top,
                width: w.bounds.width,
                height: w.bounds.height,
              ),
            );
          }

          allLines.add(
            PdfExtractionLine(
              pageIndex: i,
              text: line.text,
              x: line.bounds.left,
              y: line.bounds.top,
              width: line.bounds.width,
              height: line.bounds.height,
              words: words,
            ),
          );
        }
      }

      final String fullText = rawBuffer.toString();
      final bool isScanned =
          pageCount > 0 && allLines.isEmpty && fullText.trim().isEmpty;

      document.dispose();

      return PdfExtractionResult(
        isScanned: isScanned,
        pageCount: pageCount,
        lines: allLines,
        rawText: fullText,
      );
    } catch (e, st) {
      debugPrint('PdfTextExtractor error: $e\n$st');
      return PdfExtractionResult(
        isScanned: false,
        pageCount: 0,
        lines: [],
        rawText: '',
        error: e.toString(),
      );
    }
  }
}
