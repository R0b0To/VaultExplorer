import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'metadata_source.dart';
import 'tiff_exif_editor.dart';
import 'xmp_editor.dart';

/// The kinds of embedded metadata that can be removed from an image.
enum MetadataKind {
  /// Exif: camera, date, GPS position, orientation...
  exif,

  /// XMP: keywords, rating, edit history, vendor data.
  xmp,

  /// The colour profile. Removing it can change how colours look.
  iccProfile,

  /// IPTC / Photoshop resources: captions, keywords, credits.
  iptc,

  /// Free-text comments (JPEG comment, PNG text chunks).
  comment,
}

/// A change to an image's metadata. Any combination can be asked at once.
class MetadataEdit {
  const MetadataEdit({
    this.keywords,
    this.takenWallClock,
    this.strip = const {},
    this.keepOrientation = true,
  });

  /// Replaces the image's keywords with exactly these. Null leaves them.
  final List<String>? keywords;

  /// Sets the date the photo was taken, as the camera's wall clock.
  final DateTime? takenWallClock;

  /// Metadata kinds to remove, before the other changes are applied.
  final Set<MetadataKind> strip;

  /// When Exif is removed, keep a minimal Exif holding only the orientation,
  /// so a photo taken sideways is not shown sideways afterwards.
  final bool keepOrientation;

  bool get isEmpty => keywords == null && takenWallClock == null && strip.isEmpty;
}

/// Plans edits to the metadata of JPEG, PNG and WebP files.
///
/// Everything is expressed as a [MetadataEditPlan] ("copy this, write that"),
/// so the (large) pixel data is streamed through untouched and nothing is
/// ever written to disk in the clear. The planner is pure: it reads byte
/// ranges from a [MetadataSource] and returns the plan.
class ImageMetadataEditor {
  const ImageMetadataEditor._();

  /// File extensions (lower case, no dot) that [plan] can edit.
  static const Set<String> supportedExtensions = {
    'jpg',
    'jpeg',
    'jpe',
    'jfif',
    'png',
    'webp',
  };

  static bool canEdit(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return false;
    return supportedExtensions.contains(fileName.substring(dot + 1).toLowerCase());
  }

  /// The plan for applying [edit] to [source], or null when the file would
  /// not change. Throws [MetadataEditException] when it cannot be done.
  static Future<MetadataEditPlan?> plan(MetadataSource source, MetadataEdit edit) async {
    if (edit.isEmpty) return null;
    final s = BufferedMetadataSource(source);
    final head = await s.read(0, 12);
    if (head.length >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF) {
      return _planJpeg(s, edit);
    }
    if (head.length >= 8 && _eq(head, 0, _pngSignature)) return _planPng(s, edit);
    if (head.length >= 12 && _eq(head, 0, _riff) && _eq(head, 8, _webp)) {
      return _planWebp(s, edit);
    }
    throw const MetadataEditException(MetadataEditFailure.unsupportedFormat);
  }

  // ── Shared logic ─────────────────────────────────────────────────────────

