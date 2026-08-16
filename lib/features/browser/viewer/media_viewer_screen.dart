import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/utils/retry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/image_page_item.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_player_widget.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_top_bar.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_bottom_controls.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/advanced_settings_sheet.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_diagnostics_sheet.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/playlist_carousel_overlay.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/playlist_transition_transformer.dart';
import 'native_video_controller.dart';

enum VideoPlaybackMode { playOnce, loop, playAndAdvance }

class MediaViewerScreen extends StatefulWidget {
  final MountedContainer container;
  final List<String> mediaFiles;
  final int initialIndex;
  final String? startingFolder;
  final ThumbnailQuality thumbnailQuality;
  final ThumbnailCacheMode thumbnailCacheMode;
  final String? mediaFilter;
  final SortBy sortBy;
  final bool sortAscending;

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
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
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

  // Raw pointer tracking so a second finger touching down immediately locks
  // out swipe-to-next-item, before the gesture arena has a chance to let
  // the PageView/ListView drag recognizer mistake the pinch for a swipe.
  final Set<int> _activeTouchPointers = {};
  bool _multiTouchLock = false;
  // Whether an item's InteractiveViewer currently considers itself zoomed
  // or mid-interaction (reported via onZoomChanged). Kept separate from
  // _multiTouchLock so either source can hold the lock independently.
  bool _zoomInteractionLock = false;

  bool _showUI = false;
  bool _isContainerLocked = false;
  int _activeMenuCount = 0;
  bool _isCarouselVisible = false;
  bool _enableCarousel = true;
  late bool _wasEmpty;

  Timer? _slideshowTimer;
  Timer? _hideTimer;
  Timer? _prefetchDebounceTimer;

  final bool _autoPlay = true;
  bool _autoAdvance = false;
  bool _isAutoAdvancing = false;
  int _slideshowDelaySeconds = 4;
  VideoPlaybackMode _videoPlaybackMode = VideoPlaybackMode.playOnce;
  double _playbackSpeed = 1.0;
  bool _subtitlesEnabled = true;
  final int _doubleTapSkipSeconds = 5;
  BoxFit _imageFit = BoxFit.contain;
  PlaylistTransitionEffect _transitionEffect = PlaylistTransitionEffect.slide;
  PlaylistScrollMode _scrollMode = PlaylistScrollMode.horizontal;
  double _viewportWidth = 0.0;
  double _viewportHeight = 0.0;
  bool _isMuted = false;
  bool _isSwiping = false;
  bool _isProgrammaticScrolling = false;

  final Set<String> _prefetchingFullRes = {};
  final Map<String, int> _rotations = {};
  final Map<String, GlobalKey> _mediaKeys = {};
  NativeVideoController? _lastListenedController;
  bool _wakelockEnabled = false;
  int _transitionToken = 0;

  void _onContainerLockedEvent(int volId) {
    if (volId == widget.container.volId && mounted) {
      setState(() => _isContainerLocked = true);
    }
  }

