import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'metadata_source.dart';

/// One stored piece of an item's data: an extent of the `iloc` box.
class HeifExtent {
  const HeifExtent({
    required this.offset,
    required this.length,
    required this.offsetFieldAt,
    required this.lengthFieldAt,
  });

  /// `extent_offset` as stored: counted from the item's base offset, which is
  /// counted from the start of the file (or of `idat`, see
  /// [HeifItemLocation.constructionMethod]).
  final int offset;

  /// `extent_length` as stored. 0 means "up to the end of the data area".
  final int length;

  /// Where the two fields sit in the file, so they can be rewritten in place.
  /// -1 when the box does not store the field (its size is 0).
  final int offsetFieldAt;
  final int lengthFieldAt;
}

/// Where an item's data is, according to the `iloc` box.
class HeifItemLocation {
  const HeifItemLocation({
    required this.constructionMethod,
    required this.dataReferenceIndex,
    required this.baseOffset,
    required this.extents,
  });

  /// 0: file offsets, 1: offsets into the `idat` box, 2: item offsets.
  final int constructionMethod;

  /// 0 for data in this file; anything else is in another file.
  final int dataReferenceIndex;
  final int baseOffset;
  final List<HeifExtent> extents;
}

/// An entry of the `iinf` box, with its place from the `iloc` box.
class HeifItem {
  const HeifItem({
    required this.id,
    required this.type,
    required this.contentType,
    required this.location,
  });

  final int id;

  /// Four-character item type (`Exif`, `mime`, `hvc1`, `grid`...).
  final String type;

  /// The MIME type of a `mime` item.
  final String? contentType;
  final HeifItemLocation? location;

  bool get isExif => type == 'Exif';
  bool get isXmp =>
      type == 'mime' && contentType?.toLowerCase() == 'application/rdf+xml';
}

/// What a HEIF (HEIC) file's `meta` box says about where its items live.
///
/// HEIF is an ISO base media file: a tree of boxes. The `meta` box lists the
/// items (the picture tiles, the Exif block, the XMP packet) and where each
/// one's bytes are; the bytes themselves sit in `mdat`. Everything is
/// addressed by absolute file offsets, so nothing here may be moved without
/// the `iloc` box being told.
///
/// The reader of the "all metadata" view has its own copy of this walk that
/// only reads; this one also remembers where each `iloc` field is, because the
/// editor has to rewrite them in place.
class HeifLayout {
  HeifLayout._({
    required this.fileLength,
    required this.metaStart,
    required this.metaEnd,
    required this.idatStart,
    required this.idatEnd,
    required this.offsetSize,
    required this.lengthSize,
    required this.items,
  });

  /// Size of the whole file (not of what was read of it).
  final int fileLength;

  /// The `meta` box, header included.
  final int metaStart;
  final int metaEnd;

  /// Payload of the `idat` box, or -1 when there is none.
  final int idatStart;
  final int idatEnd;

  /// Width in bytes of the `extent_offset` and `extent_length` fields.
  final int offsetSize;
  final int lengthSize;

  final List<HeifItem> items;

  HeifItem? get exif => items.where((i) => i.isExif).firstOrNull;
  HeifItem? get xmp => items.where((i) => i.isXmp).firstOrNull;

  /// The absolute `[start, end)` byte ranges of [item]'s data, in order, or
  /// null when they cannot be found in this file (data in another file, a
  /// construction method this does not know, or extents outside the data).
  List<({int start, int end})>? rangesOf(HeifItem item) {
    final loc = item.location;
    if (loc == null || loc.dataReferenceIndex != 0 || loc.extents.isEmpty) {
      return null;
    }
    final int dataStart;
    final int dataEnd;
    switch (loc.constructionMethod) {
      case 0:
        dataStart = 0;
        dataEnd = fileLength;
      case 1:
        if (idatStart < 0) return null;
        dataStart = idatStart;
        dataEnd = idatEnd;
      default:
        return null;
    }
    final ranges = <({int start, int end})>[];
    for (final e in loc.extents) {
      final start = dataStart + loc.baseOffset + e.offset;
      if (start < dataStart || start > dataEnd) return null;
      final length = e.length == 0 ? dataEnd - start : e.length;
      if (length < 0 || start + length > dataEnd) return null;
      ranges.add((start: start, end: start + length));
    }
    return ranges;
  }

