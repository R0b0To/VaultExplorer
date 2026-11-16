import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/directory_listing_cache.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';

List<RawEntry> _entries(int n, [String prefix = 'f']) => [
  for (var i = 0; i < n; i++)
    RawEntry(name: '$prefix$i', isDir: false, sizeBytes: i, modifiedSecs: 1),
];

void main() {
  group('DirectoryListingCache', () {
    test('returns what was stored, as the same instance', () {
      final cache = DirectoryListingCache();
      final list = _entries(3);
      cache.put('a', list);
      expect(identical(cache.get('a'), list), isTrue);
      expect(cache.get('missing'), isNull);
    });

    test('put replaces an earlier listing and keeps the entry count right', () {
      final cache = DirectoryListingCache();
      cache.put('a', _entries(5));
      cache.put('a', _entries(2));
      expect(cache.length, 1);
      expect(cache.totalEntries, 2);
    });

    test('never stores an empty listing, and drops an older one for the path', () {
      final cache = DirectoryListingCache();
      cache.put('a', _entries(3));
      cache.put('a', const <RawEntry>[]);
      expect(cache.get('a'), isNull);
      expect(cache.totalEntries, 0);
    });

    test('evicts the least recently used folder past maxDirectories', () {
      final cache = DirectoryListingCache(maxDirectories: 2);
      cache.put('a', _entries(1));
      cache.put('b', _entries(1));
      cache.get('a'); // a is now more recent than b
      cache.put('c', _entries(1));
      expect(cache.contains('b'), isFalse);
      expect(cache.contains('a'), isTrue);
      expect(cache.contains('c'), isTrue);
    });

    test('evicts oldest folders until the total entry budget fits', () {
      final cache = DirectoryListingCache(maxTotalEntries: 10);
      cache.put('a', _entries(4));
      cache.put('b', _entries(4));
      cache.put('c', _entries(4)); // 12 > 10 -> 'a' goes
      expect(cache.contains('a'), isFalse);
      expect(cache.totalEntries, 8);
    });

    test('a single listing bigger than the whole budget is not kept', () {
      final cache = DirectoryListingCache(maxTotalEntries: 5);
      cache.put('big', _entries(6));
      expect(cache.get('big'), isNull);
      expect(cache.totalEntries, 0);
    });

    test('remove and clear update the totals', () {
      final cache = DirectoryListingCache();
      cache.put('a', _entries(3));
      cache.put('b', _entries(2));
      cache.remove('a');
      expect(cache.totalEntries, 2);
      cache.remove('not-there');
      expect(cache.totalEntries, 2);
      cache.clear();
      expect(cache.length, 0);
      expect(cache.totalEntries, 0);
    });

    test('contains does not change recency', () {
      final cache = DirectoryListingCache(maxDirectories: 2);
      cache.put('a', _entries(1));
      cache.put('b', _entries(1));
      cache.contains('a');
      cache.put('c', _entries(1)); // evicts a (still the oldest)
      expect(cache.contains('a'), isFalse);
    });
  });
}
