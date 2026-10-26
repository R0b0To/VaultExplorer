import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';

/// Interactive text overlay supporting 1-finger move, 2-finger pinch resize,
/// and 2-finger gesture rotation directly on the photo preview.
class TextOverlay extends StatefulWidget {
  final Size imageSize;
  final ValueNotifier<TextMarkAnnotation> textNotifier;
  final VoidCallback onDoubleTap;
  final List<TextMarkAnnotation> existingAnnotations;
  final ValueChanged<int>? onSelectExistingText;

  const TextOverlay({
    super.key,
    required this.imageSize,
    required this.textNotifier,
    required this.onDoubleTap,
    this.existingAnnotations = const [],
    this.onSelectExistingText,
  });

  @override
  State<TextOverlay> createState() => _TextOverlayState();
}

class _TextOverlayState extends State<TextOverlay> {
  double _startFontSizeFraction = 0.045;
  double _startRotation = 0.0;
  bool _isInteracting = false;
  double _lastSnappedAngle = 0.0;

  void _handleScaleStart(ScaleStartDetails details) {
    _startFontSizeFraction = widget.textNotifier.value.fontSizeFraction;
    _startRotation = widget.textNotifier.value.rotation;
    _lastSnappedAngle = _startRotation;
    setState(() => _isInteracting = true);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final imageSize = widget.imageSize;
    if (imageSize.width <= 0 || imageSize.height <= 0) return;

    // 1. Move position (pan / translation)
    final normDelta = Offset(
      details.focalPointDelta.dx / imageSize.width,
      details.focalPointDelta.dy / imageSize.height,
    );
    final cur = widget.textNotifier.value;
    final newPos = Offset(
      (cur.position.dx + normDelta.dx).clamp(0.02, 0.98),
      (cur.position.dy + normDelta.dy).clamp(0.02, 0.98),
    );

    // 2. Pinch scale (font size)
    double newFontSize = cur.fontSizeFraction;
    if (details.scale != 1.0) {
      newFontSize = (_startFontSizeFraction * details.scale).clamp(0.015, 0.35);
    }

    // 3. Rotation gesture
    double newRotation = cur.rotation;
    if (details.rotation != 0.0 || details.pointerCount >= 2) {
      var rawAngle = _startRotation + details.rotation;

      // Magnetic snap around 0, +/-90, +/-180 degrees within 2.5 degrees
      const snapThreshold = 2.5 * math.pi / 180.0;
      final snapPoints = [0.0, math.pi / 2, -math.pi / 2, math.pi, -math.pi];
      for (final snap in snapPoints) {
        if ((rawAngle - snap).abs() <= snapThreshold) {
          if (_lastSnappedAngle != snap && snap == 0.0) {
            HapticFeedback.selectionClick();
          }
          rawAngle = snap;
          break;
        }
      }
      _lastSnappedAngle = rawAngle;
      newRotation = rawAngle;
    }

    widget.textNotifier.value = cur.copyWith(
      position: newPos,
      fontSizeFraction: newFontSize,
      rotation: newRotation,
    );
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (mounted) {
      setState(() => _isInteracting = false);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.existingAnnotations.isNotEmpty) {
      final imageSize = widget.imageSize;
      if (imageSize.width > 0 && imageSize.height > 0) {
        final norm = Offset(
          (details.localPosition.dx / imageSize.width).clamp(0.0, 1.0),
          (details.localPosition.dy / imageSize.height).clamp(0.0, 1.0),
        );
        for (int i = widget.existingAnnotations.length - 1; i >= 0; i--) {
          if (widget.existingAnnotations[i].contains(norm, imageSize)) {
            widget.onSelectExistingText?.call(i);
            break;
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextMarkAnnotation>(
      valueListenable: widget.textNotifier,
      builder: (context, annotation, _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: widget.onDoubleTap,
          onTapUp: _handleTapUp,
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          onScaleEnd: _handleScaleEnd,
          child: CustomPaint(
            size: widget.imageSize,
            painter: _TextOverlayPainter(
              annotation: annotation,
              isInteracting: _isInteracting,
            ),
          ),
        );
      },
    );
  }
}

class _TextOverlayPainter extends CustomPainter {
  final TextMarkAnnotation annotation;
  final bool isInteracting;

  _TextOverlayPainter({
    required this.annotation,
    required this.isInteracting,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Draw subtle dashed guidelines around text
    final bounds = annotation.getBounds(size);
    final px = annotation.position.dx * size.width;
    final py = annotation.position.dy * size.height;

    canvas.save();
    canvas.translate(px, py);
    if (annotation.rotation != 0.0) {
      canvas.rotate(annotation.rotation);
    }

    final guidePaint = Paint()
      ..color = Colors.white.withValues(alpha: isInteracting ? 0.55 : 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final halfW = bounds.width / 2.0 + 12.0;
    final halfH = bounds.height / 2.0 + 8.0;
    const extend = 28.0;

    // Vertical guide lines extending past corners
    _drawDashedLine(
      canvas,
      Offset(-halfW, -halfH - extend),
      Offset(-halfW, halfH + extend),
      guidePaint,
    );
    _drawDashedLine(
      canvas,
      Offset(halfW, -halfH - extend),
      Offset(halfW, halfH + extend),
      guidePaint,
    );

    // Horizontal guide line passing through center
    _drawDashedLine(
      canvas,
      Offset(-halfW - extend, 0),
      Offset(halfW + extend, 0),
      guidePaint,
    );

    canvas.restore();

    // 2. Draw the text annotation
    annotation.paint(canvas, size);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint, {
    double dash = 6,
    double gap = 4,
  }) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0) return;
    final unitX = dx / dist;
    final unitY = dy / dist;
    double current = 0;
    while (current < dist) {
      final end = math.min(current + dash, dist);
      canvas.drawLine(
        Offset(p1.dx + unitX * current, p1.dy + unitY * current),
        Offset(p1.dx + unitX * end, p1.dy + unitY * end),
        paint,
      );
      current += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _TextOverlayPainter oldDelegate) =>
      oldDelegate.annotation != annotation ||
      oldDelegate.isInteracting != isInteracting;
}
