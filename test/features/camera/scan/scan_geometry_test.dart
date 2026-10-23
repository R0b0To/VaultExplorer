import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/camera/camera_ui_components.dart';
import 'package:vaultexplorer/features/camera/scan/scan_geometry.dart';

void main() {
  group('ScanQuad', () {
    test('fromPoints and toWire round-trip', () {
      const wire = [0.1, 0.2, 0.9, 0.15, 0.95, 0.85, 0.05, 0.9];
      final quad = ScanQuad.fromPoints(wire);
      expect(quad.corners.length, 4);
      expect(quad.corners[1], const Offset(0.9, 0.15));
      expect(quad.toWire(), wire);
    });

    test('inset rectangle has the expected area and is valid', () {
      final quad = ScanQuad.inset(0.06);
      expect(quad.area, closeTo(0.88 * 0.88, 1e-9));
      expect(quad.isConvex, isTrue);
      expect(quad.isValid, isTrue);
    });

    test('inset(0) is the whole image', () {
      final quad = ScanQuad.inset(0);
      expect(quad.area, closeTo(1.0, 1e-9));
      expect(quad.corners.first, Offset.zero);
      expect(quad.corners[2], const Offset(1, 1));
    });

    test('rejects bow-tie, concave and degenerate outlines', () {
      final bowTie = ScanQuad(const [Offset(.1, .1), Offset(.9, .9), Offset(.9, .1), Offset(.1, .9)]);
      final concave = ScanQuad(const [Offset(.1, .1), Offset(.9, .1), Offset(.3, .3), Offset(.1, .9)]);
      final collinear = ScanQuad(const [Offset(.1, .1), Offset(.5, .1), Offset(.9, .1), Offset(.9, .9)]);
      expect(bowTie.isConvex, isFalse);
      expect(concave.isConvex, isFalse);
      expect(collinear.isConvex, isFalse);
    });

    test('a tiny outline is convex but not valid', () {
      final tiny = ScanQuad(const [Offset(.5, .5), Offset(.55, .5), Offset(.55, .55), Offset(.5, .55)]);
      expect(tiny.isConvex, isTrue);
      expect(tiny.isValid, isFalse);
    });

    test('withCorner clamps into the image and leaves the original unchanged', () {
      final original = ScanQuad.inset(0.1);
      final moved = original.withCorner(0, const Offset(-0.5, 1.7));
      expect(moved.corners[0], const Offset(0, 1));
      expect(original.corners[0], const Offset(0.1, 0.1));
      expect(moved.corners[1], original.corners[1]);
    });

    test('lerp and maxCornerDistance', () {
      final a = ScanQuad.inset(0.1);
      final b = ScanQuad.inset(0.2);
      expect(a.maxCornerDistance(a), 0);
      expect(a.lerp(b, 0).maxCornerDistance(a), 0);
      expect(a.lerp(b, 1).maxCornerDistance(b), closeTo(0, 1e-12));
      final mid = a.lerp(b, 0.5);
      expect(mid.corners[0].dx, closeTo(0.15, 1e-12));
      expect(a.maxCornerDistance(b), closeTo(Offset(0.1, 0.1).distance, 1e-12));
    });
  });

  group('ScanQuad.withEdgeMoved', () {
    test('moves both corners of the edge together', () {
      final quad = ScanQuad.inset(0.1);
      final moved = quad.withEdgeMoved(0, const Offset(0, -0.05));
      expect(moved.corners[0].dy, closeTo(0.05, 1e-9));
      expect(moved.corners[1].dy, closeTo(0.05, 1e-9));
      expect(moved.corners[0].dx, closeTo(0.1, 1e-9));
      expect(moved.corners[2], quad.corners[2]);
      expect(moved.corners[3], quad.corners[3]);
    });

    test('the last edge wraps back to the first corner', () {
      final quad = ScanQuad.inset(0.1);
      final moved = quad.withEdgeMoved(3, const Offset(0.04, 0));
      expect(moved.corners[3].dx, closeTo(0.14, 1e-9));
      expect(moved.corners[0].dx, closeTo(0.14, 1e-9));
      expect(moved.corners[1], quad.corners[1]);
    });

    test('is stopped at the image border without bending the edge', () {
      final quad = ScanQuad.fromPoints(
        const [0.1, 0.2, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9],
      );
      final moved = quad.withEdgeMoved(0, const Offset(0, -0.5));
      // The higher corner reaches the border first and holds the whole edge.
      expect(moved.corners[1].dy, closeTo(0.0, 1e-9));
      expect(moved.corners[0].dy, closeTo(0.1, 1e-9));
      expect(
        moved.corners[0].dy - moved.corners[1].dy,
        closeTo(quad.corners[0].dy - quad.corners[1].dy, 1e-9),
      );
    });
  });

  group('cameraNaturalToDisplay', () {
    test('exactly inverts the camera screen\'s display->natural mapping', () {
      const samples = [
        Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1),
        Offset(0.25, 0.8), Offset(0.6, 0.35), Offset(0.5, 0.5),
      ];
      for (var rotation = 0; rotation < 4; rotation++) {
        for (final display in samples) {
          final natural = cameraDisplayPointToNatural(display.dx, display.dy, rotation);
          final back = cameraNaturalToDisplay(Offset(natural.x, natural.y), rotation);
          expect(back.dx, closeTo(display.dx, 1e-12), reason: 'rotation $rotation $display');
          expect(back.dy, closeTo(display.dy, 1e-12), reason: 'rotation $rotation $display');
        }
      }
    });

    test('wraps rotations beyond a full turn', () {
      const p = Offset(0.2, 0.7);
      expect(cameraNaturalToDisplay(p, 5), cameraNaturalToDisplay(p, 1));
      expect(cameraNaturalToDisplay(p, 4), p);
    });
  });

  group('cameraPreviewDisplayAspect', () {
    test('landscape sensor shown in portrait: sides swap', () {
      // 1920x1080 sensor frame, SENSOR_ORIENTATION 90, display not rotated.
      final aspect = cameraPreviewDisplayAspect(
        previewWidth: 1920,
        previewHeight: 1080,
        sensorOrientation: 90,
        displayRotation: 0,
      );
      expect(aspect, closeTo(1080 / 1920, 1e-12));
    });

    test('turning the display by a quarter flips the aspect', () {
      final portrait = cameraPreviewDisplayAspect(
        previewWidth: 1920,
        previewHeight: 1080,
        sensorOrientation: 90,
        displayRotation: 0,
      );
      final landscape = cameraPreviewDisplayAspect(
        previewWidth: 1920,
        previewHeight: 1080,
        sensorOrientation: 90,
        displayRotation: 1,
      );
      expect(landscape, closeTo(1 / portrait, 1e-12));
      expect(landscape, closeTo(1920 / 1080, 1e-12));
    });

    test('a sensor mounted upright does not swap', () {
      final aspect = cameraPreviewDisplayAspect(
        previewWidth: 1600,
        previewHeight: 1200,
        sensorOrientation: 0,
        displayRotation: 0,
      );
      expect(aspect, closeTo(4 / 3, 1e-12));
    });
  });

  group('fitContain', () {
    test('letterboxes a wide image in a tall box', () {
      final rect = fitContain(const Size(400, 800), const Size(1600, 1200));
      expect(rect.width, 400);
      expect(rect.height, 300);
      expect(rect.left, 0);
      expect(rect.top, 250);
    });

    test('pillarboxes a tall image in a wide box', () {
      final rect = fitContain(const Size(800, 400), const Size(1200, 1600));
      expect(rect.height, 400);
      expect(rect.width, closeTo(300, 1e-9));
      expect(rect.left, closeTo(250, 1e-9));
    });

    test('empty sizes give an empty rect', () {
      expect(fitContain(Size.zero, const Size(10, 10)), Rect.zero);
      expect(fitContain(const Size(10, 10), Size.zero), Rect.zero);
    });
  });
}
