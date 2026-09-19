import 'dart:async';
import 'dart:ui';
import 'package:path/path.dart' as p;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/retry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/scrub_preview_style.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/viewer/carousel_geometry.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_lock_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/media_prefetch_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/browser/viewer/video_scrub_preview_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_sheet.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/image_page_item.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_player_widget.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_top_bar.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_bottom_controls.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/advanced_settings_sheet.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_diagnostics_sheet.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/playlist_carousel_overlay.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/video_scrub_fullscreen_layer.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/playlist_transition_transformer.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_session_controller.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_toolbar_settings_screen.dart';

export 'package:vaultexplorer/features/browser/viewer/media_viewer_session_controller.dart'

    show VideoPlaybackMode;
import '../../../core/theme/app_theme.dart';
import 'native_video_controller.dart';

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
  final ValueChanged<String>? onCurrentFileChanged;

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
    this.onCurrentFileChanged,
  });

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen> {
  late final VaultFileIoApi _fileIoApi;
  late final VaultEngineEvents _engineEvents;
  late final MediaPrefetchController _prefetchController;

  late final PlaylistController _playlistController;
  late final VideoPlaybackManager _playbackManager;
  late PageController _pageController;
  late ScrollController _listScrollController;
  late final TransformationController _continuousTransformationController;
  double _continuousScale = 1.0;
  final ValueNotifier<ScrollPhysics> _swipePhysicsNotifier =
      ValueNotifier<ScrollPhysics>(const BouncingScrollPhysics());
  final ValueNotifier<VideoPlaybackProgress> _videoProgressNotifier =
      ValueNotifier<VideoPlaybackProgress>(const VideoPlaybackProgress());
  // Carries the seekbar's current drag session to the fullscreen scrub
  // preview layer (see ScrubPreviewStyle.fullscreen). Null between drags,
  // and always null in mini-box mode.
  final VideoScrubPreviewHost _scrubPreviewHost = VideoScrubPreviewHost(null);

  // Raw pointer tracking so a second finger touching down immediately locks
  // out swipe-to-next-item, before the gesture arena has a chance to let
  // the PageView/ListView drag recognizer mistake the pinch for a swipe.
  final Set<int> _activeTouchPointers = {};
  bool _multiTouchLock = false;
  // Whether an item's InteractiveViewer currently considers itself zoomed
  // or mid-interaction (reported via onZoomChanged). Kept separate from
  // _multiTouchLock so either source can hold the lock independently.
  bool _zoomInteractionLock = false;

  int _activeMenuCount = 0;
  late bool _wasEmpty;

  Timer? _slideshowTimer;
  Timer? _hideTimer;
  Timer? _prefetchDebounceTimer;

  final bool _autoPlay = true;
  final int _doubleTapSkipSeconds = 5;
  double _viewportWidth = 0.0;
  double _viewportHeight = 0.0;
  bool _isSwiping = false;
  bool _isProgrammaticScrolling = false;

  NativeVideoController? _lastListenedController;
  bool _wakelockEnabled = false;
  int _transitionToken = 0;

  String get _sessionKey => widget.container.uri;

  MediaViewerSessionState get _session =>
      ref.read(mediaViewerSessionProvider(_sessionKey));

  MediaViewerSession get _sessionController =>
      ref.read(mediaViewerSessionProvider(_sessionKey).notifier);

  bool get _showUI => _session.showUI;
  bool get _isCarouselVisible => _session.isCarouselVisible;
  bool get _enableCarousel => _session.enableCarousel;
  List<String> get _bookmarkPaths => _session.bookmarkPaths;
  bool get _autoAdvance => _session.autoAdvance;
  bool get _isAutoAdvancing => _session.isAutoAdvancing;
  int get _slideshowDelaySeconds => _session.slideshowDelaySeconds;
  VideoPlaybackMode get _videoPlaybackMode => _session.videoPlaybackMode;
  double get _playbackSpeed => _session.playbackSpeed;
  bool get _subtitlesEnabled => _session.subtitlesEnabled;
  double get _subtitleFontSize => _session.subtitleFontSize;
  double get _subtitleVerticalPosition => _session.subtitleVerticalPosition;
  BoxFit get _imageFit => _session.imageFit;
  PlaylistTransitionEffect get _transitionEffect => _session.transitionEffect;
  PlaylistScrollMode get _scrollMode => _session.scrollMode;
  bool get _isMuted => _session.isMuted;
  Map<String, int> get _rotations => _session.rotations;
  Map<String, int> get _imageReloadEpoch => _session.imageReloadEpoch;

  @override
  void initState() {
    super.initState();
    _fileIoApi = ref.read(vaultFileIoApiProvider);
    _engineEvents = ref.read(vaultEngineEventsProvider);
    _prefetchController = MediaPrefetchController(
      container: widget.container,
      fileIoApi: _fileIoApi,
      thumbnailCache: ref.read(thumbnailCacheServiceProvider),
      thumbnailQuality: widget.thumbnailQuality,
      thumbnailCacheMode: widget.thumbnailCacheMode,
    );
    ThumbnailConcurrency.videoLimiter.cancelAll();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _engineEvents.addUsbContainerDetachedListener(_onContainerDetached);

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
    _playbackManager = VideoPlaybackManager();
    _pageController = PageController(initialPage: widget.initialIndex);
    _listScrollController = ScrollController();
    _continuousTransformationController = TransformationController();

    _playlistController.addListener(_onPlaylistUpdate);
    _playbackManager.activeControllerNotifier.addListener(
      _onActiveVideoControllerChanged,
    );
    _playbackManager.currentFileNotifier.addListener(
      _onCurrentMediaFileChanged,
    );

    _loadConfig();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(_activateCurrentMedia());
      _startSlideshowTimerIfNeeded();
      await PlaybackThrottleController.initGate;
      if (mounted) _prefetchSurroundingItems();
    });
  }

  int _activateToken = 0;
  Future<void> _activateCurrentMedia() async {
    if (_playlistController.isEmpty) return;
    final file = _playlistController.currentFile;
    try {
      widget.onCurrentFileChanged?.call(file);
    } catch (_) {
      // Best-effort callback into the parent widget; a bug or edge case in
      // its listener shouldn't break media activation here.
    }
    final token = ++_activateToken;
    final isVid = MediaViewerConstants.isVideo(file);
    final isAud = MediaViewerConstants.isAudio(file);
    if (isVid || isAud) {
      PlaybackThrottleController.setInitializing();
    }
    await PlaybackThrottleController.setActive(isVid);
    if (!mounted || token != _activateToken) return;
    if (isVid || isAud) {
      unawaited(
        _playbackManager.activate(
          fileName: file,
          volId: widget.container.volId,
          // Local storage has no vault session for the native player to
          // stream decrypted bytes from -- NativePlayerManager's local
          // branch instead reads this as a real, absolute path straight
          // off disk, so it needs the full path rather than one relative
          // to the container root.
          filePath: widget.container.isLocalStorage
              ? p.join(widget.container.uri, file)
              : file,
          isLocalStorage: widget.container.isLocalStorage,
          autoPlay: _autoPlay,
          playbackSpeed: _playbackSpeed,
          looping: _videoPlaybackMode == VideoPlaybackMode.loop,
        ),
      );
    } else {
      _playbackManager.pauseActive();
    }
  }

  Future<void> _loadConfig() async {
    final config = await ref.read(fileManagerToolbarServiceProvider).load();
    final appSettings = await ref
        .read(appSettingsServiceProvider)
        .loadSettings();
    final records = await ref.read(containerRepositoryProvider).loadAll();
    final bookmarkPaths = records[widget.container.uri]?.bookmarkPaths;
    final pinnedPaths = records[widget.container.uri]?.pinnedPaths;
    if (mounted) {
      _sessionController.setEnableCarousel(config.showMediaCarousel);
      if (!config.showMediaCarousel) {
        _sessionController.setCarouselVisible(false);
      }
      _sessionController.setTransitionEffect(config.playlistTransitionEffect);
      _sessionController.setScrollMode(appSettings.playlistScrollMode);
      _sessionController.setBookmarkPaths(
        List<String>.from(bookmarkPaths ?? const []),
      );
      _sessionController.setIsMuted(appSettings.videoMuted);

      if (appSettings.videoMuted) {
        _playbackManager.activeController?.setVolume(0);
      }
      if (pinnedPaths != null) {
        _playlistController.updatePinnedPaths(Set<String>.from(pinnedPaths));
      }

      if (appSettings.playlistScrollMode.isContinuous) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToCurrentIndex(animate: false);
        });
      }
    }
  }

  Uint8List? _prefetchedBytesFor(String fileName) {
    return ref
        .read(thumbnailCacheServiceProvider)
        .peekMemory(widget.container, fileName, widget.thumbnailQuality);
  }

  void _onContainerDetached(int volId) {
    if (!mounted || volId != widget.container.volId) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _onPlaylistUpdate() {
    if (!mounted) return;
    final nowEmpty = _playlistController.isEmpty;
    if (nowEmpty != _wasEmpty) {
      _wasEmpty = nowEmpty;
      setState(() {});
    }
  }

  // Pure carousel layout math now lives in CarouselGeometry
  // (carousel_geometry.dart) -- constructed fresh from current playlist/
  // rotation state on each use since it's a cheap, immutable value object;
  // no caching, same as when this was a handful of instance methods
  // reading the same state directly.
  CarouselGeometry get _geometry => CarouselGeometry(
    playlist: _playlistController.playlist,
    rotations: _rotations,
    isAudio: MediaViewerConstants.isAudio,
    aspectRatioFor: (fileName) => MediaAspectRatioCache.get(widget.container, fileName),
  );

  void _scrollToCurrentIndex({bool animate = false}) {
    final index = _playlistController.currentIndex;
    if (_scrollMode.isContinuous) {
      if (_listScrollController.hasClients &&
          _listScrollController.positions.length == 1 &&
          _viewportHeight > 0) {
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
          _isProgrammaticScrolling = false;
          unawaited(_activateCurrentMedia());
          _onScrollEnd();
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
      return;
    }

    controller.addListener(_onControllerTickUpdate);
    _updateWakelock(controller.value.isPlaying);
    // Each playlist item gets its own native controller, which otherwise
    // starts at the platform's default volume -- reapply the persisted
    // mute state here so toggling mute stays in effect as the person
    // moves through the playlist, not just for the item it was set on.
    controller.setVolume(_isMuted ? 0 : 100);
  }

  void _onCurrentMediaFileChanged() {
    _videoProgressNotifier.value = const VideoPlaybackProgress();
  }

  void _onControllerTickUpdate() {
    final controller = _playbackManager.activeController;
    if (controller == null || controller.value.hasError) return;

    _updateWakelock(controller.value.isPlaying);

    final isInitialized = controller.value.isInitialized;
    final position = controller.value.position;
    final duration = controller.value.duration;

    if (!isInitialized || duration <= Duration.zero) return;

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
        final idx = _playlistController.playlist.indexOf(fileName);
        return idx != -1 && (idx - _playlistController.currentIndex).abs() <= 2;
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
    final token = ++_transitionToken;
    _cancelSlideshowTimer();
    _startHideTimer();
    _isProgrammaticScrolling = true;

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
      if (_listScrollController.hasClients &&
          _listScrollController.positions.length == 1 &&
          _viewportHeight > 0) {
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

    if (mounted && _transitionToken == token) {
      _isProgrammaticScrolling = false;
      _isSwiping = false;
      _sessionController.setIsAutoAdvancing(false);
      final currentFile = _playlistController.currentFile;
      if (MediaViewerConstants.isImage(currentFile)) {
        _startSlideshowTimerIfNeeded();
      }
      if (_showUI) {
        _startHideTimer();
      }
      if (mounted) setState(() {});
    } else {
      _isProgrammaticScrolling = false;
    }
  }

  void _autoAdvanceToNext() {
    final index = _playlistController.currentIndex;
    if (index < _playlistController.playlist.length - 1) {
      _transitionTo(
        index + 1,
        animate: true,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _sessionController.setIsAutoAdvancing(false);
    }
  }

  void _navigateToNext() {
    final index = _playlistController.currentIndex;
    if (index < _playlistController.playlist.length - 1) {
      HapticFeedback.lightImpact();
      _transitionTo(index + 1, animate: true);
    }
  }

  void _navigateToPrev() {
    final index = _playlistController.currentIndex;
    if (index > 0) {
      HapticFeedback.lightImpact();
      _transitionTo(index - 1, animate: true);
    }
  }

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

  // Recomputes the shared swipe-physics notifier from the two lock sources:
  // raw multi-touch (fires the instant a 2nd finger is detected) and the
  // zoom/interaction state reported by the active media item. Either one
  // holding the lock is enough to disable swipe-to-next-item.
  void _updateSwipePhysics() {
    final shouldLock = _multiTouchLock || _zoomInteractionLock;
    final desired = shouldLock
        ? const NeverScrollableScrollPhysics()
        : const BouncingScrollPhysics();
    if (_swipePhysicsNotifier.value.runtimeType != desired.runtimeType) {
      _swipePhysicsNotifier.value = desired;
    }
  }

  void _onZoomInteractionChanged(bool allowSwipe) {
    _zoomInteractionLock = !allowSwipe;
    _updateSwipePhysics();
  }

  // Called on every raw pointer down, regardless of which gesture
  // recognizer ends up winning the arena. This lets us lock out
  // swipe-to-next-item the instant a second finger touches the screen,
  // rather than waiting for InteractiveViewer's onInteractionStart (which
  // can lose the arena race to the PageView/ListView drag recognizer when
  // the two fingers of a pinch don't land in exactly the same frame).
  void _handleTouchPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _activeTouchPointers.add(event.pointer);
    if (_activeTouchPointers.length >= 2 && !_multiTouchLock) {
      _multiTouchLock = true;
      _updateSwipePhysics();
    }
  }

  void _handleTouchPointerUp(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _activeTouchPointers.remove(event.pointer);
    if (_activeTouchPointers.isEmpty && _multiTouchLock) {
      _multiTouchLock = false;
      _updateSwipePhysics();
    }
  }

  void _onScrollStart() {
    if (!_isSwiping) {
      _isSwiping = true;
      _sessionController.setIsAutoAdvancing(false);
      _playbackManager.activeController?.pause();
      _cancelSlideshowTimer();
    }
  }

  void _onScrollEnd() {
    _isSwiping = false;
    if (_playbackManager.currentFileNotifier.value !=
        _playlistController.currentFile) {
      unawaited(_activateCurrentMedia());
    } else if (_autoPlay) {
      _playbackManager.activeController?.play();
    }
    final currentFile = _playlistController.currentFile;
    if (MediaViewerConstants.isImage(currentFile)) {
      _startSlideshowTimerIfNeeded();
    }
    if (mounted) setState(() {});
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
      VeLog.e('MediaViewerScreen', 'Delete failed for ${VeLog.censorName(fileToDelete)}', e);
    }

    if (success && mounted) {
      _rotations.remove(fileToDelete);
      _imageReloadEpoch.remove(fileToDelete);
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
      _bookmarkPaths.contains(_playlistController.currentFile);

  Future<void> _toggleBookmarkCurrentFile() async {
    final file = _playlistController.currentFile;
    final wasBookmark = _bookmarkPaths.contains(file);
    _sessionController.toggleBookmark(file);
    final containerRepository = ref.read(containerRepositoryProvider);
    final records = await containerRepository.loadAll();
    var record = records[widget.container.uri];
    record ??= ContainerRecord(
      uri: widget.container.uri,
      label: widget.container.displayName,
      containerFormat: widget.container.containerFormat,
    );
    record = record.copyWith(bookmarkPaths: _bookmarkPaths);
    await containerRepository.save(record);
    if (mounted) {
      showAppSnackBar(
        context,
        message: wasBookmark
            ? context.l10n.unbookmarkedCount(1)
            : context.l10n.bookmarkedCount(1),
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _openImageEditor() async {
    _menuOpened();
    final fileToEdit = _playlistController.currentFile;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(
          container: widget.container,
          filePath: fileToEdit,
          thumbnailQuality: widget.thumbnailQuality,
        ),
      ),
    );
    if (!mounted) return;
    _menuClosed();
    // Whether or not anything was actually saved, force this item's
    // ImagePageItem to remount so it re-reads through FullResImageCache /
    // ThumbnailCacheService rather than keep showing whatever bytes it
    // already had in memory from before the editor opened. If nothing
    // changed, those caches weren't touched and the remount just re-hits
    // them -- cheap and correct either way.
    _sessionController.bumpImageReloadEpoch(fileToEdit);
  }

  Future<void> _renameCurrentFile() async {
    _menuOpened();
    final fileToRename = _playlistController.currentFile;
    final lastSlash = fileToRename.lastIndexOf('/');
    final dirPath = lastSlash == -1 ? '' : fileToRename.substring(0, lastSlash);
    final baseName = lastSlash == -1
        ? fileToRename
        : fileToRename.substring(lastSlash + 1);

    var existingEntries = <RawEntry>[];
    try {
      final raw = await _fileIoApi.listDirectory(widget.container, dirPath);
      if (raw != null) {
        existingEntries = RawEntry.parseAll(raw);
      }
    } catch (e) {
      VeLog.w('MediaViewerScreen', 'Directory listing failed at ${VeLog.censorUri(dirPath)} during rename conflict check', e);
    }

    final currentEntry = existingEntries.firstWhere(
      (e) => e.name == baseName,
      orElse: () =>
          RawEntry(name: baseName, isDir: false, sizeBytes: 0, modifiedSecs: 0),
    );

    if (!mounted) {
      _menuClosed();
      return;
    }

    await BrowserDialogs.showRename(
      context,
      container: widget.container,
      oldEntries: [currentEntry],
      existingEntries: existingEntries,
      currentDirPath: dirPath,
      onSuccess: () {},
      onEntryRenamed: (oldPath, newPath) {
        final rotation = _rotations[oldPath];
        if (rotation != null) {
          _sessionController.setRotation(newPath, rotation);
        }
        _playbackManager.renameFile(oldPath, newPath);
        _playlistController.renameFile(oldPath, newPath);
        if (mounted) {
          showAppSnackBar(
            context,
            message: context.l10n.mediaFileRenamedMessage,
            tone: AppBannerTone.success,
          );
        }
      },
    );
    _menuClosed();
  }

  void _handleMediaError(String fileName) {
    if (fileName != _playlistController.currentFile) return;
    _cancelSlideshowTimer();
    _playbackManager.pauseActive();
  }

  void _cancelSlideshowTimer() {
    _slideshowTimer?.cancel();
    _slideshowTimer = null;
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
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

  void _setUIVisibility(bool show) {
    if (mounted) {
      _sessionController.setShowUI(show);
      if (show) {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
        _startHideTimer();
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _hideTimer?.cancel();
      }
    }
  }

  void _menuOpened() {
    _activeMenuCount++;
    _hideTimer?.cancel();
  }

 void _menuClosed() {
    _activeMenuCount = (_activeMenuCount - 1).clamp(0, 999);
    _startHideTimer();
  }

  Future<void> _showFileInfoHelper(VaultFileIoApi fileIoApi) async {
    _menuOpened();
    final file = _playlistController.currentFile;
    final lastSlash = file.lastIndexOf('/');
    final dirPath = lastSlash == -1 ? '' : file.substring(0, lastSlash);
    final baseName = lastSlash == -1 ? file : file.substring(lastSlash + 1);
    var existingEntries = <RawEntry>[];
    try {
      final raw = await fileIoApi.listDirectory(widget.container, dirPath);
      if (raw != null) {
        existingEntries = RawEntry.parseAll(raw);
      }
    } catch (_) {}
    final currentEntry = existingEntries.firstWhere(
      (e) => e.name == baseName,
      orElse: () => RawEntry(
        name: baseName,
        isDir: false,
        sizeBytes: 0,
        modifiedSecs: 0,
      ),
    );
    if (mounted) {
      await FileInfoSheet.show(
        context,
        container: widget.container,
        entry: currentEntry,
        currentDirPath: dirPath,
      );
    }
    _menuClosed();
  }

void _showOrientationSheet(BuildContext context) {
    _menuOpened();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        final l10n = sheetContext.l10n;
        final isLandscape =
            MediaQuery.of(sheetContext).orientation == Orientation.landscape;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    l10n.screenOrientationMenu,
                    style:
                        Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.stay_current_portrait_rounded),
                  title: Text(l10n.forcePortraitMenu),
                  trailing: !isLandscape
                      ? Icon(Icons.check_rounded, color: cs.primary)
                      : null,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    SystemChrome.setPreferredOrientations(
                        [DeviceOrientation.portraitUp]);
                    Navigator.pop(sheetContext);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.stay_current_landscape_rounded),
                  title: Text(l10n.forceLandscapeMenu),
                  trailing: isLandscape
                      ? Icon(Icons.check_rounded, color: cs.primary)
                      : null,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]);
                    Navigator.pop(sheetContext);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.screen_rotation_rounded),
                  title: Text(l10n.autoRotateSensorMenu),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    SystemChrome.setPreferredOrientations(
                        DeviceOrientation.values);
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(_menuClosed);
  }

  void _showPlaylistOptionsMenu() {
    _menuOpened();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isPlaylist = _playlistController.isPlaylistMode;
            final folderScope = _playlistController.selectedFolder;
            final isThisFolderSelected =
                isPlaylist && folderScope == 'Current Folder Only';
            final isAllSelected = isPlaylist && folderScope == 'All';
            final cs = Theme.of(context).colorScheme;
            final l10n = context.l10n;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Text(
                        l10n.playlistOptionsTooltip,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.folder_outlined,
                        color: isThisFolderSelected ? cs.primary : null,
                      ),
                      title: Text(l10n.thisFolderMenu),
                      trailing: isThisFolderSelected
                          ? Icon(Icons.check_rounded, color: cs.primary)
                          : null,
                      onTap: () async {
                        final targetFile = _playlistController.currentFile;
                        if (isThisFolderSelected) {
                          _playlistController.disablePlaylist();
                        } else {
                          await _playlistController
                              .enablePlaylist('Current Folder Only');
                        }
                        final newIndex =
                            _playlistController.playlist.indexOf(targetFile);
                        if (newIndex != -1) {
                          _playlistController.updateIndex(newIndex);
                        }
                        _onPlaylistChanged();
                        setSheetState(() {});
                      },
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.folder_copy_outlined,
                        color: isAllSelected ? cs.primary : null,
                      ),
                      title: Text(l10n.allInclSubfoldersMenu),
                      trailing: isAllSelected
                          ? Icon(Icons.check_rounded, color: cs.primary)
                          : null,
                      onTap: () async {
                        final targetFile = _playlistController.currentFile;
                        if (isAllSelected) {
                          _playlistController.disablePlaylist();
                        } else {
                          await _playlistController.enablePlaylist('All');
                        }
                        final newIndex =
                            _playlistController.playlist.indexOf(targetFile);
                        if (newIndex != -1) {
                          _playlistController.updateIndex(newIndex);
                        }
                        _onPlaylistChanged();
                        setSheetState(() {});
                      },
                    ),
                    if (_playlistController.isPlaylistMode) ...[
                      const Divider(),
                      ListTile(
                        leading: Icon(
                          Icons.shuffle_rounded,
                          color: _playlistController.isShuffled
                              ? cs.primary
                              : null,
                        ),
                        title: Text(_playlistController.isShuffled
                            ? l10n.disableShuffleMenu
                            : l10n.shufflePlaylistMenu),
                        trailing: Switch(
                          value: _playlistController.isShuffled,
                          onChanged: (_) {
                            final targetFile = _playlistController.currentFile;
                            _playlistController.toggleShuffle();
                            final newIndex = _playlistController.playlist
                                .indexOf(targetFile);
                            if (newIndex != -1) {
                              _playlistController.updateIndex(newIndex);
                            }
                            _onPlaylistChanged();
                            setSheetState(() {});
                          },
                        ),
                        onTap: () {
                          final targetFile = _playlistController.currentFile;
                          _playlistController.toggleShuffle();
                          final newIndex = _playlistController.playlist
                              .indexOf(targetFile);
                          if (newIndex != -1) {
                            _playlistController.updateIndex(newIndex);
                          }
                          _onPlaylistChanged();
                          setSheetState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 6),
                        child: Text(
                          l10n.playlistScrollModeMenu,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<PlaylistScrollMode>(
                          segments: PlaylistScrollMode.values.map((mode) {
                            return ButtonSegment<PlaylistScrollMode>(
                              value: mode,
                              icon: Icon(mode.icon, size: 16),
                              label: Text(
                                mode.getLocalizedLabel(l10n),
                                style: const TextStyle(fontSize: 11),
                              ),
                            );
                          }).toList(),
                          selected: {_scrollMode},
                          onSelectionChanged: (newSelection) {
                            final newMode = newSelection.first;
                            _sessionController.setScrollMode(newMode);
                            ref
                                .read(appSettingsServiceProvider)
                                .loadSettings()
                                .then((s) {
                              ref
                                  .read(appSettingsServiceProvider)
                                  .saveSettings(
                                      s.copyWith(playlistScrollMode: newMode));
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _scrollToCurrentIndex(animate: false);
                              }
                            });
                            setSheetState(() {});
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(_menuClosed);
  }

  void _executeMediaAction(MediaViewerAction action) {
    _startHideTimer();
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final isImage = MediaViewerConstants.isImage(_playlistController.currentFile);

    switch (action) {
      case MediaViewerAction.playPause:
        final controller = _playbackManager.activeController;
        if (isImage) {
          _updatePlaybackMode(
            _autoAdvance
                ? VideoPlaybackMode.playOnce
                : VideoPlaybackMode.playAndAdvance,
          );
        } else if (controller != null) {
          if (controller.value.isPlaying) {
            controller.pause();
          } else {
            controller.play();
          }
        }
        break;
      case MediaViewerAction.previous:
        _navigateToPrev();
        break;
      case MediaViewerAction.next:
        _navigateToNext();
        break;
      case MediaViewerAction.mute:
        _startHideTimer();
        _sessionController.toggleMute();
        _playbackManager.activeController?.setVolume(_isMuted ? 0 : 100);
        ref.read(appSettingsServiceProvider).loadSettings().then((appSettings) {
          ref.read(appSettingsServiceProvider).saveSettings(
                appSettings.copyWith(videoMuted: _isMuted),
              );
        });
        break;
      case MediaViewerAction.playbackMode:
        VideoPlaybackMode nextMode;
        if (!_playlistController.isPlaylistMode) {
          nextMode = _videoPlaybackMode == VideoPlaybackMode.loop
              ? VideoPlaybackMode.playOnce
              : VideoPlaybackMode.loop;
        } else {
          nextMode = switch (_videoPlaybackMode) {
            VideoPlaybackMode.playOnce => VideoPlaybackMode.loop,
            VideoPlaybackMode.loop => VideoPlaybackMode.playAndAdvance,
            VideoPlaybackMode.playAndAdvance => VideoPlaybackMode.playOnce,
          };
        }
        _updatePlaybackMode(nextMode);
        break;
      case MediaViewerAction.thumbnailCarousel:
        if (_enableCarousel && _playlistController.isPlaylistMode) {
          _toggleCarousel();
        }
        break;
       case MediaViewerAction.rotate90:
        _startHideTimer();
        _sessionController.rotateClockwise(_playlistController.currentFile);
        break;
      case MediaViewerAction.playlistMenu:
        _showPlaylistOptionsMenu();
        break;
      case MediaViewerAction.bookmark:
        _toggleBookmarkCurrentFile();
        break;
      case MediaViewerAction.fileInfo:
        _showFileInfoHelper(fileIoApi);
        break;
      case MediaViewerAction.openWithApp:
        fileIoApi.openWithApp(widget.container, _playlistController.currentFile);
        break;
      case MediaViewerAction.editImage:
        _openImageEditor();
        break;
      case MediaViewerAction.rename:
        _renameCurrentFile();
        break;
      case MediaViewerAction.delete:
        _deleteCurrentFile();
        break;
      case MediaViewerAction.diagnostics:
        _showDiagnostics(context);
        break;
      case MediaViewerAction.advancedSettings:
        _showAdvancedSettings(context, isImage);
        break;
      case MediaViewerAction.playbackSpeed:
        _showAdvancedSettings(context, isImage, initialPage: 'playbackSpeed');
        break;
      case MediaViewerAction.imageFit:
        _showAdvancedSettings(context, isImage, initialPage: 'imageFit');
        break;
      case MediaViewerAction.slideshowDelay:
        _showAdvancedSettings(context, isImage, initialPage: 'slideshowDelay');
        break;
      case MediaViewerAction.subtitles:
        _showAdvancedSettings(context, isImage, initialPage: 'subtitleTracks');
        break;
      case MediaViewerAction.audioTrack:
        _showAdvancedSettings(context, isImage, initialPage: 'audioTracks');
        break;
      case MediaViewerAction.screenOrientation:
        _showOrientationSheet(context);
        break;
    }
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

  void _updatePlaybackMode(VideoPlaybackMode mode) {
    _startHideTimer();
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

 void _showAdvancedSettings(
    BuildContext context,
    bool isImage, {
    String initialPage = 'main',
  }) {
    _menuOpened();

    final toolbarSettings = ref.read(fileManagerToolbarSettingsProvider(null));
    final mediaConfig = toolbarSettings.config.mediaViewerToolbarConfig;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
       return AdvancedSettingsSheet(
          initialPage: initialPage,
          actions: mediaConfig.advancedSettingsActions,
          isMuted: _isMuted,
          onExecuteAction: _executeMediaAction,
          onCustomizeControls: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MediaViewerToolbarSettingsScreen(),
              ),
            );
          },
          isPlaylistMode: _playlistController.isPlaylistMode,
          isImage: isImage,
          currentFileName: _playlistController.currentFile,
          initialRotation: _rotations[_playlistController.currentFile] ?? 0,
          initialImageFit: _imageFit,
          initialSlideshowDelaySeconds: _slideshowDelaySeconds,
          initialPlaybackSpeed: _playbackSpeed,
          hasSubtitles: _playbackManager.isSubtitleAvailable(
            _playlistController.currentFile,
          ),
          initialSubtitlesEnabled: _subtitlesEnabled,
          initialSubtitleFontSize: _subtitleFontSize,
          initialSubtitleVerticalPosition: _subtitleVerticalPosition,
          videoController: _playbackManager.activeController,
          onSubtitleFontSizeChanged: (size) {
            _startHideTimer();
            _sessionController.setSubtitleFontSize(size);
          },
          onSubtitleVerticalPositionChanged: (pos) {
            _startHideTimer();
            _sessionController.setSubtitleVerticalPosition(pos);
          },
          onRotationChanged: (rot) {
            _startHideTimer();
            _sessionController.setRotation(_playlistController.currentFile, rot);
          },
          onImageFitChanged: (fit) {
            _startHideTimer();
            _sessionController.setImageFit(fit);
          },
          onSlideshowDelayChanged: (delay) {
            _startHideTimer();
            _sessionController.setSlideshowDelaySeconds(delay);
            if (_autoAdvance) {
              _startSlideshowTimerIfNeeded();
            }
          },
          onPlaybackSpeedChanged: (speed) {
            _startHideTimer();
            _sessionController.setPlaybackSpeed(speed);
          },
          onSubtitlesEnabledChanged: (enabled) {
            _startHideTimer();
            _sessionController.setSubtitlesEnabled(enabled);
          },
        );
      },
    ).whenComplete(_menuClosed);
  }

  void _showDiagnostics(BuildContext context) {
    final controller = _playbackManager.activeController;
    if (controller == null) return;
    _menuOpened();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      barrierDismissible: true,
      builder: (context) {
        return MediaDiagnosticsDialog(
          fileName: _playlistController.currentFile,
          controller: controller,
          playbackSpeed: _playbackSpeed,
        );
      },
    ).whenComplete(_menuClosed);
  }

  void _updateWakelock(bool enable) {
    if (_wakelockEnabled != enable) {
      _wakelockEnabled = enable;
      _fileIoApi.setKeepScreenOn(enable);
    }
  }

  @override
  void dispose() {
    PlaybackThrottleController.setActive(false);
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
    _continuousTransformationController.dispose();
    _playbackManager.dispose();
    _swipePhysicsNotifier.dispose();
    _videoProgressNotifier.dispose();
    _scrubPreviewHost.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Widget _buildMediaItem(int index) {
    final fileName = _playlistController.playlist[index];
    final contentUriString = _contentUriFor(fileName);
    final prefetchedBytes = _prefetchedBytesFor(fileName);
    if (prefetchedBytes == null) {
      unawaited(_prefetchController.prefetchThumbnail(fileName));
    }
    final isImg = MediaViewerConstants.isImage(fileName);
    final isAudio = MediaViewerConstants.isAudio(fileName);
    final itemWidget = Container(
      color: Colors.black,
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
              showUI: _showUI,
              enableZoom: !_scrollMode.isContinuous,
              onToggleUI: _setUIVisibility,
              onZoomChanged: _onZoomInteractionChanged,
              thumbnailQuality: widget.thumbnailQuality,
              thumbnailCacheMode: widget.thumbnailCacheMode,
              onSizeKnown: (w, h) {
                if (_scrollMode.isContinuous) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
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
              showUI: _showUI,
              enableZoom: !_scrollMode.isContinuous,
              onToggleUI: _setUIVisibility,
              skipSeconds: _doubleTapSkipSeconds,
              isAudio: isAudio,
              subtitlesEnabled: _subtitlesEnabled,
              subtitleFontSize: _subtitleFontSize,
              subtitleVerticalPosition: _subtitleVerticalPosition,
              onSubtitleVerticalPositionChanged: (pos) {
                _sessionController.setSubtitleVerticalPosition(pos);
              },
              playbackSpeed: _playbackSpeed,
              rotationQuarterTurns: _rotations[fileName] ?? 0,
              progressNotifier: _videoProgressNotifier,
              onSubtitlesAvailableChanged: (val) {
                _playbackManager.updateSubtitleStatus(fileName, val);
                if (fileName == _playlistController.currentFile) {
                  setState(() {});
                }
              },
              onSizeKnown: (w, h) {
                if (_scrollMode.isContinuous) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                }
              },
              onZoomChanged: _onZoomInteractionChanged,
              onError: () => _handleMediaError(fileName),
            ),
    );

    // Only the currently active item should have its Hero enabled.
    // ListenableBuilder ensures HeroMode updates immediately on swipe
    // without rebuilding the heavy media widgets.
    final heroGatedWidget = ListenableBuilder(
      listenable: _playlistController,
      builder: (context, child) {
        final isCurrent = _playlistController.currentIndex == index;
        return HeroMode(enabled: isCurrent, child: child!);
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
    ref.watch(mediaViewerSessionProvider(_sessionKey));
    final toolbarSettings = ref.watch(fileManagerToolbarSettingsProvider(null));
    final mediaViewerConfig = toolbarSettings.config.mediaViewerToolbarConfig;
    final isContainerLocked = ref.watch(
      mediaViewerLockProvider(widget.container.volId),
    );
    if (isContainerLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUI.transparentDark,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBody: true, // Draws content under bottom navigation bar
        extendBodyBehindAppBar: true,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final newWidth = constraints.maxWidth;
            final newHeight = constraints.maxHeight;
            final bool dimsChanged =
                (_viewportWidth > 0 && _viewportHeight > 0) &&
                (newWidth != _viewportWidth || newHeight != _viewportHeight);

            if (dimsChanged) {
              _viewportWidth = newWidth;
              _viewportHeight = newHeight;
              if (_scrollMode.isContinuous) {
                final targetOffset = _geometry.offsetForIndex(
                  _playlistController.currentIndex,
                  newWidth,
                  newHeight,
                );
                final oldController = _listScrollController;
                _listScrollController = ScrollController(
                  initialScrollOffset: targetOffset,
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  oldController.dispose();
                  if (mounted) {
                    unawaited(_activateCurrentMedia());
                    _onScrollEnd();
                  }
                });
              } else {
                final oldPageController = _pageController;
                _pageController = PageController(
                  initialPage: _playlistController.currentIndex,
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  oldPageController.dispose();
                  if (mounted) {
                    unawaited(_activateCurrentMedia());
                    _onScrollEnd();
                  }
                });
              }
            } else {
              _viewportWidth = newWidth;
              _viewportHeight = newHeight;
            }

            final builderKey = ValueKey(
              '${_playlistController.isPlaylistMode}_'
              '${_playlistController.selectedFolder}_'
              '${_playlistController.isShuffled}_'
              '${_scrollMode}_'
              '${_viewportWidth}_$_viewportHeight',
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
                  padding: _geometry.continuousListPadding(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  ),
                  itemCount: _playlistController.playlist.length,
                  itemBuilder: (context, index) {
                    final itemHeight = _geometry.itemHeight(
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

                return InteractiveViewer(
                  transformationController: _continuousTransformationController,
                  minScale: 1.0,
                  maxScale: MediaViewerConstants.maxImageZoom,
                  clipBehavior: Clip.none,
                  panEnabled: true,
                  onInteractionStart: (details) {
                    if (details.pointerCount >= 2) {
                      _onZoomInteractionChanged(false);
                    }
                  },
                  onInteractionUpdate: (details) {
                    final s = _continuousTransformationController.value
                        .getMaxScaleOnAxis();
                    if (s != _continuousScale) {
                      setState(() => _continuousScale = s);
                    }
                  },
                  onInteractionEnd: (details) {
                    final s = _continuousTransformationController.value
                        .getMaxScaleOnAxis();
                    if (s <= 1.01 && _continuousScale != 1.0) {
                      setState(() => _continuousScale = 1.0);
                    }
                    _onZoomInteractionChanged(true);
                  },
                  child: listWidget,
                );
              }

              return PageView.builder(
                key: builderKey,
                controller: _pageController,
                scrollDirection: _scrollMode.axis,
                physics: physics,
                itemCount: _playlistController.playlist.length,
                onPageChanged: (index) {
                  if (_playlistController.currentIndex != index) {
                    _playlistController.updateIndex(index);
                    unawaited(_activateCurrentMedia());
                  }
                  _scheduleSurroundingPrefetch();
                },
                itemBuilder: (context, index) {
                  return _buildMediaItem(index);
                },
              );
            }

            return Stack(
              children: [
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handleTouchPointerDown,
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
                                final offset = _listScrollController.offset;
                                final newIndex = _geometry.indexForOffset(
                                  offset,
                                  _viewportWidth,
                                  _viewportHeight,
                                );
                                if (_playlistController.currentIndex !=
                                    newIndex) {
                                  _playlistController.updateIndex(newIndex);
                                  unawaited(_activateCurrentMedia());
                                }
                              }
                            } else if (notification is ScrollEndNotification) {
                              _onScrollEnd();
                            }
                          }
                          return false;
                        },
                        child: buildMainScrollView(physics),
                      );
                    },
                  ),
                ),
                // Fullscreen scrub preview: above the media, below the
                // chrome, so the seekbar stays visible while dragging.
                // Not built at all in mini-box mode.
                if (mediaViewerConfig.scrubPreviewStyle ==
                    ScrubPreviewStyle.fullscreen)
                  Positioned.fill(
                    child: VideoScrubFullscreenLayer(
                      previewHost: _scrubPreviewHost,
                      progress: _videoProgressNotifier,
                      rotationQuarterTurns:
                          _rotations[_playlistController.currentFile] ?? 0,
                    ),
                  ),
                AnimatedPositioned(
                  duration: MediaViewerConstants.animationDuration,
                  curve: Curves.easeOut,
                  top: _showUI ? 0 : -120,
                  left: 0,
                  right: 0,
                  child: ListenableBuilder(
                    listenable: _playlistController,
                    builder: (context, _) => MediaViewerTopBar(
                      playlistController: _playlistController,
                      currentFileName: _playlistController.currentFile,
                      totalCount: _playlistController.playlist.length,
                      toolbarConfig: mediaViewerConfig,
                      currentTransitionEffect: _transitionEffect,
                      onTransitionEffectChanged: (newEffect) async {
                        _sessionController.setTransitionEffect(newEffect);
                        final toolbarService = ref.read(
                          fileManagerToolbarServiceProvider,
                        );
                        final config = await toolbarService.load();
                        await toolbarService.save(
                          config.copyWith(playlistTransitionEffect: newEffect),
                        );
                      },
                      currentScrollMode: _scrollMode,
                      onScrollModeChanged: (newMode) async {
                        _sessionController.setScrollMode(newMode);
                        final appSettingsService = ref.read(
                          appSettingsServiceProvider,
                        );
                        final appSettings = await appSettingsService
                            .loadSettings();
                        await appSettingsService.saveSettings(
                          appSettings.copyWith(playlistScrollMode: newMode),
                        );
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _scrollToCurrentIndex(animate: false);
                        });
                      },
                      isMuted: _isMuted,
                      onExecuteAction: _executeMediaAction,
                      onCustomizeControls: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const MediaViewerToolbarSettingsScreen(),
                          ),
                        );
                      },
                      isBookmark: _isCurrentFileBookmark,
                      onPlaylistChanged: _onPlaylistChanged,
                      onMenuOpened: _menuOpened,
                      onMenuClosed: _menuClosed,
                      isImage: MediaViewerConstants.isImage(_playlistController.currentFile),
                      isAudio: MediaViewerConstants.isAudio(_playlistController.currentFile),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: MediaViewerConstants.animationDuration,
                  curve: Curves.easeOut,
                  left: 0,
                  right: 0,
                  bottom: _showUI ? 0 : -200,
                  child: ListenableBuilder(
                    listenable: _playlistController,
                    builder: (context, _) {
                      final isImg = MediaViewerConstants.isImage(
                        _playlistController.currentFile,
                      );
                      return MediaViewerBottomControls(
                        playlistController: _playlistController,
                        playbackManager: _playbackManager,
                        videoProgressNotifier: _videoProgressNotifier,
                        scrubPreviewHost: _scrubPreviewHost,
                        toolbarConfig: mediaViewerConfig,
                        isImage: isImg,
                        isAudio: MediaViewerConstants.isAudio(_playlistController.currentFile),
                        showUI: _showUI,
                        isPlaylistMode: _playlistController.isPlaylistMode,
                        autoAdvance: _autoAdvance,
                        slideshowDelaySeconds: _slideshowDelaySeconds,
                        isMuted: _isMuted,
                        videoPlaybackMode: _videoPlaybackMode,
                        onExecuteAction: _executeMediaAction,
                        onStartHideTimer: _startHideTimer,
                        onShowUIChanged: _setUIVisibility,
                        isCarouselVisible: _isCarouselVisible,
                        onMenuOpened: _menuOpened,
                        onMenuClosed: _menuClosed,
                      );
                    },
                  ),
                ),
             if (_enableCarousel && _isCarouselVisible && _showUI)
                  AnimatedPositioned(
                    duration: MediaViewerConstants.animationDuration,
                    curve: Curves.easeOut,
                    left: 0,
                    right: 0,
                    bottom: (_isCarouselVisible && _showUI)
                        ? ((MediaQuery.paddingOf(context).bottom > 0
                                ? MediaQuery.paddingOf(context).bottom
                                : 16.0) +
                            12.0)
                        : -(PlaylistCarouselOverlay.height + 60),
                    child: PlaylistCarouselOverlay(
                      container: widget.container,
                      playlist: _playlistController.playlist,
                      currentIndex: _playlistController.currentIndex,
                      thumbnailQuality: widget.thumbnailQuality,
                      thumbnailCacheMode: widget.thumbnailCacheMode,
                      onSelect: _selectFromCarousel,
                      onClose: _toggleCarousel,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}