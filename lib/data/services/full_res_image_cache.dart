import 'dart:async';
import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/byte_budget_cache.dart';
import 'package:vaultexplorer/core/utils/image_dimensions.dart';
import 'package:vaultexplorer/core/utils/image_preview_exception.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';
import 'package:vaultexplorer/core/utils/retry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart';

export 'package:vaultexplorer/core/widgets/thumbnail/priority_task_queue.dart'
    show TaskPriority;

/// In-memory cache for decrypted image data, keyed per container session
/// (see [_key]). Large files use a separate, bounded native-decoded preview.
///
/// This exists specifically to avoid re-decrypting and re-transferring a
/// full image file across the platform channel every time the user swipes
/// back to something they've already viewed in this session. It is
/// deliberately memory-only and not persisted to disk: unlike thumbnails,
/// image data is cheap to regenerate from the still-mounted container (the
/// native [ChunkedFileEngine] already keeps its own decrypted-chunk cache
/// and open-handle LRU), so there's no need to pay disk-encryption overhead
/// for a cache whose only job is to avoid redundant work within a single
/// viewing session.
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
  // Keep method-channel image transfers small even on devices with little
  // remaining heap; larger files are sampled by native code instead.
  static const int _maxInlineImageBytes = 8 * 1024 * 1024;
  // A small *file* is not necessarily a small *image*: a flat-colour PNG of
  // hundreds of megapixels is a few MB on disk yet needs ~4 bytes/pixel
  // (gigabytes) once Flutter's codec expands it -- enough for Android's
  // low-memory killer to SIGKILL the whole process. Anything above this many
  // source pixels is therefore never decoded inline from raw bytes, however
  // small the file; it goes through the native sampled path instead, which
  // is guarded by ImageDecodeGuard (refuses > 512 MP, serialises and
  // memory-checks heavy decodes). Mirrors ImageDecodeGuard.HEAVY_SOURCE_PIXELS.
  static const int _maxInlineImagePixels = 48 * 1000 * 1000;
  static const int _largeImagePreviewSize = 2048;
  static const int _largeImagePreviewQuality = 95;
  static const int _largeImagePreviewBudget = 24 * 1024 * 1024;

  static final _cache = ByteBudgetCache(
    _maxTotalBytes - _largeImagePreviewBudget,
  );
  // Large images are decoded to a bounded WebP on the native side. Keep
  // those display copies separate so image editing never mistakes a
  // downsampled preview for the original file bytes.
  static final _largeImagePreviews = ByteBudgetCache(_largeImagePreviewBudget);

  // Files native code has said it will never decode (see
  // [ImagePreviewUnavailableReason.tooLarge]). Remembered for the session so
  // the viewer, its neighbour prefetch and every widget rebuild fail fast
  // instead of re-running a multi-second, memory-hungry decode that is
  // certain to be refused again. Out-of-memory failures are deliberately NOT
  // remembered: they depend on how much memory is free at the time.
  static final _tooLarge = LruCache<String, bool>(64);

  static String _key(MountedContainer container, String filePath) =>
      '${container.volId}:${container.mountedAt.millisecondsSinceEpoch}:$filePath';

  static Uint8List? get(MountedContainer container, String filePath) =>
      _cache[_key(container, filePath)];

  static void put(
    MountedContainer container,
    String filePath,
    Uint8List data,
  ) {
    final key = _key(container, filePath);
    _largeImagePreviews.remove(key);
    _cache[key] = data;
  }

  /// Whether [filePath] is already known to be too large to preview, so
  /// callers (e.g. neighbour prefetch) can skip it without a native call.
  static bool isKnownTooLarge(MountedContainer container, String filePath) =>
      _tooLarge.containsKey(_key(container, filePath));

  /// Whether [bytes] declare (in their own header) more source pixels than
  /// we are willing to hand to Flutter's codec. Unrecognised formats report
  /// `false` and keep the previous behaviour.
  static bool _exceedsInlinePixelBudget(Uint8List bytes) {
    final dims = extractImageDimensionsFromBytes(bytes);
    if (dims == null) return false;
    return dims.$1 * dims.$2 > _maxInlineImagePixels;
  }

  static bool contains(MountedContainer container, String filePath) =>
      _cache.containsKey(_key(container, filePath)) ||
      _largeImagePreviews.containsKey(_key(container, filePath));

  static bool isLargeImagePreview(
    MountedContainer container,
    String filePath,
  ) =>
      _largeImagePreviews.containsKey(_key(container, filePath));

  static void invalidate(MountedContainer container, String filePath) {
    final key = _key(container, filePath);
    _cache.remove(key);
    _largeImagePreviews.remove(key);
    _tooLarge.remove(key);
  }

  /// Clears all cached full-resolution bytes. Call this on container
  /// lock/unmount to release memory promptly rather than waiting for LRU
  /// eviction or process death.
  static void clear() {
    _cache.clear();
    _largeImagePreviews.clear();
    _tooLarge.clear();
  }

  /// Applies device-tier-scaled sizing (ADR-011) — see
  /// `DeviceCapabilityProfiler`/`runDeferredStartupWork()`. `FullResImageCache`
  /// is the one cache in this subsystem that was already byte-budgeted
  /// correctly from the start (ADR-002); this just exposes that primitive
  /// for the same profiler-driven sizing every other cache now has.
  static void resize(int newMaxTotalBytes) {
    final previewBudget = (newMaxTotalBytes ~/ 6)
        .clamp(1, _largeImagePreviewBudget)
        .toInt();
    _largeImagePreviews.resize(previewBudget);
    _cache.resize(
      (newMaxTotalBytes - previewBudget).clamp(1, newMaxTotalBytes).toInt(),
    );
  }

  /// Evicts [fraction] of currently-held bytes, oldest-first, without
  /// permanently lowering the budget — the full-res half of
  /// `CacheCoordinator.trimAll` (Finding F-15 / ADR-011).
  static void trimToFraction(double fraction) {
    _cache.trimToFraction(fraction);
    _largeImagePreviews.trimToFraction(fraction);
  }

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
  /// ever sit ahead of the current page in the native queue. Priority-
  /// tiered (ADR-010) and playback-aware (ADR-012) like
  /// `ThumbnailConcurrency`'s limiters -- the media viewer's current page
  /// should use [TaskPriority.visible] (the default) and its next/prev
  /// prefetch should pass [TaskPriority.adjacent] explicitly.
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
  static Future<Uint8List?> fetch({
    required VaultFileIoApi fileIoApi,
    required MountedContainer container,
    required String filePath,
    required Completer<void> completer,
    required bool Function() isStillWanted,
    TaskPriority priority = TaskPriority.visible,
  }) {
    final cached = get(container, filePath);
    if (cached != null) return Future.value(cached);
    final cachedPreview = _largeImagePreviews[_key(container, filePath)];
    if (cachedPreview != null) return Future.value(cachedPreview);

    final key = _key(container, filePath);
    if (_tooLarge.containsKey(key)) {
      return Future.error(
        const ImagePreviewUnavailableException(
          ImagePreviewUnavailableReason.tooLarge,
        ),
      );
    }
    final existing = _inFlight[key];
    if (existing != null) {
      // The fetch we are joining belongs to whoever started it, and it is
      // abandoned (returns null) when *that* caller goes stale: its widget
      // was disposed, the page scrolled out of the prefetch window, or its
      // queue ticket was cancelled. That says nothing about *this* caller,
      // which would otherwise be told the image failed to load. If we still
      // want the file, run our own fetch -- the abandoned entry has already
      // been removed from [_inFlight].
      return existing.then<Uint8List?>((data) {
        if (data != null || !isStillWanted()) return data;
        return fetch(
          fileIoApi: fileIoApi,
          container: container,
          filePath: filePath,
          completer: completer,
          isStillWanted: isStillWanted,
          priority: priority,
        );
      });
    }

    final future = _runGated(
      fileIoApi,
      container,
      filePath,
      key,
      completer,
      isStillWanted,
      priority,
    );
    _inFlight[key] = future;
    return future;
  }

  static Future<Uint8List?> _runGated(
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String filePath,
    String key,
    Completer<void> completer,
    bool Function() isStillWanted,
    TaskPriority priority,
  ) async {
    bool acquired = false;
    try {
      try {
        await limiter.acquire(completer, priority: priority);
      } catch (_) {
        // Cancelled while still queued (the caller that owned this ticket
        // went away). Not a load failure: report "abandoned" like any other
        // stale request and let a caller that still wants the file retry.
        return null;
      }
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
      var sampledLargeImage = false;

      // Native, memory-guarded, downsampled preview (a bounded WebP). Used
      // for big files and for small files that declare a huge pixel count.
      Future<Uint8List> fetchSampledPreview() async {
        Uint8List? preview;
        try {
          preview = await fileIoApi.getImageThumbnailOrThrow(
            container,
            filePath,
            targetSize: _largeImagePreviewSize,
            quality: _largeImagePreviewQuality,
            preserveAlpha: true,
          );
        } on ImagePreviewUnavailableException catch (e) {
          if (e.reason == ImagePreviewUnavailableReason.tooLarge) {
            _tooLarge[key] = true;
          }
          rethrow;
        }
        if (preview == null || preview.isEmpty) {
          throw Exception('Failed to decode large image');
        }
        if (!isStillWanted()) throw _StaleRequestException();
        sampledLargeImage = true;
        _largeImagePreviews[key] = preview;
        return preview;
      }

      try {
        result = await retryWithBackoff<Uint8List>((attempt) async {
          if (!isStillWanted()) throw _StaleRequestException();
          final size = await fileIoApi.getMediaFileSize(container, filePath);
          if (size <= 0) throw Exception('File size is empty');
          if (!isStillWanted()) throw _StaleRequestException();

          if (size >= _maxInlineImageBytes) return fetchSampledPreview();

          final data = await fileIoApi.readMediaFileChunk(
            container,
            filePath,
            0,
            size,
          );
          if (data == null || data.isEmpty) {
            throw Exception('File returned no content bytes');
          }
          // The bytes are already in memory (< _maxInlineImageBytes), so
          // reading the declared pixel size out of their header is free.
          if (_exceedsInlinePixelBudget(data)) return fetchSampledPreview();
          return data;
        },
            // Neither a stale request nor a deliberate "too large / not
            // enough memory" refusal is worth retrying: the same native
            // decode would just be attempted (and refused) again.
            retryIf: (e) =>
                e is! _StaleRequestException &&
                e is! ImagePreviewUnavailableException);
      } on _StaleRequestException {
        return null;
      }

      if (!sampledLargeImage) {
        put(container, filePath, result);
      }
      return result;
    } finally {
      if (acquired) limiter.release(completer);
      _inFlight.remove(key);
    }
  }
}

class _StaleRequestException implements Exception {}
