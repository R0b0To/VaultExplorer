import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';

/// Debounced, session-scoped fetcher for the small preview frame shown
/// above the seekbar thumb while the user is scrubbing.
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
///  - **Caching**: decoded frames are kept in a small bucketed LRU, so
///    re-crossing the same rough spot on the timeline -- a common
///    scrubbing motion, overshoot then correct -- reuses the earlier
///    frame instead of asking the native side to decode it again.
class VideoScrubPreviewController {
  VideoScrubPreviewController(this._controller);

  static const _tag = 'VideoScrubPreviewController';

  // Coarse enough that hovering back and forth over roughly the same spot
  // reuses a cached frame; fine enough that the preview still visibly
  // advances as the finger moves across the track.
  static const _bucketMs = 750;
  static const _maxCacheEntries = 40;

  final NativeVideoController? _controller;

  /// The most recently decoded preview frame, or null before the first
  /// one arrives (or if this video has no usable preview at all -- see
  /// [available]).
  final ValueNotifier<Uint8List?> frameNotifier = ValueNotifier<Uint8List?>(null);

  final Map<int, Uint8List> _cache = <int, Uint8List>{};

  bool _available = false;
  bool _fetching = false;
  Duration? _pendingPosition;
  bool _disposed = false;

  /// Whether the native side was able to open a decode session for this
  /// video at all. False for an unsupported codec or an audio-only file.
  /// Only meaningful after [begin] has completed.
  bool get available => _available;

  int _bucketFor(Duration position) => (position.inMilliseconds / _bucketMs).round();

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
      final bytes = await _controller?.getScrubPreviewFrame(position);
      if (_disposed) return;
      if (bytes != null) {
        final bucket = _bucketFor(position);
        _cache[bucket] = bytes;
        if (_cache.length > _maxCacheEntries) {
          _cache.remove(_cache.keys.first);
        }
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
  }
}
