part of 'image_editor_screen.dart';

/// Encoding the working image and the save, save-as, overwrite and leave flows.
///
/// Moved out of [_ImageEditorScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _ImageEditorSave on _ImageEditorScreenState {
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
        allowOverwrite: !_mustPreserveOriginal,
        notice: _mustPreserveOriginal ? context.l10n.motionPhotoCopyNote : null,
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
        final opService = ref.read(fileOperationServiceProvider);
        final ok = await _fileIoApi.writeWholeFile(container, path, bytes);
        if (ok) opService.notifyVolumeContentChanged(container.volId);
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
    if (_mustPreserveOriginal) {
      _documentController.setSaving(false);
      showAppSnackBar(
        context,
        message: context.l10n.motionPhotoCopyNote,
        tone: AppBannerTone.warning,
      );
      return;
    }
    // Resolve before committing. If link metadata cannot be read safely,
    // writeWholeFile will also refuse the write; do not save successfully and
    // only then fail while trying to discover the cache key to invalidate.
    final targetPath =
        await _fileIoApi.resolveVaultSymlinkTargetPath(
          container,
          filePath,
          strict: true,
        ) ??
        filePath;
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
    // The editor is opened with the shortcut path so the native file API can
    // follow it. Thumbnail widgets, however, are keyed by the resolved target
    // path. Invalidate that path too (and the link path for any older cache
    // entries) or the tile can keep showing the pre-edit preview.
    if (targetPath != filePath) {
      FullResImageCache.invalidate(container, targetPath);
    }
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final qualities = {
      widget.thumbnailQuality,
      ThumbnailQuality.defaultQuality,
    }.toList();
    await thumbnailCache.invalidate(container, filePath, qualities: qualities);
    if (targetPath != filePath) {
      await thumbnailCache.invalidate(
        container,
        targetPath,
        qualities: qualities,
      );
    }
    if (!mounted) return;
    _documentController.saved();
    showAppSnackBar(
      context,
      message: context.l10n.imageSavedMessage,
      tone: AppBannerTone.success,
    );
  }

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
}
