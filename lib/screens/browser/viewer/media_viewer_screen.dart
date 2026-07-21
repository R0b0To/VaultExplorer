import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '/../../models/mounted_container.dart';
import '/../../models/thumbnail_cache_mode.dart';
import '/../../models/thumbnail_quality.dart';
import '/../../services/vaultexplorer_api.dart';
import '../../../widgets/common_widgets.dart';
import 'media_viewer_constants.dart';
import 'playlist_controller.dart';
import 'video_playback_manager.dart';
import 'widgets/image_page_item.dart';
import 'widgets/media_player_widget.dart';
import 'widgets/media_viewer_top_bar.dart';
import 'widgets/media_viewer_bottom_controls.dart';
import 'widgets/advanced_settings_sheet.dart';
import 'widgets/playlist_carousel_overlay.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
    this.thumbnailQuality = ThumbnailQuality.medium,
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
  int _activeMenuCount = 0;
  bool _isCarouselVisible = false;

  late bool _wasEmpty;

  Timer? _slideshowTimer;
  Timer? _hideTimer;

  final bool _autoPlay = true;
  bool _autoAdvance = false;
  int _slideshowDelaySeconds = 4;
  VideoPlaybackMode _videoPlaybackMode = VideoPlaybackMode.playOnce;
  double _playbackSpeed = 1.0;
  bool _subtitlesEnabled = true;
  final int _doubleTapSkipSeconds = 5;
  BoxFit _imageFit = BoxFit.contain;
  bool _isMuted = false;
  bool _isSwiping = false;

  final Map<String, Uint8List> _prefetchedImages = {};
  final Set<String> _prefetchingActive = {};
  final Map<String, int> _rotations = {};
  
  final Map<String, GlobalKey> _mediaKeys = {};

  VideoPlayerController? _lastListenedController;
  bool _wakelockEnabled = false;

  int _transitionToken = 0;
  bool _transitionInProgress = false;

  @override
  void initState() {
    super.initState();
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSlideshowTimerIfNeeded();
      _prefetchSurroundingItems();
    });
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
    final bytes = _prefetchedImages.remove(fileName);
    if (bytes != null) {
      _prefetchedImages[fileName] = bytes;
    }
    return bytes;
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
      _videoProgressNotifier.value = const VideoPlaybackProgress();
      return;
    }

    _videoProgressNotifier.value = const VideoPlaybackProgress();
    _playbackManager.pauseAllExcept(controller);
    controller.addListener(_onControllerTickUpdate);
  }

  void _onControllerTickUpdate() {
    final controller = _playbackManager.activeController;
    if (controller == null || controller.value.hasError) return;

    final isInitialized = controller.value.isInitialized;
    final progress = _videoProgressNotifier.value;

    if (isInitialized &&
        _videoPlaybackMode == VideoPlaybackMode.loop &&
        progress.duration > Duration.zero &&
        progress.position >= progress.duration) {
      _manualLoop(controller);
    } else if (isInitialized &&
        _videoPlaybackMode != VideoPlaybackMode.loop &&
        progress.duration > Duration.zero &&
        progress.position >= progress.duration) {
      if (_videoPlaybackMode == VideoPlaybackMode.playAndAdvance) {
        if (!_transitionInProgress) {
          _navigateToNext();
        }
      }
    }
  }

  Future<void> _manualLoop(VideoPlayerController controller) async {
    try {
      await controller.pause();
      await controller.seekTo(Duration.zero);
      await controller.play();
    } catch (e) {
      debugPrint('Manual loop error execution: $e');
    }
  }

  void _prefetchSurroundingItems() {
    final index = _playlistController.currentIndex;
    final playlist = _playlistController.playlist;
    if (playlist.isEmpty) return;

    final currentFile = _playlistController.currentFile;
    if (MediaViewerConstants.isVideo(currentFile) ||
        MediaViewerConstants.isAudio(currentFile)) {
      return;
    }

    final next = index + 1;
    final prev = index - 1;
    if (next < playlist.length) _prefetchThumbnail(playlist[next]);
    if (prev >= 0) _prefetchThumbnail(playlist[prev]);
  }

  Future<void> _prefetchThumbnail(String fileName) async {
    if (!MediaViewerConstants.isImage(fileName)) return;
    if (_prefetchedImages.containsKey(fileName) ||
        _prefetchingActive.contains(fileName)) {
      return;
    }

    _prefetchingActive.add(fileName);
    try {
      final thumbBytes = await vaultExplorerApi.getImageThumbnail(
        widget.container,
        fileName,
        targetSize: MediaViewerConstants.thumbnailTargetSize,
        quality: widget.thumbnailQuality.jpegQuality,
      );
      if (thumbBytes != null && thumbBytes.isNotEmpty && mounted) {
        setState(() {
          _prefetchedImages[fileName] = thumbBytes;
          if (_prefetchedImages.length >
              MediaViewerConstants.maxPrefetchCacheSize) {
            _prefetchedImages.remove(_prefetchedImages.keys.first);
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to prefetch image content: $e');
    } finally {
      _prefetchingActive.remove(fileName);
    }
  }

  Future<void> _transitionTo(int index, {bool animate = true}) async {
    if (_transitionInProgress) return;
    if (index < 0 || index >= _playlistController.playlist.length) return;
    if (index == _playlistController.currentIndex && _pageController.hasClients && _pageController.page?.round() == index) return;

    _transitionInProgress = true;
    final token = ++_transitionToken;
    try {
      _cancelSlideshowTimer();
      _startHideTimer();

      _playlistController.updateIndex(index);
      _prefetchSurroundingItems();

      if (_pageController.hasClients) {
        if (animate) {
          await _pageController.animateToPage(
            index,
            duration: MediaViewerConstants.pageTransitionDuration,
            curve: Curves.easeInOut,
          );
        } else {
          _pageController.jumpToPage(index);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _transitionToken == token) {
              _onScrollEnd();
            }
          });
        }
      }
    } finally {
      if (_transitionToken == token) {
        _transitionInProgress = false;
      }
    }
  }

  void _navigateToNext() {
    if (_transitionInProgress) return;
    final index = _playlistController.currentIndex;
    if (index < _playlistController.playlist.length - 1) {
      HapticFeedback.lightImpact();
      _transitionTo(index + 1, animate: true);
    }
  }

  void _navigateToPrev() {
    if (_transitionInProgress) return;
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
    final currentFile = _playlistController.currentFile;
    _playbackManager.handlePageChange(currentFile);

    if (MediaViewerConstants.isImage(currentFile)) {
      _startSlideshowTimerIfNeeded();
    } else {
      if (_autoPlay) {
        _playbackManager.activeController?.play();
      }
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
        title: const Text('Delete file?'),
        content: const Text('This action is permanent and cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('Delete'),
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
      _prefetchedImages.remove(fileToDelete);
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
          message: 'File deleted successfully',
          tone: AppBannerTone.success,
        );
      }
    } else if (mounted) {
      showAppSnackBar(
        context,
        message: 'Failed to delete file',
        tone: AppBannerTone.error,
      );
    }
  }

  void _handleMediaError(String fileName) {
    if (fileName != _playlistController.currentFile) return;
    
    Future.delayed(MediaViewerConstants.brokenMediaSkipDelay, () {
      if (!mounted) return;
      if (fileName != _playlistController.currentFile) return;
      
      if (_playlistController.currentIndex < _playlistController.playlist.length - 1) {
        _transitionTo(_playlistController.currentIndex + 1, animate: true);
      }
    });
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
            _playbackManager.activeController?.setPlaybackSpeed(speed);
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

  void _updateWakelock(bool enable) {
    if (_wakelockEnabled != enable) {
      _wakelockEnabled = enable;
      WakelockPlus.toggle(enable: enable);
    }
  }

  @override
  void dispose() {
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
    _updateWakelock(false);
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
                    if (notification is ScrollStartNotification) {
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
                    if (!_transitionInProgress) {
                      _playlistController.updateIndex(index);
                      _prefetchSurroundingItems();
                    }
                  },
                  itemBuilder: (context, index) {
                    final volId = widget.container.volId;
                    final escapedPath = Uri.encodeComponent(
                      _playlistController.playlist[index],
                    );
                    final contentUriString =
                        'content://com.aeidolon.vaultexplorer.documents/document/$volId%3Afile%3A$escapedPath';
                    final fileName = _playlistController.playlist[index];
                    final prefetchedBytes = _prefetchedBytesFor(fileName);

                    final isImg = MediaViewerConstants.isImage(fileName);
                    final isAudio = MediaViewerConstants.isAudio(fileName);

                    return Container(
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
                          : MediaPlayerWidget(
                              key: _getMediaKey(fileName),
                              container: widget.container,
                              fileName: fileName,
                              contentUriString: contentUriString,
                              showUI: _showUI,
                              onToggleUI: _setUIVisibility,
                              skipSeconds: _doubleTapSkipSeconds,
                              autoPlay: false,
                              isAudio: isAudio,
                              subtitlesEnabled: _subtitlesEnabled,
                              rotationQuarterTurns: _rotations[fileName] ?? 0,
                              progressNotifier: _videoProgressNotifier,
                              isCurrent: fileName == _playlistController.currentFile,
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
                              onVideoControllerInitialized: (controller, onEvicted) {
                                _playbackManager.registerController(
                                  fileName: fileName,
                                  controller: controller,
                                  currentFocus: fileName == _playlistController.currentFile,
                                  playlist: _playlistController.playlist,
                                  currentIndex: _playlistController.currentIndex,
                                  onEvicted: onEvicted,
                                );
                                if (fileName == _playlistController.currentFile &&
                                    !_isSwiping &&
                                    _autoPlay) {
                                  controller.play();
                                }
                              },
                              onVideoControllerDisposed: () {
                                _playbackManager.handleDisposed(fileName);
                              },
                              onError: () => _handleMediaError(fileName),
                            ),
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
                        setState(() {
                          if (controller.value.isPlaying) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                        });
                      }
                    }
                  },
                  onPlaybackModeChanged: _updatePlaybackMode,
                  onToggleMute: () {
                    HapticFeedback.lightImpact();
                    _startHideTimer(); 
                    setState(() => _isMuted = !_isMuted);
                    _playbackManager.activeController?.setVolume(_isMuted ? 0.0 : 1.0);
                  },
                  onAdvancedSettingsPressed: () => _showAdvancedSettings(context, isImg),
                  onStartHideTimer: _startHideTimer,
                  onShowUIChanged: _setUIVisibility,
                  isCarouselVisible: _isCarouselVisible,
                  onToggleCarousel: _playlistController.isPlaylistMode ? _toggleCarousel : null,
                );
              },
            ),
          ),

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