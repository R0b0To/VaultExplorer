import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/utils/retry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
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

  const MediaViewerScreen({
    super.key,
    required this.container,
    required this.mediaFiles,
    required this.initialIndex,
    this.startingFolder,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    required this.thumbnailCacheMode,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PlaylistController _playlistController;
  late final VideoPlaybackManager _playbackManager;
  late PageController _pageController;
  final ValueNotifier<ScrollPhysics> _swipePhysicsNotifier =
      ValueNotifier<ScrollPhysics>(const BouncingScrollPhysics());
  final ValueNotifier<VideoPlaybackProgress> _videoProgressNotifier =
      ValueNotifier<VideoPlaybackProgress>(const VideoPlaybackProgress());
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
  int _slideshowDelaySeconds = 4;
  VideoPlaybackMode _videoPlaybackMode = VideoPlaybackMode.playOnce;
  double _playbackSpeed = 1.0;
  bool _subtitlesEnabled = true;
  final int _doubleTapSkipSeconds = 5;
  BoxFit _imageFit = BoxFit.contain;
  PlaylistTransitionEffect _transitionEffect = PlaylistTransitionEffect.slide;
  bool _isMuted = false;
  bool _isSwiping = false;
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
    );
    _wasEmpty = _playlistController.isEmpty;
    _playbackManager = VideoPlaybackManager();
    _pageController = PageController(initialPage: widget.initialIndex);
    _playlistController.addListener(_onPlaylistUpdate);
    _playbackManager.activeControllerNotifier.addListener(
      _onActiveVideoControllerChanged,
    );
    _playbackManager.currentFileNotifier.addListener(
      _onCurrentMediaFileChanged,
    );
    _loadConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
       _activateCurrentMedia();
      _startSlideshowTimerIfNeeded();

      // 2. Wait for ExoPlayer initialization to complete before background prefetching starts
      await PlaybackThrottleController.initGate;
      if (mounted) _prefetchSurroundingItems();
    });
  }

  // Monotonically-increasing token guarding against overlapping
  // _activateCurrentMedia() calls (e.g. if some future caller fires it
  // twice in quick succession before the first call's awaits resolve).
  // Without this, two concurrent calls could both pass VideoPlaybackManager
  // .activate()'s "already active" check on stale state and each spin up
  // their own hardware decoder for the same or different files at once --
  // exactly the kind of overlap this whole fix is meant to prevent.
  int _activateToken = 0;

  void _activateCurrentMedia() {
    if (_playlistController.isEmpty) return;
    final file = _playlistController.currentFile;
    final token = ++_activateToken;

    final isVid = MediaViewerConstants.isVideo(file);
    final isAud = MediaViewerConstants.isAudio(file);

    unawaited(PlaybackThrottleController.setActive(isVid));
    if (!mounted || token != _activateToken) return;

    if (isVid || isAud) {
      PlaybackThrottleController.setInitializing();
      // Call activate asynchronously - Manager internal queue handles safety
      unawaited(_playbackManager.activate(
        fileName: file,
        contentUriString: _contentUriFor(file),
        autoPlay: _autoPlay,
        playbackSpeed: _playbackSpeed,
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
        _transitionEffect = appSettings.playlistTransitionEffect;
      });
      if (config.autoStartPlaylistMode && !_playlistController.isPlaylistMode) {
        await _playlistController.enablePlaylist('Current Folder Only');
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
    if (isInitialized &&
        _videoPlaybackMode == VideoPlaybackMode.playAndAdvance &&
        duration > Duration.zero &&
        position >= duration) {
      _navigateToNext();
    }
  }

  String _contentUriFor(String fileName) {
    final volId = widget.container.volId;
    final escapedPath = Uri.encodeComponent(fileName);
    return 'content://com.aeidolon.vaultexplorer.documents/document/'
        '$volId%3Afile%3A$escapedPath';
  }

void _prefetchSurroundingItems() {
    final index = _playlistController.currentIndex;
    final playlist = _playlistController.playlist;
    if (playlist.isEmpty) return;

    final next = index + 1;
    final prev = index - 1;
    final nextFile = next < playlist.length ? playlist[next] : null;
    final prevFile = prev >= 0 ? playlist[prev] : null;

    // Prefetch Thumbnails
    if (nextFile != null) _prefetchThumbnail(nextFile);
    if (prevFile != null) _prefetchThumbnail(prevFile);

    // Prefetch Full-Res Image if next is an image
    final currentFile = _playlistController.currentFile;
    if (MediaViewerConstants.isImage(currentFile) && nextFile != null) {
      _prefetchFullRes(nextFile);
    }
  }

  Future<void> _prefetchThumbnail(String fileName) async {
  final isImg = MediaViewerConstants.isImage(fileName);
  final isVid = MediaViewerConstants.isVideo(fileName);
  if (!isImg && !isVid) return;

  // NEVER prefetch video thumbnails in the background during playback.
  // Hardware video decoders cannot handle concurrent 4K decoding contexts.
  if (isVid && PlaybackThrottleController.isPlaybackActive.value) {
    return;
  }

  if (ThumbnailCacheService.getFromMemory(
        widget.container,
        fileName,
        widget.thumbnailQuality,
      ) !=
      null) {
    return;
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
      debugPrint('Failed to prefetch thumbnail: $e');
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
    final data = await vaultExplorerApi.getVideoThumbnail(
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
          return idx != -1 && (idx - _playlistController.currentIndex).abs() <= 1;
        },
        priority: TaskPriority.adjacent,
      );
    } catch (e) {
      debugPrint('Failed to prefetch full-resolution image: $e');
    } finally {
      _prefetchingFullRes.remove(fileName);
    }
  }

Future<void> _transitionTo(int index, {bool animate = true}) async {
    if (index < 0 || index >= _playlistController.playlist.length) return;
    final token = ++_transitionToken;
    _cancelSlideshowTimer();
    _startHideTimer();

    // Update index immediately
    _playlistController.updateIndex(index);

    // ACTIVATE NOW: Native teardown & initialization run DURING the 220ms animation
    _activateCurrentMedia();

    _prefetchDebounceTimer?.cancel();
    _prefetchDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _prefetchSurroundingItems();
    });

    if (_pageController.hasClients && _pageController.positions.length == 1) {
      if (animate) {
        await _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _pageController.jumpToPage(index);
      }
    }

    if (mounted && _transitionToken == token) {
      _isSwiping = false;
      final currentFile = _playlistController.currentFile;
      if (MediaViewerConstants.isImage(currentFile)) {
        _startSlideshowTimerIfNeeded();
      }
      if (_showUI) {
        _startHideTimer();
      }
      if (mounted) setState(() {});
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
        if (mounted) _navigateToNext();
      });
    }
  }

  void _onScrollStart() {
    if (!_isSwiping) {
      _isSwiping = true;
      _playbackManager.activeController?.pause();
      _cancelSlideshowTimer();
    }
  }

