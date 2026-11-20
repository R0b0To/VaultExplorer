import 'dart:convert';
import 'dart:typed_data';

import 'heif_container.dart';
import 'metadata_source.dart';
import 'tiff_exif_editor.dart';
import 'xmp_editor.dart';

/// Plans the change of the date taken in a HEIF (HEIC) file.
///
/// The Exif block and the XMP packet of a HEIF file are *items*: byte ranges
/// inside `mdat` that the `iloc` box points to by absolute file offsets. That
/// shapes how a date is written, so that nothing that already has an address
/// ever moves:
///
///  - If the new bytes are exactly as long as the old ones (the usual case:
///    an Exif date is always 19 characters and the Exif editor overwrites it
///    where it stands), they are written over the old ones and nothing else
///    in the file changes.
///  - Otherwise (a date that had to be added to the Exif block, an XMP date
///    that got longer) the new bytes go into a new `mdat` box at the end of
///    the file, and the item's `iloc` entry is re-pointed to them. The old
///    bytes stay behind, unused. Every other offset in the file is untouched.
///
/// The (large) picture data is never read: the result is a plan of "copy
/// this, write that" like every other edit in this folder.
class HeifMetadataEditor {
  const HeifMetadataEditor._();

  /// File extensions (lower case, no dot) of the HEIF files edited here.
  static const Set<String> extensions = {'heic', 'heif', 'hif'};

