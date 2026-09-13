import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';

abstract class EditAnnotation {
  void paint(Canvas canvas, Size size);

  /// Returns true if [normalizedPoint] hits this annotation on an image of [size].
  bool contains(Offset normalizedPoint, Size size) => false;

  /// Returns a new instance moved by [normalizedDelta].
  EditAnnotation translate(Offset normalizedDelta, Size size) => this;

  /// Bounding rectangle in image-pixel coordinates for showing selection handles.
  Rect? getBounds(Size size) => null;
}

/// A solid or colored rectangle used to black out sensitive data.
class RedactAnnotation extends EditAnnotation {
  final Rect rect; // normalized 0.0 .. 1.0
  final Color color;

  RedactAnnotation({
    required this.rect,
    this.color = Colors.black,
  });

  RedactAnnotation copyWith({Rect? rect, Color? color}) {
    return RedactAnnotation(
      rect: rect ?? this.rect,
      color: color ?? this.color,
    );
  }

  @override
  Rect getBounds(Size size) {
    return Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );
  }

  @override
  bool contains(Offset normalizedPoint, Size size) {
    return rect.inflate(0.02).contains(normalizedPoint);
  }

  @override
  EditAnnotation translate(Offset normalizedDelta, Size size) {
    final shifted = rect.shift(normalizedDelta);
    final clamped = Rect.fromLTRB(
      shifted.left.clamp(0.0, 1.0 - shifted.width),
      shifted.top.clamp(0.0, 1.0 - shifted.height),
      shifted.right.clamp(shifted.width, 1.0),
      shifted.bottom.clamp(shifted.height, 1.0),
    );
    return copyWith(rect: clamped);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pixelRect = getBounds(size);
    canvas.drawRect(
      pixelRect,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }
}

/// Type alias so both `RedactAnnotation` and `RedactionAnnotation` resolve.
typedef RedactionAnnotation = RedactAnnotation;

/// A text label placed at [position] on the image.
class TextMarkAnnotation extends EditAnnotation {
  final Offset position; // normalized 0.0 .. 1.0
  final String text;
  final Color color;
  final double fontSizeFraction;

  TextMarkAnnotation({
    required this.position,
    required this.text,
    required this.color,
    required this.fontSizeFraction,
  });

  TextMarkAnnotation copyWith({
    Offset? position,
    String? text,
    Color? color,
    double? fontSizeFraction,
  }) {
    return TextMarkAnnotation(
      position: position ?? this.position,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSizeFraction: fontSizeFraction ?? this.fontSizeFraction,
    );
  }

  @override
  Rect getBounds(Size size) {
    final fontSize = size.height * fontSizeFraction;
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final px = position.dx * size.width;
    final py = position.dy * size.height;
    return Rect.fromLTWH(px, py, textPainter.width, textPainter.height);
  }

  @override
  bool contains(Offset normalizedPoint, Size size) {
    final bounds = getBounds(size);
    final touch = Offset(
      normalizedPoint.dx * size.width,
      normalizedPoint.dy * size.height,
    );
    return bounds.inflate(16.0).contains(touch);
  }

  @override
  EditAnnotation translate(Offset normalizedDelta, Size size) {
    final newPos = Offset(
      (position.dx + normalizedDelta.dx).clamp(0.0, 1.0),
      (position.dy + normalizedDelta.dy).clamp(0.0, 1.0),
    );
    return copyWith(position: newPos);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fontSize = size.height * fontSizeFraction;
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(1, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(position.dx * size.width, position.dy * size.height),
    );
  }
}

/// Freehand drawing stroke annotation.
class DrawingAnnotation extends EditAnnotation {
  final List<Offset> points; // normalized 0.0 .. 1.0
  final Color color;
  final double strokeWidthFraction;

  DrawingAnnotation({
    required this.points,
    required this.color,
    required this.strokeWidthFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final strokeWidth = size.height * strokeWidthFraction;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      final p = Offset(
        points.first.dx * size.width,
        points.first.dy * size.height,
      );
      canvas.drawCircle(p, strokeWidth / 2, paint..style = PaintingStyle.fill);
      return;
    }

    final path = Path();
    final first = Offset(
      points.first.dx * size.width,
      points.first.dy * size.height,
    );
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < points.length; i++) {
      final pt = Offset(
        points[i].dx * size.width,
        points[i].dy * size.height,
      );
      path.lineTo(pt.dx, pt.dy);
    }

    canvas.drawPath(path, paint);
  }
}

typedef PenStrokeAnnotation = DrawingAnnotation;
typedef StrokeAnnotation = DrawingAnnotation;