  @override
  void initState() {
    super.initState();
    VaultExplorerApi.addContainerLockedListener(_onContainerLockedEvent);
    ThumbnailConcurrency.videoLimiter.cancelAll();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    VaultExplorerApi.addUsbContainerDetachedListener(_onContainerDetached);

    _playlistController = PlaylistController(
      container: widget.container,
      initialMediaFiles: widget.mediaFiles,
      initialIndex: widget.initialIndex,
      startingFolder: widget.startingFolder,
      mediaFilter: widget.mediaFilter,
      sortBy: widget.sortBy,
      sortAscending: widget.sortAscending,
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
    final token = ++_activateToken;
    final isVid = MediaViewerConstants.isVideo(file);
    final isAud = MediaViewerConstants.isAudio(file);
    if (isVid || isAud) {
      PlaybackThrottleController.setInitializing();
    }
    await PlaybackThrottleController.setActive(isVid);
    if (!mounted || token != _activateToken) return;
    if (isVid || isAud) {
      unawaited(_playbackManager.activate(
        fileName: file,
        volId: widget.container.volId,
        filePath: file,
        autoPlay: _autoPlay,
        playbackSpeed: _playbackSpeed,
        looping: _videoPlaybackMode == VideoPlaybackMode.loop,
      ));
    } else {
      _playbackManager.pauseActive();
    }
  }

  Future<void> _loadConfig() async {
    final config = await FileManagerToolbarService.instance.load();
    final appSettings = await AppSettingsService.loadSettings();
    if (mounted) {
      setState(() {
        _enableCarousel = config.showMediaCarousel;
        if (!_enableCarousel) {
          _isCarouselVisible = false;
        }
        _transitionEffect = config.playlistTransitionEffect;
        _scrollMode = appSettings.playlistScrollMode;
      });

      if (config.autoStartPlaylistMode && !_playlistController.isPlaylistMode) {
        final targetFile = _playlistController.currentFile;
        await _playlistController.enablePlaylist('Current Folder Only');
        if (mounted) {
          final newIndex = _playlistController.playlist.indexOf(targetFile);
          if (newIndex != -1) {
            _playlistController.updateIndex(newIndex);
          }
          _onPlaylistChanged();
        }
      }
    }
  }

  GlobalKey _getMediaKey(String fileName) {
    final existing = _mediaKeys.remove(fileName);
    if (existing != null) {
      _mediaKeys[fileName] = existing;
      return existing;
    }
    if (_mediaKeys.length >= MediaViewerConstants.maxPrefetchCacheSize * 2) {
      _mediaKeys.remove(_mediaKeys.keys.first);
    }
    return _mediaKeys[fileName] = GlobalKey(debugLabel: fileName);
  }

  Uint8List? _prefetchedBytesFor(String fileName) {
    return ThumbnailCacheService.getFromMemory(
      widget.container,
      fileName,
      widget.thumbnailQuality,
    );
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

  double _getItemHeight(int index, double viewportWidth, double viewportHeight) {
    if (index < 0 || index >= _playlistController.playlist.length) {
      return viewportHeight;
    }
    final fileName = _playlistController.playlist[index];
    final isAudio = MediaViewerConstants.isAudio(fileName);
    if (isAudio) {
      return math.min(320.0, viewportHeight);
    }
    final ratio = MediaAspectRatioCache.get(widget.container, fileName);
    if (ratio != null && ratio > 0 && viewportWidth > 0) {
      final rotation = _rotations[fileName] ?? 0;
      final effectiveRatio = (rotation % 2 != 0) ? 1.0 / ratio : ratio;
      final calculatedHeight = viewportWidth / effectiveRatio;
      return calculatedHeight.clamp(120.0, viewportHeight);
    }
    return (viewportWidth / (16 / 9)).clamp(120.0, viewportHeight);
  }

  EdgeInsets _getContinuousListPadding(double viewportWidth, double viewportHeight) {
    final playlist = _playlistController.playlist;
    if (playlist.isEmpty || viewportHeight <= 0) return EdgeInsets.zero;
    final h0 = _getItemHeight(0, viewportWidth, viewportHeight);
    final topPadding = math.max(0.0, (viewportHeight - h0) / 2.0);
    final hLast = _getItemHeight(playlist.length - 1, viewportWidth, viewportHeight);
    final bottomPadding = math.max(0.0, (viewportHeight - hLast) / 2.0);
    return EdgeInsets.only(top: topPadding, bottom: bottomPadding);
  }

  double _getOffsetForIndex(int targetIndex, double viewportWidth, double viewportHeight) {
    final playlist = _playlistController.playlist;
    if (playlist.isEmpty || viewportHeight <= 0) return 0.0;
    if (targetIndex <= 0) return 0.0;
    if (targetIndex >= playlist.length) targetIndex = playlist.length - 1;

    final padding = _getContinuousListPadding(viewportWidth, viewportHeight);
    double sumPrevHeights = 0.0;
    for (int i = 0; i < targetIndex; i++) {
      sumPrevHeights += _getItemHeight(i, viewportWidth, viewportHeight);
    }
    final currentItemHeight = _getItemHeight(targetIndex, viewportWidth, viewportHeight);
    double idealOffset;
    if (currentItemHeight >= viewportHeight) {
      idealOffset = padding.top + sumPrevHeights;
    } else {
      idealOffset = padding.top + sumPrevHeights - (viewportHeight - currentItemHeight) / 2.0;
    }
    double totalContentHeight = padding.top + sumPrevHeights + currentItemHeight + padding.bottom;
    for (int i = targetIndex + 1; i < playlist.length; i++) {
      totalContentHeight += _getItemHeight(i, viewportWidth, viewportHeight);
    }
    final maxScrollExtent = math.max(0.0, totalContentHeight - viewportHeight);
    return idealOffset.clamp(0.0, maxScrollExtent);
  }

  int _getIndexForOffset(double offset, double viewportWidth, double viewportHeight) {
    final playlist = _playlistController.playlist;
    if (playlist.isEmpty) return 0;
    if (playlist.length == 1) return 0;

    final currentIdx = _playlistController.currentIndex.clamp(0, playlist.length - 1);
    final padding = _getContinuousListPadding(viewportWidth, viewportHeight);
    double sumPrev = 0.0;
    final targetOffsets = <double>[];
    for (int i = 0; i < playlist.length; i++) {
      final h = _getItemHeight(i, viewportWidth, viewportHeight);
      final ideal = (h >= viewportHeight)
          ? padding.top + sumPrev
          : padding.top + sumPrev - (viewportHeight - h) / 2.0;
      targetOffsets.add(ideal);
      sumPrev += h;
    }

    int bestIdx = currentIdx;
    double minDiff = (offset - targetOffsets[currentIdx]).abs();
    for (int i = 0; i < playlist.length; i++) {
      final diff = (offset - targetOffsets[i]).abs();
      if (diff < minDiff - 10.0) {
        minDiff = diff;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  void _scrollToCurrentIndex({bool animate = false}) {
    final index = _playlistController.currentIndex;
    if (_scrollMode.isContinuous) {
      if (_listScrollController.hasClients &&
          _listScrollController.positions.length == 1 &&
          _viewportHeight > 0) {
        final target = _getOffsetForIndex(index, _viewportWidth, _viewportHeight);
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
    _pageController =
        PageController(initialPage: _playlistController.currentIndex);
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
      } catch (_) {}
    }

    final controller = _playbackManager.activeController;
    _lastListenedController = controller;

    if (controller == null) {
      _updateWakelock(false);
      return;
    }

    controller.addListener(_onControllerTickUpdate);
    _updateWakelock(controller.value.isPlaying);
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
      if (position >= duration || (!controller.value.isPlaying && position >= duration - const Duration(milliseconds: 200))) {
        controller.seekTo(Duration.zero);
        controller.play();
        return;
      }
    }

    if (_isAutoAdvancing) return;

    if (_videoPlaybackMode == VideoPlaybackMode.playAndAdvance && position >= duration) {
      _isAutoAdvancing = true;
      try {
        controller.removeListener(_onControllerTickUpdate);
      } catch (_) {}
      _playbackManager.pauseActive();
      _cancelSlideshowTimer();
      _slideshowTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted && _videoPlaybackMode == VideoPlaybackMode.playAndAdvance) {
          _autoAdvanceToNext();
        } else {
          _isAutoAdvancing = false;
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
    final index = _playlistController.currentIndex;
    final playlist = _playlistController.playlist;
    if (playlist.isEmpty) return;

    for (final delta in [1, -1, 2, -2]) {
      final i = index + delta;
      if (i >= 0 && i < playlist.length) {
        final file = playlist[i];
        _prefetchThumbnail(file);
        if (MediaViewerConstants.isImage(file)) {
          _prefetchFullRes(file);
        }
      }
    }
  }

 Future<void> _prefetchThumbnail(String fileName) async {
    final isImg = MediaViewerConstants.isImage(fileName);
    final isVid = MediaViewerConstants.isVideo(fileName);
    if (!isImg && !isVid) return;

    if (ThumbnailCacheService.getFromMemory(
          widget.container,
          fileName,
          widget.thumbnailQuality,
        ) !=
        null) {
      return;
    }

    final mode = widget.thumbnailCacheMode;
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await ThumbnailCacheService.get(
        container: widget.container,
        filePath: fileName,
        mode: mode,
        quality: widget.thumbnailQuality,
      );
      if (cached != null && cached.isNotEmpty) {
        ThumbnailCacheService.putInMemory(
          widget.container,
          fileName,
          cached,
          widget.thumbnailQuality,
        );
        if (mounted) setState(() {});
        return;
      }
    }

    final key = '${widget.container.volId}:'
        '${widget.container.mountedAt.millisecondsSinceEpoch}:$fileName';
    final existing = ThumbnailConcurrency.inFlightThumbnails[key];
    if (existing != null) {
      try {
        await existing;
      } catch (_) {}
      if (mounted) setState(() {});
      return;
    }

    final limiter = isVid
        ? ThumbnailConcurrency.videoLimiter
        : ThumbnailConcurrency.imageLimiter;
    final completer = Completer<void>();
    final future = _gatedFetchThumbnail(fileName, isVid, limiter, completer);
    ThumbnailConcurrency.inFlightThumbnails[key] = future;
    try {
      await future;
      if (mounted) setState(() {});
    } catch (e) {
      // Ignore prefetch errors
    } finally {
      if (ThumbnailConcurrency.inFlightThumbnails[key] == future) {
        ThumbnailConcurrency.inFlightThumbnails.remove(key);
      }
    }
  }

  Future<Uint8List> _gatedFetchThumbnail(
    String fileName,
    bool isVid,
    PriorityTaskQueue limiter,
    Completer<void> completer,
  ) async {
    bool acquired = false;
    try {
      await limiter.acquire(completer, priority: TaskPriority.adjacent);
      acquired = true;
      return await retryWithBackoff<Uint8List>(
        (attempt) => isVid
            ? _fetchVideoThumbnailForPrefetch(fileName)
            : _fetchImageThumbnailForPrefetch(fileName),
      );
    } finally {
      if (acquired) limiter.release(completer);
    }
  }

  Future<Uint8List> _fetchImageThumbnailForPrefetch(String fileName) async {
    final mode = widget.thumbnailCacheMode;
    final quality = widget.thumbnailQuality;
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await ThumbnailCacheService.get(
        container: widget.container,
        filePath: fileName,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final data = await vaultExplorerApi.getImageThumbnail(
      widget.container,
      fileName,
      targetSize: MediaViewerConstants.thumbnailTargetSize,
      quality: quality.jpegQuality,
    );
    final bytes = (data == null || data.isEmpty) ? Uint8List(0) : data;
    if (bytes.isNotEmpty) {
      ThumbnailCacheService.putInMemory(widget.container, fileName, bytes, quality);
      if (mode != ThumbnailCacheMode.disabled) {
        unawaited(ThumbnailCacheService.put(
          container: widget.container,
          filePath: fileName,
          data: bytes,
          mode: mode,
          quality: quality,
        ));
      }
    }
    return bytes;
  }

  Future<Uint8List> _fetchVideoThumbnailForPrefetch(String fileName) async {
    return VideoThumbnailFetcher.fetch(
      widget.container,
      fileName,
      mode: widget.thumbnailCacheMode,
      quality: widget.thumbnailQuality,
      targetSize: MediaViewerConstants.thumbnailTargetSize,
    );
  }

  Future<void> _prefetchFullRes(String fileName) async {
    if (!MediaViewerConstants.isImage(fileName)) return;
    if (FullResImageCache.contains(widget.container, fileName)) return;
    if (_prefetchingFullRes.contains(fileName)) return;

    _prefetchingFullRes.add(fileName);
    final completer = Completer<void>();
    try {
      await FullResImageCache.fetch(
        widget.container,
        fileName,
        completer,
        isStillWanted: () {
          if (!mounted) return false;
          final idx = _playlistController.playlist.indexOf(fileName);
          return idx != -1 && (idx - _playlistController.currentIndex).abs() <= 2;
        },
        priority: TaskPriority.adjacent,
      );
    } catch (e) {
    } finally {
      _prefetchingFullRes.remove(fileName);
    }
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
    unawaited(_activateCurrentMedia());

    _scheduleSurroundingPrefetch();

    if (_scrollMode.isContinuous) {
      if (_listScrollController.hasClients &&
          _listScrollController.positions.length == 1 &&
          _viewportHeight > 0) {
        final target = _getOffsetForIndex(index, _viewportWidth, _viewportHeight);
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
      _isAutoAdvancing = false;
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
      _isAutoAdvancing = false;
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
      _isAutoAdvancing = false;
      _playbackManager.activeController?.pause();
      _cancelSlideshowTimer();
    }
  }

  void _onScrollEnd() {
    _isSwiping = false;
    if (_playbackManager.currentFileNotifier.value != _playlistController.currentFile) {
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
      success = await vaultExplorerApi.deleteFile(
        widget.container,
        fileToDelete,
      );
    } catch (e) {
    }

    if (success && mounted) {
      _mediaKeys.remove(fileToDelete);
      _rotations.remove(fileToDelete);
      _playlistController.removeFile(fileToDelete);
      if (_playlistController.isEmpty) {
        Navigator.pop(context);
        return;
      }
      if (_pageController.hasClients) {
        final oldController = _pageController;
        _pageController = PageController(initialPage: _playlistController.currentIndex);
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
      setState(() => _showUI = show);
      if (show) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

  void _toggleCarousel() {
    HapticFeedback.lightImpact();
    setState(() => _isCarouselVisible = !_isCarouselVisible);
    if (_isCarouselVisible) {
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
    setState(() {
      _videoPlaybackMode = mode;
      _autoAdvance = (mode == VideoPlaybackMode.playAndAdvance);
      if (_autoAdvance) {
        _startSlideshowTimerIfNeeded();
      } else {
        _cancelSlideshowTimer();
      }
    });
    final controller = _playbackManager.activeController;
    controller?.setLooping(mode == VideoPlaybackMode.loop);
  }

  void _showAdvancedSettings(BuildContext context, bool isImage) {
    _menuOpened();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return AdvancedSettingsSheet(
          isPlaylistMode: _playlistController.isPlaylistMode,
          isImage: isImage,
          currentFileName: _playlistController.currentFile,
          initialRotation: _rotations[_playlistController.currentFile] ?? 0,
          initialImageFit: _imageFit,
          initialSlideshowDelaySeconds: _slideshowDelaySeconds,
          initialPlaybackSpeed: _playbackSpeed,
          hasSubtitles: _playbackManager.isSubtitleAvailable(_playlistController.currentFile),
          initialSubtitlesEnabled: _subtitlesEnabled,
          videoController: _playbackManager.activeController,
          onRotationChanged: (rot) {
            _startHideTimer();
            setState(() {
              _rotations[_playlistController.currentFile] = rot;
            });
          },
          onImageFitChanged: (fit) {
            _startHideTimer();
            setState(() {
              _imageFit = fit;
            });
          },
          onSlideshowDelayChanged: (delay) {
            _startHideTimer();
            setState(() {
              _slideshowDelaySeconds = delay;
              if (_autoAdvance) {
                _startSlideshowTimerIfNeeded();
              }
            });
          },
          onPlaybackSpeedChanged: (speed) {
            _startHideTimer();
            setState(() {
              _playbackSpeed = speed;
            });
          },
          onSubtitlesEnabledChanged: (enabled) {
            _startHideTimer();
            setState(() {
              _subtitlesEnabled = enabled;
            });
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
      vaultExplorerApi.setKeepScreenOn(enable);
    }
  }

  @override
  void dispose() {
    VaultExplorerApi.removeContainerLockedListener(_onContainerLockedEvent);
    PlaybackThrottleController.setActive(false);
    VaultExplorerApi.removeUsbContainerDetachedListener(_onContainerDetached);
    _playlistController.removeListener(_onPlaylistUpdate);
    if (_lastListenedController != null) {
      try {
        _lastListenedController!.removeListener(_onControllerTickUpdate);
      } catch (_) {}
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Widget _buildMediaItem(int index) {
    final fileName = _playlistController.playlist[index];
    final contentUriString = _contentUriFor(fileName);
    final prefetchedBytes = _prefetchedBytesFor(fileName);
    if (prefetchedBytes == null) {
      unawaited(_prefetchThumbnail(fileName));
    }
    final isImg = MediaViewerConstants.isImage(fileName);
    final isAudio = MediaViewerConstants.isAudio(fileName);

    final itemWidget = Container(
      color: Colors.black,
      child: isImg
          ? ImagePageItem(
              key: _getMediaKey(fileName),
              fileName: fileName,
              prefetchedBytes: prefetchedBytes,
              container: widget.container,
              imageFit: _scrollMode.isContinuous ? BoxFit.contain : _imageFit,
              rotationQuarterTurns: _rotations[fileName] ?? 0,
              showUI: _showUI,
              enableZoom: !_scrollMode.isContinuous,
              onToggleUI: _setUIVisibility,
              onZoomChanged: _onZoomInteractionChanged,
              onSizeKnown: (w, h) {
                if (mounted) setState(() {});
              },
              onError: () => _handleMediaError(fileName),
            )
          : MediaPlayerWidget(
              key: _getMediaKey(fileName),
              container: widget.container,
              fileName: fileName,
              contentUriString: contentUriString,
              playbackManager: _playbackManager,
              posterBytes: prefetchedBytes,
              thumbnailCacheMode: widget.thumbnailCacheMode,
              showUI: _showUI,
              enableZoom: !_scrollMode.isContinuous,
              onToggleUI: _setUIVisibility,
              skipSeconds: _doubleTapSkipSeconds,
              isAudio: isAudio,
              subtitlesEnabled: _subtitlesEnabled,
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
                if (mounted) setState(() {});
              },
              onZoomChanged: _onZoomInteractionChanged,
              onError: () => _handleMediaError(fileName),
            ),
    );

    if (_scrollMode.isContinuous) {
      return itemWidget;
    }

    return PlaylistTransitionTransformer(
      pageController: _pageController,
      index: index,
      effect: _transitionEffect,
      scrollDirection: _scrollMode.axis,
      child: itemWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isContainerLocked) {
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

    final isCurrentAnImage =
        MediaViewerConstants.isImage(_playlistController.currentFile);
    bool isPlayingState = false;
    if (isCurrentAnImage) {
      isPlayingState = _autoAdvance;
    } else {
      isPlayingState =
          _playbackManager.activeController?.value.isPlaying ?? false;
    }
    _updateWakelock(isPlayingState);

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final newWidth = constraints.maxWidth;
          final newHeight = constraints.maxHeight;
          final bool dimsChanged = (_viewportWidth > 0 && _viewportHeight > 0) &&
              (newWidth != _viewportWidth || newHeight != _viewportHeight);

          if (dimsChanged) {
            _viewportWidth = newWidth;
            _viewportHeight = newHeight;
            if (_scrollMode.isContinuous) {
              final targetOffset = _getOffsetForIndex(
                _playlistController.currentIndex,
                newWidth,
                newHeight,
              );
              final oldController = _listScrollController;
              _listScrollController = ScrollController(initialScrollOffset: targetOffset);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                oldController.dispose();
                if (mounted) {
                  unawaited(_activateCurrentMedia());
                  _onScrollEnd();
                }
              });
            } else {
              final oldPageController = _pageController;
              _pageController = PageController(initialPage: _playlistController.currentIndex);
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
                padding: _getContinuousListPadding(constraints.maxWidth, constraints.maxHeight),
                itemCount: _playlistController.playlist.length,
                itemBuilder: (context, index) {
                  final itemHeight = _getItemHeight(index, constraints.maxWidth, constraints.maxHeight);
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
                  final s = _continuousTransformationController.value.getMaxScaleOnAxis();
                  if (s != _continuousScale) {
                    setState(() => _continuousScale = s);
                  }
                },
                onInteractionEnd: (details) {
                  final s = _continuousTransformationController.value.getMaxScaleOnAxis();
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
                          } else if (notification is ScrollUpdateNotification) {
                            if (_scrollMode.isContinuous &&
                                _viewportHeight > 0 &&
                                _listScrollController.hasClients) {
                              final offset = _listScrollController.offset;
                              final newIndex = _getIndexForOffset(offset, _viewportWidth, _viewportHeight);
                              if (_playlistController.currentIndex != newIndex) {
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
              AnimatedPositioned(
                duration: MediaViewerConstants.animationDuration,
                curve: Curves.easeOut,
                top: _showUI ? 0 : -120,
                left: 0,
                right: 0,
                child: ListenableBuilder(
                  listenable: _playlistController,
                  builder: (context, _) => MediaViewerTopBar(
                    container: widget.container,
                    playlistController: _playlistController,
                    currentFileName: _playlistController.currentFile,
                    totalCount: _playlistController.playlist.length,
                    currentTransitionEffect: _transitionEffect,
                    onTransitionEffectChanged: (newEffect) async {
                      setState(() {
                        _transitionEffect = newEffect;
                      });
                      final config = await FileManagerToolbarService.instance.load();
                      await FileManagerToolbarService.instance.save(
                        config.copyWith(playlistTransitionEffect: newEffect),
                      );
                    },
                    currentScrollMode: _scrollMode,
                    onScrollModeChanged: (newMode) async {
                      setState(() {
                        _scrollMode = newMode;
                      });
                      final appSettings = await AppSettingsService.loadSettings();
                      await AppSettingsService.saveSettings(
                        appSettings.copyWith(playlistScrollMode: newMode),
                      );
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _scrollToCurrentIndex(animate: false);
                      });
                    },
                    onBackPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    onDeletePressed: _deleteCurrentFile,
                    onPlaylistChanged: _onPlaylistChanged,
                    onMenuOpened: _menuOpened,
                    onMenuClosed: _menuClosed,
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
                    final isImg =
                        MediaViewerConstants.isImage(_playlistController.currentFile);
                    return MediaViewerBottomControls(
                      playlistController: _playlistController,
                      playbackManager: _playbackManager,
                      videoProgressNotifier: _videoProgressNotifier,
                      isImage: isImg,
                      showUI: _showUI,
                      isPlaylistMode: _playlistController.isPlaylistMode,
                      autoAdvance: _autoAdvance,
                      slideshowDelaySeconds: _slideshowDelaySeconds,
                      isMuted: _isMuted,
                      videoPlaybackMode: _videoPlaybackMode,
                      onNavigateToPrev: _navigateToPrev,
                      onNavigateToNext: _navigateToNext,
                      onTogglePlayPause: (wasPlaying) {
                        _startHideTimer();
                        if (isImg) {
                          _updatePlaybackMode(
                            wasPlaying ? VideoPlaybackMode.playOnce : VideoPlaybackMode.playAndAdvance,
                          );
                        } else {
                          final controller = _playbackManager.activeController;
                          if (controller != null) {
                            if (controller.value.isPlaying) {
                              controller.pause();
                            } else {
                              controller.play();
                            }
                          }
                        }
                      },
                      onPlaybackModeChanged: _updatePlaybackMode,
                      onToggleMute: () {
                        HapticFeedback.lightImpact();
                        _startHideTimer();
                        setState(() => _isMuted = !_isMuted);
                        _playbackManager.activeController?.setVolume(_isMuted ? 0 : 100);
                      },
                      onAdvancedSettingsPressed: () => _showAdvancedSettings(context, isImg),
                      onDiagnosticsPressed: isImg ? null : () => _showDiagnostics(context),
                      onStartHideTimer: _startHideTimer,
                      onShowUIChanged: _setUIVisibility,
                      isCarouselVisible: _isCarouselVisible,
                      onToggleCarousel: (_enableCarousel && _playlistController.isPlaylistMode) ? _toggleCarousel : null,
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
                      ? 0
                      : -PlaylistCarouselOverlay.height,
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
    );
  }
}