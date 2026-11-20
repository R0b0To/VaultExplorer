// Squarified treemap layout (Bruls, Huizing & van Wijk, 2000): tiles whose
// areas are proportional to size, packed so they stay as close to square as
// possible -- which is what keeps a tile big enough to read and to tap.
//
// Pure geometry on plain doubles (no dart:ui), so it can be tested exactly. The
// widget layer turns [TmRect] into a `Rect`.
library;

import 'dart:math' as math;

import 'package:vaultexplorer/features/tools/models/storage_tree.dart';

class TmRect {
  const TmRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get area => width * height;

  bool containsPoint(double x, double y) =>
      x >= left && x < right && y >= top && y < bottom;

  @override
  String toString() => 'TmRect($left, $top, $width x $height)';
}

class TmTile<T> {
  const TmTile(this.item, this.rect);

  final T item;
  final TmRect rect;
}

/// Lays [items] out inside [bounds], each tile's area proportional to its
/// [weight]. Items with a weight of zero or less get no tile. The returned
/// tiles cover [bounds] exactly, largest first.
List<TmTile<T>> squarify<T>({
  required List<T> items,
  required double Function(T item) weight,
  required TmRect bounds,
}) {
  if (bounds.width <= 0 || bounds.height <= 0) return <TmTile<T>>[];
  final sorted = items.where((i) => weight(i) > 0).toList()
    ..sort((a, b) => weight(b).compareTo(weight(a)));
  if (sorted.isEmpty) return <TmTile<T>>[];

  var total = 0.0;
  for (final i in sorted) {
    total += weight(i);
  }
  final scale = bounds.area / total;
  final areas = [for (final i in sorted) weight(i) * scale];

  final tiles = <TmTile<T>>[];
  var rect = bounds;
  var start = 0;
  while (start < sorted.length) {
    final shortSide = math.min(rect.width, rect.height);

    // Grow the row while it keeps (or improves) the worst aspect ratio.
    var end = start + 1;
    var sum = areas[start];
    var smallest = areas[start];
    var largest = areas[start];
    var worst = _worstRatio(sum, smallest, largest, shortSide);
    while (end < sorted.length) {
      final a = areas[end];
      final nSum = sum + a;
      final nSmallest = math.min(smallest, a);
      final nLargest = math.max(largest, a);
      final nWorst = _worstRatio(nSum, nSmallest, nLargest, shortSide);
      if (nWorst > worst) break;
      sum = nSum;
      smallest = nSmallest;
      largest = nLargest;
      worst = nWorst;
      end++;
    }

    final isLast = end == sorted.length;
    if (rect.width >= rect.height) {
      // The row is a vertical strip down the left edge.
      final stripW = isLast ? rect.width : sum / rect.height;
      var y = rect.top;
      for (var k = start; k < end; k++) {
        final h = k == end - 1 ? rect.bottom - y : areas[k] / stripW;
        tiles.add(TmTile(sorted[k], TmRect(rect.left, y, stripW, h)));
        y += h;
      }
      rect = TmRect(
        rect.left + stripW,
        rect.top,
        rect.width - stripW,
        rect.height,
      );
    } else {
      // The row is a horizontal strip along the top edge.
      final stripH = isLast ? rect.height : sum / rect.width;
      var x = rect.left;
      for (var k = start; k < end; k++) {
        final w = k == end - 1 ? rect.right - x : areas[k] / stripH;
        tiles.add(TmTile(sorted[k], TmRect(x, rect.top, w, stripH)));
        x += w;
      }
      rect = TmRect(
        rect.left,
        rect.top + stripH,
        rect.width,
        rect.height - stripH,
      );
    }
    start = end;
  }
  return tiles;
}

// The worst (largest) aspect ratio in a row whose areas sum to [sum], laid
// along a side of length [side].
double _worstRatio(double sum, double smallest, double largest, double side) {
  final s2 = side * side;
  final sum2 = sum * sum;
  return math.max(s2 * largest / sum2, sum2 / (s2 * smallest));
}

/// One tile in the folder map: a single file or folder, or a lump of the many
/// that are individually too small to draw.
class TreemapEntry {
  const TreemapEntry.single(StorageNode this.node)
    : grouped = const <StorageNode>[],
      bytes = 0;

  const TreemapEntry.group(this.grouped, this.bytes) : node = null;

  final StorageNode? node;
  final List<StorageNode> grouped;
  final int bytes;

  bool get isGroup => node == null;
  int get weightBytes => node?.sizeBytes ?? bytes;
}

/// Chooses what to draw for a folder's [children] in a map of [areaPx] square
/// pixels: every child big enough to be a readable, tappable tile gets one
/// (largest first, at most [maxTiles]), and the rest are lumped into a single
/// group tile -- unless only one is left over, which just gets its own.
/// Empty children never appear; the list view is where those are found.
List<TreemapEntry> buildTreemapEntries(
  List<StorageNode> children, {
  required double areaPx,
  double minTileArea = 2600,
  int maxTiles = 80,
}) {
  final sized = children.where((c) => c.sizeBytes > 0).toList()
    ..sort(StorageNode.bySizeDesc);
  if (sized.isEmpty) return const <TreemapEntry>[];

  var total = 0;
  for (final c in sized) {
    total += c.sizeBytes;
  }

  final entries = <TreemapEntry>[];
  var i = 0;
  while (i < sized.length && entries.length < maxTiles) {
    final share = sized[i].sizeBytes / total;
    if (share * areaPx < minTileArea) break;
    entries.add(TreemapEntry.single(sized[i]));
    i++;
  }
  // Always show at least the biggest child, however tiny the map.
  if (entries.isEmpty) {
    entries.add(TreemapEntry.single(sized[0]));
    i = 1;
  }

  final rest = sized.sublist(i);
  if (rest.length == 1) {
    entries.add(TreemapEntry.single(rest.first));
  } else if (rest.length > 1) {
    var bytes = 0;
    for (final c in rest) {
      bytes += c.sizeBytes;
    }
    entries.add(TreemapEntry.group(rest, bytes));
  }
  return entries;
}
