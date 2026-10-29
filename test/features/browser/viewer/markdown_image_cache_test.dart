import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_image_cache.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/markdown_image.dart';

// Valid 4x2 and 3x5 RGB PNGs (73 bytes each).
final Uint8List _png4x2 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAEElEQVR4nGM4YWQERwzIHAB+qglhzEG8IAAAAABJRU5ErkJggg==',
);
final Uint8List _png3x5 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAMAAAAFCAIAAAAPE8H1AAAAEElEQVR4nGM4YWQEQQxEsgDAfxGVnd9VnAAAAABJRU5ErkJggg==',
);

MountedContainer _container() => MountedContainer(
      volId: 1,
      uri: 'file:///vault.hc',
      displayName: 'Vault',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
    );

class _FakeVault {
  _FakeVault(this.files);

  final Map<String, Uint8List> files;
  int readAllCalls = 0;
  int readHeadCalls = 0;
  int headInFlight = 0;
  int maxHeadInFlight = 0;

  MarkdownImageCache cache({
    int maxBytes = 48 * 1024 * 1024,
    int prefetchConcurrency = 2,
    int? headLimit,
    Duration headDelay = Duration.zero,
    Future<void>? readAllGate,
  }) {
    return MarkdownImageCache(
      maxBytes: maxBytes,
      prefetchConcurrency: prefetchConcurrency,
      readAll: (path) async {
        readAllCalls++;
        if (readAllGate != null) await readAllGate;
        return files[path];
      },
      readHead: (path, length) async {
        readHeadCalls++;
        headInFlight++;
        maxHeadInFlight = math.max(maxHeadInFlight, headInFlight);
        try {
          if (headDelay != Duration.zero) await Future<void>.delayed(headDelay);
          final f = files[path];
          if (f == null) return null;
          final n = math.min(headLimit ?? length, math.min(length, f.length));
          return Uint8List.sublistView(f, 0, n);
        } finally {
          headInFlight--;
        }
      },
    );
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarkdownImageCache', () {
    test('resolveSize reads only the header, not the whole file', () async {
      final vault = _FakeVault({'/a.png': _png4x2});
      final cache = vault.cache();

      final size = await cache.resolveSize('/a.png');

      expect(size, const Size(4, 2));
      expect(cache.knownSize('/a.png'), const Size(4, 2));
      expect(vault.readAllCalls, 0);
      expect(cache.cachedBytes('/a.png'), isNull);
    });

    test('falls back to the whole file when the header is not enough', () async {
      final vault = _FakeVault({'/a.png': _png4x2});
      final cache = vault.cache(headLimit: 10);

      final size = await cache.resolveSize('/a.png');

      expect(size, const Size(4, 2));
      expect(vault.readAllCalls, 1);
      expect(cache.cachedBytes('/a.png'), isNotNull);
    });

    test('concurrent loads share a single read', () async {
      final vault = _FakeVault({'/a.png': _png4x2});
      final cache = vault.cache();

      final results = await Future.wait([
        cache.loadBytes('/a.png'),
        cache.loadBytes('/a.png'),
      ]);

      expect(vault.readAllCalls, 1);
      expect(results[0], isNotNull);
      expect(identical(results[0], results[1]), isTrue);
    });

    test('a loaded image is served from memory afterwards', () async {
      final vault = _FakeVault({'/a.png': _png4x2});
      final cache = vault.cache();

      final first = await cache.loadBytes('/a.png');
      final second = cache.cachedBytes('/a.png');
      await cache.loadBytes('/a.png');

      expect(identical(first, second), isTrue);
      expect(vault.readAllCalls, 1);
      expect(cache.knownSize('/a.png'), const Size(4, 2));
    });

    test('evicts least-recently-used bytes but never forgets sizes', () async {
      final vault = _FakeVault({'/a.png': _png4x2, '/b.png': _png3x5});
      // Room for one 73-byte image only.
      final cache = vault.cache(maxBytes: 100);

      await cache.loadBytes('/a.png');
      await cache.loadBytes('/b.png');

      expect(cache.cachedBytes('/a.png'), isNull);
      expect(cache.cachedBytes('/b.png'), isNotNull);
      expect(cache.knownSize('/a.png'), const Size(4, 2));
      expect(cache.knownSize('/b.png'), const Size(3, 5));
    });

    test('distinguishes unreadable from invalid images', () async {
      final vault = _FakeVault({
        '/bad.png': Uint8List.fromList([1, 2, 3, 4, 5, 6]),
      });
      final cache = vault.cache();

      expect(await cache.loadBytes('/bad.png'), isNull);
      expect(cache.failureOf('/bad.png'), MarkdownImageFailure.invalid);

      expect(await cache.loadBytes('/missing.png'), isNull);
      expect(cache.failureOf('/missing.png'), MarkdownImageFailure.unreadable);

      cache.clearFailures();
      expect(cache.failureOf('/bad.png'), isNull);
      expect(cache.failureOf('/missing.png'), isNull);
    });

    test('prefetchSizes learns sizes in the background without loading bytes',
        () async {
      final vault = _FakeVault({'/a.png': _png4x2, '/b.png': _png3x5});
      final cache = vault.cache();

      cache.prefetchSizes(['/a.png', '/b.png', '/a.png']);
      await _until(
        () => cache.knownSize('/a.png') != null && cache.knownSize('/b.png') != null,
      );

      expect(cache.knownSize('/a.png'), const Size(4, 2));
      expect(cache.knownSize('/b.png'), const Size(3, 5));
      expect(vault.readAllCalls, 0);
      expect(vault.readHeadCalls, 2); // duplicate path was not read twice
    });

    test('prefetch honours its concurrency limit', () async {
      final vault = _FakeVault({
        for (var i = 0; i < 6; i++) '/$i.png': _png4x2,
      });
      final cache = vault.cache(
        prefetchConcurrency: 2,
        headDelay: const Duration(milliseconds: 5),
      );

      cache.prefetchSizes([for (var i = 0; i < 6; i++) '/$i.png']);
      await _until(() => cache.knownSize('/5.png') != null);

      expect(cache.knownSize('/5.png'), const Size(4, 2));
      expect(vault.maxHeadInFlight, lessThanOrEqualTo(2));
    });
  });

  group('MarkdownImage layout', () {
    Widget host(MarkdownImageCache cache, String path) {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            // Tight width, unbounded height: how a ListView lays out an item.
            body: SingleChildScrollView(
              child: SizedBox(
                width: 300,
                child: MarkdownImage(
                  container: _container(),
                  resolvedPath: path,
                  alt: 'img',
                  cache: cache,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('known image is laid out at its final height on the first frame',
        (tester) async {
      final vault = _FakeVault({'/a.png': _png4x2});
      final cache = vault.cache();
      addTearDown(cache.dispose);
      await tester.runAsync(() => cache.loadBytes('/a.png'));

      await tester.pumpWidget(host(cache, '/a.png'));

      // 300 wide, 4:2 image -> 150 tall, immediately.
      expect(tester.getSize(find.byType(MarkdownImage)), const Size(300, 150));
      await tester.pump();
      expect(tester.getSize(find.byType(MarkdownImage)), const Size(300, 150));
      expect(vault.readAllCalls, 1); // building the widget did not re-read it
    });

    testWidgets('tall images are capped at 420', (tester) async {
      final vault = _FakeVault({'/t.png': _png3x5});
      final cache = vault.cache();
      addTearDown(cache.dispose);
      await tester.runAsync(() => cache.loadBytes('/t.png'));

      await tester.pumpWidget(host(cache, '/t.png'));

      expect(tester.getSize(find.byType(MarkdownImage)), const Size(300, 420));
    });

    testWidgets('re-creating the widget does not reload the image',
        (tester) async {
      final vault = _FakeVault({'/a.png': _png4x2});
      final cache = vault.cache();
      addTearDown(cache.dispose);
      await tester.runAsync(() => cache.loadBytes('/a.png'));

      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(host(cache, '/a.png'));
        expect(
          tester.getSize(find.byType(MarkdownImage)),
          const Size(300, 150),
        );
        // Simulates the lazy list disposing the item as it scrolls away.
        await tester.pumpWidget(const SizedBox.shrink());
      }

      expect(vault.readAllCalls, 1);
    });

    testWidgets('unknown size uses the 160px placeholder', (tester) async {
      final never = Completer<void>();
      final vault = _FakeVault({'/a.png': _png4x2});
      final cache = vault.cache(readAllGate: never.future);
      addTearDown(cache.dispose);

      await tester.pumpWidget(host(cache, '/a.png'));

      expect(tester.getSize(find.byType(MarkdownImage)).height, 160);
    });
  });
}
