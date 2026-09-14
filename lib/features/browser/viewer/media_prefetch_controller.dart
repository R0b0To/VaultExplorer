import 'dart:async';
import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/retry.dart';
import 'package:vaultexplorer/core/utils/task_priority.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

/// Keeps the next few items around the current playlist position warm in
/// cache -- thumbnails for the immediate neighbors, full-resolution image
/// data a little further out -- so paging through the media viewer doesn't
/// show a loading flicker on every swipe.
///
/// Extracted from `_MediaViewerScreenState`'s `_prefetchSurroundingItems`/
/// `_prefetchThumbnail`/`_gatedFetchThumbnail`/
/// `_fetchImageThumbnailForPrefetch`/`_fetchVideoThumbnailForPrefetch`/
/// `_prefetchFullRes` cluster (media-viewer-screen decomposition,
/// tech-debt audit, Sept 2026): cache/service orchestration that happened
/// to live on the widget's State only because that's where
/// `ref.read(thumbnailCacheServiceProvider)` and `widget.container`/
/// `widget.thumbnailQuality`/`widget.thumbnailCacheMode` were already in
/// scope. No BuildContext or widget lifecycle involved beyond the
/// `isStillWanted` predicate callers already had to inject before this
/// extraction (see [prefetchSurrounding]).
///
/// A plain class instantiated once per `MediaViewerScreen` -- like
/// `PlaylistController`/`VideoPlaybackManager` on the same screen, not a
/// shared singleton -- because [_prefetchingFullRes] is genuinely scoped
/// to one viewing session: a bare filename set shared across containers
/// could mark one container's in-flight prefetch as covering another's
/// same-named file.
///
/// Debouncing (the `Timer` in `_scheduleSurroundingPrefetch`) stays on the
/// widget, which owns that timer's disposal; this class starts exactly
/// where the debounce ends.
class MediaPrefetchController {
  final MountedContainer container;
  final VaultFileIoApi _fileIoApi;
  final ThumbnailCacheService _thumbnailCache;
  final ThumbnailQuality _quality;
  final ThumbnailCacheMode _cacheMode;
  final Set<String> _prefetchingFullRes = {};

  MediaPrefetchController({
    required this.container,
    required VaultFileIoApi fileIoApi,
    required ThumbnailCacheService thumbnailCache,
    required ThumbnailQuality thumbnailQuality,
    required ThumbnailCacheMode thumbnailCacheMode,
  }) : _fileIoApi = fileIoApi,
       _thumbnailCache = thumbnailCache,
       _quality = thumbnailQuality,
       _cacheMode = thumbnailCacheMode;

  /// Fire-and-forget prefetch for the few items surrounding [currentIndex]
  /// in [playlist] (deltas +1/-1/+2/-2, matching the old fixed neighbor
  /// window). [isStillWanted] is re-invoked at the point a full-res fetch
  /// is actually about to run (which may be after this file's neighbor
  /// window has already moved on) -- callers should re-check *current*
  /// playlist/index state inside it, not capture the state from this call.
  void prefetchSurrounding(
    int currentIndex,
    List<String> playlist, {
    required bool Function(String fileName) isStillWanted,
  }) {
    if (playlist.isEmpty) return;
    for (final delta in [1, -1, 2, -2]) {
      final i = currentIndex + delta;
      if (i >= 0 && i < playlist.length) {
        final file = playlist[i];
        prefetchThumbnail(file);
        if (MediaViewerConstants.isImage(file)) {
          _prefetchFullRes(file, isStillWanted: () => isStillWanted(file));
        }
      }
    }
  }

