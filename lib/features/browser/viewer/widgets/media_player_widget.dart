import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';
import '../caption_track.dart';
import '../native_video_controller.dart';

class VideoPlaybackProgress {
  final Duration position;
  final Duration duration;
  final double sliderValue;
  final bool isDragging;
  const VideoPlaybackProgress({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.sliderValue = 0.0,
    this.isDragging = false,
  });
  VideoPlaybackProgress copyWith({
    Duration? position,
    Duration? duration,
    double? sliderValue,
    bool? isDragging,
  }) {
    final currentDragging = isDragging ?? this.isDragging;
    final currentDuration = duration ?? this.duration;
    final currentPosition = position ?? this.position;
    double computedSlider = 0.0;
    if (currentDragging) {
      computedSlider = sliderValue ?? this.sliderValue;
    } else if (currentDuration.inMilliseconds > 0) {
      computedSlider =
          currentPosition.inMilliseconds / currentDuration.inMilliseconds;
    }
    return VideoPlaybackProgress(
      position: currentPosition,
      duration: currentDuration,
      sliderValue: computedSlider,
      isDragging: currentDragging,
    );
  }
}

class MediaPlayerWidget extends StatefulWidget {
  final MountedContainer container;
  final String fileName;
  final String contentUriString;
  final bool showUI;
  final ValueChanged<bool> onToggleUI;
  final ValueChanged<bool> onZoomChanged;
  final int skipSeconds;
  final bool isAudio;
  final bool subtitlesEnabled;
  final double playbackSpeed;
  final int rotationQuarterTurns;
  final ValueChanged<bool> onSubtitlesAvailableChanged;
  final ValueNotifier<VideoPlaybackProgress> progressNotifier;
  final void Function(int width, int height)? onSizeKnown;
  final VoidCallback? onError;
  final VideoPlaybackManager playbackManager;
  final Uint8List? posterBytes;

  const MediaPlayerWidget({
    super.key,
    required this.container,
    required this.fileName,
    required this.contentUriString,
    required this.showUI,
    required this.onToggleUI,
    required this.onZoomChanged,
    required this.skipSeconds,
    required this.isAudio,
    required this.subtitlesEnabled,
    required this.playbackSpeed,
    required this.rotationQuarterTurns,
    required this.onSubtitlesAvailableChanged,
    required this.progressNotifier,
    required this.playbackManager,
    this.onSizeKnown,
    this.posterBytes,
    this.onError,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> {
  NativeVideoController? _boundController;
  bool _isActive = false;
  bool _initialized = false;
  String? _playerError;
  CaptionTrack? _captionFile;
  bool _isSeeking = false;
  bool _showLeftIndicator = false;
  bool _showRightIndicator = false;
  bool _isSpeedHeld = false;
  final GlobalKey _interactiveViewerKey = GlobalKey();
  Timer? _indicatorTimer;
  int _captionsToken = 0;
  final TransformationController _videoTransformationController =
      TransformationController();
  static const double _minZoomScale = 1.0;
  static const double _maxZoomScale = 4.0;
  double _videoScale = _minZoomScale;
  TapDownDetails? _videoDoubleTapDetails;
  Size _lastKnownVideoSize = Size.zero;
  double? _knownAspectRatio;
  Uint8List? _localPosterBytes;

  @override
  void initState() {
    super.initState();
    _localPosterBytes = widget.posterBytes ??
        ThumbnailCacheService.getFromMemory(
          widget.container,
          widget.fileName,
        );
    widget.playbackManager.activeControllerNotifier.addListener(_onSharedControllerChanged);
    widget.playbackManager.currentFileNotifier.addListener(_onCurrentFileChanged);
    _knownAspectRatio =
        MediaAspectRatioCache.get(widget.container, widget.fileName);
    _syncBoundController();
  }

  @override
  void didUpdateWidget(covariant MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileName != widget.fileName) {
      _localPosterBytes = widget.posterBytes ??
          ThumbnailCacheService.getFromMemory(
            widget.container,
            widget.fileName,
          );
      _knownAspectRatio =
          MediaAspectRatioCache.get(widget.container, widget.fileName);
    }
    if (_boundController != null && oldWidget.playbackSpeed != widget.playbackSpeed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _boundController?.setPlaybackSpeed(widget.playbackSpeed);
      });
    }
    _syncBoundController();
  }

  void _onSharedControllerChanged() => _syncBoundController();
  void _onCurrentFileChanged() => _syncBoundController();

