import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/metadata/heif_container.dart';
import 'package:vaultexplorer/features/browser/metadata/image_metadata_editor.dart';
import 'package:vaultexplorer/features/browser/metadata/image_metadata_reader.dart';
import 'package:vaultexplorer/features/browser/metadata/metadata_source.dart';
import 'package:vaultexplorer/features/browser/metadata/tiff_exif_editor.dart';

import '../../../helpers/heic_fixture.dart';

final _taken = DateTime.utc(2024, 9, 19, 16, 40, 5);

Uint8List _tiffWithDates(String date) => TiffExifEditor.createMinimal(
  orientation: 6,
  exifDate: date,
);

/// An Exif block with an orientation and no dates at all.
Uint8List _tiffWithoutDates() => TiffExifEditor.createMinimal(orientation: 6);

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

List<int> _differingOffsets(Uint8List a, Uint8List b) => [
  for (var i = 0; i < a.length && i < b.length; i++)
    if (a[i] != b[i]) i,
];

/// The top-level boxes of [file], as `type:size`.
List<String> _topLevel(Uint8List file) {
  final out = <String>[];
  var o = 0;
  while (o + 8 <= file.length) {
    final size = ByteData.sublistView(file).getUint32(o);
    out.add('${String.fromCharCodes(file, o + 4, o + 8)}:$size');
    o += size;
  }
  expect(o, file.length, reason: 'boxes must tile the file exactly');
  return out;
}

