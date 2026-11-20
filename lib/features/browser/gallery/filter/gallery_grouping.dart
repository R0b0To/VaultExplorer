import 'package:intl/intl.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/widgets/gallery_date_header.dart';

import 'gallery_filter_labels.dart';
import 'gallery_filters.dart';

/// What the gallery's sections are made of.
enum GalleryGroupBy {
  /// One flat grid, no headers.
  none,
  day,
  month,
  year,
  folder,
  type,
  place,
  camera;

  bool get isDate =>
      this == GalleryGroupBy.day ||
      this == GalleryGroupBy.month ||
      this == GalleryGroupBy.year;

  static GalleryGroupBy fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return GalleryGroupBy.day;
  }
}

typedef GallerySubjectOf = GalleryFilterSubject Function(RawEntry entry);

/// Splits a list of gallery files into the sections of one [GalleryGroupBy].
///
/// Each file belongs to exactly one section. Items keep their relative order
/// inside a section, and the sections are ordered by date (newest first, or
/// oldest first when [ascending]) for the date groupings and by name for the
/// rest, with the section of files that lack the information last.
class GalleryGrouper {
  const GalleryGrouper({
    required this.by,
    required this.subjectOf,
    this.ascending = false,
    this.labels = const GalleryFilterLabels(),
  });

  final GalleryGroupBy by;
  final GallerySubjectOf subjectOf;
  final bool ascending;
  final GalleryFilterLabels labels;

  List<DateGroup<RawEntry>> call(List<RawEntry> items) {
    if (items.isEmpty) return const [];
    final groups = <String, _Bucket>{};

    // Run caching to avoid repeated DateTime, DateFormat and String allocations
    // across tens of thousands of items in typical photo libraries.
    int? lastY, lastM, lastD;
    _Info? lastDayInfo;
    int? lastMonthY, lastMonthM;
    _Info? lastMonthInfo;
    int? lastYearY;
    _Info? lastYearInfo;
    String? lastFolderPath;
    int? lastFolderVol;
    _Info? lastFolderInfo;
    final typeInfos = by == GalleryGroupBy.type
        ? <GalleryMediaType, _Info>{
            for (final t in GalleryMediaType.values)
              t: _Info(t.name, labels.typeLabel(t), null, false),
          }
        : null;

    _Info classify(GalleryFilterSubject s) {
      switch (by) {
        case GalleryGroupBy.none:
          return const _Info('all', '', null, false);
        case GalleryGroupBy.day:
          final d = s.date;
          if (d == null) return _unknownDate;
          if (d.year == lastY && d.month == lastM && d.day == lastD && lastDayInfo != null) {
            return lastDayInfo!;
          }
          final day = DateTime(d.year, d.month, d.day);
          lastY = d.year;
          lastM = d.month;
          lastD = d.day;
          return lastDayInfo = _Info('d${day.millisecondsSinceEpoch}', '', day, false);
        case GalleryGroupBy.month:
          final d = s.date;
          if (d == null) return _unknownDate;
          if (d.year == lastMonthY && d.month == lastMonthM && lastMonthInfo != null) {
            return lastMonthInfo!;
          }
          final month = DateTime(d.year, d.month);
          lastMonthY = d.year;
          lastMonthM = d.month;
          return lastMonthInfo = _Info(
            'm${month.millisecondsSinceEpoch}',
            DateFormat.yMMMM(labels.locale).format(month),
            month,
            false,
          );
        case GalleryGroupBy.year:
          final d = s.date;
          if (d == null) return _unknownDate;
          if (d.year == lastYearY && lastYearInfo != null) {
            return lastYearInfo!;
          }
          final yearDate = DateTime(d.year);
          lastYearY = d.year;
          return lastYearInfo = _Info('y${d.year}', '${d.year}', yearDate, false);
        case GalleryGroupBy.folder:
          if (s.sourceVolId == lastFolderVol && s.parentPath == lastFolderPath && lastFolderInfo != null) {
            return lastFolderInfo!;
          }
          final label = s.parentPath.isEmpty ? '/' : s.parentPath;
          final info = _Info('f${s.sourceVolId}:${s.parentPath}', label, null, false);
          lastFolderVol = s.sourceVolId;
          lastFolderPath = s.parentPath;
          return lastFolderInfo = info;
        case GalleryGroupBy.type:
          return typeInfos![s.mediaType]!;
        case GalleryGroupBy.place:
          final place = s.place;
          if (place == null) return _Info('?', labels.noLocation, null, true);
          return _Info('p${place.key}', place.label, null, false);
        case GalleryGroupBy.camera:
          final cam = s.meta.camera;
          if (cam == null) return _Info('?', labels.noCameraInfo, null, true);
          return _Info('c${cam.toLowerCase()}', cam, null, false);
      }
    }

    for (var i = 0; i < items.length; i++) {
      final subject = subjectOf(items[i]);
      final info = classify(subject);
      final bucket = groups.putIfAbsent(info.key, () => _Bucket(info));
      bucket.items.add(items[i]);
      bucket.indices.add(i);
    }

    final buckets = groups.values.toList()
      ..sort((a, b) {
        if (a.info.unknown != b.info.unknown) return a.info.unknown ? 1 : -1;
        if (by.isDate) {
          final c = a.info.sortDate!.compareTo(b.info.sortDate!);
          return ascending ? c : -c;
        }
        return a.info.label.toLowerCase().compareTo(b.info.label.toLowerCase());
      });

    return [
      for (final b in buckets)
        DateGroup<RawEntry>(
          date: b.info.sortDate,
          // Day sections, and any date section without a date, keep the
          // translated headers of GalleryDateHeader ("Today", "Earlier"...).
          label: by == GalleryGroupBy.day || (by.isDate && b.info.unknown)
              ? null
              : b.info.label,
          items: b.items,
          globalIndices: b.indices,
        ),
    ];
  }

