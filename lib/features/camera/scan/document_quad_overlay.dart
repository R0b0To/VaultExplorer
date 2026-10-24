import 'package:material_ui/material_ui.dart';

import 'scan_geometry.dart';

/// The live document outline drawn over the camera preview.
///
/// The corners arrive in the camera's upright "natural" frame. Turn them for
/// the current display rotation, then map them into the preview's centered crop.
class DocumentQuadOverlay extends StatelessWidget {
  const DocumentQuadOverlay({
    super.key,
    required this.quad,
    required this.displayRotation,
    required this.sourceAspectRatio,
    required this.frameAspectRatio,
  });

  final ValueNotifier<ScanQuad?> quad;
  final int displayRotation;
  final double sourceAspectRatio;
  final double frameAspectRatio;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScanQuad?>(
      valueListenable: quad,
      builder: (context, value, _) => CustomPaint(
        size: Size.infinite,
        painter: _QuadPainter(
          value,
          displayRotation,
          sourceAspectRatio,
          frameAspectRatio,
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(
    this.quad,
    this.displayRotation,
    this.sourceAspectRatio,
    this.frameAspectRatio,
  );

  final ScanQuad? quad;
  final int displayRotation;
  final double sourceAspectRatio;
  final double frameAspectRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad;
    if (q == null) return;
    final points = q.corners.map((c) {
      final displayPoint = cameraNaturalToDisplay(c, displayRotation);
      final d = cameraDisplayPointToAspectCrop(
        displayPoint,
        sourceAspectRatio: sourceAspectRatio,
        frameAspectRatio: frameAspectRatio,
      );
      return Offset(d.dx * size.width, d.dy * size.height);
    }).toList();

    final path = Path()..addPolygon(points, true);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.amber.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.amber,
    );
    final dot = Paint()..color = Colors.amber;
    for (final p in points) {
      canvas.drawCircle(p, 6, dot);
    }
  }

  @override
  bool shouldRepaint(_QuadPainter oldDelegate) =>
      oldDelegate.quad != quad ||
      oldDelegate.displayRotation != displayRotation ||
      oldDelegate.sourceAspectRatio != sourceAspectRatio ||
      oldDelegate.frameAspectRatio != frameAspectRatio;
}
