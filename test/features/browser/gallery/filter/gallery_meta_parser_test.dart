import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_parser.dart';

/// Builds a little-endian TIFF block with the given IFD0 / Exif / GPS entries.
Uint8List _tiff({
  String make = 'Canon',
  String model = 'Canon EOS R5',
  String? original = '2023:07:14 18:32:05',
  int orientation = 1,
  ({double lat, double lon})? gps,
}) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  // Layout: header(8) | IFD0 | exif IFD | gps IFD | data area
  final data = BytesBuilder();
  int dataOffset(int fixedEnd) => fixedEnd + data.length;

  final ifd0Count = 5 - (gps == null ? 1 : 0);
  final ifd0Size = 2 + ifd0Count * 12 + 4;
  final exifSize = 2 + 1 * 12 + 4;
  final gpsSize = 2 + 4 * 12 + 4;
  final ifd0At = 8;
  final exifAt = ifd0At + ifd0Size;
  final gpsAt = exifAt + exifSize;
  final fixedEnd = gpsAt + (gps == null ? 0 : gpsSize);

  int addAscii(String s) {
    final at = dataOffset(fixedEnd);
    data.add(utf8.encode(s));
    data.addByte(0);
    return at;
  }

  int addRationals(List<List<int>> rs) {
    final at = dataOffset(fixedEnd);
    for (final r in rs) {
      final tmp = BytesBuilder();
      for (final v in r) {
        tmp.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
      }
      data.add(tmp.toBytes());
    }
    return at;
  }

  final makeAt = addAscii(make);
  final modelAt = addAscii(model);
  final origAt = original == null ? 0 : addAscii(original);

  List<List<int>> dms(double v) {
    final a = v.abs();
    final d = a.floor();
    final m = ((a - d) * 60).floor();
    final s = (((a - d) * 60 - m) * 60 * 1000).round();
    return [
      [d, 1],
      [m, 1],
      [s, 1000],
    ];
  }

  int? latAt, lonAt;
  if (gps != null) {
    latAt = addRationals(dms(gps.lat));
    lonAt = addRationals(dms(gps.lon));
  }

  b.add([0x49, 0x49, 0x2A, 0x00]);
  u32(ifd0At);

  void entry(int tag, int type, int count, int value) {
    u16(tag);
    u16(type);
    u32(count);
    u32(value);
  }

  u16(ifd0Count);
  entry(0x010F, 2, make.length + 1, makeAt);
  entry(0x0110, 2, model.length + 1, modelAt);
  entry(0x0112, 3, 1, orientation);
  entry(0x8769, 4, 1, exifAt);
  if (gps != null) entry(0x8825, 4, 1, gpsAt);
  u32(0);

  u16(1);
  entry(0x9003, 2, original == null ? 0 : original.length + 1, origAt);
  u32(0);

  if (gps != null) {
    u16(4);
    entry(0x0001, 2, 2, gps.lat < 0 ? 0x53 : 0x4E); // 'S' / 'N'
    entry(0x0002, 5, 3, latAt!);
    entry(0x0003, 2, 2, gps.lon < 0 ? 0x57 : 0x45); // 'W' / 'E'
    entry(0x0004, 5, 3, lonAt!);
    u32(0);
  }
  b.add(data.toBytes());
  return b.toBytes();
}

Uint8List _segment(int marker, List<int> payload) {
  final len = payload.length + 2;
  return Uint8List.fromList([0xFF, marker, len >> 8, len & 0xFF, ...payload]);
}

Uint8List _jpeg({
  Uint8List? tiff,
  String? xmp,
  int width = 4000,
  int height = 3000,
}) {
  final out = BytesBuilder()..add([0xFF, 0xD8]);
  if (tiff != null) {
    out.add(_segment(0xE1, [...ascii.encode('Exif'), 0, 0, ...tiff]));
  }
  if (xmp != null) {
    out.add(_segment(0xE1, [...ascii.encode('http://ns.adobe.com/xap/1.0/'), 0, ...utf8.encode(xmp)]));
  }
  // SOF0: precision, height, width, 3 components (+ padding to a plausible length)
  out.add(_segment(0xC0, [8, height >> 8, height & 0xFF, width >> 8, width & 0xFF, 3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1]));
  out.add([0xFF, 0xDA, 0x00, 0x02, 0x00, 0x00]);
  return out.toBytes();
}

