import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';

void main() {
  group('basic get/set', () {
    test('a missing key returns null', () {
      final cache = LruCache<String, int>(3);
      expect(cache['missing'], isNull);
      expect(cache.containsKey('missing'), isFalse);
    });

    test('a stored value can be read back', () {
      final cache = LruCache<String, int>(3);
      cache['a'] = 1;
      expect(cache['a'], 1);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.length, 1);
    });

    test('setting an existing key overwrites its value without growing '
        'length', () {
      final cache = LruCache<String, int>(3);
      cache['a'] = 1;
      cache['a'] = 2;
      expect(cache['a'], 2);
      expect(cache.length, 1);
    });

    test('capacity must be positive', () {
      expect(() => LruCache<String, int>(0), throwsA(isA<AssertionError>()));
      expect(() => LruCache<String, int>(-1), throwsA(isA<AssertionError>()));
    });
  });

  group('LRU eviction', () {
    test('inserting beyond capacity evicts the least-recently-used entry',
        () {
      final cache = LruCache<String, int>(2);
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3; // evicts 'a', the least recently touched

      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
      expect(cache.containsKey('c'), isTrue);
      expect(cache.length, 2);
    });

    test('reading a key promotes it, so it is not the next eviction '
        'candidate', () {
      final cache = LruCache<String, int>(2);
      cache['a'] = 1;
      cache['b'] = 2;
      final touched = cache['a']; // touch 'a' — 'b' is now least-recent
      expect(touched, 1);
      cache['c'] = 3; // evicts 'b', not 'a'

      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('c'), isTrue);
    });

    test('overwriting an existing key also promotes it to most-recent',
        () {
      final cache = LruCache<String, int>(2);
      cache['a'] = 1;
      cache['b'] = 2;
      cache['a'] = 10; // re-set, not just read — should still promote
      cache['c'] = 3; // evicts 'b', not 'a'

      expect(cache.containsKey('a'), isTrue);
      expect(cache['a'], 10);
      expect(cache.containsKey('b'), isFalse);
    });
  });

  group('remove / removeWhere / clear', () {
    test('remove deletes a single key', () {
      final cache = LruCache<String, int>(3)
        ..['a'] = 1
        ..['b'] = 2;
      cache.remove('a');
      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
    });

    test('removeWhere deletes every key matching the predicate', () {
      final cache = LruCache<String, int>(5)
        ..['vol1:a'] = 1
        ..['vol1:b'] = 2
        ..['vol2:a'] = 3;
      cache.removeWhere((k) => k.startsWith('vol1:'));

      expect(cache.containsKey('vol1:a'), isFalse);
      expect(cache.containsKey('vol1:b'), isFalse);
      expect(cache.containsKey('vol2:a'), isTrue);
      expect(cache.length, 1);
    });

    test('clear empties the cache', () {
      final cache = LruCache<String, int>(3)
        ..['a'] = 1
        ..['b'] = 2;
      cache.clear();
      expect(cache.length, 0);
      expect(cache.containsKey('a'), isFalse);
    });
  });

  group('resize', () {
    test('growing capacity does not evict anything', () {
      final cache = LruCache<String, int>(2)
        ..['a'] = 1
        ..['b'] = 2;
      cache.resize(5);
      expect(cache.capacity, 5);
      expect(cache.length, 2);
    });

    test('shrinking capacity immediately evicts from the least-recent end',
        () {
      final cache = LruCache<String, int>(3)
        ..['a'] = 1
        ..['b'] = 2
        ..['c'] = 3;
      cache.resize(1);
      expect(cache.capacity, 1);
      expect(cache.length, 1);
      expect(cache.containsKey('c'), isTrue); // most-recently inserted
      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isFalse);
    });

    test('resize also requires a positive capacity', () {
      final cache = LruCache<String, int>(3);
      expect(() => cache.resize(0), throwsA(isA<AssertionError>()));
    });
  });

  group('trimToFraction', () {
    test('trimming 0.5 of 4 entries evicts the 2 least-recently-used, '
        'without changing capacity', () {
      final cache = LruCache<String, int>(10)
        ..['a'] = 1
        ..['b'] = 2
        ..['c'] = 3
        ..['d'] = 4;
      cache.trimToFraction(0.5);

      expect(cache.length, 2);
      expect(cache.capacity, 10); // unchanged, unlike resize
      expect(cache.containsKey('c'), isTrue);
      expect(cache.containsKey('d'), isTrue);
      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isFalse);
    });

    test('trimming 0.0 removes nothing', () {
      final cache = LruCache<String, int>(10)
        ..['a'] = 1
        ..['b'] = 2;
      cache.trimToFraction(0.0);
      expect(cache.length, 2);
    });

    test('trimming 1.0 removes everything', () {
      final cache = LruCache<String, int>(10)
        ..['a'] = 1
        ..['b'] = 2;
      cache.trimToFraction(1.0);
      expect(cache.length, 0);
    });
  });
}
