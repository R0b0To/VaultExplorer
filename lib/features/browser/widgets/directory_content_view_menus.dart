part of 'directory_content_view.dart';

/// Context menus, the item actions sheet, the more menu and the floating toolbar.
///
/// Moved out of [_DirectoryContentViewState] unchanged: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _DirectoryMenus on _DirectoryContentViewState {
  /// Entries of the right-click menu on the empty area of the folder: paste,
  /// "New" (the same actions as the add button), view mode, sort, select all
  /// and refresh. Built when the menu opens so it reflects the current
  /// clipboard, layout and sort.
  List<Widget> _buildFolderBackgroundMenu(BuildContext menuContext) {
    _signalActivity();
    final cs = Theme.of(menuContext).colorScheme;
    final l10n = menuContext.l10n;
    final inArchive = _archiveContext != null;
    final readOnly = _isReadOnly;
    final hasClipboard =
        ref.read(crossContainerClipboardProvider).hasItems ||
        _hasOsClipboardContent;
    final sort = _getSortStateForFolder(_currentDirPath);

    return <Widget>[
      if (!inArchive)
        MenuItemButton(
          leadingIcon: Icon(Icons.content_paste_rounded, color: cs.primary),
          onPressed: hasClipboard && !readOnly
              ? () => unawaited(_paste())
              : null,
          child: Text(l10n.actionPaste),
        ),
      if (inArchive)
        MenuItemButton(
          leadingIcon: Icon(Icons.unarchive_rounded, color: cs.primary),
          onPressed: () => ref
              .read(sessionLockControllerProvider)
              .withLockSuppression(_extractArchive),
          child: Text(l10n.extractArchive),
        )
      else if (readOnly)
        MenuItemButton(
          leadingIcon: Icon(Icons.lock_outline_rounded, color: cs.primary),
          onPressed: () => _setStatus(
            l10n.readOnlyContainerWarning,
            error: true,
          ),
          child: Text(l10n.newItemTooltip),
        )
      else
        SubmenuButton(
          leadingIcon: Icon(Icons.add_rounded, color: cs.primary),
          menuChildren: buildAddItemMenuChildren(
            context: menuContext,
            ref: ref,
            container: widget.container,
            currentDirPath: _currentDirPath,
            currentItems: _currentItems,
            isReadOnly: readOnly,
            hideImportAndSecureItemActions: widget.container.isLocalStorage,
            onCaptureFromCamera: _captureFromCamera,
            onRecordAudio: _recordAudio,
            onImportFilesFromDevice: _importFilesFromDevice,
            onImportFolderFromDevice: _importFolderFromDevice,
            onAddVaultItem: _addVaultItem,
          ),
          child: Text(l10n.newItemTooltip),
        ),
      const PopupMenuDivider(),
      SubmenuButton(
        leadingIcon: Icon(Icons.view_module_rounded, color: cs.onSurfaceVariant),
        menuChildren: buildLayoutModeMenuItems(
          context: menuContext,
          cs: cs,
          layoutMode: _layoutMode,
          onLayoutModeChanged: _onLayoutModeChanged,
          gridAspectRatio: _toolbarConfig.getGridAspectRatioForFolder(
            widget.container.uri,
            _currentDirPath,
          ),
          onGridAspectRatioChanged: _onGridAspectRatioChanged,
        ),
        child: Text(l10n.viewModeAction),
      ),
      SubmenuButton(
        leadingIcon: Icon(
          sortIconFor(sort.sortBy),
          color: cs.onSurfaceVariant,
        ),
        menuChildren: buildSortMenuItems(
          context: menuContext,
          cs: cs,
          sortBy: sort.sortBy,
          sortAscending: sort.sortAscending,
          onSortChanged: _onSortChanged,
        ),
        child: Text(l10n.sortOptionsTooltip),
      ),
      const PopupMenuDivider(),
      MenuItemButton(
        leadingIcon: Icon(Icons.select_all_rounded, color: cs.onSurfaceVariant),
        onPressed: () {
          final displayed = _displayedItemsForScroll();
          if (displayed.isEmpty) return;
          setSelectedItems(displayed.toSet());
          if (selectedFolderCount > 0) {
            fetchFolderSizes(widget.container, _currentDirPath);
          }
        },
        child: Text(l10n.actionSelectAll),
      ),
      MenuItemButton(
        leadingIcon: Icon(Icons.refresh_rounded, color: cs.onSurfaceVariant),
        onPressed: _refreshListing,
        child: Text(l10n.refreshListButton),
      ),
    ];
  }

  /// Covers the body of the directory view: hands tiles the drag lock and the
  /// reveal flash, and tints the whole pane (no border) while another pane's
  /// drag is over it. The tint is shown only for a pane the drag did not start in -- the
  /// source pane would otherwise glow for the entire drag.
  Widget _paneDropChrome(
    BuildContext context, {
    required bool hover,
    required bool locked,
    required Widget body,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return BrowserPaneScope(
      tabId: widget.tabId,
      interactionLocked: locked,
      revealNames: _revealNames,
      revealToken: _revealToken,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: PlatformFeatures.isDesktop
                ? (event) {
                    if ((event.buttons & kSecondaryMouseButton) != 0) {
                      unawaited(_refreshOsClipboardAvailability());
                    }
                  }
                : null,
            child: FolderBackgroundContextMenu(
              // Locked panes (a drag in flight) must not pop a menu.
              enabled: !locked,
              menuBuilder: _buildFolderBackgroundMenu,
              child: body,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: hover && locked ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showItemActionsSheet(RawEntry entry) {
    if (PlatformFeatures.isDesktop && !selectedItems.contains(entry)) {
      _selectOnly(entry);
    }
    _signalActivity();
    HapticFeedback.selectionClick();
    // Opened on one of several selected items (desktop): rename, copy, move
    // and delete act on the whole selection, not on just the one clicked.
    final targets =
        PlatformFeatures.isDesktop &&
            selectedItems.length > 1 &&
            selectedItems.contains(entry)
        ? selectedItems.toList()
        : <RawEntry>[entry];
    final fullPath = _fullPathOf(entry);
    final extension =
        ArchiveService.splitPartExtension(entry.name) ??
        (entry.name.contains('.')
            ? entry.name.split('.').last.toLowerCase()
            : '');
    final canExtract =
        _archiveContext != null ||
        (!entry.isDir && ArchiveService.isOpenableAsArchive(extension));
    FileItemActionsSheet.show(
      context,
      entry: entry,
      container: widget.container,
      currentDirPath: _currentDirPath,
      thumbnailCacheMode: _resolvedThumbnailCacheMode,
      thumbnailQuality: _resolvedThumbnailQuality,
      archiveContext: _archiveContext,
      archiveRootPath: _archiveRootPathForSearch,
      isReadOnly: _isReadOnly,
      isPinned: _isPinned(entry),
      isBookmark: _isBookmark(entry),
      isDocumentProviderMounted: _isFolderMounted(entry),
      onRename: () {
        if (targets.length > 1 && _archiveContext == null) {
          // Several items: the advanced (pattern based) rename.
          unawaited(
            BrowserDialogs.showAdvancedRename(
              context,
              container: widget.container,
              oldEntries: targets,
              existingEntries: _currentItems,
              currentDirPath: _currentDirPath,
              onSuccess: exitSelectionMode,
              readOnly: _isReadOnly,
            ),
          );
          return;
        }
        _startRename(entry);
      },
      onDelete: () {
        BrowserDialogs.showBatchDelete(
          context,
          toDelete: targets,
          onConfirmed: (entries) {
            final clipItems = entries
                .map((e) => ClipboardItem(path: _fullPathOf(e), isDir: e.isDir))
                .toList();
            final op = _opSvc.enqueueDelete(
              container: widget.container,
              items: clipItems,
              locationLabel: _currentDirPath,
              l10n: context.l10n,
            );
            _ownedOpIds.add(op.id);
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
              _finishBatchDelete(op);
            }

            op.addListener(listener);
          },
        );
      },
      onCopy: () {
        final transferEntries = <DesktopTransferEntry>[
          for (final target in targets)
            DesktopTransferEntry(
              container: widget.container,
              vaultPath: _fullPathOf(target),
              name: target.name,
              isDir: target.isDir,
              sizeBytes: target.isDir ? 0 : target.sizeBytes,
              modifiedSecs: target.modifiedSecs,
            ),
        ];
        _clip.set(
          volId: widget.container.volId,
          displayName: widget.container.displayName,
          cut: false,
          clipItems: [
            for (final target in targets)
              ClipboardItem(
                path: _fullPathOf(target),
                isDir: target.isDir,
                sizeBytes: target.isDir ? 0 : target.sizeBytes,
                modifiedSecs: target.modifiedSecs,
              ),
          ],
        );
        _syncSelectionToOsClipboard(transferEntries, cut: false);
        _setStatus(
          context.l10n.copiedSuffix(
            targets.length > 1
                ? context.l10n.folderItemCount(targets.length)
                : entry.name,
          ),
        );
      },
      onCut: () {
        if (_isReadOnly) {
          _setStatus(context.l10n.readOnlyCantMove, error: true);
          return;
        }
        _clip.set(
          volId: widget.container.volId,
          displayName: widget.container.displayName,
          cut: true,
          clipItems: [
            for (final target in targets)
              ClipboardItem(
                path: _fullPathOf(target),
                isDir: target.isDir,
                sizeBytes: target.isDir ? 0 : target.sizeBytes,
                modifiedSecs: target.modifiedSecs,
              ),
          ],
        );
        _syncSelectionToOsClipboard(const [], cut: true);
        _setStatus(context.l10n.clipboardVerbMoving);
      },
      onCopyPath: _archiveContext == null
          ? () => unawaited(_copyItemPath(entry))
          : null,
      onGoToLocation: _searchActive && _archiveContext == null
          ? () => unawaited(_goToItemLocation(entry))
          : null,
      onOpenInNewTab:
          (ref.read(appSettingsControllerProvider).settings.useBrowserTabs &&
              entry.isDir &&
              _archiveContext == null)
          ? () => _openFolderInNewTab(
              widget.container,
              fullPath,
              stateKey: _stateKey,
              selectedEntry: selectedItems.contains(entry) ? entry : null,
            )
          : null,
      onOpenInNewWindow:
          (FileManagerEnvironment.instance.canOpenWindow &&
              entry.isDir &&
              _archiveContext == null)
          ? () => _openFolderInNewWindow(widget.container, fullPath)
          : null,
      onTogglePin: () async {
        await _pinsBookmarksNotifier.togglePins(widget.container, [
          fullPath,
        ], pin: !_isPinned(entry));
      },
      onToggleBookmark: () async {
        await _pinsBookmarksNotifier.toggleBookmarks(widget.container, [
          VaultBookmark(fullPath, isDir: entry.isDir),
        ], bookmark: !_isBookmark(entry));
      },
      onInfo: () {
        FileInfoSheet.show(
          context,
          container: widget.container,
          entry: entry,
          currentDirPath: _currentDirPath,
        );
      },
      onEditMetadata:
          entry.isDir || entry.isPlaceholder || _archiveContext != null
          ? null
          : () => _editMetadata([entry]),
      onExtract: canExtract
          ? () async {
              setSelectedItems({entry});
              await _extractSelectedArchive();
            }
          : null,
      onArchive: _archiveContext == null && !_isReadOnly
          ? () async {
              setSelectedItems({entry});
              await _compressSelected();
            }
          : null,
      onOpenWith: !entry.isDir
          ? () async {
              final parts = entry.name.split('.');
              final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
              final settings = await ref
                  .read(appSettingsServiceProvider)
                  .loadSettings();
              if (mounted) {
                await _showOpenWithDialog(entry.name, fullPath, ext, settings);
              }
            }
          : null,
      onShare: () async {
        // Only plain on-disk storage goes through the local share API; a SAF
        // tree is also a negative-volId "local" container, but has no real
        // path to hand out and is shared through its own channel instead.
        final localPath = p.join(widget.container.uri, fullPath);
        final ok = widget.container.isRawLocal
            ? await ref.read(vaultLocalShareApiProvider).shareLocalFiles([
                localPath,
              ], directoryPaths: entry.isDir ? [localPath] : const [])
            : await ref
                  .read(vaultFileIoApiProvider)
                  .shareFiles(
                    widget.container,
                    [fullPath],
                    directoryPaths: entry.isDir ? [fullPath] : const [],
                    skipExtensions:
                        _DirectoryContentViewState._vaultItemExtensions,
                  );
        if (!ok && mounted) {
          _setStatus(context.l10n.couldNotShareFiles, error: true);
        }
      },
      onEditImage: (!entry.isDir && MediaViewerConstants.isImage(entry.name))
          ? () => _editImage(entry.name, fullPath)
          : null,
      onEditVideo: (!entry.isDir && MediaViewerConstants.isVideo(entry.name))
          ? () => _editVideo(fullPath)
          : null,
      onEditAudio: (!entry.isDir && MediaViewerConstants.isAudio(entry.name))
          ? () => _editAudio(fullPath)
          : null,
      onToggleDocProvider: entry.isDir && !widget.container.isLocalStorage
          ? () {
              if (_isFolderMounted(entry)) {
                _showFolderDocumentProviderSheet(entry);
              } else {
                _toggleFolderDocumentProvider(entry);
              }
            }
          : null,
      // Auto-sync is configured per vault folder: not for device storage
      // browsers, and not inside an archive.
      onSyncSettings:
          entry.isDir &&
              !widget.container.isLocalStorage &&
              _archiveContext == null
          ? () => _showSyncSettings(entry)
          : null,
      // Selection-bar parity: same handlers and same visibility rules as
      // browser_app_bar_builder.dart (export is vault-only; encrypt/decrypt
      // apply to files only, by whether the name is already app-encrypted).
      onExport: !widget.container.isLocalStorage && _archiveContext == null
          ? () {
              _selectOnly(entry);
              _exportSelectedToStorage();
            }
          : null,
      onEncrypt:
          _archiveContext == null &&
              !entry.isDir &&
              !isAppEncryptedFileName(entry.name)
          ? () async {
              _selectOnly(entry);
              await _encryptSelected();
            }
          : null,
      onDecrypt:
          _archiveContext == null &&
              !entry.isDir &&
              isAppEncryptedFileName(entry.name)
          ? () async {
              _selectOnly(entry);
              await _decryptSelected();
            }
          : null,
      // The user's choice of which actions to show, and in what order.
      actionOrder: _toolbarConfig.itemActionsOrder,
      hiddenActions: _toolbarConfig.hiddenItemActions,
      quickActions: _toolbarConfig.quickItemActions,
    );
  }

  /// Builds the menu form of every toolbar action for [actions]. One source
  /// of truth for the floating toolbar's "More" button and for the app bar's
  /// adaptive overflow menu.
  FileManagerMoreMenuButton _buildMoreMenuModel({
    required List<FileManagerAction> actions,
    required bool searchActive,
    required FileBrowserSearch searchNotifier,
    required SortBy sortBy,
    required bool sortAscending,
    required String? currentFilter,
    required BrowserLayoutMode layoutMode,
    required FileManagerToolbarConfig toolbarConfig,
    required String currentDirPath,
    required List<RawEntry> currentItems,
  }) {
    final musicEntry = _music;
    return FileManagerMoreMenuButton(
      actions: actions,
      searchActive: searchActive,
      onToggleSearch: () => _toggleOrFocusSearch(searchNotifier),
      sortBy: sortBy,
      sortAscending: sortAscending,
      onSortChanged: _onSortChanged,
      currentFilter: currentFilter,
      onFilterChanged: _onFilterChosen,
      hideVaultOnlyActions: widget.container.isLocalStorage,
      layoutMode: layoutMode,
      onLayoutModeChanged: _onLayoutModeChanged,
      gridAspectRatio: toolbarConfig.getGridAspectRatioForFolder(
        widget.container.uri,
        currentDirPath,
      ),
      onGridAspectRatioChanged: _onGridAspectRatioChanged,
      canPlayMedia: _canPlayMediaIn(currentItems),
      onPlayMedia: _startMediaViewerFromCurrentLocation,
      musicModeActive: musicEntry.config.enabled,
      onToggleMusicMode: () =>
          unawaited(toggleMusicMode(context, ref, musicEntry)),
      isGalleryMode: _isGalleryMode,
      onToggleGallery: () => unawaited(_toggleGalleryMode()),
      onPickGalleryFolders: () => unawaited(_editGalleryFolders()),
      galleryFolderCount: toolbarConfig
          .galleryFoldersForStorage(widget.container.uri)
          .length,
      toolbarConfig: toolbarConfig,
      onToggleShowHiddenFiles: (v) =>
          _updateToolbarConfigField((c) => c.copyWith(showHiddenFiles: v)),
      onToggleShowNoMediaFolders: (v) =>
          _updateToolbarConfigField((c) => c.copyWith(showNoMediaFolders: v)),
      onToggleShowGridFileNames: (v) =>
          _updateToolbarConfigField((c) => c.copyWith(showGridFileNames: v)),
      onToggleShowFileExtensions: (v) =>
          _updateToolbarConfigField((c) => c.copyWith(showFileExtensions: v)),
      onToggleShowListThumbnails: (v) =>
          _updateToolbarConfigField((c) => c.copyWith(showListThumbnails: v)),
      onOpenSettings: _openFileManagerSettings,
    );
  }

  /// Overflow-menu entries for every toolbar action that can collapse. `add`
  /// is absent on purpose: it is the primary action and stays pinned inline.
  Map<FileManagerAction, Widget? Function(BuildContext)>
  _buildActionMenuEntries({
    required bool searchActive,
    required FileBrowserSearch searchNotifier,
    required SortBy sortBy,
    required bool sortAscending,
    required String? currentFilter,
    required BrowserLayoutMode layoutMode,
    required FileManagerToolbarConfig toolbarConfig,
    required String currentDirPath,
    required List<RawEntry> currentItems,
  }) {
    final model = _buildMoreMenuModel(
      actions: FileManagerAction.values,
      searchActive: searchActive,
      searchNotifier: searchNotifier,
      sortBy: sortBy,
      sortAscending: sortAscending,
      currentFilter: currentFilter,
      layoutMode: layoutMode,
      toolbarConfig: toolbarConfig,
      currentDirPath: currentDirPath,
      currentItems: currentItems,
    );
    return {
      for (final action in FileManagerAction.values)
        if (action != FileManagerAction.add)
          action: (context) => model.menuEntryFor(context, action),
    };
  }

  Map<FileManagerAction, WidgetBuilder> _buildActionBuilders({
    required bool searchActive,
    required bool isReadOnly,
    required bool hasArchiveContext,
    required String currentDirPath,
    required List<RawEntry> currentItems,
    required BrowserLayoutMode layoutMode,
    required String? currentFilter,
    required FileManagerToolbarConfig toolbarConfig,
    required FileBrowserSearch searchNotifier,
    required FileBrowserNavigation navigationNotifier,
    required SortBy sortBy,
    required bool sortAscending,
  }) {
    final canPlayMedia = _canPlayMediaIn(currentItems);
    return {
      FileManagerAction.search: (context) => IconButton(
        icon: Icon(
          searchActive ? Icons.search_off_rounded : Icons.search_rounded,
        ),
        tooltip: searchActive
            ? context.l10n.closeSearchTooltip
            : context.l10n.searchInThisFolderTooltip,
        onPressed: () => _toggleOrFocusSearch(searchNotifier),
      ),
      FileManagerAction.add: (context) => AddItemMenuButton(
        isReadOnly: isReadOnly,
        hasArchiveContext: hasArchiveContext,
        container: widget.container,
        currentDirPath: currentDirPath,
        currentItems: currentItems,
        onSetStatus: _setStatus,
        onExtractArchive: _extractArchive,
        onSignalActivity: _signalActivity,
        onCaptureFromCamera: _captureFromCamera,
        onRecordAudio: _recordAudio,
        onImportFilesFromDevice: _importFilesFromDevice,
        onImportFolderFromDevice: _importFolderFromDevice,
        onAddVaultItem: _addVaultItem,
        hideImportAndSecureItemActions: widget.container.isLocalStorage,
      ),
      FileManagerAction.gallery: (context) => IconButton(
        icon: Icon(
          _isGalleryMode
              ? Icons.photo_library_rounded
              : Icons.photo_library_outlined,
        ),
        tooltip: context.l10n.galleryModeTooltip,
        onPressed: () => unawaited(_toggleGalleryMode()),
      ),
      FileManagerAction.viewToggle: (context) => LayoutModeMenuButton(
        layoutMode: layoutMode,
        onLayoutModeChanged: _onLayoutModeChanged,
        gridAspectRatio: toolbarConfig.getGridAspectRatioForFolder(
          widget.container.uri,
          currentDirPath,
        ),
        onGridAspectRatioChanged: _onGridAspectRatioChanged,
      ),
      FileManagerAction.sort: (context) => SortMenuButton(
        sortBy: sortBy,
        sortAscending: sortAscending,
        onSortChanged: _onSortChanged,
      ),
      FileManagerAction.filter: (context) => FilterMenuButton(
        currentFilter: currentFilter,
        onFilterChanged: _onFilterChosen,
        hideVaultOnlyActions: widget.container.isLocalStorage,
      ),
      FileManagerAction.playMedia: (context) => IconButton(
        icon: const Icon(Icons.play_circle_outline_rounded),
        tooltip: context.l10n.playMediaHereTooltip,
        onPressed: canPlayMedia ? _startMediaViewerFromCurrentLocation : null,
      ),
      FileManagerAction.musicMode: (context) {
        final music = _music;
        return ListenableBuilder(
          listenable: music,
          builder: (context, _) => MusicModeSwitchButton(
            musicMode: music.config.enabled,
            onPressed: () => unawaited(toggleMusicMode(context, ref, music)),
          ),
        );
      },
      FileManagerAction.options: (context) => FileManagerOptionsMenuButton(
        toolbarConfig: toolbarConfig,
        onToggleShowHiddenFiles: (v) =>
            _updateToolbarConfigField((c) => c.copyWith(showHiddenFiles: v)),
        onToggleShowGridFileNames: (v) =>
            _updateToolbarConfigField((c) => c.copyWith(showGridFileNames: v)),
        onToggleShowFileExtensions: (v) =>
            _updateToolbarConfigField((c) => c.copyWith(showFileExtensions: v)),
        onToggleShowListThumbnails: (v) =>
            _updateToolbarConfigField((c) => c.copyWith(showListThumbnails: v)),
        onOpenSettings: _openFileManagerSettings,
        onPickGalleryFolders: () => unawaited(_editGalleryFolders()),
        galleryFolderCount: toolbarConfig
            .galleryFoldersForStorage(widget.container.uri)
            .length,
      ),
    };
  }

  BrowserListing _getFilteredAndSortedItems(
    String query,
    List<RawEntry> placeholders,
    Set<String> pendingDeletedNames,
  ) {
    final sortState = ref.read(fileBrowserSortProvider(_stateKey));
    return _listingCache.resolve(
      BrowserListingInputs(
        items: _currentItems,
        preSortedByNameAsc: _nav.preSortedByNameAsc,
        placeholders: placeholders,
        pendingDeletedNames: pendingDeletedNames,
        query: query,
        searchActive: _searchActive,
        deepSearch: _isDeepSearch,
        deepSearchResults: _deepSearchResults,
        showHidden: _toolbarConfig.showHiddenFiles,
        typeFilter: _currentFilter,
        currentDirPath: _currentDirPath,
        pinnedPaths: _pinnedPaths,
        sortBy: sortState.sortBy,
        sortAscending: sortState.sortAscending,
      ),
    );
  }

  List<Widget> _buildFabToolbar({required double bottomOffset}) {
    final rightPadding = MediaQuery.paddingOf(context).right;
    final baseRight = 16.0 + rightPadding;

    final visibleActions = _visibleActions;
    final showAddFab = visibleActions.contains(FileManagerAction.add);
    final moreActions = visibleActions
        .where((a) => a != FileManagerAction.add)
        .toList(growable: false);
    final showMore = moreActions.isNotEmpty;

    final widgets = <Widget>[];

    if (showMore) {
      // When the Add FAB is visible, place More to its left (56dp FAB + 12dp spacing = 68dp).
      // If the Add FAB is hidden via config, More takes the primary bottom-right slot.
      final moreRight = showAddFab ? (baseRight + 68.0) : baseRight;

      final musicEntry = _music;
      widgets.add(
        Positioned(
          right: moreRight,
          bottom:
              bottomOffset +
              4.0, // 4dp offset centers the 48dp button against the 56dp Add FAB
          child: ListenableBuilder(
            listenable: musicEntry,
            builder: (context, _) => _buildMoreMenuModel(
              actions: moreActions,
              searchActive: _searchActive,
              searchNotifier: _searchNotifier,
              sortBy: sortBy,
              sortAscending: sortAscending,
              currentFilter: _currentFilter,
              layoutMode: _layoutMode,
              toolbarConfig: _toolbarConfig,
              currentDirPath: _currentDirPath,
              currentItems: _currentItems,
            ),
          ),
        ),
      );
    }

    if (showAddFab) {
      widgets.add(
        Positioned(
          right: baseRight,
          bottom: bottomOffset,
          child: AddItemMenuButton(
            isReadOnly: _isReadOnly,
            hasArchiveContext: _archiveContext != null,
            container: widget.container,
            currentDirPath: _currentDirPath,
            currentItems: _currentItems,
            onSetStatus: _setStatus,
            onExtractArchive: _extractArchive,
            onSignalActivity: _signalActivity,
            onCaptureFromCamera: _captureFromCamera,
            onRecordAudio: _recordAudio,
            onImportFilesFromDevice: _importFilesFromDevice,
            onImportFolderFromDevice: _importFolderFromDevice,
            onAddVaultItem: _addVaultItem,
            hideImportAndSecureItemActions: widget.container.isLocalStorage,
            asFab: true,
          ),
        ),
      );
    }

    return widgets;
  }
}