  static _Result _apply(Uint8List? tiffIn, String? xmpIn, MetadataEdit e) {
    final r = _Result(tiffIn, xmpIn);
    int? orientation;
    if (tiffIn != null) orientation = TiffExifEditor.tryParse(tiffIn)?.orientation;
    if (orientation == 1) orientation = null;

    final exifStripped = e.strip.contains(MetadataKind.exif) && tiffIn != null;
    if (e.strip.contains(MetadataKind.exif) && tiffIn != null) {
      r.tiff = null;
      r.exifChanged = true;
    }
    if (e.strip.contains(MetadataKind.xmp) && xmpIn != null) {
      r.xmp = null;
      r.xmpChanged = true;
    }

    if (e.keywords != null) {
      final next = XmpEditor.setKeywords(r.xmp, e.keywords!);
      if (next != null && next != r.xmp) {
        r.xmp = next;
        r.xmpChanged = true;
      }
    }

    final date = e.takenWallClock;
    // What the new Exif keeps of the old one: the orientation, unless the
    // person chose not to.
    final carried = exifStripped && !e.keepOrientation ? null : orientation;
    if (date != null) {
      final exifDate = exifDateString(date);
      if (r.tiff != null) {
        final editor = TiffExifEditor.tryParse(r.tiff!);
        if (editor == null || !editor.setDates(exifDate)) {
          throw const MetadataEditException(MetadataEditFailure.unreadableExif);
        }
        r.tiff = editor.bytes;
      } else {
        r.tiff = TiffExifEditor.createMinimal(orientation: carried, exifDate: exifDate);
      }
      r.exifChanged = true;
      if (r.xmp != null) {
        final next = XmpEditor.setDates(r.xmp!, xmpDateString(date));
        if (next != r.xmp) {
          r.xmp = next;
          r.xmpChanged = true;
        }
      }
    } else if (exifStripped && carried != null) {
      r.tiff = TiffExifEditor.createMinimal(orientation: carried);
    }
    return r;
  }

  static bool _eq(List<int> b, int offset, List<int> prefix) {
    if (offset < 0 || offset + prefix.length > b.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (b[offset + i] != prefix[i]) return false;
    }
    return true;
  }

  static Uint8List _concat(List<List<int>> parts) {
    final b = BytesBuilder(copy: false);
    for (final p in parts) {
      b.add(p);
    }
    return b.takeBytes();
  }

  static Future<Uint8List> _payload(MetadataSource s, int start, int end) async {
    final bytes = await s.read(start, end - start);
    if (bytes.length != end - start) {
      throw const MetadataEditException(MetadataEditFailure.malformed, 'truncated');
    }
    return bytes;
  }

  // ── JPEG ─────────────────────────────────────────────────────────────────

  static const _exifId = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // Exif\0\0
  static final List<int> _xmpId = ascii.encode('http://ns.adobe.com/xap/1.0/\u0000');
  static final List<int> _xmpExtId = ascii.encode('http://ns.adobe.com/xmp/extension/\u0000');
  static final List<int> _iccId = ascii.encode('ICC_PROFILE\u0000');
  static final List<int> _psId = ascii.encode('Photoshop 3.0\u0000');
  static final List<int> _jfifId = ascii.encode('JFIF\u0000');
  static final List<int> _mpfId = ascii.encode('MPF\u0000');

  /// Biggest payload one JPEG segment can carry (its 2-byte length counts
  /// itself).
  static const int _maxJpegPayload = 65533;

  static Future<MetadataEditPlan?> _planJpeg(MetadataSource s, MetadataEdit edit) async {
    // 1. The segments in front of the image data.
    final items = <_JpegItem>[];
    var o = 2;
    int? sosStart;
    while (true) {
      final head = await s.read(o, 4);
      if (head.length < 2 || head[0] != 0xFF) {
        throw const MetadataEditException(MetadataEditFailure.malformed, 'jpeg marker');
      }
      final marker = head[1];
      if (marker == 0xFF) {
        o++; // fill byte
        continue;
      }
      if (marker == 0xDA) {
        sosStart = o;
        break;
      }
      if (marker == 0xD9) {
        throw const MetadataEditException(MetadataEditFailure.malformed, 'no image data');
      }
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        items.add(_JpegItem.original(marker, o, o + 2, 'other'));
        o += 2;
        continue;
      }
      if (head.length < 4) {
        throw const MetadataEditException(MetadataEditFailure.malformed, 'jpeg length');
      }
      final length = (head[2] << 8) | head[3];
      if (length < 2 || o + 2 + length > s.length) {
        throw const MetadataEditException(MetadataEditFailure.malformed, 'jpeg segment');
      }
      final end = o + 2 + length;
      items.add(_JpegItem.original(marker, o, end, await _jpegKind(s, marker, o, end)));
      o = end;
    }

