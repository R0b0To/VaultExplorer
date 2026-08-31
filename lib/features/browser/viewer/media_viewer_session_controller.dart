import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';

part 'media_viewer_session_controller.g.dart';

enum VideoPlaybackMode { playOnce, loop, playAndAdvance }

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
    this.transitionEffect = PlaylistTransitionEffect.slide,
    this.scrollMode = PlaylistScrollMode.horizontal,
    this.isMuted = false,
    this.rotations = const {},
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
  final PlaylistTransitionEffect transitionEffect;
  final PlaylistScrollMode scrollMode;
  final bool isMuted;
  final Map<String, int> rotations;
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
    PlaylistTransitionEffect? transitionEffect,
    PlaylistScrollMode? scrollMode,
    bool? isMuted,
    Map<String, int>? rotations,
    Map<String, int>? imageReloadEpoch,
  }) => MediaViewerSessionState(
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
    transitionEffect: transitionEffect ?? this.transitionEffect,
    scrollMode: scrollMode ?? this.scrollMode,
    isMuted: isMuted ?? this.isMuted,
    rotations: rotations ?? this.rotations,
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

  void setRotation(String path, int degrees) {
    final map = Map<String, int>.from(state.rotations);
    map[path] = degrees;
    state = state.copyWith(rotations: Map.unmodifiable(map));
  }

  void rotateClockwise(String path) {
    final current = state.rotations[path] ?? 0;
    final next = (current + 90) % 360;
    setRotation(path, next);
  }

  void bumpImageReloadEpoch(String path) {
    final map = Map<String, int>.from(state.imageReloadEpoch);
    map[path] = (map[path] ?? 0) + 1;
    state = state.copyWith(imageReloadEpoch: Map.unmodifiable(map));
  }
}
