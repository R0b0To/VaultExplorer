import 'dart:typed_data';

import 'package:vaultexplorer/features/browser/widgets/date_group.dart';

/// The groups of a list, plus the maps between a child index of the grouped
/// sliver (a header per group, then its items), a group and an item.
///
/// Built once per list (see the views' `_groupsFor`), never per frame.
class GalleryGroupIndex<T> {
  GalleryGroupIndex(this.source, this.groups)
    : childCount = source.length + groups.length,
      childGroup = Int32List(source.length + groups.length),
      childLocal = Int32List(source.length + groups.length),
      childOfGlobal = Int32List(source.length)..fillRange(0, source.length, -1) {
    var c = 0;
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      childGroup[c] = g;
      childLocal[c] = -1;
      c++;
      for (var j = 0; j < group.items.length; j++) {
        childGroup[c] = g;
        childLocal[c] = j;
        if (j < group.globalIndices.length) {
          final global = group.globalIndices[j];
          if (global >= 0 && global < childOfGlobal.length) {
            childOfGlobal[global] = c;
          }
        }
        c++;
      }
    }
  }

  /// The flat list the groups were made from.
  final List<T> source;
  final List<DateGroup<T>> groups;
  final int childCount;

  /// Child index -> group.
  final Int32List childGroup;

  /// Child index -> index inside the group, or -1 for the group's header.
  final Int32List childLocal;

  /// Index in [source] -> child index, or -1 when no group holds it.
  final Int32List childOfGlobal;
}