  /// [items] reordered so that every section is one run, in section order:
  /// what a gallery needs so that "the n-th tile" and "the next tile" mean
  /// what they look like on screen.
  List<T> arrange<T extends RawEntry>(List<T> items) {
    if (by == GalleryGroupBy.none || items.isEmpty) return items;
    final groups = call(items);
    return [
      for (final g in groups)
        for (final e in g.items) e as T,
    ];
  }

  /// [arrange] and the groups of the arranged list in one pass.
  ///
  /// Grouping reads the subject of every file (a metadata lookup and an
  /// allocation each), so a view that needs both the order and the sections
  /// should not pay for it twice: the groups returned here are already
  /// expressed in the arranged order (`globalIndices` are the positions in
  /// `items`), which is exactly what `call(items)` would return for it.
  ({List<T> items, List<DateGroup<RawEntry>> groups}) arrangeWithGroups<
    T extends RawEntry
  >(List<T> items) {
    if (by == GalleryGroupBy.none || items.isEmpty) {
      return (items: items, groups: const []);
    }
    final groups = call(items);
    final arranged = <T>[];
    final rebased = <DateGroup<RawEntry>>[];
    for (final g in groups) {
      final start = arranged.length;
      for (final e in g.items) {
        arranged.add(e as T);
      }
      rebased.add(
        DateGroup<RawEntry>(
          date: g.date,
          label: g.label,
          items: g.items,
          globalIndices: List<int>.generate(g.items.length, (k) => start + k),
        ),
      );
    }
    return (items: arranged, groups: rebased);
  }

  static const _unknownDate = _Info('?', '', null, true);
}

class _Info {
  const _Info(this.key, this.label, this.sortDate, this.unknown);
  final String key;
  final String label;
  final DateTime? sortDate;
  final bool unknown;
}

class _Bucket {
  _Bucket(this.info);
  final _Info info;
  final List<RawEntry> items = [];
  final List<int> indices = [];
}
