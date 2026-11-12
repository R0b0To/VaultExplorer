import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/models/category_source.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/browser/services/category_aggregate_scan.dart';
import 'package:vaultexplorer/features/browser/services/category_listing.dart';
import 'package:vaultexplorer/features/browser/services/category_scan.dart';

String _file(String name, [int size = 10, int modified = 100]) =>
    'F|$size|$modified|$name';
String _dir(String name) => 'D|0|0|$name';

/// A map standing in for a disk: folder path -> its entries.
CategoryDirectoryLister _disk(
  Map<String, List<String>> fs, {
  Set<String> throwOn = const {},
  List<String>? log,
}) => (dir) async {
  log?.add(dir);
  if (throwOn.contains(dir)) throw StateError('unreadable');
  return fs[dir];
};

bool _isImage(String name) => name.endsWith('.jpg') || name.endsWith('.png');
bool _isHidden(String name) => name.startsWith('.');

final _phone = CategorySource(
  volId: -1,
  type: CategorySourceType.device,
  label: 'Phone',
  dedupeRoot: '/storage/0',
);
const _vaultA = CategorySource(
  volId: 7,
  type: CategorySourceType.vault,
  label: 'Vault A',
);

final _phoneFs = {
  '': [
    _dir('DCIM'),
    _dir('Docs'),
    _dir('.secret'),
    _file('top.jpg'),
    _file('a.txt'),
  ],
  'DCIM': [_dir('Camera'), _file('x.png')],
  'DCIM/Camera': [_file('1.jpg'), _file('2.jpg'), _file('n.txt')],
  'Docs': [_file('d.txt')],
  '.secret': [_file('h.jpg')],
};
final _vaultFs = {
  '': [_dir('DCIM'), _file('top.jpg')],
  'DCIM': [_dir('Camera')],
  'DCIM/Camera': [_file('1.jpg')],
};

CategoryScanner _scanner(
  Map<String, List<String>> fs, {
  bool showHidden = false,
  int? maxResults,
  int? maxFolders,
  int? maxDepth,
  bool Function(String)? skip,
  Set<String> throwOn = const {},
  List<String>? log,
  CategoryDirectoryLister? lister,
}) => CategoryScanner(
  listDirectory: lister ?? _disk(fs, throwOn: throwOn, log: log),
  matches: _isImage,
  isHidden: _isHidden,
  showHidden: showHidden,
  skipDirectory: skip,
  maxResults: maxResults ?? categoryScanMaxResults,
  maxFolders: maxFolders ?? categoryScanMaxFolders,
  maxDepth: maxDepth ?? categoryScanMaxDepth,
);

CategoryAggregateScanner _aggregate(List<CategoryScanTarget> targets) =>
    CategoryAggregateScanner(
      targets: targets,
      matches: _isImage,
      isHidden: _isHidden,
      showHidden: false,
    );

