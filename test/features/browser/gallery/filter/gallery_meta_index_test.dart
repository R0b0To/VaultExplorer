import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_index.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_parser.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_worker.dart';

Uint8List _jpegWithSize(int w, int h) => Uint8List.fromList([
  0xFF, 0xD8, //
  0xFF, 0xC0, 0x00, 0x0B, 8, h >> 8, h & 0xFF, w >> 8, w & 0xFF, 1, 1, 0x11, 0,
  0xFF, 0xDA, 0x00, 0x02, 0x00, 0x00,
]);

class _MemoryStorage implements GalleryMetaStorage {
  /// What is stored per source: a log of segments, oldest first.
  final Map<int, List<String>> segments = {};
  int appends = 0;
  int failedAppends = 0;
  int replaces = 0;

  /// Makes the next [failures] appends fail.
  int failures = 0;

  /// Sources that cannot be stored at all.
  final Set<int> unsaveable = {};

  @override
  bool persists(int volId) => !unsaveable.contains(volId);

  @override
  Future<List<String>> loadSegments(int volId) async =>
      List.of(segments[volId] ?? const []);

  @override
  Future<bool> appendSegment(int volId, String json) async {
    if (failures > 0) {
      failures--;
      failedAppends++;
      return false;
    }
    (segments[volId] ??= []).add(json);
    appends++;
    return true;
  }

  @override
  Future<bool> replaceSegments(int volId, String json) async {
    segments[volId] = [json];
    replaces++;
    return true;
  }

  /// The paths of every stored segment of [volId], one list per segment.
  List<List<String>> pathsPerSegment(int volId) => [
    for (final text in segments[volId] ?? const <String>[])
      [for (final k in ((jsonDecode(text) as Map)['e'] as Map).keys) k as String],
  ];
}

