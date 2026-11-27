import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_transfer_service.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_frame.dart';
import 'package:vaultexplorer/core/windowing/window_caption.dart';
import 'package:vaultexplorer/core/windowing/view_focus.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/scrub_preview_style.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/video_aspect_ratio_mode.dart';
import 'package:vaultexplorer/data/models/resume_playback_mode.dart';
import 'package:vaultexplorer/data/models/audio_equalizer_settings.dart';
import 'package:vaultexplorer/data/models/media_decoder_mode.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_pins_bookmarks_controller.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/viewer/carousel_geometry.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_lock_controller.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/media_playback_paths.dart';
import 'package:vaultexplorer/features/browser/viewer/media_session_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/pip/picture_in_picture_coordinator.dart';
import 'package:vaultexplorer/features/browser/viewer/media_prefetch_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_swipe_claim.dart';
import 'package:vaultexplorer/features/browser/viewer/screen_brightness_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/browser/viewer/video_scrub_preview_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/ab_loop_toast.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_sheet.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/image_page_item.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_player_widget.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_lock_overlay.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_top_bar.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_bottom_controls.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_in_place_layout_editor.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/advanced_settings_sheet.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/audio_equalizer_sheet.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_diagnostics_sheet.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/swipe_to_dismiss_layer.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/video_scrub_fullscreen_layer.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/image_special_modes_layer.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_screen.dart';
import 'package:vaultexplorer/features/video_editor/video_editor_screen.dart';
import 'package:vaultexplorer/features/audio_editor/audio_editor_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/playlist_carousel_overlay.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/playlist_transition_transformer.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_session_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/models/ab_loop_state.dart';
import 'package:vaultexplorer/features/browser/viewer/models/viewer_adjustments.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/adjustments_sheet.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/color_adjust_filter.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_toolbar_settings_screen.dart';

export 'package:vaultexplorer/features/browser/viewer/media_viewer_session_controller.dart'
    show VideoPlaybackMode;
import '../../../core/theme/app_theme.dart';
import 'native_video_controller.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/widgets/menus/back_dismissible_menu_anchor.dart';

part 'media_viewer_screen_controls.dart';
part 'media_viewer_screen_file_actions.dart';
part 'media_viewer_screen_gestures.dart';
part 'media_viewer_screen_handoff.dart';
part 'media_viewer_screen_playback.dart';
part 'media_viewer_screen_sheets.dart';

class MediaViewerScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final List<String> mediaFiles;
  final int initialIndex;
  final String? startingFolder;
  final ThumbnailQuality thumbnailQuality;
  final ThumbnailCacheMode thumbnailCacheMode;
  final String? mediaFilter;
  final SortBy sortBy;
  final bool sortAscending;
  final Set<String>? pinnedPaths;

  /// Overrides the "keep audio playing after closing" setting for this viewer:
  /// true hands music over to the background session whatever the setting is
  /// (the music library's mini player takes it from there), null follows the
  /// setting.
  final bool? keepAudioPlayingOnClose;

  /// Initializes and starts this viewer's audio, then hands it to the mini
  /// player without drawing the full viewer first.
  final bool startInMiniPlayer;

  /// Marks sessions created by the music library so its mini player can
  /// change tracks without creating a second player session.
  final bool isLibraryPlayback;
  final ValueChanged<String>? onCurrentFileChanged;
  final ValueChanged<String>? onFileDeleted;

  /// A media file staged from an archive. It is short-lived, so mutation,
  /// export, bookmark, and playlist actions must not be available.
  final bool isArchivePreview;

  const MediaViewerScreen({
    super.key,
    required this.container,
    required this.mediaFiles,
    required this.initialIndex,
    this.startingFolder,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    required this.thumbnailCacheMode,
    this.mediaFilter,
    this.sortBy = SortBy.name,
    this.sortAscending = true,
    this.pinnedPaths,
    this.keepAudioPlayingOnClose,
    this.startInMiniPlayer = false,
    this.isLibraryPlayback = false,
    this.onCurrentFileChanged,
    this.onFileDeleted,
    this.isArchivePreview = false,
  });

  bool get _isPreviewOnly => isArchivePreview;

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

/// How the viewer is closing with respect to the floating player.
enum _FloatingClose {
  /// Not closing that way.
  none,

  /// Handing the video to the floating player, which could not be told where
  /// the video is: no Hero flight back to the thumbnail, but nothing flies in
  /// either; the window just appears when the viewer is gone.
  withoutFlight,

  /// Handing the video over, and the floating window is flying out of it: the
  /// viewer must not draw its own copy as well.
  flying,
}

/// The viewer growing out of the floating window it was opened from. First
/// only [from] (the window's video, where the viewer's own is still hidden
/// while it is measured), then [dest] (where the viewer's video really is),
/// [origin] (where the media layer sits on screen) and the [animation].
class _ExpandFlight {
  final Rect from;
  final Rect? dest;
  final Offset origin;
  final Animation<double>? animation;

  const _ExpandFlight({
    required this.from,
    this.dest,
    this.origin = Offset.zero,
    this.animation,
  });
}

/// Clips to a rounded rectangle anywhere in the box, not only the box itself.
class _RRectClipper extends CustomClipper<RRect> {
  final Rect rect;
  final double radius;

  const _RRectClipper(this.rect, this.radius);

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  @override
  bool shouldReclip(covariant _RRectClipper oldClipper) =>
      oldClipper.rect != rect || oldClipper.radius != radius;
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen>
    with TickerProviderStateMixin {
  late final VaultFileIoApi _fileIoApi;
  late final VaultEngineEvents _engineEvents;
  late final MediaPrefetchController _prefetchController;

  late final PlaylistController _playlistController;
  late final VideoPlaybackManager _playbackManager;
  late PageController _pageController;
  late ScrollController _listScrollController;
  late final TransformationController _continuousTransformationController;
  double _continuousScale = 1.0;
  AnimationController? _continuousZoomAnimationController;
  Animation<Matrix4>? _continuousZoomAnimation;
  TapDownDetails? _continuousDoubleTapDetails;
  final ValueNotifier<ScrollPhysics> _swipePhysicsNotifier =
      ValueNotifier<ScrollPhysics>(const BouncingScrollPhysics());

  /// Hands a swipe that an item claims for the playlist pager to the pager as
  /// a drag, so the page follows the finger and a drag that falls short is
  /// cancelled. See [PlaylistSwipeClaimLayer].
  late final PlaylistSwipeDrag _playlistSwipeDrag = PlaylistSwipeDrag(
    positionOf: () =>
        _pageController.hasClients && _pageController.positions.length == 1
        ? _pageController.position
        : null,
    canClaim: _canClaimPlaylistSwipe,
    crossAxisYieldRatio: _playlistSwipeCrossAxisYield,
  );

  /// Whether a finger may swipe the playlist pager right now. Frozen scroll
  /// physics mean something else owns the touch: a zoomed item, a pinch, a
  /// brightness, volume or seek drag, a page change under way.
  bool _canClaimPlaylistSwipe() =>
      mounted &&
      !_scrollMode.isContinuous &&
      _playlistController.playlist.length > 1 &&
      _swipePhysicsNotifier.value is! NeverScrollableScrollPhysics;

  /// How clearly a drag has to lean across the paging axis before the pager's
  /// claim leaves it to the recognizer that owns drags in that direction:
  /// swipe to dismiss (which always works across the paging axis) or, in a
  /// vertical playlist, swipe to seek. Null when neither can start for this
  /// touch, so the claim keeps taking drags of any direction: an L-shaped
  /// swipe may well start out across the axis. Asked when a finger lands.
  double? _playlistSwipeCrossAxisYield() {
    final config = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config
        .mediaViewerToolbarConfig;
    // The same conditions the swipe-to-dismiss layer is enabled under.
    if (config.swipeToDismissEnabled &&
        !_isEditingLayout &&
        !_controlsLocked &&
        _canStartSwipeDismiss()) {
      return kPlaylistSwipeDismissYieldRatio;
    }
    if (_scrollMode == PlaylistScrollMode.verticalPage &&
        _isCurrentItemSwipeToSeekEnabled) {
      return kPlaylistSwipeSeekYieldRatio;
    }
    return null;
  }

  /// 0..1 while a swipe-to-dismiss drag pulls the media away. Drives the
  /// backdrop and viewer chrome fade while the actual image stays visible.
  final ValueNotifier<double> _swipeDismissProgress = ValueNotifier<double>(
    0.0,
  );

  /// Asked, as a close begins, where the video on screen is.
  final VideoFrameProbe _videoProbe = VideoFrameProbe();

  /// Set when the close hands the playing video to the floating player.
  final ValueNotifier<_FloatingClose> _floatingClose =
      ValueNotifier<_FloatingClose>(_FloatingClose.none);
  AnimationController? _closeFade;
  Timer? _floatingCloseGuard;

  /// 0 while the viewer opens out of the floating window (backdrop and
  /// controls not yet there), 1 otherwise. A factor of its own: the swipe
  /// progress also fades the video itself, which must stay solid here.
  final ValueNotifier<double> _openReveal = ValueNotifier<double>(1.0);

  /// Set while the video grows out of the floating window.
  final ValueNotifier<_ExpandFlight?> _expandFlight =
      ValueNotifier<_ExpandFlight?>(null);
  AnimationController? _expandController;

  /// The media layer, as built while it is still waiting to be measured: its
  /// position on screen is the origin the flight is worked out against.
  BuildContext? _expandLayerContext;

  /// The A-B repeat section of the video now playing. In memory only, and
  /// emptied whenever another item (hence a fresh native player) takes over.
  final ValueNotifier<AbLoopState> _abLoopNotifier = ValueNotifier<AbLoopState>(
    AbLoopState.empty,
  );
  final ValueNotifier<String?> _abLoopToast = ValueNotifier<String?>(null);
  Timer? _abLoopToastTimer;
  final ValueNotifier<VideoPlaybackProgress> _videoProgressNotifier =
      ValueNotifier<VideoPlaybackProgress>(const VideoPlaybackProgress());
  // Carries the seekbar's current drag session to the fullscreen scrub
  // preview layer (see ScrubPreviewStyle.fullscreen). Null between drags,
  // and always null in mini-box mode.
  final VideoScrubPreviewHost _scrubPreviewHost = VideoScrubPreviewHost(null);

  bool _isEditingLayout = false;

  /// Touch lock: while on, [MediaViewerLockOverlay] swallows every touch so a
  /// stray tap or swipe can't pause, seek, zoom, switch item or close the
  /// viewer. Lasts for this viewer only; it is never saved.
  bool _controlsLocked = false;

  // Keyboard-adjusted volume (0-100). Mute still wins over it; see
  // [_effectiveVolume]. Kept for the lifetime of the viewer so it carries
  // across playlist items like the mute state does.
  int _volumeLevel = 100;
  int get _effectiveVolume => _isMuted ? 0 : _volumeLevel;

  /// Bumped to reveal the lock button without a touch (a back press while
  /// locked).
  final ValueNotifier<int> _lockNudge = ValueNotifier<int>(0);

  // Raw pointer tracking so a second finger touching down immediately locks
  // out swipe-to-next-item, before the gesture arena has a chance to let
  // the PageView/ListView drag recognizer mistake the pinch for a swipe.
  final Set<int> _activeTouchPointers = {};
  final Map<int, Offset> _edgeTapStartPositions = {};
  final Map<int, bool> _edgeTapDirections = {};
  final Map<int, bool> _edgeTapStartedDuringTransition = {};
  final Map<int, Offset> _loopSwipeStartPositions = {};
  final Map<int, int> _loopSwipeStartIndices = {};
  bool _multiTouchLock = false;
  // Whether an item's InteractiveViewer currently considers itself zoomed
  // or mid-interaction (reported via onZoomChanged). Kept separate from
  // _multiTouchLock so either source can hold the lock independently.
  bool _zoomInteractionLock = false;
  String? _zoomLockFile;
  String? _motionPhotoActiveFile;
  bool _motionPhotoAutoplay = false;
  int _motionPhotoPreferenceRevision = 0;
  String? _panoramaActiveFile;
  int _motionPhotoActivationToken = 0;

  int _activeMenuCount = 0;
  late bool _wasEmpty;

  // Coalesces bursts of `preloadAspectRatios` callbacks (one per file whose
  // true aspect ratio was just learned) into a single setState per frame,
  // same pattern as file_masonry_view.dart's `_scheduleRebuild`.
  bool _hasPendingGeometryRebuild = false;
  // Folder scope the background aspect-ratio preload was last kicked off
  // for, so switching folders (which swaps `_playlistController.playlist`)
  // re-runs it instead of leaving the new items on the 16:9 fallback.
  String? _aspectRatioPreloadFolder;

  Timer? _slideshowTimer;
  Timer? _hideTimer;

  /// The desktop window is in fullscreen. Only then does the chrome hide on
  /// its own, like a media player: in a normal window the controls stay.
  bool _desktopFullscreen = false;

  /// Names the window to the runner, kept so fullscreen can be left from
  /// dispose, where there is no context any more.
  Map<String, Object?>? _fullscreenWindowArgs;

  /// Measured heights of the top bar and of the bottom controls (with the
  /// carousel when it is open). On desktop, outside fullscreen, the media is
  /// laid out between them instead of under them.
  double _topChromeHeight = 72;
  double _bottomChromeHeight = 150;

  /// Whether the controls take space of their own (a desktop window) rather
  /// than float over the media (a phone, or fullscreen).
  bool get _chromeDocked =>
      PlatformFeatures.isDesktop && !_desktopFullscreen && _showUI;

  void _setChromeHeight({double? top, double? bottom}) {
    if (!mounted) return;
    final newTop = top ?? _topChromeHeight;
    final newBottom = bottom ?? _bottomChromeHeight;
    if ((newTop - _topChromeHeight).abs() < 0.5 &&
        (newBottom - _bottomChromeHeight).abs() < 0.5) {
      return;
    }
    setState(() {
      _topChromeHeight = newTop;
      _bottomChromeHeight = newBottom;
    });
  }

  /// Whether the controls hide by themselves (a phone, or a desktop window in
  /// fullscreen) rather than stay up (a desktop window).
  bool get _chromeAutoHides => !PlatformFeatures.isDesktop || _desktopFullscreen;
  Timer? _prefetchDebounceTimer;
  Future<void> _playbackModeSaveQueue = Future<void>.value();
  int _playbackModeInteractionRevision = 0;

  final bool _autoPlay = true;
  double _viewportWidth = 0.0;
  double _viewportHeight = 0.0;
  bool _isSwiping = false;
  bool _isProgrammaticScrolling = false;
  int _viewportCorrectionToken = 0;

  NativeVideoController? _lastListenedController;
  bool _wakelockEnabled = false;
  bool _lockedRouteDismissalScheduled = false;

  /// Prepared in [_prepareBackgroundPlaybackHandoff] when the person closes the
  /// viewer with audio playing and "keep audio playing after closing" is on,
  /// or with a video playing and the floating video player on; [dispose] gives
  /// it to [BackgroundPlaybackHost] instead of releasing the player.
  BackgroundPlaybackSession? _backgroundPlaybackHandoff;

  /// The item whose already-running player this viewer took over from
  /// background playback, so [_activateCurrentMedia] doesn't seek it back to a
  /// saved position.
  String? _adoptedFile;
  int _transitionToken = 0;
  int _resumeFlowToken = 0;
  bool _resumeFlowStarted = false;
  final Map<String, String> _resumePositionKeys = {};
  final Map<String, Duration> _lastSavedPlaybackPositions = {};
  int _screenOrientationModeIndex = 2;

  String get _sessionKey => widget.container.uri;

  MediaViewerSessionState get _session =>
      ref.read(mediaViewerSessionProvider(_sessionKey));

  MediaViewerSession get _sessionController =>
      ref.read(mediaViewerSessionProvider(_sessionKey).notifier);

  bool get _showUI => _session.showUI;
  bool get _isCarouselVisible => _session.isCarouselVisible;
  bool get _enableCarousel => _session.enableCarousel;
  // Bookmarks and pins are the file browser's, shared through one provider,
  // so a bookmark added here shows up there and vice versa. build() watches
  // the provider; these read it, like the session getters above.
  FileBrowserPinsBookmarksState get _marks =>
      ref.read(fileBrowserPinsBookmarksProvider(widget.container.volId));
  FileBrowserPinsBookmarks get _marksNotifier => ref.read(
    fileBrowserPinsBookmarksProvider(widget.container.volId).notifier,
  );
  bool get _autoAdvance => _session.autoAdvance;
  bool get _isAutoAdvancing => _session.isAutoAdvancing;
  int get _slideshowDelaySeconds => _session.slideshowDelaySeconds;
  VideoPlaybackMode get _videoPlaybackMode => _session.videoPlaybackMode;
  double get _playbackSpeed => _session.playbackSpeed;
  bool get _subtitlesEnabled => _session.subtitlesEnabled;
  double get _subtitleFontSize => _session.subtitleFontSize;
  double get _subtitleVerticalPosition => _session.subtitleVerticalPosition;
  BoxFit get _imageFit => _session.imageFit;
  VideoAspectRatioMode get _videoAspectRatioMode =>
      _session.videoAspectRatioMode;
  PlaylistTransitionEffect get _transitionEffect => _session.transitionEffect;
  PlaylistScrollMode get _scrollMode => _session.scrollMode;
  bool get _isMuted => _session.isMuted;
  Map<String, int> get _rotations => _session.rotations;

  /// Adjustments drawn for [path]: shared across files when apply-to-all is
  /// on, and none while "hold to compare" is pressed.
  ViewerAdjustments _adjustmentsFor(String path) =>
      _session.effectiveAdjustmentsFor(path);
  Map<String, int> get _imageReloadEpoch => _session.imageReloadEpoch;

  static const _archivePreviewActions = {
    MediaViewerAction.playPause,
    MediaViewerAction.playbackSpeed,
    MediaViewerAction.rotate90,
    MediaViewerAction.screenOrientation,
    MediaViewerAction.adjustments,
    MediaViewerAction.mute,
    MediaViewerAction.playbackMode,
    MediaViewerAction.abLoop,
    MediaViewerAction.subtitles,
    MediaViewerAction.audioTrack,
    MediaViewerAction.equalizer,
    MediaViewerAction.aspectRatio,
    MediaViewerAction.advancedSettings,
    MediaViewerAction.diagnostics,
    MediaViewerAction.lockControls,
  };

  MediaViewerToolbarConfig _effectiveToolbarConfig(
    MediaViewerToolbarConfig config,
  ) {
    final hideCarouselAction = !_enableCarousel;
    // No picture-in-picture button on a device without the feature.
    final hidePictureInPicture = !PictureInPictureBridge.isSupported.value;
    if (!widget._isPreviewOnly &&
        !hideCarouselAction &&
        !hidePictureInPicture) {
      return config;
    }
    List<MediaViewerAction> filter(List<MediaViewerAction> actions) =>
        actions.where((action) {
          if (widget._isPreviewOnly &&
              !_archivePreviewActions.contains(action)) {
            return false;
          }
          if (hidePictureInPicture &&
              action == MediaViewerAction.pictureInPicture) {
            return false;
          }
          return !hideCarouselAction ||
              action != MediaViewerAction.thumbnailCarousel;
        }).toList();
    return config.copyWith(
      topBarActions: filter(config.topBarActions),
      bottomBarActions: filter(config.bottomBarActions),
      moreMenuActions: filter(config.moreMenuActions),
      advancedSettingsActions: filter(config.advancedSettingsActions),
      showPreviousNext: widget._isPreviewOnly ? false : config.showPreviousNext,
      showStatusBadge: widget._isPreviewOnly ? false : config.showStatusBadge,
    );
  }

  @override
  void initState() {
    super.initState();
    // A phone opens the viewer with the controls tucked away (tap to show);
    // a desktop window opens it with them up and keeps them there.
    if (PlatformFeatures.isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sessionController.setShowUI(true);
      });
    }
    // Warm the adjustment shader so the first slider drag already uses the
    // gamma-capable path instead of the matrix fallback.
    unawaited(ViewerAdjustShader.ensureLoaded());
    _fileIoApi = ref.read(vaultFileIoApiProvider);
    _engineEvents = ref.read(vaultEngineEventsProvider);
    _prefetchController =
        MediaPrefetchController(
            container: widget.container,
            fileIoApi: _fileIoApi,
            thumbnailCache: ref.read(thumbnailCacheServiceProvider),
            thumbnailQuality: widget.thumbnailQuality,
            thumbnailCacheMode: widget.thumbnailCacheMode,
          )
          ..onRatioLearned = () {
            // A video thumbnail taught the viewer a shape it had been guessing
            // at (16:9): lay the carousel out again, coalesced.
            if (mounted) _scheduleGeometryRebuild();
          };
    ThumbnailConcurrency.videoLimiter.cancelAll();
    if (!widget.startInMiniPlayer) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    _engineEvents.addUsbContainerDetachedListener(_onContainerDetached);
    _mediaSessionSubscription = MediaSessionBridge.actions.listen(
      _onMediaSessionAction,
    );

