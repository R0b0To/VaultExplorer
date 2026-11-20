import 'dart:typed_data';

import 'package:vaultexplorer/features/library/tags/byte_source.dart';
import 'package:vaultexplorer/features/library/tags/tag_models.dart';
import 'package:vaultexplorer/features/library/tags/tag_text.dart';

class _Atom {
  final String type;
  final int start; // offset of the atom header
  final int headerLen;
  final int size; // total size including header

  const _Atom(this.type, this.start, this.headerLen, this.size);

  int get bodyStart => start + headerLen;
  int get end => start + size;
}

/// Reads iTunes-style MP4/M4A/M4B metadata by walking atoms.
///
/// Only atom headers are read while navigating, so the `moov` box can sit
/// after a gigabyte of `mdat` and a long audiobook's sample tables are never
/// pulled in. Inside `ilst` only the small text atoms are read; `covr` is
/// located, not loaded.
class Mp4Reader {
  Mp4Reader._();

  static const int _maxAtomBody = 64 * 1024;
  static const int _maxPictureBytes = 16 * 1024 * 1024;

  static Future<bool> matches(BufferedReader r) async {
    final h = await r.bytes(0, 12);
    return h != null && Bytes.ascii(h, 4, 8) == 'ftyp';
  }

  static Future<_Atom?> _atomAt(BufferedReader r, int pos, int limit) async {
    if (pos + 8 > limit) return null;
    final avail = limit - pos;
    final h = await r.bytes(pos, avail >= 16 ? 16 : 8);
    if (h == null) return null;
    var size = Bytes.u32be(h, 0);
    final type = String.fromCharCodes(h.sublist(4, 8));
    var headerLen = 8;
    if (size == 1) {
      if (h.length < 16) return null;
      size = Bytes.u64be(h, 8);
      headerLen = 16;
    } else if (size == 0) {
      size = limit - pos;
    }
    if (size < headerLen || pos + size > limit) {
      // Tolerate a final atom that claims more than the file holds.
      if (size < headerLen) return null;
      size = limit - pos;
    }
    return _Atom(type, pos, headerLen, size);
  }

  static Future<void> read(BufferedReader r, AudioTagsBuilder b) async {
    b.format = 'm4a';
    final moov = await _findTopLevel(r, 'moov');
    if (moov == null) return;

    // moov children: mvhd (duration), udta/meta/ilst (tags).
    var pos = moov.bodyStart;
    for (var guard = 0; guard < 256; guard++) {
      final a = await _atomAt(r, pos, moov.end);
      if (a == null) break;
      if (a.type == 'mvhd') {
        await _readMvhd(r, a, b);
      } else if (a.type == 'udta') {
        await _readUdta(r, a, b);
      } else if (a.type == 'meta') {
        await _readMeta(r, a, b);
      }
      pos = a.end;
    }
  }

  static Future<_Atom?> _findTopLevel(BufferedReader r, String type) async {
    var pos = 0;
    for (var guard = 0; guard < 128; guard++) {
      final a = await _atomAt(r, pos, r.length);
      if (a == null) return null;
      if (a.type == type) return a;
      pos = a.end;
    }
    return null;
  }

  static Future<void> _readMvhd(
    BufferedReader r,
    _Atom a,
    AudioTagsBuilder b,
  ) async {
    final d = await r.bytes(a.bodyStart, 32);
    if (d == null) return;
    final version = d[0];
    int timescale;
    int duration;
    if (version == 1) {
      timescale = Bytes.u32be(d, 20);
      duration = Bytes.u64be(d, 24);
    } else {
      timescale = Bytes.u32be(d, 12);
      duration = Bytes.u32be(d, 16);
    }
    if (timescale > 0 && duration > 0) {
      b.durationMs = (duration * 1000) ~/ timescale;
    }
  }

  static Future<void> _readUdta(
    BufferedReader r,
    _Atom udta,
    AudioTagsBuilder b,
  ) async {
    var pos = udta.bodyStart;
    for (var guard = 0; guard < 64; guard++) {
      final a = await _atomAt(r, pos, udta.end);
      if (a == null) return;
      if (a.type == 'meta') await _readMeta(r, a, b);
      pos = a.end;
    }
  }

  static Future<void> _readMeta(
    BufferedReader r,
    _Atom meta,
    AudioTagsBuilder b,
  ) async {
    // 'meta' is a full box: 4 bytes of version/flags precede its children.
    var pos = meta.bodyStart + 4;
    for (var guard = 0; guard < 64; guard++) {
      final a = await _atomAt(r, pos, meta.end);
      if (a == null) return;
      if (a.type == 'ilst') {
        await _readIlst(r, a, b);
        return;
      }
      pos = a.end;
    }
  }

  static Future<_Atom?> _findIlst(BufferedReader r) async {
    final moov = await _findTopLevel(r, 'moov');
    if (moov == null) return null;
    var pos = moov.bodyStart;
    for (var guard = 0; guard < 256; guard++) {
      final a = await _atomAt(r, pos, moov.end);
      if (a == null) return null;
      if (a.type == 'udta') {
        var p = a.bodyStart;
        for (var g2 = 0; g2 < 64; g2++) {
          final m = await _atomAt(r, p, a.end);
          if (m == null) break;
          if (m.type == 'meta') {
            final il = await _ilstIn(r, m);
            if (il != null) return il;
          }
          p = m.end;
        }
      } else if (a.type == 'meta') {
        final il = await _ilstIn(r, a);
        if (il != null) return il;
      }
      pos = a.end;
    }
    return null;
  }