void main() {
  group('HEIC date', () {
    test('the date taken is written over the Exif date, in place', () async {
      final f = HeicFixture.build(tiff: _tiffWithDates('2020:01:02 03:04:05'));
      final out = await _apply(f.bytes, MetadataEdit(takenWallClock: _taken));

      // Nothing moved: same size, and only Exif bytes (the three dates)
      // differ.
      expect(out.length, f.bytes.length);
      final changed = _differingOffsets(f.bytes, out);
      expect(changed, isNotEmpty);
      expect(changed.first, greaterThanOrEqualTo(f.exifAt));
      expect(changed.last, lessThan(f.exifAt + f.exifLength));

      final tags = await _tags(out);
      expect(tags['Exif/Date/Time Original'], '2024:09:19 16:40:05');
      expect(tags['Exif/Date/Time Digitized'], '2024:09:19 16:40:05');
      expect(tags['Exif IFD0/Date/Time'], '2024:09:19 16:40:05');
      // The orientation next to it survived.
      expect(tags['Exif IFD0/Orientation'], isNotNull);
    });

    test('the picture data and the box structure are untouched', () async {
      final f = HeicFixture.build(
        tiff: _tiffWithDates('2020:01:02 03:04:05'),
        pixels: 50000,
      );
      final out = await _apply(f.bytes, MetadataEdit(takenWallClock: _taken));
      expect(
        out.sublist(f.pixelsAt, f.pixelsAt + 50000),
        HeicFixture.pixelData(50000),
      );
      expect(_topLevel(out), _topLevel(f.bytes));
    });

    test('Exif far past the start of the file is found through iloc', () async {
      final f = HeicFixture.build(
        tiff: _tiffWithDates('2020:01:02 03:04:05'),
        pixels: 600000,
      );
      expect(f.exifAt, greaterThan(500000));
      final out = await _apply(f.bytes, MetadataEdit(takenWallClock: _taken));
      expect((await _tags(out))['Exif/Date/Time Original'], '2024:09:19 16:40:05');
    });

    test('iloc version 1 files are edited too', () async {
      final f = HeicFixture.build(
        tiff: _tiffWithDates('2020:01:02 03:04:05'),
        ilocVersion: 1,
      );
      final out = await _apply(f.bytes, MetadataEdit(takenWallClock: _taken));
      expect((await _tags(out))['Exif/Date/Time Original'], '2024:09:19 16:40:05');
    });

    test('an Exif block without dates grows into a new mdat, nothing moves',
        () async {
      final f = HeicFixture.build(tiff: _tiffWithoutDates(), pixels: 3000);
      final out = await _apply(f.bytes, MetadataEdit(takenWallClock: _taken));

      // The original file is a prefix of the result, except for the two iloc
      // fields that now point at the new data.
      expect(out.length, greaterThan(f.bytes.length));
      final changed = _differingOffsets(f.bytes, out);
      expect(changed.length, lessThanOrEqualTo(8));
      final layoutBefore = await HeifLayout.locate(MemoryMetadataSource(f.bytes));
      final extent = layoutBefore!.exif!.location!.extents.single;
      for (final i in changed) {
        final inOffset = i >= extent.offsetFieldAt && i < extent.offsetFieldAt + 4;
        final inLength = i >= extent.lengthFieldAt && i < extent.lengthFieldAt + 4;
        expect(inOffset || inLength, isTrue, reason: 'byte $i changed');
      }
      // A second mdat holds the new block; the old picture is where it was.
      expect(_topLevel(out), [..._topLevel(f.bytes), 'mdat:${out.length - f.bytes.length}']);
      expect(
        out.sublist(f.pixelsAt, f.pixelsAt + 3000),
        HeicFixture.pixelData(3000),
      );

      final tags = await _tags(out);
      expect(tags['Exif/Date/Time Original'], '2024:09:19 16:40:05');
      expect(tags['Exif IFD0/Orientation'], isNotNull);

      // Editing it again now fits in place.
      final again = await _apply(
        out,
        MetadataEdit(takenWallClock: DateTime.utc(2001, 2, 3, 4, 5, 6)),
      );
      expect(again.length, out.length);
      expect((await _tags(again))['Exif/Date/Time Original'], '2001:02:03 04:05:06');
    });

    test('XMP dates are kept in step, padded when shorter', () async {
      const xmp =
          '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
          'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
          '<rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" '
          'xmp:CreateDate="2020-01-02T03:04"/></rdf:RDF></x:xmpmeta>';
      final f = HeicFixture.build(
        tiff: _tiffWithDates('2020:01:02 03:04:05'),
        xmp: xmp,
      );
      final out = await _apply(f.bytes, MetadataEdit(takenWallClock: _taken));
      // The new XMP date is longer than the old one ("...T03:04"), so the
      // packet moved to a new mdat.
      expect(_topLevel(out).where((b) => b.startsWith('mdat:')).length, 2);
      final layout = await HeifLayout.locate(MemoryMetadataSource(out));
      final data = await layout!.readItem(MemoryMetadataSource(out), layout.xmp!);
      expect(utf8.decode(data!), contains('xmp:CreateDate="2024-09-19T16:40:05"'));
      // And the Exif date is right as well.
      expect((await _tags(out))['Exif/Date/Time Original'], '2024:09:19 16:40:05');
    });

    test('XMP with a date of the same length is rewritten in place', () async {
      const xmp =
          '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
          'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
          '<rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" '
          'xmp:CreateDate="2020-01-02T03:04:05"/></rdf:RDF></x:xmpmeta>';
      final f = HeicFixture.build(
        tiff: _tiffWithDates('2020:01:02 03:04:05'),
        xmp: xmp,
      );
      final out = await _apply(f.bytes, MetadataEdit(takenWallClock: _taken));
      expect(out.length, f.bytes.length);
      expect(
        utf8.decode(out.sublist(out.length - xmp.length)),
        contains('xmp:CreateDate="2024-09-19T16:40:05"'),
      );
    });

    test('a file already carrying that date needs no change', () async {
      final f = HeicFixture.build(tiff: _tiffWithDates('2024:09:19 16:40:05'));
      final plan = await ImageMetadataEditor.plan(
        MemoryMetadataSource(f.bytes),
        MetadataEdit(takenWallClock: _taken),
      );
      expect(plan, isNull);
    });

    test('a HEIC without an Exif item is refused as unsupported', () async {
      final f = HeicFixture.build();
      await expectLater(
        ImageMetadataEditor.plan(
          MemoryMetadataSource(f.bytes),
          MetadataEdit(takenWallClock: _taken),
        ),
        throwsA(
          isA<MetadataEditException>().having(
            (e) => e.reason,
            'reason',
            MetadataEditFailure.unsupportedFormat,
          ),
        ),
      );
    });

    test('tags and removal are not offered for HEIC', () async {
      final f = HeicFixture.build(tiff: _tiffWithDates('2020:01:02 03:04:05'));
      for (final edit in [
        const MetadataEdit(keywords: ['a']),
        const MetadataEdit(strip: {MetadataKind.exif}),
        MetadataEdit(takenWallClock: _taken, keywords: const ['a']),
      ]) {
        await expectLater(
          ImageMetadataEditor.plan(MemoryMetadataSource(f.bytes), edit),
          throwsA(
            isA<MetadataEditException>().having(
              (e) => e.reason,
              'reason',
              MetadataEditFailure.unsupportedFormat,
            ),
          ),
        );
      }
    });

    test('damaged files are refused, not mangled', () async {
      final f = HeicFixture.build(tiff: _tiffWithDates('2020:01:02 03:04:05'));
      // Cut in the middle of the meta box.
      final cut = Uint8List.sublistView(f.bytes, 0, 60);
      await expectLater(
        ImageMetadataEditor.plan(
          MemoryMetadataSource(cut),
          MetadataEdit(takenWallClock: _taken),
        ),
        throwsA(isA<MetadataEditException>()),
      );
      // Exif item cut off by the end of the file.
      final trunc = Uint8List.sublistView(f.bytes, 0, f.exifAt + 4);
      await expectLater(
        ImageMetadataEditor.plan(
          MemoryMetadataSource(trunc),
          MetadataEdit(takenWallClock: _taken),
        ),
        throwsA(isA<MetadataEditException>()),
      );
    });
  });

  group('which files can be edited', () {
    test('HEIC takes a new date but not tags or removal', () {
      expect(ImageMetadataEditor.canEdit('a.heic'), isFalse);
      expect(ImageMetadataEditor.canEditDate('a.HEIC'), isTrue);
      expect(ImageMetadataEditor.canEditDate('a.heif'), isTrue);
      expect(ImageMetadataEditor.canEditDate('a.jpg'), isTrue);
      expect(ImageMetadataEditor.canEditDate('a.mp4'), isFalse);
      expect(ImageMetadataEditor.canEditDate('noextension'), isFalse);

      final date = MetadataEdit(takenWallClock: _taken);
      expect(ImageMetadataEditor.canApply('a.heic', date), isTrue);
      expect(
        ImageMetadataEditor.canApply('a.heic', const MetadataEdit(keywords: ['x'])),
        isFalse,
      );
      expect(
        ImageMetadataEditor.canApply('a.jpg', const MetadataEdit(keywords: ['x'])),
        isTrue,
      );
      expect(ImageMetadataEditor.canApply('a.mp4', date), isFalse);
    });
  });
}
