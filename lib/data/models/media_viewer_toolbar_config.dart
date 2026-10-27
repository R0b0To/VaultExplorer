import 'media_viewer_action.dart';
import 'scrub_preview_style.dart';
import 'video_aspect_ratio_mode.dart';
import 'resume_playback_mode.dart';
import 'thumbnail_generation_strategy.dart';
import 'media_decoder_mode.dart';
import 'audio_equalizer_settings.dart';

class MediaViewerToolbarConfig {
  final List<MediaViewerAction> topBarActions;
  final List<MediaViewerAction> bottomBarActions;
  final List<MediaViewerAction> moreMenuActions;
  final List<MediaViewerAction> advancedSettingsActions;
  final Set<MediaViewerAction> hiddenActions;
  final bool showProgressBar;
  final bool showCenterTransport;
  final bool showPreviousNext;
  final bool showCenterScreenPlayButton;
  final bool showCenterTransportForImages;
  final bool showStatusBadge;
  final bool showFileNamesInMediaNotification;

  /// What the seekbar shows while dragging; see [ScrubPreviewStyle].
  final ScrubPreviewStyle scrubPreviewStyle;

  // -- Video playback gestures & display (Media Player Controls screen) --
  final bool edgeSwipeBrightnessEnabled;
  final bool edgeSwipeVolumeEnabled;
  final bool edgeSwipeHudEnabled;
  final double edgeSwipeWidthFraction;
  final bool pinchZoomOutEnabled;
  final double minVideoZoomScale;
  final VideoAspectRatioMode defaultAspectRatioMode;
  final double holdToSpeedMultiplier;
  final bool swipeToSeekEnabled;

  /// Closes the viewer with a drag: down for a single item or a horizontal
  /// playlist, sideways when the playlist pages vertically (always the axis
  /// opposite to the one that changes items).
  final bool swipeToDismissEnabled;
  final ResumePlaybackMode resumePlaybackMode;

  /// Whether audio keeps playing in the background after the viewer is
  /// closed (controlled from the media notification).
  final bool keepAudioPlayingAfterClose;

  /// Whether a playing video enters Android's picture-in-picture window by
  /// itself when the app is left (home, recents, another app). Off by
  /// default: the viewer's picture-in-picture button enters it on demand.
  final bool pictureInPictureEnabled;
  final bool tapEdgesToNavigate;

  /// Double-tapping the middle of the video or audio screen plays or pauses
  /// instead of zooming. The zoom is then reset from the zoom-level pill.
  final bool doubleTapPlayPause;

  /// Whether double-tapping the left or right side of a video skips backward
  /// or forward. When off, those areas behave like the middle one.
  final bool doubleTapSkipEnabled;

  /// Seconds jumped by one double-tap (repeated taps add up).
  final int doubleTapSkipSeconds;

  /// The skip times offered by the settings slider.
  static const List<int> doubleTapSkipOptions = [3, 5, 10, 15, 20, 30, 45, 60];
  final bool loopPlaylist;
  final ThumbnailGenerationStrategy thumbnailGenerationStrategy;
  final double thumbnailFramePosition;
  final double seekSensitivity;
  final double volumeGestureSensitivity;
  final double brightnessGestureSensitivity;
  final bool volumeBoostEnabled;
  final int volumeBoostGainMb;
  final MediaDecoderMode videoDecoderMode;
  final MediaDecoderMode audioDecoderMode;

  /// The player's audio equalizer (global, not per file).
  final AudioEqualizerSettings equalizer;

