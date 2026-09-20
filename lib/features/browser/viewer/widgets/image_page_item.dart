import 'dart:async';
import 'dart:math';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/screen_brightness_bridge.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/edge_swipe_claim_recognizer.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/encrypted_image_widget.dart';

class ImagePageItem extends StatefulWidget {
  final String fileName;
  final Uint8List? prefetchedBytes;
  final MountedContainer container;
  final BoxFit imageFit;
  final int rotationQuarterTurns;
  final bool showUI;
  final ValueChanged<bool> onToggleUI;
  final ValueChanged<bool> onZoomChanged;
  final void Function(int width, int height)? onSizeKnown;
  final VoidCallback? onError;
  final bool enableZoom;
  final bool pinchZoomOutEnabled;
  final double minZoomScale;
  final ThumbnailQuality thumbnailQuality;
  final ThumbnailCacheMode thumbnailCacheMode;
  final bool edgeSwipeBrightnessEnabled;
  final bool edgeSwipeHudEnabled;
  final double edgeSwipeWidthFraction;
  final bool isActive;

  const ImagePageItem({
    super.key,
    required this.fileName,
    required this.prefetchedBytes,
    required this.container,
    required this.imageFit,
    required this.rotationQuarterTurns,
    required this.showUI,
    required this.onToggleUI,
    required this.onZoomChanged,
    this.onSizeKnown,
    this.onError,
    this.enableZoom = true,
    this.pinchZoomOutEnabled = true,
    this.minZoomScale = 0.25,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    this.thumbnailCacheMode = ThumbnailCacheMode.appCache,
    this.edgeSwipeBrightnessEnabled = true,
    this.edgeSwipeHudEnabled = true,
    this.edgeSwipeWidthFraction = 0.25,
    this.isActive = true,
  });

  @override
  State<ImagePageItem> createState() => _ImagePageItemState();
}