  static Future<_Atom?> _ilstIn(BufferedReader r, _Atom meta) async {
    var pos = meta.bodyStart + 4;
    for (var guard = 0; guard < 64; guard++) {
      final a = await _atomAt(r, pos, meta.end);
      if (a == null) return null;
      if (a.type == 'ilst') return a;
      pos = a.end;
    }
    return null;
  }

  static Future<void> _readIlst(
    BufferedReader r,
    _Atom ilst,
    AudioTagsBuilder b,
  ) async {
    var pos = ilst.bodyStart;
    for (var guard = 0; guard < 512; guard++) {
      final item = await _atomAt(r, pos, ilst.end);
      if (item == null) return;
      pos = item.end;

      final t = item.type;
      if (t == 'covr') {
        b.hasCover = true;
        continue;
      }
      final wanted = t == '\u00A9nam' ||
          t == '\u00A9ART' ||
          t == 'aART' ||
          t == '\u00A9alb' ||
          t == '\u00A9gen' ||
          t == 'gnre' ||
          t == '\u00A9day' ||
          t == 'trkn' ||
          t == 'disk';
      if (!wanted) continue;
      final dataAtoms = await _dataAtoms(r, item);
      for (final d in dataAtoms) {
        _applyItem(t, d, b);
      }
    }
  }

  /// The payloads of an item's `data` children: (typeIndicator, bytes).
  static Future<List<(int, Uint8List)>> _dataAtoms(
    BufferedReader r,
    _Atom item,
  ) async {
    final out = <(int, Uint8List)>[];
    var pos = item.bodyStart;
    for (var guard = 0; guard < 16; guard++) {
      final a = await _atomAt(r, pos, item.end);
      if (a == null) break;
      pos = a.end;
      if (a.type != 'data') continue;
      final bodyLen = a.size - a.headerLen;
      if (bodyLen < 8 || bodyLen > _maxAtomBody) continue;
      final body = await r.bytes(a.bodyStart, bodyLen);
      if (body == null) continue;
      final typeIndicator = Bytes.u32be(body, 0) & 0xFFFFFF;
      out.add((typeIndicator, Uint8List.sublistView(body, 8)));
    }
    return out;
  }

  static void _applyItem(String t, (int, Uint8List) d, AudioTagsBuilder b) {
    final payload = d.$2;
    String? text() => TagText.clean(TagText.utf8Lenient(payload, 0, payload.length));
    switch (t) {
      case '\u00A9nam':
        b.title ??= text();
      case '\u00A9ART':
        AudioTagsBuilder.addUnique(b.artists, text());
      case 'aART':
        AudioTagsBuilder.addUnique(b.albumArtists, text());
      case '\u00A9alb':
        b.album ??= text();
      case '\u00A9gen':
        AudioTagsBuilder.addUnique(b.genres, TagText.genre(text()));
      case 'gnre':
        if (payload.length >= 2) {
          final idx = Bytes.u16be(payload, 0) - 1;
          AudioTagsBuilder.addUnique(b.genres, TagText.id3GenreByIndex(idx));
        }
      case '\u00A9day':
        if (b.year == 0) b.year = TagText.year(text());
      case 'trkn':
        if (payload.length >= 6) {
          if (b.trackNo == 0) b.trackNo = Bytes.u16be(payload, 2);
          if (b.trackTotal == 0) b.trackTotal = Bytes.u16be(payload, 4);
        }
      case 'disk':
        if (payload.length >= 6) {
          if (b.discNo == 0) b.discNo = Bytes.u16be(payload, 2);
          if (b.discTotal == 0) b.discTotal = Bytes.u16be(payload, 4);
        }
    }
  }

  /// The `covr` picture, or null.
  static Future<CoverArt?> readCover(BufferedReader r) async {
    final ilst = await _findIlst(r);
    if (ilst == null) return null;
    var pos = ilst.bodyStart;
    for (var guard = 0; guard < 512; guard++) {
      final item = await _atomAt(r, pos, ilst.end);
      if (item == null) return null;
      pos = item.end;
      if (item.type != 'covr') continue;

      var p = item.bodyStart;
      for (var g2 = 0; g2 < 16; g2++) {
        final a = await _atomAt(r, p, item.end);
        if (a == null) break;
        p = a.end;
        if (a.type != 'data') continue;
        final bodyLen = a.size - a.headerLen - 8;
        if (bodyLen <= 0 || bodyLen > _maxPictureBytes) continue;
        final ti = await r.bytes(a.bodyStart, 4);
        final img = await r.bytes(a.bodyStart + 8, bodyLen);
        if (ti == null || img == null) continue;
        final indicator = Bytes.u32be(ti, 0) & 0xFFFFFF;
        final declared = indicator == 14 ? 'image/png' : 'image/jpeg';
        return CoverArt(img, sniffImageMime(img, declared));
      }
    }
    return null;
  }
}
