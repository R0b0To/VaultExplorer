import 'dart:convert';
import 'dart:typed_data';

/// Edits the Exif block of an image (a TIFF structure) without rebuilding it.
///
/// Exif is a web of absolute offsets: the MakerNote, the embedded thumbnail
/// and every long value are addressed from the start of the block, and some
/// camera makers' MakerNotes carry offsets of their own that nothing else
/// knows about. Re-serialising the whole block would silently break those.
///
/// So nothing already in the block ever moves:
///  - a value that fits where it is, is overwritten in place;
///  - a value that does not fit, and any new tag, is added at the end of the
///    block, and only the 12-byte entry (or, to add a tag, the small table of
///    entries of that one IFD) is rewritten at the end and re-pointed.
///
/// The few dead bytes the old table leaves behind are the price of never
/// invalidating an offset.
class TiffExifEditor {
  TiffExifEditor._(this._data, this._little);

  Uint8List _data;
  final bool _little;

  static const int tagOrientation = 0x0112;
  static const int tagDateTime = 0x0132;
  static const int tagExifPointer = 0x8769;
  static const int tagDateTimeOriginal = 0x9003;
  static const int tagDateTimeDigitized = 0x9004;

  static const int typeAscii = 2;
  static const int typeShort = 3;
  static const int typeLong = 4;

  /// Parses [tiff] (the bytes after `Exif\0\0`) for editing, or null when it
  /// is not a TIFF structure this editor can walk safely.
  static TiffExifEditor? tryParse(Uint8List tiff) {
    if (tiff.length < 8) return null;
    final le = tiff[0] == 0x49 && tiff[1] == 0x49;
    final be = tiff[0] == 0x4D && tiff[1] == 0x4D;
    if (!le && !be) return null;
    final editor = TiffExifEditor._(Uint8List.fromList(tiff), le);
    if (editor._u16(2) != 42) return null;
    final first = editor._u32(4);
    // 0 means "no IFD"; anything else must point inside the block.
    if (first != 0 && !editor._ifdFits(first)) return null;
    return editor;
  }

  /// The edited block.
  Uint8List get bytes => _data;

  // ── Reading ──────────────────────────────────────────────────────────────

  /// EXIF orientation (1..8), or null when the block does not say.
  int? get orientation {
    final ifd0 = _u32(4);
    if (ifd0 == 0) return null;
    final e = _find(ifd0, tagOrientation);
    if (e == null || _type(e) != typeShort) return null;
    final v = _u16(e + 8);
    return v >= 1 && v <= 8 ? v : null;
  }

  // ── Writing ──────────────────────────────────────────────────────────────

  /// Sets Date/Time Original, Date/Time Digitized and Date/Time (the three
  /// dates cameras write) to [exifDate], in `YYYY:MM:DD HH:MM:SS` form.
  /// Returns false when the block cannot take the change.
  bool setDates(String exifDate) {
    if (exifDate.length != 19) return false;
    return _setAscii(_Ifd.ifd0, tagDateTime, exifDate) &&
        _setAscii(_Ifd.exif, tagDateTimeOriginal, exifDate) &&
        _setAscii(_Ifd.exif, tagDateTimeDigitized, exifDate);
  }

  bool _setAscii(_Ifd which, int tag, String text) {
    final value = Uint8List.fromList([...ascii.encode(text), 0]);
    final ifdAt = _ifdOffset(which, createIfMissing: true);
    if (ifdAt == null) return false;
    final existing = _find(ifdAt, tag);
    if (existing != null) {
      final count = _u32(existing + 4);
      final size = _typeSize(_type(existing)) * count;
      if (_type(existing) == typeAscii && count >= value.length && size > 4) {
        final at = _u32(existing + 8);
        if (at + count > _data.length) return false;
        _data.fillRange(at, at + count, 0);
        _data.setRange(at, at + value.length, value);
        return true;
      }
      // Too small (or not text): put the value at the end and re-point.
      final at = _appendBytes(value);
      _putU16(existing + 2, typeAscii);
      _putU32(existing + 4, value.length);
      _putU32(existing + 8, at);
      return true;
    }
    return _addEntry(
      which,
      _NewEntry(tag, typeAscii, value.length, value),
    );
  }

  // ── IFD plumbing ─────────────────────────────────────────────────────────

  /// Where the entry table of [which] starts; creates the IFD when missing
  /// and [createIfMissing] (an empty one at the end of the block).
  int? _ifdOffset(_Ifd which, {required bool createIfMissing}) {
    var ifd0 = _u32(4);
    if (ifd0 == 0) {
      if (!createIfMissing) return null;
      ifd0 = _appendIfd(const []);
      _putU32(4, ifd0);
    }
    if (which == _Ifd.ifd0) return ifd0;
    final pointer = _find(ifd0, tagExifPointer);
    if (pointer != null) {
      final at = _u32(pointer + 8);
      return _ifdFits(at) ? at : null;
    }
    if (!createIfMissing) return null;
    final exif = _appendIfd(const []);
    return _addEntry(
          _Ifd.ifd0,
          _NewEntry(tagExifPointer, typeLong, 1, _le32(exif)),
        )
        ? exif
        : null;
  }

