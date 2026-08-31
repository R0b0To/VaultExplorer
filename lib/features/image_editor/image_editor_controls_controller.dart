import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/features/image_editor/widgets/annotation_layer.dart';

part 'image_editor_controls_controller.g.dart';

/// User-selected editing controls for one image-editor session.
///
/// The controller intentionally excludes crop geometry, canvas gestures, and
/// image objects: those belong to the rendered widget instance. It keeps the
/// choices that must stay coherent across the editor's toolbar, overlay, and
/// annotation input.
class ImageEditorControlsState {
  const ImageEditorControlsState({
    this.activeTool = EditorTool.none,
    this.currentColor = const Color(0xFFEF4444),
    this.currentStrokeWidthFraction = 0.010,
    this.cropAspectRatio,
  });

  final EditorTool activeTool;
  final Color currentColor;
  final double currentStrokeWidthFraction;
  final double? cropAspectRatio;

  ImageEditorControlsState copyWith({
    EditorTool? activeTool,
    Color? currentColor,
    double? currentStrokeWidthFraction,
    double? cropAspectRatio,
    bool clearCropAspectRatio = false,
  }) => ImageEditorControlsState(
    activeTool: activeTool ?? this.activeTool,
    currentColor: currentColor ?? this.currentColor,
    currentStrokeWidthFraction:
        currentStrokeWidthFraction ?? this.currentStrokeWidthFraction,
    cropAspectRatio: clearCropAspectRatio
        ? null
        : cropAspectRatio ?? this.cropAspectRatio,
  );
}

@riverpod
class ImageEditorControls extends _$ImageEditorControls {
  @override
  ImageEditorControlsState build(String sessionKey) =>
      const ImageEditorControlsState();

  void toggleTool(EditorTool tool) {
    state = state.copyWith(
      activeTool: state.activeTool == tool ? EditorTool.none : tool,
    );
  }

  void clearActiveTool() => state = state.copyWith(activeTool: EditorTool.none);

  void setColor(Color value) => state = state.copyWith(currentColor: value);

  void setStrokeWidth(double value) =>
      state = state.copyWith(currentStrokeWidthFraction: value);

  void setCropAspectRatio(double? value) => state = state.copyWith(
    cropAspectRatio: value,
    clearCropAspectRatio: value == null,
  );

  /// Resets the controls coupled to the document contents. Palette and stroke
  /// width remain selected, matching the screen's previous reset behavior.
  void resetDocumentControls() => state = state.copyWith(
    activeTool: EditorTool.none,
    clearCropAspectRatio: true,
  );
}
