import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/video_aspect_ratio_mode.dart';
import 'package:vaultexplorer/data/models/video_playback_mode.dart';
import 'package:vaultexplorer/features/browser/viewer/models/viewer_adjustments.dart';
export 'package:vaultexplorer/data/models/video_playback_mode.dart'
    show VideoPlaybackMode;
part 'media_viewer_session_controller.g.dart';



/// User-facing media viewer session options, chrome visibility, playback
/// preferences, and transient per-file rotations and reload counters.
///
/// Controllers owning native player surfaces, scroll controllers, and touch
/// recognizers stay in the widget tree because their lifecycles are bound to
/// the rendering engine.
class MediaViewerSessionState {
  const MediaViewerSessionState({
    this.showUI = false,
    this.isCarouselVisible = false,
    this.enableCarousel = true,
    this.bookmarkPaths = const [],
    this.autoAdvance = false,
    this.isAutoAdvancing = false,
    this.slideshowDelaySeconds = 4,
    this.videoPlaybackMode = VideoPlaybackMode.playOnce,
    this.playbackSpeed = 1.0,
    this.subtitlesEnabled = true,
    this.subtitleFontSize = 15.0,
    this.subtitleVerticalPosition = 0.0,
    this.imageFit = BoxFit.contain,
    this.videoAspectRatioMode = VideoAspectRatioMode.bestFit,
    this.transitionEffect = PlaylistTransitionEffect.slide,
    this.scrollMode = PlaylistScrollMode.horizontal,
    this.isMuted = false,
    this.rotations = const {},
    this.adjustments = const {},
    this.applyAdjustmentsToAll = false,
    this.sharedAdjustments = ViewerAdjustments.identity,
    this.compareOriginal = false,
    this.imageReloadEpoch = const {},
  });

  final bool showUI;
  final bool isCarouselVisible;
  final bool enableCarousel;
  final List<String> bookmarkPaths;
  final bool autoAdvance;
  final bool isAutoAdvancing;
  final int slideshowDelaySeconds;
  final VideoPlaybackMode videoPlaybackMode;
  final double playbackSpeed;
  final bool subtitlesEnabled;
  final double subtitleFontSize;
  final double subtitleVerticalPosition;
  final BoxFit imageFit;
  final VideoAspectRatioMode videoAspectRatioMode;
  final PlaylistTransitionEffect transitionEffect;
  final PlaylistScrollMode scrollMode;
  final bool isMuted;

  /// Per-file rotation in clockwise quarter-turns (0-3), keyed by path.
  /// This is the unit `RotatedBox.quarterTurns`, the `% 2` "is it sideways"
  /// checks and the playback settings sheet all work in -- not degrees.
  final Map<String, int> rotations;

  /// Per-file picture adjustments, keyed by path. In memory only: nothing is
  /// persisted, so file paths from inside an encrypted vault never reach
  /// plaintext preferences. Files without an entry are unadjusted.
  final Map<String, ViewerAdjustments> adjustments;

  /// When true, [sharedAdjustments] is used for every file and the per-file
  /// [adjustments] map is ignored (but kept, so switching back restores it).
  final bool applyAdjustmentsToAll;
  final ViewerAdjustments sharedAdjustments;

  /// True while the user holds "compare": every picture is shown without its
  /// adjustments. Transient, never edits the stored values.
  final bool compareOriginal;

  /// The adjustments stored for [path] (shared across files when
  /// apply-to-all is on). What the sliders show and edit.
  ViewerAdjustments adjustmentsFor(String path) => applyAdjustmentsToAll
      ? sharedAdjustments
      : (adjustments[path] ?? ViewerAdjustments.identity);

  /// What is actually drawn for [path]: the stored adjustments, or none
  /// while [compareOriginal] is held.
  ViewerAdjustments effectiveAdjustmentsFor(String path) =>
      compareOriginal ? ViewerAdjustments.identity : adjustmentsFor(path);

  final Map<String, int> imageReloadEpoch;

