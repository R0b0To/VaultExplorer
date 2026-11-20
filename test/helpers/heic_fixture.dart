import 'dart:convert';
import 'dart:typed_data';

/// A HEIC file laid out like the ones phones write: `ftyp`, then a `meta` box
/// (item list `iinf`, item locations `iloc`), then `mdat` holding the picture
/// data and, after it, the Exif block and the XMP packet as items.
///
/// The picture is a stand-in ([pixels]); what matters to the code under test
/// is the box structure and the absolute offsets in `iloc`.
class HeicFixture {
  HeicFixture._(this.bytes, this.exifAt, this.exifLength, this.pixelsAt);

  final Uint8List bytes;

  /// Where the Exif item's data starts, and how long it is.
  final int exifAt;
  final int exifLength;

  /// Where the stand-in picture data starts (its length is `pixels`).
  final int pixelsAt;

  static Uint8List box(String type, List<int> payload) {
    final size = 8 + payload.length;
    return Uint8List.fromList([
      (size >> 24) & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 8) & 0xFF,
      size & 0xFF,
      ...ascii.encode(type),
      ...payload,
    ]);
  }

  static Uint8List _fullBox(
    String type,
    int version,
    List<int> payload, {
    int flags = 0,
  }) => box(type, [version, 0, 0, flags, ...payload]);

  static List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
  static List<int> _u32(int v) => [
    (v >> 24) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 8) & 0xFF,
    v & 0xFF,
  ];

  /// The picture stand-in: easy to recognise, never equal to metadata.
  static Uint8List pixelData(int length) =>
      Uint8List.fromList(List.generate(length, (i) => (i * 31 + 7) & 0xFF));

  /// The `Exif` item data around a TIFF block: the 4-byte distance to the
  /// TIFF header (6, as iPhones write it), `Exif\0\0`, then the TIFF.
  static Uint8List exifItem(Uint8List tiff) => Uint8List.fromList([
    ..._u32(6),
    ...ascii.encode('Exif'),
    0,
    0,
    ...tiff,
  ]);

  /// [tiff] becomes the Exif item (null: no Exif item at all); [xmp] the XMP
  /// item. [pixels] is the size of the picture data in front of them, so a
  /// large value puts the Exif block far beyond a header read.
  ///
  /// With [ilocVersion] 1 the item entries carry a construction method.
  static HeicFixture build({
    Uint8List? tiff,
    String? xmp,
    int pixels = 4000,
    int ilocVersion = 0,
    int offsetSize = 4,
    int lengthSize = 4,
  }) {
    final exif = tiff == null ? null : exifItem(tiff);
    final xmpBytes = xmp == null ? null : Uint8List.fromList(utf8.encode(xmp));
    final picture = pixelData(pixels);

    Uint8List meta(int mdatPayloadAt) {
      final exifAt = mdatPayloadAt + picture.length;
      final xmpAt = exifAt + (exif?.length ?? 0);

      Uint8List infe(int id, String type, {String? mime}) => _fullBox('infe', 2, [
        ..._u16(id),
        ..._u16(0),
        ...ascii.encode(type),
        0, // item_name
        if (mime != null) ...[...ascii.encode(mime), 0],
      ]);

      final entries = [
        infe(1, 'hvc1'),
        if (exif != null) infe(2, 'Exif'),
        if (xmpBytes != null) infe(3, 'mime', mime: 'application/rdf+xml'),
      ];
      final iinf = _fullBox('iinf', 0, [
        ..._u16(entries.length),
        for (final e in entries) ...e,
      ]);

      List<int> field(int v, int size) => [
        for (var i = size - 1; i >= 0; i--) (v >> (8 * i)) & 0xFF,
      ];
      List<int> item(int id, int at, int length) => [
        ..._u16(id),
        if (ilocVersion >= 1) ..._u16(0), // construction method 0
        ..._u16(0), // data_reference_index
        // base_offset_size is 0: no base offset
        ..._u16(1), // extent_count
        ...field(at, offsetSize),
        ...field(length, lengthSize),
      ];
      final items = [
        item(1, mdatPayloadAt, picture.length),
        if (exif != null) item(2, exifAt, exif.length),
        if (xmpBytes != null) item(3, xmpAt, xmpBytes.length),
      ];
      final iloc = _fullBox(
        'iloc',
        ilocVersion,
        [
          (offsetSize << 4) | lengthSize,
          0, // base_offset_size 0, index_size 0
          ..._u16(items.length),
          for (final i in items) ...i,
        ],
      );
      final hdlr = _fullBox('hdlr', 0, [
        0, 0, 0, 0,
        ...ascii.encode('pict'),
        ...List.filled(12, 0),
        0,
      ]);
      final pitm = _fullBox('pitm', 0, _u16(1));
      return _fullBox('meta', 0, [...hdlr, ...pitm, ...iinf, ...iloc]);
    }

    final ftyp = box('ftyp', [
      ...ascii.encode('heic'),
      ..._u32(0),
      ...ascii.encode('mif1'),
      ...ascii.encode('heic'),
    ]);
    // The size of `meta` does not depend on the offsets it holds.
    final metaSize = meta(0).length;
    final mdatPayloadAt = ftyp.length + metaSize + 8;
    final m = meta(mdatPayloadAt);
    final mdat = box('mdat', [...picture, ...?exif, ...?xmpBytes]);
    final all = Uint8List.fromList([...ftyp, ...m, ...mdat]);
    return HeicFixture._(
      all,
      mdatPayloadAt + picture.length,
      exif?.length ?? 0,
      mdatPayloadAt,
    );
  }
}
