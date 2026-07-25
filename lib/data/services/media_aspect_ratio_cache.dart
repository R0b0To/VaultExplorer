import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';

/// Session-lived cache of each media file's *true* content aspect ratio
/// (width / height), as reported directly by native's
/// `getImageThumbnailWithSize` / `getVideoThumbnailWithSize` (see
/// [ThumbnailWithSize]) — never decoded on the Dart side.
///
/// Native already computes these bounds while producing the thumbnail
/// itself (the `inJustDecodeBounds` pass for images picks a downscale
/// sample size; the extracted frame's own dimensions for video), so having
/// it report them back is a free byproduct of work it's already doing — no
/// extra decode anywhere, native or Dart. This cache exists purely to avoid
/// asking native again for a file whose ratio this session has already
/// learned (e.g. scrolling back into a directory already visited).
///
/// Keyed the same way as `ThumbnailCacheService`'s memory tier
/// (volId + mountedAt + path) so a new container session never serves a
/// stale ratio left over from a previous mount into the same slot.
class MediaAspectRatioCache {
  MediaAspectRatioCache._();
  static final _cache = LruCache<String, double>(2000);

  // Use container.uri + filePath so the key persists across lock/unlock cycles
  static String _key(MountedContainer container, String filePath) =>
      '${container.uri}:$filePath';

  static double? get(MountedContainer container, String filePath) =>
      _cache[_key(container, filePath)];

  static void put(
    MountedContainer container,
    String filePath,
    int width,
    int height,
  ) {
    if (width <= 0 || height <= 0) return;
    _cache[_key(container, filePath)] = width / height;
  }

  static void clear() => _cache.clear();
}