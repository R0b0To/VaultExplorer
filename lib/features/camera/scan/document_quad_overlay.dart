import 'package:material_ui/material_ui.dart';

import 'scan_geometry.dart';

/// The live document outline drawn over the camera preview.
///
/// Lay it out in exactly the box the preview occupies (uncropped): the corners
/// arrive in the camera's upright "natural" frame and are turned for the
/// current display rotation here.
class DocumentQuadOverlay extends StatelessWidget {
  const DocumentQuadOverlay({
    super.key,
    required this.quad,
    required this.displayRotation,
  });

  final ValueNotifier<ScanQuad?> quad;
  final int displayRotation;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ScanQuad?>(
      valueListenable: quad,
      builder: (context, value, _) => CustomPaint(
        size: Size.infinite,
        painter: _QuadPainter(value, displayRotation),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.quad, this.displayRotation);

  final ScanQuad? quad;
  final int displayRotation;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad;
    if (q == null) return;
    final points = q.corners.map((c) {
      final d = cameraNaturalToDisplay(c, displayRotation);
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
      oldDelegate.quad != quad || oldDelegate.displayRotation != displayRotation;
}
