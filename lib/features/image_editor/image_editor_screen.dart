import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/filesystem/path_components.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/features/image_editor/image_output_format.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';
import 'package:vaultexplorer/features/image_editor/widgets/annotation_layer.dart';
import 'package:vaultexplorer/features/image_editor/widgets/crop_overlay.dart';
import 'package:vaultexplorer/features/image_editor/widgets/save_image_sheet.dart';
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
  })  : image = image.clone(),
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

class _ImageEditorScreenState extends ConsumerState<ImageEditorScreen> {
  VaultFileIoApi get _fileIoApi => ref.read(vaultFileIoApiProvider);
  VaultCryptoApi get _cryptoApi => ref.read(vaultCryptoApiProvider);

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

  final List<_EditorSnapshot> _undoStack = [];

  ValueNotifier<Rect>? _cropRectNotifier;
  Size? _cropBoxSize;

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
        return 'Photo ${widget.batchIndex}';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    for (final s in _undoStack) {
      s.dispose();
    }
    _workingImage?.dispose();
    _cropRectNotifier?.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // Undo Snapshot History
  // -------------------------------------------------------------------

  void _pushUndoSnapshot() {
    if (_workingImage == null) return;
    _undoStack.add(
      _EditorSnapshot(
        image: _workingImage!,
        annotations: _annotations,
      ),
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
      if (bytes == null && widget.container != null && widget.filePath != null) {
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
    const snapThreshold = 3.5;
    const snapPoints = [0.0, 90.0, 180.0, 270.0, 360.0];
    for (final snap in snapPoints) {
      if ((angle - snap).abs() <= snapThreshold) {
        if (snap == 360.0) return 0.0;
        return snap;
      }
    }
    return angle % 360.0;
  }

  void _onRotateAngleChanged(double rawAngle) {
    final snapped = _snapRotationAngle(rawAngle);
    if (snapped != _controls.cropRotationAngle) {
      if (snapped == 0.0 || snapped == 90.0 || snapped == 180.0 || snapped == 270.0) {
        HapticFeedback.selectionClick();
      }
      _controlsController.setCropRotationAngle(snapped);
    }
  }

  void _stepRotate90() {
    HapticFeedback.mediumImpact();
    final current = _controls.cropRotationAngle;
    final next = ((current / 90).round() * 90.0 + 90.0) % 360.0;
    _controlsController.setCropRotationAngle(next);
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

  Future<void> _selectTool(EditorTool tool) async {
    if (_document.isSaving) return;
    _controlsController.toggleTool(tool);
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

  void _clearAllAnnotations() {
    if (_annotations.isEmpty) return;
    _pushUndoSnapshot();
    _annotationsController.clear();
  }

  void _setCropAspect(double? ratio) {
    _controlsController.setCropAspectRatio(ratio);
    final notifier = _cropRectNotifier;
    final boxSize = _cropBoxSize;
    if (notifier == null || boxSize == null || ratio == null) return;
    double w = boxSize.width;
    double h = w / ratio;
    if (h > boxSize.height) {
      h = boxSize.height;
      w = h * ratio;
    }
    notifier.value = Rect.fromLTWH(
      (boxSize.width - w) / 2,
      (boxSize.height - h) / 2,
      w,
      h,
    );
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
    final angleDeg = _controls.cropRotationAngle;
    final rad = angleDeg * math.pi / 180.0;

    final cosVal = math.cos(rad).abs();
    final sinVal = math.sin(rad).abs();
    final rotW = math.max(1.0, w * cosVal + h * sinVal);
    final rotH = math.max(1.0, w * sinVal + h * cosVal);

    ui.Image baseImage = sourceImage;

    // Step 1: Render rotation to exact bounding box with no clipping
    if (angleDeg.abs() > 0.05) {
      final rotRecorder = ui.PictureRecorder();
      final rotCanvas = Canvas(rotRecorder);
      rotCanvas.translate(rotW / 2, rotH / 2);
      rotCanvas.rotate(rad);
      rotCanvas.translate(-w / 2, -h / 2);
      rotCanvas.drawImage(sourceImage, Offset.zero, Paint());
      final rotPic = rotRecorder.endRecording();
      baseImage = await rotPic.toImage(rotW.round(), rotH.round());
      rotPic.dispose();
    }

    // Step 2: Crop from the rotated image
    final localRect = notifier.value;
    final nx0 = (localRect.left / boxSize.width).clamp(0.0, 1.0).toDouble();
    final ny0 = (localRect.top / boxSize.height).clamp(0.0, 1.0).toDouble();
    final nx1 = (localRect.right / boxSize.width).clamp(0.0, 1.0).toDouble();
    final ny1 = (localRect.bottom / boxSize.height).clamp(0.0, 1.0).toDouble();

    final srcRect = Rect.fromLTRB(nx0 * rotW, ny0 * rotH, nx1 * rotW, ny1 * rotH);
    final newWidth = srcRect.width.round().clamp(1, baseImage.width).toInt();
    final newHeight = srcRect.height.round().clamp(1, baseImage.height).toInt();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      baseImage,
      srcRect,
      Rect.fromLTWH(0, 0, newWidth.toDouble(), newHeight.toDouble()),
      Paint(),
    );
    final picture = recorder.endRecording();
    final newImage = await picture.toImage(newWidth, newHeight);
    picture.dispose();

    if (baseImage != sourceImage) {
      baseImage.dispose();
    }

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

    _controlsController.setCropRotationAngle(0.0);
    _controlsController.clearActiveTool();
    _documentController.markEdited();
    oldImage?.dispose();
    notifier.dispose();
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
      final dirPath = lastSlash == -1
          ? ''
          : targetPath.substring(0, lastSlash);
      final baseName = lastSlash == -1
          ? targetPath
          : targetPath.substring(lastSlash + 1);

      var existingEntries = <RawEntry>[];
      try {
        final raw = await _fileIoApi.listDirectory(container, dirPath);
        if (raw != null) existingEntries = RawEntry.parseAll(raw);
      } catch (e) {
        VeLog.w('ImageEditorScreen', 'Directory listing failed at ${VeLog.censorUri(dirPath)} during rename conflict check', e);
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
          await _saveAsNewFile(container, dirPath, fileName, fsType, encodedBytes);
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
        final ok = await _fileIoApi.writeWholeFile(
          container,
          path,
          bytes,
        );
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
    final ok = await _fileIoApi.writeWholeFile(
      container,
      filePath,
      bytes,
    );
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

  @override
  Widget build(BuildContext context) {
    ref.watch(imageEditorControlsProvider(_controlsKey));
    ref.watch(imageEditorAnnotationsProvider(_controlsKey));
    ref.watch(imageEditorDocumentProvider(_controlsKey));
    final l10n = context.l10n;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final hasError = _document.isLoading || _document.errorMessage != null;

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(_fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: hasError ? null : _buildAppBarActions(l10n),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: isLandscape
              ? _LandscapeLayout(
                  body: _buildBody(),
                  hasError: hasError,
                  shelf: _ContextualShelf(
                    l10n: l10n,
                    isLandscape: true,
                    activeTool: _controls.activeTool,
                    cropRotationAngle: _controls.cropRotationAngle,
                    cropAspectRatio: _controls.cropAspectRatio,
                    cropBoxSize: _cropBoxSize,
                    onRotateAngleChanged: _onRotateAngleChanged,
                    onResetRotation: () => _controlsController.setCropRotationAngle(0.0),
                    onRotate90: _stepRotate90,
                    onSetCropAspect: _setCropAspect,
                    currentColor: _controls.currentColor,
                    onSetColor: _controlsController.setColor,
                    onShowStrokeWidthPicker: _showStrokeWidthPicker,
                    hasAnnotations: _annotations.isNotEmpty,
                    onClearAllAnnotations: _clearAllAnnotations,
                    onShowFontSizePicker: _showFontSizePicker,
                  ),
                  squaredToolGrid: _SquaredToolGrid(
                    l10n: l10n,
                    activeTool: _controls.activeTool,
                    onSelectTool: _selectTool,
                  ),
                )
              : _PortraitLayout(
                  body: _buildBody(),
                  hasError: hasError,
                  shelf: _ContextualShelf(
                    l10n: l10n,
                    isLandscape: false,
                    activeTool: _controls.activeTool,
                    cropRotationAngle: _controls.cropRotationAngle,
                    cropAspectRatio: _controls.cropAspectRatio,
                    cropBoxSize: _cropBoxSize,
                    onRotateAngleChanged: _onRotateAngleChanged,
                    onResetRotation: () => _controlsController.setCropRotationAngle(0.0),
                    onRotate90: _stepRotate90,
                    onSetCropAspect: _setCropAspect,
                    currentColor: _controls.currentColor,
                    onSetColor: _controlsController.setColor,
                    onShowStrokeWidthPicker: _showStrokeWidthPicker,
                    hasAnnotations: _annotations.isNotEmpty,
                    onClearAllAnnotations: _clearAllAnnotations,
                    onShowFontSizePicker: _showFontSizePicker,
                  ),
                  toolSelectorRow: _ToolSelectorRow(
                    l10n: l10n,
                    activeTool: _controls.activeTool,
                    onSelectTool: _selectTool,
                  ),
                ),
        ),
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

  List<Widget> _buildAppBarActions(AppLocalizations l10n) {
    if (_controls.activeTool == EditorTool.crop) {
      return [
        IconButton(
          icon: const Icon(Icons.check_rounded),
          tooltip: l10n.applyCropTooltip,
          onPressed: _applyCrop,
        ),
      ];
    }
    final actions = <Widget>[
      IconButton(
        icon: const Icon(Icons.undo_rounded),
        tooltip: l10n.undoTooltip,
        onPressed: _canUndo ? _undo : null,
      ),
      IconButton(
        icon: const Icon(Icons.restart_alt_rounded),
        tooltip: l10n.resetImageTooltip,
        onPressed: _canReset ? _resetToOriginal : null,
      ),
    ];

    if (widget.allowSequentialCapture) {
      actions.add(
        IconButton(
          icon: const Icon(Icons.add_a_photo_outlined),
          tooltip: l10n.cameraContinueCaptureTooltip,
          onPressed: _onContinueCapturePressed,
        ),
      );
    }

    if (!(widget.container?.readOnly ?? false)) {
      actions.add(
        _document.isSaving
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.check_rounded),
                tooltip: l10n.cameraSaveMediaTooltip,
                onPressed: _onSavePressed,
              ),
      );
    }
    return actions;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          tween: Tween<double>(
            begin: 0.0,
            end: isCropping ? 24.0 : 0.0,
          ),
          builder: (context, animatedPadding, child) {
            final image = _workingImage!;
            final fitted = _computeFittedRect(
              constraints.biggest,
              image,
              padding: animatedPadding,
              rotationDegrees: isCropping ? _controls.cropRotationAngle : 0.0,
            );

            if (isCropping &&
                (_cropRectNotifier == null || _cropBoxSize != fitted.size)) {
              _cropBoxSize = fitted.size;
              _cropRectNotifier = ValueNotifier(Offset.zero & fitted.size);
            }

            final angleRad = _controls.cropRotationAngle * math.pi / 180.0;

            return Stack(
              children: [
                Positioned.fromRect(
                  rect: fitted,
                  child: ClipRect(
                    child: CustomPaint(
                      size: fitted.size,
                      painter: _RotatedImagePreviewPainter(
                        image: image,
                        angleRad: isCropping ? angleRad : 0.0,
                      ),
                    ),
                  ),
                ),
                if (isCropping && _cropRectNotifier != null)
                  Positioned.fromRect(
                    rect: fitted,
                    child: AnimatedOpacity(
                      opacity: animatedPadding > 18 ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: CropOverlay(
                        imageSize: fitted.size,
                        rectNotifier: _cropRectNotifier!,
                        aspectRatio: _controls.cropAspectRatio,
                      ),
                    ),
                  )
                else
                  Positioned.fromRect(
                    rect: fitted,
                    child: AnnotationLayer(
                      imageSize: fitted.size,
                      annotations: _annotations,
                      activeTool: _controls.activeTool,
                      color: _controls.currentColor,
                      strokeWidthFraction: _controls.currentStrokeWidthFraction,
                      onAnnotationAdded: _addAnnotation,
                      onAnnotationUpdated: (idx, ann) {
                        _pushUndoSnapshot();
                        _annotationsController.update(idx, ann);
                      },
                      onAnnotationRemoved: (idx) {
                        _pushUndoSnapshot();
                        _annotationsController.removeAt(idx);
                      },
                      onTextTapped: _handleTextTapped,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showStrokeWidthPicker() async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final fraction in editorStrokeWidthFractions)
                InkWell(
                  onTap: () => Navigator.of(sheetContext).pop(fraction),
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      width: 12 + fraction * 200,
                      height: 12 + fraction * 200,
                      decoration: BoxDecoration(
                        color: _controls.currentColor,
                        shape: BoxShape.circle,
                        border: _controls.currentStrokeWidthFraction == fraction
                            ? Border.all(
                                color: Theme.of(sheetContext).colorScheme.primary,
                                width: 2,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      _controlsController.setStrokeWidth(selected);
    }
  }

  Future<void> _showFontSizePicker() async {
    final sizes = [
      (label: 'Small', fraction: 0.035, sampleSp: 13.0),
      (label: 'Medium', fraction: 0.055, sampleSp: 17.0),
      (label: 'Large', fraction: 0.085, sampleSp: 22.0),
      (label: 'Extra Large', fraction: 0.125, sampleSp: 28.0),
    ];

    final selected = await showModalBottomSheet<double>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final size in sizes)
              ListTile(
                title: Text(size.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Sample preview ABC 123',
                  style: TextStyle(
                    fontSize: size.sampleSp,
                    color: _controls.currentColor,
                  ),
                ),
                trailing: SizedBox(
                  width: 24,
                  height: 24,
                  child: _controls.currentFontSizeFraction == size.fraction
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                ),
                onTap: () => Navigator.of(sheetContext).pop(size.fraction),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      _controlsController.setFontSize(selected);
    }
  }
}

// ── ACTION PILL BUTTON (ZERO-WIDTH-CONSTRAINTS CRASH PROOF) ─────────────────

class _EditorActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;

  const _EditorActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: isDestructive
          ? Colors.white.withValues(alpha: 0.08)
          : cs.secondaryContainer.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: enabled
                    ? (isDestructive ? cs.error : cs.onSecondaryContainer)
                    : Colors.white24,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? (isDestructive ? cs.error : cs.onSecondaryContainer)
                      : Colors.white24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── FIXED-WIDTH ROTATION RULER (NO 3-DIGIT LAYOUT SHIFT) ─────────────────────

class _AngleRulerDial extends StatefulWidget {
  final double angle;
  final ValueChanged<double> onAngleChanged;
  final VoidCallback onReset;
  final VoidCallback onRotate90;

  const _AngleRulerDial({
    required this.angle,
    required this.onAngleChanged,
    required this.onReset,
    required this.onRotate90,
  });

  @override
  State<_AngleRulerDial> createState() => _AngleRulerDialState();
}

class _AngleRulerDialState extends State<_AngleRulerDial> {
  double? _dragStartAngle;
  double? _dragStartX;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCustomAngle = widget.angle != 0.0;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: GestureDetector(
              onTap: isCustomAngle ? widget.onReset : null,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isCustomAngle ? cs.primary : Colors.white12,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${widget.angle.round()}°',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isCustomAngle ? cs.onPrimary : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                _dragStartX = details.localPosition.dx;
                _dragStartAngle = widget.angle;
              },
              onHorizontalDragUpdate: (details) {
                if (_dragStartX == null || _dragStartAngle == null) return;
                final dx = details.localPosition.dx - _dragStartX!;
                final deltaAngle = -dx * 0.5;
                var newAngle = (_dragStartAngle! + deltaAngle);
                while (newAngle < 0) {
                  newAngle += 360.0;
                }
                newAngle = newAngle % 360.0;
                widget.onAngleChanged(newAngle);
              },
              onHorizontalDragEnd: (_) {
                _dragStartX = null;
                _dragStartAngle = null;
              },
              child: ClipRect(
                child: CustomPaint(
                  size: const Size(double.infinity, 38),
                  painter: _RulerPainter(
                    angle: widget.angle,
                    primaryColor: cs.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          IconButton(
            icon: const Icon(Icons.rotate_90_degrees_cw_rounded, size: 20, color: Colors.white),
            tooltip: '+90°',
            onPressed: widget.onRotate90,
          ),
        ],
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final double angle;
  final Color primaryColor;

  _RulerPainter({required this.angle, required this.primaryColor});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    const pxPerDegree = 4.0;

    final tickPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0;

    final majorTickPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.5;

    final cardinalPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.0;

    final visibleDegrees = (size.width / pxPerDegree) / 2 + 5;
    final minDegree = (angle - visibleDegrees).floor();
    final maxDegree = (angle + visibleDegrees).ceil();

    for (int deg = minDegree; deg <= maxDegree; deg++) {
      final x = centerX + (deg - angle) * pxPerDegree;
      if (x < 0 || x > size.width) continue;

      var normDeg = deg % 360;
      if (normDeg < 0) normDeg += 360;

      final isCardinal = normDeg == 0 || normDeg == 90 || normDeg == 180 || normDeg == 270;
      final isMajor = deg % 10 == 0;
      final isMedium = deg % 5 == 0;

      if (isCardinal) {
        canvas.drawLine(
          Offset(x, centerY - 10),
          Offset(x, centerY + 10),
          cardinalPaint,
        );
      } else if (isMajor) {
        canvas.drawLine(
          Offset(x, centerY - 8),
          Offset(x, centerY + 8),
          majorTickPaint,
        );
      } else if (isMedium) {
        canvas.drawLine(
          Offset(x, centerY - 5),
          Offset(x, centerY + 5),
          tickPaint,
        );
      } else {
        canvas.drawLine(
          Offset(x, centerY - 3),
          Offset(x, centerY + 3),
          tickPaint,
        );
      }
    }

    final needlePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(centerX, centerY - 13),
      Offset(centerX, centerY + 13),
      needlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.primaryColor != primaryColor;
}

class _RotatedImagePreviewPainter extends CustomPainter {
  final ui.Image image;
  final double angleRad;

  _RotatedImagePreviewPainter({
    required this.image,
    required this.angleRad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angleRad);

    final cosVal = math.cos(angleRad).abs();
    final sinVal = math.sin(angleRad).abs();
    final unscaledRotW = math.max(1.0, image.width * cosVal + image.height * sinVal);
    final scale = size.width / unscaledRotW;

    final drawW = image.width * scale;
    final drawH = image.height * scale;

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(-drawW / 2, -drawH / 2, drawW, drawH),
      Paint(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RotatedImagePreviewPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.angleRad != angleRad;
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── SQUARED TOOL CARD (FOR LANDSCAPE SIDEBAR) ───────────────────────────────

class _SquareToolCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SquareToolCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = selected ? cs.primaryContainer : Colors.white.withValues(alpha: 0.08);
    final iconColor = selected ? cs.onPrimaryContainer : Colors.white;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AspectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AspectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: cs.primary,
        labelStyle: TextStyle(color: selected ? cs.onPrimary : Colors.white),
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        side: BorderSide.none,
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _TextAnnotationDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final String cancelLabel;
  final String addLabel;

  const _TextAnnotationDialog({
    required this.title,
    required this.hintText,
    required this.cancelLabel,
    required this.addLabel,
  });

  @override
  State<_TextAnnotationDialog> createState() => _TextAnnotationDialogState();
}

class _TextAnnotationDialogState extends State<_TextAnnotationDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.addLabel),
        ),
      ],
    );
  }
}