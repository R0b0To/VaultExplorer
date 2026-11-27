part of 'image_editor_screen.dart';

/// Decoding the working image, fitting and rotation maths, and the zoom
/// helpers.
///
/// Moved out of [_ImageEditorScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _ImageEditorGeometry on _ImageEditorScreenState {
  void _animateTransformation(Matrix4 target) {
    _zoomAnimationController.stop();
    _zoomMatrixTween = Matrix4Tween(
      begin: _transformationController.value,
      end: target,
    );
    _zoomAnimationController.reset();
    _zoomAnimationController.forward();
  }

  void _handleDoubleTap(Offset tapPos, Size viewportSize) {
    if (_controls.activeTool != EditorTool.none) return;
    if (_currentScale > 1.05) {
      _resetZoom(animate: true);
    } else {
      const targetScale = 2.5;
      final minDx = viewportSize.width * (1 - targetScale);
      final minDy = viewportSize.height * (1 - targetScale);
      final dx = (tapPos.dx * (1 - targetScale)).clamp(minDx, 0.0);
      final dy = (tapPos.dy * (1 - targetScale)).clamp(minDy, 0.0);
      final target = Matrix4.identity()
        ..translateByDouble(dx, dy, 0.0, 1.0)
        ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
      _animateTransformation(target);
    }
  }

  void _pushUndoSnapshot() {
    if (_workingImage == null) return;
    _undoStack.add(
      _EditorSnapshot(image: _workingImage!, annotations: _annotations),
    );
    if (_undoStack.length > 12) {
      final discarded = _undoStack.removeAt(0);
      discarded.dispose();
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    if (_fileExtension == 'avif') {
      final info = await _cryptoApi.getAvifInfo(bytes);
      if (info == null) throw _UnsupportedImageFormatException();
      final frame = await _cryptoApi.decodeAvifFrame(bytes, 0);
      if (frame == null) throw _UnsupportedImageFormatException();
      return _rgbaToImage(frame.rgbaBytes, info.width, info.height);
    }
    ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
    } catch (_) {
      throw _UnsupportedImageFormatException();
    }
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  Future<ui.Image> _rgbaToImage(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Rect _computeFittedRect(
    Size boxSize,
    ui.Image image, {
    double padding = 0.0,
    double rotationDegrees = 0.0,
  }) {
    final availableWidth = math.max(1.0, boxSize.width - (padding * 2));
    final availableHeight = math.max(1.0, boxSize.height - (padding * 2));

    final rad = rotationDegrees * math.pi / 180.0;
    final cosVal = math.cos(rad).abs();
    final sinVal = math.sin(rad).abs();

    final rotW = math.max(1.0, image.width * cosVal + image.height * sinVal);
    final rotH = math.max(1.0, image.width * sinVal + image.height * cosVal);

    final imageAspect = rotW / rotH;
    final boxAspect = availableWidth / availableHeight;
    double w, h;

    if (imageAspect > boxAspect) {
      w = availableWidth;
      h = w / imageAspect;
    } else {
      h = availableHeight;
      w = h * imageAspect;
    }

    return Rect.fromLTWH(
      padding + (availableWidth - w) / 2,
      padding + (availableHeight - h) / 2,
      w,
      h,
    );
  }

  double _snapRotationAngle(double angle) {
    const snapThreshold = 0.8;
    if (angle.abs() <= snapThreshold) {
      return 0.0;
    }
    return angle.clamp(-45.0, 45.0);
  }

  void _onRotateAngleChanged(double rawAngle) {
    final snapped = _snapRotationAngle(rawAngle);
    if (snapped != _controls.cropRotationAngle) {
      if (snapped == 0.0) {
        HapticFeedback.selectionClick();
      }
      _controlsController.setCropRotationAngle(snapped);
      final notifier = _cropRectNotifier;
      final boxSize = _cropBoxSize;
      if (notifier != null && boxSize != null) {
        final angleRad = snapped * math.pi / 180.0;
        notifier.value = _calculateMaxInscribedRect(
          boxSize,
          angleRad,
          _controls.cropAspectRatio,
        );
      }
    }
  }

  Rect _calculateMaxInscribedRect(
    Size bounds,
    double angleRad,
    double? targetAspect,
  ) {
    final W = bounds.width;
    final H = bounds.height;
    if (W <= 0 || H <= 0) return Offset.zero & bounds;

    final cosA = math.cos(angleRad.abs());
    final sinA = math.sin(angleRad.abs());

    final double r;
    if (targetAspect != null && targetAspect > 0) {
      r = targetAspect;
    } else {
      r = W / H;
    }

    final denomW = r * cosA + sinA;
    final denomH = r * sinA + cosA;
    final maxH = math.min(W / denomW, H / denomH);
    final maxW = r * maxH;

    return Rect.fromCenter(
      center: Offset(W / 2.0, H / 2.0),
      width: maxW,
      height: maxH,
    );
  }
}