  // ── Finding the meta box ───────────────────────────────────────────────

  /// Biggest `meta` box that is read. Real ones are a few kilobytes to a few
  /// hundred; a larger claim is a damaged file.
  static const int maxMetaBytes = 16 * 1024 * 1024;

  /// Reads the layout of the file [s] by walking its top-level boxes. Null
  /// when the file has no usable `meta` box.
  static Future<HeifLayout?> locate(MetadataSource s) async {
    final length = s.length;
    var offset = 0;
    for (var i = 0; i < 64 && offset + 8 <= length; i++) {
      final head = await s.read(offset, 16);
      final box = _boxHeader(head, offset, length);
      if (box == null) return null;
      if (box.type == 'meta') {
        if (box.size > maxMetaBytes) return null;
        final bytes = await s.read(offset, box.size);
        if (bytes.length != box.size) return null;
        return _parseMeta(bytes, offset, box.header, length);
      }
      offset += box.size;
    }
    return null;
  }

  /// Like [locate], for a file whose first bytes are [head] (its total size
  /// being [fileLength]). Null when the `meta` box is not wholly inside
  /// [head].
  static HeifLayout? fromHeader(Uint8List head, int fileLength) {
    var offset = 0;
    for (var i = 0; i < 64 && offset + 8 <= head.length; i++) {
      final box = _boxHeader(
        Uint8List.sublistView(head, offset, math.min(head.length, offset + 16)),
        offset,
        fileLength,
      );
      if (box == null) return null;
      if (box.type == 'meta') {
        if (box.size > maxMetaBytes || offset + box.size > head.length) {
          return null;
        }
        return _parseMeta(
          Uint8List.sublistView(head, offset, offset + box.size),
          offset,
          box.header,
          fileLength,
        );
      }
      offset += box.size;
    }
    return null;
  }

  static ({String type, int size, int header})? _boxHeader(
    Uint8List head,
    int offset,
    int parentEnd,
  ) {
    if (head.length < 8 || parentEnd - offset < 8) return null;
    var size = _u32(head, 0);
    final type = String.fromCharCodes(head, 4, 8);
    var header = 8;
    if (size == 1) {
      if (head.length < 16) return null;
      size = ByteData.sublistView(head, 8, 16).getUint64(0, Endian.big);
      header = 16;
    } else if (size == 0) {
      size = parentEnd - offset;
    }
    if (size < header || size > parentEnd - offset) return null;
    return (type: type, size: size, header: header);
  }

  // ── Parsing the meta box ───────────────────────────────────────────────

  /// [box] is the whole `meta` box (header included) that starts at [start]
  /// in the file.
  static HeifLayout? _parseMeta(
    Uint8List box,
    int start,
    int headerSize,
    int fileLength,
  ) {
    try {
      // A MetaBox starts with version and flags before its child boxes.
      var p = headerSize + 4;
      int? iinfAt, ilocAt, idatAt;
      final ends = <int, int>{};
      while (p + 8 <= box.length) {
        final child = _boxHeader(
          Uint8List.sublistView(box, p, math.min(box.length, p + 16)),
          p,
          box.length,
        );
        if (child == null) break;
        final payload = p + child.header;
        switch (child.type) {
          case 'iinf':
            iinfAt ??= payload;
          case 'iloc':
            ilocAt ??= payload;
          case 'idat':
            idatAt ??= payload;
        }
        ends[payload] = p + child.size;
        p += child.size;
      }
      if (iinfAt == null || ilocAt == null) return null;

      final types = _readItemInfo(box, iinfAt, ends[iinfAt]!);
      final iloc = _readItemLocations(box, ilocAt, ends[ilocAt]!, start);
      if (iloc == null) return null;

      final items = <HeifItem>[
        for (final t in types)
          HeifItem(
            id: t.id,
            type: t.type,
            contentType: t.contentType,
            location: iloc.locations[t.id],
          ),
      ];
      return HeifLayout._(
        fileLength: fileLength,
        metaStart: start,
        metaEnd: start + box.length,
        idatStart: idatAt == null ? -1 : start + idatAt,
        idatEnd: idatAt == null ? -1 : start + ends[idatAt]!,
        offsetSize: iloc.offsetSize,
        lengthSize: iloc.lengthSize,
        items: items,
      );
    } on RangeError {
      return null;
    }
  }

