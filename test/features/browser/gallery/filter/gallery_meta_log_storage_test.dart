import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_log_storage.dart';

class _Files implements GalleryMetaFiles {
  _Files({this.readOnly = false});

  @override
  final bool readOnly;
  final Map<String, Uint8List> files = {};
  final List<String> writes = [];
  final List<String> deletes = [];

  /// Names whose deletion fails.
  final Set<String> stuck = {};

  @override
  Future<List<String>?> listNames() async => files.keys.toList()..shuffle();

  @override
  Future<Uint8List?> read(String name) async => files[name];

  @override
  Future<bool> write(String name, Uint8List bytes) async {
    writes.add(name);
    files[name] = bytes;
    return true;
  }

  @override
  Future<bool> delete(String name) async {
    deletes.add(name);
    if (stuck.contains(name)) return false;
    return files.remove(name) != null;
  }
}

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('GalleryMetaSegmentNames', () {
    test('the base file is 0, numbered files are their number, others are not ours', () {
      expect(GalleryMetaSegmentNames.seqOf('gallery_meta.json'), 0);
      expect(GalleryMetaSegmentNames.seqOf('gallery_meta.000001.json'), 1);
      expect(GalleryMetaSegmentNames.seqOf('gallery_meta.000123.json'), 123);
      expect(GalleryMetaSegmentNames.seqOf('gallery_meta.1234567.json'), 1234567);
      expect(GalleryMetaSegmentNames.seqOf('gallery_meta..json'), isNull);
      expect(GalleryMetaSegmentNames.seqOf('gallery_meta.abc.json'), isNull);
      expect(GalleryMetaSegmentNames.seqOf('gallery_meta.000000.json'), isNull);
      expect(GalleryMetaSegmentNames.seqOf('gallery_meta.-3.json'), isNull);
      expect(GalleryMetaSegmentNames.seqOf('marks.json'), isNull);
      expect(GalleryMetaSegmentNames.seqOf('gallery_meta.000001.json.tmp'), isNull);
    });

    test('names round-trip', () {
      for (final n in [0, 1, 9, 10, 999999, 1000000]) {
        expect(GalleryMetaSegmentNames.seqOf(GalleryMetaSegmentNames.nameOf(n)), n);
      }
      expect(GalleryMetaSegmentNames.nameOf(7), 'gallery_meta.000007.json');
    });

    test('numbered names sort in numeric order', () {
      final names = [for (final n in [12, 3, 100, 1, 25]) GalleryMetaSegmentNames.nameOf(n)];
      final bySeq = [...names]
        ..sort((a, b) => GalleryMetaSegmentNames.seqOf(a)!.compareTo(GalleryMetaSegmentNames.seqOf(b)!));
      expect([for (final n in bySeq) GalleryMetaSegmentNames.seqOf(n)], [1, 3, 12, 25, 100]);
    });
  });

  group('GalleryMetaLogStorage', () {
    test('an old single-file index is read as the first segment', () async {
      final files = _Files()..files['gallery_meta.json'] = _b('{"old":true}');
      final storage = GalleryMetaLogStorage((_) => files);
      expect(await storage.loadSegments(1), ['{"old":true}']);
    });

    test('appends go to new numbered files after the existing ones, in order', () async {
      final files = _Files()..files['gallery_meta.json'] = _b('base');
      final storage = GalleryMetaLogStorage((_) => files);
      await storage.loadSegments(1);
      expect(await storage.appendSegment(1, 'one'), isTrue);
      expect(await storage.appendSegment(1, 'two'), isTrue);
      expect(await storage.appendSegment(1, 'three'), isTrue);
      expect(files.writes, [
        'gallery_meta.000001.json',
        'gallery_meta.000002.json',
        'gallery_meta.000003.json',
      ]);
      expect(await storage.loadSegments(1), ['base', 'one', 'two', 'three']);
    });

    test('a fresh storage object continues the numbering of what is stored', () async {
      final files = _Files();
      final a = GalleryMetaLogStorage((_) => files);
      await a.appendSegment(1, 'x');
      await a.appendSegment(1, 'y');
      final b = GalleryMetaLogStorage((_) => files); // a new session, nothing loaded yet
      await b.appendSegment(1, 'z');
      expect(await b.loadSegments(1), ['x', 'y', 'z']);
    });

    test('segments come back in numeric order even when the folder lists them shuffled', () async {
      final files = _Files();
      final storage = GalleryMetaLogStorage((_) => files);
      for (var i = 0; i < 30; i++) {
        await storage.appendSegment(1, 's$i');
      }
      expect(await storage.loadSegments(1), [for (var i = 0; i < 30; i++) 's$i']);
    });

    test('replacing writes the base, then drops the numbered files', () async {
      final files = _Files();
      final storage = GalleryMetaLogStorage((_) => files);
      await storage.appendSegment(1, 'a');
      await storage.appendSegment(1, 'b');
      files.writes.clear();
      expect(await storage.replaceSegments(1, 'merged'), isTrue);
      expect(files.writes, ['gallery_meta.json']);
      expect(files.files.keys.toSet(), {'gallery_meta.json'});
      expect(await storage.loadSegments(1), ['merged']);
      await storage.appendSegment(1, 'c');
      expect(await storage.loadSegments(1), ['merged', 'c']);
    });

    test('if a segment cannot be deleted, later appends still come after it', () async {
      final files = _Files()..stuck.add('gallery_meta.000002.json');
      final storage = GalleryMetaLogStorage((_) => files);
      await storage.appendSegment(1, 'a');
      await storage.appendSegment(1, 'b');
      await storage.replaceSegments(1, 'merged');
      expect(files.files.keys.toSet(), {'gallery_meta.json', 'gallery_meta.000002.json'});
      await storage.appendSegment(1, 'c');
      expect(files.writes.last, 'gallery_meta.000003.json');
      expect(await storage.loadSegments(1), ['merged', 'b', 'c']);
    });

    test('unrelated files in the folder are neither read nor deleted', () async {
      final files = _Files()
        ..files['marks.json'] = _b('marks')
        ..files['gallery_meta.json.bak'] = _b('bak');
      final storage = GalleryMetaLogStorage((_) => files);
      await storage.appendSegment(1, 'a');
      expect(await storage.loadSegments(1), ['a']);
      await storage.replaceSegments(1, 'm');
      expect(files.files.containsKey('marks.json'), isTrue);
      expect(files.files.containsKey('gallery_meta.json.bak'), isTrue);
    });

    test('empty or unreadable files are skipped when loading', () async {
      final files = _Files()
        ..files['gallery_meta.000001.json'] = Uint8List(0)
        ..files['gallery_meta.000002.json'] = _b('ok');
      final storage = GalleryMetaLogStorage((_) => files);
      expect(await storage.loadSegments(1), ['ok']);
    });

    test('nothing is written to read-only sources, locked sources or when not allowed', () async {
      final ro = _Files(readOnly: true);
      final roStorage = GalleryMetaLogStorage((_) => ro);
      expect(await roStorage.appendSegment(1, 'x'), isFalse);
      expect(await roStorage.replaceSegments(1, 'x'), isFalse);
      expect(ro.files, isEmpty);

      final locked = GalleryMetaLogStorage((_) => null);
      expect(await locked.appendSegment(1, 'x'), isFalse);
      expect(await locked.loadSegments(1), isEmpty);

      final files = _Files();
      final denied = GalleryMetaLogStorage((_) => files, allowWrite: (_) => false);
      expect(await denied.appendSegment(1, 'x'), isFalse);
      expect(files.files, isEmpty);
    });

    test('persists says whether a batch could be stored at all', () {
      expect(GalleryMetaLogStorage((_) => _Files()).persists(1), isTrue);
      expect(GalleryMetaLogStorage((_) => _Files(readOnly: true)).persists(1), isFalse);
      expect(GalleryMetaLogStorage((_) => null).persists(1), isFalse); // phone storage, locked vault
      expect(
        GalleryMetaLogStorage((_) => _Files(), allowWrite: (v) => v == 2).persists(1),
        isFalse,
      );
      expect(
        GalleryMetaLogStorage((_) => _Files(), allowWrite: (v) => v == 2).persists(2),
        isTrue,
      );
    });

    test('a read-only source can still be read', () async {
      final ro = _Files(readOnly: true)..files['gallery_meta.json'] = _b('base');
      final storage = GalleryMetaLogStorage((_) => ro);
      expect(await storage.loadSegments(1), ['base']);
    });
  });
}
