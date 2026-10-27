import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';
import 'package:vaultexplorer/features/image_editor/widgets/annotation_layer.dart';

void main() {
  _resizeAndSnapTests();

  const imageSize = Size(400, 200);

  Future<List<EditAnnotation>> pump(
    WidgetTester tester, {
    List<EditAnnotation> existing = const [],
  }) async {
    final added = <EditAnnotation>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: imageSize.width,
            height: imageSize.height,
            child: AnnotationLayer(
              imageSize: imageSize,
              annotations: existing,
              activeTool: EditorTool.redact,
              color: Colors.black,
              strokeWidthFraction: 0.010,
              onAnnotationAdded: added.add,
              onTextTapped: (_) {},
            ),
          ),
        ),
      ),
    );
    return added;
  }

  Offset topLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byType(AnnotationLayer));

  testWidgets('dragging in the redact tool adds one rectangle', (tester) async {
    final added = await pump(tester);
    final origin = topLeft(tester);

    // Use timedDragFrom to generate many pointer move events, which the
    // ScaleGestureRecognizer accepts as a single-finger scale.
    await tester.timedDragFrom(
      origin + const Offset(40, 50),
      const Offset(200, 40),
      const Duration(milliseconds: 300),
    );
    await tester.pump();

    expect(added, hasLength(1));
    final redaction = added.single as RedactAnnotation;
    // The rect should roughly cover from start to end (some slop is eaten).
    expect(redaction.rect.width, greaterThan(0.3));
    expect(redaction.rect.height, greaterThan(0.05));
  });

  testWidgets('dragging up-left still produces a normalized rectangle', (
    tester,
  ) async {
    final added = await pump(tester);
    final origin = topLeft(tester);

    await tester.timedDragFrom(
      origin + const Offset(240, 90),
      const Offset(-200, -40),
      const Duration(milliseconds: 300),
    );
    await tester.pump();

    final rect = (added.single as RedactAnnotation).rect;
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
    // left < right after normalisation
    expect(rect.left, lessThan(rect.right));
  });

  testWidgets('a plain tap does not add a redaction', (tester) async {
    final added = await pump(tester);

    await tester.tapAt(topLeft(tester) + const Offset(100, 100));
    await tester.pump();

    expect(added, isEmpty);
  });

  testWidgets('a drag that starts on an existing box moves it, not a new one', (
    tester,
  ) async {
    final existing = RedactAnnotation(
      rect: const Rect.fromLTWH(0.1, 0.1, 0.3, 0.3),
    );
    final added = await pump(tester, existing: [existing]);
    final updated = <int>[];

    // Rebuild with an update callback so the move is observable.
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: imageSize.width,
            height: imageSize.height,
            child: AnnotationLayer(
              imageSize: imageSize,
              annotations: [existing],
              activeTool: EditorTool.redact,
              color: Colors.black,
              strokeWidthFraction: 0.010,
              onAnnotationAdded: added.add,
              onAnnotationUpdated: (index, _) => updated.add(index),
              onTextTapped: (_) {},
            ),
          ),
        ),
      ),
    );

    // Centre of the existing box: (0.25 * 400, 0.25 * 200) = (100, 50).
    await tester.timedDragFrom(
      topLeft(tester) + const Offset(100, 50),
      const Offset(60, 20),
      const Duration(milliseconds: 300),
    );
    await tester.pump();

    expect(added, isEmpty);
    expect(updated, isNotEmpty);
    expect(updated.every((i) => i == 0), isTrue);
  });

  testWidgets(
      'committing a newly drawn redact rectangle fires onSelectedAnnotationChanged',
      (tester) async {
    final selectedIndices = <int?>[];
    final added = <EditAnnotation>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: imageSize.width,
            height: imageSize.height,
            child: AnnotationLayer(
              imageSize: imageSize,
              annotations: const [],
              activeTool: EditorTool.redact,
              color: Colors.black,
              strokeWidthFraction: 0.010,
              onAnnotationAdded: added.add,
              onSelectedAnnotationChanged: selectedIndices.add,
              onTextTapped: (_) {},
            ),
          ),
        ),
      ),
    );

    final origin = topLeft(tester);
    await tester.timedDragFrom(
      origin + const Offset(40, 50),
      const Offset(200, 40),
      const Duration(milliseconds: 300),
    );
    await tester.pump();

    expect(added, hasLength(1));
    expect(selectedIndices, contains(0));
  });

  testWidgets(
      'tapping an existing redact box selects it and double tap removes it',
      (tester) async {
    final existing1 =
        RedactAnnotation(rect: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2));
    final existing2 =
        RedactAnnotation(rect: const Rect.fromLTWH(0.6, 0.6, 0.2, 0.2));
    final selectedIndices = <int?>[];
    final removed = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: imageSize.width,
            height: imageSize.height,
            child: AnnotationLayer(
              imageSize: imageSize,
              annotations: [existing1, existing2],
              activeTool: EditorTool.redact,
              color: Colors.black,
              strokeWidthFraction: 0.010,
              onAnnotationAdded: (_) {},
              onSelectedAnnotationChanged: selectedIndices.add,
              onAnnotationRemoved: removed.add,
              onTextTapped: (_) {},
            ),
          ),
        ),
      ),
    );

    final origin = topLeft(tester);
    // Tap on box 2: centre is (0.7 * 400, 0.7 * 200) = (280, 140)
    await tester.tapAt(origin + const Offset(280, 140));
    await tester.pump();

    expect(selectedIndices, contains(1));

    // Double tap on box 1: centre is (0.2 * 400, 0.2 * 200) = (80, 40)
    await tester.tapAt(origin + const Offset(80, 40));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(origin + const Offset(80, 40));
    await tester.pump();

    expect(removed, contains(0));
  });
}

