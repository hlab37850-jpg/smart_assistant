class PdfImportMapper {
  static String normalizeName(String input) {
    return input
        .replaceAll(RegExp(r'[\u064B-\u0652]'), '')
        .replaceAll(RegExp(r'[أإآا]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  static bool isMatch(String name1, String name2) {
    return normalizeName(name1) == normalizeName(name2);
  }
}
