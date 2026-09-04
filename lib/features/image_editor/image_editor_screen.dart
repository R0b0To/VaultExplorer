import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/filesystem/path_components.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/features/image_editor/models/edit_annotation.dart';
import 'package:vaultexplorer/features/image_editor/widgets/annotation_layer.dart';
import 'package:vaultexplorer/features/image_editor/widgets/crop_overlay.dart';
import 'package:vaultexplorer/features/image_editor/widgets/save_image_sheet.dart';
import 'image_editor_annotations_controller.dart';
import 'image_editor_controls_controller.dart';
import 'image_editor_document_controller.dart';

class _UnsupportedImageFormatException implements Exception {}

enum _ExitChoice { cancel, discard, save }

/// A simple in-vault image editor: crop, rotate, freehand draw, text
/// labels, and a solid redaction box for blacking out sensitive details --
/// everything stays inside the encrypted container, nothing is ever
/// written to a plaintext temp file or handed to an external app.
///
/// Every operation renders through `dart:ui` (`Canvas`/`PictureRecorder`)
/// rather than a third-party image package, since output only ever needs
/// to be PNG (`ui.Image.toByteData(format: png)` is built into the
/// engine); there's deliberately no attempt to re-encode as JPEG, which
/// `dart:ui` doesn't support and which would need a dependency this
/// project doesn't otherwise carry.
class ImageEditorScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;

  /// Thumbnail quality this caller's views were generated at, so a save
  /// that overwrites the original can invalidate the specific disk-cache
  /// entry those views would otherwise keep serving stale. See
  /// [ThumbnailCacheService.invalidate].
  final ThumbnailQuality thumbnailQuality;

  const ImageEditorScreen({
    super.key,
    required this.container,
    required this.filePath,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
  });

  @override
  ConsumerState<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends ConsumerState<ImageEditorScreen> {
  VaultFileIoApi get _fileIoApi => ref.read(vaultFileIoApiProvider);
  VaultCryptoApi get _cryptoApi => ref.read(vaultCryptoApiProvider);

  Uint8List? _originalBytes;
  ui.Image? _workingImage;

  ValueNotifier<Rect>? _cropRectNotifier;
  Size? _cropBoxSize;

  String get _controlsKey => '${widget.container.uri}\u0000${widget.filePath}';

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

  bool get _isDirty => _document.isEdited || _annotations.isNotEmpty;

  String get _fileName {
    final idx = widget.filePath.lastIndexOf('/');
    return idx == -1 ? widget.filePath : widget.filePath.substring(idx + 1);
  }

  String get _fileExtension {
    final dot = _fileName.lastIndexOf('.');
    return dot == -1 ? '' : _fileName.substring(dot + 1).toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cropRectNotifier?.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // Loading & decoding
  // -------------------------------------------------------------------

  Future<void> _load() async {
    _documentController.startLoading();
    try {
      var bytes = FullResImageCache.get(widget.container, widget.filePath);
      bytes ??= await _fileIoApi.readWholeFile(
        widget.container,
        widget.filePath,
      );
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
    // AVIF isn't decodable via ui.instantiateImageCodec on every Android
    // version this app supports (see NativeAvifWidget), but the native
    // decoder already used for viewing AVIF files works fine here too.
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
      // Covers HEIC and anything else this build's Skia can't decode --
      // there's no dedicated decoder for those the way there is for AVIF.
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

  Rect _computeFittedRect(Size boxSize, ui.Image image) {
    final imageAspect = image.width / image.height;
    final boxAspect = boxSize.width / boxSize.height;
    double w, h;
    if (imageAspect > boxAspect) {
      w = boxSize.width;
      h = w / imageAspect;
    } else {
      h = boxSize.height;
      w = h * imageAspect;
    }
    return Rect.fromLTWH(
      (boxSize.width - w) / 2,
      (boxSize.height - h) / 2,
      w,
      h,
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

  Future<void> _selectTool(EditorTool tool) async {
    if (_document.isSaving) return;
    if (tool == EditorTool.crop) {
      await _flattenPendingAnnotations();
      if (!mounted) return;
    }
    _controlsController.toggleTool(tool);
  }

  void _addAnnotation(EditAnnotation annotation) {
    _annotationsController.add(annotation);
  }

  Future<void> _handleTextTapped(Offset normalizedPosition) async {
    final controller = TextEditingController();
    final l10n = context.l10n;
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.addTextAnnotationTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(hintText: l10n.addTextAnnotationHint),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.add),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    _addAnnotation(
      TextMarkAnnotation(
        position: normalizedPosition,
        text: trimmed,
        color: _controls.currentColor,
        fontSizeFraction: 0.06,
      ),
    );
  }

  void _undo() {
    if (_annotations.isEmpty) return;
    _annotationsController.undo();
  }

  void _clearAllAnnotations() {
    if (_annotations.isEmpty) return;
    _annotationsController.clear();
  }

  Future<void> _rotate({required bool clockwise}) async {
    if (_workingImage == null || _document.isSaving) return;
    await _flattenPendingAnnotations();
    if (!mounted || _workingImage == null) return;
    final src = _workingImage!;
    final w = src.width.toDouble();
    final h = src.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.save();
    canvas.translate(h / 2, w / 2);
    canvas.rotate(clockwise ? math.pi / 2 : -math.pi / 2);
    canvas.translate(-w / 2, -h / 2);
    canvas.drawImage(src, Offset.zero, Paint());
    canvas.restore();
    final picture = recorder.endRecording();
    final newImage = await picture.toImage(h.round(), w.round());
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
    _documentController.markEdited();
    oldImage?.dispose();
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

    final localRect = notifier.value;
    final nx0 = (localRect.left / boxSize.width).clamp(0.0, 1.0).toDouble();
    final ny0 = (localRect.top / boxSize.height).clamp(0.0, 1.0).toDouble();
    final nx1 = (localRect.right / boxSize.width).clamp(0.0, 1.0).toDouble();
    final ny1 = (localRect.bottom / boxSize.height).clamp(0.0, 1.0).toDouble();

    final w = src.width.toDouble();
    final h = src.height.toDouble();
    final srcRect = Rect.fromLTRB(nx0 * w, ny0 * h, nx1 * w, ny1 * h);
    final newWidth = srcRect.width.round().clamp(1, src.width).toInt();
    final newHeight = srcRect.height.round().clamp(1, src.height).toInt();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      src,
      srcRect,
      Rect.fromLTWH(0, 0, newWidth.toDouble(), newHeight.toDouble()),
      Paint(),
    );
    final picture = recorder.endRecording();
    final newImage = await picture.toImage(newWidth, newHeight);
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
    _controlsController.clearActiveTool();
    _documentController.markEdited();
    oldImage?.dispose();
    notifier.dispose();
  }

  Future<void> _resetToOriginal() async {
    if (!_isDirty || _originalBytes == null) return;
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
      _documentController.resetEdited();
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
    final plain = '${base}_edited.png';
    if (!collides(plain)) return plain;
    var n = 1;
    while (collides('${base}_edited ($n).png')) {
      n++;
    }
    return '${base}_edited ($n).png';
  }

  Future<void> _onSavePressed() async {
    if (_document.isSaving ||
        widget.container.readOnly ||
        _workingImage == null) {
      return;
    }
    _documentController.setSaving(true);
    try {
      await _flattenPendingAnnotations();
      if (!mounted) return;
      final byteData = await _workingImage!.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (!mounted) return;
      if (byteData == null) {
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
      final pngBytes = byteData.buffer.asUint8List();

      final lastSlash = widget.filePath.lastIndexOf('/');
      final dirPath = lastSlash == -1
          ? ''
          : widget.filePath.substring(0, lastSlash);
      final baseName = lastSlash == -1
          ? widget.filePath
          : widget.filePath.substring(lastSlash + 1);

      var existingEntries = <RawEntry>[];
      try {
        final raw = await _fileIoApi.listDirectory(widget.container, dirPath);
        if (raw != null) existingEntries = RawEntry.parseAll(raw);
      } catch (_) {
        // Best-effort for the save sheet's live conflict check; the
        // authoritative check still happens via PathComponents below.
      }
      if (!mounted) return;

      final fsType = resolveFilesystemType(widget.container);
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
          await _saveAsNewFile(dirPath, fileName, fsType, pngBytes);
        case OverwriteOriginal():
          await _saveOverwrite(pngBytes);
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
    String dirPath,
    String fileName,
    FilesystemType fsType,
    Uint8List pngBytes,
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
          widget.container,
          path,
          pngBytes,
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

  Future<void> _saveOverwrite(Uint8List pngBytes) async {
    final ok = await _fileIoApi.writeWholeFile(
      widget.container,
      widget.filePath,
      pngBytes,
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
    FullResImageCache.invalidate(widget.container, widget.filePath);
    await ref
        .read(thumbnailCacheServiceProvider)
        .invalidate(
          widget.container,
          widget.filePath,
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
          if (!widget.container.readOnly)
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
          actions: (_document.isLoading || _document.errorMessage != null)
              ? null
              : _buildAppBarActions(l10n),
        ),
        body: SafeArea(top: false, bottom: false, child: _buildBody()),
        bottomNavigationBar:
            (_document.isLoading || _document.errorMessage != null)
            ? null
            : _buildBottomToolbar(l10n),
      ),
    );
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
        onPressed: _annotations.isEmpty ? null : _undo,
      ),
      IconButton(
        icon: const Icon(Icons.restart_alt_rounded),
        tooltip: l10n.resetImageTooltip,
        onPressed: _isDirty ? _resetToOriginal : null,
      ),
    ];
    if (!widget.container.readOnly) {
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
                icon: const Icon(Icons.save_rounded),
                tooltip: l10n.saveChangesTooltip,
                onPressed: _isDirty ? _onSavePressed : null,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final image = _workingImage!;
        final fitted = _computeFittedRect(constraints.biggest, image);

        if (_controls.activeTool == EditorTool.crop &&
            (_cropRectNotifier == null || _cropBoxSize != fitted.size)) {
          _cropBoxSize = fitted.size;
          _cropRectNotifier = ValueNotifier(Offset.zero & fitted.size);
        }

        return Stack(
          children: [
            Positioned.fromRect(
              rect: fitted,
              child: RawImage(image: image, fit: BoxFit.fill),
            ),
            if (_controls.activeTool == EditorTool.crop)
              Positioned.fromRect(
                rect: fitted,
                child: CropOverlay(
                  imageSize: fitted.size,
                  rectNotifier: _cropRectNotifier!,
                  aspectRatio: _controls.cropAspectRatio,
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
                  onTextTapped: _handleTextTapped,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBottomToolbar(AppLocalizations l10n) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [_buildContextualRow(l10n), _buildToolSelectorRow(l10n)],
        ),
      ),
    );
  }

  Widget _buildContextualRow(AppLocalizations l10n) {
    switch (_controls.activeTool) {
      case EditorTool.crop:
        final currentAspect = _cropBoxSize == null
            ? 1.0
            : _cropBoxSize!.width / _cropBoxSize!.height;
        return SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 8),
              _AspectChip(
                label: l10n.cropAspectFreeLabel,
                selected: _controls.cropAspectRatio == null,
                onTap: () => _setCropAspect(null),
              ),
              _AspectChip(
                label: l10n.cropAspectSquareLabel,
                selected: _controls.cropAspectRatio == 1.0,
                onTap: () => _setCropAspect(1.0),
              ),
              _AspectChip(
                label: l10n.cropAspectOriginalLabel,
                selected: _controls.cropAspectRatio == currentAspect,
                onTap: () => _setCropAspect(currentAspect),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.rotate_left_rounded,
                  color: Colors.white,
                ),
                tooltip: l10n.rotateLeftTooltip,
                onPressed: () => _rotate(clockwise: false),
              ),
              IconButton(
                icon: const Icon(
                  Icons.rotate_right_rounded,
                  color: Colors.white,
                ),
                tooltip: l10n.rotateRightTooltip,
                onPressed: () => _rotate(clockwise: true),
              ),
              const SizedBox(width: 4),
            ],
          ),
        );
      case EditorTool.draw:
      case EditorTool.redact:
        return SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final color in editorColorPalette)
                      _ColorSwatch(
                        color: color,
                        selected: color == _controls.currentColor,
                        onTap: () => _controlsController.setColor(color),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: Colors.white),
                tooltip: l10n.annotationStrokeWidthTooltip,
                onPressed: _showStrokeWidthPicker,
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white,
                ),
                tooltip: l10n.clearAnnotationsTooltip,
                onPressed: _annotations.isEmpty ? null : _clearAllAnnotations,
              ),
              const SizedBox(width: 4),
            ],
          ),
        );
      case EditorTool.text:
        return SizedBox(
          height: 36,
          child: Center(
            child: Text(
              l10n.textToolHint,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        );
      case EditorTool.none:
        return const SizedBox(height: 8);
    }
  }

  Widget _buildToolSelectorRow(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolButton(
            icon: Icons.crop_rounded,
            label: l10n.cropToolLabel,
            selected: _controls.activeTool == EditorTool.crop,
            onTap: () => _selectTool(EditorTool.crop),
          ),
          _ToolButton(
            icon: Icons.brush_rounded,
            label: l10n.drawToolLabel,
            selected: _controls.activeTool == EditorTool.draw,
            onTap: () => _selectTool(EditorTool.draw),
          ),
          _ToolButton(
            icon: Icons.text_fields_rounded,
            label: l10n.textToolLabel,
            selected: _controls.activeTool == EditorTool.text,
            onTap: () => _selectTool(EditorTool.text),
          ),
          _ToolButton(
            icon: Icons.visibility_off_outlined,
            label: l10n.redactToolLabel,
            selected: _controls.activeTool == EditorTool.redact,
            onTap: () => _selectTool(EditorTool.redact),
          ),
        ],
      ),
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
                                color: Theme.of(
                                  sheetContext,
                                ).colorScheme.primary,
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
