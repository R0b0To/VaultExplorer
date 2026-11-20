import 'dart:async';

import 'package:test/test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_ratio_prefetcher.dart';

MountedContainer _container(String uri) => MountedContainer(
  uri: uri,
  displayName: uri,
  volId: 1,
  rootFiles: const [],
  mountedAt: DateTime(2026),
  totalSpace: 0,
  freeSpace: 0,
);

Future<void> main() async {
  final container = _container('content://vault/a');

  test('collectBatch goes outward from the focus, two ahead per one behind', () {
    final p = GalleryRatioPrefetcher(
      probe: (c, paths) async => [],
      batchSize: 9,
    );
    p.start(
      itemCount: 100,
      wantsProbe: (_) => false,
      targetOf: (_) => null,
      focusIndex: () => 50,
      onResult: (_, __, ___) {},
    );
    final batch = p.collectBatch(itemCount: 100, focus: 50, wantsProbe: (_) => true);
    p.stop();
    expect(batch, [50, 51, 49, 52, 53, 48, 54, 55, 47]);
  });

  test('probes every wanted item exactly once, nearest first, then stops', () async {
    final probed = <String>[];
    final learned = <int, double>{};
    final wanted = {for (var i = 0; i < 200; i++) i};
    final p = GalleryRatioPrefetcher(
      probe: (c, paths) async {
        probed.addAll(paths);
        return [for (final _ in paths) (width: 400, height: 300)];
      },
      batchSize: 16,
      gap: Duration.zero,
    );
    p.start(
      itemCount: 200,
      wantsProbe: wanted.contains,
      targetOf: (i) => GalleryProbeTarget(container, 'p/$i.jpg'),
      focusIndex: () => 120,
      onResult: (i, w, h) {
        learned[i] = w / h;
        wanted.remove(i);
      },
    );
    while (p.isRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(learned.length, 200);
    expect(probed.length, 200); // never twice
    expect(probed.first, 'p/120.jpg');
    expect(probed.take(16).toSet().every((s) {
      final i = int.parse(s.substring(2, s.indexOf('.')));
      return (i - 120).abs() <= 12;
    }), isTrue);
  });

  test('only items within the look-ahead/behind window are probed', () async {
    final probed = <String>[];
    final p = GalleryRatioPrefetcher(
      probe: (c, paths) async {
        probed.addAll(paths);
        return [for (final _ in paths) (width: 4, height: 3)];
      },
      batchSize: 16,
      gap: Duration.zero,
      lookAhead: 40,
      lookBehind: 10,
    );
    final wanted = {for (var i = 0; i < 500; i++) i};
    p.start(
      itemCount: 500,
      wantsProbe: wanted.contains,
      targetOf: (i) => GalleryProbeTarget(container, '$i.jpg'),
      focusIndex: () => 250,
      onResult: (i, w, h) => wanted.remove(i),
    );
    while (p.isRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final indices = probed.map((s) => int.parse(s.substring(0, s.indexOf('.')))).toList();
    expect(indices.length, 50);
    expect(indices.every((i) => i >= 240 && i < 290), isTrue);
  });

  test('a restart without reset does not retry what already failed', () async {
    var calls = 0;
    final p = GalleryRatioPrefetcher(
      probe: (c, paths) async {
        calls++;
        return [for (final _ in paths) null];
      },
      batchSize: 8,
      gap: Duration.zero,
    );
    void run({required bool reset}) => p.start(
      resetTried: reset,
      itemCount: 16,
      wantsProbe: (_) => true,
      targetOf: (i) => GalleryProbeTarget(container, '$i.jpg'),
      focusIndex: () => 0,
      onResult: (_, __, ___) {},
    );
    run(reset: true);
    while (p.isRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(calls, 2);
    run(reset: false);
    while (p.isRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(calls, 2);
    run(reset: true);
    while (p.isRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(calls, 4);
  });

  test('in follow mode a run keeps going and picks up work when the focus moves', () async {
    var focus = 0;
    final probed = <int>[];
    final wanted = {for (var i = 0; i < 1000; i++) i};
    final p = GalleryRatioPrefetcher(
      probe: (c, paths) async {
        probed.addAll(paths.map((s) => int.parse(s.substring(0, s.indexOf('.')))));
        return [for (final _ in paths) (width: 4, height: 3)];
      },
      batchSize: 16,
      gap: Duration.zero,
      idleGap: const Duration(milliseconds: 5),
      lookAhead: 50,
      lookBehind: 0,
    );
    p.start(
      follow: true,
      itemCount: 1000,
      wantsProbe: wanted.contains,
      targetOf: (i) => GalleryProbeTarget(container, '$i.jpg'),
      focusIndex: () => focus,
      onResult: (i, w, h) => wanted.remove(i),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(probed.length, 50);
    expect(p.isRunning, isTrue, reason: 'it keeps watching');
    expect(probed.every((i) => i < 50), isTrue);

    focus = 700; // a fling / the scroll handle
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(probed.length, 100);
    expect(probed.skip(50).every((i) => i >= 700 && i < 750), isTrue);

    p.stop();
    expect(p.isRunning, isFalse);
  });

  test('an item that cannot be probed is not retried', () async {
    var calls = 0;
    final p = GalleryRatioPrefetcher(
      probe: (c, paths) async {
        calls++;
        return [for (final _ in paths) null];
      },
      batchSize: 8,
      gap: Duration.zero,
    );
    p.start(
      itemCount: 20,
      wantsProbe: (_) => true,
      targetOf: (i) => GalleryProbeTarget(container, '$i.jpg'),
      focusIndex: () => 0,
      onResult: (_, __, ___) {},
    );
    while (p.isRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(calls, 3); // 8 + 8 + 4
  });

  test('a restart abandons the previous run and drops its in-flight result', () async {
    final first = Completer<List<({int width, int height})?>>();
    final results = <int>[];
    var n = 0;
    final p = GalleryRatioPrefetcher(
      probe: (c, paths) {
        n++;
        if (n == 1) return first.future;
        return Future.value([for (final _ in paths) (width: 1, height: 1)]);
      },
      batchSize: 4,
      gap: Duration.zero,
    );
    p.start(
      itemCount: 4,
      wantsProbe: (_) => true,
      targetOf: (i) => GalleryProbeTarget(container, '$i.jpg'),
      focusIndex: () => 0,
      onResult: (i, w, h) => results.add(100 + i),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    p.start(
      itemCount: 4,
      wantsProbe: (_) => true,
      targetOf: (i) => GalleryProbeTarget(container, '$i.jpg'),
      focusIndex: () => 0,
      onResult: (i, w, h) => results.add(i),
    );
    first.complete([for (var i = 0; i < 4; i++) (width: 2, height: 2)]);
    while (p.isRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(results.every((r) => r < 100), isTrue); // nothing from run #1
    expect(results.length, 4);
  });
}