  /// Adds [entry] to the IFD [which] by writing a longer copy of its table at
  /// the end of the block (entries stay sorted by tag, as TIFF requires).
  bool _addEntry(_Ifd which, _NewEntry entry) {
    final ifdAt = _ifdOffset(which, createIfMissing: true);
    if (ifdAt == null) return false;
    final n = _u16(ifdAt);
    final rows = <_Row>[];
    for (var i = 0; i < n; i++) {
      final p = ifdAt + 2 + i * 12;
      rows.add(_Row(_u16(p), Uint8List.sublistView(_data, p, p + 12)));
    }
    final next = _u32(ifdAt + 2 + n * 12);

    // The new value goes at the end first, so its offset is known.
    final valueBytes = entry.value;
    Uint8List inline;
    if (valueBytes.length <= 4) {
      inline = Uint8List(4)..setRange(0, valueBytes.length, valueBytes);
    } else {
      inline = _le32(_appendBytes(valueBytes));
    }
    final row = Uint8List(12);
    _writeU16(row, 0, entry.tag);
    _writeU16(row, 2, entry.type);
    _writeU32(row, 4, entry.count);
    row.setRange(8, 12, inline);
    // [rows] hold copies in the file's own byte order; the new row was built
    // with the same helpers, so it matches.
    rows.removeWhere((r) => r.tag == entry.tag);
    rows.add(_Row(entry.tag, row));
    rows.sort((a, b) => a.tag.compareTo(b.tag));

    final table = Uint8List(2 + rows.length * 12 + 4);
    _writeU16(table, 0, rows.length);
    for (var i = 0; i < rows.length; i++) {
      table.setRange(2 + i * 12, 2 + i * 12 + 12, rows[i].bytes);
    }
    _writeU32(table, 2 + rows.length * 12, next);
    final newAt = _appendBytes(table);
    return _repoint(which, ifdAt, newAt);
  }

  /// Makes whatever pointed at the IFD at [oldAt] point at [newAt].
  bool _repoint(_Ifd which, int oldAt, int newAt) {
    if (which == _Ifd.ifd0) {
      _putU32(4, newAt);
      return true;
    }
    final ifd0 = _u32(4);
    final pointer = _find(ifd0, tagExifPointer);
    if (pointer == null) return false;
    _putU32(pointer + 8, newAt);
    return true;
  }

  int _appendIfd(List<_Row> rows) {
    final table = Uint8List(2 + rows.length * 12 + 4);
    _writeU16(table, 0, rows.length);
    return _appendBytes(table);
  }

  /// Appends [bytes] at an even offset and returns where they start.
  int _appendBytes(Uint8List bytes) {
    var start = _data.length;
    if (start.isOdd) start++;
    final grown = Uint8List(start + bytes.length)
      ..setRange(0, _data.length, _data)
      ..setRange(start, start + bytes.length, bytes);
    _data = grown;
    return start;
  }

  /// Offset of the 12-byte entry for [tag] in the IFD at [ifdAt], or null.
  int? _find(int ifdAt, int tag) {
    if (!_ifdFits(ifdAt)) return null;
    final n = _u16(ifdAt);
    for (var i = 0; i < n; i++) {
      final p = ifdAt + 2 + i * 12;
      if (_u16(p) == tag) return p;
    }
    return null;
  }

  bool _ifdFits(int at) {
    if (at < 8 || at + 2 > _data.length) return false;
    final n = _u16(at);
    return at + 2 + n * 12 + 4 <= _data.length;
  }

  int _type(int entryAt) => _u16(entryAt + 2);

  static int _typeSize(int type) => switch (type) {
    1 || 2 || 6 || 7 => 1,
    3 || 8 => 2,
    4 || 9 || 11 => 4,
    5 || 10 || 12 => 8,
    _ => 1,
  };

  // ── Byte order helpers ───────────────────────────────────────────────────

  int _u16(int o) => _little ? (_data[o] | (_data[o + 1] << 8)) : ((_data[o] << 8) | _data[o + 1]);

  int _u32(int o) => _little
      ? (_data[o] | (_data[o + 1] << 8) | (_data[o + 2] << 16) | (_data[o + 3] << 24))
      : ((_data[o] << 24) | (_data[o + 1] << 16) | (_data[o + 2] << 8) | _data[o + 3]);

  void _putU16(int o, int v) => _writeU16(_data, o, v);
  void _putU32(int o, int v) => _writeU32(_data, o, v);

  void _writeU16(Uint8List b, int o, int v) {
    if (_little) {
      b[o] = v & 0xFF;
      b[o + 1] = (v >> 8) & 0xFF;
    } else {
      b[o] = (v >> 8) & 0xFF;
      b[o + 1] = v & 0xFF;
    }
  }

  void _writeU32(Uint8List b, int o, int v) {
    if (_little) {
      b[o] = v & 0xFF;
      b[o + 1] = (v >> 8) & 0xFF;
      b[o + 2] = (v >> 16) & 0xFF;
      b[o + 3] = (v >> 24) & 0xFF;
    } else {
      b[o] = (v >> 24) & 0xFF;
      b[o + 1] = (v >> 16) & 0xFF;
      b[o + 2] = (v >> 8) & 0xFF;
      b[o + 3] = v & 0xFF;
    }
  }

