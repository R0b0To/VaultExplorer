import 'dart:math' as math;

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

  RedactAnnotation({required this.rect, this.color = Colors.black});

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
      final pt = Offset(points[i].dx * size.width, points[i].dy * size.height);
      path.lineTo(pt.dx, pt.dy);
    }

    canvas.drawPath(path, paint);
  }
}

/// An opaque freehand mask used to redact information from an image.
///
/// It shares the drawing stroke renderer, but keeps a distinct type so the
/// editor can move redactions separately from ordinary pencil marks.
class RedactStrokeAnnotation extends DrawingAnnotation {
  RedactStrokeAnnotation({
    required super.points,
    required Color color,
    required super.strokeWidthFraction,
  }) : super(color: color.withValues(alpha: 1));

  @override
  Rect getBounds(Size size) {
    if (points.isEmpty) return Rect.zero;
    final pixels = points
        .map((point) => Offset(point.dx * size.width, point.dy * size.height))
        .toList(growable: false);
    var left = pixels.first.dx;
    var right = left;
    var top = pixels.first.dy;
    var bottom = top;
    for (final point in pixels.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(
      left,
      top,
      right,
      bottom,
    ).inflate(size.height * strokeWidthFraction / 2);
  }

  @override
  bool contains(Offset normalizedPoint, Size size) {
    if (points.isEmpty) return false;
    final point = Offset(
      normalizedPoint.dx * size.width,
      normalizedPoint.dy * size.height,
    );
    final pixels = points
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList(growable: false);
    final hitRadius = size.height * strokeWidthFraction / 2 + 12;
    if (pixels.length == 1) {
      return (point - pixels.single).distance <= hitRadius;
    }
    for (var i = 1; i < pixels.length; i++) {
      final start = pixels[i - 1];
      final end = pixels[i];
      final segment = end - start;
      final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
      final projection = lengthSquared == 0
          ? 0.0
          : (((point.dx - start.dx) * segment.dx +
                        (point.dy - start.dy) * segment.dy) /
                    lengthSquared)
                .clamp(0.0, 1.0)
                .toDouble();
      final closest = start + segment * projection;
      if ((point - closest).distance <= hitRadius) return true;
    }
    return false;
  }

  @override
  EditAnnotation translate(Offset normalizedDelta, Size size) {
    if (points.isEmpty) return this;
    var minX = points.first.dx;
    var maxX = minX;
    var minY = points.first.dy;
    var maxY = minY;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }
    final dx = normalizedDelta.dx.clamp(-minX, 1.0 - maxX).toDouble();
    final dy = normalizedDelta.dy.clamp(-minY, 1.0 - maxY).toDouble();
    return RedactStrokeAnnotation(
      points: points
          .map((point) => Offset(point.dx + dx, point.dy + dy))
          .toList(growable: false),
      color: color,
      strokeWidthFraction: strokeWidthFraction,
    );
  }
}

typedef PenStrokeAnnotation = DrawingAnnotation;
typedef StrokeAnnotation = DrawingAnnotation;
