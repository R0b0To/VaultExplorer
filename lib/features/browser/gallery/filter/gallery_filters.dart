import 'package:intl/intl.dart';

import 'gallery_filter_labels.dart';
import 'gallery_meta.dart';
import 'gallery_places.dart';

/// Everything a filter may look at for one gallery file. A plain value (no
/// widgets, no listing types) so the filters are testable on their own.
class GalleryFilterSubject {
  const GalleryFilterSubject({
    required this.sourceVolId,
    required this.name,
    required this.parentPath,
    required this.extension,
    required this.sizeBytes,
    required this.modifiedSecs,
    this.meta = GalleryMeta.empty,
    this.place,
  });

  final int sourceVolId;

  /// File name only (no folders).
  final String name;

  /// Folder inside its source ('' for the root).
  final String parentPath;

  /// Lower case, without the dot.
  final String extension;
  final int sizeBytes;
  final int modifiedSecs;
  final GalleryMeta meta;

  /// Where it was taken (nearest city, else coordinates); null without GPS.
  final GalleryPlace? place;

  /// Pixel size when the file header said (photos only).
  int? get width => meta.width;
  int? get height => meta.height;

  /// The date the gallery files this photo under: the date it was taken when
  /// the file says so, else its modified date. A zone-less wall-clock value.
  DateTime? get date {
    final taken = meta.takenWallClock;
    if (taken != null) {
      return DateTime(
        taken.year,
        taken.month,
        taken.day,
        taken.hour,
        taken.minute,
        taken.second,
      );
    }
    if (modifiedSecs <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(modifiedSecs * 1000);
  }

  bool get hasTakenDate => meta.takenSecs != null;

  GalleryMediaType get mediaType => galleryMediaTypeOf(extension);

  String get lowercaseName => name.toLowerCase();
}

enum GalleryMediaType { photo, video, animated, raw }

extension GalleryMediaTypeLabels on GalleryFilterLabels {
  String typeLabel(GalleryMediaType t) => switch (t) {
    GalleryMediaType.photo => photos,
    GalleryMediaType.video => videos,
    GalleryMediaType.animated => animated,
    GalleryMediaType.raw => raw,
  };
}

const Set<String> _videoExtensions = {
  'mp4', 'm4v', 'mkv', 'webm', 'mov', 'avi', '3gp', '3g2', 'wmv', 'flv', 'ts', 'mts', 'm2ts', 'mpg', 'mpeg', 'ogv',
};
const Set<String> _rawExtensions = {
  'dng', 'cr2', 'cr3', 'nef', 'nrw', 'arw', 'sr2', 'orf', 'rw2', 'raf', 'pef', 'srw', 'x3f', 'raw',
};
const Set<String> _animatedExtensions = {'gif'};

GalleryMediaType galleryMediaTypeOf(String extension) {
  if (_videoExtensions.contains(extension)) return GalleryMediaType.video;
  if (_rawExtensions.contains(extension)) return GalleryMediaType.raw;
  if (_animatedExtensions.contains(extension)) return GalleryMediaType.animated;
  return GalleryMediaType.photo;
}

/// How filters group: filters of different kinds must all match; filters of
/// the same kind are alternatives (two tags show photos with either tag),
/// which is what a person adding a second tag means. Excluded ("not")
/// filters always remove, whatever the kind.
enum GalleryFilterKind {
  query,
  type,
  date,
  tag,
  place,
  camera,
  orientation,
  rating,
  size,
  folder,
  missing,
}

abstract class GalleryFilter {
  const GalleryFilter({this.reversed = false});

  /// An excluded filter: matches what the positive filter does not.
  final bool reversed;

  GalleryFilterKind get kind;

  /// Stable identity (also the persistence key's body).
  String get id;

  String get key => '${reversed ? '!' : ''}$id';

  bool positive(GalleryFilterSubject s);

  bool matches(GalleryFilterSubject s) => reversed ? !positive(s) : positive(s);

  /// Short label for chips and headers, in the language of [l].
  String label(GalleryFilterLabels l);

