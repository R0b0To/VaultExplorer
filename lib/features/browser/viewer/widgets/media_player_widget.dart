import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart'
show ClosedCaptionFile, SubRipCaptionFile, WebVTTCaptionFile, ClosedCaption;
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/native_vlc_controller.dart';

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
  final bool autoPlay;
  final bool isAudio;
  final bool subtitlesEnabled;
  final double playbackSpeed;
  final int rotationQuarterTurns;
  final ValueChanged<bool> onSubtitlesAvailableChanged;
  final void Function(NativeVlcController controller, VoidCallback onEvicted)
      onVideoControllerInitialized;
  final VoidCallback onVideoControllerDisposed;
  final ValueNotifier<VideoPlaybackProgress> progressNotifier;
  final bool isCurrent;
  final VoidCallback? onError;
  final NativeVlcController? existingController;

  const MediaPlayerWidget({
    super.key,
    required this.container,
    required this.fileName,
    required this.contentUriString,
    required this.showUI,
    required this.onToggleUI,
    required this.onZoomChanged,
    required this.skipSeconds,
    required this.autoPlay,
    required this.isAudio,
    required this.subtitlesEnabled,
    required this.playbackSpeed,
    required this.rotationQuarterTurns,
    required this.onSubtitlesAvailableChanged,
    required this.onVideoControllerInitialized,
    required this.onVideoControllerDisposed,
    required this.progressNotifier,
    required this.isCurrent,
    this.existingController,
    this.onError,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> {
  late NativeVlcController _controller;
  bool _initialized = false;
  String? _playerError;
  ClosedCaptionFile? _captionFile;
  bool _isSeeking = false;
  bool _showLeftIndicator = false;
  bool _showRightIndicator = false;
  bool _isSpeedHeld = false;
  final GlobalKey _interactiveViewerKey = GlobalKey();
  Timer? _indicatorTimer;
  int _initToken = 0;
  final TransformationController _videoTransformationController =
      TransformationController();
  static const double _minZoomScale = 1.0;
  static const double _maxZoomScale = 2.2;
  double _videoScale = _minZoomScale;
  TapDownDetails? _videoDoubleTapDetails;
  Size _lastKnownVideoSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_initialized && oldWidget.playbackSpeed != widget.playbackSpeed) {
      _controller.setPlaybackSpeed(widget.playbackSpeed);
    }
  }

  Future<void> _initPlayer() async {
    final token = ++_initToken;
    final prewarmed = widget.existingController;
    if (prewarmed != null) {
      _controller = prewarmed;
      _controller.addListener(_onControllerTick);
      try {
        final captionFile = await _loadCaptions(widget.fileName);
        if (token != _initToken || !mounted) return;
        _captionFile = captionFile;
        setState(() {
          _initialized = true;
          _playerError = null;
        });
        widget.onVideoControllerInitialized(_controller, _handleEvicted);
        await _controller.setVolume(100);
        await _controller.setLooping(false);
        await _controller.setPlaybackSpeed(widget.playbackSpeed);
        if (widget.autoPlay && widget.isCurrent) {
          _controller.play();
        }
      } catch (e) {
        if (token == _initToken && mounted) {
          setState(() => _playerError = 'Media stream initialization failed: $e');
          widget.onError?.call();
        }
      }
      return;
    }

    final controller = NativeVlcController(
      contentUriString: widget.contentUriString,
      autoPlay: false,
    );
    _controller = controller;
    controller.addListener(_onControllerTick);
    try {
      final captionsFuture = _loadCaptions(widget.fileName);
      final initFuture = controller.initialize();
      final captionFile = await captionsFuture;
      if (token != _initToken || !mounted) {
        controller.dispose();
        return;
      }
      _captionFile = captionFile;
      await initFuture;
      if (token != _initToken || !mounted) {
        controller.dispose();
        return;
      }
      if (controller.value.hasError) {
        throw Exception(controller.value.errorDescription);
      }
      setState(() {
        _initialized = true;
        _playerError = null;
      });
      widget.onVideoControllerInitialized(controller, _handleEvicted);
      await controller.setVolume(100);
      await controller.setLooping(false);
      await controller.setPlaybackSpeed(widget.playbackSpeed);
      if (widget.autoPlay && widget.isCurrent) {
        controller.play();
      }
    } catch (e) {
      if (token == _initToken && mounted) {
        setState(() => _playerError = 'Media stream initialization failed: $e');
        widget.onError?.call();
      } else {
        controller.dispose();
      }
    }
  }

  void _handleEvicted() {
    if (!mounted) return;
    try {
      _controller.removeListener(_onControllerTick);
    } catch (_) {}
    setState(() {
      _initialized = false;
    });
    _initPlayer();
  }

  void _onControllerTick() {
    if (!mounted) return;
    if (_controller.value.hasError && _playerError == null) {
      setState(() {
        _playerError = _controller.value.errorDescription.isNotEmpty
            ? _controller.value.errorDescription
            : 'Media stream initialization failed';
      });
      widget.onError?.call();
      return;
    }
    if (!_initialized || !widget.isCurrent) return;
    if (_controller.value.size != _lastKnownVideoSize) {
      _lastKnownVideoSize = _controller.value.size;
      setState(() {});
    }
    widget.progressNotifier.value = widget.progressNotifier.value.copyWith(
      position: _controller.value.position,
      duration: _controller.value.duration,
    );
  }

  Future<ClosedCaptionFile?> _loadCaptions(String videoPath) async {
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
                ? SubRipCaptionFile(text)
                : WebVTTCaptionFile(text);
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
    if (_initialized) {
      try {
        _controller.removeListener(_onControllerTick);
      } catch (_) {}
    }
    widget.onVideoControllerDisposed();
    _videoTransformationController.dispose();
    if (_initialized) {
      final ctrl = _controller;
      try {
        ctrl.pause();
        Future.delayed(const Duration(milliseconds: 150), () async {
          try {
            await ctrl.dispose();
          } catch (_) {}
        });
      } catch (_) {}
    }
    super.dispose();
  }

  void _onSpeedHoldStart(LongPressStartDetails _) {
    if (!_initialized) return;
    HapticFeedback.heavyImpact();
    _controller.setPlaybackSpeed(2.0);
    setState(() => _isSpeedHeld = true);
  }

  void _onSpeedHoldEnd(LongPressEndDetails _) {
    if (!_initialized) return;
    _controller.setPlaybackSpeed(widget.playbackSpeed);
    setState(() => _isSpeedHeld = false);
  }

  Matrix4 _calculateZoomMatrix({required Offset localPosition, required double scale}) {
    final x = -localPosition.dx * (scale - 1.0);
    final y = -localPosition.dy * (scale - 1.0);
    return Matrix4.identity()
      ..translateByVector3(Vector3(x, y, 0.0))
      ..scaleByVector3(Vector3(scale, scale, 1.0));
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
          targetMatrix = Matrix4.identity()..scaleByVector3(Vector3(targetScale, targetScale, 1.0));
        }
      } else {
        targetMatrix = Matrix4.identity()..scaleByVector3(Vector3(targetScale, targetScale, 1.0));
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
    if (_isSeeking) return;
    _isSeeking = true;
    HapticFeedback.lightImpact();
    final currentPos = _controller.value.position;
    final duration = _controller.value.duration;
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
    await _controller.seekTo(clampedPos);
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

    final bool isVideoReady = widget.isAudio || (_controller.value.size.width > 0 && _controller.value.size.height > 0);

    if (!_initialized || !isVideoReady) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
      );
    }

    final isRotated = widget.rotationQuarterTurns % 2 != 0;
    final double computedAspectRatio = widget.isAudio
        ? 0.8
        : (isRotated
            ? 1.0 / _controller.value.aspectRatio
            : _controller.value.aspectRatio);

    Widget corePlayerWidget = Center(
      child: AspectRatio(
        aspectRatio: computedAspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.isAudio)
              _buildAudioCenterVisual(cs)
            else
              RotatedBox(
                quarterTurns: widget.rotationQuarterTurns,
                child: NativeVlcPlayerView(controller: _controller),
              ),
            if (!widget.isAudio && widget.subtitlesEnabled)
              Positioned(
                bottom: widget.showUI ? 130 : 25,
                left: 20,
                right: 20,
                child: ValueListenableBuilder<VideoPlaybackProgress>(
                  valueListenable: widget.progressNotifier,
                  builder: (context, progress, child) {
                    return ClosedCaption(
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

  Widget _buildAudioCenterVisual(ColorScheme cs) {
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
        _AudioVisualizer(isPlaying: _controller.value.isPlaying),
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