  const MediaViewerToolbarConfig({
    this.topBarActions = const [
      MediaViewerAction.bookmark,
      MediaViewerAction.playlistMenu,
      MediaViewerAction.pictureInPicture,
      MediaViewerAction.lockControls,
    ],
    this.bottomBarActions = const [
      MediaViewerAction.mute,
      MediaViewerAction.playbackMode,
      MediaViewerAction.previous,
      MediaViewerAction.playPause,
      MediaViewerAction.next,
      MediaViewerAction.thumbnailCarousel,
      MediaViewerAction.advancedSettings,
    ],
    this.moreMenuActions = const [
      MediaViewerAction.fileInfo,
      MediaViewerAction.openWithApp,
      MediaViewerAction.editImage,
      MediaViewerAction.editVideo,
      MediaViewerAction.editAudio,
      MediaViewerAction.abLoop,
      MediaViewerAction.rename,
      MediaViewerAction.delete,
    ],
    this.advancedSettingsActions = const [
      MediaViewerAction.rotate90,
      MediaViewerAction.imageFit,
      MediaViewerAction.adjustments,
      MediaViewerAction.playbackSpeed,
      MediaViewerAction.aspectRatio,
      MediaViewerAction.decoder,
      MediaViewerAction.subtitles,
      MediaViewerAction.audioTrack,
      MediaViewerAction.equalizer,
      MediaViewerAction.slideshowDelay,
      MediaViewerAction.screenOrientation,
      MediaViewerAction.diagnostics,
    ],
    this.hiddenActions = const {},
    this.showProgressBar = true,
    this.showCenterTransport = true,
    this.showPreviousNext = true,
    this.showCenterScreenPlayButton = false,
    this.showCenterTransportForImages = false,
    this.showStatusBadge = true,
    this.showFileNamesInMediaNotification = false,
    this.scrubPreviewStyle = ScrubPreviewStyle.miniBox,
    this.edgeSwipeBrightnessEnabled = true,
    this.edgeSwipeVolumeEnabled = true,
    this.edgeSwipeHudEnabled = true,
    this.edgeSwipeWidthFraction = 0.25,
    this.pinchZoomOutEnabled = true,
    this.minVideoZoomScale = 0.25,
    this.defaultAspectRatioMode = VideoAspectRatioMode.bestFit,
    this.holdToSpeedMultiplier = 2.0,
    this.swipeToSeekEnabled = false,
    this.swipeToDismissEnabled = false,
    this.resumePlaybackMode = ResumePlaybackMode.askEveryTime,
    this.keepAudioPlayingAfterClose = false,
    this.pictureInPictureEnabled = false,
    this.tapEdgesToNavigate = true,
    this.doubleTapPlayPause = true,
    this.doubleTapSkipEnabled = true,
    this.doubleTapSkipSeconds = 5,
    this.loopPlaylist = true,
    this.thumbnailGenerationStrategy = ThumbnailGenerationStrategy.hybrid,
    this.thumbnailFramePosition = 0.12,
    this.seekSensitivity = 1.0,
    this.volumeGestureSensitivity = 1.0,
    this.brightnessGestureSensitivity = 1.0,
    this.volumeBoostEnabled = false,
    this.volumeBoostGainMb = 2000,
    this.videoDecoderMode = MediaDecoderMode.auto,
    this.audioDecoderMode = MediaDecoderMode.auto,
    this.equalizer = AudioEqualizerSettings.defaults,
  });

  factory MediaViewerToolbarConfig.defaults() =>
      const MediaViewerToolbarConfig();