void main() {
  group('GalleryMetaParser JPEG', () {
    test('reads camera, date taken, GPS and size', () {
      final meta = GalleryMetaParser.parse(
        _jpeg(tiff: _tiff(gps: (lat: 48.8566, lon: 2.3522))),
      );
      expect(meta.make, 'Canon');
      expect(meta.model, 'Canon EOS R5');
      expect(meta.camera, 'Canon EOS R5');
      expect(meta.takenWallClock, DateTime.utc(2023, 7, 14, 18, 32, 5));
      expect(meta.latitude, closeTo(48.8566, 0.001));
      expect(meta.longitude, closeTo(2.3522, 0.001));
      expect(meta.width, 4000);
      expect(meta.height, 3000);
      expect(meta.placeCell, '489,24');
    });

    test('southern and western hemispheres are negative', () {
      final meta = GalleryMetaParser.parse(
        _jpeg(tiff: _tiff(gps: (lat: -33.8688, lon: -70.0))),
      );
      expect(meta.latitude, closeTo(-33.8688, 0.001));
      expect(meta.longitude, closeTo(-70.0, 0.001));
    });

    test('EXIF orientation 6 swaps the size', () {
      final meta = GalleryMetaParser.parse(_jpeg(tiff: _tiff(orientation: 6)));
      expect(meta.width, 3000);
      expect(meta.height, 4000);
    });

    test('a photo with no EXIF still has its size', () {
      final meta = GalleryMetaParser.parse(_jpeg());
      expect(meta.width, 4000);
      expect(meta.takenSecs, isNull);
      expect(meta.hasLocation, isFalse);
    });

    test('placeholder date 0000:00:00 is ignored', () {
      final meta = GalleryMetaParser.parse(
        _jpeg(tiff: _tiff(original: '0000:00:00 00:00:00')),
      );
      expect(meta.takenSecs, isNull);
    });

    test('reads XMP keywords and rating, decoding entities', () {
      const xmp = '<x:xmpmeta><rdf:RDF><rdf:Description xmp:Rating="4">'
          '<dc:subject><rdf:Bag><rdf:li>Holiday</rdf:li>'
          '<rdf:li>Cats &amp; Dogs</rdf:li><rdf:li>holiday</rdf:li></rdf:Bag></dc:subject>'
          '</rdf:Description></rdf:RDF></x:xmpmeta>';
      final meta = GalleryMetaParser.parse(_jpeg(xmp: xmp));
      expect(meta.tags, ['Holiday', 'Cats & Dogs']);
      expect(meta.rating, 4);
    });

    test('garbage and truncated input never throw', () {
      expect(GalleryMetaParser.parse(Uint8List(0)).isEmpty, isTrue);
      expect(GalleryMetaParser.parse(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0xFF])).isEmpty, isTrue);
      final full = _jpeg(tiff: _tiff(gps: (lat: 1, lon: 1)));
      for (var n = 0; n < full.length; n += 7) {
        GalleryMetaParser.parse(Uint8List.sublistView(full, 0, n));
      }
    });
  });

  group('GalleryMetaParser PNG and WebP', () {
    test('PNG size from IHDR', () {
      final png = BytesBuilder()
        ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add([0, 0, 0, 13])
        ..add(ascii.encode('IHDR'))
        ..add([0, 0, 3, 0x20, 0, 0, 2, 0x58, 8, 6, 0, 0, 0])
        ..add([0, 0, 0, 0]);
      final meta = GalleryMetaParser.parse(png.toBytes());
      expect(meta.width, 800);
      expect(meta.height, 600);
    });

    test('lossy WebP size from VP8', () {
      final chunk = <int>[0, 0, 0, 0x9D, 0x01, 0x2A, 0x20, 0x03, 0x58, 0x02];
      final riff = BytesBuilder()
        ..add(ascii.encode('RIFF'))
        ..add([0, 0, 0, 0])
        ..add(ascii.encode('WEBP'))
        ..add(ascii.encode('VP8 '))
        ..add([chunk.length, 0, 0, 0])
        ..add(chunk);
      final meta = GalleryMetaParser.parse(riff.toBytes());
      expect(meta.width, 800);
      expect(meta.height, 600);
    });
  });

  group('GalleryMeta', () {
    test('JSON round trip', () {
      const meta = GalleryMeta(
        takenSecs: 1700000000,
        latitude: 48.85,
        longitude: 2.35,
        make: 'Canon',
        model: 'EOS',
        tags: ['a', 'b'],
        rating: 3,
        width: 10,
        height: 20,
      );
      expect(GalleryMeta.tryFromJson(jsonDecode(jsonEncode(meta.toJson()))), meta);
      expect(GalleryMeta.tryFromJson([1, 2]), isNull);
    });

    test('camera does not repeat the make', () {
      expect(const GalleryMeta(make: 'Canon', model: 'Canon EOS').camera, 'Canon EOS');
      expect(const GalleryMeta(make: 'Google', model: 'Pixel 9').camera, 'Google Pixel 9');
      expect(GalleryMeta.empty.camera, isNull);
    });

    test('place label', () {
      expect(GalleryMeta.placeLabel('489,24'), '48.9°N 2.4°E');
      expect(GalleryMeta.placeLabel('-339,-700'), '33.9°S 70.0°W');
    });
  });
}
