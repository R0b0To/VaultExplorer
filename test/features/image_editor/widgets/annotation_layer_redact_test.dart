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

    await tester.dragFrom(origin + const Offset(40, 50), const Offset(200, 40));
    await tester.pump();

    expect(added, hasLength(1));
    final redaction = added.single as RedactAnnotation;
    expect(redaction.rect.left, closeTo(0.1, 0.001));
    expect(redaction.rect.top, closeTo(0.25, 0.001));
    expect(redaction.rect.right, closeTo(0.6, 0.001));
    expect(redaction.rect.bottom, closeTo(0.45, 0.001));
  });

  testWidgets('dragging up-left still produces a normalized rectangle', (
    tester,
  ) async {
    final added = await pump(tester);
    final origin = topLeft(tester);

    await tester.dragFrom(
      origin + const Offset(240, 90),
      const Offset(-200, -40),
    );
    await tester.pump();

    final rect = (added.single as RedactAnnotation).rect;
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
    expect(rect.left, closeTo(0.1, 0.001));
    expect(rect.right, closeTo(0.6, 0.001));
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

    // Centre of the existing box: (0.25 * 400, 0.25 * 200).
    await tester.dragFrom(
      topLeft(tester) + const Offset(100, 50),
      const Offset(60, 20),
    );
    await tester.pump();

    expect(added, isEmpty);
    expect(updated, isNotEmpty);
    expect(updated.every((i) => i == 0), isTrue);
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
              onAnnotationUpdated: (_, a) => updated.add(a as RedactAnnotation),
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

    // Grab just inside the left edge and pull it right by 60px (it has to be
    // well past the ~36px pan slop for the drag to start at all).
    await tester.dragFrom(
      origin(tester) + const Offset(45, 50),
      const Offset(60, 0),
    );
    await tester.pump();

    expect(result.added, isEmpty);
    final rect = result.updated.last.rect;
    expect(rect.left, closeTo(0.25, 0.001));
    expect(rect.right, closeTo(0.4, 0.001));
    expect(rect.top, closeTo(0.1, 0.001));
    expect(rect.bottom, closeTo(0.4, 0.001));
  });

  testWidgets('a new box snaps its bottom to another redaction', (
    tester,
  ) async {
    final result = await pump(tester);

    // Bottom edge would be y = 84px; the existing box's bottom is y = 80px.
    await tester.dragFrom(
      origin(tester) + const Offset(200, 20),
      const Offset(100, 64),
    );
    await tester.pump();

    final rect = (result.added.single as RedactAnnotation).rect;
    expect(rect.top, closeTo(0.1, 1e-6));
    expect(rect.bottom, closeTo(0.4, 1e-6));
  });
}
