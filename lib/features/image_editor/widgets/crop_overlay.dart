import 'package:material_ui/material_ui.dart';

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

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
  static const double _handleHitSize = 44;
  static const double _handleVisualSize = 18;

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
                child: CustomPaint(painter: _CropScrimPainter(rect: rect, bounds: imageSize)),
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
            for (final corner in _Corner.values)
              _buildHandle(corner, rect),
          ],
        );
      },
    );
  }

  Widget _buildHandle(_Corner corner, Rect rect) {
    final point = switch (corner) {
      _Corner.topLeft => rect.topLeft,
      _Corner.topRight => rect.topRight,
      _Corner.bottomLeft => rect.bottomLeft,
      _Corner.bottomRight => rect.bottomRight,
    };
    return Positioned(
      left: point.dx - _handleHitSize / 2,
      top: point.dy - _handleHitSize / 2,
      width: _handleHitSize,
      height: _handleHitSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          rectNotifier.value = _resizeFromCorner(
            rect: rectNotifier.value,
            corner: corner,
            delta: details.delta,
            aspectRatio: aspectRatio,
            bounds: imageSize,
          );
        },
        child: Center(
          child: Container(
            width: _handleVisualSize,
            height: _handleVisualSize,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black.withValues(alpha: 0.35), width: 1),
            ),
          ),
        ),
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

  static Rect _resizeFromCorner({
    required Rect rect,
    required _Corner corner,
    required Offset delta,
    required double? aspectRatio,
    required Size bounds,
  }) {
    double left = rect.left, top = rect.top, right = rect.right, bottom = rect.bottom;
    switch (corner) {
      case _Corner.topLeft:
        left += delta.dx;
        top += delta.dy;
      case _Corner.topRight:
        right += delta.dx;
        top += delta.dy;
      case _Corner.bottomLeft:
        left += delta.dx;
        bottom += delta.dy;
      case _Corner.bottomRight:
        right += delta.dx;
        bottom += delta.dy;
    }

    left = left.clamp(0.0, bounds.width).toDouble();
    top = top.clamp(0.0, bounds.height).toDouble();
    right = right.clamp(0.0, bounds.width).toDouble();
    bottom = bottom.clamp(0.0, bounds.height).toDouble();

    // Whichever edges this corner doesn't own stay put; if the dragged
    // edges would cross them (or get too close), pull the dragged edge
    // back instead of letting the rectangle invert.
    final fixedLeft = corner == _Corner.topRight || corner == _Corner.bottomRight;
    final fixedRight = !fixedLeft;
    final fixedTop = corner == _Corner.bottomLeft || corner == _Corner.bottomRight;
    final fixedBottom = !fixedTop;

    if (fixedLeft && right - left < _minSize) right = left + _minSize;
    if (fixedRight && right - left < _minSize) left = right - _minSize;
    if (fixedTop && bottom - top < _minSize) bottom = top + _minSize;
    if (fixedBottom && bottom - top < _minSize) top = bottom - _minSize;

    var result = Rect.fromLTRB(left, top, right, bottom);

    if (aspectRatio != null && aspectRatio > 0) {
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
    canvas.drawPath(scrimPath, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropScrimPainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.bounds != bounds;
}
