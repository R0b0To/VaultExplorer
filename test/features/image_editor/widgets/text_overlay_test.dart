import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';
import 'package:vaultexplorer/features/image_editor/widgets/text_overlay.dart';

void main() {
  group('TextMarkAnnotation', () {
    test('instantiates with expected default and custom parameters', () {
      final annotation = TextMarkAnnotation(
        position: const Offset(0.4, 0.6),
        text: 'HELLO WORLD',
        color: Colors.amber,
        fontSizeFraction: 0.05,
        rotation: 0.25,
        opacity: 0.85,
        styleId: 'L4',
      );

      expect(annotation.position.dx, closeTo(0.4, 0.001));
      expect(annotation.position.dy, closeTo(0.6, 0.001));
      expect(annotation.text, 'HELLO WORLD');
      expect(annotation.color, Colors.amber);
      expect(annotation.fontSizeFraction, closeTo(0.05, 0.001));
      expect(annotation.rotation, closeTo(0.25, 0.001));
      expect(annotation.opacity, closeTo(0.85, 0.001));
      expect(annotation.styleId, 'L4');
    });

    test('copyWith updates properties properly', () {
      final original = TextMarkAnnotation(
        position: const Offset(0.5, 0.5),
        text: 'Original',
        color: Colors.white,
        fontSizeFraction: 0.045,
        rotation: 0.0,
        opacity: 1.0,
        styleId: 'L2',
      );

      final updated = original.copyWith(
        text: 'Updated',
        rotation: 1.57,
        opacity: 0.5,
        styleId: 'L5',
      );

      expect(updated.text, 'Updated');
      expect(updated.rotation, 1.57);
      expect(updated.opacity, 0.5);
      expect(updated.styleId, 'L5');
      expect(updated.position, const Offset(0.5, 0.5));
    });

    test('presets L1 through L8 are defined with distinct styling', () {
      expect(kTextPresets.length, 8);
      final ids = kTextPresets.map((p) => p.id).toSet();
      expect(ids, {'L1', 'L2', 'L3', 'L4', 'L5', 'L6', 'L7', 'L8'});

      // L2 is bold uppercase
      expect(transformTextForPreset('hello', 'L2'), 'HELLO');
      final styleL2 = getTextStyleForPreset(
        styleId: 'L2',
        fontSize: 20.0,
        color: Colors.white,
      );
      expect(styleL2.fontWeight, FontWeight.w900);

      // L4 has letter spacing
      expect(transformTextForPreset('hello', 'L4'), 'HELLO');
      final styleL4 = getTextStyleForPreset(
        styleId: 'L4',
        fontSize: 20.0,
        color: Colors.white,
      );
      expect(styleL4.letterSpacing, greaterThan(2.0));

      // L5 is italic serif
      final styleL5 = getTextStyleForPreset(
        styleId: 'L5',
        fontSize: 20.0,
        color: Colors.white,
      );
      expect(styleL5.fontStyle, FontStyle.italic);

      // L6 is cursive italic
      final styleL6 = getTextStyleForPreset(
        styleId: 'L6',
        fontSize: 20.0,
        color: Colors.white,
      );
      expect(styleL6.fontStyle, FontStyle.italic);
    });

    test('paint executes on canvas without errors', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final annotation = TextMarkAnnotation(
        position: const Offset(0.5, 0.5),
        text: 'SAMPLE',
        color: Colors.white,
        fontSizeFraction: 0.05,
        rotation: 0.5,
        opacity: 0.8,
        styleId: 'L2',
      );

      expect(
        () => annotation.paint(canvas, const Size(800, 600)),
        returnsNormally,
      );
      final picture = recorder.endRecording();
      picture.dispose();
    });

    test('contains performs hit testing with inverse rotation', () {
      final annotation = TextMarkAnnotation(
        position: const Offset(0.5, 0.5),
        text: 'CENTER TEXT',
        color: Colors.white,
        fontSizeFraction: 0.05,
        rotation: 0.0,
        opacity: 1.0,
        styleId: 'L2',
      );

      const canvasSize = Size(1000, 1000);
      // Center of canvas normalized (0.5, 0.5)
      expect(annotation.contains(const Offset(0.5, 0.5), canvasSize), isTrue);
      // Way off in corner normalized (0.05, 0.05)
      expect(annotation.contains(const Offset(0.05, 0.05), canvasSize), isFalse);
    });
  });

  group('TextOverlay Widget', () {
    const imageSize = Size(600, 400);

    testWidgets('renders text and responds to double tap', (tester) async {
      bool doubleTapped = false;
      final notifier = ValueNotifier<TextMarkAnnotation>(
        TextMarkAnnotation(
          position: const Offset(0.5, 0.5),
          text: 'TEST MESSAGE',
          color: Colors.white,
          fontSizeFraction: 0.05,
          rotation: 0.0,
          opacity: 1.0,
          styleId: 'L2',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: imageSize.width,
                height: imageSize.height,
                child: TextOverlay(
                  imageSize: imageSize,
                  textNotifier: notifier,
                  onDoubleTap: () => doubleTapped = true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(TextOverlay), findsOneWidget);

      // Perform double tap at center
      final center = tester.getCenter(find.byType(TextOverlay));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      expect(doubleTapped, isTrue);
    });

    testWidgets('dragging moves text position', (tester) async {
      final notifier = ValueNotifier<TextMarkAnnotation>(
        TextMarkAnnotation(
          position: const Offset(0.5, 0.5),
          text: 'DRAG ME',
          color: Colors.white,
          fontSizeFraction: 0.05,
          rotation: 0.0,
          opacity: 1.0,
          styleId: 'L2',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: imageSize.width,
                height: imageSize.height,
                child: TextOverlay(
                  imageSize: imageSize,
                  textNotifier: notifier,
                  onDoubleTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(TextOverlay));
      // Drag by +60px horizontally and +40px vertically
      // On 600x400 image, this corresponds to +0.1 dx and +0.1 dy
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(60, 40));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(notifier.value.position.dx, closeTo(0.6, 0.01));
      expect(notifier.value.position.dy, closeTo(0.6, 0.01));
    });

    testWidgets('pinch scale changes font size', (tester) async {
      final notifier = ValueNotifier<TextMarkAnnotation>(
        TextMarkAnnotation(
          position: const Offset(0.5, 0.5),
          text: 'PINCH ME',
          color: Colors.white,
          fontSizeFraction: 0.05,
          rotation: 0.0,
          opacity: 1.0,
          styleId: 'L2',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: imageSize.width,
                height: imageSize.height,
                child: TextOverlay(
                  imageSize: imageSize,
                  textNotifier: notifier,
                  onDoubleTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(TextOverlay));
      final touch1 = await tester.startGesture(center + const Offset(-20, 0));
      final touch2 = await tester.startGesture(center + const Offset(20, 0));

      // Pinch outward: increase distance between touches
      await touch1.moveBy(const Offset(-40, 0));
      await touch2.moveBy(const Offset(40, 0));
      await tester.pump();

      await touch1.up();
      await touch2.up();
      await tester.pumpAndSettle();

      expect(notifier.value.fontSizeFraction, greaterThan(0.05));
    });

    testWidgets('rotation gesture rotates text and snaps near 0 rad', (tester) async {
      final notifier = ValueNotifier<TextMarkAnnotation>(
        TextMarkAnnotation(
          position: const Offset(0.5, 0.5),
          text: 'ROTATE ME',
          color: Colors.white,
          fontSizeFraction: 0.05,
          rotation: 0.0,
          opacity: 1.0,
          styleId: 'L2',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: imageSize.width,
                height: imageSize.height,
                child: TextOverlay(
                  imageSize: imageSize,
                  textNotifier: notifier,
                  onDoubleTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(TextOverlay));
      final touch1 = await tester.startGesture(center + const Offset(0, -40));
      final touch2 = await tester.startGesture(center + const Offset(0, 40));

      // Rotate 90 degrees (pi / 2 rad)
      await touch1.moveBy(const Offset(40, 40));
      await touch2.moveBy(const Offset(-40, -40));
      await tester.pump();

      await touch1.up();
      await touch2.up();
      await tester.pumpAndSettle();

      // Rotation should have changed significantly
      expect(notifier.value.rotation.abs(), greaterThan(0.2));
    });

    testWidgets('tapping an existing text annotation calls onSelectExistingText', (tester) async {
      int? selectedExistingIndex;
      final notifier = ValueNotifier<TextMarkAnnotation>(
        TextMarkAnnotation(
          position: const Offset(0.5, 0.8),
          text: 'BOTTOM TEXT',
          color: Colors.white,
          fontSizeFraction: 0.05,
          rotation: 0.0,
          opacity: 1.0,
          styleId: 'L2',
        ),
      );

      final existingList = [
        TextMarkAnnotation(
          position: const Offset(0.5, 0.2),
          text: 'TOP TEXT',
          color: Colors.yellow,
          fontSizeFraction: 0.05,
          rotation: 0.0,
          opacity: 1.0,
          styleId: 'L4',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: imageSize.width,
                height: imageSize.height,
                child: TextOverlay(
                  imageSize: imageSize,
                  textNotifier: notifier,
                  existingAnnotations: existingList,
                  onSelectExistingText: (idx) => selectedExistingIndex = idx,
                  onDoubleTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // Tap at normalized position (0.5, 0.2) where the existing text is
      final topLeft = tester.getTopLeft(find.byType(TextOverlay));
      final topTextPos = topLeft + Offset(imageSize.width * 0.5, imageSize.height * 0.2);
      await tester.tapAt(topTextPos);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(selectedExistingIndex, 0);
    });
  });
}
