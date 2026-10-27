import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/filesystem/path_components.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/core/widgets/zoom_indicator_pill.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/features/browser/viewer/models/viewer_adjustments.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/color_adjust_filter.dart';
import 'package:vaultexplorer/features/image_editor/image_output_format.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';
import 'package:vaultexplorer/features/image_editor/widgets/annotation_layer.dart';
import 'package:vaultexplorer/features/image_editor/widgets/crop_overlay.dart';
import 'package:vaultexplorer/features/image_editor/widgets/draw_overlay.dart';
import 'package:vaultexplorer/features/image_editor/widgets/save_image_sheet.dart';
import 'package:vaultexplorer/features/image_editor/widgets/text_overlay.dart';
import 'package:vaultexplorer/features/skin_editor/skin_edit_session.dart';
import 'package:vaultexplorer/features/settings/widgets/skin_color_picker_sheet.dart';
import 'image_editor_annotations_controller.dart';
import 'image_editor_controls_controller.dart';
import 'image_editor_document_controller.dart';

part 'image_editor_screen_shelf.dart';

class _UnsupportedImageFormatException implements Exception {}

enum _ExitChoice { cancel, discard, save }

class _EditorSnapshot {
  final ui.Image image;
  final List<EditAnnotation> annotations;

  _EditorSnapshot({
    required ui.Image image,
    required List<EditAnnotation> annotations,
  }) : image = image.clone(),
       annotations = List.unmodifiable(annotations);

  void dispose() {
    image.dispose();
  }
}

sealed class ImageEditorResult {
  const ImageEditorResult();
}

class ImageEditorSaveResult extends ImageEditorResult {
  final Uint8List bytes;
  const ImageEditorSaveResult(this.bytes);
}

class ImageEditorAddAnotherResult extends ImageEditorResult {
  final Uint8List bytes;
  const ImageEditorAddAnotherResult(this.bytes);
}

class ImageEditorScreen extends ConsumerStatefulWidget {
  final MountedContainer? container;
  final String? filePath;
  final Uint8List? imageBytes;
  final ThumbnailQuality thumbnailQuality;
  final bool allowSequentialCapture;
  final int batchIndex;

  const ImageEditorScreen({
    super.key,
    this.container,
    this.filePath,
    this.imageBytes,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    this.allowSequentialCapture = false,
    this.batchIndex = 1,
  });

  @override
  ConsumerState<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

enum _TuneGestureDirection { undecided, vertical, horizontal }

class _ImageEditorScreenState extends ConsumerState<ImageEditorScreen>
    with SingleTickerProviderStateMixin {
  // Cached on first use (initState): `ref` can't be read from dispose().
  late final VaultFileIoApi _fileIoApi = ref.read(vaultFileIoApiProvider);
  VaultCryptoApi get _cryptoApi => ref.read(vaultCryptoApiProvider);
  VaultEngineEvents? _vaultEvents;
  bool _containerLocked = false;

  Uint8List? _originalBytes;

  /// Pixel count of the picture as first decoded from [_originalBytes]. Lets
  /// a save tell how much a crop shrank the image so the file can shrink with
  /// it (see [imageSizeBudgetBytes]).
  int _originalPixelCount = 0;

  /// True once "Overwrite original" has replaced the file on disk with an
  /// edited version. From then on [_originalBytes] no longer matches what is
  /// on disk, which matters when the user resets the image (see
  /// [_resetToOriginal]).
  bool _overwroteOriginal = false;

  ui.Image? _workingImage;
  ViewerAdjustments _previewAdjustments = ViewerAdjustments.identity;

  final List<_EditorSnapshot> _undoStack = [];

  ValueNotifier<Rect>? _cropRectNotifier;
  Size? _cropBoxSize;

  bool _showOriginalCompare = false;
  bool _cropFlippedHorizontal = false;
  ui.Image? _cropEntryImage;
  _TextShelfTab _textShelfTab = _TextShelfTab.style;
  ValueNotifier<TextMarkAnnotation>? _activeTextNotifier;
  TextMarkAnnotation? _textEntrySnapshot;
  int? _editingTextAnnotationIndex;

  Color _drawColor = Colors.white;
  double _drawOpacity = 1.0;
  double _drawStrokeDiameter = DrawOverlay.kDefaultBrushDiameter;
  _DrawShelfTab _drawShelfTab = _DrawShelfTab.color;
  List<DrawingAnnotation>? _drawSessionSnapshot;
  int? _selectedRedactIndex;
  List<RedactAnnotation>? _redactSessionSnapshot;
  bool _isAddingRedact = false;
  bool _isRedactColorWheelInteracting = false;
  bool _hasRedactColorWheelSnapshot = false;
  EditorTool? _pageAnnotationDragTool;
  int? _pageRedactDragIndex;
  bool _pageRedactEditStarted = false;
  double _pageTextStartFontSize = 0.045;
  double _pageTextStartRotation = 0.0;
  double _pageTextLastSnappedAngle = 0.0;
  Rect? _pageRedactStartRect;
  Rect? _pageRedactCurrentRect;
  double _pageRedactStartRotation = 0.0;
  double _pageRedactLastSnappedAngle = 0.0;
  _TuneParam _selectedTuneParam = _TuneParam.brightness;
  bool _showTuneParamMenu = false;
  String _selectedPresetId = 'original';

  _TuneGestureDirection _tuneGestureDir = _TuneGestureDirection.undecided;
  Offset? _tunePointerDownPos;
  int _tunePointerStartVal = 0;
  int _tunePointerStartParamIdx = 0;

  final Map<_TuneParam, int> _tuneValues = {
    _TuneParam.brightness: 0,
    _TuneParam.contrast: 0,
    _TuneParam.saturation: 0,
    _TuneParam.ambiance: 0,
    _TuneParam.warmth: 0,
    _TuneParam.shadows: 0,
  };

  String get _controlsKey => widget.imageBytes != null
      ? 'in_memory_image_editor_${widget.imageBytes.hashCode}'
      : '${widget.container?.uri ?? ""}\u0000${widget.filePath ?? ""}';

  ImageEditorControlsState get _controls =>
      ref.read(imageEditorControlsProvider(_controlsKey));

  ImageEditorControls get _controlsController =>
      ref.read(imageEditorControlsProvider(_controlsKey).notifier);

  List<EditAnnotation> get _annotations =>
      ref.read(imageEditorAnnotationsProvider(_controlsKey));

  ImageEditorAnnotations get _annotationsController =>
      ref.read(imageEditorAnnotationsProvider(_controlsKey).notifier);

  ImageEditorDocumentState get _document =>
      ref.read(imageEditorDocumentProvider(_controlsKey));

  ImageEditorDocument get _documentController =>
      ref.read(imageEditorDocumentProvider(_controlsKey).notifier);

  /// Whether the editor holds changes that are not on disk yet.
  ///
  /// This intentionally does not look at [_undoStack]. The undo history is
  /// kept after a save so the user can still step back, which used to make a
  /// freshly saved edit look "unsaved" forever: the save button stayed
  /// enabled and leaving the screen asked to save again. Every operation that
  /// changes the working image marks the document edited (flattening
  /// annotations, cropping, undoing), and a save clears that mark, so
  /// [ImageEditorDocumentState.isEdited] plus pending annotations is the whole
  /// truth.
  bool get _isDirty => _document.isEdited || _annotations.isNotEmpty;

  /// Whether "reset to original" has anything to do: unsaved edits, or edit
  /// history that was already saved.
  bool get _canReset => _isDirty || _undoStack.isNotEmpty;

  bool get _canUndo => _undoStack.isNotEmpty || _annotations.isNotEmpty;

  String get _fileName {
    final path = widget.filePath;
    if (path == null) {
      if (widget.allowSequentialCapture) {
        return context.l10n.imageEditorPhotoLabel(widget.batchIndex);
      }
      return 'photo.jpg';
    }
    final idx = path.lastIndexOf('/');
    return idx == -1 ? path : path.substring(idx + 1);
  }

  String get _fileExtension {
    final dot = _fileName.lastIndexOf('.');
    return dot == -1 ? '' : _fileName.substring(dot + 1).toLowerCase();
  }

  late final TransformationController _transformationController;
  late final AnimationController _zoomAnimationController;
  late final CurvedAnimation _zoomCurvedAnimation;
  Matrix4Tween? _zoomMatrixTween;
  double _currentScale = 1.0;
  Orientation? _lastOrientation;

  @override
  void initState() {
    super.initState();
    unawaited(_fileIoApi.setKeepScreenOn(true));
    final container = widget.container;
    if (container != null) {
      final events = ref.read(vaultEngineEventsProvider);
      _vaultEvents = events;
      events.addContainerLockedListener(_onContainerLocked);
    }
    _transformationController = TransformationController();
    _transformationController.addListener(_onTransformationChanged);
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _zoomCurvedAnimation =
        CurvedAnimation(
          parent: _zoomAnimationController,
          curve: Curves.easeOutCubic,
        )..addListener(() {
          if (_zoomMatrixTween != null) {
            _transformationController.value = _zoomMatrixTween!.evaluate(
              _zoomCurvedAnimation,
            );
          }
        });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _vaultEvents?.removeContainerLockedListener(_onContainerLocked);
    unawaited(_fileIoApi.setKeepScreenOn(false));
    _zoomCurvedAnimation.dispose();
    _zoomAnimationController.dispose();
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    for (final s in _undoStack) {
      s.dispose();
    }
    _workingImage?.dispose();
    _cropEntryImage?.dispose();
    _cropRectNotifier?.dispose();
    _activeTextNotifier?.dispose();
    super.dispose();
  }

  void _onContainerLocked(int volId) {
    if (!mounted || widget.container?.volId != volId || _containerLocked) {
      return;
    }
    setState(() => _containerLocked = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      final navigator = Navigator.of(context);
      // Clear transient sheets above the editor, then remove the editor route
      // without invoking its unsaved-changes prompt after the vault is locked.
      navigator.popUntil((candidate) => candidate == route);
      if (route.isActive) navigator.removeRoute(route);
    });
  }

