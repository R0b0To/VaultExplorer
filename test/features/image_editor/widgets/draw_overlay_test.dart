import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';
import 'package:vaultexplorer/features/image_editor/widgets/draw_overlay.dart';

void main() {
  group('DrawingAnnotation', () {
    test('instantiates with custom color, opacity, points, and strokeWidthFraction', () {
      final annotation = DrawingAnnotation(
        points: const [Offset(0.1, 0.2), Offset(0.3, 0.4)],
        color: Colors.red,
        opacity: 0.75,
        strokeWidthFraction: 0.02,
      );

      expect(annotation.points.length, 2);
      expect(annotation.color, Colors.red);
      expect(annotation.opacity, closeTo(0.75, 0.001));
      expect(annotation.strokeWidthFraction, closeTo(0.02, 0.001));
    });

    test('copyWith updates properties properly', () {
      final original = DrawingAnnotation(
        points: const [Offset(0.1, 0.2)],
        color: Colors.white,
        opacity: 1.0,
        strokeWidthFraction: 0.02,
      );

      final updated = original.copyWith(
        color: Colors.blue,
        opacity: 0.5,
        strokeWidthFraction: 0.05,
      );

      expect(updated.color, Colors.blue);
      expect(updated.opacity, closeTo(0.5, 0.001));
      expect(updated.strokeWidthFraction, closeTo(0.05, 0.001));
      expect(updated.points, original.points);
    });

    test('getBounds calculates valid bounding box with stroke width padding', () {
      final annotation = DrawingAnnotation(
        points: const [Offset(0.2, 0.3), Offset(0.6, 0.7)],
        color: Colors.white,
        strokeWidthFraction: 0.02,
      );

      const imageSize = Size(1000, 1000);
      final bounds = annotation.getBounds(imageSize);
      expect(bounds, isNotNull);
      // Min X is 200 - padding(10) = 190, Max X is 600 + padding(10) = 610
      expect(bounds!.left, closeTo(190, 0.1));
      expect(bounds.top, closeTo(290, 0.1));
      expect(bounds.right, closeTo(610, 0.1));
      expect(bounds.bottom, closeTo(710, 0.1));
    });

    test('paint executes for single-point dot and multi-point path', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final dotAnnotation = DrawingAnnotation(
        points: const [Offset(0.5, 0.5)],
        color: Colors.green,
        opacity: 0.8,
        strokeWidthFraction: 0.02,
      );
      expect(() => dotAnnotation.paint(canvas, const Size(800, 600)), returnsNormally);

      final pathAnnotation = DrawingAnnotation(
        points: const [Offset(0.1, 0.1), Offset(0.2, 0.2), Offset(0.3, 0.3)],
        color: Colors.amber,
        opacity: 0.5,
        strokeWidthFraction: 0.03,
      );
      expect(() => pathAnnotation.paint(canvas, const Size(800, 600)), returnsNormally);

      final picture = recorder.endRecording();
      picture.dispose();
    });
  });

  group('DrawOverlay Widget', () {
    const viewportSize = Size(600, 400);
    final imageRect = const Rect.fromLTWH(50, 50, 500, 300);

    testWidgets('1-finger drag draws a stroke and calls onStrokeCompleted', (tester) async {
      DrawingAnnotation? completedStroke;
      final transformController = TransformationController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: viewportSize.width,
                height: viewportSize.height,
                child: DrawOverlay(
                  imageRect: imageRect,
                  transformationController: transformController,
                  color: Colors.cyan,
                  opacity: 0.9,
                  onStrokeCompleted: (stroke) => completedStroke = stroke,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DrawOverlay), findsOneWidget);

      final center = tester.getCenter(find.byType(DrawOverlay));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(30, 20));
      await gesture.moveBy(const Offset(30, 20));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(completedStroke, isNotNull);
      expect(completedStroke!.points.length, greaterThanOrEqualTo(2));
      expect(completedStroke!.color, Colors.cyan);
      expect(completedStroke!.opacity, closeTo(0.9, 0.001));
    });

    testWidgets('zoom scales stroke size inversely on the image', (tester) async {
      DrawingAnnotation? strokeAt1x;
      DrawingAnnotation? strokeAt2x;
      final transformController = TransformationController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: viewportSize.width,
                height: viewportSize.height,
                child: DrawOverlay(
                  imageRect: imageRect,
                  transformationController: transformController,
                  color: Colors.white,
                  opacity: 1.0,
                  onStrokeCompleted: (stroke) {
                    if (strokeAt1x == null) {
                      strokeAt1x = stroke;
                    } else {
                      strokeAt2x = stroke;
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(DrawOverlay));

      // Draw stroke at 1x
      final g1 = await tester.startGesture(center);
      await g1.moveBy(const Offset(20, 10));
      await g1.up();
      await tester.pumpAndSettle();

      expect(strokeAt1x, isNotNull);

      // Now zoom in to 2x
      transformController.value = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
      await tester.pump();

      // Draw stroke at 2x
      final g2 = await tester.startGesture(center);
      await g2.moveBy(const Offset(20, 10));
      await g2.up();
      await tester.pumpAndSettle();

      expect(strokeAt2x, isNotNull);
      // Stroke width fraction at 2x zoom should be half of the stroke width fraction at 1x zoom
      expect(
        strokeAt2x!.strokeWidthFraction,
        closeTo(strokeAt1x!.strokeWidthFraction / 2.0, 0.005),
      );
    });

    testWidgets('2-finger pinch updates zoom matrix and cancels single-finger stroke', (tester) async {
      DrawingAnnotation? completedStroke;
      final transformController = TransformationController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: viewportSize.width,
                height: viewportSize.height,
                child: DrawOverlay(
                  imageRect: imageRect,
                  transformationController: transformController,
                  color: Colors.yellow,
                  opacity: 1.0,
                  onStrokeCompleted: (stroke) => completedStroke = stroke,
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(DrawOverlay));
      final touch1 = await tester.startGesture(center + const Offset(-30, 0));
      final touch2 = await tester.startGesture(center + const Offset(30, 0));

      // Pinch outward
      await touch1.moveBy(const Offset(-40, 0));
      await touch2.moveBy(const Offset(40, 0));
      await tester.pump();

      await touch1.up();
      await touch2.up();
      await tester.pumpAndSettle();

      // Matrix scale should have increased
      expect(transformController.value.getMaxScaleOnAxis(), greaterThan(1.1));
      // No single finger stroke should have been completed from a 2-finger pinch
      expect(completedStroke, isNull);
    });
  });
}
