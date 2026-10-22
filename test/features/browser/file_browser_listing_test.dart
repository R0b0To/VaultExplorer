import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/file_browser_listing.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';

RawEntry _file(String name, {int size = 0, int modified = 0}) => RawEntry(
  name: name,
  isDir: false,
  sizeBytes: size,
  modifiedSecs: modified,
);

RawEntry _dir(String name) =>
    RawEntry(name: name, isDir: true, sizeBytes: 0, modifiedSecs: 0);

RawEntry _placeholder(String name, {int size = 0}) => RawEntry(
  name: name,
  isDir: false,
  sizeBytes: size,
  modifiedSecs: 0,
  isPlaceholder: true,
);

BrowserListingInputs _inputs(
  List<RawEntry> items, {
  List<RawEntry> placeholders = const [],
  Set<String> pendingDeletedNames = const {},
  String query = '',
  bool searchActive = false,
  bool deepSearch = false,
  List<RawEntry> deepSearchResults = const [],
  bool showHidden = false,
  String? typeFilter,
  String currentDirPath = '',
  Set<String> pinnedPaths = const {},
  SortBy sortBy = SortBy.name,
  bool sortAscending = true,
}) => BrowserListingInputs(
  items: items,
  placeholders: placeholders,
  pendingDeletedNames: pendingDeletedNames,
  query: query,
  searchActive: searchActive,
  deepSearch: deepSearch,
  deepSearchResults: deepSearchResults,
  showHidden: showHidden,
  typeFilter: typeFilter,
  currentDirPath: currentDirPath,
  pinnedPaths: pinnedPaths,
  sortBy: sortBy,
  sortAscending: sortAscending,
);

List<String> _names(BrowserListing listing) =>
    listing.items.map((e) => e.name).toList();