  MediaViewerSessionState copyWith({
    bool? showUI,
    bool? isCarouselVisible,
    bool? enableCarousel,
    List<String>? bookmarkPaths,
    bool? autoAdvance,
    bool? isAutoAdvancing,
    int? slideshowDelaySeconds,
    VideoPlaybackMode? videoPlaybackMode,
    double? playbackSpeed,
    bool? subtitlesEnabled,
    double? subtitleFontSize,
    double? subtitleVerticalPosition,
    BoxFit? imageFit,
    VideoAspectRatioMode? videoAspectRatioMode,
    PlaylistTransitionEffect? transitionEffect,
    PlaylistScrollMode? scrollMode,
    bool? isMuted,
    Map<String, int>? rotations,
    Map<String, ViewerAdjustments>? adjustments,
    bool? applyAdjustmentsToAll,
    ViewerAdjustments? sharedAdjustments,
    bool? compareOriginal,
    Map<String, int>? imageReloadEpoch,
  }) =>
      MediaViewerSessionState(
        showUI: showUI ?? this.showUI,
        isCarouselVisible: isCarouselVisible ?? this.isCarouselVisible,
        enableCarousel: enableCarousel ?? this.enableCarousel,
        bookmarkPaths: bookmarkPaths ?? this.bookmarkPaths,
        autoAdvance: autoAdvance ?? this.autoAdvance,
        isAutoAdvancing: isAutoAdvancing ?? this.isAutoAdvancing,
        slideshowDelaySeconds:
            slideshowDelaySeconds ?? this.slideshowDelaySeconds,
        videoPlaybackMode: videoPlaybackMode ?? this.videoPlaybackMode,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
        subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
        subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
        subtitleVerticalPosition:
            subtitleVerticalPosition ?? this.subtitleVerticalPosition,
        imageFit: imageFit ?? this.imageFit,
        videoAspectRatioMode:
            videoAspectRatioMode ?? this.videoAspectRatioMode,
        transitionEffect: transitionEffect ?? this.transitionEffect,
        scrollMode: scrollMode ?? this.scrollMode,
        isMuted: isMuted ?? this.isMuted,
        rotations: rotations ?? this.rotations,
        adjustments: adjustments ?? this.adjustments,
        applyAdjustmentsToAll:
            applyAdjustmentsToAll ?? this.applyAdjustmentsToAll,
        sharedAdjustments: sharedAdjustments ?? this.sharedAdjustments,
        compareOriginal: compareOriginal ?? this.compareOriginal,
        imageReloadEpoch: imageReloadEpoch ?? this.imageReloadEpoch,
      );
}

@riverpod
class MediaViewerSession extends _$MediaViewerSession {
  @override
  MediaViewerSessionState build(String sessionKey) =>
      const MediaViewerSessionState();

  void setShowUI(bool show) {
    if (state.showUI == show) return;
    state = state.copyWith(showUI: show);
  }

  void toggleUI() {
    state = state.copyWith(showUI: !state.showUI);
  }

  void setCarouselVisible(bool visible) {
    if (state.isCarouselVisible == visible) return;
    state = state.copyWith(isCarouselVisible: visible);
  }

  void setEnableCarousel(bool enable) {
    if (state.enableCarousel == enable) return;
    state = state.copyWith(enableCarousel: enable);
  }

  void setBookmarkPaths(List<String> paths) {
    state = state.copyWith(bookmarkPaths: List.unmodifiable(paths));
  }

  void toggleBookmark(String path) {
    final list = List<String>.from(state.bookmarkPaths);
    if (list.contains(path)) {
      list.remove(path);
    } else {
      list.add(path);
    }
    state = state.copyWith(bookmarkPaths: List.unmodifiable(list));
  }

  void setAutoAdvance(bool autoAdvance) {
    if (state.autoAdvance == autoAdvance) return;
    state = state.copyWith(autoAdvance: autoAdvance);
  }

  void setIsAutoAdvancing(bool isAdvancing) {
    if (state.isAutoAdvancing == isAdvancing) return;
    state = state.copyWith(isAutoAdvancing: isAdvancing);
  }

  void setSlideshowDelaySeconds(int seconds) {
    if (state.slideshowDelaySeconds == seconds) return;
    state = state.copyWith(slideshowDelaySeconds: seconds);
  }

  void setVideoPlaybackMode(VideoPlaybackMode mode) {
    if (state.videoPlaybackMode == mode) return;
    state = state.copyWith(videoPlaybackMode: mode);
  }

  void setPlaybackSpeed(double speed) {
    if (state.playbackSpeed == speed) return;
    state = state.copyWith(playbackSpeed: speed);
  }

  void setSubtitlesEnabled(bool enabled) {
    if (state.subtitlesEnabled == enabled) return;
    state = state.copyWith(subtitlesEnabled: enabled);
  }

  void setSubtitleFontSize(double size) {
    if (state.subtitleFontSize == size) return;
    state = state.copyWith(subtitleFontSize: size);
  }

  void setSubtitleVerticalPosition(double pos) {
    if (state.subtitleVerticalPosition == pos) return;
    state = state.copyWith(subtitleVerticalPosition: pos);
  }

  void setImageFit(BoxFit fit) {
    if (state.imageFit == fit) return;
    state = state.copyWith(imageFit: fit);
  }

  void setVideoAspectRatioMode(VideoAspectRatioMode mode) {
    if (state.videoAspectRatioMode == mode) return;
    state = state.copyWith(videoAspectRatioMode: mode);
  }

  void setTransitionEffect(PlaylistTransitionEffect effect) {
    if (state.transitionEffect == effect) return;
    state = state.copyWith(transitionEffect: effect);
  }

  void setScrollMode(PlaylistScrollMode mode) {
    if (state.scrollMode == mode) return;
    state = state.copyWith(scrollMode: mode);
  }

