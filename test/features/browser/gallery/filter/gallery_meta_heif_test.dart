import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_index.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_parser.dart';
import 'package:vaultexplorer/features/browser/metadata/metadata_source.dart';
import 'package:vaultexplorer/features/browser/metadata/tiff_exif_editor.dart';

import '../../../../helpers/heic_fixture.dart';

Uint8List _tiff(String date) =>
    TiffExifEditor.createMinimal(orientation: 1, exifDate: date);

final _expected = DateTime.utc(2023, 5, 6, 7, 8, 9).millisecondsSinceEpoch ~/ 1000;

void main() {
  group('GalleryMetaParser HEIC', () {
    test('HEIC is a parsed extension', () {
      for (final e in ['heic', 'heif', 'hif']) {
        expect(GalleryMetaParser.canParse(e), isTrue);
      }
    });

    test('reads the date taken when the whole file is given', () {
      final f = HeicFixture.build(tiff: _tiff('2023:05:06 07:08:09'));
      expect(GalleryMetaParser.parse(f.bytes).takenSecs, _expected);
    });

    test('a header that stops before the Exif block gives nothing, no throw', () {
      final f = HeicFixture.build(
        tiff: _tiff('2023:05:06 07:08:09'),
        pixels: 300000,
      );
      final head = Uint8List.sublistView(f.bytes, 0, GalleryMetaParser.headerBytes);
      expect(GalleryMetaParser.parse(head).takenSecs, isNull);
    });

    test('parseSource fetches the Exif block beyond the header', () async {
      final f = HeicFixture.build(
        tiff: _tiff('2023:05:06 07:08:09'),
        pixels: 300000,
      );
      final meta = await GalleryMetaParser.parseSource(
        MemoryMetadataSource(f.bytes),
      );
      expect(meta.takenSecs, _expected);
    });

    test('parseSource does not read the picture data', () async {
      final f = HeicFixture.build(
        tiff: _tiff('2023:05:06 07:08:09'),
        pixels: 300000,
      );
      final src = _CountingSource(f.bytes);
      await GalleryMetaParser.parseSource(src);
      expect(src.bytesRead, lessThan(GalleryMetaParser.headerBytes + 4096));
    });

    test('a file with no Exif item is empty, not an error', () async {
      final f = HeicFixture.build();
      final meta = await GalleryMetaParser.parseSource(
        MemoryMetadataSource(f.bytes),
      );
      expect(meta.takenSecs, isNull);
    });

    test('garbage that looks like HEIC never throws', () async {
      final junk = Uint8List.fromList([
        0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70, ...List.filled(40, 0xFF),
      ]);
      expect(GalleryMetaParser.parse(junk).takenSecs, isNull);
      final meta = await GalleryMetaParser.parseSource(MemoryMetadataSource(junk));
      expect(meta.takenSecs, isNull);
    });

    test('a failing source is passed on, not remembered as empty', () async {
      final f = HeicFixture.build(
        tiff: _tiff('2023:05:06 07:08:09'),
        pixels: 300000,
      );
      final head = Uint8List.sublistView(f.bytes, 0, GalleryMetaParser.headerBytes);
      await expectLater(
        GalleryMetaParser.parseSource(
          _FailingSource(f.bytes.length),
          header: head,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('GalleryMetaIndex HEIC', () {
    test('reads the date taken from an Exif block past the header', () async {
      final f = HeicFixture.build(
        tiff: _tiff('2023:05:06 07:08:09'),
        pixels: 300000,
      );
      final index = GalleryMetaIndex(
        readHeader: (vol, path, length) async =>
            Uint8List.sublistView(f.bytes, 0, length),
        readRange: (vol, path, offset, length) async =>
            Uint8List.sublistView(f.bytes, offset, offset + length),
      );
      final req = GalleryIndexRequest(1, 'a.heic', f.bytes.length, 1000);
      await index.ensure([req]);
      for (var i = 0; i < 400 && index.isIndexing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(index.lookup(1, 'a.heic', f.bytes.length, 1000)?.takenSecs, _expected);
      index.dispose();
    });

    test('a range that cannot be read leaves the photo unknown', () async {
      final f = HeicFixture.build(
        tiff: _tiff('2023:05:06 07:08:09'),
        pixels: 300000,
      );
      final index = GalleryMetaIndex(
        readHeader: (vol, path, length) async =>
            Uint8List.sublistView(f.bytes, 0, length),
        readRange: (vol, path, offset, length) async => null,
      );
      await index.ensure([GalleryIndexRequest(1, 'a.heic', f.bytes.length, 1000)]);
      for (var i = 0; i < 400 && index.isIndexing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(index.lookup(1, 'a.heic', f.bytes.length, 1000), isNull);
      index.dispose();
    });
  });
}

class _CountingSource implements MetadataSource {
  _CountingSource(this._b);
  final Uint8List _b;
  int bytesRead = 0;
  @override
  int get length => _b.length;
  @override
  Future<Uint8List> read(int offset, int count) async {
    final end = (offset + count).clamp(0, _b.length);
    bytesRead += end - offset;
    return Uint8List.sublistView(_b, offset, end);
  }
}

class _FailingSource implements MetadataSource {
  _FailingSource(this.length);
  @override
  final int length;
  @override
  Future<Uint8List> read(int offset, int count) async =>
      throw StateError('disk gone');
}