void main() {
  group('ordering', () {
    test('folders come before files, then by name', () {
      final listing = buildBrowserListing(
        _inputs([_file('b.txt'), _dir('zeta'), _file('a.txt'), _dir('alpha')]),
      );
      expect(_names(listing), ['alpha', 'zeta', 'a.txt', 'b.txt']);
      expect(listing.dirCount, 2);
      expect(listing.fileCount, 2);
    });

    test('pinned entries lead, even ahead of folders', () {
      final listing = buildBrowserListing(
        _inputs(
          [_dir('dirB'), _file('a.txt'), _file('zeta.txt'), _dir('dirA')],
          pinnedPaths: {'zeta.txt'},
        ),
      );
      expect(_names(listing), ['zeta.txt', 'dirA', 'dirB', 'a.txt']);
    });

    test('pinned paths are relative to the directory being shown', () {
      final listing = buildBrowserListing(
        _inputs(
          [_file('a.txt'), _file('z.txt')],
          currentDirPath: 'docs',
          pinnedPaths: {'docs/z.txt'},
        ),
      );
      expect(_names(listing), ['z.txt', 'a.txt']);
    });

    test('the chosen sort field and direction apply within each group', () {
      final items = [
        _file('small.txt', size: 1),
        _file('big.txt', size: 100),
        _file('mid.txt', size: 10),
      ];
      expect(
        _names(buildBrowserListing(_inputs(items, sortBy: SortBy.size))),
        ['small.txt', 'mid.txt', 'big.txt'],
      );
      expect(
        _names(
          buildBrowserListing(
            _inputs(items, sortBy: SortBy.size, sortAscending: false),
          ),
        ),
        ['big.txt', 'mid.txt', 'small.txt'],
      );
    });
  });

  group('visibility', () {
    test('hidden entries stay out unless asked for', () {
      final items = [_file('.secret'), _file('open.txt')];
      expect(_names(buildBrowserListing(_inputs(items))), ['open.txt']);
      expect(_names(buildBrowserListing(_inputs(items, showHidden: true))), [
        '.secret',
        'open.txt',
      ]);
    });

    test('a type filter hides folders and non-matching files', () {
      final listing = buildBrowserListing(
        _inputs([_dir('photos'), _file('a.png'), _file('b.txt')],
            typeFilter: 'image'),
      );
      expect(_names(listing), ['a.png']);
    });

    test('pending deletes disappear from the listing', () {
      final listing = buildBrowserListing(
        _inputs(
          [_file('keep.txt'), _file('gone.txt')],
          pendingDeletedNames: {'gone.txt'},
        ),
      );
      expect(_names(listing), ['keep.txt']);
    });

    test('a placeholder is added unless a same-named entry already exists', () {
      final listing = buildBrowserListing(
        _inputs(
          [_file('a.txt')],
          placeholders: [_placeholder('A.TXT'), _placeholder('b.txt')],
        ),
      );
      expect(_names(listing), ['a.txt', 'b.txt']);
    });
  });

  group('search', () {
    test('a name search filters the directory case-insensitively', () {
      final listing = buildBrowserListing(
        _inputs(
          [_file('Report.pdf'), _file('notes.txt'), _dir('reports')],
          query: 'rep',
          searchActive: true,
        ),
      );
      expect(_names(listing), ['reports', 'Report.pdf']);
    });

    test('scan results add content-only matches without duplicating names', () {
      final listing = buildBrowserListing(
        _inputs(
          [_file('report.pdf')],
          query: 'rep',
          searchActive: true,
          deepSearchResults: [_file('REPORT.pdf'), _file('login.pass')],
        ),
      );
      expect(_names(listing), ['login.pass', 'report.pdf']);
    });

    test('deep search uses the scan results as they are', () {
      final listing = buildBrowserListing(
        _inputs(
          [_file('local.txt')],
          query: 'zzz',
          searchActive: true,
          deepSearch: true,
          deepSearchResults: [_file('sub/found.txt'), _file('.hidden')],
        ),
      );
      expect(_names(listing), ['sub/found.txt']);
    });

    test('an empty query shows the whole directory even while searching', () {
      final listing = buildBrowserListing(
        _inputs([_file('a.txt'), _file('b.txt')], searchActive: true),
      );
      expect(_names(listing), ['a.txt', 'b.txt']);
    });
  });

  group('BrowserListingCache', () {
    test('returns the same listing while nothing relevant changed', () {
      final cache = BrowserListingCache();
      final items = [_file('a.txt'), _file('b.txt')];
      final first = cache.resolve(_inputs(items, pinnedPaths: {'a.txt'}));
      // Equal content in fresh collections is still the same listing.
      final second = cache.resolve(_inputs(items, pinnedPaths: {'a.txt'}));
      expect(identical(first, second), isTrue);
    });

    test('notices one pinned path being swapped for another', () {
      final cache = BrowserListingCache();
      final items = [_file('a.txt'), _file('b.txt')];
      final first = cache.resolve(_inputs(items, pinnedPaths: {'a.txt'}));
      expect(_names(first), ['a.txt', 'b.txt']);

      final second = cache.resolve(_inputs(items, pinnedPaths: {'b.txt'}));
      expect(identical(first, second), isFalse);
      expect(_names(second), ['b.txt', 'a.txt']);
    });

    test('notices one placeholder being swapped for another', () {
      final cache = BrowserListingCache();
      final items = [_file('a.txt')];
      final first = cache.resolve(
        _inputs(items, placeholders: [_placeholder('x.txt')]),
      );
      final second = cache.resolve(
        _inputs(items, placeholders: [_placeholder('y.txt')]),
      );
      expect(_names(first), ['a.txt', 'x.txt']);
      expect(_names(second), ['a.txt', 'y.txt']);
    });

    test('a placeholder\'s progress does not defeat the cache', () {
      final cache = BrowserListingCache();
      final items = [_file('a.txt')];
      final first = cache.resolve(
        _inputs(items, placeholders: [_placeholder('x.txt', size: 10)]),
      );
      final second = cache.resolve(
        _inputs(items, placeholders: [_placeholder('x.txt', size: 20)]),
      );
      expect(identical(first, second), isTrue);
    });

    test('a replaced directory listing is recomputed', () {
      final cache = BrowserListingCache();
      final first = cache.resolve(_inputs([_file('a.txt')]));
      final second = cache.resolve(_inputs([_file('a.txt')]));
      expect(identical(first, second), isFalse);
    });

    test('sort, filter and search changes are recomputed', () {
      final cache = BrowserListingCache();
      final items = [_file('a.txt'), _file('b.png')];
      final base = cache.resolve(_inputs(items));
      expect(
        identical(cache.resolve(_inputs(items, sortAscending: false)), base),
        isFalse,
      );
      expect(
        _names(cache.resolve(_inputs(items, typeFilter: 'image'))),
        ['b.png'],
      );
      expect(
        _names(
          cache.resolve(_inputs(items, query: 'a.', searchActive: true)),
        ),
        ['a.txt'],
      );
    });
  });
}
