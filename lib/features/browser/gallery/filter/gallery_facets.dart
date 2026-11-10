import 'gallery_filter_labels.dart';
import 'gallery_filters.dart';
import 'gallery_places.dart';

/// A filter the person could add, with how many files it would match.
typedef GalleryFacet = ({GalleryFilter filter, int count});

/// The choices the filter sheet offers for a set of gallery files: every tag,
/// place, camera, year... that occurs, with its count. Built from the files
/// *before* filtering, so the counts say what a filter would bring, like the
class GalleryFacets {
  const GalleryFacets({
    required this.total,
    required this.types,
    required this.years,
    required this.monthsByYear,
    required this.tags,
    required this.places,
    required this.cameras,
    required this.orientations,
    required this.ratings,
    required this.sizes,
    required this.folders,
    required this.missing,
  });

  final int total;
  final List<GalleryFacet> types;
  final List<GalleryFacet> years;
  final Map<int, List<GalleryFacet>> monthsByYear;
  final List<GalleryFacet> tags;
  final List<GalleryFacet> places;
  final List<GalleryFacet> cameras;
  final List<GalleryFacet> orientations;
  final List<GalleryFacet> ratings;
  final List<GalleryFacet> sizes;
  final List<GalleryFacet> folders;
  final List<GalleryFacet> missing;

  static GalleryFacets compute(
    Iterable<GalleryFilterSubject> subjects, {
    GalleryFilterLabels labels = const GalleryFilterLabels(),
  }) {
    var total = 0;
    final types = <GalleryMediaType, int>{};
    final years = <int, int>{};
    final months = <int, Map<int, int>>{};
    final tags = <String, ({String tag, int count})>{};
    final places = <String, ({String label, int count})>{};
    final cameras = <String, ({String name, int count})>{};
    final orientation = <GalleryOrientation, int>{};
    final ratingAtLeast = List<int>.filled(6, 0);
    final sizes = <GallerySizeClass, int>{};
    final folders = <({int vol, String path}), int>{};
    final missing = <GalleryMissing, int>{};

    for (final s in subjects) {
      total++;
      types.update(s.mediaType, (v) => v + 1, ifAbsent: () => 1);

      final d = s.date;
      if (d != null) {
        years.update(d.year, (v) => v + 1, ifAbsent: () => 1);
        final m = months.putIfAbsent(d.year, () => {});
        m.update(d.month, (v) => v + 1, ifAbsent: () => 1);
      }

      final seen = <String>{};
      for (final t in s.meta.tags) {
        final k = t.toLowerCase();
        if (!seen.add(k)) continue;
        final cur = tags[k];
        tags[k] = (tag: cur?.tag ?? t, count: (cur?.count ?? 0) + 1);
      }

      final place = s.place;
      if (place != null) {
        final cur = places[place.key];
        places[place.key] = (label: place.label, count: (cur?.count ?? 0) + 1);
      }

      final cam = s.meta.camera;
      if (cam != null) {
        final k = cam.toLowerCase();
        final cur = cameras[k];
        cameras[k] = (name: cur?.name ?? cam, count: (cur?.count ?? 0) + 1);
      }

      final w = s.width;
      final h = s.height;
      if (w != null && h != null && w > 0 && h > 0) {
        final o = w > h
            ? GalleryOrientation.landscape
            : (h > w ? GalleryOrientation.portrait : GalleryOrientation.square);
        orientation.update(o, (v) => v + 1, ifAbsent: () => 1);
      }

      final r = s.meta.rating ?? 0;
      for (var n = 1; n <= r && n <= 5; n++) {
        ratingAtLeast[n]++;
      }

      for (final c in GallerySizeClass.values) {
        if (GallerySizeFilter(c).positive(s)) {
          sizes.update(c, (v) => v + 1, ifAbsent: () => 1);
        }
      }

      folders.update(
        (vol: s.sourceVolId, path: s.parentPath),
        (v) => v + 1,
        ifAbsent: () => 1,
      );

      for (final m in GalleryMissing.values) {
        if (GalleryMissingFilter(m).positive(s)) {
          missing.update(m, (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }

    List<GalleryFacet> byCount(List<GalleryFacet> list) {
      list.sort((a, b) {
        final c = b.count.compareTo(a.count);
        return c != 0
            ? c
            : a.filter.label(labels).toLowerCase().compareTo(b.filter.label(labels).toLowerCase());
      });
      return list;
    }

    return GalleryFacets(
      total: total,
      types: [
        for (final t in GalleryMediaType.values)
          if ((types[t] ?? 0) > 0) (filter: GalleryTypeFilter(t), count: types[t]!),
      ],
      years: [
        for (final y in (years.keys.toList()..sort((a, b) => b.compareTo(a))))
          (filter: GalleryDateFilter(y), count: years[y]!),
      ],
      monthsByYear: {
        for (final e in months.entries)
          e.key: [
            for (final m in (e.value.keys.toList()..sort((a, b) => b.compareTo(a))))
              (filter: GalleryDateFilter(e.key, month: m), count: e.value[m]!),
          ],
      },
      tags: byCount([
        for (final e in tags.values) (filter: GalleryTagFilter(e.tag), count: e.count),
      ]),
      places: byCount([
        for (final e in places.entries)
          (filter: GalleryPlaceFilter(e.key, placeLabel: e.value.label), count: e.value.count),
      ]),
      cameras: byCount([
        for (final e in cameras.values) (filter: GalleryCameraFilter(e.name), count: e.count),
      ]),
      orientations: [
        for (final o in GalleryOrientation.values)
          if ((orientation[o] ?? 0) > 0)
            (filter: GalleryOrientationFilter(o), count: orientation[o]!),
      ],
      ratings: [
        for (var n = 5; n >= 1; n--)
          if (ratingAtLeast[n] > 0) (filter: GalleryRatingFilter(n), count: ratingAtLeast[n]),
      ],
      sizes: [
        for (final c in GallerySizeClass.values)
          if ((sizes[c] ?? 0) > 0) (filter: GallerySizeFilter(c), count: sizes[c]!),
      ],
      folders: byCount([
        for (final e in folders.entries)
          (filter: GalleryFolderFilter(e.key.vol, e.key.path), count: e.value),
      ]),
      missing: [
        for (final m in GalleryMissing.values)
          if ((missing[m] ?? 0) > 0) (filter: GalleryMissingFilter(m), count: missing[m]!),
      ],
    );
  }
}

/// Tooltip of a place chip: says whether it is a city or bare coordinates.
String galleryPlaceHint(GalleryPlaceFilter f, GalleryFilterLabels labels) {
  final km = GalleryPlaceResolver.maxDistanceKm.round();
  return f.placeKey.startsWith('c')
      ? labels.placeHintCity(km)
      : labels.placeHintCoordinates(km);
}