    // 2. Current metadata blocks.
    final exifItem = items.where((i) => i.kind == 'exif').firstOrNull;
    final xmpItem = items.where((i) => i.kind == 'xmp').firstOrNull;
    Uint8List? tiff;
    if (exifItem != null) {
      final p = await _payload(s, exifItem.start! + 4, exifItem.end!);
      tiff = Uint8List.sublistView(p, _exifId.length);
    }
    String? xmp;
    if (xmpItem != null) {
      final p = await _payload(s, xmpItem.start! + 4, xmpItem.end!);
      xmp = utf8.decode(Uint8List.sublistView(p, _xmpId.length), allowMalformed: true);
    }

    final result = _apply(tiff, xmp, edit);
    var changed = result.exifChanged || result.xmpChanged;

    // 3. Segments to drop.
    final drop = <String>{
      if (edit.strip.contains(MetadataKind.exif)) 'exif',
      if (edit.strip.contains(MetadataKind.xmp)) ...['xmp', 'xmpExt'],
      if (edit.strip.contains(MetadataKind.iccProfile)) 'icc',
      if (edit.strip.contains(MetadataKind.iptc)) 'iptc',
      if (edit.strip.contains(MetadataKind.comment)) 'comment',
    };
    final out = <_JpegItem>[];
    for (final item in items) {
      if (drop.contains(item.kind)) {
        changed = true;
        continue;
      }
      out.add(item);
    }

    // 4. Rewritten and new blocks.
    Uint8List app1(List<int> id, List<int> body) {
      final payload = _concat([id, body]);
      if (payload.length > _maxJpegPayload) {
        throw const MetadataEditException(MetadataEditFailure.tooLarge);
      }
      final len = payload.length + 2;
      return _concat([
        [0xFF, 0xE1, len >> 8, len & 0xFF],
        payload,
      ]);
    }

    int insertAfterJfif() {
      var i = 0;
      while (i < out.length && out[i].kind == 'jfif') {
        i++;
      }
      return i;
    }

    if (result.tiff != null && (result.exifChanged || exifItem == null)) {
      final seg = app1(_exifId, result.tiff!);
      final at = out.indexWhere((i) => i.kind == 'exif');
      if (at >= 0) {
        out[at] = _JpegItem.literal(0xE1, seg, 'exif');
      } else {
        out.insert(insertAfterJfif(), _JpegItem.literal(0xE1, seg, 'exif'));
      }
    }
    if (result.xmp != null && (result.xmpChanged || xmpItem == null)) {
      final seg = app1(_xmpId, utf8.encode(result.xmp!));
      final at = out.indexWhere((i) => i.kind == 'xmp');
      if (at >= 0) {
        out[at] = _JpegItem.literal(0xE1, seg, 'xmp');
      } else {
        final afterExif = out.indexWhere((i) => i.kind == 'exif');
        out.insert(afterExif >= 0 ? afterExif + 1 : insertAfterJfif(), _JpegItem.literal(0xE1, seg, 'xmp'));
      }
    }
    if (!changed) return null;

    // 5. The multi-picture index (Ultra HDR, motion photos) holds absolute
    // sizes and offsets into this file; they move with the header's size.
    final oldHeader = sosStart - 2;
    var newHeader = 0;
    for (final i in out) {
      newHeader += i.length;
    }
    final delta = newHeader - oldHeader;
    final mpfAt = out.indexWhere((i) => i.kind == 'mpf');
    if (delta != 0 && mpfAt >= 0 && out[mpfAt].start != null) {
      final item = out[mpfAt];
      final payload = await _payload(s, item.start! + 4, item.end!);
      var newPos = 2;
      for (var i = 0; i < mpfAt; i++) {
        newPos += out[i].length;
      }
      final patched = _patchMpf(
        Uint8List.fromList(payload),
        oldTiffStart: item.start! + 8,
        newTiffStart: newPos + 8,
        delta: delta,
      );
      if (patched != null) {
        final len = patched.length + 2;
        out[mpfAt] = _JpegItem.literal(
          0xE2,
          _concat([
            [0xFF, 0xE2, len >> 8, len & 0xFF],
            patched,
          ]),
          'mpf',
        );
      }
    }