  MediaViewerToolbarConfig copyWith({
    List<MediaViewerAction>? topBarActions,
    List<MediaViewerAction>? bottomBarActions,
    List<MediaViewerAction>? moreMenuActions,
    List<MediaViewerAction>? advancedSettingsActions,
    Set<MediaViewerAction>? hiddenActions,
    bool? showProgressBar,
    bool? showCenterTransport,
    bool? showPreviousNext,
    bool? showCenterScreenPlayButton,
    bool? showCenterTransportForImages,
    bool? showStatusBadge,
    bool? showFileNamesInMediaNotification,
    ScrubPreviewStyle? scrubPreviewStyle,
    bool? edgeSwipeBrightnessEnabled,
    bool? edgeSwipeVolumeEnabled,
    bool? edgeSwipeHudEnabled,
    double? edgeSwipeWidthFraction,
    bool? pinchZoomOutEnabled,
    double? minVideoZoomScale,
    VideoAspectRatioMode? defaultAspectRatioMode,
    double? holdToSpeedMultiplier,
    bool? swipeToSeekEnabled,
    bool? swipeToDismissEnabled,
    ResumePlaybackMode? resumePlaybackMode,
    bool? keepAudioPlayingAfterClose,
    bool? pictureInPictureEnabled,
    bool? tapEdgesToNavigate,
    bool? doubleTapPlayPause,
    bool? doubleTapSkipEnabled,
    int? doubleTapSkipSeconds,
    bool? loopPlaylist,
    ThumbnailGenerationStrategy? thumbnailGenerationStrategy,
    double? thumbnailFramePosition,
    double? seekSensitivity,
    double? volumeGestureSensitivity,
    double? brightnessGestureSensitivity,
    bool? volumeBoostEnabled,
    int? volumeBoostGainMb,
    MediaDecoderMode? videoDecoderMode,
    MediaDecoderMode? audioDecoderMode,
    AudioEqualizerSettings? equalizer,
  }) => MediaViewerToolbarConfig(
    topBarActions: topBarActions ?? this.topBarActions,
    bottomBarActions: bottomBarActions ?? this.bottomBarActions,
    moreMenuActions: moreMenuActions ?? this.moreMenuActions,
    advancedSettingsActions:
        advancedSettingsActions ?? this.advancedSettingsActions,
    hiddenActions: hiddenActions ?? this.hiddenActions,
    showProgressBar: showProgressBar ?? this.showProgressBar,
    showCenterTransport: showCenterTransport ?? this.showCenterTransport,
    showPreviousNext: showPreviousNext ?? this.showPreviousNext,
    showCenterScreenPlayButton:
        showCenterScreenPlayButton ?? this.showCenterScreenPlayButton,
    showCenterTransportForImages:
        showCenterTransportForImages ?? this.showCenterTransportForImages,
    showStatusBadge: showStatusBadge ?? this.showStatusBadge,
    showFileNamesInMediaNotification:
        showFileNamesInMediaNotification ??
        this.showFileNamesInMediaNotification,
    scrubPreviewStyle: scrubPreviewStyle ?? this.scrubPreviewStyle,
    edgeSwipeBrightnessEnabled:
        edgeSwipeBrightnessEnabled ?? this.edgeSwipeBrightnessEnabled,
    edgeSwipeVolumeEnabled:
        edgeSwipeVolumeEnabled ?? this.edgeSwipeVolumeEnabled,
    edgeSwipeHudEnabled: edgeSwipeHudEnabled ?? this.edgeSwipeHudEnabled,
    edgeSwipeWidthFraction:
        edgeSwipeWidthFraction ?? this.edgeSwipeWidthFraction,
    pinchZoomOutEnabled: pinchZoomOutEnabled ?? this.pinchZoomOutEnabled,
    minVideoZoomScale: minVideoZoomScale ?? this.minVideoZoomScale,
    defaultAspectRatioMode:
        defaultAspectRatioMode ?? this.defaultAspectRatioMode,
    holdToSpeedMultiplier: holdToSpeedMultiplier ?? this.holdToSpeedMultiplier,
    swipeToSeekEnabled: swipeToSeekEnabled ?? this.swipeToSeekEnabled,
    swipeToDismissEnabled:
        swipeToDismissEnabled ?? this.swipeToDismissEnabled,
    resumePlaybackMode: resumePlaybackMode ?? this.resumePlaybackMode,
    keepAudioPlayingAfterClose:
        keepAudioPlayingAfterClose ?? this.keepAudioPlayingAfterClose,
    pictureInPictureEnabled:
        pictureInPictureEnabled ?? this.pictureInPictureEnabled,
    tapEdgesToNavigate: tapEdgesToNavigate ?? this.tapEdgesToNavigate,
    doubleTapPlayPause: doubleTapPlayPause ?? this.doubleTapPlayPause,
    doubleTapSkipEnabled: doubleTapSkipEnabled ?? this.doubleTapSkipEnabled,
    doubleTapSkipSeconds: doubleTapSkipSeconds ?? this.doubleTapSkipSeconds,
    loopPlaylist: loopPlaylist ?? this.loopPlaylist,
    thumbnailGenerationStrategy:
        thumbnailGenerationStrategy ?? this.thumbnailGenerationStrategy,
    thumbnailFramePosition:
        thumbnailFramePosition ?? this.thumbnailFramePosition,
    seekSensitivity: seekSensitivity ?? this.seekSensitivity,
    volumeGestureSensitivity:
        volumeGestureSensitivity ?? this.volumeGestureSensitivity,
    brightnessGestureSensitivity:
        brightnessGestureSensitivity ?? this.brightnessGestureSensitivity,
    volumeBoostEnabled: volumeBoostEnabled ?? this.volumeBoostEnabled,
    volumeBoostGainMb: volumeBoostGainMb ?? this.volumeBoostGainMb,
    videoDecoderMode: videoDecoderMode ?? this.videoDecoderMode,
    audioDecoderMode: audioDecoderMode ?? this.audioDecoderMode,
    equalizer: equalizer ?? this.equalizer,
  );

