import 'package:flutter/foundation.dart';

import 'gallery_filters.dart';
import 'gallery_grouping.dart';

/// What the person has chosen in the gallery's filter: the applied filters and
/// how the gallery is sectioned. The gallery listens and refilters.
class GalleryFilterController extends ChangeNotifier {
  GalleryFilterController({
    GalleryFilterSet filters = GalleryFilterSet.empty,
    GalleryGroupBy groupBy = GalleryGroupBy.day,
  }) : _filters = filters,
       _groupBy = groupBy;

  GalleryFilterSet _filters;
  GalleryGroupBy _groupBy;

  GalleryFilterSet get filters => _filters;
  GalleryGroupBy get groupBy => _groupBy;

  bool get hasFilters => _filters.isNotEmpty;

  set filters(GalleryFilterSet value) {
    if (value == _filters) return;
    _filters = value;
    notifyListeners();
  }

  set groupBy(GalleryGroupBy value) {
    if (value == _groupBy) return;
    _groupBy = value;
    notifyListeners();
  }

  /// Required <-> not applied (what a tap on a chip does).
  void toggle(GalleryFilter f) => filters = _filters.toggle(f);

  /// Required <-> excluded (what a long press on a chip does).
  void exclude(GalleryFilter f) {
    filters = _filters.excludes(f) ? _filters.remove(f) : _filters.add(f.withReversed(true));
  }

  void remove(GalleryFilter f) => filters = _filters.remove(f);

  void clear() => filters = GalleryFilterSet.empty;
}
