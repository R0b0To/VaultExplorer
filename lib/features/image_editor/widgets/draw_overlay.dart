import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';

/// Interactive drawing overlay supporting 1-finger drawing and 2-finger zoom/pan.
///
/// Zooming scales the effective brush size inversely (drawing finer details when
/// zoomed in, broader strokes when zoomed out). A dashed brush indicator is
/// centered in the viewport representing the current on-screen stroke footprint,
/// visible only while zooming.
class DrawOverlay extends StatefulWidget {
  final Rect imageRect;
  final TransformationController transformationController;
  final Color color;
  final double opacity;
  final double strokeDiameter;
  final bool showBrushIndicator;
  final ValueChanged<DrawingAnnotation> onStrokeCompleted;
  final VoidCallback? onStrokeStart;
  final VoidCallback? onResetZoom;

  /// Default logical pixel diameter of the brush footprint on screen.
  static const double kDefaultBrushDiameter = 60.0;

  /// Backward-compatible alias for [kDefaultBrushDiameter].
  static const double kBrushScreenDiameter = kDefaultBrushDiameter;

  /// Maximum zoom scale allowed during drawing gestures (3000%).
  static const double kMaxZoomScale = 30.0;

  const DrawOverlay({
    super.key,
    required this.imageRect,
    required this.transformationController,
    required this.color,
    required this.opacity,
    this.strokeDiameter = kDefaultBrushDiameter,
    this.showBrushIndicator = false,
    required this.onStrokeCompleted,
    this.onStrokeStart,
    this.onResetZoom,
  });

  @override
  State<DrawOverlay> createState() => _DrawOverlayState();
}

class _DrawOverlayState extends State<DrawOverlay> {
  final Map<int, Offset> _activePointers = {};

  // For 2-finger pan & zoom
  double? _initialDistance;
  Matrix4? _initialMatrix;
  Offset? _initialFocalPoint;
  bool _isTwoFingerZooming = false;
  bool _isWheelZooming = false;
  Timer? _wheelZoomDismissTimer;

  bool get _isZooming => _isTwoFingerZooming || _isWheelZooming;

  // For 1-finger drawing
  final List<Offset> _liveStrokePoints = [];
  double _liveStrokeWidthFraction = 0.02;

  @override
  void dispose() {
    _wheelZoomDismissTimer?.cancel();
    super.dispose();
  }

  Offset? _toNormalizedPoint(Offset viewportPoint) {
    if (widget.imageRect.width <= 0 || widget.imageRect.height <= 0) return null;
    final scenePoint = widget.transformationController.toScene(viewportPoint);
    final dx = (scenePoint.dx - widget.imageRect.left) / widget.imageRect.width;
    final dy = (scenePoint.dy - widget.imageRect.top) / widget.imageRect.height;
    return Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
  }