  Uint8List _le32(int v) {
    final b = Uint8List(4);
    _writeU32(b, 0, v);
    return b;
  }

  // ── A fresh block ────────────────────────────────────────────────────────

  /// A minimal little-endian Exif block holding only the given fields; the
  /// way to give a file without Exif a date, or to keep just the orientation
  /// of a file whose Exif was removed.
  static Uint8List createMinimal({int? orientation, String? exifDate}) {
    final ifd0 = <_NewEntry>[];
    final exif = <_NewEntry>[];
    if (orientation != null) {
      ifd0.add(_NewEntry(tagOrientation, typeShort, 1, Uint8List.fromList([orientation & 0xFF, 0])));
    }
    Uint8List? dateBytes;
    if (exifDate != null) {
      dateBytes = Uint8List.fromList([...ascii.encode(exifDate), 0]);
      ifd0.add(_NewEntry(tagDateTime, typeAscii, dateBytes.length, dateBytes));
      exif.add(_NewEntry(tagDateTimeOriginal, typeAscii, dateBytes.length, dateBytes));
      exif.add(_NewEntry(tagDateTimeDigitized, typeAscii, dateBytes.length, dateBytes));
    }
    final hasExif = exif.isNotEmpty;
    if (hasExif) ifd0.add(_NewEntry(tagExifPointer, typeLong, 1, Uint8List(4)));
    ifd0.sort((a, b) => a.tag.compareTo(b.tag));
    exif.sort((a, b) => a.tag.compareTo(b.tag));

    int tableSize(List<_NewEntry> l) => 2 + l.length * 12 + 4;
    final ifd0At = 8;
    final exifAt = ifd0At + tableSize(ifd0);
    var dataAt = hasExif ? exifAt + tableSize(exif) : exifAt;

    final out = BytesBuilder(copy: false);
    final data = BytesBuilder(copy: false);
    final header = Uint8List(8)
      ..[0] = 0x49
      ..[1] = 0x49
      ..[2] = 42
      ..[4] = 8;
    out.add(header);

    Uint8List buildTable(List<_NewEntry> l, int Function(_NewEntry) valueAt) {
      final t = Uint8List(tableSize(l));
      t[0] = l.length & 0xFF;
      t[1] = (l.length >> 8) & 0xFF;
      for (var i = 0; i < l.length; i++) {
        final e = l[i];
        final p = 2 + i * 12;
        t[p] = e.tag & 0xFF;
        t[p + 1] = (e.tag >> 8) & 0xFF;
        t[p + 2] = e.type & 0xFF;
        t[p + 3] = (e.type >> 8) & 0xFF;
        t[p + 4] = e.count & 0xFF;
        t[p + 5] = (e.count >> 8) & 0xFF;
        if (e.value.length <= 4) {
          t.setRange(p + 8, p + 8 + e.value.length, e.value);
        } else {
          final at = valueAt(e);
          t[p + 8] = at & 0xFF;
          t[p + 9] = (at >> 8) & 0xFF;
          t[p + 10] = (at >> 16) & 0xFF;
          t[p + 11] = (at >> 24) & 0xFF;
        }
      }
      return t;
    }

    // Long values share one data area after both tables; the same date text
    // is stored once per use (20 bytes each, not worth sharing).
    int placeValue(_NewEntry e) {
      final at = dataAt;
      data.add(e.value);
      dataAt += e.value.length;
      if (dataAt.isOdd) {
        data.addByte(0);
        dataAt++;
      }
      return at;
    }

    final ifd0Entries = ifd0;
    if (hasExif) {
      final pointer = ifd0Entries.firstWhere((e) => e.tag == tagExifPointer);
      pointer.value
        ..[0] = exifAt & 0xFF
        ..[1] = (exifAt >> 8) & 0xFF
        ..[2] = (exifAt >> 16) & 0xFF
        ..[3] = (exifAt >> 24) & 0xFF;
    }
    out.add(buildTable(ifd0Entries, placeValue));
    if (hasExif) out.add(buildTable(exif, placeValue));
    out.add(data.takeBytes());
    return out.takeBytes();
  }
}

enum _Ifd { ifd0, exif }

class _NewEntry {
  _NewEntry(this.tag, this.type, this.count, this.value);
  final int tag;
  final int type;
  final int count;
  final Uint8List value;
}

class _Row {
  _Row(this.tag, this.bytes);
  final int tag;
  final Uint8List bytes;
}

/// Formats [d] (a wall-clock moment) as an Exif date, `YYYY:MM:DD HH:MM:SS`.
String exifDateString(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}:${two(d.month)}:${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

/// Formats [d] as an XMP date without a zone, `YYYY-MM-DDTHH:MM:SS`.
String xmpDateString(DateTime d) {
  final e = exifDateString(d);
  return '${e.substring(0, 4)}-${e.substring(5, 7)}-${e.substring(8, 10)}T${e.substring(11)}';
}