    return MetadataEditPlan([
      LiteralPiece(_soi),
      for (final i in out) i.piece,
      CopyPiece(sosStart, s.length),
    ]);
  }

  static final Uint8List _soi = Uint8List.fromList([0xFF, 0xD8]);

  static Future<String> _jpegKind(MetadataSource s, int marker, int start, int end) async {
    if (marker == 0xFE) return 'comment';
    if (marker != 0xE0 && marker != 0xE1 && marker != 0xE2 && marker != 0xED) {
      return 'other';
    }
    final id = await s.read(start + 4, 40);
    switch (marker) {
      case 0xE0:
        return _eq(id, 0, _jfifId) ? 'jfif' : 'other';
      case 0xE1:
        if (_eq(id, 0, _exifId)) return 'exif';
        if (_eq(id, 0, _xmpId)) return 'xmp';
        if (_eq(id, 0, _xmpExtId)) return 'xmpExt';
        return 'other';
      case 0xE2:
        if (_eq(id, 0, _iccId)) return 'icc';
        if (_eq(id, 0, _mpfId)) return 'mpf';
        return 'other';
      default:
        return _eq(id, 0, _psId) ? 'iptc' : 'other';
    }
  }

  /// Shifts the sizes and offsets in a multi-picture (MPF) block by [delta].
  /// Returns null when the block is not one this can safely read.
  static Uint8List? _patchMpf(
    Uint8List payload, {
    required int oldTiffStart,
    required int newTiffStart,
    required int delta,
  }) {
    // payload: 'MPF\0' + TIFF header + IFD. Offsets are from the TIFF header.
    const base = 4;
    if (payload.length < base + 8) return null;
    final le = payload[base] == 0x49 && payload[base + 1] == 0x49;
    final be = payload[base] == 0x4D && payload[base + 1] == 0x4D;
    if (!le && !be) return null;
    int u16(int o) => le ? payload[o] | (payload[o + 1] << 8) : (payload[o] << 8) | payload[o + 1];
    int u32(int o) => le
        ? payload[o] | (payload[o + 1] << 8) | (payload[o + 2] << 16) | (payload[o + 3] << 24)
        : (payload[o] << 24) | (payload[o + 1] << 16) | (payload[o + 2] << 8) | payload[o + 3];
    void put32(int o, int v) {
      if (le) {
        payload[o] = v & 0xFF;
        payload[o + 1] = (v >> 8) & 0xFF;
        payload[o + 2] = (v >> 16) & 0xFF;
        payload[o + 3] = (v >> 24) & 0xFF;
      } else {
        payload[o] = (v >> 24) & 0xFF;
        payload[o + 1] = (v >> 16) & 0xFF;
        payload[o + 2] = (v >> 8) & 0xFF;
        payload[o + 3] = v & 0xFF;
      }
    }

    final ifd = base + u32(base + 4);
    if (ifd + 2 > payload.length) return null;
    final n = u16(ifd);
    for (var i = 0; i < n; i++) {
      final e = ifd + 2 + i * 12;
      if (e + 12 > payload.length) return null;
      if (u16(e) != 0xB002) continue; // MP Entry
      final count = u32(e + 4);
      final at = base + u32(e + 8);
      if (count < 16 || at + count > payload.length) return null;
      for (var k = 0; k + 16 <= count; k += 16) {
        final entry = at + k;
        final size = u32(entry + 4);
        final offset = u32(entry + 8);
        if (k == 0) {
          // The first image is the file's own: it grew with its header.
          put32(entry + 4, size + delta);
        } else {
          // Offsets count from the MPF header; both it and the image moved.
          final absolute = oldTiffStart + offset + delta;
          put32(entry + 8, absolute - newTiffStart);
        }
      }
      return payload;
    }
    return null;
  }

  // ── PNG ──────────────────────────────────────────────────────────────────

  static const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  static const _xmpKeyword = 'XML:com.adobe.xmp';

  static Future<MetadataEditPlan?> _planPng(MetadataSource s, MetadataEdit edit) async {
    final chunks = <_PngChunk>[];
    var o = 8;
    while (o + 12 <= s.length) {
      final head = await s.read(o, 8);
      if (head.length < 8) break;
      final len = _u32be(head, 0);
      final type = String.fromCharCodes(head, 4, 8);
      final end = o + 12 + len;
      if (len < 0 || end > s.length) {
        throw const MetadataEditException(MetadataEditFailure.malformed, 'png chunk');
      }
      var kind = 'other';
      if (type == 'eXIf') {
        kind = 'exif';
      } else if (type == 'iCCP') {
        kind = 'icc';
      } else if (type == 'tIME') {
        kind = 'comment';
      } else if (type == 'tEXt' || type == 'zTXt' || type == 'iTXt') {
        final data = await s.read(o + 8, len < 96 ? len : 96);
        final nul = data.indexOf(0);
        final keyword = latin1.decode(nul < 0 ? data : data.sublist(0, nul));
        kind = _pngTextKind(type, keyword);
      }
      chunks.add(_PngChunk(type, o, end, kind));
      o = end;
      if (type == 'IEND') break;
    }
    if (chunks.isEmpty || chunks.last.type != 'IEND') {
      throw const MetadataEditException(MetadataEditFailure.malformed, 'png end');
    }

    final exifChunk = chunks.where((c) => c.kind == 'exif' && c.type == 'eXIf').firstOrNull;
    final xmpChunk = chunks.where((c) => c.kind == 'xmp' && c.type == 'iTXt').firstOrNull;
    Uint8List? tiff;
    if (exifChunk != null) {
      tiff = await _payload(s, exifChunk.start + 8, exifChunk.end - 4);
      if (tiff.length >= 6 && _eq(tiff, 0, _exifId)) tiff = Uint8List.sublistView(tiff, 6);
    }
    String? xmp;
    if (xmpChunk != null) {
      xmp = _pngXmpText(await _payload(s, xmpChunk.start + 8, xmpChunk.end - 4));
    }

    final result = _apply(tiff, xmp, edit);
    var changed = result.exifChanged || result.xmpChanged;

    final drop = <String>{
      if (edit.strip.contains(MetadataKind.exif)) 'exif',
      if (edit.strip.contains(MetadataKind.xmp)) 'xmp',
      if (edit.strip.contains(MetadataKind.iccProfile)) 'icc',
      if (edit.strip.contains(MetadataKind.iptc)) 'iptc',
      if (edit.strip.contains(MetadataKind.comment)) 'comment',
    };

    final pieces = <EditPiece>[LiteralPiece(_pngSignatureBytes)];
    final firstIdat = chunks.indexWhere((c) => c.type == 'IDAT');
    final insertBefore = firstIdat >= 0 ? firstIdat : chunks.length - 1;
    var wroteExif = false;
    var wroteXmp = false;
    final newExif = result.tiff != null && result.exifChanged
        ? _pngChunk('eXIf', result.tiff!)
        : null;
    final newXmp = result.xmp != null && result.xmpChanged ? _pngChunk('iTXt', _pngXmpData(result.xmp!)) : null;

    for (var i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      if (i == insertBefore) {
        if (newExif != null && exifChunk == null) {
          pieces.add(LiteralPiece(newExif));
          wroteExif = true;
        }
        if (newXmp != null && xmpChunk == null) {
          pieces.add(LiteralPiece(newXmp));
          wroteXmp = true;
        }
      }
      if (drop.contains(c.kind)) {
        // An Exif or XMP chunk that was stripped but has a replacement (a
        // minimal Exif, a new date) is replaced rather than dropped.
        if (c == exifChunk && newExif != null && !wroteExif) {
          pieces.add(LiteralPiece(newExif));
          wroteExif = true;
        } else if (c == xmpChunk && newXmp != null && !wroteXmp) {
          pieces.add(LiteralPiece(newXmp));
          wroteXmp = true;
        }
        changed = true;
        continue;
      }
      if (c == exifChunk && newExif != null && !wroteExif) {
        pieces.add(LiteralPiece(newExif));
        wroteExif = true;
        continue;
      }
      if (c == xmpChunk && newXmp != null && !wroteXmp) {
        pieces.add(LiteralPiece(newXmp));
        wroteXmp = true;
        continue;
      }
      pieces.add(CopyPiece(c.start, c.end));
    }
    if (!changed) return null;
    return MetadataEditPlan(pieces);
  }

  static final Uint8List _pngSignatureBytes = Uint8List.fromList(_pngSignature);

  static String _pngTextKind(String type, String keyword) {
    if (type == 'iTXt' && keyword == _xmpKeyword) return 'xmp';
    final k = keyword.toLowerCase();
    if (k == 'raw profile type exif' || k == 'raw profile type app1') return 'exif';
    if (k == 'raw profile type xmp') return 'xmp';
    if (k == 'raw profile type iptc') return 'iptc';
    if (k == 'raw profile type icc' || k == 'raw profile type icm') return 'icc';
    return 'comment';
  }

  static String _pngXmpText(Uint8List data) {
    final nul = data.indexOf(0);
    if (nul < 0 || data.length < nul + 5) return '';
    final compressed = data[nul + 1] == 1;
    final langEnd = data.indexOf(0, nul + 3);
    final transEnd = langEnd < 0 ? -1 : data.indexOf(0, langEnd + 1);
    if (transEnd < 0) return '';
    var text = Uint8List.sublistView(data, transEnd + 1);
    if (compressed) {
      try {
        text = Uint8List.fromList(zlib.decode(text));
      } on FormatException {
        return '';
      }
    }
    return utf8.decode(text, allowMalformed: true);
  }

  static Uint8List _pngXmpData(String xmp) => _concat([
    ascii.encode(_xmpKeyword),
    [0, 0, 0, 0, 0], // end of keyword, not compressed, method, no language, no translation
    utf8.encode(xmp),
  ]);

  static Uint8List _pngChunk(String type, List<int> data) {
    final typeBytes = ascii.encode(type);
    final crc = _crc32(_concat([typeBytes, data]));
    final len = data.length;
    return _concat([
      [(len >> 24) & 0xFF, (len >> 16) & 0xFF, (len >> 8) & 0xFF, len & 0xFF],
      typeBytes,
      data,
      [(crc >> 24) & 0xFF, (crc >> 16) & 0xFF, (crc >> 8) & 0xFF, crc & 0xFF],
    ]);
  }

  static int _u32be(Uint8List b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static final Uint32List _crcTable = () {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      t[n] = c;
    }
    return t;
  }();

  static int _crc32(List<int> bytes) {
    var c = 0xFFFFFFFF;
    for (final b in bytes) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  // ── WebP ─────────────────────────────────────────────────────────────────

  static const _riff = [0x52, 0x49, 0x46, 0x46]; // RIFF
  static const _webp = [0x57, 0x45, 0x42, 0x50]; // WEBP

  static const int _flagIcc = 0x20;
  static const int _flagAlpha = 0x10;
  static const int _flagExif = 0x08;
  static const int _flagXmp = 0x04;

  static Future<MetadataEditPlan?> _planWebp(MetadataSource s, MetadataEdit edit) async {
    final chunks = <_WebpChunk>[];
    var o = 12;
    while (o + 8 <= s.length) {
      final head = await s.read(o, 8);
      if (head.length < 8) break;
      final fourcc = String.fromCharCodes(head, 0, 4);
      final len = head[4] | (head[5] << 8) | (head[6] << 16) | (head[7] << 24);
      final end = o + 8 + len + (len & 1);
      if (o + 8 + len > s.length) {
        throw const MetadataEditException(MetadataEditFailure.malformed, 'webp chunk');
      }
      // Some writers leave out the pad byte of an odd-sized last chunk.
      chunks.add(_WebpChunk(fourcc, o, len, end > s.length ? s.length : end, padMissing: end > s.length));
      o = end;
    }
    if (chunks.isEmpty) {
      throw const MetadataEditException(MetadataEditFailure.malformed, 'webp empty');
    }

    final exifChunk = chunks.where((c) => c.fourcc == 'EXIF').firstOrNull;
    final xmpChunk = chunks.where((c) => c.fourcc == 'XMP ').firstOrNull;
    Uint8List? tiff;
    if (exifChunk != null) {
      tiff = await _payload(s, exifChunk.start + 8, exifChunk.start + 8 + exifChunk.length);
      if (tiff.length >= 6 && _eq(tiff, 0, _exifId)) tiff = Uint8List.sublistView(tiff, 6);
    }
    String? xmp;
    if (xmpChunk != null) {
      xmp = utf8.decode(
        await _payload(s, xmpChunk.start + 8, xmpChunk.start + 8 + xmpChunk.length),
        allowMalformed: true,
      );
    }

    final result = _apply(tiff, xmp, edit);
    var changed = result.exifChanged || result.xmpChanged;

    final dropIcc = edit.strip.contains(MetadataKind.iccProfile);
    final kept = <_WebpChunk>[];
    for (final c in chunks) {
      final drop = (c.fourcc == 'EXIF' && result.tiff == null && edit.strip.contains(MetadataKind.exif)) ||
          (c.fourcc == 'XMP ' && result.xmp == null && edit.strip.contains(MetadataKind.xmp)) ||
          (c.fourcc == 'ICCP' && dropIcc);
      if (drop) {
        changed = true;
        continue;
      }
      kept.add(c);
    }
    if (!changed) return null;

    // Flags of the extended header follow what is actually in the file.
    final first = chunks.first;
    var flags = 0;
    var canvasW = 0;
    var canvasH = 0;
    if (first.fourcc == 'VP8X') {
      final h = await _payload(s, first.start + 8, first.start + 8 + (first.length < 10 ? 10 : first.length));
      flags = h[0];
      canvasW = h[4] | (h[5] << 8) | (h[6] << 16);
      canvasH = h[7] | (h[8] << 8) | (h[9] << 16);
    } else {
      final dims = await _webpSimpleDimensions(s, first);
      if (dims == null) {
        throw const MetadataEditException(MetadataEditFailure.malformed, 'webp size');
      }
      canvasW = dims.width - 1;
      canvasH = dims.height - 1;
      if (dims.alpha) flags |= _flagAlpha;
    }
    flags &= ~(_flagIcc | _flagExif | _flagXmp);
    if (kept.any((c) => c.fourcc == 'ICCP')) flags |= _flagIcc;
    final writeExif = result.tiff != null;
    final writeXmp = result.xmp != null;
    if (writeExif) flags |= _flagExif;
    if (writeXmp) flags |= _flagXmp;

    final vp8x = Uint8List(18)
      ..setRange(0, 4, ascii.encode('VP8X'))
      ..[4] = 10
      ..[8] = flags
      ..[12] = canvasW & 0xFF
      ..[13] = (canvasW >> 8) & 0xFF
      ..[14] = (canvasW >> 16) & 0xFF
      ..[15] = canvasH & 0xFF
      ..[16] = (canvasH >> 8) & 0xFF
      ..[17] = (canvasH >> 16) & 0xFF;

    final body = <EditPiece>[
      LiteralPiece(Uint8List.fromList(_webp)),
      // The extended header is always rewritten, even when the file had one:
      // its flags must match what is in the file now.
      LiteralPiece(vp8x),
    ];
    for (final c in kept) {
      if (c.fourcc == 'VP8X' || c.fourcc == 'EXIF' || c.fourcc == 'XMP ') continue;
      body.add(CopyPiece(c.start, c.end));
      // Chunks added after this one must start on an even offset.
      if (c.padMissing) body.add(LiteralPiece(Uint8List.fromList([0])));
    }
    if (writeExif) body.add(LiteralPiece(_webpChunk('EXIF', result.tiff!)));
    if (writeXmp) body.add(LiteralPiece(_webpChunk('XMP ', utf8.encode(result.xmp!))));

    var bodyLength = 0;
    for (final p in body) {
      bodyLength += switch (p) {
        LiteralPiece(:final bytes) => bytes.length,
        CopyPiece(:final start, :final end) => end - start,
      };
    }
    // The RIFF size counts everything after its own 8 bytes.
    return MetadataEditPlan([
      LiteralPiece(
        Uint8List.fromList([
          ..._riff,
          bodyLength & 0xFF,
          (bodyLength >> 8) & 0xFF,
          (bodyLength >> 16) & 0xFF,
          (bodyLength >> 24) & 0xFF,
        ]),
      ),
      ...body,
    ]);
  }

  static Uint8List _webpChunk(String fourcc, List<int> data) {
    final len = data.length;
    return _concat([
      ascii.encode(fourcc),
      [len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF, (len >> 24) & 0xFF],
      data,
      if (len.isOdd) [0],
    ]);
  }

  static Future<({int width, int height, bool alpha})?> _webpSimpleDimensions(
    MetadataSource s,
    _WebpChunk c,
  ) async {
    final d = await s.read(c.start + 8, 16);
    if (c.fourcc == 'VP8 ' && d.length >= 10 && d[3] == 0x9D && d[4] == 0x01 && d[5] == 0x2A) {
      return (
        width: (d[6] | (d[7] << 8)) & 0x3FFF,
        height: (d[8] | (d[9] << 8)) & 0x3FFF,
        alpha: false,
      );
    }
    if (c.fourcc == 'VP8L' && d.length >= 5 && d[0] == 0x2F) {
      final bits = d[1] | (d[2] << 8) | (d[3] << 16) | (d[4] << 24);
      return (
        width: (bits & 0x3FFF) + 1,
        height: ((bits >> 14) & 0x3FFF) + 1,
        alpha: ((bits >> 28) & 1) == 1,
      );
    }
    return null;
  }
}

class _Result {
  _Result(this.tiff, this.xmp);
  Uint8List? tiff;
  String? xmp;
  bool exifChanged = false;
  bool xmpChanged = false;
}

class _JpegItem {
  _JpegItem.original(this.marker, this.start, this.end, this.kind) : literalBytes = null;
  _JpegItem.literal(this.marker, Uint8List bytes, this.kind)
    : literalBytes = bytes,
      start = null,
      end = null;

  final int marker;
  final int? start;
  final int? end;
  final Uint8List? literalBytes;
  final String kind;

  int get length => literalBytes?.length ?? (end! - start!);

  EditPiece get piece => literalBytes != null ? LiteralPiece(literalBytes!) : CopyPiece(start!, end!);
}

class _PngChunk {
  _PngChunk(this.type, this.start, this.end, this.kind);
  final String type;
  final int start;
  final int end;
  final String kind;
}

class _WebpChunk {
  _WebpChunk(this.fourcc, this.start, this.length, this.end, {this.padMissing = false});
  final String fourcc;
  final int start;

  /// Size of the data, without the 8-byte header or the padding byte.
  final int length;
  final int end;

  /// The data has an odd size and the file ends before its pad byte.
  final bool padMissing;
}