Future<void> _idle(GalleryMetaIndex index) async {
  for (var i = 0; i < 400 && index.isIndexing; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  // The final append and any compaction queue behind each other: wait for the
  // whole chain instead of guessing how long it takes.
  await index.flush();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await index.flush();
}

GalleryIndexRequest _req(int i, {int vol = 1}) =>
    GalleryIndexRequest(vol, 'dir/p$i.jpg', 1000 + i, 50);

Future<GalleryMeta> _inlineParse(Uint8List b) async => GalleryMetaParser.parse(b);

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
      expect(storage.appends, greaterThan(0));

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

    test('queued photos are read in order, one at a time when asked to', () async {
      final reads = <String>[];
      final index = GalleryMetaIndex(
        readHeader: (vol, path, length) async {
          reads.add(path);
          return _jpegWithSize(10, 10);
        },
        parse: _inlineParse,
        concurrency: 1,
      );
      await index.ensure([for (var i = 0; i < 25; i++) _req(i)]);
      await _idle(index);
      expect(reads, [for (var i = 0; i < 25; i++) 'dir/p$i.jpg']);
      index.dispose();
    });

    group('saving', () {
      test('appends one small segment per batch instead of rewriting everything', () async {
        final storage = _MemoryStorage();
        final index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => _jpegWithSize(64, 48),
          parse: _inlineParse,
          storage: storage,
          saveEvery: 4,
          compactAfter: 1000,
          maxSegments: 1000,
        );
        await index.ensure([for (var i = 0; i < 10; i++) _req(i)]);
        await _idle(index);

        final per = storage.pathsPerSegment(1);
        expect(per.length, 3); // 4 + 4 + the 2 left when the run ended
        for (final seg in per) {
          expect(seg.length <= 4, isTrue, reason: 'a segment holds one batch');
        }
        final all = [for (final seg in per) ...seg];
        expect(all.length, 10);
        expect(all.toSet().length, 10); // nothing written twice
        expect(storage.replaces, 0);
        index.dispose();
      });

      test('a later session sees every segment, the newest winning', () async {
        final storage = _MemoryStorage();
        String seg(Map<String, List<Object?>> e) => jsonEncode({'v': 1, 'e': e});
        const meta = [null, null, null, null, null, <String>[], null, 10, 10];
        storage.segments[3] = [
          // size/mtime of a.jpg change in the second segment
          seg({'a.jpg': [100, 1, ...meta], 'b.jpg': [200, 1, ...meta]}),
          seg({'a.jpg': [111, 2, ...meta]}),
        ];
        final index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => null,
          parse: _inlineParse,
          storage: storage,
        );
        await index.loadStored([3]);
        expect(index.lookup(3, 'a.jpg', 100, 1), isNull); // superseded
        expect(index.lookup(3, 'a.jpg', 111, 2)?.width, 10);
        expect(index.lookup(3, 'b.jpg', 200, 1)?.width, 10);
        expect(index.publishedRevision, index.revision); // loading is published at once
        index.dispose();
      });

      test('a damaged segment is skipped, the rest is kept', () async {
        final storage = _MemoryStorage();
        const meta = [null, null, null, null, null, <String>[], null, 7, 7];
        storage.segments[1] = [
          '{not json',
          jsonEncode({'v': 99, 'e': {}}), // other version
          jsonEncode({'v': 1, 'e': {'ok.jpg': [5, 5, ...meta], 'bad.jpg': [1]}}),
        ];
        final index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => null,
          parse: _inlineParse,
          storage: storage,
        );
        await index.loadStored([1]);
        expect(index.lookup(1, 'ok.jpg', 5, 5)?.width, 7);
        expect(index.lookup(1, 'bad.jpg', 1, 1), isNull);
        index.dispose();
      });

      test('a failed append is retried with the same photos at the next flush', () async {
        final storage = _MemoryStorage()..failures = 1;
        final index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => _jpegWithSize(5, 5),
          parse: _inlineParse,
          storage: storage,
          saveEvery: 1000,
        );
        await index.ensure([_req(1), _req(2)]);
        await _idle(index); // first append fails, the retry in _idle's flush succeeds
        final all = [for (final seg in storage.pathsPerSegment(1)) ...seg];
        expect(all.toSet(), {'dir/p1.jpg', 'dir/p2.jpg'});
        index.dispose();
      });

      test('segments are merged into one once there are too many', () async {
        final storage = _MemoryStorage();
        final index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => _jpegWithSize(9, 9),
          parse: _inlineParse,
          storage: storage,
          saveEvery: 1,
          compactAfter: 3,
          maxSegments: 1000,
        );
        await index.ensure([for (var i = 0; i < 8; i++) _req(i)]);
        await _idle(index);
        for (var i = 0; i < 50 && storage.segments[1]!.length != 1; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await index.flush();
        }
        expect(storage.segments[1]!.length, 1);
        expect(storage.replaces, greaterThan(0));
        final all = storage.pathsPerSegment(1).single;
        expect(all.toSet().length, 8);
        index.dispose();

        // And nothing is lost when a new session reads the merged log.
        final second = GalleryMetaIndex(
          readHeader: (vol, path, length) async => null,
          parse: _inlineParse,
          storage: storage,
        );
        await second.loadStored([1]);
        for (var i = 0; i < 8; i++) {
          expect(second.lookup(1, 'dir/p$i.jpg', 1000 + i, 50)?.width, 9);
        }
        second.dispose();
      });

      test('compaction during a run cannot drop an append queued behind it', () async {
        final storage = _MemoryStorage();
        final index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => _jpegWithSize(3, 3),
          parse: _inlineParse,
          storage: storage,
          saveEvery: 1,
          compactAfter: 1000,
          maxSegments: 2, // compacts again and again while the run goes on
          concurrency: 1,
        );
        await index.ensure([for (var i = 0; i < 12; i++) _req(i)]);
        await _idle(index);
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await index.flush();
        }
        final second = GalleryMetaIndex(
          readHeader: (vol, path, length) async => null,
          parse: _inlineParse,
          storage: storage,
        );
        await second.loadStored([1]);
        for (var i = 0; i < 12; i++) {
          expect(second.lookup(1, 'dir/p$i.jpg', 1000 + i, 50)?.width, 3, reason: 'photo $i');
        }
        second.dispose();
        index.dispose();
      });
    });

    group('publishing', () {
      test('results are published in batches, with a final one when the run ends', () async {
        final seen = <int>[];
        late GalleryMetaIndex index;
        index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => _jpegWithSize(8, 8),
          parse: _inlineParse,
          concurrency: 1,
          notifyBatch: 3,
          notifyEvery: const Duration(hours: 1),
          maxPublishDelay: const Duration(hours: 1),
        );
        index.addListener(() {
          if (seen.isEmpty || seen.last != index.publishedRevision) {
            seen.add(index.publishedRevision);
          }
        });
        await index.ensure([for (var i = 0; i < 7; i++) _req(i)]);
        await _idle(index);
        expect(index.revision, 7);
        expect(seen, [3, 6, 7]);
        expect(index.publishedRevision, 7);
        index.dispose();
      });

      test('nothing is published while paused, and it is published on resume', () async {
        final index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => _jpegWithSize(8, 8),
          parse: _inlineParse,
          concurrency: 1,
          notifyBatch: 1,
          notifyEvery: const Duration(hours: 1),
        );
        index.paused = true;
        await index.ensure([for (var i = 0; i < 4; i++) _req(i)]);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(index.revision, 0, reason: 'no read starts while paused');
        expect(index.pending, 4);

        index.paused = false;
        await _idle(index);
        expect(index.revision, 4);
        expect(index.publishedRevision, 4);
        index.dispose();
      });

      test('a pause that starts mid-run holds back the next reads and the publish', () async {
        var reads = 0;
        late GalleryMetaIndex index;
        index = GalleryMetaIndex(
          readHeader: (vol, path, length) async {
            reads++;
            if (reads == 2) index.paused = true; // the user starts scrolling
            return _jpegWithSize(8, 8);
          },
          parse: _inlineParse,
          concurrency: 1,
          notifyBatch: 1,
          notifyEvery: const Duration(hours: 1),
        );
        await index.ensure([for (var i = 0; i < 6; i++) _req(i)]);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(reads, 2);
        expect(index.revision, 2);
        expect(index.publishedRevision, 1, reason: 'the second result waits for the scroll to stop');
        index.paused = false;
        await _idle(index);
        expect(reads, 6);
        expect(index.publishedRevision, 6);
        index.dispose();
      });

      test('progress still ticks while results are held back', () async {
        var ticks = 0;
        final index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => _jpegWithSize(8, 8),
          parse: _inlineParse,
          concurrency: 1,
          notifyBatch: 1000,
          notifyEvery: const Duration(milliseconds: 5),
          maxPublishDelay: const Duration(hours: 1),
        )..addListener(() => ticks++);
        await index.ensure([for (var i = 0; i < 5; i++) _req(i)]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(ticks, greaterThan(0));
        await _idle(index);
        index.dispose();
      });
    });

    group('session memory', () {
      GalleryMetaIndex make(GalleryMetaMemory memory, List<String> reads,
          {GalleryMetaStorage? storage, bool Function(int)? retain}) {
        return GalleryMetaIndex(
          readHeader: (vol, path, length) async {
            reads.add('$vol|$path');
            return _jpegWithSize(11, 22);
          },
          parse: _inlineParse,
          storage: storage,
          memory: memory,
          retain: retain ?? (vol) => vol == 1,
        );
      }

      test('a new index continues where the previous one stopped', () async {
        final memory = GalleryMetaMemory();
        final reads = <String>[];
        final first = make(memory, reads, retain: (_) => true);
        await first.ensure([for (var i = 0; i < 30; i++) _req(i)]);
        await _idle(first);
        first.dispose(); // the gallery view was closed
        expect(reads.length, 30);
        expect(memory.entryCount(1), 30);

        // Reopened with 10 photos more: only those are read.
        reads.clear();
        final second = make(memory, reads, retain: (_) => true);
        await second.ensure([for (var i = 0; i < 40; i++) _req(i)]);
        expect(second.total, 10);
        await _idle(second);
        expect(reads, [for (var i = 30; i < 40; i++) 'dir/p$i.jpg'].map((p) => '1|$p').toList());
        expect(second.lookup(1, 'dir/p3.jpg', 1003, 50)?.width, 11);
        second.dispose();
      });

      test('what is remembered is usable at once and published to the view', () async {
        final memory = GalleryMetaMemory();
        final first = make(memory, <String>[], retain: (_) => true);
        await first.ensure([_req(1), _req(2)]);
        await _idle(first);
        first.dispose();

        final second = make(memory, <String>[], retain: (_) => true);
        final published = <int>[];
        second.addListener(() => published.add(second.publishedRevision));
        await second.loadStored([1]);
        expect(second.lookup(1, 'dir/p1.jpg', 1001, 50)?.width, 11);
        expect(second.publishedRevision, greaterThan(0));
        expect(published, isNotEmpty);
        second.dispose();
      });

      test('only the sources retain selects are shared', () async {
        final memory = GalleryMetaMemory();
        final reads = <String>[];
        final first = make(memory, reads, retain: (vol) => vol == 1);
        await first.ensure([_req(1, vol: 1), _req(1, vol: 2)]);
        await _idle(first);
        first.dispose();
        expect(memory.entryCount(1), 1);
        expect(memory.entryCount(2), 0);

        reads.clear();
        final second = make(memory, reads, retain: (vol) => vol == 1);
        await second.ensure([_req(1, vol: 1), _req(1, vol: 2)]);
        await _idle(second);
        expect(reads, ['2|dir/p1.jpg']); // the vault source is read again
        second.dispose();
      });

      test('a changed file is read again even though its path is remembered', () async {
        final memory = GalleryMetaMemory();
        final reads = <String>[];
        final first = make(memory, reads, retain: (_) => true);
        await first.ensure([const GalleryIndexRequest(1, 'a.jpg', 100, 5)]);
        await _idle(first);
        first.dispose();
        reads.clear();
        final second = make(memory, reads, retain: (_) => true);
        await second.ensure([const GalleryIndexRequest(1, 'a.jpg', 100, 6)]); // newer mtime
        await _idle(second);
        expect(reads, ['1|a.jpg']);
        second.dispose();
      });

      test('forget drops a source from the memory too', () async {
        final memory = GalleryMetaMemory();
        final index = make(memory, <String>[], retain: (_) => true);
        await index.ensure([_req(1), _req(2)]);
        await _idle(index);
        expect(memory.entryCount(1), 2);
        index.forget(1);
        expect(memory.entryCount(1), 0);
        index.dispose();
      });

      test('without a memory nothing is kept past the index', () async {
        final reads = <String>[];
        final first = GalleryMetaIndex(
          readHeader: (vol, path, length) async {
            reads.add(path);
            return _jpegWithSize(5, 5);
          },
          parse: _inlineParse,
        );
        await first.ensure([_req(1)]);
        await _idle(first);
        first.dispose();
        reads.clear();
        final second = GalleryMetaIndex(
          readHeader: (vol, path, length) async {
            reads.add(path);
            return _jpegWithSize(5, 5);
          },
          parse: _inlineParse,
        );
        await second.ensure([_req(1)]);
        await _idle(second);
        expect(reads.length, 1);
        second.dispose();
      });

      test('the memory is bounded like any source', () async {
        final memory = GalleryMetaMemory();
        final index = make(memory, <String>[], retain: (_) => true);
        await index.ensure([for (var i = 0; i < 20; i++) _req(i)]);
        await _idle(index);
        expect(memory.entryCount(1) <= GalleryMetaIndex.maxEntriesPerSource, isTrue);
        index.dispose();
      });
    });

    group('sources that cannot be saved', () {
      test('no snapshot is built or written for them, however many photos are read', () async {
        final storage = _MemoryStorage()..unsaveable.add(1);
        final index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => _jpegWithSize(7, 7),
          parse: _inlineParse,
          storage: storage,
          saveEvery: 3,
        );
        await index.ensure([for (var i = 0; i < 20; i++) _req(i)]);
        await _idle(index);
        expect(storage.appends, 0);
        expect(storage.failedAppends, 0, reason: 'never even attempted');
        expect(index.lookup(1, 'dir/p5.jpg', 1005, 50)?.width, 7);
        index.dispose();
      });

      test('a source that can be saved next to one that cannot still is', () async {
        final storage = _MemoryStorage()..unsaveable.add(1);
        final index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => _jpegWithSize(7, 7),
          parse: _inlineParse,
          storage: storage,
          saveEvery: 3,
        );
        await index.ensure([for (var i = 0; i < 6; i++) _req(i, vol: 1), for (var i = 0; i < 6; i++) _req(i, vol: 2)]);
        await _idle(index);
        expect(storage.segments[1], isNull);
        expect([for (final seg in storage.pathsPerSegment(2)) ...seg].length, 6);
        index.dispose();
      });
    });

    group('worker isolate', () {
      test('by default photos are parsed on a background isolate and give the same answer', () async {
        final index = GalleryMetaIndex(
          readHeader: (vol, path, length) async => _jpegWithSize(400, 300),
        );
        await index.ensure([for (var i = 0; i < 6; i++) _req(i)]);
        await _idle(index);
        for (var i = 0; i < 6; i++) {
          final m = index.lookup(1, 'dir/p$i.jpg', 1000 + i, 50);
          expect(m?.width, 400);
          expect(m?.height, 300);
        }
        index.dispose();
      });

      test('the worker parses like the parser and stops by itself when idle', () async {
        final worker = GalleryMetaWorker(idleTimeout: const Duration(milliseconds: 60));
        final bytes = _jpegWithSize(123, 45);
        final viaWorker = await worker.parse(bytes);
        expect(viaWorker, GalleryMetaParser.parse(bytes));
        expect(worker.isRunning, isTrue);
        for (var i = 0; i < 100 && worker.isRunning; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(worker.isRunning, isFalse);
        // It starts again on demand.
        expect((await worker.parse(bytes)).width, 123);
        worker.dispose();
        // After dispose it still answers, inline.
        expect((await worker.parse(bytes)).height, 45);
      });

      test('many parses in flight at once all come back to the right caller', () async {
        final worker = GalleryMetaWorker();
        final futures = [
          for (var i = 1; i <= 40; i++) worker.parse(_jpegWithSize(i, 2 * i)),
        ];
        final results = await Future.wait(futures);
        for (var i = 1; i <= 40; i++) {
          expect(results[i - 1].width, i);
          expect(results[i - 1].height, 2 * i);
        }
        worker.dispose();
      });
    });
  });
}