class _ImagePageItemState extends State<ImagePageItem>
    with TickerProviderStateMixin {
  late final TransformationController _transformationController;
  double _scale = 1.0;
  TapDownDetails? _doubleTapDetails;
  Size? _imageSize;
  BoxFit? _lastFit;
  int? _lastRotation;
  Size? _lastViewportSize;

  AnimationController? _zoomAnimationController;

  // -- Edge-swipe brightness gesture --
  final Set<int> _activeTouchPointers = {};
  double _brightnessLevel = 0.5;
  bool _showBrightnessHud = false;
  Timer? _brightnessHudTimer;
  bool _isBrightnessDragging = false;
  EdgeSwipeClaimRecognizer? _brightnessClaim;

  static double _getMatrixScale(Matrix4 matrix) {
    final double x = matrix.storage[0];
    final double y = matrix.storage[1];
    return math.sqrt(x * x + y * y);
  }

  bool get _isZoomed =>
      (_getMatrixScale(_transformationController.value) - 1.0).abs() > 0.01;
  bool get _isZoomedIn =>
      _getMatrixScale(_transformationController.value) > 1.01;

  double get _effectiveMinZoomScale => widget.pinchZoomOutEnabled
      ? widget.minZoomScale.clamp(
          MediaViewerConstants.minVideoZoomFloor,
          1.0,
        )
      : 1.0;

  Animation<Matrix4>? _zoomAnimation;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController.addListener(_onImageTransformationChanged);
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: MediaViewerConstants.animationDuration,
    )..addListener(() {
        if (_zoomAnimation != null) {
          _isClampingMatrix = true;
          _transformationController.value = _zoomAnimation!.value;
          _isClampingMatrix = false;
        }
      });
    _brightnessLevel = ScreenBrightnessBridge.lastKnownLevel;
    _initImageDimensions();
  }

  static (int, int)? extractDimensionsFromBytes(Uint8List bytes) {
    if (bytes.length < 4) return null;
    // JPEG SOF parser (scans markers synchronously in <0.01ms)
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int i = 2;
      while (i < bytes.length - 8) {
        if (bytes[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = bytes[i + 1];
        if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
          final h = (bytes[i + 5] << 8) | bytes[i + 6];
          final w = (bytes[i + 7] << 8) | bytes[i + 8];
          if (w > 0 && h > 0) return (w, h);
          break;
        }
        final len = (bytes[i + 2] << 8) | bytes[i + 3];
        if (len < 2) break;
        i += 2 + len;
      }
    }
    // PNG header parser
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      if (w > 0 && h > 0) return (w, h);
    }
    // GIF header parser
    if (bytes.length >= 10 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      final w = bytes[6] | (bytes[7] << 8);
      final h = bytes[8] | (bytes[9] << 8);
      if (w > 0 && h > 0) return (w, h);
    }
    // WebP (RIFF....WEBP)
    if (bytes.length >= 30 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      // VP8 (lossy)
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x20) {
        final w = ((bytes[27] & 0x3F) << 8) | bytes[26];
        final h = ((bytes[29] & 0x3F) << 8) | bytes[28];
        if (w > 0 && h > 0) return (w, h);
      }
      // VP8L (lossless)
      if (bytes.length >= 25 &&
          bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x4C) {
        if (bytes[16] == 0x2F) {
          final w = 1 + (((bytes[18] & 0x3F) << 8) | bytes[17]);
          final h = 1 + (((bytes[20] & 0x0F) << 10) | (bytes[19] << 2) | ((bytes[18] & 0xC0) >> 6));
          if (w > 0 && h > 0) return (w, h);
        }
      }
      // VP8X (extended)
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x58) {
        final w = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
        final h = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
        if (w > 0 && h > 0) return (w, h);
      }
    }
    return null;
  }

  void _initImageDimensions() {
    if (widget.prefetchedBytes != null && widget.prefetchedBytes!.isNotEmpty) {
      final dims = extractDimensionsFromBytes(widget.prefetchedBytes!);
      if (dims != null && dims.$1 > 0 && dims.$2 > 0) {
        _imageSize = Size(dims.$1.toDouble(), dims.$2.toDouble());
        MediaAspectRatioCache.put(
          widget.container,
          widget.fileName,
          dims.$1,
          dims.$2,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onSizeKnown?.call(dims.$1, dims.$2);
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant ImagePageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefetchedBytes != widget.prefetchedBytes ||
        oldWidget.fileName != widget.fileName) {
      _imageSize = null;
      _lastViewportSize = null;
      _scale = 1.0;
      _transformationController.value = Matrix4.identity();
      _initImageDimensions();
    }
  if (!widget.isActive && _isBrightnessDragging) {
      _abortEdgeGestures();
    }
    if (oldWidget.isActive && !widget.isActive) {
      _scale = 1.0;
      _transformationController.value = Matrix4.identity();
      widget.onZoomChanged(true);
    }
  }

  Matrix4 _getBaselineMatrix(BoxConstraints constraints) {
    double? ar;
    if (_imageSize != null && _imageSize!.height > 0) {
      ar = _imageSize!.width / _imageSize!.height;
    } else {
      ar = MediaAspectRatioCache.get(widget.container, widget.fileName);
    }
    if (ar == null || ar <= 0) return Matrix4.identity();

    if (widget.rotationQuarterTurns % 2 != 0) {
      ar = 1 / ar;
    }

    if (widget.imageFit == BoxFit.contain) {
      return Matrix4.identity();
    }

    double? childWidth;
    double? childHeight;
    if (widget.imageFit == BoxFit.fitWidth) {
      childWidth = constraints.maxWidth;
      childHeight = constraints.maxWidth / ar;
    } else if (widget.imageFit == BoxFit.fitHeight) {
      childHeight = constraints.maxHeight;
      childWidth = constraints.maxHeight * ar;
    }

    if (childWidth != null && childHeight != null) {
      final canvasWidth = max(constraints.maxWidth, childWidth);
      final canvasHeight = max(constraints.maxHeight, childHeight);
      double x = 0.0;
      double y = 0.0;
      if (canvasWidth > constraints.maxWidth) {
        x = -(canvasWidth - constraints.maxWidth) / 2;
      }
      if (canvasHeight > constraints.maxHeight) {
        y = -(canvasHeight - constraints.maxHeight) / 2;
      }
      return Matrix4.translationValues(x, y, 0.0);
    }
    return Matrix4.identity();
  }

  void _centerImageInitially(BoxConstraints constraints) {
    _transformationController.value = _getBaselineMatrix(constraints);
    _scale = 1.0;
    widget.onZoomChanged(true);
  }

 void _animateImageZoomTo(Matrix4 targetMatrix, {required bool toBaseline}) {
    final controller = _zoomAnimationController;
    if (controller == null) {
      _transformationController.value = targetMatrix;
      return;
    }

    controller.stop();
    _zoomAnimation = Matrix4Tween(
      begin: _transformationController.value,
      end: targetMatrix,
    ).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
    );

    controller.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _scale = _getMatrixScale(_transformationController.value);
        });
        widget.onZoomChanged(toBaseline);
      }
    });
  }

  @override
  void dispose() {
    _brightnessHudTimer?.cancel();
    _zoomAnimationController?.dispose();
    _transformationController.removeListener(_onImageTransformationChanged);
    _transformationController.dispose();
    super.dispose();
  }

  // -- Brightness gesture handlers --
