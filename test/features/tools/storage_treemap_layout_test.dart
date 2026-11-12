import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/tools/models/storage_tree.dart';
import 'package:vaultexplorer/features/tools/models/storage_treemap_layout.dart';

const _eps = 1e-6;

double _overlap(TmRect a, TmRect b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  return (w > 0 && h > 0) ? w * h : 0;
}

void _checkInvariants(List<TmTile<double>> tiles, TmRect bounds) {
  var total = 0.0;
  var weights = 0.0;
  for (final t in tiles) {
    total += t.rect.area;
    weights += t.item;
    expect(t.rect.left, greaterThanOrEqualTo(bounds.left - _eps));
    expect(t.rect.top, greaterThanOrEqualTo(bounds.top - _eps));
    expect(t.rect.right, lessThanOrEqualTo(bounds.right + _eps));
    expect(t.rect.bottom, lessThanOrEqualTo(bounds.bottom + _eps));
    expect(t.rect.width, greaterThan(0));
    expect(t.rect.height, greaterThan(0));
  }
  // The tiles cover the container exactly...
  expect(total, closeTo(bounds.area, 1e-4));
  // ...each in proportion to its weight...
  for (final t in tiles) {
    expect(t.rect.area / bounds.area, closeTo(t.item / weights, 1e-6));
  }
  // ...and never on top of one another.
  for (var i = 0; i < tiles.length; i++) {
    for (var j = i + 1; j < tiles.length; j++) {
      expect(_overlap(tiles[i].rect, tiles[j].rect), lessThan(1e-6));
    }
  }
}

StorageNode _file(String n, int size) =>
    StorageNode.file(name: n, path: n, sizeBytes: size);

void main() {
  group('squarify', () {
    test('a single item fills the bounds', () {
      const b = TmRect(0, 0, 300, 200);
      final tiles = squarify<double>(items: [5], weight: (w) => w, bounds: b);
      expect(tiles, hasLength(1));
      expect(tiles.first.rect.area, closeTo(b.area, _eps));
    });

    test('covers, proportions and non-overlap hold for varied inputs', () {
      final cases = <List<double>>[
        [6, 6, 4, 3, 2, 2, 1],
        [100, 1, 1, 1, 1, 1, 1, 1, 1],
        [5, 5, 5, 5],
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
        [1e12, 3e11, 2e9, 7e6, 5e3],
      ];
      for (final bounds in const [
        TmRect(0, 0, 360, 280),
        TmRect(10, 20, 200, 800), // tall
        TmRect(0, 0, 900, 120), // wide
      ]) {
        for (final w in cases) {
          _checkInvariants(
            squarify<double>(items: w, weight: (x) => x, bounds: bounds),
            bounds,
          );
        }
      }
    });

    test('random inputs keep every invariant', () {
      final rnd = math.Random(42);
      for (var run = 0; run < 60; run++) {
        final n = 1 + rnd.nextInt(60);
        final w = [for (var i = 0; i < n; i++) 1 + rnd.nextDouble() * 1000];
        final b = TmRect(
          0,
          0,
          150 + rnd.nextDouble() * 700,
          150 + rnd.nextDouble() * 700,
        );
        _checkInvariants(
          squarify<double>(items: w, weight: (x) => x, bounds: b),
          b,
        );
      }
    });

    test('largest item gets the largest tile', () {
      const b = TmRect(0, 0, 400, 300);
      final tiles = squarify<double>(
        items: [1, 9, 3],
        weight: (x) => x,
        bounds: b,
      );
      expect(tiles.first.item, 9);
      final areas = tiles.map((t) => t.rect.area).toList();
      expect(areas.first, greaterThanOrEqualTo(areas[1]));
    });

    test('keeps tiles reasonably square for even input', () {
      const b = TmRect(0, 0, 400, 400);
      final tiles = squarify<double>(
        items: List.filled(16, 1.0),
        weight: (x) => x,
        bounds: b,
      );
      for (final t in tiles) {
        final ratio = math.max(
          t.rect.width / t.rect.height,
          t.rect.height / t.rect.width,
        );
        expect(ratio, lessThan(2.0));
      }
    });

    test('ignores non-positive weights and degenerate bounds', () {
      expect(
        squarify<double>(
          items: [0, -1],
          weight: (x) => x,
          bounds: const TmRect(0, 0, 9, 9),
        ),
        isEmpty,
      );
      expect(
        squarify<double>(
          items: [1],
          weight: (x) => x,
          bounds: const TmRect(0, 0, 0, 9),
        ),
        isEmpty,
      );
      expect(
        squarify<double>(
          items: <double>[],
          weight: (x) => x,
          bounds: const TmRect(0, 0, 9, 9),
        ),
        isEmpty,
      );
    });
  });

  group('buildTreemapEntries', () {
    test('gives big children their own tile and lumps the rest', () {
      final kids = [
        _file('a', 5000),
        _file('b', 3000),
        for (var i = 0; i < 20; i++) _file('s$i', 5),
      ];
      final e = buildTreemapEntries(kids, areaPx: 100000);
      expect(e.where((x) => !x.isGroup).map((x) => x.node!.name).toList(), [
        'a',
        'b',
      ]);
      final group = e.singleWhere((x) => x.isGroup);
      expect(group.grouped, hasLength(20));
      expect(group.bytes, 100);
      expect(group.weightBytes, 100);
    });

    test('a lone leftover is shown as itself, not a group of one', () {
      final e = buildTreemapEntries([
        _file('a', 9000),
        _file('b', 1),
      ], areaPx: 100000);
      expect(e.any((x) => x.isGroup), isFalse);
      expect(e, hasLength(2));
    });

    test('empty children never appear', () {
      final e = buildTreemapEntries([
        _file('z', 0),
        _file('a', 10),
      ], areaPx: 100000);
      expect(e.map((x) => x.node!.name).toList(), ['a']);
      expect(buildTreemapEntries([_file('z', 0)], areaPx: 1000), isEmpty);
      expect(buildTreemapEntries(const [], areaPx: 1000), isEmpty);
    });

    test('a tiny map still shows the biggest child', () {
      final e = buildTreemapEntries([
        _file('a', 100),
        _file('b', 100),
        _file('c', 100),
      ], areaPx: 10);
      expect(e.first.isGroup, isFalse);
      expect(e.first.node!.name, 'a');
    });

    test('honours maxTiles', () {
      final kids = [for (var i = 0; i < 30; i++) _file('f$i', 1000 - i)];
      final e = buildTreemapEntries(kids, areaPx: 1e9, maxTiles: 10);
      expect(e.where((x) => !x.isGroup).length, 10);
      expect(e.last.isGroup, isTrue);
      expect(e.last.grouped, hasLength(20));
    });

    test('entries feed squarify so every byte is accounted for', () {
      final kids = [for (var i = 1; i <= 40; i++) _file('f$i', i * 100)];
      final entries = buildTreemapEntries(kids, areaPx: 360 * 300);
      const b = TmRect(0, 0, 360, 300);
      final tiles = squarify<TreemapEntry>(
        items: entries,
        weight: (e) => e.weightBytes.toDouble(),
        bounds: b,
      );
      var area = 0.0;
      for (final t in tiles) {
        area += t.rect.area;
      }
      expect(area, closeTo(b.area, 1e-4));
    });
  });
}
