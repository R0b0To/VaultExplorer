import 'dart:async';
import 'dart:typed_data';

import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/byte_budget_cache.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';
import 'package:vaultexplorer/core/utils/retry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

export 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart'
    show TaskPriority;

/// In-memory cache for full-resolution decrypted image bytes, keyed per
/// container session (see [_key]).
///
/// This exists specifically to avoid re-decrypting and re-transferring a
/// full image file across the platform channel every time the user swipes
/// back to something they've already viewed in this session. It is
/// deliberately memory-only and not persisted to disk: unlike thumbnails,
/// full-resolution bytes are cheap to regenerate from the still-mounted
/// container (the native [ChunkedFileEngine] already keeps its own
/// decrypted-chunk cache and open-handle LRU), so there's no need to pay
/// disk-encryption overhead for a cache whose only job is to avoid redundant
/// work within a single viewing session.
///
/// Budgeted by total bytes rather than entry count, since photo file sizes
/// vary from a few hundred KB to tens of MB (or more for RAW) — see
/// [ByteBudgetCache].
class FullResImageCache {
  FullResImageCache._();

  /// ~150 MB in-memory budget. Generous enough to hold a meaningful chunk of
  /// a playlist's worth of photos, small relative to typical device RAM, and
  /// self-limiting since single files larger than this are simply not cached
  /// (see [ByteBudgetCache]).
  static const int _maxTotalBytes = 150 * 1024 * 1024;

  static final _cache = ByteBudgetCache(_maxTotalBytes);

  static String _key(MountedContainer container, String filePath) =>
      '${container.volId}:${container.mountedAt.millisecondsSinceEpoch}:$filePath';

  static Uint8List? get(MountedContainer container, String filePath) =>
      _cache[_key(container, filePath)];

  static void put(
    MountedContainer container,
    String filePath,
    Uint8List data,
  ) =>
      _cache[_key(container, filePath)] = data;

  static bool contains(MountedContainer container, String filePath) =>
      _cache.containsKey(_key(container, filePath));

  static void invalidate(MountedContainer container, String filePath) =>
      _cache.remove(_key(container, filePath));

  /// Clears all cached full-resolution bytes. Call this on container
  /// lock/unmount to release memory promptly rather than waiting for LRU
  /// eviction or process death.
  static void clear() => _cache.clear();

  static void resize(int newMaxTotalBytes) => _cache.resize(newMaxTotalBytes);

  /// Evicts [fraction] of currently-held bytes, oldest-first, without
  /// permanently lowering the budget — the full-res half of
  /// `CacheCoordinator.trimAll` (Finding F-15 / ADR-011).
  static void trimToFraction(double fraction) => _cache.trimToFraction(fraction);

  // --------------------------------------------------------------------
  // Concurrency gate
  // --------------------------------------------------------------------
  static final limiter = PriorityTaskQueue(2);

  /// In-flight de-dup so a widget-triggered load and a screen-triggered
  /// prefetch for the same file collapse into one native call instead of
  /// racing each other.
  static final _inFlight = LruCache<String, Future<Uint8List?>>(8);

  /// Fetches full-resolution bytes for [filePath], honoring the cache,
  /// de-duplicating concurrent requests for the same file, and gating the
  /// actual native call through [limiter].
  ///
  /// [completer] is the caller's own limiter-queue ticket -- hang onto it
  /// and pass it to `FullResImageCache.limiter.cancel(completer)` (e.g. on
  /// dispose or when moving on to a different file) to drop out of the
  /// queue if this specific caller stops caring while still waiting for a
  /// turn. Only the caller that's still waiting (hasn't been granted a
  /// turn yet) is affected -- if another caller is already relying on the
  /// same in-flight fetch, cancelling here doesn't touch it.
  ///
  /// [isStillWanted] is re-checked once a turn is granted and again before
  /// the network/decrypt round trip, so a request that waited through the
  /// queue still bails before paying for the native call if it's gone
  /// stale by then.
  static Future<Uint8List?> fetch(
    MountedContainer container,
    String filePath,
    Completer<void> completer, {
    required bool Function() isStillWanted,
    TaskPriority priority = TaskPriority.visible,
  }) {
    final cached = get(container, filePath);
    if (cached != null) return Future.value(cached);

    final key = _key(container, filePath);
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future =
        _runGated(container, filePath, key, completer, isStillWanted, priority);
    _inFlight[key] = future;
    return future;
  }

  static Future<Uint8List?> _runGated(
    MountedContainer container,
    String filePath,
    String key,
    Completer<void> completer,
    bool Function() isStillWanted,
    TaskPriority priority,
  ) async {
    bool acquired = false;
    try {
      await limiter.acquire(completer, priority: priority);
      acquired = true;
      if (!isStillWanted()) return null;

      // Bounded exponential-backoff retry (Finding F-11) -- this used to be
      // a flat 300ms delay between all 3 attempts, unlike the thumbnail
      // path's retry helper. Both now share the same backoff curve. A
      // genuine failure that survives every retry still propagates to the
      // caller (existing callers already catch this); going stale
      // (isStillWanted() turning false) short-circuits to null instead of
      // being reported as a fetch error.
      Uint8List? result;
      try {
        result = await retryWithBackoff<Uint8List>((attempt) async {
          if (!isStillWanted()) throw _StaleRequestException();
          final size =
              await vaultExplorerApi.getMediaFileSize(container, filePath);
          if (size <= 0) throw Exception('File size is empty');
          if (!isStillWanted()) throw _StaleRequestException();

          final data = await vaultExplorerApi.readMediaFileChunk(
              container, filePath, 0, size);
          if (data == null || data.isEmpty) {
            throw Exception('File returned no content bytes');
          }
          return data;
        }, retryIf: (e) => e is! _StaleRequestException);
      } on _StaleRequestException {
        return null;
      }

      put(container, filePath, result);
      return result;
    } finally {
      if (acquired) limiter.release(completer);
      _inFlight.remove(key);
    }
  }
}

class _StaleRequestException implements Exception {}