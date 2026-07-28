import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart';

// Barrel export: TaskPriority and PriorityTaskQueue (ADR-010) live in
// priority_task_queue.dart, re-exported here so existing imports of this
// file (and of async_thumbnail.dart, which re-exports this file) keep
// working unchanged.
export 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart';

/// Suppresses the "unhandled future" lint for intentional fire-and-forget
/// background work.
void unawaited(Future<void> future) {
  future.catchError((Object e) {
    debugPrint('unawaited error (non-fatal): $e');
  });
}

/// Process-wide thumbnail concurrency primitives, shared by every surface
/// in the app (grid, masonry, list, carousel overlay, and the media
/// viewer's own prefetch) — see Ownership Rule 7 and ADR-001.
///
/// `imageLimiter`/`videoLimiter` used to be flat `ConcurrencyLimiter`s
/// (FIFO despite being documented as LIFO — Finding F-04; no priority
/// tiers — Finding F-05). They're now [PriorityTaskQueue]s implementing
/// ADR-010: LIFO within a tier, with a `visible` request able to preempt
/// queued `adjacent`/`background` slots, and playback-aware admission
/// (ADR-012, Finding F-06) via [PlaybackThrottleController].
///
/// `imageCache`/`videoCache` used to be two independent
/// `LruCache<String, Future<Uint8List>>` in-flight de-dup maps with no
/// shared accounting between them, and were bypassed entirely by the media
/// viewer's ad hoc prefetch path (Findings F-02, F-03, F-12). They're now
/// one shared [inFlightThumbnails] map used by every caller — safe to
/// share across image and video requests because cache keys already
/// encode container + mountedAt + path + quality, so two different files'
/// keys never collide and the same file is never requested as both an
/// image and a video thumbnail.
///
/// Capacities/concurrency here are scaled once at startup by
/// `DeviceCapabilityProfiler` (ADR-011) via [resizeForDevice] — the
/// hardcoded defaults below are the "unknown device" fallback.
class ThumbnailConcurrency {
  ThumbnailConcurrency._();

  static final imageLimiter = PriorityTaskQueue(2);
  static final videoLimiter = PriorityTaskQueue(1);

  static var inFlightThumbnails = LruCache<String, Future<Uint8List>>(160);

  /// Applies device-tier-scaled sizing (ADR-011). Called once from
  /// `runDeferredStartupWork()` after `DeviceCapabilityProfiler` resolves;
  /// safe to call again (e.g. if a future settings screen wants to expose
  /// a manual override) since every underlying primitive supports resize
  /// in place.
  static void resizeForDevice({
    required int imageConcurrency,
    required int videoConcurrency,
    required int inFlightCapacity,
  }) {
    imageLimiter.resize(imageConcurrency);
    videoLimiter.resize(videoConcurrency);
    inFlightThumbnails.resize(inFlightCapacity);
  }
}