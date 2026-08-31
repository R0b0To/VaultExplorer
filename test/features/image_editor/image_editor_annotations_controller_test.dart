import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_annotations_controller.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  RedactAnnotation annotation(double left) =>
      RedactAnnotation(rect: Rect.fromLTWH(left, 0.1, 0.2, 0.2));

  group('ImageEditorAnnotations controller', () {
    test('starts empty and records immutable committed annotations', () {
      final controller = container.read(
        imageEditorAnnotationsProvider('image-a').notifier,
      );
      final first = annotation(0.1);

      controller.add(first);
      final state = container.read(imageEditorAnnotationsProvider('image-a'));

      expect(state, [first]);
      expect(() => state.add(annotation(0.2)), throwsUnsupportedError);
    });

    test('undo and clear update only the active editor session', () {
      final a = container.read(
        imageEditorAnnotationsProvider('image-a').notifier,
      );
      final b = container.read(
        imageEditorAnnotationsProvider('image-b').notifier,
      );
      final first = annotation(0.1);
      final second = annotation(0.2);

      a.add(first);
      a.add(second);
      b.add(annotation(0.3));

      a.undo();
      expect(container.read(imageEditorAnnotationsProvider('image-a')), [
        first,
      ]);
      expect(
        container.read(imageEditorAnnotationsProvider('image-b')),
        hasLength(1),
      );

      a.clear();
      expect(
        container.read(imageEditorAnnotationsProvider('image-a')),
        isEmpty,
      );
      expect(
        container.read(imageEditorAnnotationsProvider('image-b')),
        hasLength(1),
      );
    });

    test('undo and clear are harmless for an empty session', () {
      final controller = container.read(
        imageEditorAnnotationsProvider('image-a').notifier,
      );

      controller.undo();
      controller.clear();

      expect(
        container.read(imageEditorAnnotationsProvider('image-a')),
        isEmpty,
      );
    });
  });
}
