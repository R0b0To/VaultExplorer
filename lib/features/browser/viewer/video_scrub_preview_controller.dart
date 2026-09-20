import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/scrub_preview_style.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';

/// Lets the seekbar (deep inside the bottom controls) hand the current
/// drag's [VideoScrubPreviewController] to `VideoScrubFullscreenLayer`,
/// which is a sibling of the controls in the viewer's top-level stack.
/// Owned and disposed by the viewer screen; holds null between drags.
typedef VideoScrubPreviewHost = ValueNotifier<VideoScrubPreviewController?>;

/// Debounced, session-scoped fetcher for the preview frame shown while the
/// user is scrubbing -- either the small box above the seekbar thumb or the
/// fullscreen frame, depending on [ScrubPreviewStyle].
///
/// One instance is meant to live for exactly one drag gesture: [begin]
/// opens a native decode session pinned to whatever video [_controller] is
/// currently playing, [requestFrame] can then be called as often as the
/// slider reports a new position, and [end] (or [dispose], which also
/// calls [end]) tears the session down again. A fresh instance should be
/// created for the next drag rather than reusing this one.
///
/// Two things keep this cheap even if the slider reports a position on
/// every pointer-move frame:
///  - **Coalescing**: only one native decode is ever in flight. A position
///    requested while one is already running just replaces whatever was
///    pending; superseded positions are never decoded at all.
///  - **Caching**: decoded frames are kept in a small byte-budgeted cache,
///    bucketed by position, so re-crossing a spot on the timeline -- a
///    common scrubbing motion, overshoot then correct -- shows the earlier
///    frame at once while a fresh decode refines it. A bucket is at most
///    ~1/240 of the video wide ([bucketMsFor]): a whole second-scale span
///    on a long video, but a single frame's worth on a short clip, so the
///    instantly-shown frame is never noticeably the wrong one.
class VideoScrubPreviewController {
  VideoScrubPreviewController(
    this._controller, {
    this.frameMaxSize = _miniBoxFrameMaxSize,
    this.frameQuality = _miniBoxFrameQuality,
    Duration videoDuration = Duration.zero,
  }) : _bucketMs = bucketMsFor(videoDuration);

  /// Sizes the decoded frames for how [style] will show them. The ~200 px
  /// JPEG that is plenty for the mini box would be a blurry smear stretched
  /// across the screen, so fullscreen asks the native side for a much
  /// larger (and correspondingly costlier) frame.
  ///
  /// [videoDuration] sets how finely positions are bucketed for the cache;
  /// leave it at zero if unknown.
  factory VideoScrubPreviewController.forStyle(
    NativeVideoController? controller,
    ScrubPreviewStyle style, {
    Duration videoDuration = Duration.zero,
  }) =>
      switch (style) {
        ScrubPreviewStyle.miniBox => VideoScrubPreviewController(
            controller,
            videoDuration: videoDuration,
          ),
        ScrubPreviewStyle.fullscreen => VideoScrubPreviewController(
            controller,
            frameMaxSize: _fullscreenFrameMaxSize,
            frameQuality: _fullscreenFrameQuality,
            videoDuration: videoDuration,
          ),
      };

  static const _tag = 'VideoScrubPreviewController';

  // Longest edge (px) and JPEG quality requested from the native decoder.
  // The mini-box values match the native side's own defaults.
  static const _miniBoxFrameMaxSize = 200;
  static const _miniBoxFrameQuality = 55;
  static const _fullscreenFrameMaxSize = 1280;
  static const _fullscreenFrameQuality = 70;

  // Bucket width bounds, in ms. Coarse enough that hovering back and forth
  // over roughly the same spot reuses a cached frame; fine enough that the
  // preview still visibly advances as the finger moves across the track.
  // The floor is about one frame at 30 fps -- nothing to gain below it.
  static const _minBucketMs = 33;
  static const _maxBucketMs = 750;

  // A bucket spans about one slider pixel's worth of the video.
  static const _bucketsPerVideo = 240;

  // Frames vary from ~10 KB (mini box) to ~100 KB (fullscreen), so the
  // cache is capped by size rather than by entry count.
  static const _maxCacheBytes = 6 * 1024 * 1024;

  final NativeVideoController? _controller;

  /// Width of one position bucket, in milliseconds.
  final int _bucketMs;

  /// Longest edge, in pixels, of each frame requested from the native side.
  final int frameMaxSize;

  /// JPEG quality (1-100) of each frame requested from the native side.
  final int frameQuality;

