import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/services/thumbnail_stamp_registry.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';

void main() {
  const uri = 'content://vault';

  setUp(ThumbnailStampRegistry.clearForTesting);

  test('an unlisted file has no stamp', () {
    expect(ThumbnailStampRegistry.segmentFor(uri, 'a.jpg'), isNull);
  });

  test('a wire listing records plain files only', () {
    final changed = ThumbnailStampRegistry.recordWire(uri, 'pics', const [
      'F|100|1000|a.jpg',
      'D|0|1000|sub',
      'L|5|1000|link.jpg',
      'LD|0|1000|linkdir',
      'System:TRUNCATED',
      'F|7|0|no clock.jpg',
    ]);
    expect(changed, isEmpty, reason: 'first sighting is not a change');
    expect(ThumbnailStampRegistry.segmentFor(uri, 'pics/a.jpg'), '@100.1000');
    expect(ThumbnailStampRegistry.segmentFor(uri, 'pics/no clock.jpg'), '@7.0');
    expect(ThumbnailStampRegistry.segmentFor(uri, 'pics/sub'), isNull);
    expect(ThumbnailStampRegistry.segmentFor(uri, 'pics/link.jpg'), isNull);
  });

  test('a name containing | keeps everything after the third separator', () {
    ThumbnailStampRegistry.recordWire(uri, '', const ['F|9|5|a|b.jpg']);
    expect(ThumbnailStampRegistry.segmentFor(uri, 'a|b.jpg'), '@9.5');
  });

  test('the root folder and a leading slash resolve to the same path', () {
    ThumbnailStampRegistry.recordWire(uri, '', const ['F|1|2|a.jpg']);
    expect(ThumbnailStampRegistry.segmentFor(uri, '/a.jpg'), '@1.2');
    ThumbnailStampRegistry.recordWire(uri, '/pics/', const ['F|3|4|b.jpg']);
    expect(ThumbnailStampRegistry.segmentFor(uri, 'pics/b.jpg'), '@3.4');
  });

  test('a changed size or modified time is reported, an identical one is not', () {
    ThumbnailStampRegistry.recordWire(uri, '', const ['F|1|2|a.jpg']);
    expect(
      ThumbnailStampRegistry.recordWire(uri, '', const ['F|1|2|a.jpg']),
      isEmpty,
    );
    expect(
      ThumbnailStampRegistry.recordWire(uri, '', const ['F|1|3|a.jpg']),
      ['a.jpg'],
    );
    expect(
      ThumbnailStampRegistry.recordWire(uri, '', const ['F|9|3|a.jpg']),
      ['a.jpg'],
    );
  });

  test('stamps are kept per container', () {
    ThumbnailStampRegistry.record('content://one', 'a.jpg', 1, 1);
    expect(ThumbnailStampRegistry.segmentFor('content://two', 'a.jpg'), isNull);
    ThumbnailStampRegistry.forgetContainer('content://one');
    expect(ThumbnailStampRegistry.segmentFor('content://one', 'a.jpg'), isNull);
  });

  test('parsed entries record files, skipping folders, links and placeholders', () {
    final changed = ThumbnailStampRegistry.recordEntries(uri, 'd', const [
      RawEntry(name: 'a.jpg', isDir: false, sizeBytes: 4, modifiedSecs: 8),
      RawEntry(name: 'sub', isDir: true, sizeBytes: 0, modifiedSecs: 8),
      RawEntry(
        name: 'l.jpg',
        isDir: false,
        isSymlink: true,
        sizeBytes: 4,
        modifiedSecs: 8,
      ),
      RawEntry(
        name: 'p.jpg',
        isDir: false,
        isPlaceholder: true,
        sizeBytes: 4,
        modifiedSecs: 8,
      ),
    ]);
    expect(changed, isEmpty);
    expect(ThumbnailStampRegistry.segmentFor(uri, 'd/a.jpg'), '@4.8');
    expect(ThumbnailStampRegistry.segmentFor(uri, 'd/sub'), isNull);
    expect(ThumbnailStampRegistry.segmentFor(uri, 'd/l.jpg'), isNull);
    expect(ThumbnailStampRegistry.segmentFor(uri, 'd/p.jpg'), isNull);
  });

  test('the registry is bounded and drops the oldest records first', () {
    for (var i = 0; i < ThumbnailStampRegistry.maxEntries + 5; i++) {
      ThumbnailStampRegistry.record(uri, 'f$i', 1, 1);
    }
    expect(ThumbnailStampRegistry.length, ThumbnailStampRegistry.maxEntries);
    expect(ThumbnailStampRegistry.segmentFor(uri, 'f0'), isNull);
    expect(
      ThumbnailStampRegistry.segmentFor(
        uri,
        'f${ThumbnailStampRegistry.maxEntries + 4}',
      ),
      isNotNull,
    );
  });
}
