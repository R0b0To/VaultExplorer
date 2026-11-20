import 'dart:typed_data';

import 'package:vaultexplorer/features/library/tags/byte_source.dart';
import 'package:vaultexplorer/features/library/tags/tag_models.dart';
import 'package:vaultexplorer/features/library/tags/tag_text.dart';

/// Outcome of reading the ID3v2 tag at the start of a file.
class Id3Info {
  /// Whether an ID3v2 tag was present.
  final bool found;

  /// Offset of the first byte after the tag (header, frames, padding, footer):
  /// where the audio, or the next container's magic, starts. 0 without a tag.
  final int audioStart;

  /// Duration declared by a `TLEN` frame, 0 when absent.
  final int declaredDurationMs;

  const Id3Info({
    required this.found,
    required this.audioStart,
    this.declaredDurationMs = 0,
  });

  static const Id3Info none = Id3Info(found: false, audioStart: 0);
}

class _Header {
  final int version;
  final int flags;
  final int size;
  const _Header(this.version, this.flags, this.size);

  bool get hasFooter => version == 4 && (flags & 0x10) != 0;
  int get totalLength => 10 + size + (hasFooter ? 10 : 0);
}

class _Frame {
  final String id;
  final int dataStart;
  final int size;
  final int flags1;
  final int flags2;
  const _Frame(this.id, this.dataStart, this.size, this.flags1, this.flags2);
}

/// Reads ID3v2.2/2.3/2.4 and ID3v1 tags.
///
/// The frame walk reads only the small text frames it needs and jumps over
/// everything else, picture frames included, so tag size does not drive cost.
class Id3Reader {
  Id3Reader._();

  static const int _maxTextFrameBytes = 64 * 1024;
  static const int _maxPictureBytes = 16 * 1024 * 1024;

  static const Map<String, String> _v22To23 = {
    'TT2': 'TIT2',
    'TP1': 'TPE1',
    'TP2': 'TPE2',
    'TAL': 'TALB',
    'TCO': 'TCON',
    'TYE': 'TYER',
    'TRK': 'TRCK',
    'TPA': 'TPOS',
    'TLE': 'TLEN',
    'PIC': 'APIC',
  };

  static Future<_Header?> _header(BufferedReader r, int offset) async {
    final h = await r.bytes(offset, 10);
    if (h == null) return null;
    if (!Bytes.startsWith(h, 0, const [0x49, 0x44, 0x33])) return null; // 'ID3'
    final version = h[3];
    if (version < 2 || version > 4) return null;
    // Size bytes must be synchsafe.
    if ((h[6] | h[7] | h[8] | h[9]) & 0x80 != 0) return null;
    return _Header(version, h[5], Bytes.syncsafe(h, 6));
  }

  /// Reads the ID3v2 tag at [offset] into [b].
  static Future<Id3Info> read(
    BufferedReader r,
    AudioTagsBuilder b, {
    int offset = 0,
  }) async {
    final header = await _header(r, offset);
    if (header == null) return Id3Info.none;
    final audioStart = offset + header.totalLength;
    var tlen = 0;

    await _walk(r, header, offset, (f) async {
      final id = header.version == 2 ? (_v22To23[f.id] ?? f.id) : f.id;
      switch (id) {
        case 'APIC':
          b.hasCover = true;
          return false;
        case 'TIT2':
        case 'TPE1':
        case 'TPE2':
        case 'TALB':
        case 'TCON':
        case 'TYER':
        case 'TDRC':
        case 'TRCK':
        case 'TPOS':
        case 'TLEN':
          final values = await _textValues(r, header, f);
          if (values.isEmpty) return false;
          switch (id) {
            case 'TIT2':
              b.title ??= values.first;
            case 'TPE1':
              for (final v in values) {
                AudioTagsBuilder.addUnique(b.artists, v);
              }
            case 'TPE2':
              for (final v in values) {
                AudioTagsBuilder.addUnique(b.albumArtists, v);
              }
            case 'TALB':
              b.album ??= values.first;
            case 'TCON':
              for (final v in values) {
                AudioTagsBuilder.addUnique(b.genres, TagText.genre(v));
              }
            case 'TYER':
            case 'TDRC':
              if (b.year == 0) b.year = TagText.year(values.first);
            case 'TRCK':
              final (n, total) = TagText.numberPair(values.first);
              if (b.trackNo == 0) b.trackNo = n;
              if (b.trackTotal == 0) b.trackTotal = total;
            case 'TPOS':
              final (n, total) = TagText.numberPair(values.first);
              if (b.discNo == 0) b.discNo = n;
              if (b.discTotal == 0) b.discTotal = total;
            case 'TLEN':
              tlen = TagText.leadingInt(values.first);
          }
          return false;
        default:
          return false;
      }
    });

    return Id3Info(
      found: true,
      audioStart: audioStart,
      declaredDurationMs: tlen,
    );
  }