    BackgroundPlaybackHost.instance.registerViewer();
    // Opening the very item that is still playing in the background: take the
    // running player over instead of starting another one.
    final carried =
        widget._isPreviewOnly ||
            widget.initialIndex < 0 ||
            widget.initialIndex >= widget.mediaFiles.length
        ? null
        : BackgroundPlaybackHost.instance.takeMatching(
            widget.container,
            widget.mediaFiles[widget.initialIndex],
          );

    _playlistController = PlaylistController(
      container: widget.container,
      fileIoApi: _fileIoApi,
      initialMediaFiles: widget.mediaFiles,
      initialIndex: widget.initialIndex,
      startingFolder: widget.startingFolder,
      mediaFilter: widget.mediaFilter,
      sortBy: widget.sortBy,
      sortAscending: widget.sortAscending,
      pinnedPaths: widget.pinnedPaths,
    );
    _wasEmpty = _playlistController.isEmpty;
    _zoomLockFile = _playlistController.currentFile;
    _playbackManager = carried?.playbackManager ?? VideoPlaybackManager();
    if (carried != null) {
      _adoptedFile = _playbackManager.currentFileName;
      // The player is already past its resume decision; don't run it again.
      _resumeFlowStarted = true;
      if (widget.startInMiniPlayer) {
        final controller = _playbackManager.activeController;
        if (controller != null && !controller.value.isPlaying) {
          unawaited(controller.playWhenReady());
        }
      }
      // Opened from the floating player: the video grows out of the window
      // instead of appearing full screen. Until it is drawn where the window
      // is, the viewer's own copy stays hidden and the window stays up.
      final from = carried.floatingPlayer
          ? BackgroundPlaybackHost.instance.exit?.from
          : null;
      if (from != null) {
        _openReveal.value = 0.0;
        _expandFlight.value = _ExpandFlight(from: from);
        unawaited(_runExpandFlight(from));
      }
    }
    _pageController = PageController(initialPage: widget.initialIndex);
    _listScrollController = ScrollController();
    _continuousTransformationController = TransformationController();
    _continuousTransformationController.addListener(
      _onContinuousTransformationChanged,
    );
    _continuousZoomAnimationController =
        AnimationController(
          vsync: this,
          duration: MediaViewerConstants.animationDuration,
        )..addListener(() {
          if (_continuousZoomAnimation != null) {
            _isClampingContinuous = true;
            _continuousTransformationController.value =
                _continuousZoomAnimation!.value;
            _isClampingContinuous = false;
          }
        });

    _playlistController.addListener(_onPlaylistUpdate);
    FocusManager.instance.addEarlyKeyEventHandler(_handleViewerKey);
    _playbackManager.activeControllerNotifier.addListener(
      _onActiveVideoControllerChanged,
    );
    _playbackManager.currentFileNotifier.addListener(
      _onCurrentMediaFileChanged,
    );
    if (_scrollMode.isContinuous) {
      _kickOffAspectRatioPreload();
    }
    if (carried != null) _onActiveVideoControllerChanged();