  /// JSON keys describing what the viewer's controls look like and where they
  /// sit: which buttons exist in which bar, and which on-screen elements are
  /// shown. This is the part that travels with App skin -> Export.
  ///
  /// Everything else (gestures, playback defaults, decoders, equalizer,
  /// thumbnail generation, ...) is behavior and travels with Settings ->
  /// Export. A key added to [toJson] later is behavior unless it is listed
  /// here, which keeps new options out of shared skin files by default.
  static const Set<String> interfaceKeys = {
    'topBarActions',
    'bottomBarActions',
    'moreMenuActions',
    'advancedSettingsActions',
    'hiddenActions',
    'showProgressBar',
    'showCenterTransport',
    'showPreviousNext',
    'showCenterScreenPlayButton',
    'showCenterTransportForImages',
    'showStatusBadge',
    'scrubPreviewStyle',
  };

  Map<String, dynamic> interfaceToJson() {
    final all = toJson();
    return {for (final key in interfaceKeys) key: all[key]};
  }

  Map<String, dynamic> behaviorToJson() => {
    for (final entry in toJson().entries)
      if (!interfaceKeys.contains(entry.key)) entry.key: entry.value,
  };

  /// A copy of this with the layout taken from [other]; behavior is kept.
  MediaViewerToolbarConfig withInterfaceFrom(MediaViewerToolbarConfig other) =>
      MediaViewerToolbarConfig.fromJson({
        ...toJson(),
        ...other.interfaceToJson(),
      });

  /// A copy of this with the behavior taken from [other]; layout is kept.
  MediaViewerToolbarConfig withBehaviorFrom(MediaViewerToolbarConfig other) =>
      MediaViewerToolbarConfig.fromJson({
        ...toJson(),
        ...other.behaviorToJson(),
      });

  Map<String, dynamic> toJson() => {
    'topBarActions': topBarActions.map((a) => a.toJson()).toList(),
    'bottomBarActions': bottomBarActions.map((a) => a.toJson()).toList(),
    'moreMenuActions': moreMenuActions.map((a) => a.toJson()).toList(),
    'advancedSettingsActions': advancedSettingsActions
        .map((a) => a.toJson())
        .toList(),
    'hiddenActions': hiddenActions.map((a) => a.toJson()).toList(),
    'showProgressBar': showProgressBar,
    'showCenterTransport': showCenterTransport,
    'showPreviousNext': showPreviousNext,
    'showCenterScreenPlayButton': showCenterScreenPlayButton,
    'showCenterTransportForImages': showCenterTransportForImages,
    'showStatusBadge': showStatusBadge,
    'showFileNamesInMediaNotification': showFileNamesInMediaNotification,
    'scrubPreviewStyle': scrubPreviewStyle.toJson(),
    'edgeSwipeBrightnessEnabled': edgeSwipeBrightnessEnabled,
    'edgeSwipeVolumeEnabled': edgeSwipeVolumeEnabled,
    'edgeSwipeHudEnabled': edgeSwipeHudEnabled,
    'edgeSwipeWidthFraction': edgeSwipeWidthFraction,
    'pinchZoomOutEnabled': pinchZoomOutEnabled,
    'minVideoZoomScale': minVideoZoomScale,
    'defaultAspectRatioMode': defaultAspectRatioMode.toJson(),
    'holdToSpeedMultiplier': holdToSpeedMultiplier,
    'swipeToSeekEnabled': swipeToSeekEnabled,
    'swipeToDismissEnabled': swipeToDismissEnabled,
    'resumePlaybackMode': resumePlaybackMode.name,
    'keepAudioPlayingAfterClose': keepAudioPlayingAfterClose,
    'pictureInPictureEnabled': pictureInPictureEnabled,
    'tapEdgesToNavigate': tapEdgesToNavigate,
    'doubleTapPlayPause': doubleTapPlayPause,
    'doubleTapSkipEnabled': doubleTapSkipEnabled,
    'doubleTapSkipSeconds': doubleTapSkipSeconds,
    'loopPlaylist': loopPlaylist,
    'thumbnailGenerationStrategy': thumbnailGenerationStrategy.name,
    'thumbnailFramePosition': thumbnailFramePosition,
    'seekSensitivity': seekSensitivity,
    'volumeGestureSensitivity': volumeGestureSensitivity,
    'brightnessGestureSensitivity': brightnessGestureSensitivity,
    'volumeBoostEnabled': volumeBoostEnabled,
    'volumeBoostGainMb': volumeBoostGainMb,
    'videoDecoderMode': videoDecoderMode.name,
    'audioDecoderMode': audioDecoderMode.name,
    'equalizer': equalizer.toJson(),
  };

  factory MediaViewerToolbarConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return MediaViewerToolbarConfig.defaults();

    const def = MediaViewerToolbarConfig();