void main() {
  seedTests();
  group('CategoryScanner', () {
    test(
      'finds matching files by path from the root, skipping hidden folders',
      () async {
        final result = await _scanner(_phoneFs)
            .scan(token: CancellationToken());
        expect(result.entries.map((e) => e.name).toSet(), {
          'top.jpg',
          'DCIM/x.png',
          'DCIM/Camera/1.jpg',
          'DCIM/Camera/2.jpg',
        });
        expect(result.finished, isTrue);
        expect(result.limitReached, isFalse);
      },
    );

    test('records only folders that lead to a match', () async {
      final result = await _scanner(_phoneFs).scan(token: CancellationToken());
      expect(result.folderPaths, {'DCIM', 'DCIM/Camera'});
    });

    test('showHidden includes hidden folders', () async {
      final result = await _scanner(
        _phoneFs,
        showHidden: true,
      ).scan(token: CancellationToken());
      expect(result.entries.any((e) => e.name == '.secret/h.jpg'), isTrue);
    });

    test('a folder that throws is skipped and the scan carries on', () async {
      final result = await _scanner(
        _phoneFs,
        throwOn: {'DCIM'},
      ).scan(token: CancellationToken());
      expect(result.entries.map((e) => e.name), ['top.jpg']);
    });

    test('a folder that cannot be listed is skipped', () async {
      final fs = {..._phoneFs}..remove('DCIM');
      final result = await _scanner(fs).scan(token: CancellationToken());
      expect(result.entries.map((e) => e.name), ['top.jpg']);
    });

    test('skipDirectory keeps a folder from being listed', () async {
      final log = <String>[];
      await _scanner(
        _phoneFs,
        log: log,
        skip: (p) => p == 'DCIM',
      ).scan(token: CancellationToken());
      expect(log, isNot(contains('DCIM')));
    });

    test('a scan cancelled up front lists nothing and is unfinished', () async {
      final token = CancellationToken()..cancel();
      final result = await _scanner(_phoneFs).scan(token: token);
      expect(result.finished, isFalse);
      expect(result.entries, isEmpty);
    });

    test('cancelling mid-scan gives an unfinished snapshot', () async {
      final token = CancellationToken();
      var listed = 0;
      final result = await _scanner(
        _phoneFs,
        lister: (dir) async {
          listed++;
          if (listed == 2) token.cancel();
          return _phoneFs[dir];
        },
      ).scan(token: token);
      expect(result.finished, isFalse);
    });

    test('the result limit stops the scan and is reported', () async {
      final result = await _scanner(
        _phoneFs,
        maxResults: 2,
      ).scan(token: CancellationToken());
      expect(result.entries, hasLength(2));
      expect(result.limitReached, isTrue);
    });

    test('the folder limit is reported', () async {
      final result = await _scanner(
        _phoneFs,
        maxFolders: 1,
      ).scan(token: CancellationToken());
      expect(result.limitReached, isTrue);
    });

    test('the depth guard stops descending', () async {
      final result = await _scanner(
        _phoneFs,
        maxDepth: 1,
      ).scan(token: CancellationToken());
      expect(
        result.entries.any((e) => e.name.startsWith('DCIM/Camera')),
        isFalse,
      );
    });

    test('delivers results incrementally', () async {
      final counts = <int>[];
      await _scanner(_phoneFs).scan(
        token: CancellationToken(),
        progressInterval: Duration.zero,
        onProgress: (snapshot) => counts.add(snapshot.entries.length),
      );
      expect(counts.toSet().length, greaterThan(1));
    });
  });

  group('CategoryAggregateScanner', () {
    test('scans every source and keeps same-named files apart', () async {
      final result = await _aggregate([
        CategoryScanTarget(source: _phone, listDirectory: _disk(_phoneFs)),
        CategoryScanTarget(source: _vaultA, listDirectory: _disk(_vaultFs)),
      ]).scan(token: CancellationToken());

      expect(result.entries.where((e) => e.sourceVolId == -1), hasLength(4));
      expect(result.entries.where((e) => e.sourceVolId == 7), hasLength(2));
      final local = result.entries.firstWhere(
        (e) => e.sourceVolId == -1 && e.path == 'top.jpg',
      );
      final vault = result.entries.firstWhere(
        (e) => e.sourceVolId == 7 && e.path == 'top.jpg',
      );
      // Same name, size and date, different source: not the same entry.
      expect(local == vault, isFalse);
      expect({local, vault}, hasLength(2));
      expect(result.contributingSources, {-1, 7});
      expect(result.finished, isTrue);
    });

    test('lists a file reachable from two raw sources once', () async {
      const overlap = CategorySource(
        volId: -1000,
        type: CategorySourceType.storageLocation,
        label: 'Pictures',
        dedupeRoot: '/storage/0/DCIM',
      );
      final result = await _aggregate([
        CategoryScanTarget(source: _phone, listDirectory: _disk(_phoneFs)),
        CategoryScanTarget(
          source: overlap,
          listDirectory: _disk({
            '': [_dir('Camera'), _file('x.png')],
            'Camera': [_file('1.jpg'), _file('2.jpg')],
          }),
        ),
      ]).scan(token: CancellationToken());
      expect(result.entries, hasLength(4));
      expect(result.entries.every((e) => e.sourceVolId == -1), isTrue);
    });

    test('an unreadable source does not stop the others', () async {
      final result = await _aggregate([
        CategoryScanTarget(
          source: _phone,
          listDirectory: (dir) async => throw StateError('gone'),
        ),
        CategoryScanTarget(source: _vaultA, listDirectory: _disk(_vaultFs)),
      ]).scan(token: CancellationToken());
      expect(result.entries.every((e) => e.sourceVolId == 7), isTrue);
      expect(result.entries, hasLength(2));
    });

    test('a locked vault can be dropped entirely', () async {
      final result = await _aggregate([
        CategoryScanTarget(source: _vaultA, listDirectory: _disk(_vaultFs)),
      ]).scan(token: CancellationToken());
      final without = result.withoutSource(7);
      expect(without.entries, isEmpty);
      expect(without.folderPathsBySource.containsKey(7), isFalse);
    });

    test('publishes progress while scanning', () async {
      final counts = <int>[];
      await _aggregate([
        CategoryScanTarget(source: _phone, listDirectory: _disk(_phoneFs)),
        CategoryScanTarget(source: _vaultA, listDirectory: _disk(_vaultFs)),
      ]).scan(
        token: CancellationToken(),
        progressInterval: Duration.zero,
        onProgress: (snapshot) => counts.add(snapshot.entries.length),
      );
      expect(counts, isNotEmpty);
    });

    test('a cancelled scan is unfinished and empty', () async {
      final token = CancellationToken()..cancel();
      final result = await _aggregate([
        CategoryScanTarget(source: _phone, listDirectory: _disk(_phoneFs)),
      ]).scan(token: token);
      expect(result.finished, isFalse);
      expect(result.entries, isEmpty);
    });

    test('removing deleted files prunes folders that lead nowhere', () async {
      final result = await _aggregate([
        CategoryScanTarget(source: _phone, listDirectory: _disk(_phoneFs)),
      ]).scan(token: CancellationToken());
      final trimmed = result.withoutPaths({
        (-1, 'DCIM/Camera/1.jpg'),
        (-1, 'DCIM/Camera/2.jpg'),
      });
      expect(trimmed.entries, hasLength(2));
      expect(trimmed.folderPathsBySource[-1], {'DCIM'});
      expect(identical(result.withoutPaths({}), result), isTrue);
    });
  });

  group('category listings', () {
    late CategoryAggregateSnapshot both;
    final labels = {-1: 'Phone', 7: 'Vault A'};

    setUp(() async {
      both = await _aggregate([
        CategoryScanTarget(source: _phone, listDirectory: _disk(_phoneFs)),
        CategoryScanTarget(source: _vaultA, listDirectory: _disk(_vaultFs)),
      ]).scan(token: CancellationToken());
    });

    test('flat listing holds every match, and a query narrows it', () {
      expect(flatCategoryListing(both), hasLength(6));
      expect(flatCategoryListing(both, query: 'camera'), hasLength(3));
      expect(flatCategoryListing(both, query: 'TOP'), hasLength(2));
    });

    test('flat listing scoped to a directory narrows to that subfolder', () {
      final camera = flatCategoryListing(
        both,
        location: const CategoryLocation(-1, 'DCIM/Camera'),
      );
      expect(camera, hasLength(2));
      expect(camera.map((e) => e.name), ['1.jpg', '2.jpg']);
      expect(camera.every((e) => e.sourceVolId == -1), isTrue);

      final dcim = flatCategoryListing(
        both,
        location: const CategoryLocation(-1, 'DCIM'),
      );
      expect(dcim, hasLength(3));
      expect(dcim.map((e) => e.name), ['x.png', 'Camera/1.jpg', 'Camera/2.jpg']);
    });

    test('with several sources the folder view starts at the sources', () {
      final location = effectiveCategoryLocation(both, CategoryLocation.top);
      expect(location.isTop, isTrue);
      final top = folderCategoryListing(
        both,
        location: location,
        labels: labels,
      );
      expect(top, hasLength(2));
      expect(top.every((e) => e.isDir && e.isSourceRoot), isTrue);
      expect(parentCategoryLocation(both, CategoryLocation.top), isNull);
      expect(
        parentCategoryLocation(both, const CategoryLocation(7, '')),
        CategoryLocation.top,
      );
    });

    test(
      'a source root shows only folders leading to matches, plus its files',
      () {
        final listing = folderCategoryListing(
          both,
          location: const CategoryLocation(-1, ''),
          labels: labels,
        );
        expect(listing.where((e) => e.isDir).map((e) => e.name), ['DCIM']);
        expect(listing.any((e) => e.name == 'top.jpg' && !e.isDir), isTrue);
        expect(listing.any((e) => e.name == 'Docs'), isFalse);
      },
    );

    test(
      'files in a folder are named by bare name but keep their full path',
      () {
        final listing = folderCategoryListing(
          both,
          location: const CategoryLocation(-1, 'DCIM/Camera'),
          labels: labels,
        );
        expect(listing.map((e) => e.name).toSet(), {'1.jpg', '2.jpg'});
        expect(listing.every((e) => e.path.startsWith('DCIM/Camera/')), isTrue);
        expect(
          parentCategoryLocation(
            both,
            const CategoryLocation(-1, 'DCIM/Camera'),
          ),
          const CategoryLocation(-1, 'DCIM'),
        );
      },
    );

    test('with one contributing source the source level is skipped', () {
      final one = both.withoutSource(7);
      expect(
        effectiveCategoryLocation(one, CategoryLocation.top),
        const CategoryLocation(-1, ''),
      );
      expect(
        parentCategoryLocation(one, const CategoryLocation(-1, '')),
        isNull,
      );
    });
  });

  group('CategorySourceFilter', () {
    test('selects the right sources', () {
      expect(_phone.isIncludedBy(CategorySourceFilter.all), isTrue);
      expect(_vaultA.isIncludedBy(CategorySourceFilter.all), isTrue);
      expect(_phone.isIncludedBy(CategorySourceFilter.device), isTrue);
      expect(_vaultA.isIncludedBy(CategorySourceFilter.device), isFalse);
      expect(_vaultA.isIncludedBy(CategorySourceFilter.vaults), isTrue);
      expect(_phone.isIncludedBy(CategorySourceFilter.vaults), isFalse);
      expect(_vaultA.isIncludedBy(const CategorySourceFilter.vault(7)), isTrue);
      expect(
        _vaultA.isIncludedBy(const CategorySourceFilter.vault(8)),
        isFalse,
      );
      expect(_phone.isIncludedBy(const CategorySourceFilter.vault(7)), isFalse);
    });

    test('survives a round trip through its storage key', () {
      for (final key in ['all', 'device', 'vaults', 'vault:12']) {
        expect(CategorySourceFilter.fromStorageKey(key).storageKey, key);
      }
      expect(
        CategorySourceFilter.fromStorageKey('junk'),
        CategorySourceFilter.all,
      );
      expect(
        CategorySourceFilter.fromStorageKey(null),
        CategorySourceFilter.all,
      );
    });
  });

  group('FileCategory', () {
    test('orderedFrom keeps the given order and fills in what is missing', () {
      expect(
        FileCategory.orderedFrom(['audio', 'bogus', 'audio'])
            .map((c) => c.name),
        ['audio', 'images', 'videos', 'documents'],
      );
      expect(FileCategory.orderedFrom(const []), hasLength(4));
    });

    test('each category maps onto a type-filter key', () {
      expect(FileCategory.images.filterKey, 'image');
      expect(FileCategory.fromFilterKey('document'), FileCategory.documents);
    });
  });
}

