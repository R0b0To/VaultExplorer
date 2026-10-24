import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/features/image_editor/widgets/annotation_layer.dart';

part 'image_editor_controls_controller.g.dart';

const List<double> editorFontSizeFractions = [0.035, 0.055, 0.085, 0.125];

class ImageEditorControlsState {
  const ImageEditorControlsState({
    this.activeTool = EditorTool.none,
    this.currentColor = const Color(0xFFEF4444),
    this.redactColor = const Color(0xFF000000),
    this.currentStrokeWidthFraction = 0.010,
    this.currentFontSizeFraction = 0.055,
    this.cropAspectRatio,
    this.cropRotationAngle = 0.0, // in degrees: -45° to +45°
  });

  final EditorTool activeTool;
  final Color currentColor;

  /// Fill colour for redaction boxes. Kept separate from [currentColor] so
  /// switching between the pencil/text colour and redaction doesn't make the
  /// boxes come out red.
  final Color redactColor;
  final double currentStrokeWidthFraction;
  final double currentFontSizeFraction;
  final double? cropAspectRatio;
  final double cropRotationAngle;

  ImageEditorControlsState copyWith({
    EditorTool? activeTool,
    Color? currentColor,
    Color? redactColor,
    double? currentStrokeWidthFraction,
    double? currentFontSizeFraction,
    double? cropAspectRatio,
    bool clearCropAspectRatio = false,
    double? cropRotationAngle,
  }) => ImageEditorControlsState(
    activeTool: activeTool ?? this.activeTool,
    currentColor: currentColor ?? this.currentColor,
    redactColor: redactColor ?? this.redactColor,
    currentStrokeWidthFraction:
        currentStrokeWidthFraction ?? this.currentStrokeWidthFraction,
    currentFontSizeFraction:
        currentFontSizeFraction ?? this.currentFontSizeFraction,
    cropAspectRatio: clearCropAspectRatio
        ? null
        : cropAspectRatio ?? this.cropAspectRatio,
    cropRotationAngle: cropRotationAngle ?? this.cropRotationAngle,
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

  void setRedactColor(Color value) =>
      state = state.copyWith(redactColor: value);

  void setStrokeWidth(double value) =>
      state = state.copyWith(currentStrokeWidthFraction: value);

  void setFontSize(double value) =>
      state = state.copyWith(currentFontSizeFraction: value);

  void setCropAspectRatio(double? value) => state = state.copyWith(
    cropAspectRatio: value,
    clearCropAspectRatio: value == null,
  );

  void setCropRotationAngle(double angle) =>
      state = state.copyWith(cropRotationAngle: angle);

  void resetDocumentControls() => state = state.copyWith(
    activeTool: EditorTool.none,
    clearCropAspectRatio: true,
    cropRotationAngle: 0.0,
  );
}