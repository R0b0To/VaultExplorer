import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

/// How aggressively [CacheCoordinator.trimAll] should shed memory-tier
/// cache contents.
///
/// Deliberately just two levels rather than mirroring Android's full
/// `TRIM_MEMORY_*` granularity (5 levels) or iOS's single
/// `didHaveMemoryPressure` signal 1:1 — every caller maps its own native
/// signal down to whichever of these two best matches "shed some, we might
/// need it again soon" vs. "shed nearly all of it, this is serious."
enum TrimLevel {
  /// A temporary, partial trim — e.g. Android's `TRIM_MEMORY_RUNNING_LOW`/
  /// `TRIM_MEMORY_RUNNING_MODERATE`, or the app moving to the background.
  /// Sheds roughly half of what's currently resident in each memory-tier
  /// cache; on-disk tiers and anything needed for correctness (not just
  /// convenience) are untouched.
  moderate,

  /// A severe trim — e.g. Android's `TRIM_MEMORY_RUNNING_CRITICAL`/
  /// `TRIM_MEMORY_COMPLETE`, or iOS's `didHaveMemoryPressure`. Sheds nearly
  /// everything reclaimable from every memory-tier cache. Still never
  /// touches disk (that's what [ThumbnailCacheMode.disabled]'s privacy
  /// guarantee and the on-disk eviction policy in `ThumbnailCacheService`
  /// are for, not this).
  severe,
}

/// Single fan-out point for "the OS says memory is tight, shed what you can
/// spare" — Findings F-14/F-15, ADR-011.
///
/// Before this existed, [LruCache.trimToFraction] and
/// [ByteBudgetCache.trimToFraction] were added to every memory-tier cache
/// in anticipation of exactly this class (their own doc comments already
/// forward-referenced `CacheCoordinator.trimAll`), but nothing actually
/// called them and no memory-pressure signal existed anywhere in the app.
/// This class is that caller, and [MainActivity.onTrimMemory] /
/// `WidgetsBindingObserver.didHaveMemoryPressure` (see
/// `lib/app/memory_pressure_observer.dart`) are the two signals that invoke
/// it.
///
/// Deliberately trims every cache in Section 4 of architecture.md that has
/// a memory-tier component — [ThumbnailConcurrency.inFlightThumbnails],
/// [ThumbnailCacheService]'s in-memory tier, and [FullResImageCache] — with
/// the *same* [fraction] semantics ("fraction of what's currently held,"
/// see Finding F-17), so one call here has a predictable, uniform effect
/// regardless of which underlying cache type backs a given tier.
/// [MediaAspectRatioCache]/[MediaRotationCache] are deliberately excluded:
/// they're small (capped at 2000 entries of a double/int each — a few tens
/// of KB, not worth the churn) and Ownership Rule 5 already treats them as
/// harmless to keep warm.
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