  void _onTransformationChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if ((scale - _currentScale).abs() > 0.01) {
      setState(() {
        _currentScale = scale;
      });
    }
  }

  void _resetZoom({bool animate = true}) {
    if (_transformationController.value.isIdentity()) return;
    if (animate) {
      _animateTransformation(Matrix4.identity());
    } else {
      _zoomAnimationController.stop();
      _transformationController.value = Matrix4.identity();
      if (_currentScale != 1.0) {
        setState(() {
          _currentScale = 1.0;
        });
      }
    }
  }

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

  // -------------------------------------------------------------------
  // Undo Snapshot History
  // -------------------------------------------------------------------

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

  void _undo() {
    if (_undoStack.isEmpty) {
      if (_annotations.isNotEmpty) {
        _annotationsController.undo();
      }
      return;
    }

    final snapshot = _undoStack.removeLast();
    final oldImage = _workingImage;
    final sizeChanged =
        oldImage == null ||
        oldImage.width != snapshot.image.width ||
        oldImage.height != snapshot.image.height;
    if (sizeChanged) {
      _resetZoom(animate: false);
    }

    setState(() {
      _workingImage = snapshot.image.clone();
      _cropRectNotifier = null;
      _cropBoxSize = null;
    });

    oldImage?.dispose();
    snapshot.dispose();

    _annotationsController.setAll(snapshot.annotations);
    _controlsController.setCropRotationAngle(0.0);
    _documentController.markEdited();
  }

  // -------------------------------------------------------------------
  // Loading & decoding
  // -------------------------------------------------------------------

  Future<void> _load() async {
    _documentController.startLoading();
    try {
      Uint8List? bytes = widget.imageBytes;
      if (bytes == null &&
          widget.container != null &&
          widget.filePath != null) {
        bytes = FullResImageCache.get(widget.container!, widget.filePath!);
        bytes ??= await _fileIoApi.readWholeFile(
          widget.container!,
          widget.filePath!,
        );
      }
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        _documentController.loadFailed(
          context.l10n.encryptedImageLoadFailedMessage,
        );
        return;
      }
      final image = await _decodeImage(bytes);
      if (!mounted) return;
      setState(() {
        _originalBytes = bytes;
        _originalPixelCount = image.width * image.height;
        _workingImage = image;
      });
      _documentController.loaded();
    } on _UnsupportedImageFormatException {
      if (!mounted) return;
      _documentController.loadFailed(
        context.l10n.imageEditorUnsupportedFormatMessage,
      );
    } catch (e) {
      if (!mounted) return;
      _documentController.loadFailed(e.toString());
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

  // -------------------------------------------------------------------
  // 360° Magnetic Snapping
  // -------------------------------------------------------------------

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

  Future<void> _stepRotate90() async {
    final image = _workingImage;
    if (image == null) return;
    unawaited(HapticFeedback.mediumImpact());

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(image.height.toDouble(), 0);
    canvas.rotate(math.pi / 2);
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final newImage = await picture.toImage(image.height, image.width);
    picture.dispose();

    if (!mounted) {
      newImage.dispose();
      return;
    }

    final oldImage = _workingImage;
    setState(() {
      _workingImage = newImage;
      _cropRectNotifier = null;
      _cropBoxSize = null;
    });
    oldImage?.dispose();
    _documentController.markEdited();
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

  // -------------------------------------------------------------------
  // Edit operations
  // -------------------------------------------------------------------

  Future<void> _flattenPendingAnnotations() async {
    if (_annotations.isEmpty || _workingImage == null) return;
    final image = _workingImage!;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());
    for (final annotation in _annotations) {
      annotation.paint(canvas, size);
    }
    final picture = recorder.endRecording();
    final newImage = await picture.toImage(image.width, image.height);
    picture.dispose();
    if (!mounted) {
      newImage.dispose();
      return;
    }
    final oldImage = _workingImage;
    setState(() {
      _workingImage = newImage;
    });
    _annotationsController.clear();
    _documentController.markEdited();
    oldImage?.dispose();
  }

  void _onTuneValueChanged(int value) {
    setState(() {
      _tuneValues[_selectedTuneParam] = value;
    });
    _updateTuneAdjustments();
  }

  void _handleTunePointerDown(PointerDownEvent event) {
    _tuneGestureDir = _TuneGestureDirection.undecided;
    _tunePointerDownPos = event.localPosition;
    _tunePointerStartVal = _tuneValues[_selectedTuneParam] ?? 0;
    _tunePointerStartParamIdx = _TuneParam.values.indexOf(_selectedTuneParam);
  }

  void _handleTunePointerMove(PointerMoveEvent event) {
    if (_tunePointerDownPos == null) return;
    final dx = event.localPosition.dx - _tunePointerDownPos!.dx;
    final dy = event.localPosition.dy - _tunePointerDownPos!.dy;

    if (_tuneGestureDir == _TuneGestureDirection.undecided) {
      // Instant response after only 3 pixels of movement
      if (dy.abs() >= 3 && dy.abs() >= dx.abs()) {
        _tuneGestureDir = _TuneGestureDirection.vertical;
        if (!_showTuneParamMenu) {
          setState(() => _showTuneParamMenu = true);
        }
      } else if (dx.abs() >= 3 && dx.abs() > dy.abs()) {
        _tuneGestureDir = _TuneGestureDirection.horizontal;
      }
    }

    if (_tuneGestureDir == _TuneGestureDirection.vertical) {
      final step = (dy / 34.0).round();
      final newIndex = (_tunePointerStartParamIdx + step).clamp(
        0,
        _TuneParam.values.length - 1,
      );
      final newParam = _TuneParam.values[newIndex];
      if (newParam != _selectedTuneParam) {
        setState(() {
          _selectedTuneParam = newParam;
        });
        HapticFeedback.selectionClick();
      }
    } else if (_tuneGestureDir == _TuneGestureDirection.horizontal) {
      final delta = (dx / 1.5).round();
      final newVal = (_tunePointerStartVal + delta).clamp(-100, 100);
      if (newVal != (_tuneValues[_selectedTuneParam] ?? 0)) {
        _onTuneValueChanged(newVal);
      }
    }
  }

  void _handleTunePointerUp(PointerUpEvent event) {
    if (_tuneGestureDir == _TuneGestureDirection.vertical) {
      setState(() {
        _showTuneParamMenu = false;
      });
    }
    _tuneGestureDir = _TuneGestureDirection.undecided;
    _tunePointerDownPos = null;
  }

  void _handleTunePointerCancel(PointerCancelEvent event) {
    if (_tuneGestureDir == _TuneGestureDirection.vertical) {
      setState(() {
        _showTuneParamMenu = false;
      });
    }
    _tuneGestureDir = _TuneGestureDirection.undecided;
    _tunePointerDownPos = null;
  }

  void _updateTuneAdjustments() {
    final b = _tuneValues[_TuneParam.brightness]! / 100.0;
    final c = 1.0 + (_tuneValues[_TuneParam.contrast]! / 100.0);
    final s = 1.0 + (_tuneValues[_TuneParam.saturation]! / 100.0);
    final a = _tuneValues[_TuneParam.ambiance]! / 200.0;
    final w = _tuneValues[_TuneParam.warmth]! * 0.3;
    final sh = 1.0 + (_tuneValues[_TuneParam.shadows]! / 150.0);
    setState(() {
      _previewAdjustments = ViewerAdjustments(
        brightness: b,
        contrast: (c + a).clamp(0.0, 2.0),
        saturation: (s + a).clamp(0.0, 2.0),
        hue: w,
        gamma: sh.clamp(0.3, 3.0),
      );
    });
  }

  void _resetTuneValues() {
    setState(() {
      for (final p in _TuneParam.values) {
        _tuneValues[p] = 0;
      }
      _previewAdjustments = ViewerAdjustments.identity;
    });
  }

  void _autoTune() {
    HapticFeedback.mediumImpact();
    setState(() {
      _tuneValues[_TuneParam.brightness] = 4;
      _tuneValues[_TuneParam.contrast] = 12;
      _tuneValues[_TuneParam.saturation] = 6;
      _tuneValues[_TuneParam.ambiance] = 8;
    });
    _updateTuneAdjustments();
  }

  void _applyPresetLook(_LookPreset preset) {
    setState(() {
      _selectedPresetId = preset.id;
      _previewAdjustments = preset.adjustments;
    });
  }

  void _cancelActiveTool() {
    final tool = _controls.activeTool;
    if (tool == EditorTool.crop) {
      setState(() {
        if (_cropEntryImage != null) {
          final old = _workingImage;
          _workingImage = _cropEntryImage;
          _cropEntryImage = null;
          old?.dispose();
        }
        _cropFlippedHorizontal = false;
        _cropRectNotifier = null;
        _cropBoxSize = null;
      });
      _controlsController.setCropRotationAngle(0.0);
    } else if (tool == EditorTool.text) {
      if (_textEntrySnapshot != null) {
        if (_editingTextAnnotationIndex != null) {
          _annotationsController.insert(
            _editingTextAnnotationIndex!,
            _textEntrySnapshot!,
          );
        } else {
          _annotationsController.add(_textEntrySnapshot!);
        }
      }
      _activeTextNotifier?.dispose();
      _activeTextNotifier = null;
      _textEntrySnapshot = null;
      _editingTextAnnotationIndex = null;
    } else if (tool == EditorTool.draw) {
      if (_drawSessionSnapshot != null) {
        final nonDraw = _annotations
            .where((a) => a is! DrawingAnnotation)
            .toList();
        _annotationsController.setAll([...nonDraw, ..._drawSessionSnapshot!]);
        _drawSessionSnapshot = null;
      }
    } else if (tool == EditorTool.redact) {
      if (_redactSessionSnapshot != null) {
        final nonRedact = _annotations
            .where((a) => a is! RedactAnnotation)
            .toList();
        _annotationsController.setAll([
          ...nonRedact,
          ..._redactSessionSnapshot!,
        ]);
        _redactSessionSnapshot = null;
      }
      _selectedRedactIndex = null;
      _isAddingRedact = false;
    } else if (tool == EditorTool.tuneImage || tool == EditorTool.looks) {
      _resetTuneValues();
      setState(() {
        _selectedPresetId = 'original';
        _previewAdjustments = ViewerAdjustments.identity;
        _showTuneParamMenu = false;
      });
    }
    _controlsController.clearActiveTool();
  }

  Future<void> _commitActiveTool() async {
    final tool = _controls.activeTool;
    if (tool == EditorTool.crop) {
      await _applyCrop();
    } else if (tool == EditorTool.text) {
      if (_activeTextNotifier != null) {
        _pushUndoSnapshot();
        if (_editingTextAnnotationIndex != null) {
          _annotationsController.insert(
            _editingTextAnnotationIndex!,
            _activeTextNotifier!.value,
          );
        } else {
          _annotationsController.add(_activeTextNotifier!.value);
        }
        _documentController.markEdited();
      }
      _activeTextNotifier?.dispose();
      _activeTextNotifier = null;
      _textEntrySnapshot = null;
      _editingTextAnnotationIndex = null;
      _controlsController.clearActiveTool();
    } else if (tool == EditorTool.draw) {
      _drawSessionSnapshot = null;
      _documentController.markEdited();
      _controlsController.clearActiveTool();
    } else if (tool == EditorTool.redact) {
      _redactSessionSnapshot = null;
      _selectedRedactIndex = null;
      _isAddingRedact = false;
      _documentController.markEdited();
      _controlsController.clearActiveTool();
    } else if (tool == EditorTool.tuneImage || tool == EditorTool.looks) {
      final adj = _previewAdjustments;
      _resetTuneValues();
      setState(() {
        _showTuneParamMenu = false;
        _previewAdjustments = ViewerAdjustments.identity;
        _selectedPresetId = 'original';
      });
      _controlsController.clearActiveTool();
      if (!adj.isIdentity) {
        await _applyColorAdjustments(adj);
      }
    } else {
      _controlsController.clearActiveTool();
    }
  }

  Future<void> _applyColorAdjustments(ViewerAdjustments adjustments) async {
    if (adjustments.isIdentity || _workingImage == null) return;
    _pushUndoSnapshot();
    await _flattenPendingAnnotations();
    if (!mounted || _workingImage == null) return;

    final source = _workingImage!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(
      source,
      Offset.zero,
      Paint()..colorFilter = ColorFilter.matrix(adjustments.toColorMatrix()),
    );
    final picture = recorder.endRecording();
    final adjusted = await picture.toImage(source.width, source.height);
    picture.dispose();
    if (!mounted) {
      adjusted.dispose();
      return;
    }

    setState(() => _workingImage = adjusted);
    _documentController.markEdited();
    source.dispose();
  }

  Future<void> _selectTool(EditorTool tool) async {
    if (_document.isSaving) return;
    if (tool == EditorTool.crop ||
        tool == EditorTool.text ||
        tool == EditorTool.redact ||
        _controls.activeTool == EditorTool.crop ||
        _controls.activeTool == EditorTool.text ||
        _controls.activeTool == EditorTool.redact) {
      _resetZoom(animate: false);
    }
    if (tool == EditorTool.crop) {
      _cropEntryImage?.dispose();
      _cropEntryImage = _workingImage?.clone();
      _controlsController.setCropRotationAngle(0.0);
      _cropFlippedHorizontal = false;
    }
    if (tool == EditorTool.text) {
      _textShelfTab = _TextShelfTab.style;
      _editingTextAnnotationIndex = null;
      _textEntrySnapshot = null;
      _activeTextNotifier = ValueNotifier(
        TextMarkAnnotation(
          position: const Offset(0.5, 0.5),
          text: context.l10n.imageEditorTextPlaceholder,
          color: Colors.white,
          fontSizeFraction: 0.045,
          rotation: 0.0,
          opacity: 1.0,
          styleId: 'L2',
        ),
      );
    }
    if (tool == EditorTool.draw) {
      _drawShelfTab = _DrawShelfTab.color;
      _drawSessionSnapshot = _annotations
          .whereType<DrawingAnnotation>()
          .toList();
    }
    if (tool == EditorTool.redact) {
      _selectedRedactIndex = null;
      _isAddingRedact = true;
      _redactSessionSnapshot = _annotations
          .whereType<RedactAnnotation>()
          .toList();
    }
    if (tool == EditorTool.tuneImage) {
      _resetTuneValues();
    }
    _controlsController.toggleTool(tool);
  }

  void _clearDrawAnnotations() {
    _pushUndoSnapshot();
    final nonDraw = _annotations.where((a) => a is! DrawingAnnotation).toList();
    _annotationsController.setAll(nonDraw);
    _documentController.markEdited();
  }

  void _addNewTextWhileInTextTool() {
    if (_activeTextNotifier == null) return;
    final current = _activeTextNotifier!.value;
    if (current.text.trim().isNotEmpty &&
        current.text != context.l10n.imageEditorTextPlaceholder) {
      _pushUndoSnapshot();
      if (_editingTextAnnotationIndex != null) {
        _annotationsController.insert(_editingTextAnnotationIndex!, current);
      } else {
        _annotationsController.add(current);
      }
      _documentController.markEdited();
    }
    _editingTextAnnotationIndex = null;
    _textEntrySnapshot = null;
    _activeTextNotifier!.value = TextMarkAnnotation(
      position: const Offset(0.5, 0.5),
      text: context.l10n.imageEditorTextPlaceholder,
      color: Colors.white,
      fontSizeFraction: 0.045,
      rotation: 0.0,
      opacity: 1.0,
      styleId: 'L2',
    );
    setState(() => _textShelfTab = _TextShelfTab.style);
  }

  void _selectExistingTextAnnotation(int index) {
    if (index < 0 || index >= _annotations.length) return;
    final target = _annotations[index];
    if (target is! TextMarkAnnotation) return;

    if (_activeTextNotifier != null) {
      final cur = _activeTextNotifier!.value;
      if (cur.text.trim().isNotEmpty &&
          cur.text != context.l10n.imageEditorTextPlaceholder) {
        _pushUndoSnapshot();
        if (_editingTextAnnotationIndex != null) {
          _annotationsController.insert(_editingTextAnnotationIndex!, cur);
        } else {
          _annotationsController.add(cur);
        }
        _documentController.markEdited();
      }
    }

    final newIndex = _annotations.indexOf(target);
    if (newIndex >= 0) {
      _editingTextAnnotationIndex = newIndex;
      _textEntrySnapshot = target;
      _activeTextNotifier?.dispose();
      _activeTextNotifier = ValueNotifier(target);
      _annotationsController.removeAt(newIndex);
    }
    setState(() => _textShelfTab = _TextShelfTab.style);
  }

  void _deleteActiveText() {
    _pushUndoSnapshot();
    _activeTextNotifier?.dispose();
    _activeTextNotifier = null;
    _textEntrySnapshot = null;
    _editingTextAnnotationIndex = null;
    _controlsController.clearActiveTool();
    _documentController.markEdited();
  }

  /// Colour for the active tool: redaction boxes have their own (black by
  /// default); pencil and text share the other.
  Color get _toolColor => _controls.activeTool == EditorTool.redact
      ? _controls.redactColor
      : _controls.currentColor;

  Color get _currentRedactShelfColor {
    final idx = _selectedRedactIndex;
    if (idx != null && idx >= 0 && idx < _annotations.length) {
      final ann = _annotations[idx];
      if (ann is RedactAnnotation) {
        return ann.color;
      }
    }
    return _toolColor;
  }

  void _setToolColor(Color color) {
    if (_controls.activeTool == EditorTool.redact) {
      _controlsController.setRedactColor(color);
      final idx = _selectedRedactIndex;
      if (idx != null && idx >= 0 && idx < _annotations.length) {
        final current = _annotations[idx];
        if (current is RedactAnnotation && current.color != color) {
          if (_isRedactColorWheelInteracting) {
            if (!_hasRedactColorWheelSnapshot) {
              _pushUndoSnapshot();
              _hasRedactColorWheelSnapshot = true;
            }
          } else {
            _pushUndoSnapshot();
          }
          _annotationsController.update(idx, current.copyWith(color: color));
        }
      }
    } else {
      _controlsController.setColor(color);
    }
  }

  void _onRedactColorWheelInteraction(bool interacting) {
    _isRedactColorWheelInteracting = interacting;
    _hasRedactColorWheelSnapshot = false;
  }

  void _addAnnotation(EditAnnotation annotation) {
    _pushUndoSnapshot();
    _annotationsController.add(annotation);
  }

  Future<void> _handleTextTapped(Offset normalizedPosition) async {
    final l10n = context.l10n;
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _TextAnnotationDialog(
        title: l10n.addTextAnnotationTitle,
        hintText: l10n.addTextAnnotationHint,
        cancelLabel: l10n.cancel,
        addLabel: l10n.add,
      ),
    );

    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    _addAnnotation(
      TextMarkAnnotation(
        position: normalizedPosition,
        text: trimmed,
        color: _controls.currentColor,
        fontSizeFraction: _controls.currentFontSizeFraction,
      ),
    );
  }

  Future<void> _showTextEditDialog() async {
    final notifier = _activeTextNotifier;
    if (notifier == null) return;
    final current = notifier.value.text;
    final initialVal = current == context.l10n.imageEditorTextPlaceholder
        ? ''
        : current;
    final l10n = context.l10n;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _TextAnnotationDialog(
        title: l10n.addTextAnnotationTitle,
        hintText: l10n.addTextAnnotationHint,
        cancelLabel: l10n.cancel,
        addLabel: l10n.add,
        initialText: initialVal,
        showDelete:
            _editingTextAnnotationIndex != null ||
            (initialVal.isNotEmpty &&
                _annotations.any((a) => a is TextMarkAnnotation)),
        onDelete: () {
          Navigator.of(dialogContext).pop('__DELETE__');
        },
      ),
    );

    if (result == '__DELETE__') {
      _deleteActiveText();
      return;
    }

    final trimmed = result?.trim();
    if (trimmed != null && trimmed.isNotEmpty && _activeTextNotifier != null) {
      _activeTextNotifier!.value = _activeTextNotifier!.value.copyWith(
        text: trimmed,
      );
    }
  }

  void _deleteSelectedRedactAnnotation() {
    final idx = _selectedRedactIndex;
    if (idx != null && idx >= 0 && idx < _annotations.length) {
      _pushUndoSnapshot();
      _annotationsController.removeAt(idx);
      setState(() => _selectedRedactIndex = null);
      _documentController.markEdited();
      HapticFeedback.mediumImpact();
    }
  }

  void _clearRedactAnnotations() {
    final hasRedact = _annotations.any((a) => a is RedactAnnotation);
    if (!hasRedact) return;
    _pushUndoSnapshot();
    final nonRedact = _annotations
        .where((a) => a is! RedactAnnotation)
        .toList();
    _annotationsController.setAll(nonRedact);
    setState(() => _selectedRedactIndex = null);
    _documentController.markEdited();
    HapticFeedback.mediumImpact();
  }

  void _addRedactAnnotation() {
    setState(() => _isAddingRedact = true);
  }

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

  void _setCropAspect(double? ratio) {
    _controlsController.setCropAspectRatio(ratio);
    final notifier = _cropRectNotifier;
    final boxSize = _cropBoxSize;
    if (notifier == null || boxSize == null) return;
    final angleRad = _controls.cropRotationAngle * math.pi / 180.0;
    notifier.value = _calculateMaxInscribedRect(boxSize, angleRad, ratio);
  }

  Future<void> _applyCrop() async {
    final notifier = _cropRectNotifier;
    final boxSize = _cropBoxSize;
    final src = _workingImage;
    if (notifier == null || boxSize == null || src == null) return;

    _pushUndoSnapshot();

    await _flattenPendingAnnotations();
    if (!mounted || _workingImage == null) return;
    final sourceImage = _workingImage!;

    final w = sourceImage.width.toDouble();
    final h = sourceImage.height.toDouble();

    final scale = w / boxSize.width;

    final localRect = notifier.value;
    final angleDeg = _controls.cropRotationAngle;
    final angleRad = angleDeg * math.pi / 180.0;
    final hasAngle = angleRad.abs() >= 0.001;
    final hasFlip = _cropFlippedHorizontal;

    final destW = (localRect.width * scale).round().clamp(1, (w * 2).toInt());
    final destH = (localRect.height * scale).round().clamp(1, (h * 2).toInt());

    // Center of crop rect relative to canvas center, scaled to source image pixels
    final deltaX = (localRect.center.dx - boxSize.width / 2.0) * scale;
    final deltaY = (localRect.center.dy - boxSize.height / 2.0) * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.save();
    canvas.translate(destW / 2.0, destH / 2.0);
    canvas.translate(-deltaX, -deltaY);
    if (hasFlip) {
      canvas.scale(-1.0, 1.0);
    }
    if (hasAngle) {
      canvas.rotate(angleRad);
    }
    canvas.drawImageRect(
      sourceImage,
      Rect.fromLTWH(0, 0, w, h),
      Rect.fromLTWH(-w / 2.0, -h / 2.0, w, h),
      Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();

    final picture = recorder.endRecording();
    final newImage = await picture.toImage(destW, destH);
    picture.dispose();

    if (!mounted) {
      newImage.dispose();
      return;
    }

    final oldImage = _workingImage;
    setState(() {
      _workingImage = newImage;
      _cropFlippedHorizontal = false;
      _cropRectNotifier = null;
      _cropBoxSize = null;
    });

    _cropEntryImage?.dispose();
    _cropEntryImage = null;
    _controlsController.setCropRotationAngle(0.0);
    _controlsController.clearActiveTool();
    oldImage?.dispose();
    _documentController.markEdited();
  }

  Future<void> _resetToOriginal() async {
    if (!_canReset || _originalBytes == null) return;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.resetImageConfirmTitle),
        content: Text(l10n.resetImageConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.resetImageTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _pushUndoSnapshot();

    final bytes = _originalBytes!;
    _documentController.startLoading();
    try {
      final image = await _decodeImage(bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      final oldImage = _workingImage;
      _resetZoom(animate: false);
      setState(() {
        _workingImage = image;
        _cropRectNotifier = null;
        _cropBoxSize = null;
      });
      _annotationsController.clear();
      _controlsController.resetDocumentControls();
      _documentController.loaded();
      // Nothing is left to save after a reset - unless an earlier overwrite
      // already replaced the file on disk with an edited version. Then the
      // original picture now on screen is itself a change to save.
      if (_overwroteOriginal) {
        _documentController.markEdited();
      } else {
        _documentController.resetEdited();
      }
      oldImage?.dispose();
    } catch (_) {
      if (!mounted) return;
      _documentController.stopLoading();
    }
  }

  // -------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------

  String _uniqueEditedName(
    String originalFileName,
    List<RawEntry> existingEntries,
    bool caseSensitive,
  ) {
    final dot = originalFileName.lastIndexOf('.');
    final base = dot > 0
        ? originalFileName.substring(0, dot)
        : originalFileName;
    bool collides(String name) => existingEntries.any(
      (e) => caseSensitive
          ? e.name == name
          : e.name.toLowerCase() == name.toLowerCase(),
    );
    final ext = _outputExtension;
    final plain = '${base}_edited.$ext';
    if (!collides(plain)) return plain;
    var n = 1;
    while (collides('${base}_edited ($n).$ext')) {
      n++;
    }
    return '${base}_edited ($n).$ext';
  }

  ImageOutputFormat get _outputFormat =>
      imageOutputFormatForExtension(_fileExtension);

  String get _outputExtension =>
      imageOutputExtension(_outputFormat, _fileExtension);

  /// Encodes the working image for saving, in the same family as the file
  /// that was opened (see [ImageOutputFormat]).
  ///
  /// PNG goes through `dart:ui`. JPEG and WebP have no encoder there, so the
  /// raw pixels are handed to the platform encoder; when the edit made the
  /// picture smaller, the encoder is also told how big the result may be so a
  /// crop cannot make the file larger than the share of the original it kept.
  ///
  /// Returns null if encoding failed, so the caller can report it instead of
  /// silently writing a different format than the file's extension promises.
  Future<Uint8List?> _encodeWorkingImage() async {
    final image = _workingImage;
    if (image == null) return null;

    final format = _outputFormat;
    if (format == ImageOutputFormat.png) {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }

    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) return null;
    final original = _originalBytes;
    final budget = original == null
        ? null
        : imageSizeBudgetBytes(
            originalBytes: original.length,
            originalPixels: _originalPixelCount,
            newPixels: image.width * image.height,
          );
    return _fileIoApi.encodeImage(
      rgba: raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      width: image.width,
      height: image.height,
      format: format.name,
      quality: kLossyEncodeQuality,
      maxBytes: budget ?? 0,
    );
  }

  Future<void> _onSavePressed() async {
    if (_document.isSaving ||
        (widget.container?.readOnly ?? false) ||
        _workingImage == null) {
      return;
    }
    _documentController.setSaving(true);
    try {
      await _flattenPendingAnnotations();
      if (!mounted) return;
      final encodedBytes = await _encodeWorkingImage();
      if (!mounted) return;
      if (encodedBytes == null) {
        _documentController.setSaving(false);
        showAppSnackBar(
          context,
          message: context.l10n.imageSaveFailedMessage(
            context.l10n.unknownErrorFallback,
          ),
          tone: AppBannerTone.error,
        );
        return;
      }

      if (widget.imageBytes != null) {
        _documentController.setSaving(false);
        Navigator.of(context).pop(ImageEditorSaveResult(encodedBytes));
        return;
      }

      final container = widget.container;
      final targetPath = widget.filePath;
      if (container == null || targetPath == null) {
        _documentController.setSaving(false);
        Navigator.of(context).pop(encodedBytes);
        return;
      }

      final lastSlash = targetPath.lastIndexOf('/');
      final dirPath = lastSlash == -1 ? '' : targetPath.substring(0, lastSlash);
      final baseName = lastSlash == -1
          ? targetPath
          : targetPath.substring(lastSlash + 1);

      var existingEntries = <RawEntry>[];
      try {
        final raw = await _fileIoApi.listDirectory(container, dirPath);
        if (raw != null) existingEntries = RawEntry.parseAll(raw);
      } catch (e) {
        VeLog.w(
          'ImageEditorScreen',
          'Directory listing failed at ${VeLog.censorUri(dirPath)} during rename conflict check',
          e,
        );
      }
      if (!mounted) return;

      final fsType = resolveFilesystemType(container);
      final caseSensitive = FilesystemRules.of(fsType).caseSensitive;
      final suggested = _uniqueEditedName(
        baseName,
        existingEntries,
        caseSensitive,
      );

      final choice = await SaveImageSheet.show(
        context,
        suggestedFileName: suggested,
        existingEntries: existingEntries,
        fsType: fsType,
        caseSensitive: caseSensitive,
      );
      if (choice == null || !mounted) {
        _documentController.setSaving(false);
        return;
      }

      switch (choice) {
        case SaveAsNewFile(:final fileName):
          await _saveAsNewFile(
            container,
            dirPath,
            fileName,
            fsType,
            encodedBytes,
          );
        case OverwriteOriginal():
          await _saveOverwrite(container, targetPath, encodedBytes);
      }
    } catch (e) {
      if (!mounted) return;
      _documentController.setSaving(false);
      showAppSnackBar(
        context,
        message: context.l10n.imageSaveFailedMessage(e.toString()),
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _saveAsNewFile(
    MountedContainer container,
    String dirPath,
    String fileName,
    FilesystemType fsType,
    Uint8List bytes,
  ) async {
    final built = PathComponents(
      parentSegments: dirPath.isEmpty ? const [] : dirPath.split('/'),
      name: fileName,
      type: EntryType.file,
      fsType: fsType,
    ).validateAndBuild(context.l10n);

    switch (built) {
      case PathBuildFailure(:final issues):
        _documentController.setSaving(false);
        showAppSnackBar(
          context,
          message: context.l10n.imageSaveFailedMessage(issues.first.message),
          tone: AppBannerTone.error,
        );
      case PathBuildSuccess(:final path):
        final ok = await _fileIoApi.writeWholeFile(container, path, bytes);
        if (!mounted) return;
        _documentController.setSaving(false);
        if (ok) {
          _documentController.saved();
          showAppSnackBar(
            context,
            message: context.l10n.imageSavedMessage,
            tone: AppBannerTone.success,
          );
        } else {
          showAppSnackBar(
            context,
            message: context.l10n.imageSaveFailedMessage(
              context.l10n.unknownErrorFallback,
            ),
            tone: AppBannerTone.error,
          );
        }
    }
  }

  Future<void> _saveOverwrite(
    MountedContainer container,
    String filePath,
    Uint8List bytes,
  ) async {
    final ok = await _fileIoApi.writeWholeFile(container, filePath, bytes);
    if (!mounted) return;
    if (!ok) {
      _documentController.setSaving(false);
      showAppSnackBar(
        context,
        message: context.l10n.imageSaveFailedMessage(
          context.l10n.unknownErrorFallback,
        ),
        tone: AppBannerTone.error,
      );
      return;
    }
    _overwroteOriginal = true;
    FullResImageCache.invalidate(container, filePath);
    await ref
        .read(thumbnailCacheServiceProvider)
        .invalidate(
          container,
          filePath,
          qualities: {
            widget.thumbnailQuality,
            ThumbnailQuality.defaultQuality,
          }.toList(),
        );
    if (!mounted) return;
    _documentController.saved();
    showAppSnackBar(
      context,
      message: context.l10n.imageSavedMessage,
      tone: AppBannerTone.success,
    );
  }

  // -------------------------------------------------------------------
  // Exit handling
  // -------------------------------------------------------------------

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;
    final l10n = context.l10n;
    final choice = await showDialog<_ExitChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.unsavedChangesTitle),
        content: Text(l10n.unsavedChangesMessage),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ExitChoice.cancel),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ExitChoice.discard),
            child: Text(l10n.discardButton),
          ),
          if (!(widget.container?.readOnly ?? false))
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExitChoice.save),
              child: Text(l10n.save),
            ),
        ],
      ),
    );
    switch (choice) {
      case _ExitChoice.discard:
        return true;
      case _ExitChoice.save:
        await _onSavePressed();
        return !_isDirty;
      case _ExitChoice.cancel:
      case null:
        return false;
    }
  }

  // -------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------

  Widget _buildShelf() {
    switch (_controls.activeTool) {
      case EditorTool.none:
        return _EditorToolsRow(
          activeTool: _controls.activeTool,
          onSelectTool: _selectTool,
        );
      case EditorTool.crop:
        return _CropShelf(
          cropAspectRatio: _controls.cropAspectRatio,
          cropBoxSize: _cropBoxSize,
          onSetCropAspect: _setCropAspect,
          angle: _controls.cropRotationAngle,
          onAngleChanged: _onRotateAngleChanged,
        );
      case EditorTool.tuneImage:
        return _TuneImageShelf(
          param: _selectedTuneParam,
          value: _tuneValues[_selectedTuneParam] ?? 0,
          onValueChanged: _onTuneValueChanged,
          onToggleParamMenu: () =>
              setState(() => _showTuneParamMenu = !_showTuneParamMenu),
        );
      case EditorTool.looks:
        return _LooksShelf(
          selectedPresetId: _selectedPresetId,
          onSelectPreset: _applyPresetLook,
        );
      case EditorTool.text:
        if (_activeTextNotifier == null) return const SizedBox.shrink();
        return ValueListenableBuilder<TextMarkAnnotation>(
          valueListenable: _activeTextNotifier!,
          builder: (context, activeText, _) {
            return _TextShelf(
              tab: _textShelfTab,
              textAnnotation: activeText,
              onSelectStyle: (styleId) {
                _activeTextNotifier!.value = activeText.copyWith(
                  styleId: styleId,
                );
              },
              onSelectColor: (color) {
                _activeTextNotifier!.value = activeText.copyWith(color: color);
              },
              onColorInteraction: null,
              onOpacityChanged: (opacity) {
                _activeTextNotifier!.value = activeText.copyWith(
                  opacity: opacity,
                );
              },
            );
          },
        );
      case EditorTool.draw:
        return _DrawShelf(
          tab: _drawShelfTab,
          selectedColor: _drawColor,
          opacity: _drawOpacity,
          strokeDiameter: _drawStrokeDiameter,
          onSelectColor: (c) => setState(() => _drawColor = c),
          onColorInteraction: null,
          onOpacityChanged: (op) => setState(() => _drawOpacity = op),
          onStrokeDiameterChanged: (d) =>
              setState(() => _drawStrokeDiameter = d),
        );
      case EditorTool.redact:
        return _RedactShelf(
          selectedColor: _currentRedactShelfColor,
          onSelectColor: _setToolColor,
          onColorInteraction: _onRedactColorWheelInteraction,
        );
    }
  }

  Widget _buildBottomBar() {
    final tool = _controls.activeTool;
    if (tool == EditorTool.none) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final List<Widget> centerActions = switch (tool) {
      EditorTool.crop => [
        _EditorToolActionItem(
          icon: Icons.auto_fix_high_rounded,
          label: l10n.imageEditorActionAuto,
          onTap: () {
            _controlsController.setCropRotationAngle(0.0);
            final notifier = _cropRectNotifier;
            final boxSize = _cropBoxSize;
            if (notifier != null && boxSize != null) {
              notifier.value = _calculateMaxInscribedRect(
                boxSize,
                0.0,
                _controls.cropAspectRatio,
              );
            }
          },
        ),
        _EditorToolActionItem(
          icon: Icons.flip_rounded,
          label: l10n.imageEditorActionFlip,
          onTap: () =>
              setState(() => _cropFlippedHorizontal = !_cropFlippedHorizontal),
        ),
        _EditorToolActionItem(
          icon: Icons.rotate_90_degrees_cw_rounded,
          label: l10n.imageEditorActionRotate,
          onTap: _stepRotate90,
        ),
      ],
      EditorTool.tuneImage => [
        _EditorToolActionItem(
          icon: Icons.auto_fix_high_rounded,
          label: l10n.imageEditorActionAuto,
          onTap: _autoTune,
        ),
        _EditorToolActionItem(
          icon: Icons.restart_alt_rounded,
          label: l10n.reset,
          onTap: _resetTuneValues,
        ),
      ],
      EditorTool.looks => [
        _EditorToolActionItem(
          icon: Icons.restart_alt_rounded,
          label: l10n.cropAspectOriginalLabel,
          onTap: () => _applyPresetLook(_kLookPresets.first),
        ),
      ],
      EditorTool.draw => [
        _EditorToolActionItem(
          icon: Icons.format_color_fill_rounded,
          label: l10n.imageEditorActionColor,
          isSelected: _drawShelfTab == _DrawShelfTab.color,
          onTap: () => setState(() => _drawShelfTab = _DrawShelfTab.color),
        ),
        _EditorToolActionItem(
          icon: Icons.line_weight_rounded,
          label: l10n.imageEditorActionSize,
          isSelected: _drawShelfTab == _DrawShelfTab.size,
          onTap: () => setState(() => _drawShelfTab = _DrawShelfTab.size),
        ),
        _EditorToolActionItem(
          icon: Icons.water_drop_outlined,
          label: l10n.imageEditorActionOpacity,
          isSelected: _drawShelfTab == _DrawShelfTab.opacity,
          onTap: () => setState(() => _drawShelfTab = _DrawShelfTab.opacity),
        ),
        _EditorToolActionItem(
          icon: Icons.delete_outline_rounded,
          label: l10n.clear,
          onTap: _annotations.any((a) => a is DrawingAnnotation)
              ? _clearDrawAnnotations
              : null,
        ),
      ],
      EditorTool.text => [
        _EditorToolActionItem(
          icon: Icons.add_circle_outline_rounded,
          label: l10n.add,
          isSelected: false,
          onTap: _addNewTextWhileInTextTool,
        ),
        _EditorToolActionItem(
          icon: Icons.format_color_fill_rounded,
          label: l10n.imageEditorActionColor,
          isSelected: _textShelfTab == _TextShelfTab.color,
          onTap: () => setState(() => _textShelfTab = _TextShelfTab.color),
        ),
        _EditorToolActionItem(
          icon: Icons.water_drop_outlined,
          label: l10n.imageEditorActionOpacity,
          isSelected: _textShelfTab == _TextShelfTab.opacity,
          onTap: () => setState(() => _textShelfTab = _TextShelfTab.opacity),
        ),
        _EditorToolActionItem(
          icon: Icons.style_rounded,
          label: l10n.imageEditorActionStyle,
          isSelected: _textShelfTab == _TextShelfTab.style,
          onTap: () => setState(() => _textShelfTab = _TextShelfTab.style),
        ),
      ],
      EditorTool.redact => [
        _EditorToolActionItem(
          icon: Icons.add_circle_outline_rounded,
          label: l10n.add,
          isSelected: _isAddingRedact,
          onTap: _addRedactAnnotation,
        ),
        _EditorToolActionItem(
          icon: Icons.delete_rounded,
          label: l10n.delete,
          onTap:
              (_selectedRedactIndex != null &&
                  _selectedRedactIndex! >= 0 &&
                  _selectedRedactIndex! < _annotations.length)
              ? _deleteSelectedRedactAnnotation
              : null,
        ),
        _EditorToolActionItem(
          icon: Icons.delete_sweep_rounded,
          label: l10n.clear,
          onTap: _annotations.any((a) => a is RedactAnnotation)
              ? _clearRedactAnnotations
              : null,
        ),
      ],
      EditorTool.none => const <Widget>[],
    };

    return _EditorToolActionBar(
      onCancel: _cancelActiveTool,
      onApply: _commitActiveTool,
      centerActions: centerActions,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_containerLocked) {
      return const ColoredBox(color: Colors.black, child: SizedBox.expand());
    }
    ref.watch(imageEditorControlsProvider(_controlsKey));
    ref.watch(imageEditorAnnotationsProvider(_controlsKey));
    ref.watch(imageEditorDocumentProvider(_controlsKey));

    final appSkin = ref.watch(appSkinSettingsProvider);
    final editSession = ref.watch(skinEditSessionProvider);
    final skinPreset = editSession == null
        ? appSkin.preset
        : AppSkinPreset.custom;
    final customSkin = editSession?.draft ?? appSkin.customAppSkin;
    final editorTheme =
        buildDarkTheme(
          appSkin: skinPreset,
          customAppSkin: customSkin,
          manualFileManagerSkin: appSkin.fileManagerSkin,
          fileManagerFollowsAppSkin: appSkin.fileManagerFollowsAppSkin,
          editorFollowsAppSkin: appSkin.editorFollowsAppSkin,
        ).copyWith(
          scaffoldBackgroundColor: const Color(0xFF161616),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            systemOverlayStyle: AppSystemUI.transparentDark,
            elevation: 0,
          ),
        );

    return Theme(
      data: editorTheme,
      child: Builder(
        builder: (context) {
          final isLandscape =
              MediaQuery.of(context).orientation == Orientation.landscape;
          final hasError =
              _document.isLoading || _document.errorMessage != null;

          return PopScope(
            canPop: !_isDirty && _controls.activeTool == EditorTool.none,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              if (_controls.activeTool != EditorTool.none) {
                _cancelActiveTool();
                return;
              }
              final shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) Navigator.of(context).pop();
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF161616),
              appBar: _EditorTopBar(
                fileName: _fileName,
                activeTool: _controls.activeTool,
                canUndo: _canUndo,
                hasEdits: _canReset,
                isComparing: _showOriginalCompare,
                allowSequentialCapture: widget.allowSequentialCapture,
                onBack: () async {
                  if (_controls.activeTool != EditorTool.none) {
                    _cancelActiveTool();
                    return;
                  }
                  final shouldPop = await _onWillPop();
                  if (shouldPop && context.mounted) Navigator.of(context).pop();
                },
                onUndo: _undo,
                onCompareStart: () =>
                    setState(() => _showOriginalCompare = true),
                onCompareEnd: () =>
                    setState(() => _showOriginalCompare = false),
                onResetToOriginal: _resetToOriginal,
                onExport: _onSavePressed,
                onContinueCapture: widget.allowSequentialCapture
                    ? _onContinueCapturePressed
                    : null,
              ),
              body: SafeArea(
                top: false,
                bottom: false,
                child: isLandscape
                    ? _LandscapeLayout(
                        body: _buildBody(),
                        hasError: hasError,
                        shelf: _buildShelf(),
                        bottomBar: _buildBottomBar(),
                        isTuneImage:
                            _controls.activeTool == EditorTool.tuneImage,
                        onTunePointerDown: _handleTunePointerDown,
                        onTunePointerMove: _handleTunePointerMove,
                        onTunePointerUp: _handleTunePointerUp,
                        onTunePointerCancel: _handleTunePointerCancel,
                      )
                    : _PortraitLayout(
                        body: _buildBody(),
                        hasError: hasError,
                        shelf: _buildShelf(),
                        bottomBar: _buildBottomBar(),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _onContinueCapturePressed() async {
    if (_document.isSaving || _workingImage == null) return;
    _documentController.setSaving(true);
    try {
      await _flattenPendingAnnotations();
      if (!mounted) return;
      final encodedBytes = await _encodeWorkingImage();
      if (!mounted) return;
      _documentController.setSaving(false);
      if (encodedBytes != null) {
        Navigator.of(context).pop(ImageEditorAddAnotherResult(encodedBytes));
      }
    } catch (_) {
      if (mounted) _documentController.setSaving(false);
    }
  }

  Widget _buildBody() {
    if (_document.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              context.l10n.decryptingFileContent,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    if (_document.errorMessage != null || _workingImage == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.cannotOpenFile,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _document.errorMessage ?? '',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  context.l10n.goBack,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isCropping = _controls.activeTool == EditorTool.crop;

    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != null && _lastOrientation != orientation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetZoom(animate: false);
      });
    }
    _lastOrientation = orientation;

    return LayoutBuilder(
      builder: (context, constraints) {
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          tween: Tween<double>(begin: 0.0, end: isCropping ? 24.0 : 0.0),
          builder: (context, animatedPadding, child) {
            final image = _workingImage!;
            final fitted = _computeFittedRect(
              constraints.biggest,
              image,
              padding: animatedPadding,
              rotationDegrees: 0.0,
            );

            final angleRad = _controls.cropRotationAngle * math.pi / 180.0;

            if (isCropping &&
                (_cropRectNotifier == null || _cropBoxSize != fitted.size)) {
              _cropBoxSize = fitted.size;
              _cropRectNotifier = ValueNotifier(
                _calculateMaxInscribedRect(
                  fitted.size,
                  angleRad,
                  _controls.cropAspectRatio,
                ),
              );
            }

            final isTuneImage = _controls.activeTool == EditorTool.tuneImage;
            final isLooks = _controls.activeTool == EditorTool.looks;
            final isTextTool = _controls.activeTool == EditorTool.text;
            final isDrawTool = _controls.activeTool == EditorTool.draw;

            final canvasContent = SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: fitted,
                    child: CustomPaint(
                      size: fitted.size,
                      painter: _RotatedImagePreviewPainter(
                        image: image,
                        angleRad: (isCropping && !_showOriginalCompare)
                            ? angleRad
                            : 0.0,
                        flipHorizontal:
                            (isCropping && !_showOriginalCompare) &&
                            _cropFlippedHorizontal,
                      ),
                    ),
                  ),
                  if ((isTextTool ||
                          _controls.activeTool == EditorTool.redact) &&
                      !_showOriginalCompare)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onScaleStart: (details) =>
                            _handleCanvasPageScaleStart(details, fitted),
                        onScaleUpdate: (details) =>
                            _handleCanvasPageScaleUpdate(details, fitted.size),
                        onScaleEnd: _handleCanvasPageScaleEnd,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  if (isCropping &&
                      _cropRectNotifier != null &&
                      !_showOriginalCompare)
                    Positioned.fromRect(
                      rect: fitted,
                      child: AnimatedOpacity(
                        opacity: animatedPadding > 18 ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: CropOverlay(
                          imageSize: fitted.size,
                          rectNotifier: _cropRectNotifier!,
                          aspectRatio: _controls.cropAspectRatio,
                          angleRad: angleRad,
                          onAngleDelta: (deltaPx) {
                            final deltaDeg = deltaPx * 0.15;
                            _onRotateAngleChanged(
                              _controls.cropRotationAngle + deltaDeg,
                            );
                          },
                        ),
                      ),
                    ),
                  Positioned.fromRect(
                    rect: fitted,
                    child: Opacity(
                      opacity: _showOriginalCompare ? 0.0 : 1.0,
                      child: IgnorePointer(
                        ignoring:
                            _controls.activeTool == EditorTool.none ||
                            isTuneImage ||
                            isLooks ||
                            isCropping ||
                            isTextTool ||
                            isDrawTool ||
                            _showOriginalCompare,
                        child: AnnotationLayer(
                          imageSize: fitted.size,
                          annotations: _annotations,
                          activeTool: _controls.activeTool,
                          selectedAnnotationIndex: _selectedRedactIndex,
                          isAddingRedact: _isAddingRedact,
                          color: _toolColor,
                          strokeWidthFraction:
                              _controls.currentStrokeWidthFraction,
                          onAnnotationAdded: _addAnnotation,
                          // One undo snapshot per move/resize gesture, taken
                          // before its first change (not one per frame).
                          onAnnotationEditStart: _pushUndoSnapshot,
                          onAnnotationUpdated: (idx, ann) =>
                              _annotationsController.update(idx, ann),
                          onAnnotationRemoved: (idx) {
                            _pushUndoSnapshot();
                            _annotationsController.removeAt(idx);
                            if (_selectedRedactIndex == idx) {
                              setState(() => _selectedRedactIndex = null);
                            }
                          },
                          onSelectedAnnotationChanged: (idx) {
                            setState(() => _selectedRedactIndex = idx);
                          },
                          onRedactAddComplete: () {
                            setState(() => _isAddingRedact = false);
                          },
                          onTextTapped: _handleTextTapped,
                        ),
                      ),
                    ),
                  ),
                  if (isTextTool &&
                      _activeTextNotifier != null &&
                      !_showOriginalCompare)
                    Positioned.fromRect(
                      rect: fitted,
                      child: TextOverlay(
                        imageSize: fitted.size,
                        textNotifier: _activeTextNotifier!,
                        existingAnnotations: _annotations
                            .whereType<TextMarkAnnotation>()
                            .toList(),
                        onSelectExistingText: (matchingIndex) {
                          final textAnns = _annotations
                              .whereType<TextMarkAnnotation>()
                              .toList();
                          if (matchingIndex >= 0 &&
                              matchingIndex < textAnns.length) {
                            final realIdx = _annotations.indexOf(
                              textAnns[matchingIndex],
                            );
                            if (realIdx >= 0) {
                              _selectExistingTextAnnotation(realIdx);
                            }
                          }
                        },
                        onDoubleTap: _showTextEditDialog,
                      ),
                    ),
                ],
              ),
            );

            return Stack(
              children: [
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: isTuneImage ? _handleTunePointerDown : null,
                  onPointerMove: isTuneImage ? _handleTunePointerMove : null,
                  onPointerUp: isTuneImage ? _handleTunePointerUp : null,
                  onPointerCancel: isTuneImage
                      ? _handleTunePointerCancel
                      : null,
                  child: GestureDetector(
                    onDoubleTapDown:
                        (!isTuneImage &&
                            !isCropping &&
                            !isTextTool &&
                            !isDrawTool &&
                            _controls.activeTool == EditorTool.none)
                        ? (details) => _handleDoubleTap(
                            details.localPosition,
                            constraints.biggest,
                          )
                        : null,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 1.0,
                      maxScale: DrawOverlay.kMaxZoomScale,
                      panEnabled:
                          !isCropping &&
                          !isTextTool &&
                          !isDrawTool &&
                          _controls.activeTool == EditorTool.none,
                      scaleEnabled: _controls.activeTool == EditorTool.none,
                      clipBehavior: Clip.hardEdge,
                      child: ColorAdjustFilter(
                        adjustments: _showOriginalCompare
                            ? ViewerAdjustments.identity
                            : _previewAdjustments,
                        child: canvasContent,
                      ),
                    ),
                  ),
                ),
                if (isDrawTool && !_showOriginalCompare)
                  Positioned.fill(
                    child: DrawOverlay(
                      imageRect: fitted,
                      transformationController: _transformationController,
                      color: _drawColor,
                      opacity: _drawOpacity,
                      strokeDiameter: _drawStrokeDiameter,
                      showBrushIndicator: _drawShelfTab == _DrawShelfTab.size,
                      onStrokeCompleted: (stroke) {
                        _pushUndoSnapshot();
                        _annotationsController.add(stroke);
                        _documentController.markEdited();
                      },
                      onStrokeStart: _pushUndoSnapshot,
                      onResetZoom: () => _resetZoom(animate: true),
                    ),
                  ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: AnimatedOpacity(
                    opacity: (!isCropping && _currentScale > 1.05) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: IgnorePointer(
                      ignoring: isCropping || _currentScale <= 1.05,
                      child: ZoomIndicatorPill(
                        scale: _currentScale,
                        onReset: () => _resetZoom(animate: true),
                      ),
                    ),
                  ),
                ),
                if (_showTuneParamMenu && isTuneImage)
                  Positioned.fill(
                    child: _TuneParamOverlay(
                      selectedParam: _selectedTuneParam,
                      values: _tuneValues,
                      isInteractive:
                          _tuneGestureDir == _TuneGestureDirection.undecided,
                      onSelectParam: (param) {
                        setState(() {
                          _selectedTuneParam = param;
                          _showTuneParamMenu = false;
                        });
                      },
                      onDismiss: () =>
                          setState(() => _showTuneParamMenu = false),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _RotatedImagePreviewPainter extends CustomPainter {
  final ui.Image image;
  final double angleRad;
  final bool flipHorizontal;

  _RotatedImagePreviewPainter({
    required this.image,
    required this.angleRad,
    this.flipHorizontal = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    if (flipHorizontal) {
      canvas.scale(-1.0, 1.0);
    }
    canvas.rotate(angleRad);

    final scale = size.width / image.width;
    final drawW = size.width;
    final drawH = image.height * scale;

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(-drawW / 2, -drawH / 2, drawW, drawH),
      Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RotatedImagePreviewPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.angleRad != angleRad ||
      oldDelegate.flipHorizontal != flipHorizontal;
}

class _TextAnnotationDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final String cancelLabel;
  final String addLabel;
  final String initialText;
  final bool showDelete;
  final VoidCallback? onDelete;

  const _TextAnnotationDialog({
    required this.title,
    required this.hintText,
    required this.cancelLabel,
    required this.addLabel,
    this.initialText = '',
    this.showDelete = false,
    this.onDelete,
  });

  @override
  State<_TextAnnotationDialog> createState() => _TextAnnotationDialogState();
}

class _TextAnnotationDialogState extends State<_TextAnnotationDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        if (widget.showDelete && widget.onDelete != null)
          TextButton(
            onPressed: widget.onDelete,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.delete),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.addLabel)),
      ],
    );
  }
}