  GalleryFilter withReversed(bool value);

  GalleryFilter toggled() => withReversed(!reversed);

  Map<String, Object?> toJson();

  static GalleryFilter? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final reversed = raw['not'] == true;
    switch (raw['t']) {
      case 'q':
        final v = raw['v'];
        return v is String && v.trim().isNotEmpty
            ? GalleryQueryFilter(v, reversed: reversed)
            : null;
      case 'type':
        final i = raw['v'];
        return i is int && i >= 0 && i < GalleryMediaType.values.length
            ? GalleryTypeFilter(GalleryMediaType.values[i], reversed: reversed)
            : null;
      case 'date':
        final y = raw['y'];
        final m = raw['m'];
        final d = raw['d'];
        return y is int
            ? GalleryDateFilter(
                y,
                month: m is int ? m : null,
                day: d is int ? d : null,
                reversed: reversed,
              )
            : null;
      case 'tag':
        final v = raw['v'];
        return v is String ? GalleryTagFilter(v, reversed: reversed) : null;
      case 'place':
        final v = raw['v'];
        final l = raw['l'];
        return v is String
            ? GalleryPlaceFilter(v, placeLabel: l is String ? l : null, reversed: reversed)
            : null;
      case 'cam':
        final v = raw['v'];
        return v is String ? GalleryCameraFilter(v, reversed: reversed) : null;
      case 'ori':
        final i = raw['v'];
        return i is int && i >= 0 && i < GalleryOrientation.values.length
            ? GalleryOrientationFilter(GalleryOrientation.values[i], reversed: reversed)
            : null;
      case 'rate':
        final v = raw['v'];
        return v is int ? GalleryRatingFilter(v, reversed: reversed) : null;
      case 'size':
        final i = raw['v'];
        return i is int && i >= 0 && i < GallerySizeClass.values.length
            ? GallerySizeFilter(GallerySizeClass.values[i], reversed: reversed)
            : null;
      case 'dir':
        final v = raw['v'];
        final vol = raw['vol'];
        return v is String && vol is int
            ? GalleryFolderFilter(vol, v, reversed: reversed)
            : null;
      case 'miss':
        final i = raw['v'];
        return i is int && i >= 0 && i < GalleryMissing.values.length
            ? GalleryMissingFilter(GalleryMissing.values[i], reversed: reversed)
            : null;
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is GalleryFilter && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Free text: matches the file name, its folder, tags, camera and place.
class GalleryQueryFilter extends GalleryFilter {
  const GalleryQueryFilter(this.text, {super.reversed});
  final String text;

  @override
  GalleryFilterKind get kind => GalleryFilterKind.query;
  @override
  String get id => 'q:${text.trim().toLowerCase()}';

  @override
  bool positive(GalleryFilterSubject s) {
    final q = text.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (s.lowercaseName.contains(q)) return true;
    if (s.parentPath.toLowerCase().contains(q)) return true;
    for (final t in s.meta.tags) {
      if (t.toLowerCase().contains(q)) return true;
    }
    final cam = s.meta.camera;
    if (cam != null && cam.toLowerCase().contains(q)) return true;
    if (s.place?.label.toLowerCase().contains(q) ?? false) return true;
    return false;
  }

  @override
  String label(GalleryFilterLabels l) => '"${text.trim()}"';
  @override
  GalleryFilter withReversed(bool v) => GalleryQueryFilter(text, reversed: v);
  @override
  Map<String, Object?> toJson() => {'t': 'q', 'v': text, if (reversed) 'not': true};
}

class GalleryTypeFilter extends GalleryFilter {
  const GalleryTypeFilter(this.type, {super.reversed});
  final GalleryMediaType type;

  @override
  GalleryFilterKind get kind => GalleryFilterKind.type;
  @override
  String get id => 'type:${type.name}';
  @override
  bool positive(GalleryFilterSubject s) => s.mediaType == type;

  @override
  String label(GalleryFilterLabels l) => l.typeLabel(type);
  @override
  GalleryFilter withReversed(bool v) => GalleryTypeFilter(type, reversed: v);
  @override
  Map<String, Object?> toJson() => {'t': 'type', 'v': type.index, if (reversed) 'not': true};
}

/// A year, a month of a year, or one day.
class GalleryDateFilter extends GalleryFilter {
  const GalleryDateFilter(this.year, {this.month, this.day, super.reversed});
  final int year;
  final int? month;
  final int? day;

  @override
  GalleryFilterKind get kind => GalleryFilterKind.date;
  @override
  String get id => 'date:$year-${month ?? 0}-${day ?? 0}';

  @override
  bool positive(GalleryFilterSubject s) {
    final d = s.date;
    if (d == null || d.year != year) return false;
    if (month != null && d.month != month) return false;
    if (day != null && d.day != day) return false;
    return true;
  }

  @override
  String label(GalleryFilterLabels l) {
    if (month == null) return '$year';
    if (day == null) return DateFormat.yMMMM(l.locale).format(DateTime(year, month!));
    return DateFormat.yMMMd(l.locale).format(DateTime(year, month!, day!));
  }

  @override
  GalleryFilter withReversed(bool v) =>
      GalleryDateFilter(year, month: month, day: day, reversed: v);
  @override
  Map<String, Object?> toJson() => {
    't': 'date',
    'y': year,
    if (month != null) 'm': month,
    if (day != null) 'd': day,
    if (reversed) 'not': true,
  };
}

class GalleryTagFilter extends GalleryFilter {
  const GalleryTagFilter(this.tag, {super.reversed});
  final String tag;

  @override
  GalleryFilterKind get kind => GalleryFilterKind.tag;
  @override
  String get id => 'tag:${tag.toLowerCase()}';
  @override
  bool positive(GalleryFilterSubject s) {
    final t = tag.toLowerCase();
    for (final x in s.meta.tags) {
      if (x.toLowerCase() == t) return true;
    }
    return false;
  }

  @override
  String label(GalleryFilterLabels l) => tag;
  @override
  GalleryFilter withReversed(bool v) => GalleryTagFilter(tag, reversed: v);
  @override
  Map<String, Object?> toJson() => {'t': 'tag', 'v': tag, if (reversed) 'not': true};
}

/// One place: a city or, far from any city, a coordinate cell (see
/// [GalleryPlace]). [label] is what the chip shows; it is not part of the
/// identity.
class GalleryPlaceFilter extends GalleryFilter {
  const GalleryPlaceFilter(this.placeKey, {this.placeLabel, super.reversed});

  /// The [GalleryPlace.key].
  final String placeKey;
  final String? placeLabel;

  @override
  GalleryFilterKind get kind => GalleryFilterKind.place;
  @override
  String get id => 'place:$placeKey';
  @override
  bool positive(GalleryFilterSubject s) => s.place?.key == placeKey;
  @override
  String label(GalleryFilterLabels l) => placeLabel ?? placeKey;
  @override
  GalleryFilter withReversed(bool v) =>
      GalleryPlaceFilter(placeKey, placeLabel: placeLabel, reversed: v);
  @override
  Map<String, Object?> toJson() => {
    't': 'place',
    'v': placeKey,
    if (placeLabel != null) 'l': placeLabel,
    if (reversed) 'not': true,
  };
}

class GalleryCameraFilter extends GalleryFilter {
  const GalleryCameraFilter(this.camera, {super.reversed});
  final String camera;

  @override
  GalleryFilterKind get kind => GalleryFilterKind.camera;
  @override
  String get id => 'cam:${camera.toLowerCase()}';
  @override
  bool positive(GalleryFilterSubject s) =>
      s.meta.camera?.toLowerCase() == camera.toLowerCase();
  @override
  String label(GalleryFilterLabels l) => camera;
  @override
  GalleryFilter withReversed(bool v) => GalleryCameraFilter(camera, reversed: v);
  @override
  Map<String, Object?> toJson() => {'t': 'cam', 'v': camera, if (reversed) 'not': true};
}

enum GalleryOrientation { landscape, portrait, square }

/// Needs the pixel size, read from the photo's header; videos and files not
/// read yet match none of the three.
class GalleryOrientationFilter extends GalleryFilter {
  const GalleryOrientationFilter(this.orientation, {super.reversed});
  final GalleryOrientation orientation;

  @override
  GalleryFilterKind get kind => GalleryFilterKind.orientation;
  @override
  String get id => 'ori:${orientation.name}';
  @override
  bool positive(GalleryFilterSubject s) {
    final w = s.width;
    final h = s.height;
    if (w == null || h == null || w <= 0 || h <= 0) return false;
    return switch (orientation) {
      GalleryOrientation.landscape => w > h,
      GalleryOrientation.portrait => h > w,
      GalleryOrientation.square => w == h,
    };
  }

  @override
  String label(GalleryFilterLabels l) => switch (orientation) {
    GalleryOrientation.landscape => l.landscape,
    GalleryOrientation.portrait => l.portrait,
    GalleryOrientation.square => l.square,
  };
  @override
  GalleryFilter withReversed(bool v) => GalleryOrientationFilter(orientation, reversed: v);
  @override
  Map<String, Object?> toJson() => {'t': 'ori', 'v': orientation.index, if (reversed) 'not': true};
}

/// Photos rated at least [stars] (1..5).
class GalleryRatingFilter extends GalleryFilter {
  const GalleryRatingFilter(this.stars, {super.reversed});
  final int stars;

  @override
  GalleryFilterKind get kind => GalleryFilterKind.rating;
  @override
  String get id => 'rate:$stars';
  @override
  bool positive(GalleryFilterSubject s) => (s.meta.rating ?? 0) >= stars;
  @override
  String label(GalleryFilterLabels l) => '$stars+ ★';
  @override
  GalleryFilter withReversed(bool v) => GalleryRatingFilter(stars, reversed: v);
  @override
  Map<String, Object?> toJson() => {'t': 'rate', 'v': stars, if (reversed) 'not': true};
}

enum GallerySizeClass { small, medium, large }

class GallerySizeFilter extends GalleryFilter {
  const GallerySizeFilter(this.sizeClass, {super.reversed});
  final GallerySizeClass sizeClass;

  static const int mb = 1024 * 1024;

  @override
  GalleryFilterKind get kind => GalleryFilterKind.size;
  @override
  String get id => 'size:${sizeClass.name}';
  @override
  bool positive(GalleryFilterSubject s) => switch (sizeClass) {
    GallerySizeClass.small => s.sizeBytes < mb,
    GallerySizeClass.medium => s.sizeBytes >= mb && s.sizeBytes < 10 * mb,
    GallerySizeClass.large => s.sizeBytes >= 10 * mb,
  };
  @override
  String label(GalleryFilterLabels l) => switch (sizeClass) {
    GallerySizeClass.small => l.sizeSmall,
    GallerySizeClass.medium => l.sizeMedium,
    GallerySizeClass.large => l.sizeLarge,
  };
  @override
  GalleryFilter withReversed(bool v) => GallerySizeFilter(sizeClass, reversed: v);
  @override
  Map<String, Object?> toJson() => {'t': 'size', 'v': sizeClass.index, if (reversed) 'not': true};
}

/// Files directly in one folder of one source.
class GalleryFolderFilter extends GalleryFilter {
  const GalleryFolderFilter(this.sourceVolId, this.path, {super.reversed});
  final int sourceVolId;
  final String path;

  @override
  GalleryFilterKind get kind => GalleryFilterKind.folder;
  @override
  String get id => 'dir:$sourceVolId:$path';
  @override
  bool positive(GalleryFilterSubject s) =>
      s.sourceVolId == sourceVolId && s.parentPath == path;
  @override
  String label(GalleryFilterLabels l) {
    if (path.isEmpty) return '/';
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  @override
  GalleryFilter withReversed(bool v) => GalleryFolderFilter(sourceVolId, path, reversed: v);
  @override
  Map<String, Object?> toJson() => {
    't': 'dir',
    'vol': sourceVolId,
    'v': path,
    if (reversed) 'not': true,
  };
}

enum GalleryMissing { location, tags, camera, dateTaken }

/// Photos that lack something: handy to find what still needs tagging or
/// whose origin is unknown.
class GalleryMissingFilter extends GalleryFilter {
  const GalleryMissingFilter(this.what, {super.reversed});
  final GalleryMissing what;

  @override
  GalleryFilterKind get kind => GalleryFilterKind.missing;
  @override
  String get id => 'miss:${what.name}';
  @override
  bool positive(GalleryFilterSubject s) => switch (what) {
    GalleryMissing.location => !s.meta.hasLocation,
    GalleryMissing.tags => s.meta.tags.isEmpty,
    GalleryMissing.camera => s.meta.camera == null,
    GalleryMissing.dateTaken => !s.hasTakenDate,
  };
  @override
  String label(GalleryFilterLabels l) => switch (what) {
    GalleryMissing.location => l.noLocation,
    GalleryMissing.tags => l.noTags,
    GalleryMissing.camera => l.noCameraInfo,
    GalleryMissing.dateTaken => l.noDateTaken,
  };
  @override
  GalleryFilter withReversed(bool v) => GalleryMissingFilter(what, reversed: v);
  @override
  Map<String, Object?> toJson() => {'t': 'miss', 'v': what.index, if (reversed) 'not': true};
}

/// The filters currently applied to the gallery. Immutable: every change
/// returns a new set, so a view can tell by identity whether it changed.
class GalleryFilterSet {
  const GalleryFilterSet([this.filters = const []]);

  static const GalleryFilterSet empty = GalleryFilterSet();

  final List<GalleryFilter> filters;

  bool get isEmpty => filters.isEmpty;
  bool get isNotEmpty => filters.isNotEmpty;
  int get length => filters.length;

  bool contains(GalleryFilter f) => filters.contains(f);

  /// Whether [f] is in the set in its positive form (not excluded).
  bool includes(GalleryFilter f) =>
      filters.any((x) => x.id == f.id && !x.reversed);

  bool excludes(GalleryFilter f) =>
      filters.any((x) => x.id == f.id && x.reversed);

  /// Adds [f]; an existing filter with the same identity (either form) is
  /// replaced, so a filter is never both required and excluded.
  GalleryFilterSet add(GalleryFilter f) => GalleryFilterSet([
    for (final x in filters)
      if (x.id != f.id) x,
    f,
  ]);

  GalleryFilterSet remove(GalleryFilter f) =>
      GalleryFilterSet([for (final x in filters) if (x.id != f.id) x]);

  /// Off -> on -> off for a filter chip.
  GalleryFilterSet toggle(GalleryFilter f) =>
      includes(f) ? remove(f) : add(f.withReversed(false));

  /// Excluded <-> included for a filter already in the set.
  GalleryFilterSet flip(GalleryFilter f) {
    final current = filters.where((x) => x.id == f.id);
    if (current.isEmpty) return add(f.withReversed(true));
    return add(current.first.toggled());
  }

  GalleryFilterSet clear() => empty;

  bool matches(GalleryFilterSubject s) {
    if (filters.isEmpty) return true;
    final alternatives = <GalleryFilterKind, bool>{};
    for (final f in filters) {
      if (f.reversed) {
        if (!f.matches(s)) return false;
      } else {
        alternatives[f.kind] = (alternatives[f.kind] ?? false) || f.positive(s);
      }
    }
    return alternatives.values.every((v) => v);
  }

  List<Object?> toJson() => [for (final f in filters) f.toJson()];

  static GalleryFilterSet fromJson(Object? raw) {
    if (raw is! List) return empty;
    return GalleryFilterSet([
      for (final e in raw)
        if (GalleryFilter.tryFromJson(e) case final f?) f,
    ]);
  }

  @override
  bool operator ==(Object other) {
    if (other is! GalleryFilterSet || other.filters.length != filters.length) {
      return false;
    }
    for (var i = 0; i < filters.length; i++) {
      if (filters[i] != other.filters[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(filters);
}
