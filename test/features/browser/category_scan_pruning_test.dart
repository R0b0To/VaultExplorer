import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/models/category_source.dart';
import 'package:vaultexplorer/features/browser/services/category_aggregate_scan.dart';
import 'package:vaultexplorer/features/browser/services/category_scan.dart';
import 'package:vaultexplorer/features/browser/services/category_walk_policy.dart';

String _file(String name, [int size = 10, int modified = 100]) =>
    'F|$size|$modified|$name';
String _dir(String name) => 'D|0|0|$name';

CategoryDirectoryLister _disk(
  Map<String, List<String>> fs, {
  List<String>? log,
}) => (dir) async {
  log?.add(dir);
  return fs[dir];
};

bool _isImage(String name) => name.endsWith('.jpg') || name.endsWith('.png');
bool _isHidden(String name) => name.startsWith('.');

CategoryScanner _scanner(
  Map<String, List<String>> fs, {
  bool respectNoMedia = false,
  bool showHidden = false,
  bool Function(String)? skip,
  List<String>? log,
}) => CategoryScanner(
  listDirectory: _disk(fs, log: log),
  matches: _isImage,
  isHidden: _isHidden,
  showHidden: showHidden,
  skipDirectory: skip,
  respectNoMedia: respectNoMedia,
);

Future<CategoryScanSnapshot> _scan(CategoryScanner s) =>
    s.scan(token: CancellationToken());

final _phone = CategorySource(
  volId: -1,
  type: CategorySourceType.device,
  label: 'Phone',
  dedupeRoot: '/storage/0',
);

