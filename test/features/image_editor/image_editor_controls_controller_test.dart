import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_controls_controller.dart';
import 'package:vaultexplorer/features/image_editor/widgets/annotation_layer.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('ImageEditorControls controller', () {
    test('starts with the editor defaults', () {
      final state = container.read(imageEditorControlsProvider('image-a'));

      expect(state.activeTool, EditorTool.none);
      expect(state.currentColor, const Color(0xFFEF4444));
      expect(state.currentStrokeWidthFraction, 0.010);
      expect(state.cropAspectRatio, isNull);
    });

    test('toggles tools and retains the chosen annotation controls', () {
      final controller = container.read(
        imageEditorControlsProvider('image-a').notifier,
      );

      controller.setColor(Colors.blue);
      controller.setStrokeWidth(0.020);
      controller.toggleTool(EditorTool.draw);

      var state = container.read(imageEditorControlsProvider('image-a'));
      expect(state.activeTool, EditorTool.draw);
      expect(state.currentColor, Colors.blue);
      expect(state.currentStrokeWidthFraction, 0.020);

      controller.toggleTool(EditorTool.draw);
      state = container.read(imageEditorControlsProvider('image-a'));
      expect(state.activeTool, EditorTool.none);
      expect(state.currentColor, Colors.blue);
      expect(state.currentStrokeWidthFraction, 0.020);
    });

    test('crop ratio can be set and cleared independently', () {
      final controller = container.read(
        imageEditorControlsProvider('image-a').notifier,
      );

      controller.toggleTool(EditorTool.crop);
      controller.setCropAspectRatio(1.0);
      expect(
        container.read(imageEditorControlsProvider('image-a')).cropAspectRatio,
        1.0,
      );

      controller.setCropAspectRatio(null);
      expect(
        container.read(imageEditorControlsProvider('image-a')).cropAspectRatio,
        isNull,
      );
    });

    test('document reset clears only document-coupled controls', () {
      final controller = container.read(
        imageEditorControlsProvider('image-a').notifier,
      );
      controller.setColor(Colors.green);
      controller.setStrokeWidth(0.020);
      controller.toggleTool(EditorTool.crop);
      controller.setCropAspectRatio(1.0);

      controller.resetDocumentControls();
      final state = container.read(imageEditorControlsProvider('image-a'));
      expect(state.activeTool, EditorTool.none);
      expect(state.cropAspectRatio, isNull);
      expect(state.currentColor, Colors.green);
      expect(state.currentStrokeWidthFraction, 0.020);
    });

    test('keeps controls isolated by editor session', () {
      container
          .read(imageEditorControlsProvider('image-a').notifier)
          .toggleTool(EditorTool.redact);
      container
          .read(imageEditorControlsProvider('image-b').notifier)
          .setColor(Colors.black);

      expect(
        container.read(imageEditorControlsProvider('image-a')).activeTool,
        EditorTool.redact,
      );
      expect(
        container.read(imageEditorControlsProvider('image-b')).activeTool,
        EditorTool.none,
      );
      expect(
        container.read(imageEditorControlsProvider('image-b')).currentColor,
        Colors.black,
      );
    });
  });
}
