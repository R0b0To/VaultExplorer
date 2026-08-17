import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/byte_budget_cache.dart';

Uint8List bytesOf(int length) => Uint8List(length);

void main() {
  group('basic get/set', () {
    test('a missing key returns null', () {
      final cache = ByteBudgetCache(1000);
      expect(cache['missing'], isNull);
      expect(cache.containsKey('missing'), isFalse);
    });

    test('a stored value can be read back and counts toward currentBytes',
        () {
      final cache = ByteBudgetCache(1000);
      cache['a'] = bytesOf(100);
      expect(cache['a'], hasLength(100));
      expect(cache.currentBytes, 100);
      expect(cache.length, 1);
    });

    test('overwriting a key adjusts currentBytes by the size delta, not '
        'by double-counting', () {
      final cache = ByteBudgetCache(1000);
      cache['a'] = bytesOf(100);
      cache['a'] = bytesOf(40);
      expect(cache.currentBytes, 40);
      expect(cache.length, 1);
    });

    test('maxTotalBytes must be positive', () {
      expect(() => ByteBudgetCache(0), throwsA(isA<AssertionError>()));
      expect(() => ByteBudgetCache(-1), throwsA(isA<AssertionError>()));
    });

    test('keys exposes the currently-cached keys', () {
      final cache = ByteBudgetCache(1000)
        ..['a'] = bytesOf(10)
        ..['b'] = bytesOf(10);
      expect(cache.keys.toSet(), {'a', 'b'});
    });
  });

  group('a single value larger than the whole budget', () {
    test('is silently dropped rather than evicting everything else', () {
      final cache = ByteBudgetCache(100);
      cache['small'] = bytesOf(50);
      cache['huge'] = bytesOf(200); // > maxTotalBytes

      expect(cache.containsKey('huge'), isFalse);
      expect(cache.containsKey('small'), isTrue);
      expect(cache.currentBytes, 50);
    });
  });

  group('eviction to stay within the byte budget', () {
    test('inserting past the budget evicts the least-recently-used entry '
        'first', () {
      final cache = ByteBudgetCache(100);
      cache['a'] = bytesOf(60);
      cache['b'] = bytesOf(60); // 'a' (60) evicted to fit within 100

      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
      expect(cache.currentBytes, 60);
    });

    test('eviction can remove more than one entry if needed to fit', () {
      final cache = ByteBudgetCache(100);
      cache['a'] = bytesOf(30);
      cache['b'] = bytesOf(30);
      cache['c'] = bytesOf(30);
      cache['d'] = bytesOf(90); // needs to evict a, b, and c to fit

      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('c'), isFalse);
      expect(cache.containsKey('d'), isTrue);
      expect(cache.currentBytes, 90);
    });

    test('reading a value promotes it, protecting it from the next '
        'eviction', () {
      final cache = ByteBudgetCache(100);
      cache['a'] = bytesOf(40);
      cache['b'] = bytesOf(40);
      final touched = cache['a']; // 'b' is now least-recently-used
      expect(touched, isNotNull);
      cache['c'] = bytesOf(40); // evicts 'b', not 'a'

      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('b'), isFalse);
    });
  });

  group('remove / removeWhere / clear', () {
    test('remove deletes the key and decrements currentBytes', () {
      final cache = ByteBudgetCache(1000)
        ..['a'] = bytesOf(30)
        ..['b'] = bytesOf(20);
      cache.remove('a');
      expect(cache.containsKey('a'), isFalse);
      expect(cache.currentBytes, 20);
    });

    test('removeWhere removes every matching key, e.g. one volume\'s '
        'prefix on lock', () {
      final cache = ByteBudgetCache(1000)
        ..['vol1:x'] = bytesOf(10)
        ..['vol1:y'] = bytesOf(10)
        ..['vol2:x'] = bytesOf(10);
      cache.removeWhere((k) => k.startsWith('vol1:'));

      expect(cache.containsKey('vol1:x'), isFalse);
      expect(cache.containsKey('vol1:y'), isFalse);
      expect(cache.containsKey('vol2:x'), isTrue);
      expect(cache.currentBytes, 10);
    });

    test('clear resets both the entries and currentBytes to zero', () {
      final cache = ByteBudgetCache(1000)
        ..['a'] = bytesOf(30)
        ..['b'] = bytesOf(20);
      cache.clear();
      expect(cache.length, 0);
      expect(cache.currentBytes, 0);
    });
  });

  group('resize', () {
    test('shrinking the budget evicts until the new budget is respected',
        () {
      final cache = ByteBudgetCache(200)
        ..['a'] = bytesOf(60)
        ..['b'] = bytesOf(60)
        ..['c'] = bytesOf(60);
      cache.resize(100);

      expect(cache.maxTotalBytes, 100);
      expect(cache.currentBytes, lessThanOrEqualTo(100));
      expect(cache.containsKey('c'), isTrue); // most-recently inserted
      expect(cache.containsKey('a'), isFalse);
    });

    test('growing the budget evicts nothing', () {
      final cache = ByteBudgetCache(100)..['a'] = bytesOf(60);
      cache.resize(1000);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.maxTotalBytes, 1000);
    });
  });

  group('trimToFraction', () {
    test('trimming half the current bytes evicts oldest-first up to that '
        'target, without changing maxTotalBytes', () {
      final cache = ByteBudgetCache(1000)
        ..['a'] = bytesOf(25)
        ..['b'] = bytesOf(25)
        ..['c'] = bytesOf(25)
        ..['d'] = bytesOf(25); // currentBytes = 100
      cache.trimToFraction(0.5); // target = 50

      expect(cache.currentBytes, lessThanOrEqualTo(50));
      expect(cache.maxTotalBytes, 1000);
      expect(cache.containsKey('d'), isTrue);
      expect(cache.containsKey('a'), isFalse);
    });

    test('trimming 0.0 removes nothing', () {
      final cache = ByteBudgetCache(1000)..['a'] = bytesOf(50);
      cache.trimToFraction(0.0);
      expect(cache.currentBytes, 50);
    });

    test('trimming 1.0 removes everything', () {
      final cache = ByteBudgetCache(1000)
        ..['a'] = bytesOf(50)
        ..['b'] = bytesOf(50);
      cache.trimToFraction(1.0);
      expect(cache.currentBytes, 0);
      expect(cache.length, 0);
    });
  });
}