void _onScrollEnd() {
    _isSwiping = false;
    
    // Fallback check in case page scroll completed without index change
    if (_playbackManager.currentFileNotifier.value != _playlistController.currentFile) {
      _activateCurrentMedia();
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
    if (confirm != true) return;
    final fileToDelete = _playlistController.currentFile;
    bool success = false;
    try {
      success = await vaultExplorerApi.deleteFile(
        widget.container,
        fileToDelete,
      );
    } catch (e) {
      debugPrint('Deletion error operation failed: $e');
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
    // Leave the current item in place and let its error overlay stay on
    // screen so the user can see what failed, rather than automatically
    // skipping to the next file. Auto-skipping here previously triggered
    // a cascading loop: it advanced (and began initializing the next
    // file's decoder) while the failed video's hardware decoder was still
    // being torn down, which on single-decoder-pipeline devices produced
    // another NO_MEMORY failure, which skipped again, and so on.
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
    _playbackManager.activeController?.setLooping(mode == VideoPlaybackMode.loop);
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return MediaDiagnosticsSheet(
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
    _playbackManager.dispose();
    _swipePhysicsNotifier.dispose();
    _videoProgressNotifier.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
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
      body: Stack(
        children: [
          ValueListenableBuilder<ScrollPhysics>(
            valueListenable: _swipePhysicsNotifier,
            builder: (context, physics, child) {
              return NotificationListener<ScrollNotification>(
                onNotification: (ScrollNotification notification) {
                  if (notification.depth == 0) {
                    if (notification is ScrollStartNotification &&
                        notification.dragDetails != null) {
                      _onScrollStart();
                    } else if (notification is ScrollEndNotification) {
                      _onScrollEnd();
                    }
                  }
                  return false;
                },
                child: PageView.builder(
                  key: ValueKey(
                    '${_playlistController.isPlaylistMode}_'
                    '${_playlistController.selectedFolder}_'
                    '${_playlistController.isShuffled}',
                  ),
                  controller: _pageController,
                  physics: physics,
                  itemCount: _playlistController.playlist.length,
                  onPageChanged: (index) {
                  if (_playlistController.currentIndex != index) {
                    _playlistController.updateIndex(index);
                    // Immediately start hardware decoder switch when swipe crosses midpoint
                    _activateCurrentMedia();
                  }

                  _prefetchDebounceTimer?.cancel();
                  _prefetchDebounceTimer = Timer(const Duration(milliseconds: 150), () {
                    if (mounted) _prefetchSurroundingItems();
                  });
                },

                  itemBuilder: (context, index) {
                    final fileName = _playlistController.playlist[index];
                    final contentUriString = _contentUriFor(fileName);
                    final prefetchedBytes = _prefetchedBytesFor(fileName);
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
                                imageFit: _imageFit,
                                rotationQuarterTurns: _rotations[fileName] ?? 0,
                                showUI: _showUI,
                                onToggleUI: _setUIVisibility,
                                onZoomChanged: (allowSwipe) {
                                _swipePhysicsNotifier.value = allowSwipe
                                    ? const BouncingScrollPhysics()
                                    : const NeverScrollableScrollPhysics();
                              },
                              onError: () => _handleMediaError(fileName),
                            )
                          :MediaPlayerWidget(
                              key: _getMediaKey(fileName),
                              container: widget.container,
                              fileName: fileName,
                              contentUriString: contentUriString,
                              playbackManager: _playbackManager,
                              posterBytes: prefetchedBytes,
                              showUI: _showUI,
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
                              onZoomChanged: (allowSwipe) {
                                _swipePhysicsNotifier.value = allowSwipe
                                    ? const BouncingScrollPhysics()
                                    : const NeverScrollableScrollPhysics();
                              },
                              onError: () => _handleMediaError(fileName),
                            ),
                    );

                    return PlaylistTransitionTransformer(
                      pageController: _pageController,
                      index: index,
                      effect: _transitionEffect,
                      child: itemWidget,
                    );
                  },
                ),
              );
            },
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
                  final appSettings = await AppSettingsService.loadSettings();
                  await AppSettingsService.saveSettings(
                    appSettings.copyWith(playlistTransitionEffect: newEffect),
                  );
                },
                onBackPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                },
                onDeletePressed: _deleteCurrentFile,
                onPlaylistChanged: () {
                  _startHideTimer();
                  if (!_playlistController.isPlaylistMode) {
                    if (_isCarouselVisible) _toggleCarousel();
                    if (_autoAdvance) {
                      _updatePlaybackMode(VideoPlaybackMode.playOnce);
                    }
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
                    if (mounted) _onScrollEnd();
                  });
                },
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
      ),
    );
  }
}