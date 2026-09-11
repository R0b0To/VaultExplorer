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

  static const double _minSize = 40;
  static const double _cornerHitSize = 52;
  static const double _cornerVisualSize = 22;
  static const double _edgeHitSize = 48;

  const CropOverlay({
    super.key,
    required this.imageSize,
    required this.rectNotifier,
    this.aspectRatio,
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
              child: IgnorePointer(
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
                    rectNotifier.value = _moveRect(rect, details.delta, imageSize),
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
          bounds: imageSize,
        );
      },
      // You don't necessarily need a circle widget here if the 
      // L-brackets are already drawn by _CropScrimPainter!
      child: const SizedBox.expand(),
    ),
  );
}

  Widget _buildCornerVisual() {
    return Container(
      width: _cornerVisualSize,
      height: _cornerVisualSize,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
        border: Border.all(color: Colors.black38, width: 1.5),
      ),
    );
  }

  Widget _buildHorizontalBarVisual() {
    return Container(
      width: 28,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
        border: Border.all(color: Colors.black38, width: 1),
      ),
    );
  }

  Widget _buildVerticalBarVisual() {
    return Container(
      width: 6,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
        border: Border.all(color: Colors.black38, width: 1),
      ),
    );
  }

  static Rect _moveRect(Rect rect, Offset delta, Size bounds) {
    var next = rect.translate(delta.dx, delta.dy);
    if (next.left < 0) next = next.translate(-next.left, 0);
    if (next.top < 0) next = next.translate(0, -next.top);
    if (next.right > bounds.width) next = next.translate(bounds.width - next.right, 0);
    if (next.bottom > bounds.height) next = next.translate(0, bounds.height - next.bottom);
    return next;
  }

  static Rect _resizeFromHandle({
    required Rect rect,
    required _CropHandle handle,
    required Offset delta,
    required double? aspectRatio,
    required Size bounds,
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

    left = left.clamp(0.0, bounds.width).toDouble();
    top = top.clamp(0.0, bounds.height).toDouble();
    right = right.clamp(0.0, bounds.width).toDouble();
    bottom = bottom.clamp(0.0, bounds.height).toDouble();

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

    var result = Rect.fromLTRB(left, top, right, bottom);

    if (aspectRatio != null && aspectRatio > 0) {
      if (handle == _CropHandle.top || handle == _CropHandle.bottom) {
        final height = result.height;
        var width = (height * aspectRatio).clamp(_minSize, bounds.width).toDouble();
        var newLeft = result.center.dx - width / 2;
        var newRight = result.center.dx + width / 2;
        if (newLeft < 0) {
          newRight += -newLeft;
          newLeft = 0;
        }
        if (newRight > bounds.width) {
          newLeft -= (newRight - bounds.width);
          newRight = bounds.width;
        }
        newLeft = newLeft.clamp(0.0, bounds.width - _minSize).toDouble();
        newRight = newRight.clamp(newLeft + _minSize, bounds.width).toDouble();
        result = Rect.fromLTRB(newLeft, result.top, newRight, result.bottom);
      } else if (handle == _CropHandle.left || handle == _CropHandle.right) {
        final width = result.width;
        var height = (width / aspectRatio).clamp(_minSize, bounds.height).toDouble();
        var newTop = result.center.dy - height / 2;
        var newBottom = result.center.dy + height / 2;
        if (newTop < 0) {
          newBottom += -newTop;
          newTop = 0;
        }
        if (newBottom > bounds.height) {
          newTop -= (newBottom - bounds.height);
          newBottom = bounds.height;
        }
        newTop = newTop.clamp(0.0, bounds.height - _minSize).toDouble();
        newBottom = newBottom.clamp(newTop + _minSize, bounds.height).toDouble();
        result = Rect.fromLTRB(result.left, newTop, result.right, newBottom);
      } else {
        final fixedLeft = handle == _CropHandle.topRight || handle == _CropHandle.bottomRight;
        final fixedTop = handle == _CropHandle.bottomLeft || handle == _CropHandle.bottomRight;

        final anchorX = fixedLeft ? result.left : result.right;
        final anchorY = fixedTop ? result.top : result.bottom;

        var width = result.width;
        var height = width / aspectRatio;

        final maxHeight = fixedTop ? bounds.height - anchorY : anchorY;
        if (height > maxHeight) {
          height = maxHeight;
          width = height * aspectRatio;
        }
        final maxWidth = fixedLeft ? bounds.width - anchorX : anchorX;
        if (width > maxWidth) {
          width = maxWidth;
          height = width / aspectRatio;
        }
        width = width < _minSize ? _minSize : width;
        height = height < _minSize ? _minSize : height;

        final newLeft = fixedLeft ? anchorX : anchorX - width;
        final newTop = fixedTop ? anchorY : anchorY - height;
        result = Rect.fromLTWH(newLeft, newTop, width, height);
      }
    }

    return result;
  }
}

class _CropScrimPainter extends CustomPainter {
  final Rect rect;
  final Size bounds;

  _CropScrimPainter({required this.rect, required this.bounds});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & bounds;
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
