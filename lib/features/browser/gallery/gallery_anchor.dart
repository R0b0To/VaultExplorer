import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_group_index.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_layout.dart';
import 'package:vaultexplorer/features/browser/services/category_aggregate_scan.dart';

/// What identifies an entry from one version of a list to the next.
///
/// A [CategoryEntry] is its source and path (two copies of a photo in different
/// folders can share name, size and date, so [RawEntry]'s own equality would
/// mix them up); any other entry is its name.
Object galleryAnchorKey(RawEntry entry) =>
    entry is CategoryEntry ? (entry.sourceVolId, entry.path) : entry.name;

/// Where, in [next], the entry that was at [index] of [previous] is.
///
/// That is the entry itself when [next] still has it. When it is gone (a filter
/// now excludes it), the closest entry after it that survives, then the closest
/// before it, so that whatever the person was looking at stays in view. Null
/// when no entry of [previous] is left in [next].
///
/// The common case (the entry is still there) is one pass without allocating a
/// map; the map is only built when the entry is gone.
int? findAnchorIndex<T>(
  List<T> previous,
  int index,
  List<T> next,
  Object Function(T) keyOf,
) {
  if (index < 0 || index >= previous.length || next.isEmpty) return null;
  final target = keyOf(previous[index]);
  for (var i = 0; i < next.length; i++) {
    if (keyOf(next[i]) == target) return i;
  }
  final position = <Object, int>{
    for (var i = 0; i < next.length; i++) keyOf(next[i]): i,
  };
  for (var j = index + 1; j < previous.length; j++) {
    final found = position[keyOf(previous[j])];
    if (found != null) return found;
  }
  for (var j = index - 1; j >= 0; j--) {
    final found = position[keyOf(previous[j])];
    if (found != null) return found;
  }
  return null;
}

/// The scroll offset that keeps the entry that was first on screen at the same
/// place when a list of equal-height rows changes from [previous] to [next]
/// (a plain grid or list: every row is [rowExtent] tall, [columns] entries
/// wide, below [topPadding]). Null when there is nothing to hold in place: the
/// list is at its very top, or no entry survives.
double? uniformAnchorOffset<T>({
  required List<T> previous,
  required List<T> next,
  required Object Function(T) keyOf,
  required double offset,
  required double rowExtent,
  int columns = 1,
  double topPadding = 0,
}) {
  if (rowExtent <= 0 || columns < 1 || offset <= topPadding + 0.5) return null;
  final row = ((offset - topPadding) / rowExtent).floor();
  final index = row * columns;
  if (index < 0 || index >= previous.length) return null;
  final into = (offset - topPadding) - row * rowExtent;
  final found = findAnchorIndex<T>(previous, index, next, keyOf);
  if (found == null) return null;
  return topPadding + (found ~/ columns) * rowExtent + into;
}

/// Carries [anchor] (a child of the grouped sliver laid out from [previous])
/// over to the grouped sliver laid out from [next]: the child that draws the
/// same entry, at the same distance from the top of the screen. Null when the
/// anchor is not an item, or nothing of [previous] is left in [next].
GalleryAnchor? carryGroupAnchor<T>(
  GalleryAnchor anchor,
  GalleryGroupIndex<T> previous,
  GalleryGroupIndex<T> next,
  Object Function(T) keyOf,
) {
  final c = anchor.child;
  if (c < 0 || c >= previous.childCount) return null;
  final local = previous.childLocal[c];
  if (local < 0) return null; // a header: callers anchor on items
  final group = previous.groups[previous.childGroup[c]];
  if (local >= group.globalIndices.length) return null;
  final oldGlobal = group.globalIndices[local];
  final newGlobal = findAnchorIndex<T>(
    previous.source,
    oldGlobal,
    next.source,
    keyOf,
  );
  if (newGlobal == null || newGlobal >= next.childOfGlobal.length) return null;
  final child = next.childOfGlobal[newGlobal];
  if (child < 0) return null;
  return GalleryAnchor(child: child, viewportOffset: anchor.viewportOffset);
}
