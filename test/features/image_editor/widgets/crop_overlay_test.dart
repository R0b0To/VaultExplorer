import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/image_editor/widgets/crop_overlay.dart';

void main() {
  group('CropOverlay', () {
    const imageSize = Size(600, 400);

    testWidgets('renders scrim and handles for crop rectangle', (tester) async {
      final rectNotifier = ValueNotifier<Rect>(
        const Rect.fromLTWH(100, 100, 200, 200),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: imageSize.width,
              height: imageSize.height,
              child: CropOverlay(
                imageSize: imageSize,
                rectNotifier: rectNotifier,
                aspectRatio: 1.0,
                angleRad: 0.0,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CropOverlay), findsOneWidget);
      expect(rectNotifier.value, const Rect.fromLTWH(100, 100, 200, 200));
    });

    testWidgets('can drag crop rectangle horizontally and vertically at 0 degrees',
        (tester) async {
      final rectNotifier = ValueNotifier<Rect>(
        const Rect.fromLTWH(100, 100, 200, 200),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: imageSize.width,
              height: imageSize.height,
              child: CropOverlay(
                imageSize: imageSize,
                rectNotifier: rectNotifier,
                aspectRatio: 1.0,
                angleRad: 0.0,
              ),
            ),
          ),
        ),
      );

      final overlayTopLeft = tester.getTopLeft(find.byType(CropOverlay));
      final cropCenter = overlayTopLeft + rectNotifier.value.center;
      await tester.dragFrom(cropCenter, const Offset(60, 50));
      await tester.pump();

      expect(rectNotifier.value.center.dx, greaterThan(200.0));
      expect(rectNotifier.value.center.dy, greaterThan(200.0));
    });

    testWidgets('can drag crop rectangle horizontally and vertically when angled',
        (tester) async {
      final angleRad = 15.0 * math.pi / 180.0;
      final rectNotifier = ValueNotifier<Rect>(
        const Rect.fromLTWH(200, 150, 150, 100),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: imageSize.width,
              height: imageSize.height,
              child: CropOverlay(
                imageSize: imageSize,
                rectNotifier: rectNotifier,
                aspectRatio: null,
                angleRad: angleRad,
              ),
            ),
          ),
        ),
      );

      final initialCenter = rectNotifier.value.center;
      final overlayTopLeft = tester.getTopLeft(find.byType(CropOverlay));

      // Drag horizontally
      await tester.dragFrom(overlayTopLeft + initialCenter, const Offset(40, 0));
      await tester.pump();

      expect(rectNotifier.value.center.dx, greaterThan(initialCenter.dx));

      // Drag vertically
      final updatedCenter = rectNotifier.value.center;
      await tester.dragFrom(overlayTopLeft + updatedCenter, const Offset(0, 30));
      await tester.pump();

      expect(rectNotifier.value.center.dy, greaterThan(updatedCenter.dy));

      // Verify mathematical containment of all 4 corners in rotated image frame
      final rect = rectNotifier.value;
      final W = imageSize.width;
      final H = imageSize.height;
      final cx = rect.center.dx - W / 2.0;
      final cy = rect.center.dy - H / 2.0;
      final cosT = math.cos(angleRad);
      final sinT = math.sin(angleRad);
      final u = cx * cosT + cy * sinT;
      final v = -cx * sinT + cy * cosT;
      final spanU = (rect.width / 2.0) * math.cos(angleRad.abs()) +
          (rect.height / 2.0) * math.sin(angleRad.abs());
      final spanV = (rect.width / 2.0) * math.sin(angleRad.abs()) +
          (rect.height / 2.0) * math.cos(angleRad.abs());

      expect(u.abs() + spanU, lessThanOrEqualTo(W / 2.0 + 0.01));
      expect(v.abs() + spanV, lessThanOrEqualTo(H / 2.0 + 0.01));
    });

    testWidgets('swiping background outside crop box reports onAngleDelta',
        (tester) async {
      double receivedDelta = 0.0;
      final rectNotifier = ValueNotifier<Rect>(
        const Rect.fromLTWH(200, 150, 100, 100),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: imageSize.width,
              height: imageSize.height,
              child: CropOverlay(
                imageSize: imageSize,
                rectNotifier: rectNotifier,
                aspectRatio: 1.0,
                angleRad: 0.0,
                onAngleDelta: (delta) => receivedDelta += delta,
              ),
            ),
          ),
        ),
      );

      // Drag on the scrim (top-left corner, far outside the 100x100 crop box at (200, 150))
      final topLeft = tester.getTopLeft(find.byType(CropOverlay));
      await tester.dragFrom(topLeft + const Offset(10, 10), const Offset(60, 0));
      await tester.pump();

      expect(receivedDelta, closeTo(60.0, 1.0));
    });
  });
}