void main() {
  group('category walk policy', () {
    test('pruned folder names match at any depth, ignoring case', () {
      expect(isPrunedCategoryFolder('node_modules'), isTrue);
      expect(isPrunedCategoryFolder('Pictures/App/Cache'), isTrue);
      expect(isPrunedCategoryFolder('a/b/LOST.DIR'), isTrue);
      expect(isPrunedCategoryFolder('Pictures'), isFalse);
      expect(isPrunedCategoryFolder('Pictures/Caching'), isFalse);
    });

    test('Android private folders are skipped only at their exact path', () {
      expect(skipPrivateAndroidFolders('Android/data'), isTrue);
      expect(skipPrivateAndroidFolders('Android/obb'), isTrue);
      expect(skipPrivateAndroidFolders('Android/media'), isFalse);
      expect(skipPrivateAndroidFolders('Pictures/Android/data'), isFalse);
    });

    test('device rule combines both', () {
      expect(skipDeviceCategoryFolder('Android/data'), isTrue);
      expect(skipDeviceCategoryFolder('x/cache'), isTrue);
      expect(skipDeviceCategoryFolder('DCIM/Camera'), isFalse);
    });

    test('a file path is skipped when any folder above it is', () {
      final verdicts = <String, bool>{};
      expect(
        hasSkippedAncestor(
          'Android/data/x/a.jpg',
          skipDeviceCategoryFolder,
          verdicts,
        ),
        isTrue,
      );
      expect(
        hasSkippedAncestor(
          'DCIM/Camera/a.jpg',
          skipDeviceCategoryFolder,
          verdicts,
        ),
        isFalse,
      );
      // A file at the root has no folder above it.
      expect(
        hasSkippedAncestor('a.jpg', skipDeviceCategoryFolder, verdicts),
        isFalse,
      );
    });

    test('each folder is asked about once however many files it holds', () {
      var asked = 0;
      final verdicts = <String, bool>{};
      bool skip(String dir) {
        asked++;
        return false;
      }

      for (var i = 0; i < 100; i++) {
        hasSkippedAncestor('DCIM/Camera/$i.jpg', skip, verdicts);
      }
      expect(asked, 2); // 'DCIM' and 'DCIM/Camera'
    });
  });

  group('respectNoMedia', () {
    final fs = {
      '': [_dir('DCIM'), _dir('Hidden'), _file('top.jpg')],
      'DCIM': [_file('a.jpg')],
      'Hidden': [_file('.nomedia'), _file('b.jpg'), _dir('Deep')],
      'Hidden/Deep': [_file('c.jpg')],
    };

    test(
      'is off by default: a .nomedia folder is walked like any other',
      () async {
        final r = await _scan(_scanner(fs));
        expect(r.entries.map((e) => e.name).toSet(), {
          'top.jpg',
          'DCIM/a.jpg',
          'Hidden/b.jpg',
          'Hidden/Deep/c.jpg',
        });
      },
    );

    test('skips the folder and everything beneath it', () async {
      final log = <String>[];
      final r = await _scan(_scanner(fs, respectNoMedia: true, log: log));
      expect(r.entries.map((e) => e.name).toSet(), {'top.jpg', 'DCIM/a.jpg'});
      // The marked folder was listed (that is how the marker was found) but
      // its sub-folder never was.
      expect(log, contains('Hidden'));
      expect(log, isNot(contains('Hidden/Deep')));
      expect(r.folderPaths, isNot(contains('Hidden')));
    });

    test('is ignored while hidden files are shown', () async {
      final r = await _scan(
        _scanner(fs, respectNoMedia: true, showHidden: true),
      );
      expect(r.entries.map((e) => e.name), contains('Hidden/Deep/c.jpg'));
    });

    test('never prunes the scan root itself', () async {
      final rootMarked = {
        '': [_file('.nomedia'), _file('top.jpg'), _dir('Sub')],
        'Sub': [_file('s.jpg')],
      };
      final r = await _scan(_scanner(rootMarked, respectNoMedia: true));
      expect(r.entries.map((e) => e.name).toSet(), {'top.jpg', 'Sub/s.jpg'});
    });

    test('a folder named .nomedia is not a marker', () async {
      final r = await _scan(
        _scanner(
          {
            '': [_dir('A')],
            'A': [_dir('.nomedia'), _file('a.jpg')],
            'A/.nomedia': [_file('x.jpg')],
          },
          respectNoMedia: true,
          showHidden: false,
        ),
      );
      expect(r.entries.map((e) => e.name), ['A/a.jpg']);
    });
  });

  group('pruning cuts the number of folders listed', () {
    test('a tree of junk folders is never entered', () async {
      final fs = <String, List<String>>{
        '': [_dir('DCIM'), _dir('node_modules'), _dir('Android')],
        'DCIM': [_file('a.jpg')],
        'Android': [_dir('data'), _dir('media')],
        'Android/media': [_file('m.jpg')],
      };
      for (var i = 0; i < 500; i++) {
        (fs['node_modules'] ??= []).add(_dir('pkg$i'));
        fs['node_modules/pkg$i'] = [_file('i.jpg')];
        (fs['Android/data'] ??= []).add(_dir('app$i'));
        fs['Android/data/app$i'] = [_file('i.jpg')];
      }
      final log = <String>[];
      final r = await _scan(
        _scanner(fs, skip: skipDeviceCategoryFolder, log: log),
      );
      expect(r.entries.map((e) => e.name).toSet(), {
        'DCIM/a.jpg',
        'Android/media/m.jpg',
      });
      // Root, DCIM, Android, Android/media. Not one of the 1000 junk folders.
      expect(log.length, 4);
    });
  });

  group('indexLookup', () {
    final fs = {
      '': [_dir('DCIM'), _file('top.jpg')],
      'DCIM': [_file('a.jpg')],
    };

    CategoryAggregateScanner aggregate(
      CategoryScanTarget target, {
      List<String>? log,
    }) => CategoryAggregateScanner(
      targets: [target],
      matches: _isImage,
      isHidden: _isHidden,
      showHidden: false,
    );

    CategoryScanTarget target({
      CategoryIndexLookup? lookup,
      List<String>? log,
      List<RawEntry>? seed,
    }) => CategoryScanTarget(
      source: _phone,
      listDirectory: _disk(fs, log: log),
      indexLookup: lookup,
      seed: seed,
    );

    test('a hit replaces the walk: nothing is listed', () async {
      final log = <String>[];
      final result = await aggregate(
        target(
          log: log,
          lookup: () async => CategoryIndexHit([
            const RawEntry(
              name: 'x/y.jpg',
              isDir: false,
              sizeBytes: 5,
              modifiedSecs: 9,
            ),
          ]),
        ),
      ).scan(token: CancellationToken());
      expect(log, isEmpty);
      expect(result.entries.map((e) => e.path), ['x/y.jpg']);
      expect(result.folderPathsBySource[-1], {'x'});
      expect(result.foldersChecked, 0);
      expect(result.finished, isTrue);
      expect(result.limitReached, isFalse);
    });

    test('a hit can flag that the list was cut', () async {
      final result = await aggregate(
        target(
          lookup: () async => CategoryIndexHit([
            const RawEntry(
              name: 'a.jpg',
              isDir: false,
              sizeBytes: 1,
              modifiedSecs: 1,
            ),
          ], limitReached: true),
        ),
      ).scan(token: CancellationToken());
      expect(result.limitReached, isTrue);
    });

    test('null falls back to the walk', () async {
      final log = <String>[];
      final result = await aggregate(
        target(log: log, lookup: () async => null),
      ).scan(token: CancellationToken());
      expect(log, isNotEmpty);
      expect(result.entries.map((e) => e.path).toSet(), {
        'top.jpg',
        'DCIM/a.jpg',
      });
    });

    test('a lookup that throws falls back to the walk', () async {
      final log = <String>[];
      final result = await aggregate(
        target(log: log, lookup: () async => throw StateError('no index')),
      ).scan(token: CancellationToken());
      expect(log, isNotEmpty);
      expect(result.entries, hasLength(2));
      expect(result.failedSources, isEmpty);
    });

    test(
      'a hit takes the place of the seed, and the seed shows first',
      () async {
        final snapshots = <CategoryAggregateSnapshot>[];
        final result = await aggregate(
          target(
            seed: const [
              RawEntry(
                name: 'old.jpg',
                isDir: false,
                sizeBytes: 1,
                modifiedSecs: 1,
              ),
            ],
            lookup: () async => CategoryIndexHit([
              const RawEntry(
                name: 'new.jpg',
                isDir: false,
                sizeBytes: 2,
                modifiedSecs: 2,
              ),
            ]),
          ),
        ).scan(token: CancellationToken(), onProgress: snapshots.add);
        expect(snapshots.first.entries.map((e) => e.path), ['old.jpg']);
        expect(snapshots.last.entries.map((e) => e.path), ['new.jpg']);
        expect(result.entries.map((e) => e.path), ['new.jpg']);
      },
    );

    test(
      'with a seed and a failed lookup the walk still replaces the seed',
      () async {
        final result = await aggregate(
          target(
            seed: const [
              RawEntry(
                name: 'old.jpg',
                isDir: false,
                sizeBytes: 1,
                modifiedSecs: 1,
              ),
            ],
            lookup: () async => null,
          ),
        ).scan(token: CancellationToken());
        expect(result.entries.map((e) => e.path).toSet(), {
          'top.jpg',
          'DCIM/a.jpg',
        });
      },
    );

    test('a cancelled scan does not publish the hit', () async {
      final token = CancellationToken();
      final result = await aggregate(
        target(
          lookup: () async {
            token.cancel();
            return CategoryIndexHit([
              const RawEntry(
                name: 'a.jpg',
                isDir: false,
                sizeBytes: 1,
                modifiedSecs: 1,
              ),
            ]);
          },
        ),
      ).scan(token: token);
      expect(result.finished, isFalse);
      expect(result.entries, isEmpty);
    });
  });
}