/// Tests added with the vault category index: a stand-in list for a source
/// until its own scan finishes.
void seedTests() {
  group('seeded sources', () {
    RawEntry seedEntry(String path) => RawEntry(
      name: path,
      isDir: false,
      sizeBytes: 5,
      modifiedSecs: 1,
      lowercaseName: path.toLowerCase(),
      extension: path.split('.').last,
    );

    test('shows the seed at once and swaps it for the scan result', () async {
      final seen = <List<String>>[];
      final result =
          await _aggregate([
            CategoryScanTarget(
              source: _vaultA,
              listDirectory: _disk({
                '': [_file('fresh.jpg')],
              }),
              seed: [
                seedEntry('old1.jpg'),
                seedEntry('Trips/old2.jpg'),
                seedEntry('old3.jpg'),
              ],
            ),
          ]).scan(
            token: CancellationToken(),
            progressInterval: Duration.zero,
            onProgress: (s) => seen.add([for (final e in s.entries) e.path]),
          );

      // Every update before the end still shows the seed, not the scan's
      // partial results.
      expect(seen, isNotEmpty);
      expect(seen.every((paths) => paths.length == 3), isTrue);
      expect(seen.first, contains('Trips/old2.jpg'));
      // The final result is the scan, with the stale names gone.
      expect(result.entries.map((e) => e.path), ['fresh.jpg']);
      expect(result.folderPathsBySource[7], isNull);
    });

    test('the seed gives the folder view its folders straight away', () async {
      CategoryAggregateSnapshot? first;
      await _aggregate([
        CategoryScanTarget(
          source: _vaultA,
          listDirectory: _disk({'': <String>[]}),
          seed: [seedEntry('Trips/2024/a.jpg')],
        ),
      ]).scan(
        token: CancellationToken(),
        progressInterval: Duration.zero,
        onProgress: (s) => first ??= s,
      );
      expect(first!.folderPathsBySource[7], {'Trips', 'Trips/2024'});
    });

    test('a source without a seed streams as before', () async {
      final counts = <int>[];
      await _aggregate([
        CategoryScanTarget(source: _phone, listDirectory: _disk(_phoneFs)),
      ]).scan(
        token: CancellationToken(),
        progressInterval: Duration.zero,
        onProgress: (s) => counts.add(s.entries.length),
      );
      expect(counts.toSet().length, greaterThan(1));
    });
  });
}