  void _syncBoundController() {
    final shouldBeActive = widget.playbackManager.currentFileName == widget.fileName;
    final target = widget.playbackManager.getControllerFor(widget.fileName) ??
        (shouldBeActive ? widget.playbackManager.activeController : null);
    if (shouldBeActive == _isActive && identical(target, _boundController)) return;
    final becameActive = shouldBeActive && !_isActive;
    final becameInactive = !shouldBeActive && _isActive;
    _boundController?.removeListener(_onControllerTick);
    _boundController = target;
    target?.addListener(_onControllerTick);
    final nowInitialized = target?.value.isInitialized ?? false;
    _isActive = shouldBeActive;
    _initialized = nowInitialized;
    _playerError = null;
    if (target != null && target.value.size != Size.zero) {
      _lastKnownVideoSize = target.value.size;
    }
    if (becameInactive) {
      _videoScale = _minZoomScale;
      _videoTransformationController.value = Matrix4.identity();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    _onControllerTick();
    if (becameActive) {
      _loadCaptionsForThisFile();
    } else if (becameInactive) {
      _captionsToken++;
      _captionFile = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onZoomChanged(true);
      });
    }
  }

  Future<void> _loadCaptionsForThisFile() async {
    final token = ++_captionsToken;
    final captionFile = await _loadCaptions(widget.fileName);
    if (token != _captionsToken || !mounted) return;
    setState(() => _captionFile = captionFile);
  }

  void _onControllerTick() {
    if (!mounted) return;
    final controller = _boundController;
    if (controller == null) return;
    if (controller.value.hasError) {
      if (_playerError == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _playerError == null) {
            setState(() {
              _playerError = controller.value.errorDescription.isNotEmpty
                  ? controller.value.errorDescription
                  : 'Media stream initialization failed';
            });
            widget.onError?.call();
          }
        });
      }
      return;
    }
    if (!_initialized && controller.value.isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_initialized) {
          setState(() => _initialized = true);
        }
      });
    }
    final newSize = controller.value.size;
    if (newSize.width > 0 && newSize.height > 0 && newSize != _lastKnownVideoSize) {
      _lastKnownVideoSize = newSize;
      MediaAspectRatioCache.put(
        widget.container,
        widget.fileName,
        newSize.width.round(),
        newSize.height.round(),
      );
      widget.onSizeKnown?.call(newSize.width.round(), newSize.height.round());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    if (!_isActive) return;
    final newProgress = widget.progressNotifier.value.copyWith(
      position: controller.value.position,
      duration: controller.value.duration,
    );
    if (widget.progressNotifier.value.position != newProgress.position ||
        widget.progressNotifier.value.duration != newProgress.duration) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isActive) {
          widget.progressNotifier.value = newProgress;
        }
      });
    }
  }

  Future<CaptionTrack?> _loadCaptions(String videoPath) async {
    final dotIndex = videoPath.lastIndexOf('.');
    if (dotIndex == -1) return null;
    final basePath = videoPath.substring(0, dotIndex);
    for (final ext in ['srt', 'vtt']) {
      final subPath = '$basePath.$ext';
      try {
        final size = await vaultExplorerApi.getFileSize(
          widget.container,
          subPath,
        );
        if (size > 0) {
          final data = await vaultExplorerApi.readFileChunk(
            widget.container,
            subPath,
            0,
            size,
          );
          if (data != null && data.isNotEmpty) {
            final text = utf8.decode(data, allowMalformed: true);
            widget.onSubtitlesAvailableChanged(true);
            return ext == 'srt'
                ? CaptionTrack.subRip(text)
                : CaptionTrack.webVtt(text);
          }
        }
      } catch (_) {}
    }
    widget.onSubtitlesAvailableChanged(false);
    return null;
  }

  String _captionTextAt(Duration position) {
    final file = _captionFile;
    if (file == null) return '';
    for (final caption in file.captions) {
      if (position >= caption.start && position <= caption.end) {
        return caption.text;
      }
    }
    return '';
  }

  @override
  void dispose() {
    _indicatorTimer?.cancel();
    _boundController?.removeListener(_onControllerTick);
    widget.playbackManager.activeControllerNotifier.removeListener(_onSharedControllerChanged);
    widget.playbackManager.currentFileNotifier.removeListener(_onCurrentFileChanged);
    _videoTransformationController.dispose();
    super.dispose();
  }

  void _onSpeedHoldStart(LongPressStartDetails _) {
    final controller = _boundController;
    if (controller == null) return;
    HapticFeedback.heavyImpact();
    controller.setPlaybackSpeed(2.0);
    setState(() => _isSpeedHeld = true);
  }

  void _onSpeedHoldEnd(LongPressEndDetails _) {
    final controller = _boundController;
    if (controller == null) return;
    controller.setPlaybackSpeed(widget.playbackSpeed);
    setState(() => _isSpeedHeld = false);
  }

  Matrix4 _calculateZoomMatrix({required Offset localPosition, required double scale}) {
    final x = -localPosition.dx * (scale - 1.0);
    final y = -localPosition.dy * (scale - 1.0);
    return Matrix4.identity()
      ..translate(x, y, 0.0)
      ..scale(scale, scale, 1.0);
  }

  void _handleVideoDoubleTap() {
    if (widget.isAudio) return;
    final doubleTapDetails = _videoDoubleTapDetails;
    if (doubleTapDetails == null) return;
    final context = _interactiveViewerKey.currentContext;
    if (context == null || !context.mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final double targetScale;
    final Matrix4 targetMatrix;
    final bool zoomIn = _videoScale == _minZoomScale;
    if (zoomIn) {
      targetScale = _maxZoomScale;
      if (box.hasSize) {
        final position = box.globalToLocal(doubleTapDetails.globalPosition);
        if (position.isFinite) {
          targetMatrix = _calculateZoomMatrix(
            localPosition: position,
            scale: targetScale,
          );
        } else {
          targetMatrix = Matrix4.identity()..scale(targetScale, targetScale, 1.0);
        }
      } else {
        targetMatrix = Matrix4.identity()..scale(targetScale, targetScale, 1.0);
      }
    } else {
      targetScale = _minZoomScale;
      targetMatrix = Matrix4.identity();
    }
    setState(() {
      _videoScale = targetScale;
      _videoTransformationController.value = targetMatrix;
      widget.onZoomChanged(!zoomIn);
    });
  }

  Future<void> _skip({required bool backwards}) async {
    final controller = _boundController;
    if (controller == null || _isSeeking) return;
    _isSeeking = true;
    HapticFeedback.lightImpact();
    final currentPos = controller.value.position;
    final duration = controller.value.duration;
    final targetPos = backwards
        ? currentPos - Duration(seconds: widget.skipSeconds)
        : currentPos + Duration(seconds: widget.skipSeconds);
    final clampedPos = targetPos < Duration.zero
        ? Duration.zero
        : (targetPos > duration ? duration : targetPos);
    setState(() {
      if (backwards) {
        _showLeftIndicator = true;
      } else {
        _showRightIndicator = true;
      }
    });
    await controller.seekTo(clampedPos);
    if (!mounted) return;
    _isSeeking = false;
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(MediaViewerConstants.doubleTapIndicatorDelay, () {
      if (mounted) {
        setState(() {
          _showLeftIndicator = false;
          _showRightIndicator = false;
        });
      }
    });
  }

  Widget _buildPoster(ColorScheme cs, {required bool isLoading}) {
    final poster = _localPosterBytes ?? widget.posterBytes;
    final posterCacheWidth =
        (MediaQuery.of(context).size.width * MediaQuery.of(context).devicePixelRatio)
            .round()
            .clamp(1, 1 << 20);
    final isRotated = widget.rotationQuarterTurns % 2 != 0;
    final knownRatio = _knownAspectRatio;
    final effectiveKnownRatio = (knownRatio != null && isRotated)
        ? 1.0 / knownRatio
        : knownRatio;
    Widget? posterContent;
    if (poster != null && poster.isNotEmpty) {
      if (widget.isAudio) {
        posterContent = Center(
          child: AspectRatio(
            aspectRatio: 0.8,
            child: RotatedBox(
              quarterTurns: widget.rotationQuarterTurns,
              child: Image.memory(poster, fit: BoxFit.cover, cacheWidth: posterCacheWidth),
            ),
          ),
        );
      } else if (effectiveKnownRatio != null) {
        posterContent = Center(
          child: AspectRatio(
            aspectRatio: effectiveKnownRatio,
            child: RotatedBox(
              quarterTurns: widget.rotationQuarterTurns,
              child: Image.memory(poster, fit: BoxFit.cover, cacheWidth: posterCacheWidth),
            ),
          ),
        );
      } else {
        posterContent = RotatedBox(
          quarterTurns: widget.rotationQuarterTurns,
          child: Image.memory(
            poster,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: posterCacheWidth,
          ),
        );
      }
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        if (posterContent != null)
          posterContent
        else if (widget.isAudio)
          Center(child: _buildAudioCenterVisual(cs, isPlaying: false)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_playerError != null) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.errorContainer.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.error_outline_rounded, color: cs.error, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                _playerError!,
                style: TextStyle(color: cs.onErrorContainer, fontSize: 13, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    final controller = _boundController;
    final bool isVideoReady = controller != null &&
        _initialized &&
        (widget.isAudio || (controller.value.size.width > 0 && controller.value.size.height > 0));
    final isRotated = widget.rotationQuarterTurns % 2 != 0;
    final double computedAspectRatio = widget.isAudio
        ? 0.8
        : (isVideoReady
            ? (isRotated ? 1.0 / controller!.value.aspectRatio : controller!.value.aspectRatio)
            : ((_knownAspectRatio != null && isRotated)
                ? 1.0 / _knownAspectRatio!
                : (_knownAspectRatio ?? 16 / 9)));
    Widget corePlayerWidget = Center(
      child: AspectRatio(
        aspectRatio: computedAspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _buildPoster(cs, isLoading: _isActive),
            if (!widget.isAudio && controller != null && isVideoReady)
              RotatedBox(
                quarterTurns: widget.rotationQuarterTurns,
                child: NativeVideoPlayerView(controller: controller),
              ),
            if (widget.isAudio && controller != null && isVideoReady)
              _buildAudioCenterVisual(cs, isPlaying: controller.value.isPlaying)
            else if (!widget.isAudio && widget.subtitlesEnabled)
              Positioned(
                bottom: widget.showUI ? 130 : 25,
                left: 20,
                right: 20,
                child: ValueListenableBuilder<VideoPlaybackProgress>(
                  valueListenable: widget.progressNotifier,
                  builder: (context, progress, child) {
                    return ClosedCaptionText(
                      text: _captionTextAt(progress.position),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            blurRadius: 4,
                            color: Colors.black,
                            offset: Offset(1, 1),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => widget.onToggleUI(!widget.showUI),
                    onDoubleTapDown: (d) => _videoDoubleTapDetails = d,
                    onDoubleTap: () {
                      if (widget.isAudio) return;
                      final width = constraints.maxWidth;
                      final dx = _videoDoubleTapDetails?.localPosition.dx ?? 0;
                      if (dx < width * 0.3) {
                        _skip(backwards: true);
                      } else if (dx > width * 0.7) {
                        _skip(backwards: false);
                      } else {
                        _handleVideoDoubleTap();
                      }
                    },
                    onLongPressStart: _onSpeedHoldStart,
                    onLongPressEnd: _onSpeedHoldEnd,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (!widget.isAudio) {
      corePlayerWidget = InteractiveViewer(
        key: _interactiveViewerKey,
        transformationController: _videoTransformationController,
        maxScale: MediaViewerConstants.maxVideoZoom,
        minScale: 1.0,
        clipBehavior: Clip.none,
        onInteractionUpdate: (details) {
          final s = _videoTransformationController.value.getMaxScaleOnAxis();
          if (s != _videoScale) {
            setState(() => _videoScale = s);
            widget.onZoomChanged(s <= 1.01);
          }
        },
        onInteractionEnd: (details) {
          final s = _videoTransformationController.value.getMaxScaleOnAxis();
          if (s <= 1.01) widget.onZoomChanged(true);
        },
        child: corePlayerWidget,
      );
    }
    return ClipRect(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          corePlayerWidget,
          if (_showLeftIndicator)
            _buildIndicator(
              Icons.fast_rewind_rounded,
              '-${widget.skipSeconds}s',
              true,
            ),
          if (_showRightIndicator)
            _buildIndicator(
              Icons.fast_forward_rounded,
              '+${widget.skipSeconds}s',
              false,
            ),
          if (_isSpeedHeld)
            Positioned(
              top: 96,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fast_forward_rounded,
                        color: cs.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '2× Speed',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIndicator(IconData icon, String text, bool isLeft) {
    return Positioned(
      left: isLeft ? 40 : null,
      right: isLeft ? null : 40,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            shape: BoxShape.circle,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(height: 2),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioCenterVisual(ColorScheme cs, {required bool isPlaying}) {
    final fileTitle = widget.fileName.split('/').last;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Center(
            child: Icon(Icons.music_note_rounded, size: 56, color: cs.primary),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Text(
            fileTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 24),
        _AudioVisualizer(isPlaying: isPlaying),
      ],
    );
  }
}

class _AudioVisualizer extends StatefulWidget {
  final bool isPlaying;
  const _AudioVisualizer({required this.isPlaying});
  @override
  State<_AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<_AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _heights = [0.2, 0.5, 0.8, 0.4, 0.9, 0.3, 0.7, 0.5, 0.2];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isPlaying) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 50,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_heights.length, (index) {
            double animValue = _controller.value;
            double factor = (index % 3 == 0)
                ? (animValue * 0.8 + 0.2)
                : (index % 3 == 1)
                ? ((1.0 - animValue) * 0.7 + 0.3)
                : (((animValue + 0.5) % 1.0) * 0.6 + 0.4);
            if (!widget.isPlaying) factor = 0.15;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 5,
              height: 40 * factor * _heights[index],
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(100),
              ),
            );
          }),
        ),
      ),
    );
  }
}