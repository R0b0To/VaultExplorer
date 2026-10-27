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

/// A solid or colored rectangle used to black out sensitive data with rotation and scale support.
class RedactAnnotation extends EditAnnotation {
  final Rect rect; // normalized 0.0 .. 1.0 (unrotated bounds)
  final Color color;
  final double rotation; // in radians, 0.0 is unrotated

  RedactAnnotation({
    required this.rect,
    this.color = Colors.black,
    this.rotation = 0.0,
  });

  RedactAnnotation copyWith({
    Rect? rect,
    Color? color,
    double? rotation,
  }) {
    return RedactAnnotation(
      rect: rect ?? this.rect,
      color: color ?? this.color,
      rotation: rotation ?? this.rotation,
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
    final bounds = getBounds(size);
    final touch = Offset(
      normalizedPoint.dx * size.width,
      normalizedPoint.dy * size.height,
    );

    final dx = touch.dx - bounds.center.dx;
    final dy = touch.dy - bounds.center.dy;
    final cosT = math.cos(rotation);
    final sinT = math.sin(rotation);
    final u = dx * cosT + dy * sinT;
    final v = -dx * sinT + dy * cosT;

    final halfW = bounds.width / 2.0 + 8.0;
    final halfH = bounds.height / 2.0 + 8.0;
    return u.abs() <= halfW && v.abs() <= halfH;
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
    if (rotation != 0.0) {
      canvas.save();
      final center = pixelRect.center;
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: pixelRect.width,
          height: pixelRect.height,
        ),
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.restore();
    } else {
      canvas.drawRect(
        pixelRect,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }
}

/// Type alias so both `RedactAnnotation` and `RedactionAnnotation` resolve.
typedef RedactionAnnotation = RedactAnnotation;

class TextStylePreset {
  final String id;
  final String label;
  final String previewText;

  const TextStylePreset({
    required this.id,
    required this.label,
    required this.previewText,
  });
}

const List<TextStylePreset> kTextPresets = [
  TextStylePreset(id: 'L1', label: 'L1', previewText: 'LINE'),
  TextStylePreset(id: 'L2', label: 'L2', previewText: 'LINE'),
  TextStylePreset(id: 'L3', label: 'L3', previewText: 'line'),
  TextStylePreset(id: 'L4', label: 'L4', previewText: 'LINE'),
  TextStylePreset(id: 'L5', label: 'L5', previewText: 'line'),
  TextStylePreset(id: 'L6', label: 'L6', previewText: 'line'),
  TextStylePreset(id: 'L7', label: 'L7', previewText: 'LINE'),
  TextStylePreset(id: 'L8', label: 'L8', previewText: 'line'),
];

TextStyle getTextStyleForPreset({
  required String styleId,
  required double fontSize,
  required Color color,
}) {
  switch (styleId) {
    case 'L1':
      return TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.0,
      );
    case 'L2':
      return TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
      );
    case 'L3':
      return TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w300,
        letterSpacing: 2.0,
      );
    case 'L4':
      return TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: 4.5,
      );
    case 'L5':
      return TextStyle(
        color: color,
        fontSize: fontSize,
        fontFamily: 'serif',
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w600,
      );
    case 'L6':
      return TextStyle(
        color: color,
        fontSize: fontSize,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.2,
      );
    case 'L7':
      return TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
      );
    case 'L8':
      return TextStyle(
        color: color,
        fontSize: fontSize,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w500,
        letterSpacing: 1.5,
      );
    default:
      return TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
      );
  }
}

String transformTextForPreset(String text, String styleId) {
  switch (styleId) {
    case 'L1':
    case 'L2':
    case 'L4':
    case 'L7':
      return text.toUpperCase();
    case 'L3':
    case 'L5':
    case 'L6':
    case 'L8':
      return text;
    default:
      return text.toUpperCase();
  }
}

/// A text label placed at [position] on the image with scale, rotation, and style support.
class TextMarkAnnotation extends EditAnnotation {
  final Offset position; // normalized 0.0 .. 1.0 (center of text)
  final String text;
  final Color color;
  final double fontSizeFraction;
  final double rotation; // in radians
  final double opacity; // 0.0 .. 1.0
  final String styleId; // e.g. 'L1', 'L2', etc.

  TextMarkAnnotation({
    required this.position,
    required this.text,
    required this.color,
    required this.fontSizeFraction,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.styleId = 'L2',
  });

