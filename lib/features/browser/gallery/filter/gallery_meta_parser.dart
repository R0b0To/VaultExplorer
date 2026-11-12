import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'gallery_meta.dart';

/// Reads the gallery's per-photo facts (date taken, GPS, camera, keywords,
/// rating) out of the start of an image file: EXIF in JPEG, PNG and WebP, and
/// XMP in all three.
///
/// Pure and synchronous: give it the first [headerBytes] of the file. Never
/// throws; anything it cannot read is simply missing from the result. HEIC,
/// AVIF, TIFF and RAW containers are not read (their metadata sits in boxes
/// or IFD chains this reader does not walk), so they come back [GalleryMeta.empty].
class GalleryMetaParser {
  const GalleryMetaParser._();

  /// How much of a file to read. EXIF and XMP each live in one segment of at
  /// most 64 KB right after the JPEG's start, so two of them and a few small
  /// segments in front fit comfortably.
  static const int headerBytes = 160 * 1024;

  /// File extensions (lower case, no dot) [parse] can read something from.
  static const Set<String> parsedExtensions = {
    'jpg',
    'jpeg',
    'jpe',
    'jfif',
    'png',
    'webp',
  };

  static bool canParse(String extension) => parsedExtensions.contains(extension);

  static GalleryMeta parse(Uint8List bytes) {
    try {
      if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return _parseJpeg(bytes);
      }
      if (bytes.length >= 24 && _startsWith(bytes, 0, _pngSignature)) {
        return _parsePng(bytes);
      }
      if (bytes.length >= 16 &&
          _startsWith(bytes, 0, _riff) &&
          _startsWith(bytes, 8, _webp)) {
        return _parseWebp(bytes);
      }
    } catch (_) {
      // A damaged header is just a photo without metadata.
    }
    return GalleryMeta.empty;
  }

  // ── Containers ───────────────────────────────────────────────────────────

  static const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  static const _riff = [0x52, 0x49, 0x46, 0x46]; // RIFF
  static const _webp = [0x57, 0x45, 0x42, 0x50]; // WEBP
  static const _exifId = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // Exif\0\0
  static final List<int> _xmpId = ascii.encode('http://ns.adobe.com/xap/1.0/\u0000');

  static GalleryMeta _parseJpeg(Uint8List b) {
    final c = _Collector();
    var o = 2;
    while (o + 4 <= b.length) {
      if (b[o] != 0xFF) {
        o++;
        continue;
      }
      final marker = b[o + 1];
      if (marker == 0xFF) {
        o++; // fill byte
        continue;
      }
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        o += 2; // markers without a length
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) break; // end / start of pixels
      final length = (b[o + 2] << 8) | b[o + 3];
      if (length < 2 || o + 2 + length > b.length) break;
      final start = o + 4;
      final end = o + 2 + length;
      // Start-of-frame markers carry the pixel size.
      if (length >= 8 &&
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        c.setSize((b[start + 3] << 8) | b[start + 4], (b[start + 1] << 8) | b[start + 2]);
      }
      if (marker == 0xE1) {
        if (_startsWith(b, start, _exifId)) {
          c.addTiff(Uint8List.sublistView(b, start + _exifId.length, end));
        } else if (_startsWith(b, start, _xmpId)) {
          c.addXmp(Uint8List.sublistView(b, start + _xmpId.length, end));
        }
      }
      o = end;
    }
    return c.build();
  }

  static GalleryMeta _parsePng(Uint8List b) {
    final c = _Collector();
    c.setSize(_u32be(b, 16), _u32be(b, 20));
    var o = 8;
    while (o + 12 <= b.length) {
      final len = _u32be(b, o);
      final type = String.fromCharCodes(b, o + 4, o + 8);
      final start = o + 8;
      if (type == 'IDAT' || type == 'IEND') break;
      if (len < 0 || start + len > b.length) break;
      final data = Uint8List.sublistView(b, start, start + len);
      if (type == 'eXIf') {
        c.addTiff(data);
      } else if (type == 'iTXt') {
        final nul = data.indexOf(0);
        if (nul > 0 &&
            latin1.decode(data.sublist(0, nul)) == 'XML:com.adobe.xmp' &&
            data.length > nul + 3 &&
            data[nul + 1] == 0) {
          // keyword\0 flag method language\0 translated\0 text
          final langEnd = data.indexOf(0, nul + 3);
          final transEnd = langEnd < 0 ? -1 : data.indexOf(0, langEnd + 1);
          if (transEnd >= 0) c.addXmp(Uint8List.sublistView(data, transEnd + 1));
        }
      }
      o = start + len + 4; // data + CRC
    }
    return c.build();
  }

  static GalleryMeta _parseWebp(Uint8List b) {
    final c = _Collector();
    var o = 12;
    while (o + 8 <= b.length) {
      final type = String.fromCharCodes(b, o, o + 4);
      final len = b[o + 4] | (b[o + 5] << 8) | (b[o + 6] << 16) | (b[o + 7] << 24);
      final start = o + 8;
      if (len < 0 || start + len > b.length) break;
      final data = Uint8List.sublistView(b, start, start + len);
      if (type == 'VP8X' && len >= 10) {
        c.setSize(
          1 + (data[4] | (data[5] << 8) | (data[6] << 16)),
          1 + (data[7] | (data[8] << 8) | (data[9] << 16)),
        );
      } else if (type == 'VP8 ' && len >= 10 && data[3] == 0x9D && data[4] == 0x01 && data[5] == 0x2A) {
        c.setSize(
          (data[6] | (data[7] << 8)) & 0x3FFF,
          (data[8] | (data[9] << 8)) & 0x3FFF,
        );
      } else if (type == 'VP8L' && len >= 5 && data[0] == 0x2F) {
        final bits = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
        c.setSize((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
      } else if (type == 'EXIF') {
        c.addTiff(_startsWith(data, 0, _exifId)
            ? Uint8List.sublistView(data, _exifId.length)
            : data);
      } else if (type == 'XMP ') {
        c.addXmp(data);
      }
      o = start + len + (len & 1); // chunks are padded to an even size
    }
    return c.build();
  }

  static bool _startsWith(List<int> b, int offset, List<int> prefix) {
    if (offset < 0 || offset + prefix.length > b.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (b[offset + i] != prefix[i]) return false;
    }
    return true;
  }

  static int _u32be(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  // ── Dates ────────────────────────────────────────────────────────────────

  static final RegExp _exifDate = RegExp(
    r'^(\d{4})[:\-](\d{2})[:\-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
  );

  /// `2023:07:14 18:32:05` (EXIF) or `2023-07-14T18:32:05` (XMP) read as a
  /// wall-clock time, in seconds. Null for the placeholder `0000:00:00`.
  static int? parseDate(String? text) {
    if (text == null) return null;
    final m = _exifDate.firstMatch(text.trim());
    if (m == null) return null;
    final y = int.parse(m[1]!);
    final mo = int.parse(m[2]!);
    final d = int.parse(m[3]!);
    final h = int.parse(m[4]!);
    final mi = int.parse(m[5]!);
    final s = int.parse(m[6]!);
    if (y < 1 || mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 60) {
      return null;
    }
    return DateTime.utc(y, mo, d, h, mi, s).millisecondsSinceEpoch ~/ 1000;
  }

  // ── XMP ──────────────────────────────────────────────────────────────────

  static const List<String> _keywordElements = ['dc:subject', 'digiKam:TagsList'];
  static final RegExp _li = RegExp(r'<rdf:li[^>]*>([^<]*)</rdf:li>');
  static final RegExp _rating = RegExp(r'xmp:Rating(?:="|>)\s*(-?\d+)');
  static final RegExp _xmpDate = RegExp(
    r'(?:photoshop:DateCreated|exif:DateTimeOriginal)(?:="|>)\s*([0-9:\-T ]{19})',
  );
  static const int _maxTags = 48;
  static const int _maxTagLength = 80;

  /// Keywords, rating and creation date found in an XMP packet.
  static ({List<String> tags, int? rating, int? taken}) parseXmp(String xmp) {
    final tags = <String>[];
    final seen = <String>{};
    for (final element in _keywordElements) {
      final block = RegExp(
        '<$element[^>]*>(.*?)</$element>',
        dotAll: true,
      );
      for (final bag in block.allMatches(xmp)) {
        for (final li in _li.allMatches(bag[1]!)) {
          var tag = _unescape(li[1]!).trim();
          if (tag.isEmpty) continue;
          if (tag.length > _maxTagLength) tag = tag.substring(0, _maxTagLength);
          if (seen.add(tag.toLowerCase()) && tags.length < _maxTags) tags.add(tag);
        }
      }
    }
    int? rating;
    final r = _rating.firstMatch(xmp);
    if (r != null) {
      final v = int.tryParse(r[1]!);
      if (v != null && v >= 1 && v <= 5) rating = v;
    }
    final d = _xmpDate.firstMatch(xmp);
    return (tags: tags, rating: rating, taken: parseDate(d?[1]));
  }

  static final RegExp _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);');

  static String _unescape(String s) {
    if (!s.contains('&')) return s;
    return s.replaceAllMapped(_entity, (m) {
      final e = m[1]!;
      switch (e) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final code = e.startsWith('#x')
          ? int.tryParse(e.substring(2), radix: 16)
          : int.tryParse(e.substring(1));
      if (code == null || code <= 0 || code > 0x10FFFF) return m[0]!;
      return String.fromCharCode(code);
    });
  }
}

/// Gathers what the EXIF and XMP blocks of one file say, preferring the more
/// specific source for each field when both have it.
class _Collector {
  String? make;
  String? model;
  int? original; // EXIF DateTimeOriginal
  int? digitized; // EXIF DateTimeDigitized
  int? modifiedExif; // EXIF DateTime (IFD0): last edit, the weakest date
  double? lat;
  double? lon;
  List<String> tags = const [];
  int? rating;
  int? xmpTaken;
  int? pixelWidth;
  int? pixelHeight;
  int orientation = 1;

  /// The size the image data has, before any EXIF rotation.
  void setSize(int w, int h) {
    if (w > 0 && h > 0 && pixelWidth == null) {
      pixelWidth = w;
      pixelHeight = h;
    }
  }

  void addXmp(Uint8List bytes) {
    final xmp = utf8.decode(bytes, allowMalformed: true);
    final r = GalleryMetaParser.parseXmp(xmp);
    if (r.tags.isNotEmpty) tags = r.tags;
    rating ??= r.rating;
    xmpTaken ??= r.taken;
  }

  void addTiff(Uint8List t) {
    if (t.length < 8) return;
    final le = t[0] == 0x49 && t[1] == 0x49;
    final be = t[0] == 0x4D && t[1] == 0x4D;
    if (!le && !be) return;

    int u16(int o) {
      if (o < 0 || o + 2 > t.length) return 0;
      return le ? (t[o] | (t[o + 1] << 8)) : ((t[o] << 8) | t[o + 1]);
    }

    int u32(int o) {
      if (o < 0 || o + 4 > t.length) return 0;
      return le
          ? (t[o] | (t[o + 1] << 8) | (t[o + 2] << 16) | (t[o + 3] << 24))
          : ((t[o] << 24) | (t[o + 1] << 16) | (t[o + 2] << 8) | t[o + 3]);
    }

    int typeSize(int type) => switch (type) {
      1 || 2 || 6 || 7 => 1,
      3 || 8 => 2,
      4 || 9 || 11 => 4,
      5 || 10 || 12 => 8,
      _ => 0,
    };

    String readAscii(int valueAt, int count) {
      if (valueAt < 0 || valueAt >= t.length || count <= 0) return '';
      final end = math.min(t.length, valueAt + count);
      var stop = end;
      for (var i = valueAt; i < end; i++) {
        if (t[i] == 0) {
          stop = i;
          break;
        }
      }
      return utf8.decode(Uint8List.sublistView(t, valueAt, stop), allowMalformed: true).trim();
    }

    double? rational(int o) {
      if (o < 0 || o + 8 > t.length) return null;
      final den = u32(o + 4);
      if (den == 0) return null;
      return u32(o) / den;
    }

    double? dms(int valueAt, int count) {
      if (count < 3) return null;
      final d = rational(valueAt);
      final m = rational(valueAt + 8);
      final s = rational(valueAt + 16);
      if (d == null || m == null || s == null) return null;
      return d + m / 60 + s / 3600;
    }

    final visited = <int>{};
    String latRef = 'N';
    String lonRef = 'E';
    double? rawLat;
    double? rawLon;

    // kind: 0 = IFD0, 1 = Exif IFD, 2 = GPS IFD
    void readIfd(int offset, int kind, int depth) {
      if (depth > 3 || offset <= 0 || offset + 2 > t.length) return;
      if (!visited.add(offset)) return;
      final n = u16(offset);
      for (var i = 0; i < n; i++) {
        final p = offset + 2 + i * 12;
        if (p + 12 > t.length) break;
        final tag = u16(p);
        final type = u16(p + 2);
        final count = u32(p + 4);
        final size = typeSize(type) * count;
        final valueAt = size <= 4 ? p + 8 : u32(p + 8);

        if (kind == 0) {
          switch (tag) {
            case 0x010F:
              make = readAscii(valueAt, count);
            case 0x0110:
              model = readAscii(valueAt, count);
            case 0x0112:
              orientation = u16(p + 8);
            case 0x0132:
              modifiedExif ??= GalleryMetaParser.parseDate(readAscii(valueAt, count));
            case 0x8769:
              readIfd(u32(p + 8), 1, depth + 1);
            case 0x8825:
              readIfd(u32(p + 8), 2, depth + 1);
          }
        } else if (kind == 1) {
          switch (tag) {
            case 0x9003:
              original ??= GalleryMetaParser.parseDate(readAscii(valueAt, count));
            case 0x9004:
              digitized ??= GalleryMetaParser.parseDate(readAscii(valueAt, count));
          }
        } else {
          switch (tag) {
            case 0x0001:
              latRef = readAscii(valueAt, count);
            case 0x0002:
              rawLat = dms(valueAt, count);
            case 0x0003:
              lonRef = readAscii(valueAt, count);
            case 0x0004:
              rawLon = dms(valueAt, count);
          }
        }
      }
    }

    readIfd(u32(4), 0, 0);

    if (rawLat != null && rawLon != null) {
      final la = latRef.toUpperCase().startsWith('S') ? -rawLat! : rawLat!;
      final lo = lonRef.toUpperCase().startsWith('W') ? -rawLon! : rawLon!;
      // 0,0 is what cameras without a fix write ("Null Island").
      final valid = la.abs() <= 90 && lo.abs() <= 180 && !(la == 0 && lo == 0);
      if (valid) {
        lat = la;
        lon = lo;
      }
    }
  }

  GalleryMeta build() => GalleryMeta(
    takenSecs: original ?? digitized ?? xmpTaken ?? modifiedExif,
    latitude: lat,
    longitude: lon,
    make: (make?.isEmpty ?? true) ? null : make,
    model: (model?.isEmpty ?? true) ? null : model,
    tags: tags,
    rating: rating,
    // Orientations 5..8 turn the picture a quarter, so what is shown is the
    // stored size the other way round.
    width: orientation >= 5 && orientation <= 8 ? pixelHeight : pixelWidth,
    height: orientation >= 5 && orientation <= 8 ? pixelWidth : pixelHeight,
  );
}