    _loadConfig();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (carried != null && mounted) {
        _sessionController.setPlaybackSpeed(carried.playbackSpeed);
      }
      if (widget.isLibraryPlayback && mounted) {
        // Set this after the first build: changing the viewer-session provider
        // from initState is rejected by Riverpod. Do it before activation so
        // the initial audio track starts with the library's advance behavior.
        _updatePlaybackMode(VideoPlaybackMode.playAndAdvance, persist: false);
      }
      unawaited(_activateCurrentMedia());
      if (carried != null) _handoffToMiniPlayerIfReady();
      _startSlideshowTimerIfNeeded();
      await PlaybackThrottleController.initGate;
      if (mounted) _prefetchSurroundingItems();
    });
  }

  StreamSubscription<MediaSessionAction>? _mediaSessionSubscription;

  /// True while the app is minimized or the screen is off. No frames are
  /// produced then, so anything that waits on an animation or on the end of a
  /// frame would stall until the app returns -- including auto-advancing to
  /// the next item during background playback.
  bool get _isAppInBackground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
  }

  void _onMediaSessionAction(MediaSessionAction action) {
    if (!mounted) return;
    switch (action) {
      case MediaSessionAction.next:
        _navigateToNext();
      case MediaSessionAction.previous:
        _navigateToPrev();
      case MediaSessionAction.stop:
        _closeFromMediaSession();
    }
  }

  bool _closingFromBackPress = false;
  bool _miniPlayerBootstrapDismissScheduled = false;

  /// True once a close has begun. The start-up chain that would otherwise go
  /// on to ask about resuming, seek and play (see [_resolveInitialPlayback])
  /// stands down: with a hand-off the new owner starts the player itself, and
  /// without one nothing should start in a viewer that is going away.
  bool _closing = false;

  bool _enteringPictureInPicture = false;

  int _activateToken = 0;
  Future<void> _loadConfig() async {
    final playbackModeRevision = _playbackModeInteractionRevision;
    final motionPhotoPreferenceRevision = _motionPhotoPreferenceRevision;
    final config = await ref.read(fileManagerToolbarServiceProvider).load();
    final appSettings = await ref
        .read(appSettingsServiceProvider)
        .loadSettings();
    await _marksNotifier.ensureLoaded(widget.container);
    if (mounted) {
      if (motionPhotoPreferenceRevision == _motionPhotoPreferenceRevision &&
          _motionPhotoAutoplay != appSettings.motionPhotoAutoplay) {
        setState(() {
          _motionPhotoAutoplay = appSettings.motionPhotoAutoplay;
        });
      }
      final pinnedPaths = _marks.pinnedPaths;
      unawaited(
        MediaSessionBridge.setShowFileNamesInNotification(
          config.mediaViewerToolbarConfig.showFileNamesInMediaNotification,
        ),
      );
      _sessionController.setEnableCarousel(config.showMediaCarousel);
      if (!config.showMediaCarousel) {
        _sessionController.setCarouselVisible(false);
      }
      _sessionController.setTransitionEffect(config.playlistTransitionEffect);
      _sessionController.setScrollMode(appSettings.playlistScrollMode);
      _sessionController.setVideoAspectRatioMode(
        config.mediaViewerToolbarConfig.defaultAspectRatioMode,
      );
      _sessionController.setIsMuted(appSettings.videoMuted);
      if (playbackModeRevision == _playbackModeInteractionRevision) {
        _updatePlaybackMode(
          widget.isLibraryPlayback
              ? VideoPlaybackMode.playAndAdvance
              : appSettings.videoPlaybackMode,
          persist: false,
        );
      }

      if (appSettings.videoMuted) {
        _playbackManager.activeController?.setVolume(0);
      }
      if (pinnedPaths.isNotEmpty) {
        _playlistController.updatePinnedPaths(Set<String>.from(pinnedPaths));
      }

      if (appSettings.playlistScrollMode.isContinuous) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToCurrentIndex(animate: false);
        });
      }
    }
  }

  void _onContainerDetached(int volId) {
    if (!mounted || volId != widget.container.volId) return;
    _backgroundPlaybackHandoff = null;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _onPlaylistUpdate() {
    if (!mounted) return;
    final currentFile = _playlistController.currentFile;
    final activeMotionPhoto = _motionPhotoActiveFile;
    final activePanorama = _panoramaActiveFile;
    var clearedSpecialMode = false;
    if (activeMotionPhoto != null && activeMotionPhoto != currentFile) {
      _motionPhotoActivationToken++;
      _motionPhotoActiveFile = null;
      clearedSpecialMode = true;
      _playbackManager.pauseActive();
    }
    if (activePanorama != null && activePanorama != currentFile) {
      _panoramaActiveFile = null;
      clearedSpecialMode = true;
    }
    if (clearedSpecialMode) {
      setState(() {});
      _updateSwipePhysics();
    }
    if (currentFile != _zoomLockFile) {
      _zoomLockFile = currentFile;
      // Neighboring items reset their zoom as they become inactive. Clear
      // the previous item's lock so the newly active image can dismiss now.
      _zoomInteractionLock = false;
      _updateSwipePhysics();
    }
    final nowEmpty = _playlistController.isEmpty;
    if (nowEmpty != _wasEmpty) {
      _wasEmpty = nowEmpty;
      setState(() {});
    }
    if (_scrollMode.isContinuous) {
      _kickOffAspectRatioPreload();
    }
  }

  void _scheduleGeometryRebuild() {
    if (!_scrollMode.isContinuous) return;
    if (_hasPendingGeometryRebuild) return;
    _hasPendingGeometryRebuild = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasPendingGeometryRebuild = false;
      if (!mounted) return;
      // Do not shift layout while the user is actively swiping or coasting
      if (_isSwiping) return;
      setState(() {});
    });
  }

  // Freezes measured item heights while the user is actively swiping or coasting
  // so items do not resize mid-gesture and cause screen jitter.
  final Map<int, double> _lockedExtents = {};

  // Pure carousel layout math now lives in CarouselGeometry
  // (carousel_geometry.dart) -- constructed fresh from current playlist/
  // rotation state on each use since it's a cheap, immutable value object;
  // no caching, same as when this was a handful of instance methods
  // reading the same state directly.
  CarouselGeometry get _geometry => CarouselGeometry(
    playlist: _playlistController.playlist,
    rotations: _rotations,
    isAudio: MediaViewerConstants.isAudio,
    aspectRatioFor: (fileName) =>
        MediaAspectRatioCache.get(widget.container, fileName),
  );

  void _scrollToCurrentIndex({bool animate = false}) {
    final index = _playlistController.currentIndex;
    if (_scrollMode.isContinuous) {
      if (_listScrollController.hasClients &&
          _listScrollController.positions.length == 1 &&
          _viewportHeight > 0) {
        // Target offsets assume an un-zoomed list.
        _resetContinuousZoom();
        final target = _geometry.offsetForIndex(
          index,
          _viewportWidth,
          _viewportHeight,
        );
        if (animate) {
          _isProgrammaticScrolling = true;
          _listScrollController
              .animateTo(
                target,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
              )
              .then((_) {
                if (mounted) {
                  _isProgrammaticScrolling = false;
                  unawaited(_activateCurrentMedia());
                  _onScrollEnd();
                }
              });
        } else {
          _isProgrammaticScrolling = true;
          _listScrollController.jumpTo(target);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _isProgrammaticScrolling = false;
              unawaited(_activateCurrentMedia());
              _onScrollEnd();
            }
          });
        }
      }
    } else {
      if (_pageController.hasClients && _pageController.positions.length == 1) {
        if (animate) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        } else {
          _pageController.jumpToPage(index);
        }
      }
    }
  }

  void _onPlaylistChanged() {
    _startHideTimer();
    if (!_playlistController.isPlaylistMode) {
      if (_isCarouselVisible) _toggleCarousel();
      if (_autoAdvance) {
        _updatePlaybackMode(VideoPlaybackMode.playOnce);
      }
    }

    final oldController = _pageController;
    _pageController = PageController(
      initialPage: _playlistController.currentIndex,
    );
    if (oldController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose();
      });
    } else {
      oldController.dispose();
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToCurrentIndex(animate: false);
        _onScrollEnd();
      }
    });
  }

  void _onActiveVideoControllerChanged() {
    // A new controller means a freshly initialised native player, which has
    // no A-B loop registered, so drop the one shown here too.
    _abLoopNotifier.value = AbLoopState.empty;
    if (_lastListenedController != null) {
      try {
        _lastListenedController!.removeListener(_onControllerTickUpdate);
      } catch (_) {
        // removeListener() can throw if the controller was already
        // disposed elsewhere; safe to ignore since this reference is being
        // dropped regardless.
      }
    }

    final controller = _playbackManager.activeController;
    _lastListenedController = controller;

    if (controller == null) {
      _updateWakelock(false);
      _syncPictureInPicture();
      return;
    }

    controller.addListener(_onControllerTickUpdate);
    if (!widget.startInMiniPlayer) {
      _updateWakelock(controller.value.isPlaying);
    }
    _syncPictureInPicture();
    // Each playlist item gets its own native controller, which otherwise
    // starts at the platform's default volume -- reapply the persisted
    // mute state here so toggling mute stays in effect as the person
    // moves through the playlist, not just for the item it was set on.
    controller.setVolume(_effectiveVolume);
  }

  void _onCurrentMediaFileChanged() {
    _videoProgressNotifier.value = const VideoPlaybackProgress();
    _abLoopNotifier.value = AbLoopState.empty;
    _abLoopToastTimer?.cancel();
    _abLoopToast.value = null;
    _resumeFlowToken++;
    _resumeFlowStarted = false;
    _adoptedFile = null;
    _syncPictureInPicture();
  }

  Future<void> _setMotionPhotoMode(String fileName, bool active) async {
    if (!mounted || _playlistController.currentFile != fileName) return;
    if (!active) {
      if (_motionPhotoActiveFile != fileName) return;
      _motionPhotoActivationToken++;
      setState(() => _motionPhotoActiveFile = null);
      _playbackManager.pauseActive();
      await PlaybackThrottleController.setActive(false);
      return;
    }
    if (_motionPhotoActiveFile == fileName) return;

    final activationToken = ++_motionPhotoActivationToken;
    setState(() => _motionPhotoActiveFile = fileName);
    _cancelSlideshowTimer();
    await PlaybackThrottleController.setActive(true);
    if (!mounted ||
        activationToken != _motionPhotoActivationToken ||
        _motionPhotoActiveFile != fileName ||
        _playlistController.currentFile != fileName) {
      return;
    }
    final playbackSettings = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config
        .mediaViewerToolbarConfig;
    await _playbackManager.activate(
      fileName: fileName,
      volId: widget.container.volId,
      filePath: nativePlaybackPathFor(widget.container, fileName),
      isLocalStorage: widget.container.isLocalStorage,
      autoPlay: true,
      playbackSpeed: 1,
      looping: true,
      videoDecoderMode: playbackSettings.videoDecoderMode,
      audioDecoderMode: playbackSettings.audioDecoderMode,
      mediaSession: false,
    );
    if (!mounted ||
        activationToken != _motionPhotoActivationToken ||
        _motionPhotoActiveFile != fileName ||
        _playlistController.currentFile != fileName) {
      if (_playbackManager.currentFileName == fileName) {
        _playbackManager.pauseActive();
      }
    }
  }

  void _setMotionPhotoAutoplay(bool enabled) {
    _motionPhotoPreferenceRevision++;
    if (_motionPhotoAutoplay != enabled) {
      setState(() => _motionPhotoAutoplay = enabled);
    }
    unawaited(_persistMotionPhotoAutoplay(enabled));
  }

  Future<void> _persistMotionPhotoAutoplay(bool enabled) async {
    try {
      await ref
          .read(appSettingsServiceProvider)
          .updateSettings(
            (settings) => settings.copyWith(motionPhotoAutoplay: enabled),
          );
    } catch (error) {
      VeLog.w('MediaViewer', 'Could not save motion photo preference', error);
    }
  }

  void _setPanoramaMode(String fileName, bool active) {
    if (!mounted) return;
    if (active) {
      if (_playlistController.currentFile != fileName ||
          _panoramaActiveFile == fileName) {
        return;
      }
      setState(() => _panoramaActiveFile = fileName);
    } else {
      if (_panoramaActiveFile != fileName) return;
      setState(() => _panoramaActiveFile = null);
    }
    _updateSwipePhysics();
  }

  /// Offers the video on screen to Android's picture-in-picture window (the
  /// viewer's button enters it right away through the coordinator; the
  /// "automatic" setting enters it on leaving the app), or withdraws it for
  /// anything that isn't a video. Idempotent: the coordinator ignores repeats.
  void _syncPictureInPicture() {
    if (!mounted) return;
    final coordinator = PictureInPictureCoordinator.instance;
    final file = _playbackManager.currentFileName;
    final controller = _playbackManager.activeController;
    if (file == null ||
        controller == null ||
        controller.isDisposed ||
        !MediaViewerConstants.isVideo(file)) {
      coordinator.detach(this);
      return;
    }
    final autoEnter = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config
        .mediaViewerToolbarConfig
        .pictureInPictureEnabled;
    coordinator.attach(this, controller, autoEnter: autoEnter);
  }

  void _onControllerTickUpdate() {
    final controller = _playbackManager.activeController;
    if (controller == null) return;
    if (controller.value.hasError) {
      _dismissMiniPlayerBootstrapAfterError();
      return;
    }

    if (!widget.startInMiniPlayer) {
      _updateWakelock(controller.value.isPlaying);
    }

    final isInitialized = controller.value.isInitialized;
    if (!isInitialized) return;

    _handoffToMiniPlayerIfReady();

    final position = controller.value.position;
    final duration = controller.value.duration;

    final fileName = _playbackManager.currentFileName;
    if (fileName != null && fileName == _motionPhotoActiveFile) return;
    if (fileName != null) {
      if (duration > Duration.zero) {
        final lastSaved =
            _lastSavedPlaybackPositions[fileName] ?? Duration.zero;
        if (position.inSeconds - lastSaved.inSeconds >= 5) {
          unawaited(
            _savePlaybackPosition(fileName, position, duration: duration),
          );
        }
      }
      unawaited(
        _resolveInitialPlayback(controller, fileName, _resumeFlowToken),
      );
    }

    if (duration <= Duration.zero) return;

    // While an A-B loop is active the video never ends: the native player
    // jumps back to A instead. So neither whole-video repeat nor
    // auto-advance may act on the position reaching the end.
    if (_abLoopNotifier.value.isActive) return;

    if (_videoPlaybackMode == VideoPlaybackMode.loop) {
      if (controller.value.isPlaying && position >= duration) {
        controller.seekTo(Duration.zero);
        controller.play();
        return;
      }
    }

    if (_isAutoAdvancing) return;

    if (_videoPlaybackMode == VideoPlaybackMode.playAndAdvance &&
        position >= duration) {
      _sessionController.setIsAutoAdvancing(true);
      try {
        controller.removeListener(_onControllerTickUpdate);
      } catch (_) {
        // Same reasoning as elsewhere in this file: removeListener() can
        // throw on an already-disposed controller, and it's safe to
        // ignore since playback is moving on regardless.
      }
      _playbackManager.pauseActive();
      _cancelSlideshowTimer();
      _slideshowTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted && _videoPlaybackMode == VideoPlaybackMode.playAndAdvance) {
          _autoAdvanceToNext();
        } else {
          _sessionController.setIsAutoAdvancing(false);
        }
      });
    }
  }

  String _contentUriFor(String fileName) {
    final volId = widget.container.volId;
    final escapedPath = Uri.encodeComponent(fileName);
    return 'content://com.aeidolon.vaultexplorer.documents/document/'
        '$volId%3Afile%3A$escapedPath';
  }

  /// Debounces rapid swipes, then waits for [PlaybackThrottleController.initGate]
  /// before prefetching neighboring thumbnails -- same ordering as the
  /// initial-open path in [initState]. Skipping the wait lets a
  /// transition's prefetch race the just-activated video's ExoPlayer
  /// init: native video-thumbnail extraction reroutes to a
  /// software-only codec while isPlaybackActive is set (see
  /// extractVideoFrame in ThumbnailHandlers.kt), and that fallback path
  /// occasionally hands back the wrong keyframe -- "success" there
  /// isn't proof it's the *right* frame. See also the before/after
  /// playback-active guard in [VideoThumbnailFetcher.fetch] (used by
  /// _fetchVideoThumbnailForPrefetch), which stops such a frame from
  /// being persisted even if one slips through this wait.
  void _scheduleSurroundingPrefetch() {
    _prefetchDebounceTimer?.cancel();
    _prefetchDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      unawaited(() async {
        await PlaybackThrottleController.initGate;
        if (mounted) _prefetchSurroundingItems();
      }());
    });
  }

  void _prefetchSurroundingItems() {
    // Cache/service orchestration now lives in MediaPrefetchController
    // (media_prefetch_controller.dart) -- isStillWanted re-checks current
    // playlist/index state at call time rather than capturing it here,
    // same as before this extraction.
    _prefetchController.prefetchSurrounding(
      _playlistController.currentIndex,
      _playlistController.playlist,
      isStillWanted: (fileName) {
        if (!mounted) return false;
        final cur = _playlistController.currentIndex;
        final playlist = _playlistController.playlist;
        for (int delta = -2; delta <= 2; delta++) {
          final i = cur + delta;
          if (i >= 0 && i < playlist.length && playlist[i] == fileName) {
            return true;
          }
        }
        return false;
      },
    );
  }

  Future<void> _transitionTo(
    int index, {
    bool animate = true,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (index < 0 || index >= _playlistController.playlist.length) return;
    // Backgrounded (background playback auto-advancing, or Next pressed on
    // the lock screen): no frames are produced, so an animation -- or waiting
    // for the end of a frame -- would never complete and the transition would
    // hang until the app returned. Jump instead; the item is activated (and
    // starts playing) regardless of the page animation.
    final inBackground = _isAppInBackground;
    if (inBackground) animate = false;
    final token = ++_transitionToken;
    _cancelSlideshowTimer();
    _startHideTimer();
    _isProgrammaticScrolling = true;
    _updateSwipePhysics();

    _playlistController.updateIndex(index);
    try {
      widget.onCurrentFileChanged?.call(_playlistController.currentFile);
    } catch (_) {
      // Best-effort callback into the parent widget, same as in
      // _activateCurrentMedia() above -- shouldn't break playlist
      // navigation.
    }
    unawaited(_activateCurrentMedia());

    _scheduleSurroundingPrefetch();
    if (_scrollMode.isContinuous) {
      _kickOffAspectRatioPreload(index);
    }

    if (_scrollMode.isContinuous) {
      if (_listScrollController.hasClients &&
          _listScrollController.positions.length == 1 &&
          _viewportHeight > 0) {
        // Target offsets assume an un-zoomed list.
        _resetContinuousZoom();
        final target = _geometry.offsetForIndex(
          index,
          _viewportWidth,
          _viewportHeight,
        );
        if (animate) {
          await _listScrollController.animateTo(
            target,
            duration: duration,
            curve: curve,
          );
        } else {
          _listScrollController.jumpTo(target);
          if (!inBackground) await WidgetsBinding.instance.endOfFrame;
        }
      }
    } else {
      if (_pageController.hasClients && _pageController.positions.length == 1) {
        if (animate) {
          await _pageController.animateToPage(
            index,
            duration: duration,
            curve: curve,
          );
        } else {
          _pageController.jumpToPage(index);
        }
      }
    }

    if (!mounted || _transitionToken != token) return;

    _isProgrammaticScrolling = false;
    _updateSwipePhysics();
    _isSwiping = false;
    _sessionController.setIsAutoAdvancing(false);
    final currentFile = _playlistController.currentFile;
    if (MediaViewerConstants.isImage(currentFile)) {
      _startSlideshowTimerIfNeeded();
    }
    if (_showUI) {
      _startHideTimer();
    }
    setState(() {});
  }

  void _autoAdvanceToNext() {
    final index = _playlistController.currentIndex;
    final count = _playlistController.playlist.length;
    if (count > 1 && (index < count - 1 || _isPlaylistLoopEnabled)) {
      _transitionTo(
        (index + 1) % count,
        animate: true,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _sessionController.setIsAutoAdvancing(false);
    }
  }

  void _navigateToNext({bool animate = true}) {
    final index = _playlistController.currentIndex;
    final count = _playlistController.playlist.length;
    if (count > 1 && (index < count - 1 || _isPlaylistLoopEnabled)) {
      HapticFeedback.lightImpact();
      _transitionTo((index + 1) % count, animate: animate);
    }
  }

  void _navigateToPrev({bool animate = true}) {
    final index = _playlistController.currentIndex;
    final count = _playlistController.playlist.length;
    if (count > 1 && (index > 0 || _isPlaylistLoopEnabled)) {
      HapticFeedback.lightImpact();
      _transitionTo((index - 1 + count) % count, animate: animate);
    }
  }

  bool get _isPlaylistLoopEnabled => ref
      .read(fileManagerToolbarSettingsProvider(null))
      .config
      .mediaViewerToolbarConfig
      .loopPlaylist;

  void _startSlideshowTimerIfNeeded() {
    _cancelSlideshowTimer();
    if (!_autoAdvance || _playlistController.isEmpty) return;
    final currentFile = _playlistController.currentFile;
    if (MediaViewerConstants.isImage(currentFile)) {
      _slideshowTimer = Timer(Duration(seconds: _slideshowDelaySeconds), () {
        if (mounted) _autoAdvanceToNext();
      });
    }
  }

  bool get _isCurrentItemSwipeToSeekEnabled {
    if (_playlistController.isEmpty) return false;
    final currentFile = _playlistController.currentFile;
    if (!MediaViewerConstants.isVideo(currentFile)) return false;
    final gestureConfig = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config
        .mediaViewerToolbarConfig;
    if (!_playlistController.isPlaylistMode) {
      return true;
    }
    return gestureConfig.swipeToSeekEnabled;
  }

  /// The drag that closes the viewer is always the one opposite to the drag
  /// that changes items, so the two never compete: swipe down when items
  /// change sideways, swipe sideways when they change vertically. A single
  /// item has no playlist to change, so it uses the default (down).
  Axis get _swipeDismissAxis {
    if (!_playlistController.isPlaylistMode) return Axis.vertical;
    return _scrollMode.axis == Axis.horizontal
        ? Axis.vertical
        : Axis.horizontal;
  }

  // ---- Continuous-mode zoom ------------------------------------------------
  //
  // The continuous list is zoomed by an InteractiveViewer wrapped around the
  // ListView: "zoomed" means the list is drawn through a transform, it is not
  // re-laid out. The list keeps scrolling normally underneath that transform.

  /// Puts the continuous list back at 1x.
  ///
  /// With [keepCenter] the list is also scrolled so that whatever was in the
  /// middle of the screen stays there, instead of the view snapping to a
  /// different item. Pass `false` when the caller is about to reposition the
  /// list itself anyway (e.g. after the viewport was resized).
  bool _isClampingContinuous = false;

  void _onContinuousTransformationChanged() {
    if (_isClampingContinuous || !mounted) return;
    final vw = _viewportWidth;
    final vh = _viewportHeight;
    if (vw <= 0 || vh <= 0) return;

    final matrix = _continuousTransformationController.value;
    final s = _getMatrixScale(matrix);
    if (s <= 0) return;

    final config = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config
        .mediaViewerToolbarConfig;
    final effectiveMinScale = config.pinchZoomOutEnabled
        ? config.minVideoZoomScale.clamp(
            MediaViewerConstants.minVideoZoomFloor,
            1.0,
          )
        : 1.0;

    // Hard floor for zoom-out
    if (s < effectiveMinScale) {
      final clampedS = effectiveMinScale;
      final dx = vw * (1.0 - clampedS) / 2.0;
      final dy = vh * (1.0 - clampedS) / 2.0;
      _isClampingContinuous = true;
      _continuousTransformationController.value = Matrix4.identity()
        ..setTranslationRaw(dx, dy, 0.0)
        ..scale(clampedS, clampedS, clampedS);
      _isClampingContinuous = false;
      return;
    }

    // Lock borders when zoomed in (s >= 1.0) across both X and Y
    if (s >= 1.0) {
      final scaledW = vw * s;
      final scaledH = vh * s;
      final currentTx = matrix.storage[12];
      final currentTy = matrix.storage[13];

      final double clampedTx = scaledW > vw
          ? currentTx.clamp(vw - scaledW, 0.0)
          : (vw - scaledW) / 2.0;
      final double clampedTy = scaledH > vh
          ? currentTy.clamp(vh - scaledH, 0.0)
          : (vh - scaledH) / 2.0;

      if ((currentTx - clampedTx).abs() > 0.001 ||
          (currentTy - clampedTy).abs() > 0.001) {
        _isClampingContinuous = true;
        _continuousTransformationController.value = Matrix4.identity()
          ..setTranslationRaw(clampedTx, clampedTy, 0.0)
          ..scale(s, s, s);
        _isClampingContinuous = false;
      }
    }
  }

  void _animateContinuousZoomTo(
    Matrix4 targetMatrix, {
    required bool toBaseline,
  }) {
    final controller = _continuousZoomAnimationController;
    if (controller == null) {
      _continuousTransformationController.value = targetMatrix;
      return;
    }

    controller.stop();
    _continuousZoomAnimation = Matrix4Tween(
      begin: _continuousTransformationController.value,
      end: targetMatrix,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));

    controller.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _continuousScale = _getMatrixScale(
            _continuousTransformationController.value,
          );
        });
        _onZoomInteractionChanged(toBaseline);
      }
    });
  }

  void _resetContinuousZoom({bool keepCenter = true, bool animate = false}) {
    if (animate) {
      _animateContinuousZoomTo(Matrix4.identity(), toBaseline: true);
      return;
    }

    final controller = _continuousTransformationController;
    if (controller.value.isIdentity()) {
      _continuousScale = 1.0;
      return;
    }
    final shift = keepCenter ? _continuousVisibleCenterShift() : 0.0;
    _isClampingContinuous = true;
    controller.value = Matrix4.identity();
    _isClampingContinuous = false;
    if (shift.abs() > 0.5 &&
        _listScrollController.hasClients &&
        _listScrollController.positions.length == 1) {
      final position = _listScrollController.position;
      position.jumpTo(
        (position.pixels + shift)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    }
    _onZoomInteractionChanged(true);
    if (mounted) setState(() => _continuousScale = 1.0);
  }

  static double _getMatrixScale(Matrix4 matrix) {
    final double x = matrix.storage[0];
    final double y = matrix.storage[1];
    return math.sqrt(x * x + y * y);
  }

  void _onScrollEnd() {
    _isSwiping = false;
    _lockedExtents.clear();
    final currentFile = _playlistController.currentFile;
    if (_playbackManager.currentFileNotifier.value != currentFile) {
      unawaited(_activateCurrentMedia());
    } else if (_autoPlay || currentFile == _motionPhotoActiveFile) {
      _playbackManager.activeController?.play();
    }
    if (MediaViewerConstants.isImage(currentFile) &&
        currentFile != _motionPhotoActiveFile) {
      _startSlideshowTimerIfNeeded();
    }
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    if (_showUI) {
      _startHideTimer();
    }
  }

  Future<void> _deleteCurrentFile() async {
    _menuOpened();
    final cs = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteFileDialogTitle),
        content: Text(context.l10n.deleteFilePermanentWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    _menuClosed();

    if (confirm != true) return;

    final fileToDelete = _playlistController.currentFile;
    bool success = false;
    try {
      success = await _fileIoApi.deleteFile(widget.container, fileToDelete);
    } catch (e) {
      VeLog.e(
        'MediaViewerScreen',
        'Delete failed for ${VeLog.censorName(fileToDelete)}',
        e,
      );
    }

    if (success) widget.onFileDeleted?.call(fileToDelete);

    if (success && mounted) {
      _sessionController.forgetFile(fileToDelete);
      _playlistController.removeFile(fileToDelete);
      if (_playlistController.isEmpty) {
        Navigator.pop(context);
        return;
      }
      if (_pageController.hasClients) {
        final oldController = _pageController;
        _pageController = PageController(
          initialPage: _playlistController.currentIndex,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldController.dispose();
        });
      }
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToCurrentIndex(animate: false);
          _prefetchSurroundingItems();
          _onScrollEnd();
        }
      });
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.mediaFileDeletedMessage,
          tone: AppBannerTone.success,
        );
      }
    } else if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.mediaFileDeleteFailedMessage,
        tone: AppBannerTone.error,
      );
    }
  }

  bool get _isCurrentFileBookmark =>
      _marks.isBookmarked(_playlistController.currentFile);

  void _cancelSlideshowTimer() {
    _slideshowTimer?.cancel();
    _slideshowTimer = null;
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_chromeAutoHides) return;
    if (_activeMenuCount > 0) return;
    _hideTimer = Timer(MediaViewerConstants.uiHideDelay, () {
      final controller = _playbackManager.activeController;
      if (mounted &&
          controller != null &&
          controller.value.isPlaying &&
          _showUI &&
          _activeMenuCount == 0) {
        _setUIVisibility(false);
      }
    });
  }

  /// Turns the touch lock on or off. Locking tucks the chrome away; unlocking
  /// brings it back.
  void _setControlsLocked(bool locked) {
    if (!mounted || _controlsLocked == locked) return;
    setState(() => _controlsLocked = locked);
    _hideTimer?.cancel();
    _setUIVisibility(!locked);
  }

  void _setUIVisibility(bool show) {
    // Nothing may bring the chrome back while locked; unlocking does.
    if (show && _controlsLocked) return;
    // A desktop window in its normal state keeps its controls up.
    if (!show && !_chromeAutoHides) return;
    if (mounted) {
      _sessionController.setShowUI(show);
      if (show) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        _startHideTimer();
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _hideTimer?.cancel();
      }
    }
  }

  /// Real fullscreen for the desktop window: no frame, the whole monitor, the
  /// caption row and (after the usual delay) the controls gone. Where the
  /// runner cannot (Linux) only the viewer's own chrome follows.
  Future<void> _setDesktopFullscreen(bool on) async {
    if (!PlatformFeatures.isDesktop || !mounted || _desktopFullscreen == on) {
      return;
    }
    if (_fullscreenSwitching) return;
    _fullscreenSwitching = true;
    try {
      _fullscreenWindowArgs = windowChannelArgsFor(context);
      // Change the window first and the viewer's layout only once the window
      // has its new size, so the media is laid out once, for the final size.
      // Switching the layout first would stretch the media to a window that
      // has not grown yet and then again when it has.
      final resized = _nextViewMetrics();
      final changed = await setWindowFullscreen(_fullscreenWindowArgs, on);
      _nativeFullscreen = changed && on;
      if (changed) await resized;
      if (!mounted) return;
      setState(() => _desktopFullscreen = on);
      if (on) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
        _setUIVisibility(true);
      }
    } finally {
      _fullscreenSwitching = false;
    }
  }

  bool _fullscreenSwitching = false;

  /// The window itself (not just the viewer's layout) is in fullscreen.
  bool _nativeFullscreen = false;

  /// Completes when the window's size next changes (or after a short while if
  /// it never does, e.g. it was already that size).
  Future<void> _nextViewMetrics() {
    final done = Completer<void>();
    final observer = _MetricsOnce(() {
      if (!done.isCompleted) done.complete();
    });
    WidgetsBinding.instance.addObserver(observer);
    return done.future
        .timeout(const Duration(milliseconds: 400), onTimeout: () {})
        .whenComplete(() => WidgetsBinding.instance.removeObserver(observer));
  }

  void _toggleDesktopFullscreen() =>
      unawaited(_setDesktopFullscreen(!_desktopFullscreen));

  void _menuOpened() {
    _activeMenuCount++;
    _hideTimer?.cancel();
  }

  void _menuClosed() {
    _activeMenuCount = (_activeMenuCount - 1).clamp(0, 999);
    _startHideTimer();
  }

  IconData _screenOrientationIcon() => switch (_screenOrientationModeIndex) {
    0 => Icons.stay_current_portrait_rounded,
    1 => Icons.stay_current_landscape_rounded,
    _ => Icons.screen_rotation_rounded,
  };

  void _cycleScreenOrientation() {
    final nextMode = (_screenOrientationModeIndex + 1) % 3;
    setState(() => _screenOrientationModeIndex = nextMode);

    switch (nextMode) {
      case 0:
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      case 1:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      case 2:
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  static String _decoderModeLabel(
    AppLocalizations l10n,
    MediaDecoderMode mode,
  ) {
    return switch (mode) {
      MediaDecoderMode.auto => l10n.decoderAutoOption,
      MediaDecoderMode.hardware => l10n.decoderHardwareOption,
      MediaDecoderMode.software => l10n.decoderSoftwareOption,
      MediaDecoderMode.ffmpeg => l10n.decoderFfmpegOption,
    };
  }

  void _toggleCarousel() {
    HapticFeedback.lightImpact();
    final next = !_isCarouselVisible;
    _sessionController.setCarouselVisible(next);
    if (next) {
      _menuOpened();
    } else {
      _menuClosed();
    }
  }

  void _selectFromCarousel(int index) {
    HapticFeedback.selectionClick();
    _transitionTo(index, animate: false);
  }

  void _updatePlaybackMode(VideoPlaybackMode mode, {bool persist = true}) {
    if (persist) {
      _playbackModeInteractionRevision++;
      _startHideTimer();
      _persistVideoPlaybackMode(mode);
    }
    _sessionController.setVideoPlaybackMode(mode);
    final autoAdvance = (mode == VideoPlaybackMode.playAndAdvance);
    _sessionController.setAutoAdvance(autoAdvance);
    if (autoAdvance) {
      _startSlideshowTimerIfNeeded();
    } else {
      _cancelSlideshowTimer();
    }
    final controller = _playbackManager.activeController;
    controller?.setLooping(mode == VideoPlaybackMode.loop);
  }

  void _persistVideoPlaybackMode(VideoPlaybackMode mode) {
    final settingsService = ref.read(appSettingsServiceProvider);
    _playbackModeSaveQueue = _playbackModeSaveQueue
        .catchError((Object error) {
          VeLog.w(
            'MediaViewer',
            'Could not persist video playback mode',
            error,
          );
        })
        .then((_) async {
          final settings = await settingsService.loadSettings();
          await settingsService.saveSettings(
            settings.copyWith(videoPlaybackMode: mode),
          );
        });
  }

  void _openCustomizeControls() {
    _menuOpened();
    _cancelSlideshowTimer();
    _playbackManager.pauseActive();
    setState(() {
      _isEditingLayout = true;
    });
    _updateSwipePhysics();
  }

 final Set<LogicalKeyboardKey> _handledViewerKeysDown = {};

  KeyEventResult _handleViewerKey(KeyEvent event) {
    if (!mounted) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      return _handledViewerKeysDown.remove(key)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return KeyEventResult.ignored;
    }
    if (!keyboardFocusIsInViewOf(context)) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<EditableText>() != null ||
        focused?.widget is EditableText) {
      return KeyEventResult.ignored;
    }
    final kb = HardwareKeyboard.instance;
    final isRepeat = event is KeyRepeatEvent;
    final primary = kb.isControlPressed || kb.isMetaPressed;

    KeyEventResult markHandled() {
      if (event is KeyDownEvent) {
        _handledViewerKeysDown.add(key);
      }
      return KeyEventResult.handled;
    }

    // Ctrl/Cmd+C copies the image (desktop clipboard).
    if (primary &&
        !kb.isShiftPressed &&
        !kb.isAltPressed &&
        key == LogicalKeyboardKey.keyC) {
      if (!PlatformFeatures.isDesktop ||
          !MediaViewerConstants.isImage(_playlistController.currentFile)) {
        return KeyEventResult.ignored;
      }
      if (isRepeat) return markHandled();
      unawaited(_copyCurrentImageToClipboard());
      return markHandled();
    }

    // Everything below is a plain key (Shift only matters for < and >).
    if (primary || kb.isAltPressed) return KeyEventResult.ignored;
    // A menu or sheet is open, or the touch lock is on: leave the keys alone.
    if (OpenMenuBackGuard.hasOpenMenu || _activeMenuCount > 0) {
      return KeyEventResult.ignored;
    }
    if (_controlsLocked) return KeyEventResult.ignored;
    if (_playlistController.isEmpty) return KeyEventResult.ignored;

    final isImage = MediaViewerConstants.isImage(_playlistController.currentFile);
    final shift = kb.isShiftPressed;

    // Keys that may auto-repeat while held (seek, volume, speed).
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final forward = key == LogicalKeyboardKey.arrowRight;
      if (isImage) {
        if (isRepeat) return markHandled();
        _startHideTimer();
        forward ? _navigateToNext() : _navigateToPrev();
      } else {
        _seekBy(Duration(seconds: shift ? 30 : 5) * (forward ? 1 : -1));
      }
      return markHandled();
    }
    if (!isImage &&
        (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.keyL)) {
      _seekBy(Duration(seconds: 10) * (key == LogicalKeyboardKey.keyL ? 1 : -1));
      return markHandled();
    }
    if (!isImage &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      _changeVolume(key == LogicalKeyboardKey.arrowUp ? 5 : -5);
      return markHandled();
    }
    if (!isImage &&
        (key == LogicalKeyboardKey.less ||
            key == LogicalKeyboardKey.greater ||
            (shift &&
                (key == LogicalKeyboardKey.comma ||
                    key == LogicalKeyboardKey.period)))) {
      if (isRepeat) return markHandled();
      final faster =
          key == LogicalKeyboardKey.greater || key == LogicalKeyboardKey.period;
      _stepPlaybackSpeed(faster ? 1 : -1);
      return markHandled();
    }

    if (shift) return KeyEventResult.ignored;

    // 0-9 jump to that tenth of the video (top row or numpad).
    if (!isImage) {
      final digit = _digitFor(key);
      if (digit != null) {
        if (!isRepeat) _seekToFraction(digit / 10);
        return markHandled();
      }
      if (key == LogicalKeyboardKey.home) {
        if (!isRepeat) _seekToFraction(0);
        return markHandled();
      }
      if (key == LogicalKeyboardKey.end) {
        if (!isRepeat) _seekToFraction(1);
        return markHandled();
      }
    }

    MediaViewerAction? action;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      action = MediaViewerAction.playPause;
    } else if (key == LogicalKeyboardKey.keyN ||
        key == LogicalKeyboardKey.pageDown) {
      action = MediaViewerAction.next;
    } else if (key == LogicalKeyboardKey.keyP ||
        key == LogicalKeyboardKey.pageUp) {
      action = MediaViewerAction.previous;
    } else if (key == LogicalKeyboardKey.keyM && !isImage) {
      action = MediaViewerAction.mute;
    } else if (key == LogicalKeyboardKey.keyR) {
      action = MediaViewerAction.rotate90;
    } else if (key == LogicalKeyboardKey.keyI) {
      action = MediaViewerAction.fileInfo;
    } else if (key == LogicalKeyboardKey.keyB) {
      action = MediaViewerAction.bookmark;
    } else if (key == LogicalKeyboardKey.keyT) {
      action = MediaViewerAction.thumbnailCarousel;
    } else if (key == LogicalKeyboardKey.keyA && !isImage) {
      action = MediaViewerAction.abLoop;
    } else if (key == LogicalKeyboardKey.keyO) {
      action = MediaViewerAction.openWithApp;
    } else if (key == LogicalKeyboardKey.f2) {
      action = MediaViewerAction.rename;
    } else if (key == LogicalKeyboardKey.delete) {
      action = MediaViewerAction.delete;
    }
    if (action != null) {
      if (!isRepeat) _executeMediaAction(action);
      return markHandled();
    }

    if (key == LogicalKeyboardKey.keyC && !isImage) {
      if (!isRepeat) {
        _startHideTimer();
        _sessionController.setSubtitlesEnabled(!_subtitlesEnabled);
        _showKeyToast(
          _subtitlesEnabled ? 'CC' : 'CC · ${context.l10n.offLabel}',
        );
      }
      return markHandled();
    }
    if (key == LogicalKeyboardKey.keyH) {
      if (!isRepeat) _setUIVisibility(!_showUI);
      return markHandled();
    }
    if (PlatformFeatures.isDesktop &&
        !primary &&
        (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.f11)) {
      if (!isRepeat) _toggleDesktopFullscreen();
      return markHandled();
    }
    if (key == LogicalKeyboardKey.escape) {
      if (!isRepeat) unawaited(Navigator.of(context).maybePop());
      return markHandled();
    }
    return KeyEventResult.ignored;
  }

  static int? _digitFor(LogicalKeyboardKey key) {
    final digits = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.digit0: 0,
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.digit9: 9,
      LogicalKeyboardKey.numpad0: 0,
      LogicalKeyboardKey.numpad1: 1,
      LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.numpad3: 3,
      LogicalKeyboardKey.numpad4: 4,
      LogicalKeyboardKey.numpad5: 5,
      LogicalKeyboardKey.numpad6: 6,
      LogicalKeyboardKey.numpad7: 7,
      LogicalKeyboardKey.numpad8: 8,
      LogicalKeyboardKey.numpad9: 9,
    };
    return digits[key];
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleViewerKey);
    _handledViewerKeysDown.clear();
    unawaited(_saveActivePlaybackPosition());
    unawaited(_mediaSessionSubscription!.cancel());
    _engineEvents.removeUsbContainerDetachedListener(_onContainerDetached);
    _playlistController.removeListener(_onPlaylistUpdate);
    if (_lastListenedController != null) {
      try {
        _lastListenedController!.removeListener(_onControllerTickUpdate);
      } catch (_) {
        // Same as _onActiveVideoControllerChanged() above: safe to ignore,
        // this controller is being torn down regardless.
      }
    }
    _playbackManager.activeControllerNotifier.removeListener(
      _onActiveVideoControllerChanged,
    );
    _playbackManager.currentFileNotifier.removeListener(
      _onCurrentMediaFileChanged,
    );
    _updateWakelock(false);
    _prefetchDebounceTimer?.cancel();
    _cancelSlideshowTimer();
    _hideTimer?.cancel();
    _pageController.dispose();
    _listScrollController.dispose();
    _continuousZoomAnimationController?.dispose();
    _floatingCloseGuard?.cancel();
    _closeFade?.dispose();
    _expandController?.dispose();
    // The floating window must not outlive a viewer that never got to end it.
    BackgroundPlaybackHost.instance.endFloatingExit();
    _continuousTransformationController.removeListener(
      _onContinuousTransformationChanged,
    );
    _continuousTransformationController.dispose();
    PictureInPictureCoordinator.instance.detach(this);
    // Closed with audio playing and "keep audio playing after closing" on:
    // background playback takes the live player; otherwise it is released as
    // always.
    final handoff = _backgroundPlaybackHandoff;
    _backgroundPlaybackHandoff = null;
    final handedOff =
        handoff != null && BackgroundPlaybackHost.instance.adopt(handoff);
    // The window that flew out of this viewer is now the session's (or, if
    // nothing was adopted, it has nothing left to show).
    BackgroundPlaybackHost.instance.endFloatingEntry();
    if (!handedOff) {
      PlaybackThrottleController.setActive(false);
      _playbackManager.dispose();
    }
    BackgroundPlaybackHost.instance.unregisterViewer();
    _swipePhysicsNotifier.dispose();
    _swipeDismissProgress.dispose();
    _floatingClose.dispose();
    _openReveal.dispose();
    _expandFlight.dispose();
    _lockNudge.dispose();
    _videoProgressNotifier.dispose();
    _abLoopNotifier.dispose();
    _abLoopToastTimer?.cancel();
    _abLoopToast.dispose();
    _scrubPreviewHost.dispose();
    if (_nativeFullscreen || _desktopFullscreen) {
      // The window is the person's file manager again: give it its frame back.
      unawaited(setWindowFullscreen(_fullscreenWindowArgs, false));
    }
    if (!widget.startInMiniPlayer) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    // Best-effort: don't let a brightness edge-swipe made in this viewer
    // leak into the rest of the app once the person leaves it. Fire-and-
    // forget since the screen is already tearing down.
    unawaited(ScreenBrightnessBridge.clearOverride());
    super.dispose();
  }

  Widget _buildMediaItem(int index) {
    final fileName = _playlistController.playlist[index];
    final contentUriString = _contentUriFor(fileName);
    final prefetchedBytes = _prefetchedBytesFor(fileName);
    if (!widget._isPreviewOnly && prefetchedBytes == null) {
      unawaited(_prefetchController.prefetchThumbnail(fileName));
    }
    final isImg = MediaViewerConstants.isImage(fileName);
    final isAudio = MediaViewerConstants.isAudio(fileName);
    // Keep the zoom pill above the bottom controls while they are visible.
    // The controls reserve the device safe-area inset at the bottom.
    final zoomIndicatorBottomOffset = !_showUI
        ? 16.0
        : MediaQuery.paddingOf(context).bottom +
              (isImg
                  ? MediaViewerConstants.zoomIndicatorImageControlsClearance
                  : MediaViewerConstants.zoomIndicatorVideoControlsClearance) +
              (_enableCarousel && _isCarouselVisible
                  ? PlaylistCarouselOverlay.height
                  : 0.0);
    final gestureConfig = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config
        .mediaViewerToolbarConfig;
    void onItemZoomChanged(bool allowSwipe) {
      // PageView keeps neighboring items alive. Their zoom callbacks must not
      // change whether the item currently on screen can be dismissed.
      if (fileName != _playlistController.currentFile) return;
      _onZoomInteractionChanged(allowSwipe);
    }

    final itemWidget = ValueListenableBuilder<double>(
      valueListenable: _swipeDismissProgress,
      child: Container(
        color: Colors.transparent,
        child: isImg
            ? ImagePageItem(
                key: ValueKey(
                  'image_${fileName}_${_imageReloadEpoch[fileName] ?? 0}',
                ),
                fileName: fileName,
                prefetchedBytes: prefetchedBytes,
                container: widget.container,
                imageFit: _scrollMode.isContinuous ? BoxFit.contain : _imageFit,
                rotationQuarterTurns: _rotations[fileName] ?? 0,
                adjustments: _adjustmentsFor(fileName),
                showUI: _showUI,
                dismissProgress: _swipeDismissProgress,
                zoomIndicatorBottomOffset: zoomIndicatorBottomOffset,
                tapEdgesToNavigate: gestureConfig.tapEdgesToNavigate,
                enableZoom: !_scrollMode.isContinuous,
                pinchZoomOutEnabled: gestureConfig.pinchZoomOutEnabled,
                minZoomScale: gestureConfig.minVideoZoomScale,
                onToggleUI: _setUIVisibility,
                onZoomChanged: onItemZoomChanged,
                thumbnailQuality: widget.thumbnailQuality,
                thumbnailCacheMode: widget.thumbnailCacheMode,
                edgeSwipeBrightnessEnabled:
                    gestureConfig.edgeSwipeBrightnessEnabled,
                edgeSwipeHudEnabled: gestureConfig.edgeSwipeHudEnabled,
                edgeSwipeWidthFraction: gestureConfig.edgeSwipeWidthFraction,
                isActive: _playlistController.currentFile == fileName,
                onSizeKnown: (w, h) {
                  if (_scrollMode.isContinuous) {
                    _scheduleGeometryRebuild();
                  }
                },
                onError: () => _handleMediaError(fileName),
              )
            : MediaPlayerWidget(
                key: ValueKey('player_$fileName'),
                container: widget.container,
                fileName: fileName,
                contentUriString: contentUriString,
                playbackManager: _playbackManager,
                posterBytes: prefetchedBytes,
                thumbnailQuality: widget.thumbnailQuality,
                thumbnailCacheMode: widget.thumbnailCacheMode,
                thumbnailGenerationStrategy:
                    gestureConfig.thumbnailGenerationStrategy,
                showUI: _showUI,
                dismissProgress: _swipeDismissProgress,
                tapEdgesToNavigate: gestureConfig.tapEdgesToNavigate,
                doubleTapPlayPause: gestureConfig.doubleTapPlayPause,
                zoomIndicatorBottomOffset: zoomIndicatorBottomOffset,
                enableZoom: !_scrollMode.isContinuous,
                onToggleUI: _setUIVisibility,
                // 0 turns double-tap skipping off.
                skipSeconds: gestureConfig.doubleTapSkipEnabled
                    ? gestureConfig.doubleTapSkipSeconds
                    : 0,
                isAudio: isAudio,
                subtitlesEnabled: _subtitlesEnabled,
                subtitleFontSize: _subtitleFontSize,
                subtitleVerticalPosition: _subtitleVerticalPosition,
                onSubtitleVerticalPositionChanged: (pos) {
                  _sessionController.setSubtitleVerticalPosition(pos);
                },
                playbackSpeed: _playbackSpeed,
                rotationQuarterTurns: _rotations[fileName] ?? 0,
                adjustments: _adjustmentsFor(fileName),
                videoAspectRatioMode: _videoAspectRatioMode,
                // Only the video that is showing says where it is: the PiP
                // transition animates from that rectangle.
                onVideoRectChanged:
                    !isAudio && fileName == _playlistController.currentFile
                    ? (rect, devicePixelRatio) =>
                          PictureInPictureCoordinator.instance.setSourceRect(
                            this,
                            rect,
                            devicePixelRatio: devicePixelRatio,
                          )
                    : null,
                videoFrameProbe:
                    !isAudio && fileName == _playlistController.currentFile
                    ? _videoProbe
                    : null,
                isMuted: _isMuted,
                onMuteChanged: (muted) {
                  if (_isMuted != muted) {
                    _sessionController.setIsMuted(muted);
                    _playbackManager.activeController?.setVolume(
                      muted ? 0 : _volumeLevel,
                    );
                    ref.read(appSettingsServiceProvider).loadSettings().then((
                      appSettings,
                    ) {
                      ref
                          .read(appSettingsServiceProvider)
                          .saveSettings(
                            appSettings.copyWith(videoMuted: muted),
                          );
                    });
                  }
                },
                edgeSwipeBrightnessEnabled:
                    gestureConfig.edgeSwipeBrightnessEnabled,
                edgeSwipeVolumeEnabled: gestureConfig.edgeSwipeVolumeEnabled,
                edgeSwipeHudEnabled: gestureConfig.edgeSwipeHudEnabled,
                edgeSwipeWidthFraction: gestureConfig.edgeSwipeWidthFraction,
                pinchZoomOutEnabled: gestureConfig.pinchZoomOutEnabled,
                minVideoZoomScale: gestureConfig.minVideoZoomScale,
                holdToSpeedMultiplier: gestureConfig.holdToSpeedMultiplier,
                swipeToSeekEnabled:
                    !_playlistController.isPlaylistMode ||
                    gestureConfig.swipeToSeekEnabled,
                seekSensitivity: gestureConfig.seekSensitivity,
                volumeGestureSensitivity:
                    gestureConfig.volumeGestureSensitivity,
                brightnessGestureSensitivity:
                    gestureConfig.brightnessGestureSensitivity,
                volumeBoostEnabled: gestureConfig.volumeBoostEnabled,
                volumeBoostGainMb: gestureConfig.volumeBoostGainMb,
                videoDecoderMode: gestureConfig.videoDecoderMode,
                audioDecoderMode: gestureConfig.audioDecoderMode,
                progressNotifier: _videoProgressNotifier,
                onSubtitlesAvailableChanged: (val) {
                  _playbackManager.updateSubtitleStatus(fileName, val);
                  if (fileName == _playlistController.currentFile) {
                    setState(() {});
                  }
                },
                onSizeKnown: (w, h) {
                  if (_scrollMode.isContinuous) {
                    _scheduleGeometryRebuild();
                  }
                },
                onZoomChanged: onItemZoomChanged,
                onError: () => _handleMediaError(fileName),
              ),
      ),
      builder: (context, progress, media) {
        final backgroundAlpha = (1.0 - progress).clamp(0.0, 1.0).toDouble();
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<double>(
                valueListenable: _openReveal,
                builder: (context, reveal, _) => ColoredBox(
                  color: Colors.black.withValues(
                    alpha: backgroundAlpha * reveal,
                  ),
                ),
              ),
            ),
            // While the floating window flies out of the video, this copy of
            // it must not be drawn as well: it would hang about where the
            // video was, fading, as the window leaves. And when the viewer was
            // opened from the floating window, the item on screen grows out of
            // it (see _runExpandFlight).
            ValueListenableBuilder<_FloatingClose>(
              valueListenable: _floatingClose,
              child: fileName == _playlistController.currentFile
                  ? _expandFlightLayer(media!)
                  : media,
              builder: (context, closing, child) => Opacity(
                opacity: closing == _FloatingClose.flying ? 0.0 : 1.0,
                child: child,
              ),
            ),
            if (isImg)
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _playlistController,
                  builder: (context, _) {
                    if (_playlistController.currentFile != fileName) {
                      return const SizedBox.shrink();
                    }
                    return ImageSpecialModesLayer(
                      key: ValueKey('image_special_modes_$fileName'),
                      container: widget.container,
                      fileName: fileName,
                      showUI: _showUI,
                      motionPhotoActive: _motionPhotoActiveFile == fileName,
                      motionPhotoAutoplay: _motionPhotoAutoplay,
                      onMotionPhotoChanged: (active) =>
                          _setMotionPhotoMode(fileName, active),
                      onMotionPhotoAutoplayChanged: _setMotionPhotoAutoplay,
                      onPanoramaModeChanged: (active) =>
                          _setPanoramaMode(fileName, active),
                      playbackManager: _playbackManager,
                      onToggleUI: _setUIVisibility,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );

    // Only the currently active item should have its Hero enabled.
    // ListenableBuilder ensures HeroMode updates immediately on swipe
    // without rebuilding the heavy media widgets.
    //
    // Also off for a close that hands the video to the floating player: the
    // Hero would fly the poster back to the file manager's thumbnail, when the
    // video is going to the floating window instead.
    final heroGatedWidget = ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        _playlistController,
        _floatingClose,
      ]),
      builder: (context, child) {
        final isCurrent = _playlistController.currentIndex == index;
        final closingToFloatingPlayer =
            _floatingClose.value != _FloatingClose.none;
        return HeroMode(
          enabled: isCurrent && !closingToFloatingPlayer,
          child: child!,
        );
      },
      child: itemWidget,
    );

    if (_scrollMode.isContinuous) {
      return heroGatedWidget;
    }
    return PlaylistTransitionTransformer(
      pageController: _pageController,
      index: index,
      effect: _transitionEffect,
      scrollDirection: _scrollMode.axis,
      child: heroGatedWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _buildViewer(context);
    if (!PlatformFeatures.isDesktop) return viewer;
    // On Windows the viewer is a root-navigator route built by hand, which the
    // theme's caption frame never sees, so it gets the title bar here (a no-op
    // where the window keeps its native one). Fullscreen folds the bar away
    // without touching the viewer's state, and moving the mouse brings the
    // controls back.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (_) {
        if (!_desktopFullscreen) return;
        if (_showUI) {
          _startHideTimer();
        } else {
          _setUIVisibility(true);
        }
      },
      child: DesktopCaptionFrame(
        child: DesktopCaptionHider(hidden: _desktopFullscreen, child: viewer),
      ),
    );
  }

  Widget _buildViewer(BuildContext context) {
    ref.watch(mediaViewerSessionProvider(_sessionKey));
    ref.watch(fileBrowserPinsBookmarksProvider(widget.container.volId));
    final toolbarSettings = ref.watch(fileManagerToolbarSettingsProvider(null));
    final mediaViewerConfig = _effectiveToolbarConfig(
      toolbarSettings.config.mediaViewerToolbarConfig,
    );
    ref.listen<FileManagerToolbarSettingsState>(
      fileManagerToolbarSettingsProvider(null),
      (previous, next) {
        if (previous?.config.mediaViewerToolbarConfig.swipeToSeekEnabled !=
            next.config.mediaViewerToolbarConfig.swipeToSeekEnabled) {
          _updateSwipePhysics();
        }
        if (previous?.config.mediaViewerToolbarConfig.pictureInPictureEnabled !=
            next.config.mediaViewerToolbarConfig.pictureInPictureEnabled) {
          _syncPictureInPicture();
        }
        if (previous?.config.showMediaCarousel !=
            next.config.showMediaCarousel) {
          _sessionController.setEnableCarousel(next.config.showMediaCarousel);
          if (!next.config.showMediaCarousel) {
            _sessionController.setCarouselVisible(false);
          }
        }
      },
    );
    ref.listen<MediaViewerSessionState>(
      mediaViewerSessionProvider(_sessionKey),
      (previous, next) {
        if (previous?.scrollMode != next.scrollMode) {
          _updateSwipePhysics();
          if (next.scrollMode.isContinuous) {
            _kickOffAspectRatioPreload();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scrollToCurrentIndex(animate: false);
            });
          }
        }
      },
    );
    final isContainerLocked = ref.watch(
      mediaViewerLockProvider(widget.container.volId),
    );
    if (isContainerLocked) {
      _dismissRouteAfterContainerLock();
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    if (widget.startInMiniPlayer) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    if (_playlistController.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
          ),
        ),
      );
    }

    return PopScope(
      // Always intercepted: the only things that reach this callback with
      // didPop == false are the person's own back presses (maybePop), which
      // is how a deliberate close is told apart from one the app forces with
      // pop / popUntil / removeRoute (app lock, locked container, ...).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // A menu is open: this press closes it (BackDismissibleMenuAnchor).
        if (OpenMenuBackGuard.hasOpenMenu) return;
        // Escape / back in fullscreen leaves fullscreen, like any player.
        if (_desktopFullscreen) {
          unawaited(_setDesktopFullscreen(false));
          return;
        }
        // A back press is as likely a misstap as any other touch: it only
        // points at the lock button.
        if (_controlsLocked) {
          _lockNudge.value++;
          return;
        }
        if (_isEditingLayout) {
          setState(() => _isEditingLayout = false);
          _updateSwipePhysics();
          _menuClosed();
          _startHideTimer();
          return;
        }
        unawaited(_closeFromBackPress());
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppSystemUI.transparentDark,
        // The black behind the viewer fades out while a swipe-to-dismiss drag
        // pulls the image away, showing the screen underneath.
        child: ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[
            _swipeDismissProgress,
            _openReveal,
          ]),
          builder: (context, scaffold) {
            final fades = ModalRoute.of(context)?.opaque == false;
            final shown =
                (1.0 - _swipeDismissProgress.value) * _openReveal.value;
            return ColoredBox(
              color: fades
                  ? Colors.black.withValues(alpha: shown.clamp(0.0, 1.0))
                  : Colors.black,
              child: scaffold,
            );
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true, // Draws content under bottom navigation bar
            extendBodyBehindAppBar: true,
            body: LayoutBuilder(
              builder: (context, outerConstraints) {
                // The media's own area: the window less the controls that
                // have a space of their own (see _chromeDocked).
                final dockTop = _chromeDocked ? _topChromeHeight : 0.0;
                final dockBottom = _chromeDocked ? _bottomChromeHeight : 0.0;
                final constraints = outerConstraints.deflate(
                  EdgeInsets.only(top: dockTop, bottom: dockBottom),
                );
                final newWidth = constraints.maxWidth;
                final newHeight = constraints.maxHeight;
                final bool dimsChanged =
                    (_viewportWidth > 0 && _viewportHeight > 0) &&
                    (newWidth != _viewportWidth ||
                        newHeight != _viewportHeight);

                if (dimsChanged) {
                  _viewportWidth = newWidth;
                  _viewportHeight = newHeight;
                  if (_scrollMode.isContinuous) {
                    final viewportIndex = _playlistController.currentIndex;
                    if (_listScrollController.hasClients &&
                        _listScrollController.positions.length == 1) {
                      final correctionToken = ++_viewportCorrectionToken;
                      _isProgrammaticScrolling = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted ||
                            correctionToken != _viewportCorrectionToken) {
                          return;
                        }
                        if (_listScrollController.hasClients &&
                            _listScrollController.positions.length == 1) {
                          _listScrollController.jumpTo(
                            _geometry.offsetForIndex(
                              viewportIndex,
                              _viewportWidth,
                              _viewportHeight,
                            ),
                          );
                        }
                        _isProgrammaticScrolling = false;
                      });
                    }
                  } else {
                    if (_pageController.hasClients &&
                        _pageController.positions.length == 1) {
                      _pageController.jumpToPage(
                        _playlistController.currentIndex,
                      );
                    }
                  }
                } else {
                  final isFirstLayout =
                      _viewportWidth == 0.0 && _viewportHeight == 0.0;
                  _viewportWidth = newWidth;
                  _viewportHeight = newHeight;
                  if (isFirstLayout &&
                      _scrollMode.isContinuous &&
                      _playlistController.currentIndex > 0) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _scrollToCurrentIndex(animate: false);
                    });
                  }
                }

                // Preserve the scrollable when system bars or orientation change
                // the viewport size. Remounting it here resets its offset to zero.
                final builderKey = ValueKey(
                  '${_playlistController.isPlaylistMode}_'
                  '${_playlistController.selectedFolder}_'
                  '${_playlistController.isShuffled}_'
                  '${_scrollMode}',
                );

                // Builds the actual scrollable (PageView or continuous ListView)
                // for a given physics value. Constructing it fresh here — inside
                // the ValueListenableBuilder below — is what makes swipe-locking
                // actually take effect: a widget built once and reused with a
                // stale `physics:` snapshot never reflects a later change to
                // the notifier, since ScrollPhysics is a constructor parameter,
                // not something PageView/ListView re-reads on its own.
                Widget buildMainScrollView(ScrollPhysics physics) {
                  if (_scrollMode.isContinuous) {
                    final listWidget = ListView.builder(
                      key: builderKey,
                      controller: _listScrollController,
                      scrollDirection: Axis.vertical,
                      physics: physics,
                      itemExtentBuilder: (index, _) => _getItemExtent(
                        index,
                        constraints.maxWidth,
                        constraints.maxHeight,
                      ),
                      padding: _geometry.continuousListPadding(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      ),
                      itemCount: _playlistController.playlist.length,
                      itemBuilder: (context, index) {
                        final itemHeight = _getItemExtent(
                          index,
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return SizedBox(
                          height: itemHeight,
                          width: constraints.maxWidth,
                          child: _buildMediaItem(index),
                        );
                      },
                    );

                    // Only registered while the list is transformed, so a plain
                    // tap at 1x isn't held back waiting to rule out a double tap.
                    final zoomed = !_continuousTransformationController.value
                        .isIdentity();
                    final listCanScroll =
                        physics is! NeverScrollableScrollPhysics;

                    final effectiveMinScale =
                        mediaViewerConfig.pinchZoomOutEnabled
                        ? mediaViewerConfig.minVideoZoomScale.clamp(
                            MediaViewerConstants.minVideoZoomFloor,
                            1.0,
                          )
                        : 1.0;

                    final continuousView = InteractiveViewer(
                      transformationController:
                          _continuousTransformationController,
                      minScale: effectiveMinScale,
                      maxScale: MediaViewerConstants.maxImageZoom,
                      interactionEndFrictionCoefficient: 0.0005,
                      boundaryMargin: mediaViewerConfig.pinchZoomOutEnabled
                          ? const EdgeInsets.all(double.infinity)
                          : EdgeInsets.zero,
                      clipBehavior: Clip.none,
                      // Only allow 1-finger panning when zoomed in; keep centered when zoomed out
                      panEnabled: _continuousScale > 1.01,
                      // Free 360° panning in all directions
                      panAxis: PanAxis.free,
                      onInteractionStart: (details) {
                        if (details.pointerCount >= 2) {
                          _continuousZoomAnimationController?.stop();
                          _onZoomInteractionChanged(false);
                        }
                      },
                      onInteractionUpdate: (details) {
                        final s = _getMatrixScale(
                          _continuousTransformationController.value,
                        );
                        if (s != _continuousScale) {
                          _continuousScale = s;
                        }
                      },
                      onInteractionEnd: (details) {
                        final s = _getMatrixScale(
                          _continuousTransformationController.value,
                        );
                        final clampedS = s.clamp(
                          effectiveMinScale,
                          MediaViewerConstants.maxImageZoom,
                        );
                        final vw = constraints.maxWidth;
                        final vh = constraints.maxHeight;

                        if (clampedS < 1.0 && vw > 0 && vh > 0) {
                          // Keep continuous view centered horizontally and vertically when zoomed out
                          final dx = vw * (1.0 - clampedS) / 2.0;
                          final dy = vh * (1.0 - clampedS) / 2.0;
                          _isClampingContinuous = true;
                          _continuousTransformationController.value =
                              Matrix4.identity()
                                ..setTranslationRaw(dx, dy, 0.0)
                                ..scale(clampedS, clampedS, clampedS);
                          _isClampingContinuous = false;
                        }

                        _continuousScale = _getMatrixScale(
                          _continuousTransformationController.value,
                        );
                        _onZoomInteractionChanged(true);
                        if (mounted) setState(() {});
                      },
                      child: listWidget,
                    );

                    return GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onDoubleTapDown: (details) =>
                          _continuousDoubleTapDetails = details,
                      onDoubleTap: () => _handleContinuousDoubleTap(
                        _continuousDoubleTapDetails,
                      ),
                      child: continuousView,
                    );
                  }

                  final roundedWidth = math.max(
                    1.0,
                    constraints.maxWidth.floorToDouble(),
                  );
                  final roundedHeight = math.max(
                    1.0,
                    constraints.maxHeight.floorToDouble(),
                  );

                  return Center(
                    child: SizedBox(
                      width: roundedWidth,
                      height: roundedHeight,
                      child: PageView.builder(
                        key: builderKey,
                        controller: _pageController,
                        scrollDirection: _scrollMode.axis,
                        physics: physics,
                        itemCount: _playlistController.playlist.length,
                        onPageChanged: (index) {
                          if (_playlistController.currentIndex != index) {
                            final sw = Stopwatch()..start();
                            _playlistController.updateIndex(index);
                            unawaited(_activateCurrentMedia());
                            VeLog.d(
                              'MediaViewer',
                              'Switched to item $index in ${sw.elapsedMilliseconds}ms',
                            );
                          }
                          _scheduleSurroundingPrefetch();
                        },
                        itemBuilder: (context, index) {
                          return _buildMediaItem(index);
                        },
                      ),
                    ),
                  );
                }

                Widget fadeDuringDismiss(Widget child) => ListenableBuilder(
                  listenable: Listenable.merge(<Listenable>[
                    _swipeDismissProgress,
                    _openReveal,
                  ]),
                  child: child,
                  builder: (context, child) {
                    // Fades out with a swipe, and in as the viewer opens out of
                    // the floating window.
                    final visible =
                        ((1.0 - _swipeDismissProgress.value) *
                                _openReveal.value)
                            .clamp(0.0, 1.0)
                            .toDouble();
                    return IgnorePointer(
                      ignoring: visible <= 0.01,
                      child: Opacity(opacity: visible, child: child),
                    );
                  },
                );

                final minimizeMusicPlayer =
                    widget.isLibraryPlayback &&
                    MediaViewerConstants.isAudio(
                      _playlistController.currentFile,
                    );
                final swipeDismissAxis = minimizeMusicPlayer
                    ? Axis.vertical
                    : _swipeDismissAxis;
                return MediaSwipeDismissLayer(
                  enabled:
                      (mediaViewerConfig.swipeToDismissEnabled ||
                          minimizeMusicPlayer) &&
                      !_isEditingLayout &&
                      !_controlsLocked,
                  axis: swipeDismissAxis,
                  bothDirections: !minimizeMusicPlayer,
                  canStart: _canStartSwipeDismiss,
                  onDismiss: _closeViewerFromSwipe,
                  progress: _swipeDismissProgress,
                  transformChild: minimizeMusicPlayer,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        top: dockTop,
                        bottom: dockBottom,
                        child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _handleTouchPointerDown,
                        onPointerMove: _handleTouchPointerMove,
                        onPointerUp: _handleTouchPointerUp,
                        onPointerCancel: _handleTouchPointerUp,
                        child: ValueListenableBuilder<ScrollPhysics>(
                          valueListenable: _swipePhysicsNotifier,
                          builder: (context, physics, child) {
                            return NotificationListener<ScrollNotification>(
                              onNotification: (ScrollNotification notification) {
                                if (notification.depth == 0) {
                                  if (_isProgrammaticScrolling) {
                                    return false;
                                  }
                                  if (notification is ScrollStartNotification &&
                                      notification.dragDetails != null) {
                                    _onScrollStart();
                                  } else if (notification
                                      is ScrollUpdateNotification) {
                                    if (_scrollMode.isContinuous &&
                                        _viewportHeight > 0 &&
                                        _listScrollController.hasClients) {
                                      final offset =
                                          _listScrollController.offset;
                                      final shift =
                                          _continuousVisibleCenterShift();
                                      double customHeight(int i) =>
                                          _getItemExtent(
                                            i,
                                            _viewportWidth,
                                            _viewportHeight,
                                          );
                                      final newIndex = _geometry.indexForOffset(
                                        offset + shift,
                                        _viewportWidth,
                                        _viewportHeight,
                                        customHeight,
                                      );

                                      if (_playlistController.currentIndex !=
                                          newIndex) {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              if (mounted &&
                                                  !_isProgrammaticScrolling &&
                                                  _playlistController
                                                          .currentIndex !=
                                                      newIndex) {
                                                _playlistController.updateIndex(
                                                  newIndex,
                                                );
                                                unawaited(
                                                  _activateCurrentMedia(),
                                                );
                                              }
                                            });
                                      }
                                    }
                                  } else if (notification
                                      is ScrollEndNotification) {
                                    _onScrollEnd();
                                  }
                                }
                                return false;
                              },
                              child: PlaylistSwipeScope(
                                drag: _playlistSwipeDrag,
                                axis: _scrollMode.axis,
                                enabled: !_scrollMode.isContinuous,
                                child: buildMainScrollView(physics),
                              ),
                            );
                          },
                        ),
                      ),
                      ),
                      // Fullscreen scrub preview: above the media, below the
                      // chrome, so the seekbar stays visible while dragging.
                      // Not built at all in mini-box mode or during layout editing.
                      if (!_isEditingLayout &&
                          mediaViewerConfig.scrubPreviewStyle ==
                              ScrubPreviewStyle.fullscreen)
                        Positioned.fill(
                          top: dockTop,
                          bottom: dockBottom,
                          child: fadeDuringDismiss(
                            VideoScrubFullscreenLayer(
                              previewHost: _scrubPreviewHost,
                              progress: _videoProgressNotifier,
                              rotationQuarterTurns:
                                  _rotations[_playlistController.currentFile] ??
                                  0,
                              adjustments: _adjustmentsFor(
                                _playlistController.currentFile,
                              ),
                            ),
                          ),
                        ),
                      // A-B repeat feedback. Mid-screen and pointer-transparent so
                      // it can never cover or block the button that triggered it.
                      if (!_isEditingLayout)
                        Positioned.fill(
                          child: fadeDuringDismiss(
                            AbLoopToast(data: _abLoopToast),
                          ),
                        ),

                      if (_isEditingLayout)
                        Positioned.fill(
                          child: MediaViewerInPlaceLayoutEditor(
                            toolbarConfig: mediaViewerConfig,
                            containerUri: widget.container.isLocalStorage
                                ? null
                                : widget.container.uri,
                            isImage: MediaViewerConstants.isImage(
                              _playlistController.currentFile,
                            ),
                            isAudio: MediaViewerConstants.isAudio(
                              _playlistController.currentFile,
                            ),
                            isPlaylistMode: _playlistController.isPlaylistMode,
                            onConfigChanged: (updated) {
                              unawaited(
                                ref
                                    .read(
                                      fileManagerToolbarSettingsProvider(
                                        null,
                                      ).notifier,
                                    )
                                    .updateMediaViewerConfig(updated),
                              );
                            },
                            onDone: () {
                              setState(() => _isEditingLayout = false);
                              _updateSwipePhysics();
                              _menuClosed();
                              _startHideTimer();
                            },
                            onOpenSettings: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SkinAreaScope(
                                    area: SkinArea.settings,
                                    child:
                                        const MediaViewerToolbarSettingsScreen(),
                                  ),
                                ),
                              );
                            },
                            onResetToDefaults: () async {
                              final controller = ref.read(
                                fileManagerToolbarSettingsProvider(
                                  null,
                                ).notifier,
                              );
                              await controller
                                  .resetMediaViewerConfigToDefaults();
                              if (mounted) {
                                showAppSnackBar(
                                  context,
                                  message:
                                      context.l10n.mediaControlsResetSuccess,
                                  tone: AppBannerTone.success,
                                );
                              }
                            },
                          ),
                        )
                      else ...[
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          // Slide by the bar's own height rather than a fixed offset:
                          // its height is status-bar/cutout inset + content, so it
                          // grows with display size and font scale, and a hard-coded
                          // value left part of it visible when hidden.
                          child: fadeDuringDismiss(
                            RepaintBoundary(
                              child: AnimatedSlide(
                                duration:
                                    MediaViewerConstants.animationDuration,
                                curve: Curves.easeOutCubic,
                                offset: _showUI
                                    ? Offset.zero
                                    : const Offset(0, -1),
                                child: ListenableBuilder(
                                  listenable: _playlistController,
                                  builder: (context, _) => _ChromeSizeProbe(
                                    onHeight: (h) => _setChromeHeight(top: h),
                                    child: MediaViewerTopBar(
                                    playlistController: _playlistController,
                                    currentFileName:
                                        _playlistController.currentFile,
                                    totalCount:
                                        _playlistController.playlist.length,
                                    toolbarConfig: mediaViewerConfig,
                                    isFullscreen: _desktopFullscreen,
                                    onToggleFullscreen:
                                        PlatformFeatures.isDesktop
                                        ? _toggleDesktopFullscreen
                                        : null,
                                    currentTransitionEffect: _transitionEffect,
                                    onTransitionEffectChanged:
                                        (newEffect) async {
                                          _sessionController
                                              .setTransitionEffect(newEffect);
                                          final toolbarService = ref.read(
                                            fileManagerToolbarServiceProvider,
                                          );
                                          final config = await toolbarService
                                              .load();
                                          await toolbarService.save(
                                            config.copyWith(
                                              playlistTransitionEffect:
                                                  newEffect,
                                            ),
                                          );
                                        },
                                    currentScrollMode: _scrollMode,
                                    onScrollModeChanged: (newMode) async {
                                      _sessionController.setScrollMode(newMode);
                                      final appSettingsService = ref.read(
                                        appSettingsServiceProvider,
                                      );
                                      final appSettings =
                                          await appSettingsService
                                              .loadSettings();
                                      await appSettingsService.saveSettings(
                                        appSettings.copyWith(
                                          playlistScrollMode: newMode,
                                        ),
                                      );
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (mounted)
                                              _scrollToCurrentIndex(
                                                animate: false,
                                              );
                                          });
                                    },
                                    isMuted: _isMuted,
                                    onExecuteAction: _executeMediaAction,
                                    onCustomizeControls: _openCustomizeControls,
                                    isBookmark: _isCurrentFileBookmark,
                                    onPlaylistChanged: _onPlaylistChanged,
                                    onMenuOpened: _menuOpened,
                                    onMenuClosed: _menuClosed,
                                    isImage: MediaViewerConstants.isImage(
                                      _playlistController.currentFile,
                                    ),
                                    isAudio: MediaViewerConstants.isAudio(
                                      _playlistController.currentFile,
                                    ),
                                  ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: fadeDuringDismiss(
                            RepaintBoundary(
                              child: AnimatedSlide(
                                duration:
                                    MediaViewerConstants.animationDuration,
                                curve: Curves.easeOutCubic,
                                offset: _showUI
                                    ? Offset.zero
                                    : const Offset(0, 1),
                                child: ListenableBuilder(
                                  listenable: _playlistController,
                                  builder: (context, _) {
                                    final isImg = MediaViewerConstants.isImage(
                                      _playlistController.currentFile,
                                    );
                                    final showCarousel =
                                        _enableCarousel &&
                                        _isCarouselVisible &&
                                        _showUI;

                                    return _ChromeSizeProbe(
                                      onHeight: (h) =>
                                          _setChromeHeight(bottom: h),
                                      child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            Colors.black.withValues(
                                              alpha: 0.85,
                                            ),
                                            Colors.black.withValues(
                                              alpha: 0.35,
                                            ),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          // Docked filmstrip carousel expands/collapses smoothly above controls
                                          AnimatedSwitcher(
                                            duration: MediaViewerConstants
                                                .animationDuration,
                                            reverseDuration:
                                                MediaViewerConstants
                                                    .animationDuration,
                                            switchInCurve: Curves.easeOutCubic,
                                            switchOutCurve: Curves.easeInCubic,
                                            transitionBuilder:
                                                (child, animation) {
                                                  final slide = animation.drive(
                                                    Tween<Offset>(
                                                      begin: const Offset(
                                                        0,
                                                        0.12,
                                                      ),
                                                      end: Offset.zero,
                                                    ),
                                                  );
                                                  return SizeTransition(
                                                    sizeFactor: animation,
                                                    axisAlignment: 1.0,
                                                    child: FadeTransition(
                                                      opacity: animation,
                                                      child: SlideTransition(
                                                        position: slide,
                                                        child: child,
                                                      ),
                                                    ),
                                                  );
                                                },
                                            child: showCarousel
                                                ? PlaylistCarouselOverlay(
                                                    key: const ValueKey(
                                                      'playlist-carousel-visible',
                                                    ),
                                                    container: widget.container,
                                                    playlist:
                                                        _playlistController
                                                            .playlist,
                                                    currentIndex:
                                                        _playlistController
                                                            .currentIndex,
                                                    thumbnailQuality:
                                                        widget.thumbnailQuality,
                                                    thumbnailCacheMode: widget
                                                        .thumbnailCacheMode,
                                                    onSelect:
                                                        _selectFromCarousel,
                                                    onClose: _toggleCarousel,
                                                  )
                                                : const SizedBox.shrink(
                                                    key: ValueKey(
                                                      'playlist-carousel-hidden',
                                                    ),
                                                  ),
                                          ),
                                          MediaViewerBottomControls(
                                            playlistController:
                                                _playlistController,
                                            playbackManager: _playbackManager,
                                            videoProgressNotifier:
                                                _videoProgressNotifier,
                                            abLoopNotifier: _abLoopNotifier,
                                            scrubPreviewHost: _scrubPreviewHost,
                                            toolbarConfig: mediaViewerConfig,
                                            isImage: isImg,
                                            isAudio:
                                                MediaViewerConstants.isAudio(
                                                  _playlistController
                                                      .currentFile,
                                                ),
                                            showUI: _showUI,
                                            isPlaylistMode: _playlistController
                                                .isPlaylistMode,
                                            autoAdvance: _autoAdvance,
                                            slideshowDelaySeconds:
                                                _slideshowDelaySeconds,
                                            isMuted: _isMuted,
                                            videoPlaybackMode:
                                                _videoPlaybackMode,
                                            screenOrientationIcon:
                                                _screenOrientationIcon(),
                                            onExecuteAction:
                                                _executeMediaAction,
                                            onStartHideTimer: _startHideTimer,
                                            onShowUIChanged: _setUIVisibility,
                                            isCarouselVisible:
                                                _isCarouselVisible,
                                            onMenuOpened: _menuOpened,
                                            onMenuClosed: _menuClosed,
                                          ),
                                        ],
                                      ),
                                    ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      // Topmost, so it also covers the top and bottom bars.
                      if (_controlsLocked)
                        Positioned.fill(
                          child: MediaViewerLockOverlay(
                            nudge: _lockNudge,
                            onUnlock: () => _setControlsLocked(false),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports the height of [child] once it is laid out and whenever it changes.
class _ChromeSizeProbe extends StatefulWidget {
  final ValueChanged<double> onHeight;
  final Widget child;

  const _ChromeSizeProbe({required this.onHeight, required this.child});

  @override
  State<_ChromeSizeProbe> createState() => _ChromeSizeProbeState();
}

class _ChromeSizeProbeState extends State<_ChromeSizeProbe> {
  void _report() {
    if (!mounted) return;
    final height = (context.findRenderObject() as RenderBox?)?.size.height;
    if (height != null && height > 0) widget.onHeight(height);
  }

  void _reportAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void initState() {
    super.initState();
    _reportAfterFrame();
  }

  @override
  void didUpdateWidget(_ChromeSizeProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reportAfterFrame();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _reportAfterFrame();
        return true;
      },
      child: SizeChangedLayoutNotifier(child: widget.child),
    );
  }
}

/// Calls [onChange] when the window's metrics (its size) change.
class _MetricsOnce with WidgetsBindingObserver {
  final VoidCallback onChange;

  _MetricsOnce(this.onChange);

  @override
  void didChangeMetrics() => onChange();
}