  static List<({int id, String type, String? contentType})> _readItemInfo(
    Uint8List b,
    int iinf,
    int iinfEnd,
  ) {
    final version = b[iinf];
    final count = version == 0 ? _u16(b, iinf + 4) : _u32(b, iinf + 4);
    var p = iinf + (version == 0 ? 6 : 8);
    final items = <({int id, String type, String? contentType})>[];
    for (var i = 0; i < count && i < 10000 && p + 8 <= iinfEnd; i++) {
      final size = _u32(b, p);
      final type = String.fromCharCodes(b, p + 4, p + 8);
      if (size < 8 || p + size > iinfEnd) break;
      final end = p + size;
      final body = p + 8;
      p = end;
      if (type != 'infe') continue;
      final v = b[body];
      if (v != 2 && v != 3) continue;
      final idSize = v == 2 ? 2 : 4;
      final id = idSize == 2 ? _u16(b, body + 4) : _u32(b, body + 4);
      final typeAt = body + 4 + idSize + 2;
      if (typeAt + 4 > end) continue;
      final itemType = String.fromCharCodes(b, typeAt, typeAt + 4);
      String? contentType;
      if (itemType == 'mime') {
        final nameEnd = _zero(b, typeAt + 4, end);
        if (nameEnd >= 0) {
          final typeEnd = _zero(b, nameEnd + 1, end);
          if (typeEnd >= 0) {
            contentType = latin1.decode(
              Uint8List.sublistView(b, nameEnd + 1, typeEnd),
            );
          }
        }
      }
      items.add((id: id, type: itemType, contentType: contentType));
    }
    return items;
  }

  static ({
    Map<int, HeifItemLocation> locations,
    int offsetSize,
    int lengthSize,
  })?
  _readItemLocations(Uint8List b, int iloc, int ilocEnd, int boxStart) {
    final version = b[iloc];
    if (version > 2) return null;
    final offsetSize = b[iloc + 4] >> 4;
    final lengthSize = b[iloc + 4] & 0x0F;
    final baseOffsetSize = b[iloc + 5] >> 4;
    final indexSize = version == 0 ? 0 : b[iloc + 5] & 0x0F;
    var p = iloc + 6;

    int? take(int size) {
      if (size < 0 || size > 8 || p + size > ilocEnd) return null;
      var v = 0;
      for (var i = 0; i < size; i++) {
        v = (v << 8) | b[p++];
      }
      return v < 0 ? null : v;
    }

    final count = take(version < 2 ? 2 : 4);
    if (count == null || count > 10000) return null;
    final locations = <int, HeifItemLocation>{};
    for (var i = 0; i < count; i++) {
      final id = take(version < 2 ? 2 : 4);
      if (id == null) break;
      var method = 0;
      if (version >= 1) {
        final m = take(2);
        if (m == null) break;
        method = m & 0x0F;
      }
      final dataRef = take(2);
      final base = take(baseOffsetSize);
      final extentCount = take(2);
      if (dataRef == null ||
          base == null ||
          extentCount == null ||
          extentCount > 256) {
        break;
      }
      final extents = <HeifExtent>[];
      var ok = true;
      for (var j = 0; j < extentCount; j++) {
        if (version >= 1 && indexSize > 0 && take(indexSize) == null) {
          ok = false;
          break;
        }
        final offsetAt = offsetSize == 0 ? -1 : boxStart + p;
        final offset = take(offsetSize);
        final lengthAt = lengthSize == 0 ? -1 : boxStart + p;
        final length = take(lengthSize);
        if (offset == null || length == null) {
          ok = false;
          break;
        }
        extents.add(
          HeifExtent(
            offset: offset,
            length: length,
            offsetFieldAt: offsetAt,
            lengthFieldAt: lengthAt,
          ),
        );
      }
      if (!ok) break;
      locations[id] = HeifItemLocation(
        constructionMethod: method,
        dataReferenceIndex: dataRef,
        baseOffset: base,
        extents: extents,
      );
    }
    return (
      locations: locations,
      offsetSize: offsetSize,
      lengthSize: lengthSize,
    );
  }

