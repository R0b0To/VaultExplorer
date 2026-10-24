// Pure geometry for the document scanner: no Flutter widgets, no platform
// calls, so it can be unit-tested on its own.

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// The four corners of a document, normalised (0..1) to the image they refer
/// to and ordered clockwise from the top-left.
class ScanQuad {
  // Not const: a list's length is not a constant expression, so the assert
  // below could not live in a const constructor.
  ScanQuad(this.corners) : assert(corners.length == 4);

  /// From the eight numbers the native side sends: x0, y0, x1, y1, ...
  factory ScanQuad.fromPoints(List<double> p) {
    assert(p.length == 8);
    return ScanQuad([for (var i = 0; i < 8; i += 2) Offset(p[i], p[i + 1])]);
  }

  /// A rectangle [margin] in from every edge: where to start when nothing was
  /// detected. A margin of 0 is the whole image.
  factory ScanQuad.inset([double margin = 0.06]) => ScanQuad([
        Offset(margin, margin),
        Offset(1 - margin, margin),
        Offset(1 - margin, 1 - margin),
        Offset(margin, 1 - margin),
      ]);

  final List<Offset> corners;

  /// The wire format of the platform channel: x0, y0, x1, y1, ...
  List<double> toWire() => [
        for (final c in corners) ...[c.dx, c.dy],
      ];

  /// Moves one corner, keeping it inside the image.
  ScanQuad withCorner(int index, Offset to) {
    final clamped = Offset(
      math.max(0.0, math.min(1.0, to.dx)),
      math.max(0.0, math.min(1.0, to.dy)),
    );
    final next = [...corners];
    next[index] = clamped;
    return ScanQuad(next);
  }

  /// Moves edge [index], the one from corner [index] to the next corner, by
  /// [delta] (normalised), carrying both of its corners along.
  ///
  /// The delta is trimmed so neither corner leaves the image; trimming the
  /// move rather than clamping each corner keeps the edge's length and angle.
  ScanQuad withEdgeMoved(int index, Offset delta) {
    final a = corners[index % 4];
    final b = corners[(index + 1) % 4];
    final dx = math.max(
      -math.min(a.dx, b.dx),
      math.min(1 - math.max(a.dx, b.dx), delta.dx),
    ).toDouble();
    final dy = math.max(
      -math.min(a.dy, b.dy),
      math.min(1 - math.max(a.dy, b.dy), delta.dy),
    ).toDouble();
    final next = [...corners];
    next[index % 4] = a + Offset(dx, dy);
    next[(index + 1) % 4] = b + Offset(dx, dy);
    return ScanQuad(next);
  }

  /// Area as a fraction of the whole image.
  double get area {
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2;
  }

  /// True when the corners form a convex, non-self-intersecting quadrilateral.
  /// (Affine-invariant, so it holds in normalised coordinates too.)
  bool get isConvex {
    double? sign;
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      final c = corners[(i + 2) % 4];
      final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross.abs() < 1e-9) return false;
      if (sign == null) {
        sign = cross.sign;
      } else if (cross.sign != sign) {
        return false;
      }
    }
    return true;
  }

  /// A usable crop: convex and not vanishingly small.
  bool get isValid => isConvex && area >= 0.02;

  ScanQuad lerp(ScanQuad other, double t) => ScanQuad([
        for (var i = 0; i < 4; i++) corners[i] + (other.corners[i] - corners[i]) * t,
      ]);

  /// Largest distance between matching corners (in normalised units).
  double maxCornerDistance(ScanQuad other) {
    var worst = 0.0;
    for (var i = 0; i < 4; i++) {
      worst = math.max(worst, (corners[i] - other.corners[i]).distance);
    }
    return worst;
  }
}

/// Maps a point in the upright "natural" camera frame (0..1) to the *displayed*
/// frame (0..1) for a display rotation of 0..3 quarter turns. This is the exact
/// inverse of `cameraDisplayPointToNatural` in camera_ui_components.dart.
Offset cameraNaturalToDisplay(Offset p, int displayRotation) {
  switch (displayRotation % 4) {
    case 1:
      return Offset(p.dy, 1 - p.dx);
    case 2:
      return Offset(1 - p.dx, 1 - p.dy);
    case 3:
      return Offset(1 - p.dy, p.dx);
    default:
      return p;
  }
}

/// Width / height of the camera preview as it appears on screen, with no
/// cropping: the texture arrives already upright for the natural orientation
/// (so its sides swap for 90/270 sensors) and is then turned for the display.
double cameraPreviewDisplayAspect({
  required int previewWidth,
  required int previewHeight,
  required int sensorOrientation,
  required int displayRotation,
}) {
  final swap = sensorOrientation % 180 != 0;
  final naturalW = (swap ? previewHeight : previewWidth).toDouble();
  final naturalH = (swap ? previewWidth : previewHeight).toDouble();
  final turnedSideways = displayRotation.isOdd;
  return turnedSideways ? naturalH / naturalW : naturalW / naturalH;
}

/// Maps a point in the full displayed camera frame into its centered cover crop.
/// Coordinates can be outside 0..1 when the point lies beyond the visible crop;
/// the preview clips those parts of the document outline.
Offset cameraDisplayPointToAspectCrop(
  Offset point, {
  required double sourceAspectRatio,
  required double frameAspectRatio,
}) {
  if (!sourceAspectRatio.isFinite ||
      sourceAspectRatio <= 0 ||
      !frameAspectRatio.isFinite ||
      frameAspectRatio <= 0) {
    return point;
  }
  if ((sourceAspectRatio - frameAspectRatio).abs() < 1e-6) return point;

  if (sourceAspectRatio > frameAspectRatio) {
    final visibleWidth = frameAspectRatio / sourceAspectRatio;
    final left = (1 - visibleWidth) / 2;
    return Offset((point.dx - left) / visibleWidth, point.dy);
  }

  final visibleHeight = sourceAspectRatio / frameAspectRatio;
  final top = (1 - visibleHeight) / 2;
  return Offset(point.dx, (point.dy - top) / visibleHeight);
}

/// The rectangle an image of [image] size occupies when fitted (contain) inside
/// [container], centred.
Rect fitContain(Size container, Size image) {
  if (image.isEmpty || container.isEmpty) return Rect.zero;
  final scale = math.min(container.width / image.width, container.height / image.height);
  final w = image.width * scale;
  final h = image.height * scale;
  return Rect.fromLTWH((container.width - w) / 2, (container.height - h) / 2, w, h);
}
