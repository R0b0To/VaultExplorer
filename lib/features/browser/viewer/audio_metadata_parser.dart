import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Tags and stream facts read straight from the first bytes of an audio file.
///
/// Codec, duration, bitrate, sample rate and channel count come from the
/// native probe; this covers what the probe does not report: the embedded tags
/// (title, artist, ...) and the bit depth of PCM/lossless streams.
class ParsedAudioMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final String? year;
  final String? genre;
  final String? trackNumber;
  final int? bitDepth;

  const ParsedAudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.year,
    this.genre,
    this.trackNumber,
    this.bitDepth,
  });

  bool get hasTags =>
      title != null ||
      artist != null ||
      album != null ||
      year != null ||
      genre != null ||
      trackNumber != null;
}

/// Reads ID3v2 (MP3 and friends), FLAC Vorbis comments, MP4/M4A `ilst` atoms
/// and the WAV `fmt ` chunk. The format is detected from magic bytes, not the
/// file extension, so a mislabelled file still works. Anything unrecognised or
/// truncated yields an empty result rather than throwing.
class AudioMetadataParser {
  /// How much of the file start the caller should hand to [parse]. Tags can
  /// carry cover art, so this is larger than the image header read.
  static const int headerReadBytes = 1024 * 1024;

  static ParsedAudioMetadata parse(Uint8List b) {
    if (b.length < 12) return const ParsedAudioMetadata();
    try {
      if (_ascii(b, 0, 3) == 'ID3') return _parseId3v2(b);
      if (_ascii(b, 0, 4) == 'fLaC') return _parseFlac(b);
      if (_ascii(b, 4, 8) == 'ftyp') return _parseMp4(b);
      if (_ascii(b, 0, 4) == 'RIFF' && _ascii(b, 8, 12) == 'WAVE') {
        return _parseWav(b);
      }
    } catch (_) {
      // Malformed tags must never break the info sheet.
    }
    return const ParsedAudioMetadata();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _ascii(Uint8List b, int start, int end) {
    if (start < 0 || end > b.length || start >= end) return '';
    return String.fromCharCodes(b.sublist(start, end));
  }

  static int _u32be(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _u32le(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static int _syncsafe(Uint8List b, int o) =>
      ((b[o] & 0x7F) << 21) |
      ((b[o + 1] & 0x7F) << 14) |
      ((b[o + 2] & 0x7F) << 7) |
      (b[o + 3] & 0x7F);

  static String? _clean(String? s) {
    if (s == null) return null;
    final t = s.replaceAll('\u0000', ' ').trim();
    return t.isEmpty ? null : t;
  }

  /// "2019-05-03" / "2019" -> "2019". Returns null when there is no year.
  static String? _yearOf(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^\s*(\d{4})').firstMatch(s);
    return m?.group(1);
  }

  /// ID3 genres are often a number in parentheses -- "(17)" or "(17)Rock".
  /// A bare number is dropped because the lookup table is not worth shipping
  /// here; a trailing name is kept.
  static String? _genreOf(String? s) {
    if (s == null) return null;
    final t = s.trim();
    final prefixed = RegExp(r'^\(\d+\)(.*)$').firstMatch(t);
    if (prefixed != null) return _clean(prefixed.group(1));
    if (RegExp(r'^\d+$').hasMatch(t)) return null;
    return _clean(t);
  }

  // ── ID3v2 ──────────────────────────────────────────────────────────────────

  static ParsedAudioMetadata _parseId3v2(Uint8List b) {
    final major = b[3];
    if (major < 2 || major > 4) return const ParsedAudioMetadata();
    final flags = b[5];
    final tagSize = _syncsafe(b, 6);
    final end = min(b.length, 10 + tagSize);

    var pos = 10;
    if ((flags & 0x40) != 0 && major >= 3) {
      if (pos + 4 > end) return const ParsedAudioMetadata();
      pos += major == 4 ? _syncsafe(b, pos) : _u32be(b, pos) + 4;
    }

    final idLen = major == 2 ? 3 : 4;
    final headLen = major == 2 ? 6 : 10;
    final found = <String, String>{};

    while (pos + headLen <= end) {
      if (b[pos] == 0) break; // padding
      final id = _ascii(b, pos, pos + idLen);
      final size = major == 2
          ? (b[pos + 3] << 16) | (b[pos + 4] << 8) | b[pos + 5]
          : major == 4
          ? _syncsafe(b, pos + 4)
          : _u32be(b, pos + 4);
      final dataStart = pos + headLen;
      final dataEnd = dataStart + size;
      // A frame running past the buffer (large cover art, or a tag we only
      // partly read) ends the walk; whatever was found so far is kept.
      if (size <= 0 || dataEnd > end) break;

      final key = switch (id) {
        'TT2' || 'TIT2' => 'title',
        'TP1' || 'TPE1' => 'artist',
        'TAL' || 'TALB' => 'album',
        'TYE' || 'TYER' || 'TDRC' => 'year',
        'TCO' || 'TCON' => 'genre',
        'TRK' || 'TRCK' => 'track',
        _ => null,
      };
      if (key != null && !found.containsKey(key)) {
        final text = _decodeId3Text(b, dataStart, dataEnd);
        if (text != null) found[key] = text;
      }
      pos = dataEnd;
    }

    return ParsedAudioMetadata(
      title: found['title'],
      artist: found['artist'],
      album: found['album'],
      year: _yearOf(found['year']),
      genre: _genreOf(found['genre']),
      trackNumber: found['track'],
    );
  }

  static String? _decodeId3Text(Uint8List b, int start, int end) {
    if (end - start < 2) return null;
    final encoding = b[start];
    final data = b.sublist(start + 1, end);
    String text;
    switch (encoding) {
      case 0:
        text = latin1.decode(data);
      case 1:
        var le = true;
        var from = 0;
        if (data.length >= 2) {
          if (data[0] == 0xFF && data[1] == 0xFE) {
            from = 2;
          } else if (data[0] == 0xFE && data[1] == 0xFF) {
            le = false;
            from = 2;
          }
        }
        text = _utf16(data, from, le);
      case 2:
        text = _utf16(data, 0, false);
      case 3:
        text = utf8.decode(data, allowMalformed: true);
      default:
        return null;
    }
    // Multi-value frames separate values with NUL; show them comma-joined.
    final parts = text
        .replaceAll('\uFEFF', '')
        .split('\u0000')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  static String _utf16(Uint8List d, int start, bool littleEndian) {
    final units = <int>[];
    for (var i = start; i + 1 < d.length; i += 2) {
      units.add(littleEndian ? d[i] | (d[i + 1] << 8) : (d[i] << 8) | d[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  // ── FLAC ───────────────────────────────────────────────────────────────────

  static ParsedAudioMetadata _parseFlac(Uint8List b) {
    int? bitDepth;
    final comments = <String, String>{};

    var pos = 4;
    while (pos + 4 <= b.length) {
      final header = b[pos];
      final isLast = (header & 0x80) != 0;
      final type = header & 0x7F;
      final len = (b[pos + 1] << 16) | (b[pos + 2] << 8) | b[pos + 3];
      final start = pos + 4;
      final end = start + len;
      if (end > b.length) break;

      if (type == 0 && len >= 18) {
        // STREAMINFO: bits-per-sample is 5 bits straddling bytes 12 and 13.
        bitDepth = (((b[start + 12] & 0x01) << 4) | (b[start + 13] >> 4)) + 1;
      } else if (type == 4) {
        _readVorbisComments(b, start, end, comments);
      }

      if (isLast) break;
      pos = end;
    }

    return ParsedAudioMetadata(
      title: comments['TITLE'],
      artist: comments['ARTIST'],
      album: comments['ALBUM'],
      year: _yearOf(comments['DATE'] ?? comments['YEAR']),
      genre: comments['GENRE'],
      trackNumber: comments['TRACKNUMBER'],
      bitDepth: bitDepth,
    );
  }

  static void _readVorbisComments(
    Uint8List b,
    int start,
    int end,
    Map<String, String> out,
  ) {
    var p = start;
    if (p + 4 > end) return;
    p += 4 + _u32le(b, p); // vendor string
    if (p + 4 > end) return;
    final count = _u32le(b, p);
    p += 4;
    for (var i = 0; i < count; i++) {
      if (p + 4 > end) return;
      final len = _u32le(b, p);
      p += 4;
      if (len < 0 || p + len > end) return;
      final entry = utf8.decode(b.sublist(p, p + len), allowMalformed: true);
      p += len;
      final eq = entry.indexOf('=');
      if (eq < 1) continue;
      final value = _clean(entry.substring(eq + 1));
      if (value == null) continue;
      out.putIfAbsent(entry.substring(0, eq).toUpperCase(), () => value);
    }
  }

  // ── MP4 / M4A / M4B ────────────────────────────────────────────────────────

  static ParsedAudioMetadata _parseMp4(Uint8List b) {
    // The tags live in moov/udta/meta/ilst. Rather than walk the atom tree
    // (which needs the whole moov box), look for each item atom directly and
    // validate its `data` child; this works whenever moov is in the bytes we
    // were given (faststart files, and most m4a files from tagging tools).
    String? text(List<int> fourcc) {
      final payload = _mp4DataPayload(b, fourcc);
      if (payload == null) return null;
      return _clean(utf8.decode(payload, allowMalformed: true));
    }

    String? track;
    final trkn = _mp4DataPayload(b, const [0x74, 0x72, 0x6B, 0x6E]); // 'trkn'
    if (trkn != null && trkn.length >= 6) {
      final n = (trkn[2] << 8) | trkn[3];
      final total = (trkn[4] << 8) | trkn[5];
      if (n > 0) track = total > 0 ? '$n/$total' : '$n';
    }

    return ParsedAudioMetadata(
      title: text(const [0xA9, 0x6E, 0x61, 0x6D]), // (c)nam
      artist: text(const [0xA9, 0x41, 0x52, 0x54]), // (c)ART
      album: text(const [0xA9, 0x61, 0x6C, 0x62]), // (c)alb
      year: _yearOf(text(const [0xA9, 0x64, 0x61, 0x79])), // (c)day
      genre: text(const [0xA9, 0x67, 0x65, 0x6E]), // (c)gen
      trackNumber: track,
    );
  }

  /// Payload of the `data` atom under the item atom [fourcc], or null.
  ///
  /// Item layout: [size][fourcc] then [size]['data'][version+flags][locale]
  /// [payload...].
  static Uint8List? _mp4DataPayload(Uint8List b, List<int> fourcc) {
    var from = 0;
    while (true) {
      final idx = _indexOf(b, fourcc, from);
      if (idx < 0) return null;
      from = idx + 4;
      if (idx + 20 > b.length) return null;
      if (_ascii(b, idx + 8, idx + 12) != 'data') continue;
      final size = _u32be(b, idx + 4);
      final start = idx + 20;
      final end = min(b.length, idx + 4 + size);
      if (end <= start) continue;
      return b.sublist(start, end);
    }
  }

  static int _indexOf(Uint8List b, List<int> pattern, int from) {
    for (var i = from; i + pattern.length <= b.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (b[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  // ── WAV ────────────────────────────────────────────────────────────────────

  static ParsedAudioMetadata _parseWav(Uint8List b) {
    var pos = 12;
    while (pos + 8 <= b.length) {
      final id = _ascii(b, pos, pos + 4);
      final size = _u32le(b, pos + 4);
      if (id == 'fmt ') {
        if (pos + 8 + 16 > b.length) break;
        final bits = b[pos + 8 + 14] | (b[pos + 8 + 15] << 8);
        return ParsedAudioMetadata(bitDepth: bits > 0 ? bits : null);
      }
      pos += 8 + size + (size & 1);
    }
    return const ParsedAudioMetadata();
  }
}