  void setIsMuted(bool muted) {
    if (state.isMuted == muted) return;
    state = state.copyWith(isMuted: muted);
  }

  void toggleMute() {
    state = state.copyWith(isMuted: !state.isMuted);
  }

  /// Sets [path]'s rotation in clockwise quarter-turns; anything outside
  /// 0-3 wraps (so 4 -> 0 and -1 -> 3).
  void setRotation(String path, int quarterTurns) {
    final map = Map<String, int>.from(state.rotations);
    map[path] = quarterTurns % 4;
    state = state.copyWith(rotations: Map.unmodifiable(map));
  }

  /// One 90-degree clockwise step.
  void rotateClockwise(String path) {
    setRotation(path, (state.rotations[path] ?? 0) + 1);
  }

  /// Sets the adjustments for [path]. While apply-to-all is on this edits the
  /// shared value instead, so the sheet behaves the same either way.
  ///
  /// Identity values are stored as "no entry" so the map never accumulates
  /// neutral rows.
  void setAdjustments(String path, ViewerAdjustments value) {
    if (state.applyAdjustmentsToAll) {
      if (state.sharedAdjustments == value) return;
      state = state.copyWith(sharedAdjustments: value);
      return;
    }
    final current = state.adjustments[path] ?? ViewerAdjustments.identity;
    if (current == value) return;
    final map = Map<String, ViewerAdjustments>.from(state.adjustments);
    if (value.isIdentity) {
      map.remove(path);
    } else {
      map[path] = value;
    }
    state = state.copyWith(adjustments: Map.unmodifiable(map));
  }

  /// Hold-to-compare: show (true) or stop showing (false) the originals.
  void setCompareOriginal(bool compare) {
    if (state.compareOriginal == compare) return;
    state = state.copyWith(compareOriginal: compare);
  }

  /// Resets the adjustments that currently apply to [path].
  void resetAdjustments(String path) =>
      setAdjustments(path, ViewerAdjustments.identity);

  /// Turns "use these adjustments for every file" on or off.
  ///
  /// Turning it on seeds the shared value from [path]'s current adjustments,
  /// so nothing visibly jumps when the switch is flipped. Turning it off
  /// hands the shared value back to [path] only; other files return to
  /// whatever they had before.
  void setApplyAdjustmentsToAll(String path, bool apply) {
    if (state.applyAdjustmentsToAll == apply) return;
    if (apply) {
      state = state.copyWith(
        applyAdjustmentsToAll: true,
        sharedAdjustments: state.adjustmentsFor(path),
      );
    } else {
      final shared = state.sharedAdjustments;
      final map = Map<String, ViewerAdjustments>.from(state.adjustments);
      if (shared.isIdentity) {
        map.remove(path);
      } else {
        map[path] = shared;
      }
      state = state.copyWith(
        applyAdjustmentsToAll: false,
        adjustments: Map.unmodifiable(map),
      );
    }
  }

  /// Moves [oldPath]'s per-file adjustments to [newPath] after a rename.
  void moveAdjustments(String oldPath, String newPath) {
    final value = state.adjustments[oldPath];
    if (value == null || oldPath == newPath) return;
    final map = Map<String, ViewerAdjustments>.from(state.adjustments)
      ..remove(oldPath)
      ..[newPath] = value;
    state = state.copyWith(adjustments: Map.unmodifiable(map));
  }

  void bumpImageReloadEpoch(String path) {
    final map = Map<String, int>.from(state.imageReloadEpoch);
    map[path] = (map[path] ?? 0) + 1;
    state = state.copyWith(imageReloadEpoch: Map.unmodifiable(map));
  }

  /// Drops the transient per-file state (rotation, adjustments, reload counter) kept for
  /// [path], e.g. once the file has been deleted.
  ///
  /// [MediaViewerSessionState.rotations] and
  /// [MediaViewerSessionState.imageReloadEpoch] are immutable (`const {}` by
  /// default, `Map.unmodifiable` after any setter), so they have to be
  /// replaced rather than mutated: calling `.remove` on them throws
  /// [UnsupportedError] even when [path] isn't in the map.
  void forgetFile(String path) {
    final hasRotation = state.rotations.containsKey(path);
    final hasEpoch = state.imageReloadEpoch.containsKey(path);
    final hasAdjustments = state.adjustments.containsKey(path);
    if (!hasRotation && !hasEpoch && !hasAdjustments) return;
    state = state.copyWith(
      rotations: hasRotation
          ? Map.unmodifiable(
              Map<String, int>.from(state.rotations)..remove(path),
            )
          : null,
      adjustments: hasAdjustments
          ? Map.unmodifiable(
              Map<String, ViewerAdjustments>.from(state.adjustments)
                ..remove(path),
            )
          : null,
      imageReloadEpoch: hasEpoch
          ? Map.unmodifiable(
              Map<String, int>.from(state.imageReloadEpoch)..remove(path),
            )
          : null,
    );
  }
}