  /// Also called directly for the item currently being built (not just its
  /// neighbors) -- see `_buildMediaItem`'s prefetch-on-render fallback.
  Future<void> prefetchThumbnail(String fileName) async {
    final isImg = MediaViewerConstants.isImage(fileName);
    final isVid = MediaViewerConstants.isVideo(fileName);
    if (!isImg && !isVid) return;

    if (_thumbnailCache.peekMemory(container, fileName, _quality) != null) {
      return;
    }

    if (_cacheMode != ThumbnailCacheMode.disabled) {
      final cached = await _thumbnailCache.fetch(
        container: container,
        filePath: fileName,
        mode: _cacheMode,
        quality: _quality,
      );
      if (cached != null && cached.isNotEmpty) {
        _thumbnailCache.cacheInMemory(container, fileName, cached, _quality);
        return;
      }
    }

    final key = '${container.volId}:${container.mountedAt.millisecondsSinceEpoch}:$fileName';
    final existing = ThumbnailConcurrency.inFlightThumbnails[key];
    if (existing != null) {
      try {
        await existing;
      } catch (_) {
        // Only waiting for the in-flight generation to finish, not its
        // outcome -- same "ignore prefetch errors" reasoning as the
        // future below. A later request will pick up whatever ended up
        // cached, or trigger a fresh attempt.
      }
      return;
    }

    final limiter = isVid ? ThumbnailConcurrency.videoLimiter : ThumbnailConcurrency.imageLimiter;
    final completer = Completer<void>();
    final future = _gatedFetchThumbnail(fileName, isVid, limiter, completer);
    ThumbnailConcurrency.inFlightThumbnails[key] = future;
    try {
      await future;
    } catch (e) {
      // Ignore prefetch errors
    } finally {
      if (ThumbnailConcurrency.inFlightThumbnails[key] == future) {
        ThumbnailConcurrency.inFlightThumbnails.remove(key);
      }
    }
  }

  Future<Uint8List> _gatedFetchThumbnail(
    String fileName,
    bool isVid,
    PriorityTaskQueue limiter,
    Completer<void> completer,
  ) async {
    bool acquired = false;
    try {
      await limiter.acquire(completer, priority: TaskPriority.adjacent);
      acquired = true;
      return await retryWithBackoff<Uint8List>(
        (attempt) => isVid
            ? _fetchVideoThumbnailForPrefetch(fileName)
            : _fetchImageThumbnailForPrefetch(fileName),
      );
    } finally {
      if (acquired) limiter.release(completer);
    }
  }

  Future<Uint8List> _fetchImageThumbnailForPrefetch(String fileName) async {
    if (_cacheMode != ThumbnailCacheMode.disabled) {
      final cached = await _thumbnailCache.fetch(
        container: container,
        filePath: fileName,
        mode: _cacheMode,
        quality: _quality,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final data = await _fileIoApi.getImageThumbnail(
      container,
      fileName,
      targetSize: MediaViewerConstants.thumbnailTargetSize,
      quality: _quality.jpegQuality,
    );
    final bytes = (data == null || data.isEmpty) ? Uint8List(0) : data;
    if (bytes.isNotEmpty) {
      _thumbnailCache.cacheInMemory(container, fileName, bytes, _quality);
      if (_cacheMode != ThumbnailCacheMode.disabled) {
        unawaited(
          _thumbnailCache.store(
            container: container,
            filePath: fileName,
            data: bytes,
            mode: _cacheMode,
            quality: _quality,
          ),
        );
      }
    }
    return bytes;
  }

  Future<Uint8List> _fetchVideoThumbnailForPrefetch(String fileName) async {
    return VideoThumbnailFetcher.fetch(
      _thumbnailCache,
      _fileIoApi,
      container,
      fileName,
      mode: _cacheMode,
      quality: _quality,
      targetSize: MediaViewerConstants.thumbnailTargetSize,
    );
  }

  Future<void> _prefetchFullRes(String fileName, {required bool Function() isStillWanted}) async {
    if (!MediaViewerConstants.isImage(fileName)) return;
    if (FullResImageCache.contains(container, fileName)) return;
    if (_prefetchingFullRes.contains(fileName)) return;

    _prefetchingFullRes.add(fileName);
    final completer = Completer<void>();
    try {
      await FullResImageCache.fetch(
        fileIoApi: _fileIoApi,
        container: container,
        filePath: fileName,
        completer: completer,
        isStillWanted: isStillWanted,
        priority: TaskPriority.adjacent,
      );
    } catch (e) {
      VeLog.w('MediaPrefetchController', 'Full-res prefetch failed for ${VeLog.censorName(fileName)}', e);
    } finally {
      _prefetchingFullRes.remove(fileName);
    }
  }
}
