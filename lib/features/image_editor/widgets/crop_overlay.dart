import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';

enum _CropHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

/// Interactive crop rectangle drawn on top of the image editor's preview.
///
/// This widget must be sized to exactly match the displayed image (the
/// caller sizes its parent to [imageSize] via a [SizedBox]/[Positioned]);
/// every coordinate here -- the current rect, drag deltas, handle
/// positions -- lives in that same local space, never normalized. The
/// image editor screen is the one that later converts the committed rect
/// into a fraction of the working image's pixel size.
class CropOverlay extends StatelessWidget {
  final Size imageSize;

  /// The current crop rect, in the same coordinate space as [imageSize].
  /// Read live and written to on every drag; the caller reads
  /// [rectNotifier.value] when the user taps "Apply crop".
  final ValueNotifier<Rect> rectNotifier;

  /// Locked width/height ratio, or null for a free-form crop.
  final double? aspectRatio;

  /// Rotation angle of the underlying image in radians.
  final double angleRad;

  /// Callback when user drags horizontally on the scrim background (outside
  /// the crop box) to rotate the image.
  final ValueChanged<double>? onAngleDelta;

  static const double _minSize = 40;
  static const double _cornerHitSize = 52;
  static const double _edgeHitSize = 48;

  const CropOverlay({
    super.key,
    required this.imageSize,
    required this.rectNotifier,
    this.aspectRatio,
    this.angleRad = 0.0,
    this.onAngleDelta,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Rect>(
      valueListenable: rectNotifier,
      builder: (context, rect, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  onAngleDelta?.call(details.primaryDelta ?? 0.0);
                },
                child: CustomPaint(
                  painter: _CropScrimPainter(rect: rect, bounds: imageSize),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: rect,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) =>
                    rectNotifier.value = _moveRect(rect, details.delta, imageSize, angleRad),
                child: const SizedBox.expand(),
              ),
            ),
            for (final handle in _CropHandle.values)
              if (_shouldShowHandle(handle, rect))
                _buildHandle(handle, rect),
          ],
        );
      },
    );
  }

  bool _shouldShowHandle(_CropHandle handle, Rect rect) {
    if (handle == _CropHandle.top || handle == _CropHandle.bottom) {
      return rect.width >= 64;
    }
    if (handle == _CropHandle.left || handle == _CropHandle.right) {
      return rect.height >= 64;
    }
    return true;
  }

  Widget _buildHandle(_CropHandle handle, Rect rect) {
    final Offset point;
    final double hitWidth;
    final double hitHeight;

    switch (handle) {
      case _CropHandle.topLeft:
        point = rect.topLeft;
        hitWidth = _cornerHitSize;
        hitHeight = _cornerHitSize;
      case _CropHandle.topRight:
        point = rect.topRight;
        hitWidth = _cornerHitSize;
        hitHeight = _cornerHitSize;
      case _CropHandle.bottomLeft:
        point = rect.bottomLeft;
        hitWidth = _cornerHitSize;
        hitHeight = _cornerHitSize;
      case _CropHandle.bottomRight:
        point = rect.bottomRight;
        hitWidth = _cornerHitSize;
        hitHeight = _cornerHitSize;
      case _CropHandle.top:
        point = rect.topCenter;
        hitWidth = 64;
        hitHeight = _edgeHitSize;
      case _CropHandle.bottom:
        point = rect.bottomCenter;
        hitWidth = 64;
        hitHeight = _edgeHitSize;
      case _CropHandle.left:
        point = rect.centerLeft;
        hitWidth = _edgeHitSize;
        hitHeight = 64;
      case _CropHandle.right:
        point = rect.centerRight;
        hitWidth = _edgeHitSize;
        hitHeight = 64;
    }

    return Positioned(
      left: point.dx - hitWidth / 2,
      top: point.dy - hitHeight / 2,
      width: hitWidth,
      height: hitHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          rectNotifier.value = _resizeFromHandle(
            rect: rectNotifier.value,
            handle: handle,
            delta: details.delta,
            aspectRatio: aspectRatio,
            imageSize: imageSize,
            angleRad: angleRad,
          );
        },
        child: const SizedBox.expand(),
      ),
    );
  }

  static Rect _moveRect(Rect rect, Offset delta, Size imageSize, double angleRad) {
    final nextCenter = rect.center + delta;
    final w = rect.width;
    final h = rect.height;
    final W = imageSize.width;
    final H = imageSize.height;

    final cosA = math.cos(angleRad.abs());
    final sinA = math.sin(angleRad.abs());

    // Half-spans of the upright rectangle along rotated image axes U and V
    final spanU = (w / 2.0) * cosA + (h / 2.0) * sinA;
    final spanV = (w / 2.0) * sinA + (h / 2.0) * cosA;

    final limitU = math.max(0.0, W / 2.0 - spanU);
    final limitV = math.max(0.0, H / 2.0 - spanV);

    // Center relative to image center
    final cx = nextCenter.dx - W / 2.0;
    final cy = nextCenter.dy - H / 2.0;

    // Transform center to rotated image frame (rotate by -angleRad)
    final cosT = math.cos(angleRad);
    final sinT = math.sin(angleRad);
    final u = cx * cosT + cy * sinT;
    final v = -cx * sinT + cy * cosT;

    final clampedU = u.clamp(-limitU, limitU);
    final clampedV = v.clamp(-limitV, limitV);

    // Transform back to canvas frame (rotate by +angleRad)
    final clampedCx = clampedU * cosT - clampedV * sinT;
    final clampedCy = clampedU * sinT + clampedV * cosT;

    return Rect.fromCenter(
      center: Offset(W / 2.0 + clampedCx, H / 2.0 + clampedCy),
      width: w,
      height: h,
    );
  }

  static Rect _resizeFromHandle({
    required Rect rect,
    required _CropHandle handle,
    required Offset delta,
    required double? aspectRatio,
    required Size imageSize,
    required double angleRad,
  }) {
    double left = rect.left;
    double top = rect.top;
    double right = rect.right;
    double bottom = rect.bottom;

    switch (handle) {
      case _CropHandle.topLeft:
        left += delta.dx;
        top += delta.dy;
      case _CropHandle.topRight:
        right += delta.dx;
        top += delta.dy;
      case _CropHandle.bottomLeft:
        left += delta.dx;
        bottom += delta.dy;
      case _CropHandle.bottomRight:
        right += delta.dx;
        bottom += delta.dy;
      case _CropHandle.top:
        top += delta.dy;
      case _CropHandle.bottom:
        bottom += delta.dy;
      case _CropHandle.left:
        left += delta.dx;
      case _CropHandle.right:
        right += delta.dx;
    }

    final bool movesLeft = handle == _CropHandle.topLeft ||
        handle == _CropHandle.bottomLeft ||
        handle == _CropHandle.left;
    final bool movesRight = handle == _CropHandle.topRight ||
        handle == _CropHandle.bottomRight ||
        handle == _CropHandle.right;
    final bool movesTop = handle == _CropHandle.topLeft ||
        handle == _CropHandle.topRight ||
        handle == _CropHandle.top;
    final bool movesBottom = handle == _CropHandle.bottomLeft ||
        handle == _CropHandle.bottomRight ||
        handle == _CropHandle.bottom;

    if (movesLeft && right - left < _minSize) left = right - _minSize;
    if (movesRight && right - left < _minSize) right = left + _minSize;
    if (movesTop && bottom - top < _minSize) top = bottom - _minSize;
    if (movesBottom && bottom - top < _minSize) bottom = top + _minSize;

    if (aspectRatio != null && aspectRatio > 0) {
      if (handle == _CropHandle.top || handle == _CropHandle.bottom) {
        final height = bottom - top;
        final width = height * aspectRatio;
        final centerX = (left + right) / 2.0;
        left = centerX - width / 2.0;
        right = centerX + width / 2.0;
      } else if (handle == _CropHandle.left || handle == _CropHandle.right) {
        final width = right - left;
        final height = width / aspectRatio;
        final centerY = (top + bottom) / 2.0;
        top = centerY - height / 2.0;
        bottom = centerY + height / 2.0;
      } else {
        final fixedLeft = handle == _CropHandle.topRight || handle == _CropHandle.bottomRight;
        final fixedTop = handle == _CropHandle.bottomLeft || handle == _CropHandle.bottomRight;
        final anchorX = fixedLeft ? left : right;
        final anchorY = fixedTop ? top : bottom;
        var width = (right - left).abs();
        var height = width / aspectRatio;
        if (width < _minSize) {
          width = _minSize;
          height = width / aspectRatio;
        }
        if (height < _minSize) {
          height = _minSize;
          width = height * aspectRatio;
        }
        left = fixedLeft ? anchorX : anchorX - width;
        right = fixedLeft ? anchorX + width : anchorX;
        top = fixedTop ? anchorY : anchorY - height;
        bottom = fixedTop ? anchorY + height : anchorY;
      }
    }

    final W = imageSize.width;
    final H = imageSize.height;
    final cosA = math.cos(angleRad.abs());
    final sinA = math.sin(angleRad.abs());

    var curW = (right - left).abs().clamp(_minSize, W).toDouble();
    var curH = (bottom - top).abs().clamp(_minSize, H).toDouble();

    // Check maximum possible dimensions at this angle
    if (aspectRatio != null && aspectRatio > 0) {
      final denomU = aspectRatio * cosA + sinA;
      final denomV = aspectRatio * sinA + cosA;
      final maxH = math.min(W / denomU, H / denomV);
      final maxW = aspectRatio * maxH;
      if (curH > maxH) {
        curH = maxH;
        curW = maxW;
      }
      if (curW > maxW) {
        curW = maxW;
        curH = curW / aspectRatio;
      }
    } else {
      final spanU = curW * cosA + curH * sinA;
      final spanV = curW * sinA + curH * cosA;
      if (spanU > W || spanV > H) {
        final factor = math.min(W / spanU, H / spanV);
        curW = math.max(_minSize, curW * factor);
        curH = math.max(_minSize, curH * factor);
      }
    }

    // Clamp center using (u, v) rotated frame projection
    final candidateCenter = Offset((left + right) / 2.0, (top + bottom) / 2.0);
    final spanU = (curW / 2.0) * cosA + (curH / 2.0) * sinA;
    final spanV = (curW / 2.0) * sinA + (curH / 2.0) * cosA;
    final limitU = math.max(0.0, W / 2.0 - spanU);
    final limitV = math.max(0.0, H / 2.0 - spanV);

    final cx = candidateCenter.dx - W / 2.0;
    final cy = candidateCenter.dy - H / 2.0;

    final cosT = math.cos(angleRad);
    final sinT = math.sin(angleRad);
    final u = cx * cosT + cy * sinT;
    final v = -cx * sinT + cy * cosT;

    final clampedU = u.clamp(-limitU, limitU);
    final clampedV = v.clamp(-limitV, limitV);

    final clampedCx = clampedU * cosT - clampedV * sinT;
    final clampedCy = clampedU * sinT + clampedV * cosT;

    return Rect.fromCenter(
      center: Offset(W / 2.0 + clampedCx, H / 2.0 + clampedCy),
      width: curW,
      height: curH,
    );
  }
}

class _CropScrimPainter extends CustomPainter {
  final Rect rect;
  final Size bounds;

  _CropScrimPainter({required this.rect, required this.bounds});

  @override
  void paint(Canvas canvas, Size size) {
    final maxDim = math.max(bounds.width, bounds.height) * 3.0;
    final center = Offset(bounds.width / 2.0, bounds.height / 2.0);
    final full = Rect.fromCenter(center: center, width: maxDim, height: maxDim);
    final scrimPath = Path()
      ..addRect(full)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // Bounding crop rectangle
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Rule of thirds grid
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }

    // Bold corner accents
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square;
    const cornerLen = 18.0;
    final cl = math.min(cornerLen, math.min(rect.width, rect.height) / 3);

    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(cl, 0), cornerPaint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, cl), cornerPaint);
    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight - Offset(cl, 0), cornerPaint);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, cl), cornerPaint);
    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + Offset(cl, 0), cornerPaint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft - Offset(0, cl), cornerPaint);
    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight - Offset(cl, 0), cornerPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight - Offset(0, cl), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _CropScrimPainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.bounds != bounds;
}
