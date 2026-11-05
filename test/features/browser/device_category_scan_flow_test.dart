import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/models/category_source.dart';
import 'package:vaultexplorer/features/browser/services/category_aggregate_scan.dart';
import 'package:vaultexplorer/features/browser/services/category_media_index_api.dart';
import 'package:vaultexplorer/features/browser/services/category_scan.dart';
import 'package:vaultexplorer/features/browser/services/category_walk_policy.dart';
import 'package:vaultexplorer/features/browser/services/device_category_index.dart';
import 'package:vaultexplorer/features/browser/services/device_category_index_store.dart';
import 'package:vaultexplorer/features/browser/services/raw_local_category_lister.dart';

bool _isImage(String n) {
  final l = n.toLowerCase();
  return l.endsWith('.jpg') || l.endsWith('.png');
}

bool _isHidden(String n) => n.startsWith('.');

/// Wraps the real lister, counting how many folders it is asked to list.
class _CountingLister {
  _CountingLister(this.inner);
  final CategoryDirectoryLister inner;
  final List<String> folders = [];
  Future<List<String>?> call(String dir) {
    folders.add(dir);
    return inner(dir);
  }
}

/// What the category views do for one phone-storage source, step for step:
/// seed from the index, try the lookup, otherwise walk, then remember.
Future<
  ({
    CategoryAggregateSnapshot result,
    List<CategoryAggregateSnapshot> shown,
    List<String> listed,
  })
>
_open({
  required String root,
  required DeviceCategoryIndex index,
  required bool deep,
  bool showHidden = false,
}) async {
  final key = DeviceCategoryIndexKey(
    rootPath: root,
    categoryKey: 'gallery',
    showHidden: showHidden,
  );
  final seed = await index.seed(key);
  final counting = _CountingLister(
    rawLocalCategoryLister(rootPath: root, matches: _isImage),
  );
  final source = CategorySource(
    volId: -1,
    type: CategorySourceType.device,
    label: 'Phone',
    dedupeRoot: root,
  );
  final shown = <CategoryAggregateSnapshot>[];
  final scanner = CategoryAggregateScanner(
    targets: [
      CategoryScanTarget(
        source: source,
        listDirectory: counting.call,
        skipDirectory: skipDeviceCategoryFolder,
        respectNoMedia: true,
        indexLookup: deep
            ? null
            : () => index.lookup(
                key,
                extensions: const ['jpg', 'png'],
                matches: _isImage,
                isHidden: _isHidden,
                skipDirectory: skipDeviceCategoryFolder,
              ),
        seed: seed,
      ),
    ],
    matches: _isImage,
    isHidden: _isHidden,
    showHidden: showHidden,
  );
  final result = await scanner.scan(
    token: CancellationToken(),
    onProgress: shown.add,
  );
  if (result.finished && !result.limitReached) {
    await index.remember(key, [
      for (final e in result.entries)
        RawEntry(
          name: e.path,
          isDir: false,
          sizeBytes: e.sizeBytes,
          modifiedSecs: e.modifiedSecs,
        ),
    ]);
  }
  return (result: result, shown: shown, listed: counting.folders);
}