  TextMarkAnnotation copyWith({
    Offset? position,
    String? text,
    Color? color,
    double? fontSizeFraction,
    double? rotation,
    double? opacity,
    String? styleId,
  }) {
    return TextMarkAnnotation(
      position: position ?? this.position,
      text: text ?? this.text,
      color: color ?? this.color,
      fontSizeFraction: fontSizeFraction ?? this.fontSizeFraction,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      styleId: styleId ?? this.styleId,
    );
  }

  @override
  Rect getBounds(Size size) {
    final fontSize = size.height * fontSizeFraction;
    final displayedText = transformTextForPreset(text, styleId);
    final textPainter = TextPainter(
      text: TextSpan(
        text: displayedText,
        style: getTextStyleForPreset(
          styleId: styleId,
          fontSize: fontSize,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    final px = position.dx * size.width;
    final py = position.dy * size.height;
    return Rect.fromCenter(
      center: Offset(px, py),
      width: textPainter.width,
      height: textPainter.height,
    );
  }

  @override
  bool contains(Offset normalizedPoint, Size size) {
    final bounds = getBounds(size);
    final touch = Offset(
      normalizedPoint.dx * size.width,
      normalizedPoint.dy * size.height,
    );

    final dx = touch.dx - bounds.center.dx;
    final dy = touch.dy - bounds.center.dy;
    final cosT = math.cos(rotation);
    final sinT = math.sin(rotation);
    final u = dx * cosT + dy * sinT;
    final v = -dx * sinT + dy * cosT;

    final halfW = bounds.width / 2.0 + 20.0;
    final halfH = bounds.height / 2.0 + 20.0;
    return u.abs() <= halfW && v.abs() <= halfH;
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
    if (text.isEmpty) return;
    final fontSize = size.height * fontSizeFraction;
    final effectiveColor = color.withValues(alpha: color.a * opacity);
    final displayedText = transformTextForPreset(text, styleId);
    final baseStyle = getTextStyleForPreset(
      styleId: styleId,
      fontSize: fontSize,
      color: effectiveColor,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: displayedText,
        style: baseStyle.copyWith(
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.45 * opacity),
              blurRadius: 4,
              offset: const Offset(1, 1),
            ),
            ...?baseStyle.shadows,
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    final px = position.dx * size.width;
    final py = position.dy * size.height;

    canvas.save();
    canvas.translate(px, py);
    if (rotation != 0.0) {
      canvas.rotate(rotation);
    }
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2.0, -textPainter.height / 2.0),
    );
    canvas.restore();
  }
}

/// Freehand drawing stroke annotation.
class DrawingAnnotation extends EditAnnotation {
  final List<Offset> points; // normalized 0.0 .. 1.0
  final Color color;
  final double strokeWidthFraction;
  final double opacity;

  DrawingAnnotation({
    required this.points,
    required this.color,
    required this.strokeWidthFraction,
    this.opacity = 1.0,
  });

  DrawingAnnotation copyWith({
    List<Offset>? points,
    Color? color,
    double? strokeWidthFraction,
    double? opacity,
  }) {
    return DrawingAnnotation(
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidthFraction: strokeWidthFraction ?? this.strokeWidthFraction,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  Rect? getBounds(Size size) {
    if (points.isEmpty) return null;
    double minX = points.first.dx;
    double maxX = points.first.dx;
    double minY = points.first.dy;
    double maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final strokePx = size.height * strokeWidthFraction;
    return Rect.fromLTRB(
      minX * size.width - strokePx / 2.0,
      minY * size.height - strokePx / 2.0,
      maxX * size.width + strokePx / 2.0,
      maxY * size.height + strokePx / 2.0,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final strokeWidth = size.height * strokeWidthFraction;
    final effectiveAlpha = (color.a * opacity).clamp(0.0, 1.0);
    final effectiveColor = color.withValues(alpha: effectiveAlpha);
    final paint = Paint()
      ..color = effectiveColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      final p = Offset(
        points.first.dx * size.width,
        points.first.dy * size.height,
      );
      canvas.drawCircle(p, strokeWidth / 2.0, paint..style = PaintingStyle.fill);
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

typedef PenStrokeAnnotation = DrawingAnnotation;
typedef StrokeAnnotation = DrawingAnnotation;