bool _isClampingMatrix = false;
  double? _activeCanvasWidth;
  double? _activeCanvasHeight;

  void _onImageTransformationChanged() {
    if (_isClampingMatrix || !mounted) return;
    final vw = _lastViewportSize?.width ?? 0.0;
    final vh = _lastViewportSize?.height ?? 0.0;
    if (vw <= 0 || vh <= 0) return;

   final matrix = _transformationController.value;
    final s = _getMatrixScale(matrix);
    if (s <= 0) return;

    if (s < _effectiveMinZoomScale) {
      final clampedS = _effectiveMinZoomScale;
      final cW = _activeCanvasWidth ?? vw;
      final cH = _activeCanvasHeight ?? vh;
      final dx = (vw - cW * clampedS) / 2.0;
      final dy = (vh - cH * clampedS) / 2.0;
      _isClampingMatrix = true;
      _transformationController.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0.0, 1.0)
        ..scaleByDouble(clampedS, clampedS, clampedS, 1.0);
      _isClampingMatrix = false;
      return;
    }

    if (s >= 1.0) {
      final cW = _activeCanvasWidth ?? vw;
      final cH = _activeCanvasHeight ?? vh;
      final scaledW = cW * s;
      final scaledH = cH * s;
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
        _isClampingMatrix = true;
        _transformationController.value = Matrix4.identity()
          ..translateByDouble(clampedTx, clampedTy, 0.0, 1.0)
          ..scaleByDouble(s, s, 1.0, 1.0);
        _isClampingMatrix = false;
      }
    }
  }

  Matrix4 _clampImageMatrix({
    required Matrix4 matrix,
    required double vw,
    required double vh,
    required double cW,
    required double cH,
  }) {
    if (vw <= 0 || vh <= 0 || cW <= 0 || cH <= 0) return matrix;
    final s = _getMatrixScale(matrix);
    if (s <= 0) return matrix;
    final clampedS = s.clamp(_effectiveMinZoomScale, MediaViewerConstants.maxImageZoom);

    if (clampedS < 1.0) {
      final dx = (vw - cW * clampedS) / 2.0;
      final dy = (vh - cH * clampedS) / 2.0;
      return Matrix4.identity()
        ..translateByDouble(dx, dy, 0.0, 1.0)
        ..scaleByDouble(clampedS, clampedS, clampedS, 1.0);
    }

    final scaledW = cW * s;
    final scaledH = cH * s;
    final currentTx = matrix.storage[12];
    final currentTy = matrix.storage[13];

    final double clampedTx = scaledW > vw
        ? currentTx.clamp(vw - scaledW, 0.0)
        : (vw - scaledW) / 2.0;
    final double clampedTy = scaledH > vh
        ? currentTy.clamp(vh - scaledH, 0.0)
        : (vh - scaledH) / 2.0;

    return Matrix4.identity()
      ..translateByDouble(clampedTx, clampedTy, 0.0, 1.0)
      ..scaleByDouble(s, s, 1.0, 1.0);
  }

  // -- Brightness gesture handlers --
  bool _canStartEdgeSwipe() =>
      widget.isActive && !_isZoomed && _activeTouchPointers.length <= 1;

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
    _brightnessClaim?.abort();
    _handleBrightnessDragCancel();
  }

  void _handleBrightnessDragStart(DragStartDetails details) {
    if (!_canStartEdgeSwipe()) return;
    widget.onZoomChanged(false); // Locks scroll physics so the page cannot swipe
    _isBrightnessDragging = true;
    _brightnessLevel = ScreenBrightnessBridge.lastKnownLevel;
    _brightnessHudTimer?.cancel();
    setState(() => _showBrightnessHud = true);
  }

  void _handleBrightnessDragUpdate(DragUpdateDetails details) {
    if (!_isBrightnessDragging) return;
    if (_activeTouchPointers.length > 1) {
      _abortEdgeGestures();
      return;
    }
    final dy = details.primaryDelta ?? details.delta.dy;
    final delta = -dy; // Dragging upward increases brightness
    final change = delta / MediaViewerConstants.edgeSwipeFullRangeDistance;
    final newLevel = (_brightnessLevel + change).clamp(0.0, 1.0);
    if ((newLevel - _brightnessLevel).abs() < 0.002) return;
    setState(() => _brightnessLevel = newLevel);
    unawaited(ScreenBrightnessBridge.setBrightness(newLevel));
  }

 void _handleBrightnessDragEnd(DragEndDetails details) {
    if (_isBrightnessDragging) {
      _isBrightnessDragging = false;
      widget.onZoomChanged(!_isZoomed); // Restores scroll physics only if not zoomed
      _hideBrightnessHudSoon();
    }
  }

  void _handleBrightnessDragCancel() {
    if (_isBrightnessDragging) {
      _isBrightnessDragging = false;
      widget.onZoomChanged(!_isZoomed); // Restores scroll physics only if not zoomed
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

  Widget _edgeSwipeStrip({
    required void Function(EdgeSwipeClaimRecognizer) onClaimCreated,
    required GestureDragStartCallback onDragStart,
    required GestureDragUpdateCallback onDragUpdate,
    required GestureDragEndCallback onDragEnd,
    required VoidCallback onDragCancel,
  }) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        EdgeSwipeClaimRecognizer:
            GestureRecognizerFactoryWithHandlers<EdgeSwipeClaimRecognizer>(
              () {
                final recognizer = EdgeSwipeClaimRecognizer(
                  canClaim: _canStartEdgeSwipe,
                );
                onClaimCreated(recognizer);
                return recognizer;
              },
              (recognizer) {
                recognizer
                  ..onStart = onDragStart
                  ..onUpdate = onDragUpdate
                  ..onEnd = onDragEnd
                  ..onCancel = onDragCancel;
              },
            ),
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        child: const SizedBox.expand(),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onGlobalPointerDown,
      onPointerUp: _onGlobalPointerUp,
      onPointerCancel: _onGlobalPointerUp,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final viewportHeight = constraints.maxHeight;

          double? rawAr;
          if (_imageSize != null && _imageSize!.height > 0) {
            rawAr = _imageSize!.width / _imageSize!.height;
          } else {
            rawAr = MediaAspectRatioCache.get(widget.container, widget.fileName);
          }

          double? childWidth;
          double? childHeight;
          double? canvasWidth;
          double? canvasHeight;
          bool isConstrained = true;

          if (rawAr != null && rawAr > 0 && viewportWidth > 0 && viewportHeight > 0) {
            final isRotated = widget.rotationQuarterTurns % 2 != 0;
            final ar = isRotated ? (1.0 / rawAr) : rawAr;

            if (widget.imageFit == BoxFit.fitWidth) {
              childWidth = viewportWidth;
              childHeight = viewportWidth / ar;
              isConstrained = false;
            } else if (widget.imageFit == BoxFit.fitHeight) {
              childHeight = viewportHeight;
              childWidth = viewportHeight * ar;
              isConstrained = false;
            } else {
              // BoxFit.contain: calculate exact image boundaries so Hero only wraps the actual image
              if ((viewportWidth / viewportHeight) > ar) {
                childHeight = viewportHeight;
                childWidth = viewportHeight * ar;
              } else {
                childWidth = viewportWidth;
                childHeight = viewportWidth / ar;
              }
            }

            canvasWidth = max(viewportWidth, childWidth);
            canvasHeight = max(viewportHeight, childHeight);

            final viewportSize = Size(viewportWidth, viewportHeight);
            if (_lastFit != widget.imageFit ||
                _lastRotation != widget.rotationQuarterTurns ||
                _lastViewportSize != viewportSize) {
              _lastFit = widget.imageFit;
              _lastRotation = widget.rotationQuarterTurns;
              _lastViewportSize = viewportSize;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _centerImageInitially(constraints);
                }
              });
            }
          }

          Widget imageContent = Center(
            child: SizedBox(
              width: childWidth,
              height: childHeight,
              child: Hero(
                tag: 'media_hero_${widget.container.volId}_${widget.fileName}',
                createRectTween: (begin, end) => MaterialRectArcTween(begin: begin, end: end),
                child: Material(
                  type: MaterialType.transparency,
                  child: RotatedBox(
                    quarterTurns: widget.rotationQuarterTurns,
                    child: EncryptedImageWidget(
                      container: widget.container,
                      fileName: widget.fileName,
                      prefetchedBytes: widget.prefetchedBytes,
                      fit: BoxFit.contain,
                      onError: widget.onError,
                      thumbnailQuality: widget.thumbnailQuality,
                      thumbnailCacheMode: widget.thumbnailCacheMode,
                    ),
                  ),
                ),
              ),
            ),
          );

          final Widget coreImageWidget = !widget.enableZoom
              ? GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => widget.onToggleUI(!widget.showUI),
                  child: SizedBox.expand(
                    child: imageContent,
                  ),
                )
              : GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => widget.onToggleUI(!widget.showUI),
                  onDoubleTapDown: (d) => _doubleTapDetails = d,
                  onDoubleTap: () {
                    // Strict live evaluation: reset if not at default 1.0x baseline
                    if (_isZoomed) {
                      final baselineMatrix = _getBaselineMatrix(constraints);
                      _animateImageZoomTo(baselineMatrix, toBaseline: true);
                      return;
                    }

                    final position = _doubleTapDetails?.localPosition;
                    if (position != null && childWidth != null && childHeight != null) {
                      final imageLeft = (viewportWidth - childWidth!) / 2;
                      final imageTop = (viewportHeight - childHeight!) / 2;
                      final imageRect = Rect.fromLTWH(imageLeft, imageTop, childWidth!, childHeight!);
                      if (!imageRect.contains(position)) {
                        // In black-out area at default zoom; do not zoom in
                        return;
                      }
                    }

                    const targetScale = 3.5;
                    final Matrix4 targetMatrix;
                    if (position != null) {
                      final x = -position.dx * (targetScale - 1);
                      final y = -position.dy * (targetScale - 1);
                      targetMatrix = Matrix4.identity()
                        ..translateByDouble(x, y, 0.0, 1.0)
                        ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
                    } else {
                      targetMatrix = Matrix4.identity()
                        ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
                    }

                    final cW = canvasWidth ?? viewportWidth;
                    final cH = canvasHeight ?? viewportHeight;
                    final clampedMatrix = _clampImageMatrix(
                      matrix: targetMatrix,
                      vw: viewportWidth,
                      vh: viewportHeight,
                      cW: cW,
                      cH: cH,
                    );

                    widget.onZoomChanged(false);
                    _animateImageZoomTo(clampedMatrix, toBaseline: false);
                  },
                  child: SizedBox.expand(
                    child: Builder(
                      builder: (context) {
                        _activeCanvasWidth = canvasWidth;
                        _activeCanvasHeight = canvasHeight;
                        return InteractiveViewer(
                          transformationController: _transformationController,
                          maxScale: MediaViewerConstants.maxImageZoom,
                          minScale: _effectiveMinZoomScale,
                          interactionEndFrictionCoefficient: 0.0005,
                          boundaryMargin: widget.pinchZoomOutEnabled
                              ? const EdgeInsets.all(double.infinity)
                              : EdgeInsets.zero,
                          constrained: isConstrained,
                          panEnabled: _isZoomedIn,
                    onInteractionStart: (details) {
                            if (details.pointerCount >= 2) {
                              _zoomAnimationController?.stop();
                            }
                            widget.onZoomChanged(false);
                          },
                         onInteractionUpdate: (details) {
                            final s = _getMatrixScale(_transformationController.value);
                            if (s != _scale) {
                              _scale = s;
                            }
                          },
                         onInteractionEnd: (details) {
                            final s = _getMatrixScale(_transformationController.value);
                            final clampedS = s.clamp(_effectiveMinZoomScale, MediaViewerConstants.maxImageZoom);
                            if (clampedS < 1.0 && viewportWidth > 0 && viewportHeight > 0) {
                              final cW = canvasWidth ?? viewportWidth;
                              final cH = canvasHeight ?? viewportHeight;
                              final dx = (viewportWidth - cW * clampedS) / 2.0;
                              final dy = (viewportHeight - cH * clampedS) / 2.0;
                              _isClampingMatrix = true;
                              _transformationController.value = Matrix4.identity()
                                ..translateByDouble(dx, dy, 0.0, 1.0)
                                ..scaleByDouble(clampedS, clampedS, clampedS, 1.0);
                              _isClampingMatrix = false;
                            }
                            setState(() {
                              _scale = _getMatrixScale(_transformationController.value);
                            });
                            widget.onZoomChanged(!_isZoomed);
                          },
                          child: SizedBox(
                            width: canvasWidth,
                            height: canvasHeight,
                            child: imageContent,
                          ),
                        );
                      },
                    ),
                  ),
                );

          final rawEdgeWidth = viewportWidth * widget.edgeSwipeWidthFraction;
          final edgeWidth = rawEdgeWidth.clamp(
            viewportWidth * MediaViewerConstants.edgeSwipeWidthMin,
            viewportWidth * MediaViewerConstants.edgeSwipeWidthMax,
          );

          return ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                coreImageWidget,
                if (widget.edgeSwipeBrightnessEnabled)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: edgeWidth,
                    child: _edgeSwipeStrip(
                      onClaimCreated: (r) => _brightnessClaim = r,
                      onDragStart: _handleBrightnessDragStart,
                      onDragUpdate: _handleBrightnessDragUpdate,
                      onDragEnd: _handleBrightnessDragEnd,
                      onDragCancel: _handleBrightnessDragCancel,
                    ),
                  ),
                if (widget.edgeSwipeHudEnabled && _showBrightnessHud)
                  _buildEdgeGestureHud(
                    isLeft: true,
                    icon: Icons.wb_sunny_rounded,
                    level: _brightnessLevel,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}