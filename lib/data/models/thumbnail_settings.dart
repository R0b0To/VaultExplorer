import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';

/// One complete set of thumbnail preferences: where thumbnails are cached
/// ([cacheMode]) and how they are rendered ([quality]).
///
/// The two are always chosen together, so every place that stores, resolves
/// or edits thumbnail preferences works with this value instead of two loose
/// fields. That is what keeps the app-wide default, a vault's own override
/// and the Local Storage slot from drifting apart (for example a copy that
/// carries the mode but forgets the quality).
///
/// A *missing* [ThumbnailSettings] (null) is how a scope says "I have no
/// settings of my own, use the parent's". Consumers of thumbnails (the
/// viewer, the prefetch controller, the cache service) only ever see a
/// resolved, concrete value -- see `resolveThumbnailSettings`.
@immutable
class ThumbnailSettings {
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;

  const ThumbnailSettings({required this.cacheMode, required this.quality});

  /// The out-of-the-box values: no disk cache, default quality.
  static const ThumbnailSettings defaults = ThumbnailSettings(
    cacheMode: ThumbnailCacheMode.disabled,
    quality: ThumbnailQuality.defaultQuality,
  );

  ThumbnailSettings copyWith({
    ThumbnailCacheMode? cacheMode,
    ThumbnailQuality? quality,
  }) => ThumbnailSettings(
    cacheMode: cacheMode ?? this.cacheMode,
    quality: quality ?? this.quality,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThumbnailSettings &&
          other.cacheMode == cacheMode &&
          other.quality == quality;

  @override
  int get hashCode => Object.hash(cacheMode, quality);

  @override
  String toString() =>
      'ThumbnailSettings(${cacheMode.name}, ${quality.label})';
}
