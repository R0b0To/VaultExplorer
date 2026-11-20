import 'dart:convert';
import 'dart:typed_data';

/// Text helpers shared by the tag readers.
class TagText {
  TagText._();

  /// Trims [s], strips NULs and byte-order marks, and returns null when
  /// nothing is left.
  static String? clean(String? s) {
    if (s == null) return null;
    final stripped = s.replaceAll('\u0000', '').replaceAll('\uFEFF', '').trim();
    return stripped.isEmpty ? null : stripped;
  }

  static String latin1(Uint8List b, int start, int end) {
    if (start >= end) return '';
    return String.fromCharCodes(b.sublist(start, end));
  }

  static String utf8Lenient(Uint8List b, int start, int end) {
    if (start >= end) return '';
    return utf8.decode(b.sublist(start, end), allowMalformed: true);
  }

  /// UTF-16 with an optional BOM; [defaultBigEndian] applies without one.
  static String utf16(
    Uint8List b,
    int start,
    int end, {
    bool defaultBigEndian = false,
  }) {
    var s = start;
    var big = defaultBigEndian;
    if (end - s >= 2) {
      if (b[s] == 0xFF && b[s + 1] == 0xFE) {
        big = false;
        s += 2;
      } else if (b[s] == 0xFE && b[s + 1] == 0xFF) {
        big = true;
        s += 2;
      }
    }
    final units = <int>[];
    for (var i = s; i + 1 < end; i += 2) {
      units.add(big ? (b[i] << 8) | b[i + 1] : b[i] | (b[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }

  /// Decodes an ID3v2 text field: byte [start] is the encoding, the rest is
  /// the text. Returns every NUL-separated value (ID3v2.4 multi-value
  /// strings), blanks removed.
  static List<String> id3Values(Uint8List b, int start, int end) {
    if (start >= end) return const [];
    final enc = b[start];
    final from = start + 1;
    final String text;
    switch (enc) {
      case 0:
        text = latin1(b, from, end);
      case 1:
        text = utf16(b, from, end);
      case 2:
        text = utf16(b, from, end, defaultBigEndian: true);
      case 3:
        text = utf8Lenient(b, from, end);
      default:
        text = latin1(b, from, end);
    }
    return splitNuls(text);
  }

  static List<String> splitNuls(String text) {
    final out = <String>[];
    for (final part in text.split('\u0000')) {
      final c = clean(part);
      if (c != null) out.add(c);
    }
    return out;
  }

  /// First run of digits in [s], 0 when there is none.
  static int leadingInt(String? s) {
    if (s == null) return 0;
    final m = RegExp(r'\d+').firstMatch(s);
    if (m == null) return 0;
    return int.tryParse(m.group(0)!) ?? 0;
  }

  /// "3/12" -> (3, 12); "3" -> (3, 0).
  static (int, int) numberPair(String? s) {
    if (s == null) return (0, 0);
    final parts = s.split('/');
    final a = leadingInt(parts[0]);
    final b = parts.length > 1 ? leadingInt(parts[1]) : 0;
    return (a, b);
  }

  /// First plausible four-digit year in [s] ("2004", "2004-05-06", ...), else 0.
  static int year(String? s) {
    if (s == null) return 0;
    final m = RegExp(r'(?<!\d)([12]\d{3})(?!\d)').firstMatch(s);
    if (m == null) return 0;
    return int.tryParse(m.group(1)!) ?? 0;
  }

  /// Resolves ID3 genre references: "(17)", "17", "(17)Rock", "(RX)".
  static String? genre(String? raw) {
    final s = clean(raw);
    if (s == null) return null;
    final paren = RegExp(r'^\((\d{1,3})\)\s*(.*)$').firstMatch(s);
    if (paren != null) {
      final rest = clean(paren.group(2));
      if (rest != null) return rest;
      return id3GenreByIndex(int.tryParse(paren.group(1)!) ?? -1) ?? s;
    }
    if (s == '(RX)') return 'Remix';
    if (s == '(CR)') return 'Cover';
    if (RegExp(r'^\d{1,3}$').hasMatch(s)) {
      return id3GenreByIndex(int.parse(s)) ?? s;
    }
    return s;
  }

  static String? id3GenreByIndex(int i) =>
      i >= 0 && i < id3Genres.length ? id3Genres[i] : null;

  /// The ID3v1 genre list plus the Winamp extensions.
  static const List<String> id3Genres = [
    'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco', 'Funk', 'Grunge',
    'Hip-Hop', 'Jazz', 'Metal', 'New Age', 'Oldies', 'Other', 'Pop', 'R&B',
    'Rap', 'Reggae', 'Rock', 'Techno', 'Industrial', 'Alternative', 'Ska',
    'Death Metal', 'Pranks', 'Soundtrack', 'Euro-Techno', 'Ambient',
    'Trip-Hop', 'Vocal', 'Jazz+Funk', 'Fusion', 'Trance', 'Classical',
    'Instrumental', 'Acid', 'House', 'Game', 'Sound Clip', 'Gospel', 'Noise',
    'Alternative Rock', 'Bass', 'Soul', 'Punk', 'Space', 'Meditative',
    'Instrumental Pop', 'Instrumental Rock', 'Ethnic', 'Gothic', 'Darkwave',
    'Techno-Industrial', 'Electronic', 'Pop-Folk', 'Eurodance', 'Dream',
    'Southern Rock', 'Comedy', 'Cult', 'Gangsta', 'Top 40', 'Christian Rap',
    'Pop/Funk', 'Jungle', 'Native American', 'Cabaret', 'New Wave',
    'Psychedelic', 'Rave', 'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal',
    'Acid Punk', 'Acid Jazz', 'Polka', 'Retro', 'Musical', 'Rock & Roll',
    'Hard Rock', 'Folk', 'Folk-Rock', 'National Folk', 'Swing', 'Fast Fusion',
    'Bebop', 'Latin', 'Revival', 'Celtic', 'Bluegrass', 'Avantgarde',
    'Gothic Rock', 'Progressive Rock', 'Psychedelic Rock', 'Symphonic Rock',
    'Slow Rock', 'Big Band', 'Chorus', 'Easy Listening', 'Acoustic', 'Humour',
    'Speech', 'Chanson', 'Opera', 'Chamber Music', 'Sonata', 'Symphony',
    'Booty Bass', 'Primus', 'Porn Groove', 'Satire', 'Slow Jam', 'Club',
    'Tango', 'Samba', 'Folklore', 'Ballad', 'Power Ballad', 'Rhythmic Soul',
    'Freestyle', 'Duet', 'Punk Rock', 'Drum Solo', 'A cappella', 'Euro-House',
    'Dance Hall',
  ];
}