  // ── Item data ──────────────────────────────────────────────────────────

  /// The most item data that is read (an Exif block or XMP packet is small).
  static const int maxItemBytes = 8 * 1024 * 1024;

  /// The data of [item], read from [s]; null when it cannot be found or is
  /// bigger than [maxBytes].
  Future<Uint8List?> readItem(
    MetadataSource s,
    HeifItem item, {
    int maxBytes = maxItemBytes,
  }) async {
    final ranges = rangesOf(item);
    if (ranges == null) return null;
    final out = BytesBuilder(copy: false);
    var total = 0;
    for (final r in ranges) {
      final n = r.end - r.start;
      total += n;
      if (total > maxBytes) return null;
      final bytes = await s.read(r.start, n);
      if (bytes.length != n) return null;
      out.add(bytes);
    }
    return out.takeBytes();
  }

  /// The data of [item] when all of it is inside [head] (the file's first
  /// bytes) and not bigger than [maxBytes], else null.
  Uint8List? itemFromHeader(
    Uint8List head,
    HeifItem item, {
    int maxBytes = maxItemBytes,
  }) {
    final ranges = rangesOf(item);
    if (ranges == null) return null;
    final out = BytesBuilder(copy: false);
    var total = 0;
    for (final r in ranges) {
      if (r.end > head.length) return null;
      total += r.end - r.start;
      if (total > maxBytes) return null;
      out.add(Uint8List.sublistView(head, r.start, r.end));
    }
    return out.takeBytes();
  }

  /// Where the TIFF structure starts inside the data of an `Exif` item, or
  /// null when there is none. The item starts with the distance from its
  /// fourth byte to the TIFF header (6 when `Exif\0\0` comes first, as in
  /// iPhone files).
  static int? exifTiffOffset(Uint8List item) {
    bool tiffAt(int o) =>
        o + 8 <= item.length &&
        ((item[o] == 0x49 && item[o + 1] == 0x49) ||
            (item[o] == 0x4D && item[o + 1] == 0x4D));
    // Some writers leave the offset field out.
    if (tiffAt(0)) return 0;
    if (item.length < 4) return null;
    var start = 4 + _u32(item, 0);
    if (start < 4 || start + 8 > item.length) return null;
    // ...and some write `Exif\0\0` without counting it in the offset.
    if (start + 6 <= item.length &&
        item[start] == 0x45 &&
        item[start + 1] == 0x78 &&
        item[start + 2] == 0x69 &&
        item[start + 3] == 0x66 &&
        item[start + 4] == 0 &&
        item[start + 5] == 0) {
      start += 6;
    }
    return tiffAt(start) ? start : null;
  }

  static int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

  static int _u32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _zero(Uint8List b, int from, int end) {
    for (var i = from; i < end; i++) {
      if (b[i] == 0) return i;
    }
    return -1;
  }
}
