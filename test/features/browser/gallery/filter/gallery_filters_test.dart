import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_facets.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_filter_labels.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_filters.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_grouping.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_places.dart';

GalleryFilterSubject _s(
  String name, {
  String dir = '',
  int size = 500000,
  int modified = 0,
  GalleryMeta meta = GalleryMeta.empty,
}) {
  final dot = name.lastIndexOf('.');
  return GalleryFilterSubject(
    sourceVolId: 1,
    name: name,
    parentPath: dir,
    extension: dot < 0 ? '' : name.substring(dot + 1).toLowerCase(),
    sizeBytes: size,
    modifiedSecs: modified,
    meta: meta,
    place: galleryPlaceOf(meta, null),
  );
}

int _taken(int y, int m, int d) => DateTime.utc(y, m, d, 12).millisecondsSinceEpoch ~/ 1000;

void main() {
  final paris = GalleryMeta(
    takenSecs: _taken(2023, 7, 14),
    latitude: 48.85,
    longitude: 2.35,
    make: 'Canon',
    model: 'EOS R5',
    tags: ['Holiday', 'Food'],
    rating: 4,
    width: 4000,
    height: 3000,
  );
  final rome = GalleryMeta(
    takenSecs: _taken(2022, 5, 2),
    latitude: 41.9,
    longitude: 12.5,
    make: 'Google',
    model: 'Pixel 9',
    tags: ['holiday'],
    width: 3000,
    height: 4000,
  );
  final a = _s('a.jpg', dir: 'Trips/Paris', meta: paris);
  final b = _s('b.jpg', dir: 'Trips/Rome', meta: rome);
  final c = _s('c.mp4', dir: 'Clips', size: 20 * 1024 * 1024, modified: 1700000000);
  final d = _s('d.png', dir: 'Misc');

  group('single filters', () {
    test('tag match is case-insensitive', () {
      expect(const GalleryTagFilter('HOLIDAY').matches(a), isTrue);
      expect(const GalleryTagFilter('holiday').matches(b), isTrue);
      expect(const GalleryTagFilter('holiday').matches(c), isFalse);
    });

    test('date filter by year, month and day', () {
      expect(const GalleryDateFilter(2023).matches(a), isTrue);
      expect(const GalleryDateFilter(2023, month: 7).matches(a), isTrue);
      expect(const GalleryDateFilter(2023, month: 8).matches(a), isFalse);
      expect(const GalleryDateFilter(2023, month: 7, day: 14).matches(a), isTrue);
      expect(const GalleryDateFilter(2022).matches(a), isFalse);
      expect(const GalleryDateFilter(2023).matches(d), isFalse); // undated
    });

    test('place, camera, orientation, rating, size, type', () {
      expect(GalleryPlaceFilter('x${paris.placeCell}').matches(a), isTrue);
      expect(GalleryPlaceFilter('x${paris.placeCell}').matches(b), isFalse);
      expect(const GalleryCameraFilter('google pixel 9').matches(b), isTrue);
      expect(const GalleryOrientationFilter(GalleryOrientation.landscape).matches(a), isTrue);
      expect(const GalleryOrientationFilter(GalleryOrientation.portrait).matches(b), isTrue);
      expect(const GalleryOrientationFilter(GalleryOrientation.portrait).matches(c), isFalse);
      expect(const GalleryRatingFilter(3).matches(a), isTrue);
      expect(const GalleryRatingFilter(5).matches(a), isFalse);
      expect(const GallerySizeFilter(GallerySizeClass.large).matches(c), isTrue);
      expect(const GalleryTypeFilter(GalleryMediaType.video).matches(c), isTrue);
      expect(const GalleryTypeFilter(GalleryMediaType.photo).matches(c), isFalse);
    });

    test('missing and reversed', () {
      expect(const GalleryMissingFilter(GalleryMissing.location).matches(d), isTrue);
      expect(const GalleryMissingFilter(GalleryMissing.location).matches(a), isFalse);
      expect(const GalleryTagFilter('food', reversed: true).matches(a), isFalse);
      expect(const GalleryTagFilter('food', reversed: true).matches(b), isTrue);
    });

    test('query matches name, folder, tag and camera', () {
      expect(const GalleryQueryFilter('paris').matches(a), isTrue);
      expect(const GalleryQueryFilter('food').matches(a), isTrue);
      expect(const GalleryQueryFilter('pixel').matches(b), isTrue);
      expect(const GalleryQueryFilter('d.p').matches(d), isTrue);
      expect(const GalleryQueryFilter('zzz').matches(a), isFalse);
    });
  });

  group('GalleryFilterSet', () {
    test('same kind is OR, different kinds are AND', () {
      var set = const GalleryFilterSet();
      set = set.add(const GalleryTagFilter('food')).add(const GalleryTagFilter('nothing'));
      expect(set.matches(a), isTrue); // food OR nothing
      expect(set.matches(b), isFalse);
      set = set.add(const GalleryDateFilter(2022));
      expect(set.matches(a), isFalse); // tag ok, wrong year
    });

    test('excluded filters always remove', () {
      final set = const GalleryFilterSet().add(const GalleryTypeFilter(GalleryMediaType.photo)).add(const GalleryTagFilter('food', reversed: true));
      expect(set.matches(a), isFalse);
      expect(set.matches(b), isTrue);
      expect(set.matches(c), isFalse);
    });

    test('toggle, flip and replace keep one entry per identity', () {
      var set = const GalleryFilterSet();
      set = set.toggle(const GalleryTagFilter('food'));
      expect(set.includes(const GalleryTagFilter('FOOD')), isTrue);
      set = set.flip(const GalleryTagFilter('food'));
      expect(set.excludes(const GalleryTagFilter('food')), isTrue);
      expect(set.length, 1);
      set = set.toggle(const GalleryTagFilter('food')); // excluded -> included
      expect(set.includes(const GalleryTagFilter('food')), isTrue);
      set = set.toggle(const GalleryTagFilter('food'));
      expect(set.isEmpty, isTrue);
    });

    test('JSON round trip of every kind', () {
      final set = GalleryFilterSet([
        const GalleryQueryFilter('x'),
        const GalleryTypeFilter(GalleryMediaType.raw),
        const GalleryDateFilter(2023, month: 7, day: 4),
        const GalleryTagFilter('a b'),
        GalleryPlaceFilter('x${paris.placeCell}', placeLabel: '48.9°N 2.4°E', reversed: true),
        const GalleryCameraFilter('Canon EOS'),
        const GalleryOrientationFilter(GalleryOrientation.square),
        const GalleryRatingFilter(2),
        const GallerySizeFilter(GallerySizeClass.medium),
        const GalleryFolderFilter(3, 'a/b'),
        const GalleryMissingFilter(GalleryMissing.tags),
      ]);
      expect(GalleryFilterSet.fromJson(set.toJson()), set);
      expect(GalleryFilterSet.fromJson('nonsense'), GalleryFilterSet.empty);
      expect(GalleryFilterSet.fromJson([{'t': 'unknown'}, 5]).isEmpty, isTrue);
    });
  });

  group('facets', () {
    test('count what each filter would show', () {
      final f = GalleryFacets.compute([a, b, c, d]);
      expect(f.total, 4);
      expect(f.years.map((e) => (e.filter as GalleryDateFilter).year), [2023, 2022]);
      final holiday = f.tags.firstWhere((e) => e.filter.label(const GalleryFilterLabels()).toLowerCase() == 'holiday');
      expect(holiday.count, 2); // "Holiday" and "holiday" are one tag
      expect(f.places.length, 2);
      expect(f.cameras.length, 2);
      expect(f.sizes.any((e) => (e.filter as GallerySizeFilter).sizeClass == GallerySizeClass.large), isTrue);
      expect(f.missing.firstWhere((e) => (e.filter as GalleryMissingFilter).what == GalleryMissing.location).count, 2);
    });
  });

  group('grouping', () {
    List<RawEntry> entries() => [
      RawEntry(name: 'a', isDir: false, sizeBytes: 0, modifiedSecs: 0),
      RawEntry(name: 'b', isDir: false, sizeBytes: 0, modifiedSecs: 0),
      RawEntry(name: 'c', isDir: false, sizeBytes: 0, modifiedSecs: 0),
      RawEntry(name: 'd', isDir: false, sizeBytes: 0, modifiedSecs: 0),
    ];
    final subjects = {'a': a, 'b': b, 'c': c, 'd': d};
    GalleryGrouper grouper(GalleryGroupBy by, {bool asc = false}) => GalleryGrouper(
      by: by,
      subjectOf: (e) => subjects[e.name]!,
      ascending: asc,
    );

    test('year groups are newest first, undated last', () {
      final groups = grouper(GalleryGroupBy.year)(entries());
      expect(groups.map((g) => g.label), ['2023', '2022', null]); // null: the translated "Earlier" header
      expect(groups.first.items.map((e) => e.name), ['a', 'c']); // c's file date is in 2023 too
      expect(groups.map((g) => g.items.length).reduce((x, y) => x + y), 4);
    });

    test('ascending flips date groups', () {
      final groups = grouper(GalleryGroupBy.year, asc: true)(entries());
      expect(groups.first.label, '2022');
    });

    test('folder groups are alphabetical and each item is in exactly one', () {
      final groups = grouper(GalleryGroupBy.folder)(entries());
      expect(groups.map((g) => g.label), ['Clips', 'Misc', 'Trips/Paris', 'Trips/Rome']);
    });

    test('place group puts photos without location last', () {
      final groups = grouper(GalleryGroupBy.place)(entries());
      expect(groups.last.label, 'No location');
      expect(groups.last.items.map((e) => e.name), ['c', 'd']);
    });

    test('arrange makes each group one run and keeps global indices valid', () {
      final g = grouper(GalleryGroupBy.place);
      final arranged = g.arrange(entries());
      expect(arranged.map((e) => e.name).toList().sublist(2), ['c', 'd']);
      final groups = g(arranged);
      var next = 0;
      for (final grp in groups) {
        for (final i in grp.globalIndices) {
          expect(i, next++); // contiguous: group runs follow the list order
        }
      }
    });
  });
}