  /// The plan for setting the date taken to [taken] (a wall-clock time), or
  /// null when the file already says so. Throws [MetadataEditException] when
  /// the file has no Exif block to put the date in, or its structure cannot
  /// be edited safely.
  static Future<MetadataEditPlan?> planDate(
    MetadataSource source,
    DateTime taken,
  ) async {
    final layout = await HeifLayout.locate(source);
    if (layout == null) {
      throw const MetadataEditException(
        MetadataEditFailure.malformed,
        'heif meta',
      );
    }
    final exifItem = layout.exif;
    if (exifItem == null) {
      // Adding an item would grow `iinf`, which moves everything after it.
      throw const MetadataEditException(
        MetadataEditFailure.unsupportedFormat,
        'heif without an Exif item',
      );
    }

    final changes = <_ItemChange>[];

    // Exif.
    final exifRange = _only(layout, exifItem);
    final exifOld = await layout.readItem(source, exifItem);
    if (exifRange == null || exifOld == null) {
      throw const MetadataEditException(
        MetadataEditFailure.unreadableExif,
        'heif Exif location',
      );
    }
    final tiffAt = HeifLayout.exifTiffOffset(exifOld);
    final editor = tiffAt == null
        ? null
        : TiffExifEditor.tryParse(Uint8List.sublistView(exifOld, tiffAt));
    if (tiffAt == null ||
        editor == null ||
        !editor.setDates(exifDateString(taken))) {
      throw const MetadataEditException(MetadataEditFailure.unreadableExif);
    }
    final exifNew = Uint8List.fromList([
      ...Uint8List.sublistView(exifOld, 0, tiffAt),
      ...editor.bytes,
    ]);
    if (!_same(exifOld, exifNew)) {
      changes.add(_ItemChange(exifItem, exifRange, exifNew, false));
    }

    // XMP, kept in step with Exif the way the JPEG path does. A packet that
    // cannot be found or edited is left alone: Exif is the date that counts.
    final xmpItem = layout.xmp;
    if (xmpItem != null) {
      final xmpRange = _only(layout, xmpItem);
      final xmpOld = await layout.readItem(source, xmpItem);
      if (xmpRange != null && xmpOld != null) {
        final text = utf8.decode(xmpOld, allowMalformed: true);
        final next = XmpEditor.setDates(text, xmpDateString(taken));
        if (next != text) {
          changes.add(
            _ItemChange(
              xmpItem,
              xmpRange,
              Uint8List.fromList(utf8.encode(next)),
              true,
            ),
          );
        }
      }
    }
    if (changes.isEmpty) return null;

    // In place where the length allows, else moved to the end of the file.
    final overwrites = <_Overwrite>[];
    final appended = BytesBuilder(copy: false);
    const mdatHeader = 8;
    final appendBase = layout.fileLength + mdatHeader;
    for (final c in changes) {
      var data = c.next;
      final oldLength = c.range.end - c.range.start;
      // An XMP packet may be padded with blanks, so a shorter one fits.
      if (c.isXmp && data.length < oldLength) {
        data = Uint8List(oldLength)
          ..fillRange(0, oldLength, 0x20)
          ..setRange(0, data.length, data);
      }
      if (data.length == oldLength) {
        overwrites.add(_Overwrite(c.range.start, data));
        continue;
      }

      final loc = c.item.location!;
      final extent = loc.extents.single;
      if (loc.constructionMethod != 0 ||
          extent.offsetFieldAt < 0 ||
          extent.lengthFieldAt < 0) {
        // Data inside `idat` (in the middle of `meta`) cannot grow.
        throw const MetadataEditException(
          MetadataEditFailure.unreadableExif,
          'heif item cannot be moved',
        );
      }
      final newAbsolute = appendBase + appended.length;
      final storedOffset = newAbsolute - loc.baseOffset;
      if (storedOffset < 0 ||
          !_fits(storedOffset, layout.offsetSize) ||
          !_fits(data.length, layout.lengthSize)) {
        throw const MetadataEditException(
          MetadataEditFailure.tooLarge,
          'heif iloc field too small',
        );
      }
      appended.add(data);
      overwrites
        ..add(
          _Overwrite(
            extent.offsetFieldAt,
            _beBytes(storedOffset, layout.offsetSize),
          ),
        )
        ..add(
          _Overwrite(
            extent.lengthFieldAt,
            _beBytes(data.length, layout.lengthSize),
          ),
        );
    }

    overwrites.sort((a, b) => a.start.compareTo(b.start));
    final pieces = <EditPiece>[];
    var at = 0;
    for (final o in overwrites) {
      if (o.start < at || o.start + o.bytes.length > layout.fileLength) {
        throw const MetadataEditException(
          MetadataEditFailure.malformed,
          'heif overlapping data',
        );
      }
      pieces
        ..add(CopyPiece(at, o.start))
        ..add(LiteralPiece(o.bytes));
      at = o.start + o.bytes.length;
    }
    pieces.add(CopyPiece(at, layout.fileLength));

    if (appended.length > 0) {
      final payload = appended.takeBytes();
      final size = mdatHeader + payload.length;
      if (size > 0xFFFFFFFF) {
        throw const MetadataEditException(MetadataEditFailure.tooLarge);
      }
      pieces
        ..add(LiteralPiece(_beBytes(size, 4)))
        ..add(LiteralPiece(Uint8List.fromList(ascii.encode('mdat'))))
        ..add(LiteralPiece(payload));
    }
    return MetadataEditPlan(pieces);
  }

  /// The one range of an item stored in a single piece, or null.
  static ({int start, int end})? _only(HeifLayout layout, HeifItem item) {
    final ranges = layout.rangesOf(item);
    if (ranges == null || ranges.length != 1) return null;
    return ranges.single;
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Whether [value] fits in [size] bytes (0 bytes hold nothing).
  static bool _fits(int value, int size) {
    if (size <= 0) return false;
    if (size >= 8) return value >= 0;
    return value >= 0 && value < (1 << (8 * size));
  }

  static Uint8List _beBytes(int value, int size) {
    final b = Uint8List(size);
    for (var i = size - 1; i >= 0; i--) {
      b[i] = value & 0xFF;
      value >>= 8;
    }
    return b;
  }
}

class _ItemChange {
  _ItemChange(this.item, this.range, this.next, this.isXmp);
  final HeifItem item;
  final ({int start, int end}) range;
  final Uint8List next;
  final bool isXmp;
}

class _Overwrite {
  _Overwrite(this.start, this.bytes);
  final int start;
  final Uint8List bytes;
}
