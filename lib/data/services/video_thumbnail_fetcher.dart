import 'dart:async';
import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

/// Single choke point for "fetch a *video* thumbnail, caching it if it
/// wasn't already." Every call site that does this should go through here
/// instead of calling `vaultExplorerApi.getVideoThumbnail[WithSize]` and
/// `ThumbnailCacheService.put` directly -- that pair used to be
/// copy-pasted across five call sites (file_grid_view, file_masonry_view,
/// file_tile, media_viewer_screen's prefetch, playlist_carousel_overlay),
/// which is exactly what let the guard below go missing at three of them
/// (file_grid_view, file_masonry_view, file_tile) while the other two
/// independently hand-rolled a stricter version of it.
///
/// The guard: while a video is actively playing, native extraction
/// reroutes to a software-only MediaCodec fallback so it doesn't contend
/// with ExoPlayer for the hardware decoder (see `extractVideoFrame` in
/// ThumbnailHandlers.kt). That fallback can return a "successful" but
/// wrong frame rather than failing outright, and there's currently no
/// signal telling Dart which one happened. So a fetch made while playback
/// is active still returns bytes immediately -- and still populates the
/// in-memory tier, so the UI has something to show -- but is never
/// written to the durable disk/in-container cache, where a wrong frame
/// would otherwise stick until something changes the cache key.
///
/// We read [PlaybackThrottleController.isPlaybackActive] both *before*
/// and *after* the extraction call, not just before. Checking only
/// before leaves a gap: native's own routing check happens whenever the
/// platform call actually executes, which can be meaningfully later than
/// this Dart-side snapshot (channel + thread-pool scheduling), so
/// playback can go inactive-to-active *during* the await -- native takes
/// the fallback path while this side is still holding a stale "false".
/// Checking again after narrows that window (doesn't close it entirely:
/// native's check could still land in the small remaining gap between the
/// after-check and native's own read of the flag -- closing it fully
/// needs the native call to report whether it took the fallback path, not
/// a flag guessed at from the Dart side). Either read being true is
/// enough to withhold from the durable cache; a wrong frame only needs to
/// slip through once to stick.
///
/// This is what made the masonry-layout bug so reliable in practice:
/// masonry packs more tiles on screen than grid/list and fetches the
/// heavier `...WithSize` variant, so on a folder's first visit it
/// routinely has several video extractions still in flight at once. Any
/// one of those in-flight calls that straddled a tap-to-open-video (which
/// flips [PlaybackThrottleController.isPlaybackActive] true) would, with
/// no guard at all, unconditionally persist whatever native handed back
/// -- durably poisoning that file's cache entry for every layout, forever
/// (or until the cache key changes). Once one layout has written a good
/// frame to the durable cache first, every other layout just reads it
/// back and the symptom disappears -- which is why visiting grid/list
/// first "fixed" it.
class VideoThumbnailFetcher {
  VideoThumbnailFetcher._();

  static Future<Uint8List> fetch(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String filePath, {
    required ThumbnailCacheMode mode,
    required ThumbnailQuality quality,
    required int targetSize,
  }) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await thumbnailCache.fetch(
        container: container,
        filePath: filePath,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }

    // Read both before *and* after extracting -- see the class doc for why
    // a before-only snapshot leaves a gap.
    final activeBeforeFetch = PlaybackThrottleController.isPlaybackActive.value;
    final data = await fileIoApi.getVideoThumbnail(
      container,
      filePath,
      quality: quality.jpegQuality,
      targetSize: targetSize,
    );
    final activeDuringFetch =
        activeBeforeFetch || PlaybackThrottleController.isPlaybackActive.value;
    if (data == null || data.isEmpty) {
      throw StateError('Video thumbnail unavailable');
    }

    thumbnailCache.cacheInMemory(container, filePath, data, quality);
    if (mode != ThumbnailCacheMode.disabled && !activeDuringFetch) {
      unawaited(
        thumbnailCache.store(
          container: container,
          filePath: filePath,
          data: data,
          mode: mode,
          quality: quality,
        ),
      );
    }
    return data;
  }

  /// Same as [fetch], but also reports the source frame's true
  /// width/height via [onSizeKnown] -- for masonry-style layouts that need
  /// the real aspect ratio. [onUnknownSize] is called instead when a cache
  /// *hit* has no size on record (e.g. written before dimensions were
  /// tracked, or the `.meta` sidecar is missing/unreadable).
  static Future<Uint8List> fetchWithSize(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String filePath, {
    required ThumbnailCacheMode mode,
    required ThumbnailQuality quality,
    required int targetSize,
    required void Function(int width, int height) onSizeKnown,
    required Future<void> Function(Uint8List bytes) onUnknownSize,
  }) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await thumbnailCache.fetchWithSize(
        container: container,
        filePath: filePath,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.$1.isNotEmpty) {
        final (bytes, width, height) = cached;
        if (width != null && height != null) {
          onSizeKnown(width, height);
        } else {
          await onUnknownSize(bytes);
        }
        return bytes;
      }
    }

    final activeBeforeFetch = PlaybackThrottleController.isPlaybackActive.value;
    final thumb = await fileIoApi.getVideoThumbnailWithSize(
      container,
      filePath,
      quality: quality.jpegQuality,
      targetSize: targetSize,
    );
    final activeDuringFetch =
        activeBeforeFetch || PlaybackThrottleController.isPlaybackActive.value;
    final data = thumb?.bytes;
    if (data == null || data.isEmpty) {
      throw StateError('Video thumbnail unavailable');
    }
    onSizeKnown(thumb!.width, thumb.height);

    thumbnailCache.cacheInMemory(
      container,
      filePath,
      data,
      quality,
      thumb.width,
      thumb.height,
    );
    if (mode != ThumbnailCacheMode.disabled && !activeDuringFetch) {
      unawaited(
        thumbnailCache.store(
          container: container,
          filePath: filePath,
          data: data,
          mode: mode,
          quality: quality,
          width: thumb.width,
          height: thumb.height,
        ),
      );
    }
    return data;
  }
}
