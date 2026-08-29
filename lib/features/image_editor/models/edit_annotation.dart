import 'package:material_ui/material_ui.dart';

/// A single user-added mark drawn on top of the image editor's current
/// working image.
///
/// Every geometric field here is stored as a *fraction* of the working
/// image's own width/height (0.0-1.0), never as raw on-screen pixels.
/// That's what lets the exact same annotation be painted correctly both
/// live, at whatever size the preview widget happens to be laid out at,
/// and again later at the image's full pixel resolution when pending
/// annotations are flattened into the working image for crop, rotate, or
/// save -- without either step needing to know about the other's scale.
sealed class EditAnnotation {
  const EditAnnotation();

  /// Paints this annotation into [canvas], scaled to [targetSize] -- the
  /// size (in whatever unit [canvas] is using) of the image this
  /// annotation sits on top of.
  void paint(Canvas canvas, Size targetSize);
}

/// A freehand pen stroke, drawn as one continuous path through [points].
class FreehandStrokeAnnotation extends EditAnnotation {
  final List<Offset> points;
  final Color color;

  /// Stroke width as a fraction of the image width, so thickness stays
  /// visually consistent whether painted at preview or full resolution.
  final double strokeWidthFraction;

  const FreehandStrokeAnnotation({
    required this.points,
    required this.color,
    required this.strokeWidthFraction,
  });

  @override
  void paint(Canvas canvas, Size targetSize) {
    final width = strokeWidthFraction * targetSize.width;
    if (points.length < 2) {
      if (points.isEmpty) return;
      // A tap without a drag still leaves a visible dot rather than
      // silently vanishing.
      canvas.drawCircle(
        Offset(points.first.dx * targetSize.width, points.first.dy * targetSize.height),
        width / 2,
        Paint()..color = color,
      );
      return;
    }
    final path = Path()
      ..moveTo(points.first.dx * targetSize.width, points.first.dy * targetSize.height);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx * targetSize.width, p.dy * targetSize.height);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
}

/// A solid blackout box, for hiding sensitive details (a document number,
/// a face, a barcode) before the image ever leaves the vault.
class RedactAnnotation extends EditAnnotation {
  /// Normalized rect: left/top/right/bottom each in [0,1].
  final Rect rect;
  final Color color;

  const RedactAnnotation({required this.rect, this.color = Colors.black});

  @override
  void paint(Canvas canvas, Size targetSize) {
    final scaled = Rect.fromLTRB(
      rect.left * targetSize.width,
      rect.top * targetSize.height,
      rect.right * targetSize.width,
      rect.bottom * targetSize.height,
    );
    canvas.drawRect(scaled, Paint()..color = color);
  }
}

/// A short text label placed at a tapped point.
class TextMarkAnnotation extends EditAnnotation {
  /// Normalized top-left anchor, in [0,1].
  final Offset position;
  final String text;
  final Color color;

  /// Font size as a fraction of the image width, for the same
  /// resolution-independence reason as [FreehandStrokeAnnotation].
  final double fontSizeFraction;

  const TextMarkAnnotation({
    required this.position,
    required this.text,
    required this.color,
    required this.fontSizeFraction,
  });

  @override
  void paint(Canvas canvas, Size targetSize) {
    final fontSize = fontSizeFraction * targetSize.width;
    final origin = Offset(position.dx * targetSize.width, position.dy * targetSize.height);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: fontSize * 0.18,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: (targetSize.width - origin.dx).clamp(1.0, targetSize.width).toDouble());
    painter.paint(canvas, origin);
  }
}

/// The small, fixed palette offered for pen/redact/text colors. Kept short
/// and high-contrast on purpose -- this is a quick markup tool, not a
/// full color picker.
const List<Color> editorColorPalette = [
  Colors.black,
  Colors.white,
  Color(0xFFEF4444), // red
  Color(0xFFF59E0B), // amber
  Color(0xFF22C55E), // green
  Color(0xFF3B82F6), // blue
  Color(0xFFA855F7), // purple
];

/// The stroke-width presets offered for the pen and redact-box border-free
/// fill; expressed as a fraction of the image width (see
/// [FreehandStrokeAnnotation.strokeWidthFraction]).
const List<double> editorStrokeWidthFractions = [0.004, 0.010, 0.020];
