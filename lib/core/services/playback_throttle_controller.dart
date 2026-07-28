import 'package:flutter/foundation.dart';

/// Gates background image/thumbnail decoding while a `MediaCodec` video
/// session (ExoPlayer/VLC) is active — ADR-012.
///
/// Finding F-06: `MediaMetadataRetriever` (used to generate video
/// thumbnails) contends with an active video decoder for system
/// `MediaCodec` slots and can throw `Released by resource manager
/// (0xffffffe0)` on 4K video. [MediaViewerScreen] used to work around this
/// with a hard-coded `if (isVideo) return;` skip in its own ad hoc
/// prefetch path, but [PlaylistCarouselOverlay] — rendering *during the
/// same viewer session, while a video is playing* — used the regular
/// `AsyncThumbnail`/`ThumbnailConcurrency.videoLimiter` path for its
/// neighbor tiles, completely bypassing that point-fix.
///
/// This is the general replacement: a single process-wide signal that
/// [PriorityTaskQueue] consults on every admission decision, regardless of
/// which surface (grid, carousel, viewer prefetch) is asking. No caller
/// needs its own "am I competing with video playback" awareness.
///
/// Process-wide singleton by design, matching ADR-001's pattern for
/// [ThumbnailConcurrency] and [FullResImageCache] — there is exactly one
/// shared native video player for the whole app (see
/// `VideoPlaybackManager`), so "is a video decode session active" is a
/// single global fact, not a per-screen one.
class PlaybackThrottleController {
  PlaybackThrottleController._();

  /// True while the app's single shared video player has an active
  /// `MediaCodec` video-decode session (i.e. the current media-viewer page
  /// is a video, not an image/audio file). Toggled from
  /// `MediaViewerScreen._activateCurrentMedia()`/`dispose()` — see
  /// `MediaViewerConstants.isVideo`.
  ///
  /// Deliberately scoped to *video* only, not audio: audio playback uses a
  /// separate audio codec path and doesn't contend with
  /// `MediaMetadataRetriever`'s video frame extraction the way active video
  /// decode does (this mirrors the specific contention Finding F-06
  /// describes, rather than throttling more broadly than the actual
  /// hardware constraint requires).
  static final ValueNotifier<bool> isPlaybackActive = ValueNotifier<bool>(false);

  static void setActive(bool active) {
    if (isPlaybackActive.value != active) {
      isPlaybackActive.value = active;
    }
  }
}
