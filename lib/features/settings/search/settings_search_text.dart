/// Latin letters with diacritics folded to their base letter, so "cafe" finds
/// "café" and "uber" finds "über". Everything else (CJK, Arabic, Cyrillic, ...)
/// is left untouched.
const Map<String, String> _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'ç': 'c', 'ć': 'c', 'č': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ě': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
  'š': 's', 'ś': 's', 'ß': 'ss',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ž': 'z', 'ź': 'z', 'ż': 'z',
};

final RegExp _notWordChar = RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true);
final RegExp _whitespace = RegExp(r'\s+');

/// Lower-cases [input], folds Latin diacritics, drops punctuation and collapses
/// whitespace. Both the query and the searchable text go through this.
String normalizeSearchText(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_fold[ch] ?? ch);
  }
  return buffer
      .toString()
      .replaceAll(_notWordChar, ' ')
      .replaceAll(_whitespace, ' ')
      .trim();
}
