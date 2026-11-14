import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/metadata/image_metadata_editor.dart';
import 'package:vaultexplorer/features/browser/metadata/image_metadata_reader.dart';
import 'package:vaultexplorer/features/browser/metadata/metadata_source.dart';
import 'package:vaultexplorer/features/browser/metadata/tiff_exif_editor.dart';

/// Pixel data stand-in: it must come out of every edit byte for byte.
final Uint8List _scan = Uint8List.fromList(List.generate(300, (i) => (i * 7) & 0xFF));

Uint8List _seg(int marker, List<int> payload) {
  final len = payload.length + 2;
  return Uint8List.fromList([0xFF, marker, len >> 8, len & 0xFF, ...payload]);
}

/// A JPEG made of [segments] (before the image data) and the stand-in scan.
Uint8List _jpeg([List<Uint8List> segments = const []]) {
  final b = BytesBuilder()
    ..add([0xFF, 0xD8])
    ..add(_seg(0xE0, [...ascii.encode('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]));
  segments.forEach(b.add);
  b
    ..add([0xFF, 0xDA, 0x00, 0x02])
    ..add(_scan)
    ..add([0xFF, 0xD9]);
  return b.takeBytes();
}

Future<Uint8List> _apply(Uint8List file, MetadataEdit edit) async {
  final src = MemoryMetadataSource(file);
  final plan = await ImageMetadataEditor.plan(src, edit);
  expect(plan, isNotNull);
  final out = await plan!.toBytes(src);
  expect(out.length, plan.outputLength);
  return out;
}

Future<Map<String, String>> _tags(Uint8List file) async {
  final dirs = await ImageMetadataReader.read(MemoryMetadataSource(file));
  return {
    for (final d in dirs)
      for (final t in d.tags) '${d.name}/${t.name}': t.value,
  };
}

bool _endsWithScan(Uint8List out) {
  final tail = out.sublist(out.length - _scan.length - 2, out.length - 2);
  return _listEq(tail, _scan);
}

bool _listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _exifSeg(Uint8List tiff) => _seg(0xE1, [0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff]);

void main() {
  group('JPEG', () {
    test('a date is written into a file with no Exif', () async {
      final out = await _apply(
        _jpeg(),
        MetadataEdit(takenWallClock: DateTime.utc(2021, 3, 4, 5, 6, 7)),
      );
      final tags = await _tags(out);
      expect(tags['Exif/Date/Time Original'], '2021:03:04 05:06:07');
      expect(tags['Exif IFD0/Date/Time'], '2021:03:04 05:06:07');
      expect(_endsWithScan(out), isTrue);
    });

    test('keywords are written, replaced and removed', () async {
      var out = await _apply(_jpeg(), const MetadataEdit(keywords: ['sunset', 'Lake Como', 'a&b']));
      expect((await _tags(out))['XMP/dc:subject'], 'sunset, Lake Como, a&b');

      out = await _apply(out, const MetadataEdit(keywords: ['only']));
      expect((await _tags(out))['XMP/dc:subject'], 'only');

      out = await _apply(out, const MetadataEdit(keywords: []));
      expect((await _tags(out)).containsKey('XMP/dc:subject'), isFalse);
      expect(_endsWithScan(out), isTrue);
    });

    test('editing a date keeps the orientation and other tags', () async {
      final tiff = TiffExifEditor.createMinimal(orientation: 6, exifDate: '2020:01:02 03:04:05');
      final out = await _apply(
        _jpeg([_exifSeg(tiff)]),
        MetadataEdit(takenWallClock: DateTime.utc(2023, 7, 14, 18, 32, 5)),
      );
      final tags = await _tags(out);
      expect(tags['Exif/Date/Time Original'], '2023:07:14 18:32:05');
      expect(tags['Exif IFD0/Orientation'], contains('90'));
    });

    test('adding a date to Exif that has none never moves existing data', () async {
      // An IFD0 holding a Make whose text lives after the table.
      const make = 'SomeCamera';
      final t = BytesBuilder()
        ..add([0x49, 0x49, 42, 0, 8, 0, 0, 0])
        ..add([1, 0, 0x0F, 0x01, 2, 0, make.length + 1, 0, 0, 0, 0x1A, 0, 0, 0])
        ..add([0, 0, 0, 0])
        ..add(ascii.encode(make))
        ..addByte(0);
      final original = t.takeBytes();
      final out = await _apply(
        _jpeg([_exifSeg(original)]),
        MetadataEdit(takenWallClock: DateTime.utc(2000, 1, 2, 3, 4, 5)),
      );
      final tags = await _tags(out);
      expect(tags['Exif IFD0/Make'], make);
      expect(tags['Exif/Date/Time Original'], '2000:01:02 03:04:05');
      // The text is still where it was, relative to the block.
      final start = _indexOf(out, [0x45, 0x78, 0x69, 0x66, 0, 0]) + 6;
      final at = _indexOf(out, ascii.encode(make));
      expect(at - start, 0x1A);
    });

    test('stripping Exif keeps only the orientation', () async {
      final tiff = TiffExifEditor.createMinimal(orientation: 8, exifDate: '2020:01:02 03:04:05');
      final out = await _apply(
        _jpeg([_exifSeg(tiff)]),
        const MetadataEdit(strip: {MetadataKind.exif}),
      );
      final tags = await _tags(out);
      expect(tags.keys.where((k) => k.startsWith('Exif')).toList(), ['Exif IFD0/Orientation']);

      final bare = await _apply(
        _jpeg([_exifSeg(tiff)]),
        const MetadataEdit(strip: {MetadataKind.exif}, keepOrientation: false),
      );
      expect((await _tags(bare)).keys.any((k) => k.startsWith('Exif')), isFalse);
      expect(_endsWithScan(bare), isTrue);
    });

    test('nothing to do gives no plan', () async {
      final src = MemoryMetadataSource(_jpeg());
      expect(
        await ImageMetadataEditor.plan(src, const MetadataEdit(strip: {MetadataKind.xmp, MetadataKind.exif})),
        isNull,
      );
    });

    test('the multi-picture index follows the header', () async {
      // MPF: primary image at offset 0, a second image appended after it.
      Uint8List mpf(int primary, int offset, int size) {
        final b = BytesBuilder()
          ..add(ascii.encode('MPF'))
          ..addByte(0)
          ..add([0x4D, 0x4D, 0, 42, 0, 0, 0, 8])
          ..add([0, 1])
          ..add([0xB0, 0x02, 0, 7, 0, 0, 0, 32, 0, 0, 0, 0x1A])
          ..add([0, 0, 0, 0]);
        void be32(int v) => b.add([v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF]);
        be32(0x20030000);
        be32(primary);
        be32(0);
        b.add([0, 0, 0, 0]);
        be32(0);
        be32(size);
        be32(offset);
        b.add([0, 0, 0, 0]);
        return _seg(0xE2, b.takeBytes());
      }

      final second = _jpeg();
      // Primary size = everything before the second image.
      final probe = _jpeg([mpf(0, 0, 0)]);
      final primary = probe.length;
      final tiffStart = 2 + 18 + 4 + 4; // SOI, JFIF segment, MPF marker + id
      final file = BytesBuilder()
        ..add(_jpeg([mpf(primary, primary - tiffStart, second.length)]))
        ..add(second);
      final out = await _apply(
        file.takeBytes(),
        MetadataEdit(takenWallClock: DateTime.utc(2024, 5, 6, 7, 8, 9), keywords: const ['one', 'two']),
      );
      final i = _indexOf(out, ascii.encode('MPF'));
      final t = i + 4;
      int be32At(int o) => (out[o] << 24) | (out[o + 1] << 16) | (out[o + 2] << 8) | out[o + 3];
      final ifd = t + be32At(t + 4);
      final entries = t + be32At(ifd + 2 + 8);
      final size0 = be32At(entries + 4);
      final offset1 = be32At(entries + 16 + 8);
      expect(size0 > primary, isTrue);
      expect(out[t + offset1], 0xFF);
      expect(out[t + offset1 + 1], 0xD8);
      expect(t + offset1, size0);
    });
  });

  group('PNG', () {
    Uint8List chunk(String type, List<int> data) {
      final c = ascii.encode(type);
      final crc = _crc([...c, ...data]);
      return Uint8List.fromList([
        data.length >> 24 & 0xFF, data.length >> 16 & 0xFF, data.length >> 8 & 0xFF, data.length & 0xFF,
        ...c, ...data, crc >> 24 & 0xFF, crc >> 16 & 0xFF, crc >> 8 & 0xFF, crc & 0xFF,
      ]);
    }

    Uint8List png({List<Uint8List> extra = const []}) {
      final b = BytesBuilder()
        ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(chunk('IHDR', [0, 0, 0, 2, 0, 0, 0, 2, 8, 2, 0, 0, 0]));
      extra.forEach(b.add);
      b
        ..add(chunk('IDAT', _scan))
        ..add(chunk('IEND', const []));
      return b.takeBytes();
    }

    test('a date and keywords are added with valid checksums', () async {
      final out = await _apply(
        png(),
        MetadataEdit(takenWallClock: DateTime.utc(2021, 3, 4, 5, 6, 7), keywords: const ['png tag', 'é ü']),
      );
      final tags = await _tags(out);
      expect(tags['Exif/Date/Time Original'], '2021:03:04 05:06:07');
      expect(tags['XMP/dc:subject'], 'png tag, é ü');
      // Every chunk's CRC must match.
      var o = 8;
      while (o < out.length) {
        final len = (out[o] << 24) | (out[o + 1] << 16) | (out[o + 2] << 8) | out[o + 3];
        final crc = _crc(out.sublist(o + 4, o + 8 + len));
        final stored = (out[o + 8 + len] << 24) | (out[o + 9 + len] << 16) | (out[o + 10 + len] << 8) | out[o + 11 + len];
        expect(crc, stored);
        o += 12 + len;
      }
    });

    test('text chunks are removed as comments', () async {
      final text = chunk('tEXt', [...ascii.encode('Comment'), 0, ...ascii.encode('hello')]);
      final out = await _apply(png(extra: [text]), const MetadataEdit(strip: {MetadataKind.comment}));
      expect((await _tags(out)).keys.any((k) => k.startsWith('PNG Text')), isFalse);
    });
  });

  group('WebP', () {
    Uint8List webp() {
      // A lossless image header (width 4, height 3, no alpha) and some data.
      final vp8l = [0x2F, 3, 0, 0x80 | 0, 0, ..._scan];
      final body = BytesBuilder()
        ..add(ascii.encode('WEBP'))
        ..add(ascii.encode('VP8L'))
        ..add([vp8l.length & 0xFF, vp8l.length >> 8, 0, 0])
        ..add(vp8l);
      final bytes = body.takeBytes();
      return Uint8List.fromList([
        ...ascii.encode('RIFF'),
        bytes.length & 0xFF, bytes.length >> 8 & 0xFF, 0, 0,
        ...bytes,
      ]);
    }

    test('a simple file becomes extended when metadata is added', () async {
      final out = await _apply(webp(), const MetadataEdit(keywords: ['wk']));
      expect(String.fromCharCodes(out, 12, 16), 'VP8X');
      expect(out[20] & 0x04, 0x04); // XMP flag
      final riff = out[4] | (out[5] << 8) | (out[6] << 16) | (out[7] << 24);
      expect(riff, out.length - 8);
      expect((await _tags(out))['XMP/dc:subject'], 'wk');
    });
  });

  test('unsupported files are refused', () async {
    Object? error;
    try {
      await ImageMetadataEditor.plan(
        MemoryMetadataSource(Uint8List.fromList(ascii.encode('GIF89a-not-supported'))),
        const MetadataEdit(strip: {MetadataKind.exif}),
      );
    } on MetadataEditException catch (e) {
      error = e;
    }
    expect(error, isA<MetadataEditException>());
  });
}

int _indexOf(Uint8List b, List<int> needle) {
  for (var i = 0; i + needle.length <= b.length; i++) {
    var ok = true;
    for (var k = 0; k < needle.length; k++) {
      if (b[i + k] != needle[k]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}

int _crc(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
