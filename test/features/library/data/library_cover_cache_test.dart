import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/library/data/library_cover_cache.dart';

Uint8List _bytes(int n) => Uint8List(n);

void main() {
  test('caches a loaded picture and does not call the loader again', () async {
    final cache = LibraryCoverCache();
    var calls = 0;
    Future<Uint8List?> loader() async {
      calls++;
      return _bytes(10);
    }

    expect((await cache.load('a', loader))!.length, 10);
    expect((await cache.load('a', loader))!.length, 10);
    expect(calls, 1);
    expect(cache.contains('a'), isTrue);
  });

  test('concurrent requests for one key share a single read', () async {
    final cache = LibraryCoverCache();
    var calls = 0;
    final gate = Completer<void>();
    Future<Uint8List?> loader() async {
      calls++;
      await gate.future;
      return _bytes(5);
    }

    final f1 = cache.load('a', loader);
    final f2 = cache.load('a', loader);
    gate.complete();
    await Future.wait([f1, f2]);
    expect(calls, 1);
  });

  test('a miss is remembered so it is not re-read on every scroll', () async {
    final cache = LibraryCoverCache();
    var calls = 0;
    Future<Uint8List?> loader() async {
      calls++;
      return null;
    }

    expect(await cache.load('none', loader), isNull);
    expect(await cache.load('none', loader), isNull);
    expect(calls, 1);
    expect(cache.contains('none'), isTrue);
    expect(cache.peek('none'), isNull);
  });

  test('a loader that throws is treated as a miss', () async {
    final cache = LibraryCoverCache();
    expect(await cache.load('x', () async => throw StateError('io')), isNull);
    expect(cache.contains('x'), isTrue);
  });

  test('evicts least recently used pictures past the byte budget', () async {
    final cache = LibraryCoverCache(maxBytes: 100);
    await cache.load('a', () async => _bytes(40));
    await cache.load('b', () async => _bytes(40));
    cache.peek('a'); // a is now more recent than b
    await cache.load('c', () async => _bytes(40));
    expect(cache.contains('b'), isFalse);
    expect(cache.contains('a'), isTrue);
    expect(cache.contains('c'), isTrue);
    expect(cache.byteSize, 80);
  });

  test('an oversized picture is still served, alone', () async {
    final cache = LibraryCoverCache(maxBytes: 100);
    await cache.load('a', () async => _bytes(40));
    await cache.load('big', () async => _bytes(500));
    expect(cache.contains('big'), isTrue);
    expect(cache.contains('a'), isFalse);
  });

  test('clear drops everything and ignores reads that finish afterwards', () async {
    final cache = LibraryCoverCache();
    await cache.load('a', () async => _bytes(10));
    final gate = Completer<void>();
    final pending = cache.load('late', () async {
      await gate.future;
      return _bytes(10);
    });
    cache.clear();
    gate.complete();
    expect((await pending)!.length, 10); // the caller still gets its bytes
    expect(cache.contains('late'), isFalse); // but nothing is kept
    expect(cache.contains('a'), isFalse);
    expect(cache.byteSize, 0);
  });
}
