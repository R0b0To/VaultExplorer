import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/video_aspect_ratio_mode.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/native_media3_controller.dart'
    show DeviceVolumeBridge;
import 'package:vaultexplorer/features/browser/viewer/screen_brightness_bridge.dart';
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
      computedSlider = (sliderValue ?? this.sliderValue).clamp(0.0, 1.0);
    } else if (currentDuration.inMilliseconds > 0) {
      final ratio = currentPosition.inMilliseconds / currentDuration.inMilliseconds;
      computedSlider = ratio.clamp(0.0, 1.0);
      if (computedSlider.isNaN) computedSlider = 0.0;
    }

    return VideoPlaybackProgress(
      position: currentPosition,
      duration: currentDuration,
      sliderValue: computedSlider,
      isDragging: currentDragging,
    );
  }
}

class MediaPlayerWidget extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String fileName;
  final String contentUriString;
  final bool showUI;
  final ValueChanged<bool> onToggleUI;
  final ValueChanged<bool> onZoomChanged;
  final int skipSeconds;
  final bool isAudio;
  final bool subtitlesEnabled;
  final double subtitleFontSize;
  final double subtitleVerticalPosition;
  final ValueChanged<double>? onSubtitleVerticalPositionChanged;
  final double playbackSpeed;
  final int rotationQuarterTurns;
  final ValueChanged<bool> onSubtitlesAvailableChanged;
  final ValueNotifier<VideoPlaybackProgress> progressNotifier;
  final void Function(int width, int height)? onSizeKnown;
  final VoidCallback? onError;
  final VideoPlaybackManager playbackManager;
  final Uint8List? posterBytes;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;
  final bool enableZoom;
  final bool isMuted;
  final ValueChanged<bool>? onMuteChanged;
  final VideoAspectRatioMode videoAspectRatioMode;
  final bool edgeSwipeBrightnessEnabled;
  final bool edgeSwipeVolumeEnabled;
  final bool edgeSwipeHudEnabled;
  final double edgeSwipeWidthFraction;
  final bool pinchZoomOutEnabled;
  final double minVideoZoomScale;
  final double holdToSpeedMultiplier;

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
    this.subtitleFontSize = 15.0,
    this.subtitleVerticalPosition = 0.0,
    this.onSubtitleVerticalPositionChanged,
    required this.playbackSpeed,
    required this.rotationQuarterTurns,
    required this.onSubtitlesAvailableChanged,
    required this.progressNotifier,
    required this.playbackManager,
    this.posterBytes,
    this.thumbnailCacheMode = ThumbnailCacheMode.appCache,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    this.onSizeKnown,
    this.onError,
   this.isMuted = false,
    this.onMuteChanged,
    this.enableZoom = true,
    this.videoAspectRatioMode = VideoAspectRatioMode.bestFit,
    this.edgeSwipeBrightnessEnabled = true,
    this.edgeSwipeVolumeEnabled = true,
    this.edgeSwipeHudEnabled = true,
    this.edgeSwipeWidthFraction = 0.25,
    this.pinchZoomOutEnabled = true,
    this.minVideoZoomScale = 0.25,
    this.holdToSpeedMultiplier = 2.0,
  });

  @override
  ConsumerState<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends ConsumerState<MediaPlayerWidget> {
  VaultFileIoApi get _fileIoApi => ref.read(vaultFileIoApiProvider);

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
  // The "at rest" scale double-tap resets to and zoom-lock coordination
  // treats as "not interacting". Distinct from the InteractiveViewer's
  // actual `minScale` bound, which can now sit below this when pinch
  // zoom-out is enabled -- see [_effectiveMinZoomScale].
  static const double _baselineZoomScale = 1.0;
  static const double _maxZoomScale = 4.0;
  double _videoScale = _baselineZoomScale;
  TapDownDetails? _videoDoubleTapDetails;
  Size _lastKnownVideoSize = Size.zero;
  double? _knownAspectRatio;
  Uint8List? _localPosterBytes;
  late final ThumbnailCacheService _thumbnailCache;

  // -- Edge-swipe brightness/volume gestures --
  // Every touch currently down anywhere on this widget, tracked via a raw
  // Listener (fires regardless of which gesture recognizer -- tap,
  // double-tap, InteractiveViewer's pan/scale -- ends up winning the
  // arena for that pointer). Lets an edge drag abort the instant a second
  // finger appears, mirroring the pinch-vs-swipe fix already used at the
  // MediaViewerScreen level.
  final Set<int> _activeTouchPointers = {};
  int? _brightnessDragPointerId;
  double? _brightnessDragStartY;
  double? _brightnessDragStartLevel;
  double _brightnessLevel = 0.5;
  bool _showBrightnessHud = false;
  Timer? _brightnessHudTimer;
  int? _volumeDragPointerId;
  double? _volumeDragStartY;
  double? _volumeDragStartLevel;
  double _volumeLevel = 1.0;
  bool _showVolumeHud = false;
  Timer? _volumeHudTimer;
  static const double _edgeSwipeSlop = 10.0;
  bool _isBrightnessDragging = false;
  bool _isVolumeDragging = false;
  double _effectiveHoldSpeed = 2.0;

  /// Whether the video is currently zoomed in beyond the 1.0x baseline.
  /// Single-finger dragging (panning zoomed content, or an edge swipe) is
  /// only meaningful in one of these two modes at a time, never both.
  bool get _isZoomedIn => _videoScale > _baselineZoomScale + 0.001;

  /// The InteractiveViewer's actual pinch-zoom floor: the configured
  /// minimum when zoom-out is enabled, otherwise the historical hard
  /// floor of 1.0x (no zoom-out at all).
  double get _effectiveMinZoomScale => widget.pinchZoomOutEnabled
      ? widget.minVideoZoomScale.clamp(
          MediaViewerConstants.minVideoZoomFloor,
          1.0,
        )
      : _baselineZoomScale;

  @override
  void initState() {
    super.initState();
    _thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final initialPoster = widget.posterBytes ??
        _thumbnailCache.peekMemory(
          widget.container,
          widget.fileName,
          widget.thumbnailQuality,
        );
    _localPosterBytes = initialPoster;
    widget.playbackManager.activeControllerNotifier.addListener(_onSharedControllerChanged);
    widget.playbackManager.currentFileNotifier.addListener(_onCurrentFileChanged);
    _knownAspectRatio =
        MediaAspectRatioCache.get(widget.container, widget.fileName);
   _brightnessLevel = ScreenBrightnessBridge.lastKnownLevel;
    DeviceVolumeBridge.getVolume().then((vol) {
      if (mounted) {
        setState(() => _volumeLevel = vol);
      }
    });
    _syncBoundController();
    _ensurePosterLoaded();
  }

Future<void> _ensurePosterLoaded() async {
    if (_localPosterBytes != null) {
      return;
    }
    try {
      final bytes = await _thumbnailCache.fetch(
        container: widget.container,
        filePath: widget.fileName,
        mode: widget.thumbnailCacheMode,
        quality: widget.thumbnailQuality,
      );
      if (bytes != null && bytes.isNotEmpty && mounted) {
        setState(() {
          _localPosterBytes = bytes;
        });
      }
    } catch (_) {
      // Poster load failed; fall back to no poster.
    }
  }

  @override
  void didUpdateWidget(covariant MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileName != widget.fileName) {
      // File changed — reset poster for new file
      final newPoster = widget.posterBytes ??
          _thumbnailCache.peekMemory(
            widget.container,
            widget.fileName,
            widget.thumbnailQuality,
          );
      _localPosterBytes = newPoster;
      _knownAspectRatio =
          MediaAspectRatioCache.get(widget.container, widget.fileName);
      _ensurePosterLoaded();
    } else if (widget.posterBytes != null && widget.posterBytes != oldWidget.posterBytes) {
      // Same file, but explicit new poster bytes provided
      _localPosterBytes = widget.posterBytes!;
    }
     if (widget.isMuted != oldWidget.isMuted) {
      if (widget.isMuted) {
        _volumeLevel = 0.0;
      } else {
        DeviceVolumeBridge.getVolume().then((vol) {
          if (mounted) setState(() => _volumeLevel = vol > 0 ? vol : 0.5);
        });
      }
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
      _videoScale = _baselineZoomScale;
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
            final rawError = controller.value.errorDescription;
            setState(() {
            _playerError = rawError.isNotEmpty
                ? (rawError == 'Video decoder unavailable — hardware codec contention'
                    ? context.l10n.videoDecoderUnavailableError
                    : rawError)
                : context.l10n.mediaStreamInitFailedError;
          });
          widget.onError?.call();
          widget.onToggleUI(true); // Force reveal top bar and action menus on error
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
    if (widget.progressNotifier.value.isDragging || _isSeeking) return;

    final Duration rawPos = controller.value.position;
    final Duration rawDur = controller.value.duration;

    final newProgress = widget.progressNotifier.value.copyWith(
      position: rawPos < Duration.zero ? Duration.zero : rawPos,
      duration: rawDur < Duration.zero ? Duration.zero : rawDur,
    );

    if (widget.progressNotifier.value.position != newProgress.position ||
        widget.progressNotifier.value.duration != newProgress.duration ||
        (widget.progressNotifier.value.sliderValue - newProgress.sliderValue).abs() > 0.0005) {
      widget.progressNotifier.value = newProgress;
    }
  }

  Future<CaptionTrack?> _loadCaptions(String videoPath) async {
    final dotIndex = videoPath.lastIndexOf('.');
    if (dotIndex == -1) return null;
    final basePath = videoPath.substring(0, dotIndex);
    for (final ext in ['srt', 'vtt']) {
      final subPath = '$basePath.$ext';
      try {
        final size = await _fileIoApi.getFileSize(
          widget.container,
          subPath,
        );
        if (size > 0) {
          final data = await _fileIoApi.readFileChunk(
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
      } catch (_) {
        // Expected when no matching .srt/.vtt file exists next to the
        // video for this extension -- try the next extension, or fall
        // through to "no subtitles available" below.
      }
    }
    widget.onSubtitlesAvailableChanged(false);
    return null;
  }

   String _captionTextAt(Duration position) {
    final file = _captionFile;
    if (file == null) return '';
    return file.captionAt(position)?.text ?? '';
  }

  @override
  void dispose() {
    _indicatorTimer?.cancel();
    _brightnessHudTimer?.cancel();
    _volumeHudTimer?.cancel();
    _boundController?.removeListener(_onControllerTick);
    widget.playbackManager.activeControllerNotifier.removeListener(_onSharedControllerChanged);
    widget.playbackManager.currentFileNotifier.removeListener(_onCurrentFileChanged);
    _videoTransformationController.dispose();
    super.dispose();
  }

 void _onSpeedHoldStart(LongPressStartDetails details) {
    final controller = _boundController;
    if (controller == null) return;
    HapticFeedback.heavyImpact();
    final box = context.findRenderObject();
    final width = box is RenderBox && box.hasSize
        ? box.size.width
        : MediaQuery.of(context).size.width;
    final isLeft = details.localPosition.dx < width * 0.35;

    final double targetSpeed;
    if (widget.holdToSpeedMultiplier < 1.0) {
      targetSpeed = widget.holdToSpeedMultiplier;
    } else if (isLeft) {
      targetSpeed = 0.5;
    } else {
      targetSpeed = widget.holdToSpeedMultiplier;
    }

    _effectiveHoldSpeed = targetSpeed;
    controller.setPlaybackSpeed(targetSpeed);
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
    ..translateByDouble(x, y, 0.0, 1.0)
    ..scaleByDouble(scale, scale, 1.0, 1.0);
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
    final bool atBaseline = (_videoScale - _baselineZoomScale).abs() < 0.001;
    if (atBaseline) {
      targetScale = _maxZoomScale;
      if (box.hasSize) {
        final position = box.globalToLocal(doubleTapDetails.globalPosition);
        if (position.isFinite) {
          targetMatrix = _calculateZoomMatrix(
            localPosition: position,
            scale: targetScale,
          );
        } else {
          targetMatrix = Matrix4.identity()..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
        }
      } else {
        targetMatrix = Matrix4.identity()..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
      }
    } else {
      // Whether the video was pinched in or out, double-tap always
      // cleanly resets back to the 1.0x baseline rather than toggling
      // toward whatever the current pinch-zoom-out floor happens to be.
      targetScale = _baselineZoomScale;
      targetMatrix = Matrix4.identity();
    }
    setState(() {
      _videoScale = targetScale;
      _videoTransformationController.value = targetMatrix;
    });
    widget.onZoomChanged(true);
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

Widget _buildVideoTexture(NativeVideoController controller) {
    final mode = widget.videoAspectRatioMode;
    final textureView = NativeVideoPlayerView(controller: controller);
    final rawSize = controller.value.size;
    if (rawSize.width <= 0 || rawSize.height <= 0) {
      return RotatedBox(
        quarterTurns: widget.rotationQuarterTurns,
        child: ColoredBox(
          color: Colors.black,
          child: textureView,
        ),
      );
    }
    double sizedWidth = rawSize.width;
    double sizedHeight = rawSize.height;
    final BoxFit fit;
    switch (mode) {
      case VideoAspectRatioMode.bestFit:
        fit = BoxFit.contain;
      case VideoAspectRatioMode.fill:
        fit = BoxFit.fill;
      case VideoAspectRatioMode.ratio16x9:
      case VideoAspectRatioMode.ratio4x3:
        fit = BoxFit.cover;
      case VideoAspectRatioMode.centre:
        fit = BoxFit.none;
        final dpr = MediaQuery.of(context).devicePixelRatio;
        if (dpr > 0) {
          sizedWidth = rawSize.width / dpr;
          sizedHeight = rawSize.height / dpr;
        }
    }
    return RotatedBox(
      quarterTurns: widget.rotationQuarterTurns,
      child: ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: FittedBox(
            fit: fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: sizedWidth,
              height: sizedHeight,
              child: textureView,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPoster(ColorScheme cs, {required bool isLoading}) {
    final poster = _localPosterBytes ??
        widget.posterBytes ??
        _thumbnailCache.peekMemory(
          widget.container,
          widget.fileName,
        );

    final posterCacheWidth =
        (MediaQuery.of(context).size.width * MediaQuery.of(context).devicePixelRatio)
            .round()
            .clamp(1, 1 << 20);
    final isRotated = widget.rotationQuarterTurns % 2 != 0;
    final knownRatio = _knownAspectRatio ??
        MediaAspectRatioCache.get(widget.container, widget.fileName);
    final effectiveKnownRatio = (knownRatio != null && isRotated)
        ? 1.0 / knownRatio
        : knownRatio;

    Widget? posterContent;
    if (poster != null && poster.isNotEmpty) {
      final mode = widget.videoAspectRatioMode;
      final controller = _boundController;
      final rawW = (controller != null && controller.value.size.width > 0)
          ? controller.value.size.width
          : _lastKnownVideoSize.width;
      final rawH = (controller != null && controller.value.size.height > 0)
          ? controller.value.size.height
          : _lastKnownVideoSize.height;

      final BoxFit fit;
      switch (mode) {
        case VideoAspectRatioMode.bestFit:
          fit = BoxFit.contain;
        case VideoAspectRatioMode.fill:
          fit = BoxFit.fill;
        case VideoAspectRatioMode.ratio16x9:
        case VideoAspectRatioMode.ratio4x3:
          fit = BoxFit.cover;
        case VideoAspectRatioMode.centre:
          fit = BoxFit.none;
      }

      Widget imageWidget = Image.memory(
        poster,
        fit: mode == VideoAspectRatioMode.centre ? BoxFit.fill : fit,
        cacheWidth: posterCacheWidth,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.expand();
        },
      );

      if (mode == VideoAspectRatioMode.centre) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        if (rawW > 0 && rawH > 0 && dpr > 0) {
          imageWidget = SizedBox(
            width: rawW / dpr,
            height: rawH / dpr,
            child: imageWidget,
          );
        } else {
          imageWidget = FittedBox(
            fit: BoxFit.contain,
            child: imageWidget,
          );
        }
      }

      if (widget.isAudio) {
        posterContent = Center(
          child: AspectRatio(
            aspectRatio: 0.8,
            child: RotatedBox(
              quarterTurns: widget.rotationQuarterTurns,
              child: Image.memory(
                poster,
                fit: BoxFit.cover,
                cacheWidth: posterCacheWidth,
                errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
              ),
            ),
          ),
        );
      } else {
        posterContent = RotatedBox(
          quarterTurns: widget.rotationQuarterTurns,
          child: SizedBox.expand(
            child: FittedBox(
              fit: fit,
              clipBehavior: Clip.hardEdge,
              child: imageWidget,
            ),
          ),
        );
      }
    }

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (posterContent != null)
            posterContent
          else if (widget.isAudio)
            Center(child: _buildAudioCenterVisual(cs, isPlaying: false))
          else
            const SizedBox.expand(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_playerError != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onToggleUI(!widget.showUI),
        child: Center(
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
        ),
      );
    }
    final controller = _boundController;
    final bool isVideoReady = controller != null &&
        _initialized &&
        (widget.isAudio || (controller.value.size.width > 0 && controller.value.size.height > 0));
    final isRotated = widget.rotationQuarterTurns % 2 != 0;
    final double outerAspectRatio = widget.isAudio
        ? 0.8
        : (isVideoReady
            ? (isRotated ? 1.0 / controller.value.aspectRatio : controller.value.aspectRatio)
            : ((_knownAspectRatio != null && isRotated)
                ? 1.0 / _knownAspectRatio!
                : (_knownAspectRatio ?? 16 / 9)));
    // Fill/Centre size the viewport to the full available space instead
    // of a fixed ratio; 16:9/4:3 force a fixed ratio regardless of the
    // source or its rotation (a landscape frame stays 16:9 on screen no
    // matter how the source video itself is oriented); Best fit keeps the
    // historical rotation-aware, source-shaped box.
    final double? effectiveOuterAspectRatio = widget.isAudio
        ? outerAspectRatio
        : switch (widget.videoAspectRatioMode) {
            VideoAspectRatioMode.bestFit => outerAspectRatio,
            VideoAspectRatioMode.ratio16x9 => 16 / 9,
            VideoAspectRatioMode.ratio4x3 => 4 / 3,
            VideoAspectRatioMode.fill => null,
            VideoAspectRatioMode.centre => null,
          };
   final Widget stackContent = Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Hero(
                tag: 'media_hero_${widget.container.volId}_${widget.fileName}',
                createRectTween: (begin, end) => MaterialRectArcTween(begin: begin, end: end),
                child: Material(
                  color: Colors.black,
                  child: _buildPoster(cs, isLoading: _isActive),
                ),
              ),
            ),
            if (!widget.isAudio && controller != null && _isActive)
              Positioned.fill(
                child: ValueListenableBuilder<NativeVideoValue>(
                  valueListenable: controller,
                  builder: (context, val, _) {
                    final showVideo = val.isInitialized &&
                        val.hasRenderedFirstFrame &&
                        !controller.isDisposed;

                    return AnimatedOpacity(
                      opacity: showVideo ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: _buildVideoTexture(controller),
                    );
                  },
                ),
              ),
          if (widget.isAudio && controller != null && isVideoReady)
              _buildAudioCenterVisual(cs, isPlaying: controller.value.isPlaying)
            else if (!widget.isAudio && widget.subtitlesEnabled)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxH = constraints.maxHeight;
                    const baseBottom = 25.0;
                    final maxUsable = (maxH - 70.0 > baseBottom) ? maxH - 70.0 : baseBottom;
                    final effectiveBottom = (baseBottom +
                            widget.subtitleVerticalPosition *
                                (maxUsable - baseBottom))
                        .clamp(baseBottom, maxUsable);

                    return Stack(
                      children: [
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: effectiveBottom,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragUpdate: (details) {
                              if (widget.onSubtitleVerticalPositionChanged == null) return;
                              final delta = -details.primaryDelta!;
                              final totalRange = maxUsable - baseBottom;
                              if (totalRange <= 0) return;
                              final newPos = (widget.subtitleVerticalPosition +
                                      (delta / totalRange))
                                  .clamp(0.0, 1.0);
                              widget.onSubtitleVerticalPositionChanged!(newPos);
                            },
                            child: controller != null
                                ? ValueListenableBuilder<NativeVideoValue>(
                                    valueListenable: controller,
                                    builder: (context, videoVal, _) {
                                      return ValueListenableBuilder<VideoPlaybackProgress>(
                                        valueListenable: widget.progressNotifier,
                                        builder: (context, progress, _) {
                                          final text = videoVal.captionText.isNotEmpty
                                              ? videoVal.captionText
                                              : _captionTextAt(progress.position);
                                          return ClosedCaptionText(
                                            text: text,
                                            textStyle: TextStyle(
                                              fontSize: widget.subtitleFontSize,
                                              color: Colors.white,
                                              shadows: const [
                                                Shadow(
                                                  blurRadius: 4,
                                                  color: Colors.black,
                                                  offset: Offset(1, 1),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  )
                                : ValueListenableBuilder<VideoPlaybackProgress>(
                                    valueListenable: widget.progressNotifier,
                                    builder: (context, progress, _) {
                                      return ClosedCaptionText(
                                        text: _captionTextAt(progress.position),
                                        textStyle: TextStyle(
                                          fontSize: widget.subtitleFontSize,
                                          color: Colors.white,
                                          shadows: const [
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
                        ),
                      ],
                    );
                  },
                ),
              ),
            if (controller != null && _isActive)
              _MediaLoadingFeedbackOverlay(
                controller: controller,
                colorScheme: cs,
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
        );
    Widget corePlayerWidget = effectiveOuterAspectRatio != null
        ? Center(
            child: AspectRatio(
              aspectRatio: effectiveOuterAspectRatio,
              child: stackContent,
            ),
          )
        : SizedBox.expand(child: stackContent);
if (!widget.isAudio && widget.enableZoom) {
      corePlayerWidget = InteractiveViewer(
        key: _interactiveViewerKey,
        transformationController: _videoTransformationController,
        maxScale: MediaViewerConstants.maxVideoZoom,
        minScale: _effectiveMinZoomScale,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        panEnabled: false,
        clipBehavior: Clip.none,
        onInteractionStart: (details) {
          if (details.pointerCount >= 2) {
            widget.onZoomChanged(false);
          }
        },
        onInteractionUpdate: (details) {
          final s = _videoTransformationController.value.getMaxScaleOnAxis();
          if (s != _videoScale) {
            _videoScale = s;
          }
        },
        onInteractionEnd: (details) {
          final s = _videoTransformationController.value.getMaxScaleOnAxis();
          _videoScale = s;
          widget.onZoomChanged(true);
        },
        child: corePlayerWidget,
      );
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onGlobalPointerDown,
      onPointerUp: _onGlobalPointerUp,
      onPointerCancel: _onGlobalPointerUp,
      child: LayoutBuilder(
        builder: (context, outerConstraints) {
          final rawEdgeWidth =
              outerConstraints.maxWidth * widget.edgeSwipeWidthFraction;
          final edgeWidth = rawEdgeWidth.clamp(
            outerConstraints.maxWidth * MediaViewerConstants.edgeSwipeWidthMin,
            outerConstraints.maxWidth * MediaViewerConstants.edgeSwipeWidthMax,
          );
          return ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                corePlayerWidget,
                if (widget.edgeSwipeBrightnessEnabled)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: edgeWidth,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _onBrightnessPointerDown,
                      onPointerMove: _onBrightnessPointerMove,
                      onPointerUp: _onBrightnessPointerUp,
                      onPointerCancel: _onBrightnessPointerUp,
                    ),
                  ),
                if (widget.edgeSwipeVolumeEnabled)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: edgeWidth,
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _onVolumePointerDown,
                      onPointerMove: _onVolumePointerMove,
                      onPointerUp: _onVolumePointerUp,
                      onPointerCancel: _onVolumePointerUp,
                    ),
                  ),
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
                              _effectiveHoldSpeed < 1.0
                                  ? Icons.slow_motion_video_rounded
                                  : Icons.fast_forward_rounded,
                              color: cs.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              context.l10n.holdToSpeedIndicatorLabel(
                                _formatSpeedMultiplier(
                                  _effectiveHoldSpeed,
                                ),
                              ),
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
                if (widget.edgeSwipeHudEnabled && _showBrightnessHud)
                  _buildEdgeGestureHud(
                    isLeft: true,
                    icon: Icons.wb_sunny_rounded,
                    level: _brightnessLevel,
                  ),
                if (widget.edgeSwipeHudEnabled && _showVolumeHud)
                  _buildEdgeGestureHud(
                    isLeft: false,
                    icon: _volumeLevel <= 0.01
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    level: _volumeLevel,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _formatSpeedMultiplier(double value) {
    if (value % 1 == 0) return value.toInt().toString();
    String s = value.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s;
  }

  Widget _buildEdgeGestureHud({
    required bool isLeft,
    required IconData icon,
    required double level,
  }) {
    final clampedLevel = level.clamp(0.0, 1.0);
    final percent = (clampedLevel * 100).round();
    return Positioned(
      left: isLeft ? 40 : null,
      right: isLeft ? null : 40,
      child: IgnorePointer(
        child: Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(height: 8),
              Container(
                height: 72,
                width: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    widthFactor: 1.0,
                    heightFactor: clampedLevel,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$percent%',
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

  // Fires for every raw touch down/up on this widget, regardless of which
  // gesture recognizer ends up winning the arena for it. Mirrors the
  // pinch-vs-swipe fix in MediaViewerScreen, scoped locally here so an
  // edge-swipe gesture can abort the instant a second finger appears
  // without threading state through the screen level.
  void _onGlobalPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _activeTouchPointers.add(event.pointer);
    if (_activeTouchPointers.length >= 2) {
      _abortEdgeGestures();
    }
  }

  void _onGlobalPointerUp(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _activeTouchPointers.remove(event.pointer);
  }

  void _abortEdgeGestures() {
    if (_brightnessDragPointerId != null) {
      _brightnessDragPointerId = null;
      _brightnessDragStartY = null;
      _brightnessDragStartLevel = null;
      if (_isBrightnessDragging) {
        _isBrightnessDragging = false;
        _hideBrightnessHudSoon();
      }
    }
    if (_volumeDragPointerId != null) {
      _volumeDragPointerId = null;
      _volumeDragStartY = null;
      _volumeDragStartLevel = null;
      if (_isVolumeDragging) {
        _isVolumeDragging = false;
        _hideVolumeHudSoon();
      }
    }
  }

  void _onBrightnessPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch || !_isActive) return;
    if (_activeTouchPointers.length > 1 || _isZoomedIn) return;
    _brightnessDragPointerId = event.pointer;
    _brightnessDragStartY = event.position.dy;
    _brightnessDragStartLevel = ScreenBrightnessBridge.lastKnownLevel;
    _isBrightnessDragging = false;
  }

  void _onBrightnessPointerMove(PointerMoveEvent event) {
    if (_brightnessDragPointerId != event.pointer) return;
    if (_activeTouchPointers.length > 1) {
      _abortEdgeGestures();
      return;
    }
    final startY = _brightnessDragStartY;
    final startLevel = _brightnessDragStartLevel;
    if (startY == null || startLevel == null) return;
    final totalDelta = startY - event.position.dy;
    if (!_isBrightnessDragging) {
      if (totalDelta.abs() < _edgeSwipeSlop) return;
      _isBrightnessDragging = true;
      _brightnessHudTimer?.cancel();
      setState(() {
        _brightnessLevel = startLevel;
        _showBrightnessHud = true;
      });
    }
    final effectiveDelta = totalDelta - (totalDelta.isNegative ? -_edgeSwipeSlop : _edgeSwipeSlop);
    final newLevel = (startLevel +
            effectiveDelta / MediaViewerConstants.edgeSwipeFullRangeDistance)
        .clamp(0.0, 1.0);
    if ((newLevel - _brightnessLevel).abs() < 0.002) return;
    setState(() => _brightnessLevel = newLevel);
    unawaited(ScreenBrightnessBridge.setBrightness(newLevel));
  }

  void _onBrightnessPointerUp(PointerEvent event) {
    if (_brightnessDragPointerId != event.pointer) return;
    _brightnessDragPointerId = null;
    _brightnessDragStartY = null;
    _brightnessDragStartLevel = null;
    if (_isBrightnessDragging) {
      _isBrightnessDragging = false;
      _hideBrightnessHudSoon();
    }
  }

  void _hideBrightnessHudSoon() {
    _brightnessHudTimer?.cancel();
    _brightnessHudTimer = Timer(
      MediaViewerConstants.edgeSwipeHudHideDelay,
      () {
        if (mounted) setState(() => _showBrightnessHud = false);
      },
    );
  }

  void _onVolumePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch || !_isActive) return;
    if (_activeTouchPointers.length > 1 || _isZoomedIn) return;
    _volumeDragPointerId = event.pointer;
    _volumeDragStartY = event.position.dy;
    _volumeDragStartLevel = widget.isMuted ? 0.0 : _volumeLevel;
    _isVolumeDragging = false;
  }

  void _onVolumePointerMove(PointerMoveEvent event) {
    if (_volumeDragPointerId != event.pointer) return;
    if (_activeTouchPointers.length > 1) {
      _abortEdgeGestures();
      return;
    }
    final startY = _volumeDragStartY;
    final startLevel = _volumeDragStartLevel;
    if (startY == null || startLevel == null) return;
    final totalDelta = startY - event.position.dy;
    if (!_isVolumeDragging) {
      if (totalDelta.abs() < _edgeSwipeSlop) return;
      _isVolumeDragging = true;
      _volumeHudTimer?.cancel();
      setState(() {
        _volumeLevel = startLevel;
        _showVolumeHud = true;
      });
    }
    final effectiveDelta = totalDelta - (totalDelta.isNegative ? -_edgeSwipeSlop : _edgeSwipeSlop);
    final newLevel = (startLevel +
            effectiveDelta / MediaViewerConstants.edgeSwipeFullRangeDistance)
        .clamp(0.0, 1.0);
    if ((newLevel - _volumeLevel).abs() < 0.002) return;
    setState(() => _volumeLevel = newLevel);
    unawaited(DeviceVolumeBridge.setVolume(newLevel));

    if (newLevel <= 0.01) {
      if (!widget.isMuted) {
        widget.onMuteChanged?.call(true);
      }
    } else {
      if (widget.isMuted) {
        widget.onMuteChanged?.call(false);
      }
      _boundController?.setVolume(100);
    }
  }

  void _onVolumePointerUp(PointerEvent event) {
    if (_volumeDragPointerId != event.pointer) return;
    _volumeDragPointerId = null;
    _volumeDragStartY = null;
    _volumeDragStartLevel = null;
    if (_isVolumeDragging) {
      _isVolumeDragging = false;
      _hideVolumeHudSoon();
    }
  }

  void _hideVolumeHudSoon() {
    _volumeHudTimer?.cancel();
    _volumeHudTimer = Timer(MediaViewerConstants.edgeSwipeHudHideDelay, () {
      if (mounted) setState(() => _showVolumeHud = false);
    });
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

class _MediaLoadingFeedbackOverlay extends StatefulWidget {
  final NativeVideoController controller;
  final ColorScheme colorScheme;

  const _MediaLoadingFeedbackOverlay({
    required this.controller,
    required this.colorScheme,
  });

  @override
  State<_MediaLoadingFeedbackOverlay> createState() => _MediaLoadingFeedbackOverlayState();
}

class _MediaLoadingFeedbackOverlayState extends State<_MediaLoadingFeedbackOverlay> {
  Timer? _delayTimer;
  bool _showFeedback = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_evaluateState);
    _evaluateState();
  }

  @override
  void didUpdateWidget(covariant _MediaLoadingFeedbackOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_evaluateState);
      widget.controller.addListener(_evaluateState);
      _showFeedback = false;
      _delayTimer?.cancel();
      _delayTimer = null;
      _evaluateState();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_evaluateState);
    _delayTimer?.cancel();
    super.dispose();
  }

  void _evaluateState() {
    final val = widget.controller.value;
    // Feedback is needed if the video hasn't rendered its first frame yet,
    // or if it is rebuffering during playback.
    final videoStarted = val.isInitialized && val.hasRenderedFirstFrame;
    final needsFeedback = !videoStarted || val.isBuffering;

    if (!needsFeedback) {
      _delayTimer?.cancel();
      _delayTimer = null;
      if (_showFeedback) {
        setState(() => _showFeedback = false);
      }
      return;
    }

    if (_showFeedback) {
      // Already showing, trigger rebuild if downloading/buffering status changed
      setState(() {});
      return;
    }

    // Start 1-second delay timer so short loads (< 1s) never flicker
    _delayTimer ??= Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      final currentVal = widget.controller.value;
      final stillNeedsFeedback = (!currentVal.isInitialized || !currentVal.hasRenderedFirstFrame) || currentVal.isBuffering;
      if (stillNeedsFeedback) {
        setState(() => _showFeedback = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showFeedback) return const SizedBox.shrink();

    final val = widget.controller.value;
    final isDownloading = val.isMirrorDownloading;
    final cs = widget.colorScheme;

    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: _showFeedback ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isDownloading ? 16 : 14,
              vertical: isDownloading ? 10 : 14,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(isDownloading ? 24 : 100),
              border: isDownloading
                  ? Border.all(color: cs.primary.withValues(alpha: 0.5), width: 1.5)
                  : null,
            ),
            child: isDownloading
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Downloading...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}