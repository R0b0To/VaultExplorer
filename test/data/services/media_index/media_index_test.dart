import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vaultexplorer/data/services/media_index/media_index.dart';
import 'package:vaultexplorer/data/services/media_index/media_index_codec.dart';
import 'package:vaultexplorer/data/services/media_index/media_path_hash.dart';

void main() {
  group('MediaPathHash', () {
    test('is FNV-1a 64 (published test vectors)', () {
      expect(MediaPathHash.ofPath(''), 0xcbf29ce484222325);
      expect(MediaPathHash.ofPath('a'), 0xaf63dc4c8601ec8c);
      expect(MediaPathHash.ofPath('foobar'), 0x85944171f73967e8);
    });

    test('hashing a folder once then each name equals hashing the whole path', () {
      final dirs = ['', '/', 'Photos', '/Photos/2024', 'a/b/c'];
      final names = ['x.jpg', 'IMG 0001.heic', 'ünï.png', '日本語.jpg'];
      for (final dir in dirs) {
        final state = MediaPathHash.stateOfDir(dir);
        for (final name in names) {
          final full = dir.isEmpty || dir == '/' ? name : '$dir/$name';
          expect(MediaPathHash.ofName(state, name), MediaPathHash.ofPath(full),
              reason: '"$dir" + "$name"');
        }
      }
    });

    test('a leading slash does not matter', () {
      expect(MediaPathHash.ofPath('/a/b.jpg'), MediaPathHash.ofPath('a/b.jpg'));
      // Category views pass full paths as names with the root state.
      expect(MediaPathHash.ofName(MediaPathHash.root, '/a/b.jpg'),
          MediaPathHash.ofPath('a/b.jpg'));
    });

    test('different paths differ', () {
      final seen = <int>{};
      for (var i = 0; i < 50000; i++) {
        seen.add(MediaPathHash.ofPath('Photos/2024/IMG_$i.jpg'));
      }
      expect(seen.length, 50000);
    });
  });

  group('MediaIndex', () {
    test('lookup returns the size only for the file it was measured on', () {
      final index = MediaIndex()..record(42, 1000, 1700000000, 4000, 3000);
      final hit = index.lookup(42, 1000, 1700000000);
      expect(MediaIndex.widthOf(hit), 4000);
      expect(MediaIndex.heightOf(hit), 3000);
      expect(index.lookup(42, 1001, 1700000000), 0, reason: 'size changed');
      expect(index.lookup(42, 1000, 1700000001), 0, reason: 'modified');
      expect(index.lookup(43, 1000, 1700000000), 0, reason: 'other file');
    });

    test('recording the same measurement again changes nothing', () {
      final index = MediaIndex()..record(1, 10, 20, 100, 200);
      final revision = index.revision;
      index.record(1, 10, 20, 100, 200);
      expect(index.revision, revision);
      index.record(1, 10, 20, 100, 201);
      expect(index.revision, revision + 1);
      // Invalid sizes are ignored.
      index.record(2, 1, 1, 0, 5);
      index.record(2, 1, 1, 5, -1);
      expect(index.lookup(2, 1, 1), 0);
    });

    test('compact merges the overlay into sorted arrays, newest wins', () {
      final rnd = math.Random(3);
      final index = MediaIndex();
      final expected = <int, (int, int)>{};
      for (var round = 0; round < 5; round++) {
        for (var i = 0; i < 3000; i++) {
          final hash = rnd.nextInt(4000) - 2000; // negatives too, plenty of overlap
          final w = 1 + rnd.nextInt(9000);
          final h = 1 + rnd.nextInt(9000);
          index.record(hash, hash.abs(), 5, w, h);
          expected[hash] = (w, h);
        }
        final snap = index.compact();
        for (var i = 1; i < snap.length; i++) {
          expect(snap.hashes[i - 1] < snap.hashes[i], isTrue);
        }
        expect(snap.length, expected.length);
      }
      for (final e in expected.entries) {
        final packed = index.lookup(e.key, e.key.abs(), 5);
        expect(MediaIndex.widthOf(packed), e.value.$1);
        expect(MediaIndex.heightOf(packed), e.value.$2);
      }
    });

    test('a changed file is replaced, not duplicated', () {
      final index = MediaIndex()..record(7, 100, 1, 10, 10);
      index.compact();
      index.record(7, 200, 2, 20, 30); // edited
      expect(index.lookup(7, 100, 1), 0);
      final packed = index.lookup(7, 200, 2);
      expect(MediaIndex.widthOf(packed), 20);
      expect(index.compact().length, 1);
    });

    test('stays under the cap, keeping what is fresh', () {
      final index = MediaIndex();
      for (var i = 0; i < MediaIndex.maxEntries; i++) {
        index.record(i * 2, 1, 1, 4, 3);
      }
      index.compact();
      for (var i = 0; i < 1000; i++) {
        index.record(i * 2 + 1, 1, 1, 5, 5);
      }
      final snap = index.compact();
      expect(snap.length, MediaIndex.maxEntries);
      for (var i = 0; i < 1000; i++) {
        expect(index.lookup(i * 2 + 1, 1, 1) != 0, isTrue, reason: 'fresh $i');
      }
    });

    test('unsaved-changes tracking', () {
      final index = MediaIndex();
      expect(index.hasUnsavedChanges, isFalse);
      index.record(1, 1, 1, 2, 2);
      expect(index.hasUnsavedChanges, isTrue);
      final rev = index.revision;
      index.record(2, 1, 1, 2, 2); // arrives "while writing"
      index.markSaved(rev);
      expect(index.hasUnsavedChanges, isTrue);
      index.markSaved(index.revision);
      expect(index.hasUnsavedChanges, isFalse);
    });

    test('binary search over a large index', () {
      final index = MediaIndex();
      for (var i = 0; i < 100000; i++) {
        index.record(MediaPathHash.ofPath('p/$i.jpg'), i, i, 1 + i % 5000, 1 + i % 3000);
      }
      index.compact();
      final sw = Stopwatch()..start();
      var hits = 0;
      for (var i = 0; i < 100000; i++) {
        if (index.lookup(MediaPathHash.ofPath('p/$i.jpg'), i, i) != 0) hits++;
      }
      sw.stop();
      expect(hits, 100000);
      expect(sw.elapsedMilliseconds < 3000, isTrue, reason: '${sw.elapsedMilliseconds} ms');
    });
  });

  group('MediaIndexCodec', () {
    MediaIndexSnapshot sample(int n) {
      final index = MediaIndex();
      for (var i = 0; i < n; i++) {
        index.record(MediaPathHash.ofPath('f/$i'), i * 7, 1700000000 + i, 1 + i, 2 + i);
      }
      return index.compact();
    }

    test('round trips', () {
      final snap = sample(500);
      final bytes = MediaIndexCodec.encode(snap);
      expect(bytes.length, MediaIndexCodec.headerSize + 500 * MediaIndexCodec.entrySize);
      final back = MediaIndexCodec.decode(bytes)!;
      expect(back.length, 500);
      for (var i = 0; i < 500; i++) {
        expect(back.hashes[i], snap.hashes[i]);
        expect(back.sizes[i], snap.sizes[i]);
        expect(back.mtimes[i], snap.mtimes[i]);
        expect(back.widths[i], snap.widths[i]);
        expect(back.heights[i], snap.heights[i]);
      }
    });

    test('an empty index round trips', () {
      final back = MediaIndexCodec.decode(MediaIndexCodec.encode(MediaIndexSnapshot.empty));
      expect(back != null && back.length == 0, isTrue);
    });

    test('damage of any kind means "no index", never a wrong one', () {
      final bytes = MediaIndexCodec.encode(sample(300));
      expect(MediaIndexCodec.decode(Uint8List(0)), null);
      expect(MediaIndexCodec.decode(Uint8List.sublistView(bytes, 0, bytes.length - 1)), null);
      expect(MediaIndexCodec.decode(Uint8List.sublistView(bytes, 0, 10)), null);
      final rnd = math.Random(8);
      for (var t = 0; t < 200; t++) {
        final damaged = Uint8List.fromList(bytes);
        damaged[rnd.nextInt(damaged.length)] ^= 1 << rnd.nextInt(8);
        expect(MediaIndexCodec.decode(damaged), null, reason: 'trial $t');
      }
      final wrongMagic = Uint8List.fromList(bytes)..[0] = 0x00;
      expect(MediaIndexCodec.decode(wrongMagic), null);
      final futureVersion = Uint8List.fromList(bytes)..[4] = 99;
      expect(MediaIndexCodec.decode(futureVersion), null);
    });

    test('an unsorted body is rejected even with a valid checksum', () {
      final snap = sample(10);
      final swapped = MediaIndexSnapshot(
        hashes: Int64List.fromList(snap.hashes.reversed.toList()),
        sizes: snap.sizes,
        mtimes: snap.mtimes,
        widths: snap.widths,
        heights: snap.heights,
      );
      expect(MediaIndexCodec.decode(MediaIndexCodec.encode(swapped)), null);
    });

    test('crc32 matches the standard check value', () {
      final data = Uint8List.fromList('123456789'.codeUnits);
      expect(MediaIndexCodec.crc32(data, 0, data.length), 0xCBF43926);
    });

    test('big indexes go through an isolate and still round trip', () async {
      final snap = sample(MediaIndexCodec.isolateThreshold + 500);
      final bytes = await MediaIndexCodec.encodeAsync(snap);
      final back = (await MediaIndexCodec.decodeAsync(bytes))!;
      expect(back.length, snap.length);
      expect(back.hashes[1234], snap.hashes[1234]);
      expect(back.heights.last, snap.heights.last);
    });

    test('a 200k-entry index is a few MB and fast to encode', () {
      final snap = sample(200000);
      final sw = Stopwatch()..start();
      final bytes = MediaIndexCodec.encode(snap);
      final enc = sw.elapsedMilliseconds;
      sw.reset();
      MediaIndexCodec.decode(bytes);
      final dec = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('       200k entries: ${(bytes.length / 1e6).toStringAsFixed(1)} MB, encode $enc ms, decode $dec ms');
      expect(bytes.length, MediaIndexCodec.headerSize + 200000 * 28);
    });
  });
}
