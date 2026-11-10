import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_index.dart';

Uint8List _jpegWithSize(int w, int h) => Uint8List.fromList([
  0xFF, 0xD8, //
  0xFF, 0xC0, 0x00, 0x0B, 8, h >> 8, h & 0xFF, w >> 8, w & 0xFF, 1, 1, 0x11, 0,
  0xFF, 0xDA, 0x00, 0x02, 0x00, 0x00,
]);

class _MemoryStorage implements GalleryMetaStorage {
  final Map<int, String> files = {};
  int saves = 0;

  @override
  Future<String?> load(int volId) async => files[volId];

  @override
  Future<bool> save(int volId, String json) async {
    files[volId] = json;
    saves++;
    return true;
  }
}

Future<void> _idle(GalleryMetaIndex index) async {
  for (var i = 0; i < 200 && index.isIndexing; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  // let the final flush finish
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  group('GalleryMetaIndex', () {
    test('reads queued photos and answers lookups for the same size and date', () async {
      final reads = <String>[];
      final index = GalleryMetaIndex(
        readHeader: (vol, path, length) async {
          reads.add(path);
          return _jpegWithSize(400, 300);
        },
        notifyEvery: const Duration(milliseconds: 1),
      );
      await index.ensure([
        const GalleryIndexRequest(1, 'a/1.jpg', 1000, 50),
        const GalleryIndexRequest(1, 'a/2.jpg', 1000, 50),
        const GalleryIndexRequest(1, 'a/clip.mp4', 1000, 50), // not parsed
      ]);
      await _idle(index);

      expect(reads.length, 2);
      expect(index.lookup(1, 'a/1.jpg', 1000, 50)?.width, 400);
      expect(index.lookup(1, 'a/1.jpg', 999, 50), isNull); // size changed
      expect(index.lookup(1, 'a/1.jpg', 1000, 51), isNull); // date changed
      expect(index.lookup(1, 'a/clip.mp4', 1000, 50), isNull);
      index.dispose();
    });

    test('does not read a photo twice', () async {
      var reads = 0;
      final index = GalleryMetaIndex(
        readHeader: (vol, path, length) async {
          reads++;
          return _jpegWithSize(10, 10);
        },
      );
      const req = GalleryIndexRequest(1, 'x.jpg', 500, 1);
      await index.ensure([req, req]);
      await _idle(index);
      await index.ensure([req]);
      await _idle(index);
      expect(reads, 1);
      index.dispose();
    });

    test('an unreadable file stays unknown instead of being recorded as empty', () async {
      final index = GalleryMetaIndex(readHeader: (vol, path, length) async => null);
      await index.ensure([const GalleryIndexRequest(1, 'x.jpg', 500, 1)]);
      await _idle(index);
      expect(index.lookup(1, 'x.jpg', 500, 1), isNull);
      index.dispose();
    });

    test('is saved and loaded back by a later session', () async {
      final storage = _MemoryStorage();
      final first = GalleryMetaIndex(
        readHeader: (vol, path, length) async => _jpegWithSize(640, 480),
        storage: storage,
      );
      await first.ensure([const GalleryIndexRequest(7, 'p.jpg', 321, 9)]);
      await _idle(first);
      first.dispose();
      expect(storage.saves, greaterThan(0));

      var reads = 0;
      final second = GalleryMetaIndex(
        readHeader: (vol, path, length) async {
          reads++;
          return null;
        },
        storage: storage,
      );
      await second.ensure([const GalleryIndexRequest(7, 'p.jpg', 321, 9)]);
      await _idle(second);
      expect(reads, 0);
      expect(second.lookup(7, 'p.jpg', 321, 9)?.height, 480);
      second.dispose();
    });
  });
}