    final top = j.containsKey('topBarActions')
        ? (j['topBarActions'] as List<dynamic>? ?? [])
              .map((v) => MediaViewerAction.fromJson(v as String?))
              .whereType<MediaViewerAction>()
              .toList()
        : def.topBarActions;

    final bottom = j.containsKey('bottomBarActions')
        ? (j['bottomBarActions'] as List<dynamic>? ?? [])
              .map((v) => MediaViewerAction.fromJson(v as String?))
              .whereType<MediaViewerAction>()
              .toList()
        : def.bottomBarActions;

    final more = j.containsKey('moreMenuActions')
        ? (j['moreMenuActions'] as List<dynamic>? ?? [])
              .map((v) => MediaViewerAction.fromJson(v as String?))
              .whereType<MediaViewerAction>()
              .toList()
        : def.moreMenuActions;

    final advanced = j.containsKey('advancedSettingsActions')
        ? (j['advancedSettingsActions'] as List<dynamic>? ?? [])
              .map((v) => MediaViewerAction.fromJson(v as String?))
              .whereType<MediaViewerAction>()
              .toList()
        : def.advancedSettingsActions;

    final hidden = (j['hiddenActions'] as List<dynamic>? ?? [])
        .map((v) => MediaViewerAction.fromJson(v as String?))
        .whereType<MediaViewerAction>()
        .toSet();

    // A config saved before `editVideo` existed doesn't list it anywhere. Every
    // action always lives in exactly one section (the settings screen only ever
    // moves them), so "in none" means "new": put it in the More menu.
    final placed = {...top, ...bottom, ...more, ...advanced, ...hidden};
    final moreWithNew = placed.contains(MediaViewerAction.editVideo)
        ? more
        : [...more, MediaViewerAction.editVideo];

    // Same for `editAudio`: it joins the More menu next to `editVideo`.
    final placedAudio = {...top, ...bottom, ...moreWithNew, ...advanced, ...hidden};
    final moreWithAudio = placedAudio.contains(MediaViewerAction.editAudio)
        ? moreWithNew
        : [...moreWithNew, MediaViewerAction.editAudio];

    // A config saved before `decoder` existed doesn't list it anywhere.
    final placed2 = {...top, ...bottom, ...moreWithAudio, ...advanced, ...hidden};
    final advancedWithDecoder = placed2.contains(MediaViewerAction.decoder)
        ? advanced
        : [...advanced, MediaViewerAction.decoder];

    // Same for `adjustments`: a config saved before it existed doesn't list
    // it anywhere, so it joins the Advanced settings list.
    final placed3 = {
      ...top,
      ...bottom,
      ...moreWithAudio,
      ...advancedWithDecoder,
      ...hidden,
    };
    final advancedWithNew = placed3.contains(MediaViewerAction.adjustments)
        ? advancedWithDecoder
        : [...advancedWithDecoder, MediaViewerAction.adjustments];

    // Same for `abLoop`: a saved layout is the person's own arrangement, so
    // the new action joins the More menu instead of crowding the bottom bar.
    final placed4 = {
      ...top,
      ...bottom,
      ...moreWithAudio,
      ...advancedWithNew,
      ...hidden,
    };
    final moreWithAbLoop = placed4.contains(MediaViewerAction.abLoop)
        ? moreWithAudio
        : [...moreWithAudio, MediaViewerAction.abLoop];

    // Same for `equalizer`: it joins the Advanced settings list.
    final placed5 = {
      ...top,
      ...bottom,
      ...moreWithAbLoop,
      ...advancedWithNew,
      ...hidden,
    };
    final advancedWithEqualizer = placed5.contains(MediaViewerAction.equalizer)
        ? advancedWithNew
        : [...advancedWithNew, MediaViewerAction.equalizer];

    // Same for `pictureInPicture`: a saved layout is the person's own
    // arrangement, so it joins the More menu instead of crowding a bar.
    final placed6 = {
      ...top,
      ...bottom,
      ...moreWithAbLoop,
      ...advancedWithEqualizer,
      ...hidden,
    };
    final moreWithPip = placed6.contains(MediaViewerAction.pictureInPicture)
        ? moreWithAbLoop
        : [...moreWithAbLoop, MediaViewerAction.pictureInPicture];

    // Same for `lockControls`: it joins the More menu rather than crowding a
    // bar the person has already arranged.
    final placed7 = {
      ...top,
      ...bottom,
      ...moreWithPip,
      ...advancedWithEqualizer,
      ...hidden,
    };
    final moreWithLock = placed7.contains(MediaViewerAction.lockControls)
        ? moreWithPip
        : [...moreWithPip, MediaViewerAction.lockControls];