  /// The tag length at [offset] (0 when there is no tag), without reading
  /// frames. Used to hop over a leading tag.
  static Future<int> skipLength(BufferedReader r, {int offset = 0}) async {
    final header = await _header(r, offset);
    return header?.totalLength ?? 0;
  }

  /// The embedded picture, front cover preferred, or null.
  static Future<CoverArt?> readCover(BufferedReader r, {int offset = 0}) async {
    final header = await _header(r, offset);
    if (header == null) return null;
    CoverArt? fallback;
    CoverArt? front;

    await _walk(r, header, offset, (f) async {
      final id = header.version == 2 ? (_v22To23[f.id] ?? f.id) : f.id;
      if (id != 'APIC') return false;
      if (f.size < 8 || f.size > _maxPictureBytes) return false;
      final payload = await _payload(r, header, f, _maxPictureBytes);
      if (payload == null) return false;
      final pic = _parsePicture(payload, header.version == 2);
      if (pic == null) return false;
      if (pic.$1 == 3) {
        front = pic.$2;
        return true;
      }
      fallback ??= pic.$2;
      return false;
    });
    return front ?? fallback;
  }

  // ── Frame walk ─────────────────────────────────────────────────────────────

  static Future<void> _walk(
    BufferedReader r,
    _Header h,
    int offset,
    Future<bool> Function(_Frame f) visit,
  ) async {
    var pos = offset + 10;
    final end = offset + 10 + h.size;

    if (h.version >= 3 && (h.flags & 0x40) != 0) {
      final eh = await r.bytes(pos, 4);
      if (eh == null) return;
      pos += h.version == 4 ? Bytes.syncsafe(eh, 0) : Bytes.u32be(eh, 0) + 4;
    }

    final idLen = h.version == 2 ? 3 : 4;
    final hdrLen = h.version == 2 ? 6 : 10;
    for (var guard = 0; guard < 2000; guard++) {
      if (pos + hdrLen > end) return;
      final hd = await r.bytes(pos, hdrLen);
      if (hd == null) return;
      if (hd[0] == 0) return; // padding: no more frames
      for (var i = 0; i < idLen; i++) {
        final c = hd[i];
        final ok = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A);
        if (!ok) return;
      }
      final id = Bytes.ascii(hd, 0, idLen);
      final int size;
      if (h.version == 2) {
        size = Bytes.u24be(hd, 3);
      } else if (h.version == 3) {
        size = Bytes.u32be(hd, 4);
      } else {
        size = Bytes.syncsafe(hd, 4);
      }
      final f1 = h.version == 2 ? 0 : hd[8];
      final f2 = h.version == 2 ? 0 : hd[9];
      final dataStart = pos + hdrLen;
      if (size < 0 || dataStart + size > end) return;
      final stop = await visit(_Frame(id, dataStart, size, f1, f2));
      if (stop) return;
      pos = dataStart + size;
    }
  }

  /// The frame's payload with flag-driven prefixes removed and unsynchronisation
  /// undone, or null when the frame is compressed/encrypted or too large.
  static Future<Uint8List?> _payload(
    BufferedReader r,
    _Header h,
    _Frame f,
    int maxBytes,
  ) async {
    var start = f.dataStart;
    var len = f.size;
    var unsync = (h.version < 4) && (h.flags & 0x80) != 0;

    if (h.version == 3) {
      if (f.flags2 & 0x80 != 0 || f.flags2 & 0x40 != 0) return null;
      if (f.flags2 & 0x20 != 0) {
        start += 1;
        len -= 1;
      }
    } else if (h.version == 4) {
      if (f.flags2 & 0x08 != 0 || f.flags2 & 0x04 != 0) return null;
      if (f.flags2 & 0x40 != 0) {
        start += 1;
        len -= 1;
      }
      if (f.flags2 & 0x01 != 0) {
        start += 4;
        len -= 4;
      }
      if (f.flags2 & 0x02 != 0) unsync = true;
    }
    if (len <= 0 || len > maxBytes) return null;
    final raw = await r.bytes(start, len);
    if (raw == null) return null;
    return unsync ? _deUnsync(raw) : raw;
  }

  static Uint8List _deUnsync(Uint8List b) {
    final out = BytesBuilder(copy: false);
    var i = 0;
    while (i < b.length) {
      out.addByte(b[i]);
      if (b[i] == 0xFF && i + 1 < b.length && b[i + 1] == 0x00) {
        i += 2;
      } else {
        i += 1;
      }
    }
    return out.takeBytes();
  }

  static Future<List<String>> _textValues(
    BufferedReader r,
    _Header h,
    _Frame f,
  ) async {
    if (f.size < 2 || f.size > _maxTextFrameBytes) return const [];
    final payload = await _payload(r, h, f, _maxTextFrameBytes);
    if (payload == null || payload.isEmpty) return const [];
    return TagText.id3Values(payload, 0, payload.length);
  }

  static (int, CoverArt)? _parsePicture(Uint8List d, bool v22) {
    try {
      if (d.length < 8) return null;
      final enc = d[0];
      var p = 1;
      String declared;
      if (v22) {
        declared = TagText.latin1(d, p, p + 3).toLowerCase();
        declared = declared == 'png' ? 'image/png' : 'image/jpeg';
        p += 3;
      } else {
        var e = p;
        while (e < d.length && d[e] != 0) {
          e++;
        }
        declared = TagText.latin1(d, p, e).toLowerCase();
        p = e + 1;
      }
      if (p >= d.length) return null;
      final picType = d[p];
      p += 1;
      // Description: terminated by one NUL (8-bit encodings) or an aligned
      // NUL pair (UTF-16).
      if (enc == 1 || enc == 2) {
        while (p + 1 < d.length && !(d[p] == 0 && d[p + 1] == 0)) {
          p += 2;
        }
        p += 2;
      } else {
        while (p < d.length && d[p] != 0) {
          p++;
        }
        p += 1;
      }
      if (p >= d.length) return null;
      final img = Uint8List.sublistView(d, p);
      return (picType, CoverArt(img, sniffImageMime(img, declared)));
    } catch (_) {
      return null;
    }
  }

  // ── ID3v1 ──────────────────────────────────────────────────────────────────

  /// Reads the 128-byte ID3v1 block at the end of the file into [b].
  static Future<bool> readV1(BufferedReader r, AudioTagsBuilder b) async {
    if (r.length < 128) return false;
    final t = await r.bytes(r.length - 128, 128);
    if (t == null || !Bytes.startsWith(t, 0, const [0x54, 0x41, 0x47])) {
      return false;
    }
    String field(int s, int e) => TagText.clean(TagText.latin1(t, s, e)) ?? '';

    final title = field(3, 33);
    final artist = field(33, 63);
    final album = field(63, 93);
    if (title.isNotEmpty) b.title ??= title;
    if (artist.isNotEmpty) AudioTagsBuilder.addUnique(b.artists, artist);
    if (album.isNotEmpty) b.album ??= album;
    if (b.year == 0) b.year = TagText.year(field(93, 97));
    if (t[125] == 0 && t[126] != 0 && b.trackNo == 0) b.trackNo = t[126];
    final g = TagText.id3GenreByIndex(t[127]);
    if (g != null) AudioTagsBuilder.addUnique(b.genres, g);
    return true;
  }
}
