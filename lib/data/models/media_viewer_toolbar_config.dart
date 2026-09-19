import 'media_viewer_action.dart';
import 'scrub_preview_style.dart';
import 'video_aspect_ratio_mode.dart';

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

  const MediaViewerToolbarConfig({
    this.topBarActions = const [
      MediaViewerAction.bookmark,
      MediaViewerAction.playlistMenu,
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
      MediaViewerAction.rename,
      MediaViewerAction.delete,
    ],
    this.advancedSettingsActions = const [
      MediaViewerAction.rotate90,
      MediaViewerAction.imageFit,
      MediaViewerAction.playbackSpeed,
      MediaViewerAction.aspectRatio,
      MediaViewerAction.subtitles,
      MediaViewerAction.audioTrack,
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
    this.scrubPreviewStyle = ScrubPreviewStyle.miniBox,
    this.edgeSwipeBrightnessEnabled = true,
    this.edgeSwipeVolumeEnabled = true,
    this.edgeSwipeHudEnabled = true,
    this.edgeSwipeWidthFraction = 0.25,
    this.pinchZoomOutEnabled = true,
    this.minVideoZoomScale = 0.25,
    this.defaultAspectRatioMode = VideoAspectRatioMode.bestFit,
    this.holdToSpeedMultiplier = 2.0,
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
    ScrubPreviewStyle? scrubPreviewStyle,
    bool? edgeSwipeBrightnessEnabled,
    bool? edgeSwipeVolumeEnabled,
    bool? edgeSwipeHudEnabled,
    double? edgeSwipeWidthFraction,
    bool? pinchZoomOutEnabled,
    double? minVideoZoomScale,
    VideoAspectRatioMode? defaultAspectRatioMode,
    double? holdToSpeedMultiplier,
  }) =>
      MediaViewerToolbarConfig(
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
        holdToSpeedMultiplier:
            holdToSpeedMultiplier ?? this.holdToSpeedMultiplier,
      );

  Map<String, dynamic> toJson() => {
        'topBarActions': topBarActions.map((a) => a.toJson()).toList(),
        'bottomBarActions': bottomBarActions.map((a) => a.toJson()).toList(),
        'moreMenuActions': moreMenuActions.map((a) => a.toJson()).toList(),
        'advancedSettingsActions':
            advancedSettingsActions.map((a) => a.toJson()).toList(),
        'hiddenActions': hiddenActions.map((a) => a.toJson()).toList(),
        'showProgressBar': showProgressBar,
        'showCenterTransport': showCenterTransport,
        'showPreviousNext': showPreviousNext,
        'showCenterScreenPlayButton': showCenterScreenPlayButton,
        'showCenterTransportForImages': showCenterTransportForImages,
        'showStatusBadge': showStatusBadge,
        'scrubPreviewStyle': scrubPreviewStyle.toJson(),
        'edgeSwipeBrightnessEnabled': edgeSwipeBrightnessEnabled,
        'edgeSwipeVolumeEnabled': edgeSwipeVolumeEnabled,
        'edgeSwipeHudEnabled': edgeSwipeHudEnabled,
        'edgeSwipeWidthFraction': edgeSwipeWidthFraction,
        'pinchZoomOutEnabled': pinchZoomOutEnabled,
        'minVideoZoomScale': minVideoZoomScale,
        'defaultAspectRatioMode': defaultAspectRatioMode.toJson(),
        'holdToSpeedMultiplier': holdToSpeedMultiplier,
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

    return MediaViewerToolbarConfig(
      topBarActions: top,
      bottomBarActions: bottom,
      moreMenuActions: more,
      advancedSettingsActions: advanced,
      hiddenActions: hidden,
      showProgressBar: j['showProgressBar'] as bool? ?? true,
      showCenterTransport: j['showCenterTransport'] as bool? ?? true,
      showPreviousNext: j['showPreviousNext'] as bool? ?? true,
      showCenterScreenPlayButton:
          j['showCenterScreenPlayButton'] as bool? ?? false,
      showCenterTransportForImages:
          j['showCenterTransportForImages'] as bool? ?? false,
      showStatusBadge: j['showStatusBadge'] as bool? ?? true,
      scrubPreviewStyle:
          ScrubPreviewStyle.fromJson(j['scrubPreviewStyle'] as String?),
      edgeSwipeBrightnessEnabled:
          j['edgeSwipeBrightnessEnabled'] as bool? ?? true,
      edgeSwipeVolumeEnabled: j['edgeSwipeVolumeEnabled'] as bool? ?? true,
      edgeSwipeHudEnabled: j['edgeSwipeHudEnabled'] as bool? ?? true,
      edgeSwipeWidthFraction:
          (j['edgeSwipeWidthFraction'] as num?)?.toDouble() ?? 0.25,
      pinchZoomOutEnabled: j['pinchZoomOutEnabled'] as bool? ?? true,
      minVideoZoomScale:
          (j['minVideoZoomScale'] as num?)?.toDouble() ?? 0.25,
      defaultAspectRatioMode: VideoAspectRatioMode.fromJson(
        j['defaultAspectRatioMode'] as String?,
      ),
      holdToSpeedMultiplier:
          (j['holdToSpeedMultiplier'] as num?)?.toDouble() ?? 2.0,
    );
  }
}