  double _calculateStrokeWidthFraction() {
    final scale = widget.transformationController.value.getMaxScaleOnAxis();
    final h = widget.imageRect.height > 0 ? widget.imageRect.height : 1.0;
    return (widget.strokeDiameter / (h * scale)).clamp(0.00005, 0.5);
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;

    if (_activePointers.length == 1) {
      _isTwoFingerZooming = false;
      _liveStrokePoints.clear();
      _liveStrokeWidthFraction = _calculateStrokeWidthFraction();

      final pt = _toNormalizedPoint(event.localPosition);
      if (pt != null) {
        _liveStrokePoints.add(pt);
        widget.onStrokeStart?.call();
        setState(() {});
      }
    } else if (_activePointers.length >= 2) {
      _isTwoFingerZooming = true;
      if (_liveStrokePoints.isNotEmpty) {
        setState(() => _liveStrokePoints.clear());
      }
      final pts = _activePointers.values.toList();
      _initialDistance = (pts[0] - pts[1]).distance;
      _initialFocalPoint = (pts[0] + pts[1]) / 2.0;
      _initialMatrix = widget.transformationController.value.clone();
      setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.localPosition;

    if (_activePointers.length >= 2) {
      _isTwoFingerZooming = true;
      if (_liveStrokePoints.isNotEmpty) {
        setState(() => _liveStrokePoints.clear());
      }
      final pts = _activePointers.values.toList();
      final currentDistance = (pts[0] - pts[1]).distance;
      final currentFocalPoint = (pts[0] + pts[1]) / 2.0;

      if (_initialDistance != null &&
          _initialDistance! > 0 &&
          _initialMatrix != null &&
          _initialFocalPoint != null) {
        final scaleFactor = currentDistance / _initialDistance!;
        final initialScale = _initialMatrix!.getMaxScaleOnAxis();
        final newScale = (initialScale * scaleFactor).clamp(1.0, DrawOverlay.kMaxZoomScale);
        final effectiveRatio = newScale / initialScale;

        final matrix = _initialMatrix!.clone();
        final translation = matrix.getTranslation();
        final tx = translation.x;
        final ty = translation.y;

        final fx = _initialFocalPoint!.dx;
        final fy = _initialFocalPoint!.dy;
        final focalDelta = currentFocalPoint - _initialFocalPoint!;

        final newTx = fx + (tx - fx) * effectiveRatio + focalDelta.dx;
        final newTy = fy + (ty - fy) * effectiveRatio + focalDelta.dy;

        final box = context.findRenderObject() as RenderBox?;
        final overlayW = box?.size.width ?? widget.imageRect.width;
        final overlayH = box?.size.height ?? widget.imageRect.height;
        final scaledW = overlayW * newScale;
        final scaledH = overlayH * newScale;

        final clampedTx = newScale <= 1.0
            ? (overlayW - scaledW) / 2.0
            : newTx.clamp(overlayW - scaledW, 0.0);
        final clampedTy = newScale <= 1.0
            ? (overlayH - scaledH) / 2.0
            : newTy.clamp(overlayH - scaledH, 0.0);

        widget.transformationController.value =
            Matrix4.diagonal3Values(newScale, newScale, 1.0)
              ..setTranslationRaw(clampedTx, clampedTy, 0.0);

        setState(() {});
      }
    } else if (_activePointers.length == 1 && !_isTwoFingerZooming) {
      final pt = _toNormalizedPoint(event.localPosition);
      if (pt != null) {
        _liveStrokePoints.add(pt);
        setState(() {});
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);

    if (_activePointers.isEmpty) {
      if (_isTwoFingerZooming) {
        _isTwoFingerZooming = false;
        _initialDistance = null;
        _initialFocalPoint = null;
        _initialMatrix = null;
        setState(() {});
      } else if (_liveStrokePoints.isNotEmpty) {
        widget.onStrokeCompleted(
          DrawingAnnotation(
            points: List.unmodifiable(_liveStrokePoints),
            color: widget.color,
            opacity: widget.opacity,
            strokeWidthFraction: _liveStrokeWidthFraction,
          ),
        );
        _liveStrokePoints.clear();
        setState(() {});
      }
    } else if (_activePointers.length == 1) {
      _isTwoFingerZooming = true;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _isTwoFingerZooming = false;
      _liveStrokePoints.clear();
      setState(() {});
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final zoomDelta = event.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15;
      final currentScale = widget.transformationController.value.getMaxScaleOnAxis();
      final newScale = (currentScale * zoomDelta).clamp(1.0, DrawOverlay.kMaxZoomScale);
      if (newScale == currentScale) return;

      final ratio = newScale / currentScale;
      final focalPoint = event.localPosition;
      final matrix = widget.transformationController.value.clone();
      final translation = matrix.getTranslation();
      final tx = translation.x;
      final ty = translation.y;

      final newTx = focalPoint.dx + (tx - focalPoint.dx) * ratio;
      final newTy = focalPoint.dy + (ty - focalPoint.dy) * ratio;

      final box = context.findRenderObject() as RenderBox?;
      final overlayW = box?.size.width ?? widget.imageRect.width;
      final overlayH = box?.size.height ?? widget.imageRect.height;
      final scaledW = overlayW * newScale;
      final scaledH = overlayH * newScale;

      final clampedTx = newScale <= 1.0
          ? (overlayW - scaledW) / 2.0
          : newTx.clamp(overlayW - scaledW, 0.0);
      final clampedTy = newScale <= 1.0
          ? (overlayH - scaledH) / 2.0
          : newTy.clamp(overlayH - scaledH, 0.0);

      widget.transformationController.value =
          Matrix4.diagonal3Values(newScale, newScale, 1.0)
            ..setTranslationRaw(clampedTx, clampedTy, 0.0);

      _wheelZoomDismissTimer?.cancel();
      _isWheelZooming = true;
      _wheelZoomDismissTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _isWheelZooming = false;
          });
        }
      });
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerSignal: _onPointerSignal,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live stroke in progress
          if (_liveStrokePoints.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: _LiveStrokePainter(
                  points: _liveStrokePoints,
                  color: widget.color,
                  opacity: widget.opacity,
                  strokeWidthFraction: _liveStrokeWidthFraction,
                  imageRect: widget.imageRect,
                  matrix: widget.transformationController.value,
                ),
              ),
            ),

          // 2. Dashed circular brush ring in the center of the viewport
          // (visible while zooming, or when brush indicator is requested and no stroke is currently being drawn)
          if (_isZooming || (widget.showBrushIndicator && _liveStrokePoints.isEmpty))
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DashedBrushRingPainter(
                    radius: widget.strokeDiameter / 2.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveStrokePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double opacity;
  final double strokeWidthFraction;
  final Rect imageRect;
  final Matrix4 matrix;

  _LiveStrokePainter({
    required this.points,
    required this.color,
    required this.opacity,
    required this.strokeWidthFraction,
    required this.imageRect,
    required this.matrix,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || imageRect.width <= 0 || imageRect.height <= 0) return;

    canvas.save();
    canvas.transform(matrix.storage);
    canvas.translate(imageRect.left, imageRect.top);

    final strokeWidth = imageRect.height * strokeWidthFraction;
    final effectiveAlpha = (color.a * opacity).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = color.withValues(alpha: effectiveAlpha)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      final p = Offset(
        points.first.dx * imageRect.width,
        points.first.dy * imageRect.height,
      );
      canvas.drawCircle(p, strokeWidth / 2.0, paint..style = PaintingStyle.fill);
      canvas.restore();
      return;
    }

    final path = Path();
    final first = Offset(
      points.first.dx * imageRect.width,
      points.first.dy * imageRect.height,
    );
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < points.length; i++) {
      final pt = Offset(
        points[i].dx * imageRect.width,
        points[i].dy * imageRect.height,
      );
      path.lineTo(pt.dx, pt.dy);
    }

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiveStrokePainter oldDelegate) => true;
}

/// Dashed circular indicator showing the on-screen brush footprint.
class _DashedBrushRingPainter extends CustomPainter {
  final double radius;

  _DashedBrushRingPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2.0, size.height / 2.0);

    // Subtle dark shadow for contrast against bright images
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Crisp white dashed circular ring
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    const int dashCount = 26;
    const double sweepPerDash = (2 * math.pi) / dashCount;
    const double dashFraction = 0.55;

    final rect = Rect.fromCircle(center: center, radius: radius);
    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * sweepPerDash;
      final sweepAngle = sweepPerDash * dashFraction;

      // Dark shadow arc
      canvas.drawArc(
        rect.shift(const Offset(0.5, 0.5)),
        startAngle,
        sweepAngle,
        false,
        shadowPaint,
      );
      // White dash arc
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        false,
        dashPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBrushRingPainter oldDelegate) =>
      oldDelegate.radius != radius;
}
