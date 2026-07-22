import 'dart:async';
import 'dart:typed_data';

import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/byte_budget_cache.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart' show ConcurrencyLimiter;
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

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

  // --------------------------------------------------------------------
  // Concurrency gate
  // --------------------------------------------------------------------
  //
  // Without this, both EncryptedImageWidget's on-demand load and
  // MediaViewerScreen's background prefetch called vaultExplorerApi
  // directly and unconditionally. Every page PageView.builder materializes
  // during a fast swipe/fling fires a real decrypt+transfer immediately,
  // with no cap and no way to cancel a request for a page the user has
  // already scrolled past -- so those requests pile up FIFO on the native
  // ioExecutor thread pool (see MainActivity.kt), and the page the user
  // has actually landed on has to wait behind however many stale ones were
  // queued ahead of it. There is no cancellation once invokeMethod is
  // sent, so the only lever available from Dart is never submitting the
  // call in the first place.
  //
  // This mirrors ThumbnailConcurrency/AsyncThumbnail's LIFO-with-
  // cancellation gate (see widgets/async_thumbnail.dart) -- same shape,
  // applied to the much heavier full-resolution path.

  /// Kept small (2) since each request here is a whole decrypted file, not
  /// a thumbnail -- this bounds how many stale swiped-past requests can
  /// ever sit ahead of the current page in the native queue.
  static final limiter = ConcurrencyLimiter(2);

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
  }) {
    final cached = get(container, filePath);
    if (cached != null) return Future.value(cached);

    final key = _key(container, filePath);
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future =
        _runGated(container, filePath, key, completer, isStillWanted);
    _inFlight[key] = future;
    return future;
  }

  static Future<Uint8List?> _runGated(
    MountedContainer container,
    String filePath,
    String key,
    Completer<void> completer,
    bool Function() isStillWanted,
  ) async {
    bool acquired = false;
    try {
      await limiter.acquire(completer);
      acquired = true;
      if (!isStillWanted()) return null;

      const maxAttempts = 3;
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (!isStillWanted()) return null;
        try {
          final size =
              await vaultExplorerApi.getMediaFileSize(container, filePath);
          if (size <= 0) throw Exception('File size is empty');
          if (!isStillWanted()) return null;

          final data = await vaultExplorerApi.readMediaFileChunk(
              container, filePath, 0, size);
          if (data == null || data.isEmpty) {
            throw Exception('File returned no content bytes');
          }

          put(container, filePath, data);
          return data;
        } catch (e) {
          if (attempt == maxAttempts - 1) rethrow;
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      return null; // unreachable
    } finally {
      if (acquired) limiter.release();
      _inFlight.remove(key);
    }
  }
}
