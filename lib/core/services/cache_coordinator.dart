import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

/// How aggressively [CacheCoordinator.trimAll] should shed memory-tier
/// cache contents.
enum TrimLevel {
  moderate,

  severe,
}

class CacheCoordinator {
  CacheCoordinator._();

  static const double _moderateFraction = 0.5;
  static const double _severeFraction = 0.9;

  /// Sheds cache contents according to [level]. Safe to call as often as a
  /// native signal fires — every underlying `trimToFraction` call is a
  /// no-op on an already-empty/near-empty cache.
  static void trimAll(TrimLevel level) {
    final fraction =
        level == TrimLevel.moderate ? _moderateFraction : _severeFraction;
    ThumbnailConcurrency.inFlightThumbnails.trimToFraction(fraction);
    ThumbnailCacheService.trimMemoryToFraction(fraction);
    FullResImageCache.trimToFraction(fraction);
  }
}
