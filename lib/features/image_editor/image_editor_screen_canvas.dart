part of 'image_editor_screen.dart';

/// Pan, scale and rotation gestures on the canvas page.
///
/// Moved out of [_ImageEditorScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _ImageEditorCanvas on _ImageEditorScreenState {
  void _handleCanvasPageScaleStart(ScaleStartDetails details, Rect imageRect) {
    _pageAnnotationDragTool = null;
    _pageRedactDragIndex = null;
    _pageRedactEditStarted = false;
    _pageRedactStartRect = null;
    _pageRedactCurrentRect = null;

    // Image overlays handle gestures that start over the photo. This handler
    // extends the same move gesture into the unused canvas around it.
    if (imageRect.contains(details.localFocalPoint)) return;

    if (_controls.activeTool == EditorTool.text &&
        _activeTextNotifier != null) {
      _pageAnnotationDragTool = EditorTool.text;
      final annotation = _activeTextNotifier!.value;
      _pageTextStartFontSize = annotation.fontSizeFraction;
      _pageTextStartRotation = annotation.rotation;
      _pageTextLastSnappedAngle = annotation.rotation;
      return;
    }

    final index = _selectedRedactIndex;
    if (_controls.activeTool == EditorTool.redact &&
        index != null &&
        index >= 0 &&
        index < _annotations.length &&
        _annotations[index] is RedactAnnotation) {
      final annotation = _annotations[index] as RedactAnnotation;
      _pageAnnotationDragTool = EditorTool.redact;
      _pageRedactDragIndex = index;
      _pageRedactStartRect = annotation.rect;
      _pageRedactCurrentRect = annotation.rect;
      _pageRedactStartRotation = annotation.rotation;
      _pageRedactLastSnappedAngle = annotation.rotation;
    }
  }

  void _handleCanvasPageScaleUpdate(
    ScaleUpdateDetails details,
    Size imageSize,
  ) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return;
    final delta = Offset(
      details.focalPointDelta.dx / imageSize.width,
      details.focalPointDelta.dy / imageSize.height,
    );

    if (_pageAnnotationDragTool == EditorTool.text) {
      final notifier = _activeTextNotifier;
      if (notifier == null) return;
      final current = notifier.value;
      notifier.value = current.copyWith(
        position: Offset(
          (current.position.dx + delta.dx).clamp(0.02, 0.98),
          (current.position.dy + delta.dy).clamp(0.02, 0.98),
        ),
        fontSizeFraction: details.scale == 1.0
            ? current.fontSizeFraction
            : (_pageTextStartFontSize * details.scale).clamp(0.015, 0.35),
        rotation: _pageTextRotation(current.rotation, details),
      );
      return;
    }

    final index = _pageRedactDragIndex;
    if (_pageAnnotationDragTool != EditorTool.redact ||
        index == null ||
        index < 0 ||
        index >= _annotations.length) {
      return;
    }

    final annotation = _annotations[index];
    if (annotation is! RedactAnnotation) return;
    final startRect = _pageRedactStartRect;
    if (startRect == null) return;

    final currentRect = _pageRedactCurrentRect ?? annotation.rect;
    final shifted = currentRect.shift(delta);
    var updatedRect = _clampRedactRect(shifted);
    if (details.scale != 1.0) {
      final minWidth = 6.0 / imageSize.width;
      final minHeight = 6.0 / imageSize.height;
      final width = (startRect.width * details.scale)
          .clamp(minWidth, 1.0)
          .toDouble();
      final height = (startRect.height * details.scale)
          .clamp(minHeight, 1.0)
          .toDouble();
      updatedRect = _clampRedactRect(
        Rect.fromCenter(
          center: updatedRect.center,
          width: width,
          height: height,
        ),
      );
    }
    final updatedRotation = _pageRedactRotation(annotation.rotation, details);
    if (updatedRect == annotation.rect &&
        updatedRotation == annotation.rotation) {
      return;
    }

    if (!_pageRedactEditStarted) {
      _pushUndoSnapshot();
      _pageRedactEditStarted = true;
    }
    _pageRedactCurrentRect = updatedRect;
    _annotationsController.update(
      index,
      annotation.copyWith(rect: updatedRect, rotation: updatedRotation),
    );
  }

  double _pageTextRotation(double currentRotation, ScaleUpdateDetails details) {
    if (details.rotation == 0.0 && details.pointerCount < 2) {
      return currentRotation;
    }

    var angle = _pageTextStartRotation + details.rotation;
    const threshold = 2.5 * math.pi / 180.0;
    const snapPoints = [0.0, math.pi / 2, -math.pi / 2, math.pi, -math.pi];
    for (final snap in snapPoints) {
      if ((angle - snap).abs() <= threshold) {
        if (_pageTextLastSnappedAngle != snap && snap == 0.0) {
          HapticFeedback.selectionClick();
        }
        angle = snap;
        break;
      }
    }
    _pageTextLastSnappedAngle = angle;
    return angle;
  }

  double _pageRedactRotation(
    double currentRotation,
    ScaleUpdateDetails details,
  ) {
    if (details.rotation == 0.0 && details.pointerCount < 2) {
      return currentRotation;
    }

    var angle = _pageRedactStartRotation + details.rotation;
    const threshold = 2.5 * math.pi / 180.0;
    final snapPoints = [
      0.0,
      math.pi / 2,
      -math.pi / 2,
      math.pi,
      -math.pi,
      3 * math.pi / 2,
      -3 * math.pi / 2,
    ];
    for (final snap in snapPoints) {
      if ((angle - snap).abs() <= threshold) {
        if (_pageRedactLastSnappedAngle != snap &&
            (snap == 0.0 || snap.abs() == math.pi / 2)) {
          HapticFeedback.selectionClick();
        }
        angle = snap;
        break;
      }
    }
    _pageRedactLastSnappedAngle = angle;
    return angle;
  }

  Rect _clampRedactRect(Rect rect) {
    final width = rect.width.clamp(0.0, 1.0).toDouble();
    final height = rect.height.clamp(0.0, 1.0).toDouble();
    final left = rect.left.clamp(0.0, 1.0 - width).toDouble();
    final top = rect.top.clamp(0.0, 1.0 - height).toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  void _handleCanvasPageScaleEnd(ScaleEndDetails _) {
    _clearCanvasPagePan();
  }

  void _clearCanvasPagePan() {
    _pageAnnotationDragTool = null;
    _pageRedactDragIndex = null;
    _pageRedactEditStarted = false;
    _pageRedactStartRect = null;
    _pageRedactCurrentRect = null;
  }
}