void main() {
  late Directory root;
  late Directory cacheDir;

  /// A phone: a few real folders, and a few thousand that only hold junk.
  Future<void> buildPhone() async {
    Future<void> file(String rel, [int bytes = 4]) async {
      final f = File('${root.path}/$rel');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(Uint8List(bytes));
    }

    await file('DCIM/Camera/a.jpg', 10);
    await file('DCIM/Camera/b.png', 20);
    await file('Pictures/Screenshots/c.jpg', 30);
    await file('Download/notes.txt');
    await file('Hidden/.nomedia');
    await file('Hidden/secret.jpg');
    await file('Hidden/Deeper/more.jpg');
    // thousands of folders that never hold anything wanted
    for (var i = 0; i < 300; i++) {
      await file('node_modules/pkg$i/lib/x$i.jpg');
      await file('Android/data/com.app$i/files/y.jpg');
      await file('Pictures/Cache/n$i/z.jpg');
    }
  }

  DeviceCategoryIndex newIndex({
    IndexBytesTransform? xor,
    bool withMedia = false,
    List<String>? mediaRows,
  }) {
    final t =
        xor ??
        (Uint8List d) async =>
            Uint8List.fromList([for (final b in d) b ^ 0x2a]);
    return DeviceCategoryIndex(
      media: withMedia
          ? CategoryMediaIndexApi(
              (m, a) async => {'entries': mediaRows ?? <String>[]},
            )
          : null,
      store: DeviceCategoryIndexStore(
        directory: () async => cacheDir,
        encrypt: t,
        decrypt: t,
      ),
    );
  }

  setUp(() async {
    final tmp = await Directory.systemTemp.createTemp('flow_test');
    root = Directory('${tmp.path}/phone')..createSync();
    cacheDir = Directory('${tmp.path}/cache');
    await buildPhone();
  });

  tearDown(() async {
    if (await root.parent.exists()) await root.parent.delete(recursive: true);
  });

  group('opening phone storage again and again', () {
    test(
      'the first open walks, but prunes the junk (nowhere near every folder)',
      () async {
        final first = await _open(
          root: root.path,
          index: newIndex(),
          deep: false,
        );
        expect(first.result.entries.map((e) => e.path).toSet(), {
          'DCIM/Camera/a.jpg',
          'DCIM/Camera/b.png',
          'Pictures/Screenshots/c.jpg',
        });
        // 900+ folders exist under the junk roots; none of them was listed.
        expect(first.listed.any((d) => d.startsWith('node_modules')), isFalse);
        expect(first.listed.any((d) => d.startsWith('Android/data')), isFalse);
        expect(first.listed.any((d) => d.contains('Cache')), isFalse);
        // The .nomedia folder was read (to find the marker) but not entered.
        expect(first.listed, contains('Hidden'));
        expect(first.listed, isNot(contains('Hidden/Deeper')));
        expect(first.listed.length, lessThan(15));
      },
    );

    test(
      'the second open shows the last result at once, before any scan result',
      () async {
        final index = newIndex();
        await _open(root: root.path, index: index, deep: false);
        final second = await _open(root: root.path, index: index, deep: false);
        // The very first thing shown is already the full list.
        expect(second.shown.first.entries, hasLength(3));
        expect(second.shown.first.finished, isFalse);
      },
    );

    test(
      'after a restart the list is still there at once (from the encrypted file)',
      () async {
        await _open(root: root.path, index: newIndex(), deep: false);
        final restarted = newIndex(); // a new process: empty memory, same disk
        final open = await _open(
          root: root.path,
          index: restarted,
          deep: false,
        );
        expect(open.shown.first.entries, hasLength(3));
      },
    );

    test(
      'with the platform index available, opening lists no folder at all',
      () async {
        // The platform index reports what is really there.
        final rows = [
          'F|10|1|DCIM/Camera/a.jpg',
          'F|20|1|DCIM/Camera/b.png',
          'F|30|1|Pictures/Screenshots/c.jpg',
          'F|4|1|node_modules/pkg1/lib/x1.jpg', // junk the index also knows about
          'F|4|1|Android/data/com.app1/files/y.jpg',
        ];
        final index = newIndex(withMedia: true, mediaRows: rows);
        final open = await _open(root: root.path, index: index, deep: false);
        expect(open.listed, isEmpty);
        expect(open.result.foldersChecked, 0);
        expect(open.result.entries.map((e) => e.path).toSet(), {
          'DCIM/Camera/a.jpg',
          'DCIM/Camera/b.png',
          'Pictures/Screenshots/c.jpg',
        });
      },
    );

    test(
      'a pull to refresh walks even when the platform index would answer',
      () async {
        final index = newIndex(
          withMedia: true,
          mediaRows: ['F|1|1|stale/ghost.jpg'],
        );
        final open = await _open(root: root.path, index: index, deep: true);
        expect(open.listed, isNotEmpty);
        expect(
          open.result.entries.map((e) => e.path),
          isNot(contains('stale/ghost.jpg')),
        );
        expect(open.result.entries, hasLength(3));
      },
    );

    test(
      'a walk corrects what was remembered: a deleted file stops being shown',
      () async {
        final index = newIndex();
        await _open(root: root.path, index: index, deep: false);
        File('${root.path}/DCIM/Camera/a.jpg').deleteSync();
        final refreshed = await _open(
          root: root.path,
          index: index,
          deep: true,
        );
        expect(
          refreshed.result.entries.map((e) => e.path),
          isNot(contains('DCIM/Camera/a.jpg')),
        );
        // and the next open starts from the corrected list
        final next = await _open(root: root.path, index: index, deep: false);
        expect(next.shown.first.entries, hasLength(2));
      },
    );

    test(
      'an index that finds nothing falls back to the walk, not to an empty screen',
      () async {
        final index = newIndex(withMedia: true, mediaRows: const []);
        final open = await _open(root: root.path, index: index, deep: false);
        expect(open.listed, isNotEmpty);
        expect(open.result.entries, hasLength(3));
      },
    );

    test(
      'showing hidden files never reuses a list gathered without them',
      () async {
        final index = newIndex();
        await _open(
          root: root.path,
          index: index,
          deep: false,
          showHidden: false,
        );
        final key = DeviceCategoryIndexKey(
          rootPath: root.path,
          categoryKey: 'gallery',
          showHidden: true,
        );
        // Nothing is remembered for the other setting, so no stand-in shows.
        expect(await index.seed(key), isNull);
        final withHidden = await _open(
          root: root.path,
          index: index,
          deep: false,
          showHidden: true,
        );
        expect(
          withHidden.shown.where((s) => s.entries.length == 3 && !s.finished),
          isEmpty,
        );
      },
    );
  });
}
