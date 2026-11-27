part of 'directory_content_view.dart';

/// Copy, cut and paste, batch delete and export to storage, with the operation listeners they bind.
///
/// Moved out of [_DirectoryContentViewState] unchanged: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _DirectoryFileOperations on _DirectoryContentViewState {
  void _initClipboard({required bool cut}) {
    final selected = _uniqueSelectedBrowserEntries
        .where((item) => !item.insideArchive)
        .toList();
    if (selected.isEmpty) return;
    if (cut && selected.any((item) => item.container.readOnly)) {
      _setStatus(context.l10n.readOnlyCantMove, error: true);
      return;
    }
    _signalActivity();
    final primary = selected.first.container;
    final seen = <(int, String)>{};
    final clipItems = <ClipboardItem>[];
    for (final item in selected) {
      final path = fullPathOf(item.entry, item.currentDirPath);
      if (!seen.add((item.container.volId, path))) continue;
      clipItems.add(
        ClipboardItem(
          path: path,
          isDir: item.entry.isDir,
          sizeBytes: item.entry.isDir ? 0 : item.entry.sizeBytes,
          modifiedSecs: item.entry.modifiedSecs,
          volId: item.container.volId == primary.volId
              ? null
              : item.container.volId,
        ),
      );
    }

    _clip.set(
      volId: primary.volId,
      displayName: primary.displayName,
      cut: cut,
      clipItems: clipItems,
    );
    _syncSelectionToOsClipboard([
      for (final item in selected)
        DesktopTransferEntry(
          container: item.container,
          vaultPath: fullPathOf(item.entry, item.currentDirPath),
          name: item.entry.name,
          isDir: item.entry.isDir,
          sizeBytes: item.entry.isDir ? 0 : item.entry.sizeBytes,
          modifiedSecs: item.entry.modifiedSecs,
        ),
    ], cut: cut);
    exitSelectionMode();
  }

  /// A finished move keeps bookmarks and pins on what was moved: within one
  /// vault they follow it to the new path; moved out to another vault there is
  /// nothing left to point at, so they are dropped.
  void _syncMarksAfterMove(FileOperation op) {
    final moves = <String, String>{};
    for (var i = 0; i < op.items.length; i++) {
      final status = i < op.itemStatuses.length ? op.itemStatuses[i] : null;
      if (status?.result != FileItemResult.success) continue;
      final item = op.items[i];
      final name = op.resolvedDestName(i) ?? item.name;
      moves[item.path] = op.destDirPath.isEmpty
          ? name
          : '${op.destDirPath}/$name';
    }
    if (moves.isEmpty) return;
    if (op.sourceVolId == widget.container.volId) {
      unawaited(_pinsBookmarksNotifier.remapPaths(widget.container, moves));
      return;
    }
    final source = widget.resolveContainer?.call(op.sourceVolId);
    if (source == null) return;
    unawaited(
      ref
          .read(fileBrowserPinsBookmarksProvider(source.volId).notifier)
          .removeDeletedPaths(source, moves.keys.toSet()),
    );
  }

  void _bindOpListener(FileOperation op) {
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        if (op.isCut && !op.isDelete) _syncMarksAfterMove(op);
        final isDirectDest = op.destDirPath == _currentDirPath;
        final isSubdirOfCurrent = op.destDirPath.startsWith(
          _currentDirPath.isEmpty ? '' : '$_currentDirPath/',
        );
        final isCurrentInsideDest = _currentDirPath.startsWith(
          op.destDirPath.isEmpty ? '' : '${op.destDirPath}/',
        );
        // A failed/diskFull/partially-failed op is left in the service's
        // list instead of being dismissed here -- dismissing unconditionally
        // used to wipe the operation out (and its error message with it)
        // the instant it finished, before AppBarTransferButton's
        // "keep showing while there are errors" linger logic or
        // FileOperationsSheet's per-item failure detail ever got a chance
        // to display it. This is exactly why e.g. running out of space
        // mid-import/copy/move used to look like a silent no-op: the
        // status and message were computed correctly, just discarded
        // before anyone could see them. The person (or the sheet's
        // "Clear all") dismisses it explicitly instead.
        final keepVisible = _opNeedsAttention(op);

        if (isDirectDest || isSubdirOfCurrent || isCurrentInsideDest) {
          // This viewport brings itself up to date below, so the service's
          // volume-changed notification for the same copy/move must not make
          // it list the folder a second time. Only plain transfers publish
          // one; if this viewport has moved to an unrelated folder in the
          // meantime it takes the notification like any other view.
          if (op.isTransfer) _ownedOpIds.add(op.id);
          if (_isVisibleTab) {
            _loadDirectoryContents(_currentDirPath, refresh: true).then((_) {
              if (!keepVisible) _opSvc.dismiss(op.id);
            });
          } else {
            _navNotifier.markNeedsRefresh();
            if (!keepVisible) _opSvc.dismiss(op.id);
          }
        } else if (!keepVisible) {
          _opSvc.dismiss(op.id);
        }
      }
    }

    op.addListener(listener);
  }

  void _returnToCategoryAfterOperations(
    List<FileOperation> operations,
    int? returnToTabId,
    String? returnToFilter,
  ) {
    if (operations.isEmpty || returnToTabId == null) return;

    void listener() {
      if (!mounted) {
        for (final op in operations) {
          op.removeListener(listener);
        }
        return;
      }
      final allFinished = operations.every(
        (op) =>
            op.status != FileOperationStatus.pending &&
            op.status != FileOperationStatus.running,
      );
      if (!allFinished) return;

      for (final op in operations) {
        op.removeListener(listener);
      }
      if (!operations.any((op) => op.doneCount > 0)) return;

      final returnTab = ref
          .read(browserTabsProvider(widget.workspaceConfig))
          .tabs
          .where((tab) => tab.tabId == TabId(returnToTabId))
          .firstOrNull;
      if (returnTab == null) return;
      if (returnTab.isCategory) {
        _workspaceNotifier.activate(returnTab.tabId);
      } else if (returnTab.tabId == widget.tabId && returnToFilter != null) {
        _navNotifier.setFilter(returnToFilter);
      }
    }

    for (final op in operations) {
      op.addListener(listener);
    }
    listener();
  }

  /// Drag drops can target a different tab or volume, so this viewport is not
  /// necessarily the destination viewport. Let the service's volume-change
  /// notifications refresh every affected tab instead of claiming the op as
  /// its own destination update.
  void _bindDroppedMoveListener(FileOperation op) {
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (!done) return;
      op.removeListener(listener);
      if (op.isCut && !op.isDelete) _syncMarksAfterMove(op);
      // Not dismissed yet: the placeholders in the destination folder must
      // outlive the re-list that swaps them for the real entries, or they
      // vanish for its duration (see FileOperationService.dismissWhenRefreshed).
      if (!_opNeedsAttention(op)) _opSvc.dismissWhenRefreshed(op.id);
    }

    op.addListener(listener);
  }

  Future<void> _paste() async {
    if (_archiveContext != null) return;
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyCantPaste, error: true);
      return;
    }
    final clip = ref.read(crossContainerClipboardProvider);
    final returnToTabId = clip.returnToTabId;
    final returnToFilter = clip.returnToFilter;

    if (PlatformFeatures.isDesktop) {
      final osClip = await DesktopTransferService.instance.inspectOsClipboard();
      if (!mounted) return;
      final osHasExternal =
          (osClip.hasFiles &&
              !osClip.isOwnFiles &&
              osClip.filePaths.isNotEmpty) ||
          osClip.hasImage;
      final isNonOsMirroredClip =
          clip.isCutOperation || clip.isArchiveCreate || clip.isArchiveExtract;
      final preferOs =
          osHasExternal &&
          (!clip.hasItems ||
              (!isNonOsMirroredClip && !osClip.isOwnFiles) ||
              (isNonOsMirroredClip &&
                  DesktopTransferService.instance
                      .hasExternalClipboardChangedSinceWatermark(osClip)));
      if (preferOs) {
        if (osClip.hasFiles &&
            !osClip.isOwnFiles &&
            osClip.filePaths.isNotEmpty) {
          await _handleExternalDrop(osClip.filePaths);
          return;
        }
        if (osClip.hasImage) {
          final png =
              await DesktopTransferService.instance.readClipboardImagePng();
          if (!mounted) return;
          if (png != null && png.isNotEmpty) {
            await _pasteClipboardImagePng(png);
            return;
          }
        }
      }
    }

    if (!clip.hasItems) return;
    _signalActivity();
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final srcVolId = clip.sourceVolId;
    if (srcVolId == null) {
      _setStatus(context.l10n.clipboardSourceInvalid, error: true);
      _clip.clear();
      return;
    }
    final isCrossContainer = !clip.isFromVolume(widget.container.volId);
    MountedContainer? srcContainer;
    if (isCrossContainer) {
      if (widget.resolveContainer == null) {
        _setStatus(context.l10n.crossContainerPasteNotConfigured, error: true);
        return;
      }
      srcContainer = widget.resolveContainer!(srcVolId);
      if (srcContainer == null) {
        _setStatus(
          context.l10n.crossContainerPasteRequiresBothMounted,
          error: true,
          autoClear: const Duration(seconds: 6),
        );
        _clip.clear();
        return;
      }
    } else {
      srcContainer = widget.container;
    }

    // ── Archive Create Paste ────────────────────────────────────────────
    if (clip.isArchiveCreate) {
      final surviving = <ClipboardItem>[];
      final missingPaths = <String>[];
      for (final item in clip.items) {
        final exists = await fileIoApi.entryExists(
          srcContainer,
          item.path,
          isDir: item.isDir,
        );
        if (exists) {
          surviving.add(item);
        } else {
          missingPaths.add(item.path);
        }
      }
      if (missingPaths.isNotEmpty) {
        ref
            .read(crossContainerClipboardProvider.notifier)
            .removeDeletedPaths(srcVolId, missingPaths);
      }
      if (surviving.isEmpty) {
        _setStatus(context.l10n.bookmarkTargetMissing, error: true);
        _clip.clear();
        return;
      }

      final archiveName = clip.archiveName ?? 'archive.zip';
      final options = await ArchivePasteOptionsSheet.show(
        context,
        isExtract: false,
        archiveName: archiveName,
        destDirPath: _currentDirPath,
        format: clip.archiveFormat,
      );
      if (options == null || !mounted) return;

      final op = _opSvc.enqueueArchiveCreate(
        source: srcContainer,
        dest: widget.container,
        destDirPath: _currentDirPath,
        archiveName: archiveName,
        items: List.of(surviving),
        format: clip.archiveFormat ?? ArchiveFormatType.zip,
        passphrase: clip.passphrase,
        encryptFilenames: clip.encryptFilenames,
        deleteSourceAfter: options.deleteSourceAfter,
        compressionLevel:
            clip.compressionLevel ?? ArchiveCompressionLevel.normal,
        compressionMethod: clip.compressionMethod,
        splitSizeBytes: options.splitSizeBytes,
        l10n: context.l10n,
      );
      _clip.clear();
      _bindOpListener(op);
      _returnToCategoryAfterOperations([op], returnToTabId, returnToFilter);
      return;
    }

    // ── Archive Extract Paste ───────────────────────────────────────────
    if (clip.isArchiveExtract) {
      final archiveName = clip.archiveName ?? 'archive.zip';
      var archiveContext = clip.archiveContext;
      if (archiveContext == null) return;

      if (archiveContext.isNested) {
        final localPath = archiveContext.localPathOrUri;
        if (localPath == null || !await File(localPath).exists()) {
          _setStatus(context.l10n.bookmarkTargetMissing, error: true);
          _clip.clear();
          return;
        }
      } else {
        final targetArchivePath = clip.isPartialExtract
            ? archiveContext.archivePathInContainer
            : clip.items.firstOrNull?.path;
        if (targetArchivePath != null) {
          var exists = await fileIoApi.entryExists(
            srcContainer,
            targetArchivePath,
            isDir: false,
          );
          if (!exists &&
              srcContainer.isLocalStorage &&
              archiveContext.localPathOrUri != null) {
            exists = await File(archiveContext.localPathOrUri!).exists();
          }
          if (!exists) {
            _setStatus(context.l10n.bookmarkTargetMissing, error: true);
            _clip.clear();
            return;
          }
        }
      }

      final options = await ArchivePasteOptionsSheet.show(
        context,
        isExtract: true,
        archiveName: archiveName,
        destDirPath: _currentDirPath,
        isPartialExtract: clip.isPartialExtract,
        itemCount: clip.items.length,
      );
      if (options == null || !mounted) return;

      final verifiedArchive = await _ensureArchivePasswordForExtraction(
        archiveContext,
      );
      if (verifiedArchive == null || !mounted) return;
      archiveContext = verifiedArchive;

      var targetDir = _currentDirPath;
      if (options.extractIntoSubfolder) {
        final stem = p.basenameWithoutExtension(archiveName);
        targetDir = _currentDirPath.isEmpty ? stem : '$_currentDirPath/$stem';
      }

      final archivePath = clip.isPartialExtract
          ? archiveContext.archivePathInContainer
          : clip.items.first.path;

      final totalEntries = clip.isPartialExtract
          ? (clip.selectedEntryPaths?.length ?? 1)
          : archiveContext.allEntries.where((e) => !e.isDirectory).length;

      final op = _opSvc.enqueueArchiveExtract(
        source: srcContainer,
        dest: widget.container,
        destDirPath: targetDir,
        archivePath: archivePath,
        archiveName: archiveName,
        archiveContext: archiveContext,
        selectedEntryPaths: clip.selectedEntryPaths,
        totalEntries: totalEntries,
        deleteArchiveAfter: options.deleteSourceAfter,
        l10n: context.l10n,
      );
      _clip.clear();
      _bindOpListener(op);
      return;
    }

    // ── Standard Copy / Move Paste ──────────────────────────────────────
    // Conflict detection + local-vs-general transfer-mode selection now
    // live in FileBrowserOperationsController (see the note above
    // _fadeScrimOpacity's file for the media-scan equivalent of this
    // note) -- this is just "show the sheet if asked, then hand back to
    // the widget for listener binding", same as before.
    // Items staged from several tabs can live on different volumes; they are
    // transferred as one operation per source volume. A normal clipboard has
    // a single group, which behaves exactly as before.
    final isCut = clip.isCutOperation;
    final groups = <int, List<ClipboardItem>>{};
    for (final item in clip.items) {
      groups.putIfAbsent(item.volId ?? srcVolId, () => []).add(item);
    }

    final survivingGroups = <int, List<ClipboardItem>>{};
    final missingPathsByVol = <int, List<String>>{};
    PerfTrace.count('paste.widget.items', clip.items.length);
    PerfTrace.count('paste.widget.source_groups', groups.length);
    final sourceValidationT0 = PerfTrace.begin();
    for (final group in groups.entries) {
      final groupVolId = group.key;
      final groupIsCross = groupVolId != widget.container.volId;
      final groupSrc = !groupIsCross
          ? widget.container
          : (groupVolId == srcVolId
                ? srcContainer
                : widget.resolveContainer?.call(groupVolId));
      if (groupSrc == null) {
        survivingGroups[groupVolId] = group.value;
        continue;
      }
      final surviving = <ClipboardItem>[];
      final sourceExists = await fileIoApi.entryExistsBatch(groupSrc, [
        for (final item in group.value) (path: item.path, isDir: item.isDir),
      ]);
      for (var index = 0; index < group.value.length; index++) {
        final item = group.value[index];
        if (sourceExists[index]) {
          surviving.add(item);
        } else {
          missingPathsByVol.putIfAbsent(groupVolId, () => []).add(item.path);
        }
      }
      if (surviving.isNotEmpty) {
        survivingGroups[groupVolId] = surviving;
      }
    }
    PerfTrace.end(
      'paste.widget.source_validation',
      sourceValidationT0,
      slowMs: 250,
    );
    for (final entry in missingPathsByVol.entries) {
      ref
          .read(crossContainerClipboardProvider.notifier)
          .removeDeletedPaths(entry.key, entry.value);
    }
    if (survivingGroups.isEmpty) {
      _setStatus(context.l10n.bookmarkTargetMissing, error: true);
      _clip.clear();
      return;
    }

    final groupContainers = <int, MountedContainer>{srcVolId: srcContainer};
    final remainingItems = <(int, ClipboardItem)>[];
    final startedOperations = <FileOperation>[];
    for (final group in survivingGroups.entries) {
      final groupVolId = group.key;
      final groupIsCross = groupVolId != widget.container.volId;
      MountedContainer? groupSrc;
      if (!groupIsCross) {
        groupSrc = widget.container;
      } else if (groupVolId == srcVolId) {
        groupSrc = srcContainer;
      } else {
        groupSrc = widget.resolveContainer?.call(groupVolId);
      }
      if (groupSrc == null) {
        _setStatus(
          context.l10n.crossContainerPasteRequiresBothMounted,
          error: true,
          autoClear: const Duration(seconds: 6),
        );
        remainingItems.addAll(group.value.map((item) => (groupVolId, item)));
        continue;
      }
      groupContainers[groupVolId] = groupSrc;
      final op = await ref
          .read(fileBrowserOperationsControllerProvider)
          .pasteStandardTransfer(
            destContainer: widget.container,
            srcContainer: groupSrc,
            destDirPath: _currentDirPath,
            items: List<ClipboardItem>.from(group.value),
            isCut: isCut,
            isCrossContainer: groupIsCross,
            sourceItemsValidated: true,
            resolveConflicts: (conflicts) async {
              if (!mounted) return null;
              return ConflictResolutionSheet.show(
                context,
                conflicts: conflicts,
                caseSensitive: namesAreCaseSensitive(widget.container),
              );
            },
            l10n: context.l10n,
          );
      if (!mounted) return;
      if (op == null) {
        remainingItems.addAll(group.value.map((item) => (groupVolId, item)));
        continue;
      }
      startedOperations.add(op);
      _bindOpListener(op);
    }
    if (remainingItems.isEmpty) {
      _clip.clear();
    } else {
      final remainingSourceVolId = remainingItems.first.$1;
      final remainingSource = groupContainers[remainingSourceVolId];
      _clip.set(
        volId: remainingSourceVolId,
        displayName:
            remainingSource?.displayName ??
            clip.sourceDisplayName ??
            widget.container.displayName,
        cut: isCut,
        returnToTabId: returnToTabId,
        returnToFilter: returnToFilter,
        clipItems: [
          for (final (volId, item) in remainingItems)
            ClipboardItem(
              path: item.path,
              isDir: item.isDir,
              sizeBytes: item.sizeBytes,
              modifiedSecs: item.modifiedSecs,
              volId: volId == remainingSourceVolId ? null : volId,
            ),
        ],
      );
    }
    if (remainingItems.isEmpty) {
      _returnToCategoryAfterOperations(
        startedOperations,
        returnToTabId,
        returnToFilter,
      );
    }
  }

  void _batchDelete() {
    final selected = _uniqueSelectedBrowserEntries
        .where((item) => !item.insideArchive)
        .toList();
    if (selected.isEmpty) return;
    if (selected.any((item) => item.container.readOnly)) {
      _setStatus(context.l10n.readOnlyCantDelete, error: true);
      return;
    }
    HapticFeedback.heavyImpact();
    _signalActivity();
    BrowserDialogs.showBatchDelete(
      context,
      toDelete: selected.map((item) => item.entry).toList(),
      onConfirmed: (_) {
        exitSelectionMode();
        final groups = <(int, TabId, String), List<_SelectedBrowserEntry>>{};
        for (final item in selected) {
          groups
              .putIfAbsent((
                item.container.volId,
                item.stateKey,
                item.currentDirPath,
              ), () => [])
              .add(item);
        }
        for (final group in groups.values) {
          final container = group.first.container;
          final seenPaths = <String>{};
          final items = <ClipboardItem>[];
          for (final item in group) {
            final path = fullPathOf(item.entry, item.currentDirPath);
            if (seenPaths.add(path)) {
              items.add(ClipboardItem(path: path, isDir: item.entry.isDir));
            }
          }
          if (items.isEmpty) continue;
          final op = _opSvc.enqueueDelete(
            container: container,
            items: items,
            locationLabel: group.first.currentDirPath,
            l10n: context.l10n,
          );
          _ownedOpIds.add(op.id);
          _bindGroupedDeleteListener(
            op,
            container,
            currentDirPath: group.first.currentDirPath,
          );
        }
      },
    );
  }

  void _bindGroupedDeleteListener(
    FileOperation op,
    MountedContainer container, {
    required String currentDirPath,
  }) {
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (!done) return;
      op.removeListener(listener);
      unawaited(() async {
        final successfulPaths = op.itemStatuses
            .where((status) => status.result == FileItemResult.success)
            .map((status) => status.item.path)
            .toSet();
        if (container.volId == widget.container.volId &&
            currentDirPath == _currentDirPath) {
          final deletedNames = successfulPaths
              .map((path) => p.basename(path))
              .toSet();
          if (deletedNames.isNotEmpty) {
            _navNotifier.removeItemsByName(deletedNames);
          }
        }
        if (_searchActive && successfulPaths.isNotEmpty) {
          _searchNotifier.removeDeletedPaths(successfulPaths, _currentDirPath);
        }
        await ref
            .read(fileBrowserPinsBookmarksProvider(container.volId).notifier)
            .removeDeletedPaths(container, successfulPaths);
        ref
            .read(crossContainerClipboardProvider.notifier)
            .removeDeletedPaths(container.volId, successfulPaths);
        if (!mounted) return;
        if (container.volId == widget.container.volId) {
          if (_isVisibleTab) {
            await _loadDirectoryContents(_currentDirPath, refresh: true);
          } else {
            _navNotifier.markNeedsRefresh();
          }
        }
        if (!_opNeedsAttention(op)) _opSvc.dismiss(op.id);
      }());
    }

    op.addListener(listener);
  }

  Future<void> _finishBatchDelete(FileOperation op) async {
    final deletedNames = op.itemStatuses
        .where((s) => s.result == FileItemResult.success)
        .map((s) => s.item.name)
        .toSet();
    final deletedPaths = op.itemStatuses
        .where((s) => s.result == FileItemResult.success)
        .map((s) => s.item.path)
        .toSet();

    if (mounted && deletedNames.isNotEmpty) {
      _navNotifier.removeItemsByName(deletedNames);
    }

    if (mounted && deletedPaths.isNotEmpty && _searchActive) {
      _searchNotifier.removeDeletedPaths(deletedPaths, _currentDirPath);
    }

    await _pinsBookmarksNotifier.removeDeletedPaths(
      widget.container,
      deletedPaths,
    );
    ref
        .read(crossContainerClipboardProvider.notifier)
        .removeDeletedPaths(widget.container.volId, deletedPaths);
    if (!mounted) return;
    if (_isVisibleTab) {
      await _loadDirectoryContents(_currentDirPath, refresh: true);
    } else {
      _navNotifier.markNeedsRefresh();
    }
    if (!_opNeedsAttention(op)) _opSvc.dismiss(op.id);
  }

  void _exportSelectedToStorage() {
    _signalActivity();
    final selected = _uniqueSelectedBrowserEntries
        .where((item) => !item.insideArchive)
        .toList();
    if (selected.isEmpty ||
        selected.map((item) => item.container.volId).toSet().length != 1) {
      return;
    }
    final source = selected.first.container;
    final items = selected.map((item) {
      final path = fullPathOf(item.entry, item.currentDirPath);
      return ClipboardItem(
        path: path,
        isDir: item.entry.isDir,
        sizeBytes: item.entry.sizeBytes,
      );
    }).toList();
    if (items.isEmpty) return;
    exitSelectionMode();
    final op = _opSvc.enqueueExport(
      source: source,
      items: items,
      performExport: (opId) => ref
          .read(vaultFileIoApiProvider)
          .exportSelectedToFolder(
            source,
            items
                .map((i) => <String, dynamic>{'path': i.path, 'isDir': i.isDir})
                .toList(),
            opId: opId,
          ),
      l10n: context.l10n,
    );
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (!done) return;
      op.removeListener(listener);
      // See _opNeedsAttention's doc comment (applied the same way for
      // copy/move/import/delete) -- a failed/partially-failed export (e.g.
      // the destination folder ran out of space) stays in the service's
      // list instead of being dismissed out from under the transfer
      // button/sheet the moment it finishes.
      if (!_opNeedsAttention(op)) _opSvc.dismiss(op.id);
      final count = op.doneCount;
      _setStatus(
        count > 0
            ? context.l10n.exportedCount(count)
            : context.l10n.exportCancelledOrFailed,
        error: count == 0,
      );
    }

    op.addListener(listener);
  }
}
