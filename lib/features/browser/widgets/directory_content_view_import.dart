part of 'directory_content_view.dart';

/// Bringing files in: drag and drop, import from the device, camera and audio capture.
///
/// Moved out of [_DirectoryContentViewState] unchanged: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _DirectoryImportActions on _DirectoryContentViewState {
  /// Runs the copy or move chosen in the drop menu (see
  /// `handleBrowserItemDrop`). Invoked on the viewport the drag started in.
  Future<void> _handleBrowserItemDrop(
    BrowserItemDragData data,
    MountedContainer destination,
    String destinationPath,
    BrowserDropMode mode,
  ) async {
    if (!mounted || data.entries.isEmpty) return;
    final isMove = mode == BrowserDropMode.move;
    if (destination.readOnly || (isMove && data.source.readOnly)) {
      _setStatus(
        isMove ? context.l10n.readOnlyCantMove : context.l10n.readOnlyCantPaste,
        error: true,
      );
      return;
    }
    final allowed = isMove
        ? data.canMoveInto(destination, destinationPath)
        : data.canCopyInto(destination, destinationPath);
    if (!allowed) return;

    // Taken before the first await: the reveal outlives this viewport.
    final providers = ProviderScope.containerOf(context, listen: false);

    final items = data.entries
        .map(
          (entry) => ClipboardItem(
            path: data.pathFor(entry),
            isDir: entry.isDir,
            sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
            modifiedSecs: entry.modifiedSecs,
          ),
        )
        .toList(growable: false);

    _signalActivity();
    final op = await ref
        .read(fileBrowserOperationsControllerProvider)
        .pasteStandardTransfer(
          destContainer: destination,
          srcContainer: data.source,
          destDirPath: destinationPath,
          items: items,
          isCut: isMove,
          isCrossContainer: data.source.volId != destination.volId,
          resolveConflicts: (conflicts) async {
            if (!mounted) return null;
            return ConflictResolutionSheet.show(
              context,
              conflicts: conflicts,
              caseSensitive: namesAreCaseSensitive(destination),
            );
          },
          l10n: context.l10n,
        );
    if (op == null) return;
    _bindDropReveal(op, destination, destinationPath, providers);
    if (!mounted) return;

    ref
        .read(fileBrowserSelectionProvider(_stateKey).notifier)
        .exitSelectionMode();
    _bindDroppedMoveListener(op);
  }

  /// Announces where a finished drop put its items, so the viewport showing
  /// that folder can flash them and scroll one into view. Deliberately not
  /// tied to this viewport: its tab may be gone by the time the copy ends.
  void _bindDropReveal(
    FileOperation op,
    MountedContainer destination,
    String destinationPath,
    ProviderContainer providers,
  ) {
    void onChanged() {
      final done =
          op.status != FileOperationStatus.pending &&
          op.status != FileOperationStatus.running;
      if (!done) return;
      op.removeListener(onChanged);

      final arrived = <String>{};
      for (int i = 0; i < op.items.length; i++) {
        final status = i < op.itemStatuses.length ? op.itemStatuses[i] : null;
        if (status?.result != FileItemResult.success) continue;
        arrived.add(op.resolvedDestName(i) ?? op.items[i].name);
      }
      if (arrived.isEmpty) return;

      final namesByDir = <String, Set<String>>{destinationPath: arrived};
      // A pane showing the folder the items went *into* has nothing new in its
      // listing, so flash that folder's own tile instead.
      if (destinationPath.isNotEmpty) {
        final slash = destinationPath.lastIndexOf('/');
        final parent = slash < 0 ? '' : destinationPath.substring(0, slash);
        final name = slash < 0
            ? destinationPath
            : destinationPath.substring(slash + 1);
        (namesByDir[parent] ??= <String>{}).add(name);
      }
      providers
          .read(browserDropRevealProvider.notifier)
          .publish(volId: destination.volId, namesByDir: namesByDir);
    }

    op.addListener(onChanged);
    onChanged();
  }

  /// [candidateIsDir] is whether the incoming items are folders, for pickers
  /// that only ever bring in one kind. `null` (a drag-and-drop can mix files
  /// and folders) reads it per item from [pick].
  Future<ConflictPlan?> _resolveImportConflicts(
    ImportPickResult pick, {
    required bool? candidateIsDir,
  }) async {
    if (pick.conflicts.isEmpty) return const {};
    final incomingIsDir = {for (final i in pick.items) i.path: i.isDir};
    final entries = pick.conflicts
        .map(
          (c) => ConflictEntry(
            item: ClipboardItem(
              path: c.name,
              isDir: candidateIsDir ?? incomingIsDir[c.name] ?? c.destIsDir,
            ),
            destIsDir: c.destIsDir,
          ),
        )
        .toList();
    if (!mounted) {
      await ref.read(vaultFileIoApiProvider).cancelPickedImport(pick.pickToken);
      return null;
    }
    final result = await ConflictResolutionSheet.show(
      context,
      conflicts: entries,
      cancelLabel: context.l10n.cancelImportButton,
      caseSensitive: namesAreCaseSensitive(widget.container),
    );
    if (result == null) {
      await ref.read(vaultFileIoApiProvider).cancelPickedImport(pick.pickToken);
      return null;
    }
    return result;
  }

  Future<void> _importFilesFromDevice() async {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    _signalActivity();
    final pick = await ref
        .read(vaultFileIoApiProvider)
        .pickFilesForImport(widget.container, _currentDirPath);
    if (pick == null || !mounted) return;
    final conflictPlan = await _resolveImportConflicts(
      pick,
      candidateIsDir: false,
    );
    if (conflictPlan == null) return;
    final op = _opSvc.enqueueImport(
      dest: widget.container,
      destDirPath: _currentDirPath,
      items: pick.items,
      isFolder: false,
      performImport: (opId) => ref
          .read(vaultFileIoApiProvider)
          .importFiles(
            widget.container,
            _currentDirPath,
            opId,
            pick.pickToken,
            conflictPlan: conflictPlan.map((k, v) => MapEntry(k, v.name)),
          ),
      l10n: context.l10n,
    );
    _attachImportCompletionListener(op, isFolder: false);
  }

  /// Why files cannot be dropped on this pane from the OS file manager, or
  /// `null` when they can. Only an unlocked vault folder takes imports (the
  /// same places the "Import files" menu entry is offered).
  String? _externalDropBlockedReason(BuildContext context) {
    if (widget.container.isLocalStorage || _archiveContext != null) {
      return context.l10n.dropImportUnavailableHere;
    }
    if (_isReadOnly) return context.l10n.readOnlyContainerWarning;
    return null;
  }

  /// Files and folders dragged in from the OS file manager (Explorer,
  /// Nautilus, ...) and dropped on this pane. Goes through the same steps as
  /// "Import files": name conflicts are resolved in one sheet, the copy is a
  /// queued transfer with progress, and the delete-originals preference is
  /// honoured afterwards. A drop may mix files and folders.
  Future<void> _handleExternalDrop(List<String> paths) async {
    if (!mounted || paths.isEmpty || !_isVisibleTab) return;
    final blocked = _externalDropBlockedReason(context);
    if (blocked != null) {
      _setStatus(blocked, error: true);
      return;
    }
    _signalActivity();

    // Navigating while the conflict sheet is open must not redirect the
    // import: the conflicts were computed against this folder.
    final container = widget.container;
    final destDirPath = _currentDirPath;
    if (DesktopTransferService.instance.isSameOriginDrop(
      paths,
      destVolId: container.volId,
      destDirPath: destDirPath,
    )) {
      return;
    }
    final fileIo = ref.read(vaultFileIoApiProvider);
    final pinnedDirs = DesktopTransferService.instance.retainImportPaths(paths);
    final skipDeleteSources =
        DesktopTransferService.instance.containsStagedPath(paths);
    var handedToOp = false;

    try {
      final pick = await fileIo.prepareDropImport(container, destDirPath, paths);
      if (!mounted) {
        if (pick != null) unawaited(fileIo.cancelPickedImport(pick.pickToken));
        return;
      }
      if (pick == null) {
        _setStatus(
          context.l10n.dropImportSkippedItems(paths.length),
          error: true,
        );
        return;
      }
      final skipped = paths.length - pick.items.length;

      final conflictPlan = await _resolveImportConflicts(
        pick,
        candidateIsDir: null,
      );
      if (conflictPlan == null || !mounted) return;

      final onlyFolders = pick.items.every((i) => i.isDir);
      final op = _opSvc.enqueueImport(
        dest: container,
        destDirPath: destDirPath,
        items: pick.items,
        isFolder: onlyFolders,
        performImport: (opId) => fileIo.importFiles(
          container,
          destDirPath,
          opId,
          pick.pickToken,
          conflictPlan: conflictPlan.map((k, v) => MapEntry(k, v.name)),
        ),
        l10n: context.l10n,
      );
      _attachImportCompletionListener(
        op,
        isFolder: onlyFolders,
        skipDeleteSources: skipDeleteSources,
        onDone: pinnedDirs.isEmpty
            ? null
            : () => DesktopTransferService.instance.releaseImportPaths(
                pinnedDirs,
              ),
      );
      handedToOp = true;
      if (skipped > 0) {
        _setStatus(context.l10n.dropImportSkippedItems(skipped), error: true);
      }
    } finally {
      if (!handedToOp && pinnedDirs.isNotEmpty) {
        DesktopTransferService.instance.releaseImportPaths(pinnedDirs);
      }
    }
  }

  /// Attaches the "operation finished" listener a queued import (file or
  /// folder) needs: refresh the current directory if the op landed there,
  /// dismiss the operation banner either way, then offer to delete the
  /// import sources once it's actually finished. Was duplicated
  /// identically between _importFilesFromDevice and
  /// _importFolderFromDevice except for the [isFolder] flag passed
  /// through to [_maybeDeleteImportSources].
  void _attachImportCompletionListener(
    FileOperation op, {
    required bool isFolder,
    bool skipDeleteSources = false,
    VoidCallback? onDone,
  }) {
    final fileIo = ref.read(vaultFileIoApiProvider);
    var completedHandled = false;
    void finishOnce() {
      if (completedHandled) return;
      completedHandled = true;
      onDone?.call();
    }

    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        finishOnce();
        unawaited(fileIo.clearImportSources(op.id));
        return;
      }
      final done =
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        finishOnce();
        // See _opNeedsAttention's doc comment (applied the same way in
        // bindOpListener, above) -- a failed/diskFull/partially-failed
        // import stays in the service's list instead of being dismissed out
        // from under the transfer button/sheet the moment it finishes.
        final keepVisible = _opNeedsAttention(op);
        if (op.status == FileOperationStatus.completed &&
            op.destDirPath == _currentDirPath) {
          _ownedOpIds.add(op.id);
          _loadDirectoryContents(_currentDirPath).then((_) {
            _opSvc.dismiss(op.id);
          });
        } else if (!keepVisible) {
          _opSvc.dismiss(op.id);
        }
        if (op.status == FileOperationStatus.completed && !skipDeleteSources) {
          _maybeDeleteImportSources(op, isFolder: isFolder);
        } else {
          unawaited(fileIo.clearImportSources(op.id));
        }
      }
    }

    op.addListener(listener);
  }

  Future<void> _maybeDeleteImportSources(
    FileOperation op, {
    required bool isFolder,
  }) async {
    final fileIo = ref.read(vaultFileIoApiProvider);
    var deletionAttempted = false;
    try {
      if (!mounted) return;
      final settings = await ref
          .read(appSettingsServiceProvider)
          .loadSettings();
      if (!mounted) return;
      _appSettings = settings;

      final records = await ref.read(containerRepositoryProvider).loadAll();
      if (!mounted) return;
      final record = records[widget.container.uri];
      final vaultMode =
          record?.vaultDeleteAfterImportMode ??
          VaultDeleteAfterImportMode.inherit;
      final behavior = vaultMode.resolve(settings.deleteAfterImportMode);

      var shouldDelete = false;
      switch (behavior) {
        case DeleteAfterImportMode.keep:
          break;
        case DeleteAfterImportMode.delete:
          shouldDelete = true;
          break;
        case DeleteAfterImportMode.ask:
          final choice = await DeleteOriginalsDialog.show(
            context,
            isFolder: isFolder,
          );
          if (choice == null || !mounted) return;

          if (choice.dontAskAgain) {
            final selected = choice.confirmed
                ? DeleteAfterImportMode.delete
                : DeleteAfterImportMode.keep;
            try {
              if (record != null) {
                await ref
                    .read(containerRepositoryProvider)
                    .save(
                      record.copyWith(
                        vaultDeleteAfterImportMode:
                            selected == DeleteAfterImportMode.delete
                            ? VaultDeleteAfterImportMode.delete
                            : VaultDeleteAfterImportMode.keep,
                      ),
                    );
              } else {
                final updated = settings.copyWith(
                  deleteAfterImportMode: selected,
                );
                await ref
                    .read(appSettingsServiceProvider)
                    .saveSettings(updated);
                if (mounted) _appSettings = updated;
              }
            } catch (e) {
              VeLog.w(
                'FileBrowserScreen',
                'Could not save the delete-after-import choice',
                e,
              );
            }
          }

          shouldDelete = choice.confirmed;
          break;
      }

      if (!shouldDelete || !mounted) return;
      deletionAttempted = true;
      final deleted = await fileIo.deleteImportSources(op.id);
      if (!mounted) return;
      _setStatus(
        deleted > 0
            ? context.l10n.deletedOriginalCount(deleted)
            : context.l10n.couldNotDeleteOriginals,
        error: deleted == 0,
        autoClear: const Duration(seconds: 3),
      );
    } catch (e) {
      VeLog.e(
        'FileBrowserScreen',
        'Could not resolve delete-after-import behavior',
        e,
      );
    } finally {
      if (!deletionAttempted) {
        await fileIo.clearImportSources(op.id);
      }
    }
  }

  Future<void> _importFolderFromDevice() async {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    _signalActivity();
    final pick = await ref
        .read(vaultFileIoApiProvider)
        .pickFolderForImport(widget.container, _currentDirPath);
    if (pick == null || !mounted) return;
    final conflictPlan = await _resolveImportConflicts(
      pick,
      candidateIsDir: true,
    );
    if (conflictPlan == null) return;
    final op = _opSvc.enqueueImport(
      dest: widget.container,
      destDirPath: _currentDirPath,
      items: pick.items,
      isFolder: true,
      performImport: (opId) => ref
          .read(vaultFileIoApiProvider)
          .importFolder(
            widget.container,
            _currentDirPath,
            opId,
            pick.pickToken,
            conflictPlan: conflictPlan.map((k, v) => MapEntry(k, v.name)),
          ),
      l10n: context.l10n,
    );
    _attachImportCompletionListener(op, isFolder: true);
  }

  /// Follows a video that is still being written after the camera screen
  /// closed: refresh the folder it lands in once it is done, then drop the
  /// operation from the transfer list. A failed or cancelled save stays listed
  /// so its error remains readable (see [_opNeedsAttention]).
  void _attachCaptureSaveCompletionListener(FileOperation op) {
    final willReceiveContentChange =
        op.status == FileOperationStatus.pending ||
        op.status == FileOperationStatus.running;
    void listener() {
      final done =
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (!done) return;
      op.removeListener(listener);
      if (!mounted) {
        // This view is gone, so nothing will refresh for it; just don't leave
        // a finished save in the transfer list (and its placeholder).
        if (op.status == FileOperationStatus.completed) _opSvc.dismiss(op.id);
        return;
      }
      if (op.status == FileOperationStatus.completed) {
        final inCurrentDir = op.destDirPath == _currentDirPath;
        if (inCurrentDir) {
          if (willReceiveContentChange) _ownedOpIds.add(op.id);
          FolderThumbnailPreview.clearSessionCache();
          _loadDirectoryContents(
            _currentDirPath,
            refresh: true,
          ).then((_) => _opSvc.dismiss(op.id));
        } else {
          _opSvc.dismiss(op.id);
        }
      } else if (!_opNeedsAttention(op)) {
        _opSvc.dismiss(op.id);
      }
    }

    // The save may already have finished by the time the screen is popped.
    listener();
    if (op.status == FileOperationStatus.pending ||
        op.status == FileOperationStatus.running) {
      op.addListener(listener);
    }
  }

  Future<void> _captureFromCamera() async {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    _signalActivity();
    try {
      final captured = await Navigator.push<CameraCaptureResult>(
        context,
        MaterialPageRoute(
          builder: (_) => CameraCaptureScreen(
            container: widget.container,
            targetDirPath: _currentDirPath,
          ),
        ),
      );
      if (captured == null || !mounted) return;
      // Videos may still be writing. They report through the transfer UI, so
      // follow them to the end and refresh the listing when they land.
      for (final op in captured.backgroundSaves) {
        _attachCaptureSaveCompletionListener(op);
      }
      final stillSaving = captured.backgroundSaves.any(
        (op) =>
            op.status == FileOperationStatus.pending ||
            op.status == FileOperationStatus.running,
      );
      _setStatus(
        stillSaving
            ? context.l10n.savingLabel
            : captured.isVideo
            ? context.l10n.videoCapturedEncrypted
            : context.l10n.photoCapturedEncrypted,
        autoClear: const Duration(seconds: 3),
      );
    } catch (e) {
      if (mounted) {
        _setStatus(
          context.l10n.cameraCaptureFailed('${e.runtimeType}'),
          error: true,
        );
      }
    }
  }

  Future<void> _recordAudio() async {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    _signalActivity();
    try {
      final savedName = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => AudioCaptureScreen(
            container: widget.container,
            targetDirPath: _currentDirPath,
          ),
        ),
      );
      if (savedName == null || !mounted) return;
      _setStatus(
        context.l10n.audioCapturedEncrypted,
        autoClear: const Duration(seconds: 3),
      );
    } catch (e) {
      if (mounted) {
        _setStatus(
          context.l10n.cameraRecordingFailedWithReasonMessage(
            '${e.runtimeType}',
          ),
          error: true,
        );
      }
    }
  }
}