void _resizeAndSnapTests() {
  const imageSize = Size(400, 200);
  // Pixel box: left 40, top 20, right 160, bottom 80.
  final box = RedactAnnotation(rect: const Rect.fromLTWH(0.1, 0.1, 0.3, 0.3));

  Future<({List<EditAnnotation> added, List<RedactAnnotation> updated})> pump(
    WidgetTester tester,
  ) async {
    final added = <EditAnnotation>[];
    final updated = <RedactAnnotation>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: imageSize.width,
            height: imageSize.height,
            child: AnnotationLayer(
              imageSize: imageSize,
              annotations: [box],
              activeTool: EditorTool.redact,
              color: Colors.black,
              strokeWidthFraction: 0.010,
              onAnnotationAdded: added.add,
              onAnnotationUpdated: (_, a) =>
                  updated.add(a as RedactAnnotation),
              onTextTapped: (_) {},
            ),
          ),
        ),
      ),
    );
    return (added: added, updated: updated);
  }

  Offset origin(WidgetTester tester) =>
      tester.getTopLeft(find.byType(AnnotationLayer));

  testWidgets('dragging the left side of a selected box resizes it', (
    tester,
  ) async {
    final result = await pump(tester);
    // Select the box with a tap.
    await tester.tapAt(origin(tester) + const Offset(100, 50));
    await tester.pump();

    // Grab just inside the left edge and pull it right by 80px (well past slop).
    // The edge-resize only works on un-rotated boxes (rotation < 0.05), and
    // this box starts at rotation 0.
    await tester.timedDragFrom(
      origin(tester) + const Offset(45, 50),
      const Offset(80, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pump();

    expect(result.added, isEmpty);
    expect(result.updated, isNotEmpty);
    final rect = result.updated.last.rect;
    // The left edge should have moved right from its original 0.1
    expect(rect.left, greaterThan(0.1));
    // The right edge should stay at 0.4
    expect(rect.right, closeTo(0.4, 0.01));
    // Top and bottom should be unchanged
    expect(rect.top, closeTo(0.1, 0.01));
    expect(rect.bottom, closeTo(0.4, 0.01));
  });

  testWidgets('a new box snaps its bottom to another redaction', (
    tester,
  ) async {
    final result = await pump(tester);

    // Draw a box that lands near the existing box's bottom edge (0.4 / 80px).
    // The snap should align the bottom edge.
    await tester.timedDragFrom(
      origin(tester) + const Offset(200, 20),
      const Offset(100, 62),
      const Duration(milliseconds: 300),
    );
    await tester.pump();

    expect(result.added, hasLength(1));
    final rect = (result.added.single as RedactAnnotation).rect;
    // The bottom should snap to 0.4 (matching the existing box's bottom).
    expect(rect.bottom, closeTo(0.4, 0.05));
  });
}