    return MediaViewerToolbarConfig(
      topBarActions: top,
      bottomBarActions: bottom,
      moreMenuActions: moreWithLock,
      advancedSettingsActions: advancedWithEqualizer,
      hiddenActions: hidden,
      showProgressBar: j['showProgressBar'] as bool? ?? true,
      showCenterTransport: j['showCenterTransport'] as bool? ?? true,
      showPreviousNext: j['showPreviousNext'] as bool? ?? true,
      showCenterScreenPlayButton:
          j['showCenterScreenPlayButton'] as bool? ?? false,
      showCenterTransportForImages:
          j['showCenterTransportForImages'] as bool? ?? false,
      showStatusBadge: j['showStatusBadge'] as bool? ?? true,
      showFileNamesInMediaNotification:
          j['showFileNamesInMediaNotification'] as bool? ?? false,
      scrubPreviewStyle: ScrubPreviewStyle.fromJson(
        j['scrubPreviewStyle'] as String?,
      ),
      edgeSwipeBrightnessEnabled:
          j['edgeSwipeBrightnessEnabled'] as bool? ?? true,
      edgeSwipeVolumeEnabled: j['edgeSwipeVolumeEnabled'] as bool? ?? true,
      edgeSwipeHudEnabled: j['edgeSwipeHudEnabled'] as bool? ?? true,
      edgeSwipeWidthFraction:
          (j['edgeSwipeWidthFraction'] as num?)?.toDouble() ?? 0.25,
      pinchZoomOutEnabled: j['pinchZoomOutEnabled'] as bool? ?? true,
      minVideoZoomScale: (j['minVideoZoomScale'] as num?)?.toDouble() ?? 0.25,
      defaultAspectRatioMode: VideoAspectRatioMode.fromJson(
        j['defaultAspectRatioMode'] as String?,
      ),
      holdToSpeedMultiplier:
          (j['holdToSpeedMultiplier'] as num?)?.toDouble() ?? 2.0,
      swipeToSeekEnabled: j['swipeToSeekEnabled'] as bool? ?? false,
      swipeToDismissEnabled: j['swipeToDismissEnabled'] as bool? ?? false,
      resumePlaybackMode: ResumePlaybackMode.values.firstWhere(
        (mode) => mode.name == j['resumePlaybackMode'],
        orElse: () => ResumePlaybackMode.askEveryTime,
      ),
      keepAudioPlayingAfterClose:
          j['keepAudioPlayingAfterClose'] as bool? ?? false,
      pictureInPictureEnabled: j['pictureInPictureEnabled'] as bool? ?? false,
      tapEdgesToNavigate: j['tapEdgesToNavigate'] as bool? ?? true,
      doubleTapPlayPause: j['doubleTapPlayPause'] as bool? ?? true,
      doubleTapSkipEnabled: j['doubleTapSkipEnabled'] as bool? ?? true,
      doubleTapSkipSeconds: ((j['doubleTapSkipSeconds'] as num?)?.toInt() ?? 5)
          .clamp(1, 600)
          .toInt(),
      loopPlaylist: j['loopPlaylist'] as bool? ?? true,
      thumbnailGenerationStrategy: ThumbnailGenerationStrategy.fromJson(
        j['thumbnailGenerationStrategy'] as String?,
      ),
      thumbnailFramePosition:
          (j['thumbnailFramePosition'] as num?)?.toDouble() ?? 0.12,
      seekSensitivity: (j['seekSensitivity'] as num?)?.toDouble() ?? 1.0,
      volumeGestureSensitivity:
          (j['volumeGestureSensitivity'] as num?)?.toDouble() ?? 1.0,
      brightnessGestureSensitivity:
          (j['brightnessGestureSensitivity'] as num?)?.toDouble() ?? 1.0,
      volumeBoostEnabled: j['volumeBoostEnabled'] as bool? ?? false,
      volumeBoostGainMb: (j['volumeBoostGainMb'] as num?)?.toInt() ?? 2000,
      videoDecoderMode: MediaDecoderMode.fromJson(
        j['videoDecoderMode'] as String?,
      ),
      audioDecoderMode: MediaDecoderMode.fromJson(
        j['audioDecoderMode'] as String?,
      ),
      equalizer: AudioEqualizerSettings.fromJson(j['equalizer']),
    );
  }
}
