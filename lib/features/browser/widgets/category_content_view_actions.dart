part of 'category_content_view.dart';

/// What taps and menu entries do: open, share, stage, export, compress, crypto,
/// rename and edit.
///
/// Moved out of [_CategoryContentViewState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _CategoryActions on _CategoryContentViewState {
  void _onFileTap(RawEntry entry) {
    if (entry is! CategoryEntry) return;
    final selectionNotifier = ref.read(
      fileBrowserSelectionProvider(widget.tabId).notifier,
    );
    final selection = ref.read(fileBrowserSelectionProvider(widget.tabId));
    if (selection.items.isNotEmpty) {
      selectionNotifier.toggleSelectItem(entry);
      return;
    }
    unawaited(_open(entry));
  }

  void _onDirTap(RawEntry entry) {
    if (entry is! CategoryEntry) return;
    final selection = ref.read(fileBrowserSelectionProvider(widget.tabId));
    if (selection.items.isNotEmpty) return;
    _enterFolder(entry);
  }

  void _onItemLongPress(RawEntry entry) {
    if (entry.isDir) return;
    final selection = ref.read(fileBrowserSelectionProvider(widget.tabId));
    if (!selection.isSelectionMode) {
      // First hold: add to selection (not toggle). The drag recogniser in
      // BrowserItemDragItem calls this again when a drag starts, and it
      // must not deselect the item it just selected.
      HapticFeedback.selectionClick();
      ref
          .read(fileBrowserSelectionProvider(widget.tabId).notifier)
          .setSelectedItems({...selection.items, entry});
    } else if (!selection.items.contains(entry)) {
      HapticFeedback.selectionClick();
      ref
          .read(fileBrowserSelectionProvider(widget.tabId).notifier)
          .toggleSelectItem(entry);
    }
    // If already selected in selection mode: do nothing (leave it to drag).
  }

  Future<void> _open(CategoryEntry entry) async {
    final container = _containers[entry.sourceVolId];
    if (container == null) return;
    final name = entry.baseName;
    if (MediaViewerConstants.isSupported(name)) {
      await _openMedia(entry, container);
      return;
    }
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final settings = await ref.read(appSettingsServiceProvider).loadSettings();
    if (!mounted) return;
    final action = decideFileOpenAction(
      ext: ext,
      extensionPreference: settings.extensionPreferences[ext],
      needsSystemAppForLocal:
          container.isLocalStorage && (ext == 'html' || ext == 'htm'),
      isSupportedMedia: false,
    );
    switch (action) {
      case OpenInEditor():
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                TextEditorScreen(container: container, filePath: entry.path),
          ),
        );
      case OpenInPdfViewer():
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PdfViewerScreen(container: container, filePath: entry.path),
          ),
        );
      case OpenWithSystemApp(packageName: final package):
        await _openWithApp(
          container,
          entry,
          packageName: package,
          // See directory_content_view: a saved external-app preference that
          // falls back to the chooser re-learns the app picked there.
          appPickRequestId:
              isExternalAppPreference(settings.extensionPreferences[ext])
              ? armRememberedAppCapture(ref, ext)
              : null,
        );
      default:
        await _openWithApp(container, entry);
    }
  }

  void _ensureTilesVisible(
    List<CategoryEntry> items,
    Set<int> indices, {
    required bool animate,
    required bool center,
    bool clearOfToolbar = true,
  }) {
    final controller = _scrollController;
    if (!controller.hasClients) return;
    final position = controller.position;

    final viewportWidth =
        position.context.notificationContext?.size?.width ??
        MediaQuery.sizeOf(context).width;
    final geometry = _tileGeometries(items, indices, viewportWidth);
    if (geometry.isEmpty) return;

    final maxScroll = position.maxScrollExtent;
    final viewportHeight = position.viewportDimension;
    final currentOffset = position.pixels;
    final topMargin = clearOfToolbar ? 16.0 : 8.0;

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomMargin = clearOfToolbar
        ? AppSpacing.floatingStackClearance + bottomInset + 16.0
        : 8.0;
    final visibleTop = currentOffset + topMargin;
    final visibleBottom = currentOffset + viewportHeight - bottomMargin;
    final bandHeight = viewportHeight - bottomMargin - topMargin;

    double? bestOffset;
    var bestDistance = double.infinity;
    for (final tile in geometry.values) {
      if (tile.top >= visibleTop && (tile.top + tile.height) <= visibleBottom) {
        return;
      }
      final double target;
      if (center) {
        target =
            tile.top -
            topMargin -
            math.max(0.0, (bandHeight - tile.height) / 2);
      } else if (tile.top < visibleTop) {
        target = tile.top - topMargin;
      } else {
        target = (tile.top + tile.height) - viewportHeight + bottomMargin;
      }
      final clamped = target.clamp(0.0, maxScroll).toDouble();
      final distance = (clamped - currentOffset).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestOffset = clamped;
      }
    }

    if (bestOffset == null || bestDistance < 1.0) return;
    if (animate) {
      unawaited(
        controller.animateTo(
          bestOffset,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      controller.jumpTo(bestOffset);
    }
  }

  void _scrollToItem(String fullPath, [int? sourceVolId]) {
    if (!_scrollController.hasClients) return;

    final items = _items;
    final targetName = fullPath.contains('/')
        ? fullPath.substring(fullPath.lastIndexOf('/') + 1)
        : fullPath;

    final targetIndex = items.indexWhere((e) {
      if (sourceVolId != null && e.sourceVolId != sourceVolId) return false;
      return e.path == fullPath || e.baseName == targetName;
    });

    if (targetIndex == -1) return;

    _ensureTilesVisible(items, {targetIndex}, animate: false, center: false);
  }

  Future<void> _openWithApp(
    MountedContainer container,
    CategoryEntry entry, {
    String? packageName,
    String? appPickRequestId,
  }) async {
    try {
      final ok = container.isLocalStorage
          ? await ref
                .read(vaultLocalShareApiProvider)
                .openLocalFileWithApp(
                  p.join(container.uri, entry.path),
                  packageName: packageName,
                  requestId: appPickRequestId,
                )
          : await ref
                .read(vaultFileIoApiProvider)
                .openWithApp(
                  container,
                  entry.path,
                  packageName: packageName,
                  requestId: appPickRequestId,
                );
      if (!ok && mounted) {
        _notify(context.l10n.noAppFoundForFileType, error: true);
      }
    } catch (_) {
      if (mounted) {
        _notify(context.l10n.couldNotOpenFile(entry.baseName), error: true);
      }
    }
  }

  void _notify(String message, {bool error = false}) {
    showAppSnackBar(
      context,
      message: message,
      tone: error ? AppBannerTone.error : AppBannerTone.info,
    );
  }

  Map<int, List<CategoryEntry>> _bySource(List<CategoryEntry> entries) {
    final groups = <int, List<CategoryEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(e.sourceVolId, () => []).add(e);
    }
    return groups;
  }

  Future<void> _toggleSelectedMarks(
    List<CategoryEntry> entries, {
    required bool pin,
    required bool enabled,
  }) async {
    final eligible = entries.where((entry) => !entry.isSourceRoot).toList();
    for (final group in _bySource(eligible).entries) {
      final container = _containers[group.key];
      if (container == null) continue;
      final notifier = ref.read(
        fileBrowserPinsBookmarksProvider(group.key).notifier,
      );
      if (pin) {
        await notifier.togglePins(
          container,
          group.value.map((entry) => entry.path).toSet().toList(),
          pin: enabled,
        );
      } else {
        await notifier.toggleBookmarks(container, [
          for (final entry in group.value)
            VaultBookmark(entry.path, isDir: entry.isDir),
        ], bookmark: enabled);
      }
    }
    if (!mounted) return;
    final count = eligible.length;
    _notify(
      pin
          ? (enabled
                ? context.l10n.pinnedCount(count)
                : context.l10n.unpinnedCount(count))
          : (enabled
                ? context.l10n.bookmarkedCount(count)
                : context.l10n.unbookmarkedCount(count)),
    );
    _clearSelection();
  }

  Future<void> _share(List<CategoryEntry> entries) async {
    final shareable = entries.where((entry) {
      return !entry.isSourceRoot &&
          (entry.isDir || !isVaultItemFileName(entry.baseName));
    }).toList();
    if (shareable.isEmpty) return;
    final groups = _bySource(shareable);
    if (groups.length != 1) {
      _notify(context.l10n.categoryShareOneSource, error: true);
      return;
    }
    final container = _containers[groups.keys.single];
    if (container == null) return;
    try {
      final paths = [for (final e in shareable) e.path];
      final directoryPaths = [
        for (final e in shareable)
          if (e.isDir) e.path,
      ];
      final ok = container.isRawLocal
          ? await ref
                .read(vaultLocalShareApiProvider)
                .shareLocalFiles(
                  [for (final path in paths) p.join(container.uri, path)],
                  directoryPaths: [
                    for (final path in directoryPaths)
                      p.join(container.uri, path),
                  ],
                )
          : await ref
                .read(vaultFileIoApiProvider)
                .shareFiles(
                  container,
                  paths,
                  directoryPaths: directoryPaths,
                  skipExtensions: [
                    for (final type in VaultItemType.values)
                      type.name.toLowerCase(),
                  ],
                );
      if (!ok && mounted) {
        _notify(context.l10n.couldNotShareFiles, error: true);
      }
    } catch (_) {
      if (mounted) _notify(context.l10n.couldNotShareFiles, error: true);
    }
  }

  void _stage(List<CategoryEntry> entries, {required bool cut}) {
    final eligible = entries.where((e) => !e.isSourceRoot).toList();
    if (eligible.isEmpty) return;
    final containers = [
      for (final e in eligible)
        if (_containers[e.sourceVolId] != null) _containers[e.sourceVolId]!,
    ];
    if (cut && containers.any((c) => c.readOnly)) {
      _notify(context.l10n.readOnlyCantMove, error: true);
      return;
    }
    final primary = _containers[eligible.first.sourceVolId];
    if (primary == null) return;
    ref
        .read(crossContainerClipboardProvider.notifier)
        .set(
          volId: primary.volId,
          displayName: primary.displayName,
          cut: cut,
          clipItems: [
            for (final e in eligible)
              ClipboardItem(
                path: e.path,
                isDir: e.isDir,
                sizeBytes: e.sizeBytes,
                modifiedSecs: e.modifiedSecs,
                volId: e.sourceVolId == primary.volId ? null : e.sourceVolId,
              ),
          ],
          returnToTabId: widget.tabId.value,
          returnToFilter: _scoped ? widget.category.filterKey : null,
        );
    _clearSelection();
    if (PlatformFeatures.isDesktop) {
      if (cut) {
        unawaited(DesktopTransferService.instance.markInternalNonOsClipboard());
      } else {
        final transferEntries = <DesktopTransferEntry>[
          for (final e in eligible)
            if (_containers[e.sourceVolId] != null)
              DesktopTransferEntry(
                container: _containers[e.sourceVolId]!,
                vaultPath: e.path,
                name: e.path.split('/').last,
                isDir: e.isDir,
                sizeBytes: e.sizeBytes,
                modifiedSecs: e.modifiedSecs,
              ),
        ];
        if (transferEntries.isNotEmpty) {
          unawaited(
            DesktopTransferService.instance.copyFilesToOsClipboard(
              items: transferEntries,
            ),
          );
          // When exactly one image file is copied, additionally place decoded
          // PNG + bitmap data on the clipboard so the image can be pasted into
          // apps that accept raw image formats without a dedicated menu item.
          if (transferEntries.length == 1 &&
              !transferEntries.first.isDir &&
              MediaViewerConstants.isImage(transferEntries.first.name)) {
            final te = transferEntries.first;
            unawaited(
              DesktopTransferService.instance.copyImageToOsClipboard(
                container: te.container,
                vaultPath: te.vaultPath,
                fileIoApi: ref.read(vaultFileIoApiProvider),
              ),
            );
          }
        }
      }
    }
    _notify(context.l10n.categoryClipboardReady(eligible.length));
    _openFileManagerForStagedItems(eligible);
  }

  void _exportSelection(List<CategoryEntry> entries) {
    final eligible = entries.where((entry) => !entry.isSourceRoot).toList();
    final groups = _bySource(eligible);
    if (groups.length != 1) return;
    final source = _containers[groups.keys.single];
    if (source == null || source.isLocalStorage) return;
    final items = [
      for (final entry in eligible)
        ClipboardItem(
          path: entry.path,
          isDir: entry.isDir,
          sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
        ),
    ];
    if (items.isEmpty) return;

    _clearSelection();
    final opService = ref.read(fileOperationServiceProvider);
    final op = opService.enqueueExport(
      source: source,
      items: items,
      performExport: (opId) =>
          ref.read(vaultFileIoApiProvider).exportSelectedToFolder(source, [
            for (final item in items) {'path': item.path, 'isDir': item.isDir},
          ], opId: opId),
      l10n: context.l10n,
    );
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      if (op.status == FileOperationStatus.running ||
          op.status == FileOperationStatus.pending) {
        return;
      }
      op.removeListener(listener);
      opService.dismiss(op.id);
      _notify(
        op.doneCount > 0
            ? context.l10n.exportedCount(op.doneCount)
            : context.l10n.exportCancelledOrFailed,
        error: op.doneCount == 0,
      );
    }

    op.addListener(listener);
  }

  Future<void> _compressSelection(List<CategoryEntry> entries) async {
    final eligible = entries.where((entry) => !entry.isSourceRoot).toList();
    if (eligible.isEmpty ||
        eligible.any(
          (entry) => entry.sourceVolId != eligible.first.sourceVolId,
        )) {
      return;
    }
    final source = _containers[eligible.first.sourceVolId];
    if (source == null || source.readOnly) return;
    final parent = eligible.first.parentPath;
    final listing =
        await ref.read(vaultFileIoApiProvider).listDirectory(source, parent) ??
        const <String>[];
    if (!mounted) return;

    final selectedEntries = [
      for (final entry in eligible)
        RawEntry(
          name: entry.baseName,
          isDir: entry.isDir,
          sizeBytes: entry.sizeBytes,
          modifiedSecs: entry.modifiedSecs,
          lowercaseName: entry.baseName.toLowerCase(),
          extension: entry.extension,
        ),
    ];
    String stem(RawEntry entry) {
      if (entry.isDir) return entry.name;
      final dot = entry.name.lastIndexOf('.');
      return dot > 0 ? entry.name.substring(0, dot) : entry.name;
    }

    final suggestedName = eligible.length == 1
        ? '${stem(selectedEntries.first)}.zip'
        : '${parent.isEmpty ? source.displayName : parent.split('/').last}.zip';
    _clearSelection();
    BrowserDialogs.showCreateArchive(
      context,
      container: source,
      currentDirPath: parent,
      existingEntries: RawEntry.parseAll(listing),
      suggestedName: suggestedName,
      selectedEntries: selectedEntries,
      readOnly: source.readOnly,
      onCreate:
          (
            destPath,
            format,
            passphrase,
            encryptFilenames,
            compressionLevel,
            compressionMethod,
          ) async {
            ref
                .read(crossContainerClipboardProvider.notifier)
                .setArchiveCreate(
                  volId: source.volId,
                  displayName: source.displayName,
                  clipItems: [
                    for (final entry in eligible)
                      ClipboardItem(
                        path: entry.path,
                        isDir: entry.isDir,
                        sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
                        modifiedSecs: entry.modifiedSecs,
                      ),
                  ],
                  archiveName: destPath.split('/').last,
                  format: format,
                  passphrase: passphrase,
                  encryptFilenames: encryptFilenames,
                  compressionLevel: compressionLevel,
                  compressionMethod: compressionMethod,
                  returnToTabId: widget.tabId.value,
                  returnToFilter: _scoped ? widget.category.filterKey : null,
                );
            if (mounted) {
              _notify(
                '${context.l10n.verbArchiving}: ${destPath.split('/').last}',
              );
              _openFileManagerForStagedItems(eligible);
            }
          },
    );
  }

  Future<void> _runCategoryCrypto(
    List<CategoryEntry> entries,
    CryptoDirection direction,
  ) async {
    final files = entries.where((entry) {
      if (entry.isDir || entry.isSourceRoot) return false;
      final encrypted = isAppEncryptedFileName(entry.baseName);
      return direction == CryptoDirection.encrypt ? !encrypted : encrypted;
    }).toList();
    if (files.isEmpty) return;

    final sources = <CryptoSourceItem>[];
    for (final entry in files) {
      final source = _containers[entry.sourceVolId];
      if (source == null) continue;
      if (source.isLocalStorage) {
        sources.add(
          CryptoSourceItem.external(
            displayName: entry.baseName,
            externalUri: Uri.file(p.join(source.uri, entry.path)).toString(),
          ),
        );
      } else {
        sources.add(
          CryptoSourceItem.vault(
            displayName: entry.baseName,
            container: source,
            relativePath: entry.path,
          ),
        );
      }
    }
    if (sources.isEmpty) return;

    final first = files.first;
    final destinationContainer = _containers[first.sourceVolId];
    if (destinationContainer == null) return;
    final parent = first.parentPath;
    final folderLabel = parent.isEmpty
        ? destinationContainer.displayName
        : '${destinationContainer.displayName} / ${parent.split('/').last}';
    final destination = destinationContainer.isLocalStorage
        ? CryptoDestination.external(
            displayName: folderLabel,
            externalPath: parent.isEmpty
                ? destinationContainer.uri
                : p.join(destinationContainer.uri, parent),
          )
        : CryptoDestination.vault(
            displayName: folderLabel,
            container: destinationContainer,
            relativePath: parent,
          );

    _clearSelection();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SkinAreaScope(
          area: SkinArea.tools,
          child: SingleFileCryptoSheet(
            initialSources: sources,
            initialDestination: destination,
            initialDirection: direction,
            allowEditingSelection: false,
          ),
        ),
      ),
    );
    if (!mounted) return;
    await _startScan(deep: true);
  }

  Future<void> _rename(List<CategoryEntry> entries) async {
    if (entries.isEmpty) return;
    final first = entries.first;
    if (first.isDir || first.isSourceRoot) return;
    if (entries.any(
      (entry) =>
          entry.isDir ||
          entry.isSourceRoot ||
          entry.sourceVolId != first.sourceVolId ||
          entry.parentPath != first.parentPath,
    )) {
      return;
    }
    final container = _containers[first.sourceVolId];
    if (container == null || container.readOnly) return;
    final parent = first.parentPath;
    final listing =
        await ref
            .read(vaultFileIoApiProvider)
            .listDirectory(container, parent) ??
        const <String>[];
    if (!mounted) return;
    await BrowserDialogs.showRename(
      context,
      container: container,
      oldEntries: [
        for (final entry in entries)
          RawEntry(
            name: entry.baseName,
            isDir: false,
            sizeBytes: entry.sizeBytes,
            modifiedSecs: entry.modifiedSecs,
            lowercaseName: entry.baseName.toLowerCase(),
            extension: entry.extension,
          ),
      ],
      existingEntries: RawEntry.parseAll(listing),
      currentDirPath: parent,
      readOnly: container.readOnly,
      onSuccess: () {
        if (!mounted) return;
        _clearSelection();
        unawaited(_startScan(deep: true));
      },
    );
  }

  Future<void> _editImage(CategoryEntry entry) async {
    final container = _containers[entry.sourceVolId];
    if (container == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ImageEditorScreen(container: container, filePath: entry.path),
      ),
    );
    if (!mounted) return;
    unawaited(_startScan(deep: true));
  }

  void _showInFolder(CategoryEntry entry) {
    final container = _containers[entry.sourceVolId];
    final callback = widget.onShowInFolder;
    if (container == null || callback == null) return;
    _clearSelection();
    callback(container, entry.path);
  }

  /// Tags, date and time, and metadata removal for the selected files.
  void _editMetadata(List<CategoryEntry> entries) {
    final targets = <MetadataEditTarget>[
      for (final e in entries)
        if (!e.isDir && _containers[e.sourceVolId] != null)
          MetadataEditTarget(
            container: _containers[e.sourceVolId]!,
            path: e.path,
            sizeBytes: e.sizeBytes,
            modifiedSecs: e.modifiedSecs,
          ),
    ];
    if (targets.isEmpty) return;
    unawaited(
      showMetadataEditMenu(
        context,
        ref,
        targets,
        onChanged: (changed) {
          // An edit can keep a file's size and modified time, which is what
          // the cached metadata is checked against, so drop it explicitly.
          for (final t in changed) {
            _metaIndex?.invalidate(t.container.volId, t.path);
          }
          _clearSelection();
          unawaited(_startScan(keepResults: true));
        },
      ),
    );
  }

  void _showFileInfo(CategoryEntry entry) {
    final container = _containers[entry.sourceVolId];
    if (container == null) return;
    unawaited(
      FileInfoSheet.show(
        context,
        container: container,
        entry: entry.renamedForView(entry.baseName),
        currentDirPath: entry.parentPath,
      ),
    );
  }

  void _copyPath(CategoryEntry entry) {
    final container = _containers[entry.sourceVolId];
    if (container == null) return;
    final path = clipboardPathFor(
      relativePath: entry.path,
      rootPath: container.uri,
      isLocalStorage: container.isLocalStorage,
    );
    unawaited(copyPathToClipboard(context, path));
  }

  String _sourceLabel(
    List<MountedContainer> mountedVaults, [
    AppLocalizations? l10n,
  ]) {
    final effectiveL10n = l10n ?? (mounted ? context.l10n : null);
    final scoped = widget.scopedContainer;
    if (scoped != null) {
      return _sources[scoped.volId]?.label ?? scoped.displayName;
    }
    if (effectiveL10n == null) return '';
    switch (_source.kind) {
      case CategorySourceKind.all:
        return effectiveL10n.categorySourceAll;
      case CategorySourceKind.device:
        return localStorageDisplayName(effectiveL10n.localStorageCardTitle);
      case CategorySourceKind.vaults:
        return effectiveL10n.vaultsSectionTitle;
      case CategorySourceKind.vault:
        for (final v in mountedVaults) {
          if (v.volId == _source.volId) return v.displayName;
        }
        return effectiveL10n.vaultsSectionTitle;
    }
  }

  PopupMenuItem<CategorySourceFilter> _sourceItem(
    CategorySourceFilter filter,
    String label, {
    bool indent = false,
  }) {
    final selected = _source == filter;
    return PopupMenuItem<CategorySourceFilter>(
      value: filter,
      child: Row(
        children: [
          SizedBox(width: indent ? 16 : 0),
          Icon(selected ? Icons.check_rounded : null, size: 18),
          const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  void _showItemMenu(CategoryEntry entry) {
    final container = _containers[entry.sourceVolId];
    if (container == null) return;
    final toolbarConfig = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config;
    final thumbSettings = _thumbs[entry.sourceVolId];
    final isImg = !entry.isDir && MediaViewerConstants.isImage(entry.baseName);
    final actionEntry = entry.renamedForView(entry.baseName);
    FileItemActionsSheet.show(
      context,
      entry: actionEntry,
      container: container,
      currentDirPath: entry.parentPath,
      isReadOnly: container.readOnly,
      isPinned: false,
      isBookmark: false,
      thumbnailCacheMode:
          thumbSettings?.cacheMode ?? ThumbnailCacheMode.appCache,
      thumbnailQuality:
          thumbSettings?.quality ?? ThumbnailQuality.defaultAutoQuality,
      onRename: () => unawaited(_rename([entry])),
      onDelete: () => _delete([entry]),
      onCopy: () => _stage([entry], cut: false),
      onCut: () => _stage([entry], cut: true),
      onTogglePin: () {},
      onToggleBookmark: () {},
      onInfo: () => _showFileInfo(entry),
      onOpenWith: () {
        final c = _containers[entry.sourceVolId];
        if (c != null) unawaited(_openWithApp(c, entry));
      },
      onShare: () => _share([entry]),
      onEditImage: (isImg && !container.readOnly)
          ? () => _editImage(entry)
          : null,
      onEditMetadata: entry.isDir ? null : () => _editMetadata([entry]),
      onCopyPath: () => _copyPath(entry),
      onGoToLocation: widget.onShowInFolder != null
          ? () => _showInFolder(entry)
          : null,
      actionOrder: toolbarConfig.itemActionsOrder,
      hiddenActions: toolbarConfig.hiddenItemActions,
      quickActions: toolbarConfig.quickItemActions,
    );
  }

  void _playMediaFromFirst() {
    final items = _currentItems().where((e) => !e.isDir).toList();
    if (items.isEmpty) return;
    unawaited(_open(items.first));
  }
}