  /// The most recently decoded preview frame, or null before the first
  /// one arrives (or if this video has no usable preview at all -- see
  /// [available]).
  final ValueNotifier<Uint8List?> frameNotifier = ValueNotifier<Uint8List?>(null);

  final Map<int, Uint8List> _cache = <int, Uint8List>{};
  int _cacheBytes = 0;

  bool _available = false;
  bool _fetching = false;
  Duration? _pendingPosition;
  bool _disposed = false;

  /// Whether the native side was able to open a decode session for this
  /// video at all. False for an unsupported codec or an audio-only file.
  /// Only meaningful after [begin] has completed.
  bool get available => _available;

  /// True once [dispose] has run; [frameNotifier] is unusable after that.
  bool get isDisposed => _disposed;

  /// Width of a position bucket, in ms, for a video of [duration]: about
  /// 1/240 of it (roughly a slider pixel), but never coarser than 750 ms --
  /// the old fixed width, and still right for long videos -- nor finer than
  /// ~one frame. A short clip gets fine buckets, so its many distinct
  /// frames aren't collapsed into a handful of cache slots. An unknown
  /// duration gets the coarse default.
  @visibleForTesting
  static int bucketMsFor(Duration duration) {
    final ms = duration.inMilliseconds;
    if (ms <= 0) return _maxBucketMs;
    return (ms / _bucketsPerVideo).round().clamp(_minBucketMs, _maxBucketMs).toInt();
  }

  /// How many frames are currently cached.
  @visibleForTesting
  int get cachedFrameCount => _cache.length;

  int _bucketFor(Duration position) => (position.inMilliseconds / _bucketMs).round();

  void _remember(int bucket, Uint8List bytes) {
    // Remove first so a re-fetched bucket moves to the back of the
    // eviction order instead of keeping its original place in line.
    final replaced = _cache.remove(bucket);
    if (replaced != null) _cacheBytes -= replaced.length;
    _cache[bucket] = bytes;
    _cacheBytes += bytes.length;
    // Always keep the newest frame, however large.
    while (_cacheBytes > _maxCacheBytes && _cache.length > 1) {
      final oldest = _cache.keys.first;
      _cacheBytes -= _cache.remove(oldest)!.length;
    }
  }

  /// Opens the native decode session. Call once, before the first
  /// [requestFrame] of a drag gesture.
  Future<void> begin() async {
    if (_disposed) return;
    _available = await _controller?.startScrubPreview() ?? false;
  }

  /// Requests the preview frame nearest [position]. Fire-and-forget: the
  /// result (if any) arrives via [frameNotifier], not this call's return
  /// value, since a request can be silently superseded by a later one.
  void requestFrame(Duration position) {
    if (_disposed || !_available) return;

    final cached = _cache[_bucketFor(position)];
    if (cached != null) {
      frameNotifier.value = cached;
    }

    if (_fetching) {
      _pendingPosition = position;
      return;
    }
    unawaited(_dispatch(position));
  }

  Future<void> _dispatch(Duration position) async {
    if (_disposed || !_available) return;
    _fetching = true;
    try {
      final bytes = await _controller?.getScrubPreviewFrame(
        position,
        maxSize: frameMaxSize,
        quality: frameQuality,
      );
      if (_disposed) return;
      if (bytes != null) {
        _remember(_bucketFor(position), bytes);
        frameNotifier.value = bytes;
      }
    } catch (e) {
      VeLog.w(_tag, 'getScrubPreviewFrame failed', e);
    } finally {
      _fetching = false;
      final next = _pendingPosition;
      _pendingPosition = null;
      if (next != null && !_disposed) {
        unawaited(_dispatch(next));
      }
    }
  }

  /// Closes the native decode session. Safe to call even if [begin] never
  /// completed or [available] is false.
  Future<void> end() async {
    if (_disposed) return;
    _available = false;
    _pendingPosition = null;
    try {
      await _controller?.endScrubPreview();
    } catch (e) {
      VeLog.w(_tag, 'endScrubPreview failed', e);
    }
  }

  /// Ends the session (best-effort, not awaited) and releases the frame
  /// notifier and cache. After this call the controller is unusable --
  /// create a new one for the next drag gesture.
  void dispose() {
    if (_disposed) return;
    // Deliberately called before _disposed flips: end() itself guards on
    // _disposed at entry, so calling it after would make it a no-op and
    // leak the native decode session whenever this controller is
    // disposed mid-drag (e.g. the viewer is popped while still
    // scrubbing) instead of going through the normal onChangeEnd path.
    unawaited(end());
    _disposed = true;
    frameNotifier.dispose();
    _cache.clear();
    _cacheBytes = 0;
  }
}
