part of 'category_content_view.dart';

/// Collecting the sources a category spans, the cover and index caches, and
/// building the current item list.
///
/// Moved out of [_CategoryContentViewState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _CategoryScan on _CategoryContentViewState {
  Future<List<_CategorySourceBundle>> _collectSources() async {
    final l10n = context.l10n;
    final scoped = widget.scopedContainer;
    if (scoped != null) {
      final isVault = !scoped.isLocalStorage;
      final isDevice = !isVault && scoped.isPrimaryLocalStorage;
      return [
        _CategorySourceBundle(
          scoped,
          CategorySource(
            volId: scoped.volId,
            type: isVault
                ? CategorySourceType.vault
                : isDevice
                ? CategorySourceType.device
                : CategorySourceType.storageLocation,
            label: isDevice ? localStorageDisplayName(l10n.localStorageCardTitle) : scoped.displayName,
            dedupeRoot: !isVault && scoped.isRawLocal ? scoped.uri : null,
          ),
        ),
      ];
    }

    final bundles = <_CategorySourceBundle>[];
    final primary = widget.primaryLocalContainer;
    if (primary != null) {
      bundles.add(
        _CategorySourceBundle(
          primary,
          CategorySource(
            volId: primary.volId,
            type: CategorySourceType.device,
            label: localStorageDisplayName(l10n.localStorageCardTitle),
            dedupeRoot: primary.isRawLocal ? primary.uri : null,
          ),
        ),
      );
    }

    final locationsNotifier = ref.read(
      externalStorageLocationsProvider.notifier,
    );
    for (final loc in ref.read(externalStorageLocationsProvider)) {
      if (!await locationsNotifier.isAccessible(loc)) continue;
      final container = buildExternalStorageContainer(
        rootPath: loc.resolvedUri,
        displayName: loc.displayName,
        volId: loc.volId,
      );
      bundles.add(
        _CategorySourceBundle(
          container,
          CategorySource(
            volId: container.volId,
            type: CategorySourceType.storageLocation,
            label: loc.displayName,
            dedupeRoot: container.isRawLocal ? container.uri : null,
          ),
        ),
      );
    }

    final unlocked = widget.includeVaults
        ? ref.read(vaultDashboardControllerProvider).mounted
        : const <MountedContainer>[];
    for (final vault in unlocked) {
      bundles.add(
        _CategorySourceBundle(
          vault,
          CategorySource(
            volId: vault.volId,
            type: CategorySourceType.vault,
            label: vault.displayName,
          ),
        ),
      );
    }
    return bundles;
  }

  void _indexCovers() {
    final index = <String, List<CategoryEntry>>{};
    for (final e in _snapshot.entries) {
      if (e.isDir) continue;
      if (!MediaViewerConstants.isImage(e.baseName) &&
          !MediaViewerConstants.isVideo(e.baseName)) {
        continue;
      }
      var dir = e.parentPath;
      while (true) {
        final list = index.putIfAbsent('${e.sourceVolId}:$dir', () => []);
        if (list.length < _CategoryContentViewState._coversPerFolder ||
            _CategoryContentViewState._coverOrder(e, list.last) < 0) {
          var at = list.length;
          while (at > 0 &&
              _CategoryContentViewState._coverOrder(e, list[at - 1]) < 0) {
            at--;
          }
          list.insert(at, e);
          if (list.length > _CategoryContentViewState._coversPerFolder) {
            list.removeLast();
          }
        }
        if (dir.isEmpty) break;
        final slash = dir.lastIndexOf('/');
        dir = slash < 0 ? '' : dir.substring(0, slash);
      }
    }
    _covers = index;
    _coversSnapshot = _snapshot;
  }

  /// The files a folder tile may use as its cover, or null to let the tile
  /// look inside the folder itself.
  List<String>? _folderCoverPaths(RawEntry folder) {
    if (folder is! CategoryEntry) return null;
    if (!identical(_coversSnapshot, _snapshot)) _indexCovers();
    final found = _covers['${folder.sourceVolId}:${folder.path}'];
    if (found == null || found.isEmpty) return null;
    return [for (final e in found) e.path];
  }

  Future<void> _pickGalleryFolders() async {
    final scoped = widget.scopedContainer;
    if (scoped == null || !mounted) return;
    final fileIo = ref.read(vaultFileIoApiProvider);
    final toolbarSettings = ref.read(
      fileManagerToolbarSettingsProvider(_scopedToolbarUri),
    );
    final showHidden = toolbarSettings.config.showHiddenFiles;
    final isSkipped = toolbarSettings.config.isGalleryPromptSkippedForStorage(
      scoped.uri,
    );
    final chosen = await showGalleryScopeSheet(
      context,
      container: scoped,
      access: libraryFileAccess(fileIo, scoped),
      initialFolders: _galleryRoots,
      initialDontAskAgain: isSkipped,
      turningOn: false,
      preferChoosing: false,
      showHidden: showHidden,
      skipDirectory: scoped.isRawLocal
          ? skipDeviceCategoryFolder
          : _CategoryContentViewState._skipVaultMetaFolder,
    );
    if (chosen == null || !mounted) return;
    final notifier = ref.read(
      fileManagerToolbarSettingsProvider(_scopedToolbarUri).notifier,
    );
    if (chosen.dontAskAgain != isSkipped) {
      await notifier.setGalleryPromptSkippedForStorage(
        scoped.uri,
        chosen.dontAskAgain,
      );
    }
    if (_CategoryContentViewState._sameRoots(chosen.folders, _galleryRoots)) {
      return;
    }
    await notifier.setGalleryFoldersForStorage(scoped.uri, chosen.folders);
    if (mounted &&
        !_CategoryContentViewState._sameRoots(_galleryRoots, chosen.folders)) {
      _applyGalleryRoots(chosen.folders);
    }
  }

  DeviceCategoryIndexKey _deviceKey(
    _CategorySourceBundle bundle,
    bool showHidden,
    bool showNoMedia,
  ) => DeviceCategoryIndexKey(
    rootPath: bundle.container.uri,
    categoryKey: _categoryKey,
    showHidden: showHidden,
    showNoMedia: showNoMedia,
  );

  /// Keeps what a finished scan found in phone storage, to show at once the
  /// next time this category opens. A scan that was cut off, or that could
  /// not read a source, would leave a wrong list behind, so it keeps nothing.
  Future<void> _rememberDevice(
    DeviceCategoryIndex index,
    List<_CategorySourceBundle> bundles,
    CategoryAggregateSnapshot result,
    bool showHidden,
    bool showNoMedia,
  ) async {
    if (!result.finished || result.limitReached) return;
    for (final b in bundles) {
      if (!b.container.isRawLocal ||
          result.failedSources.contains(b.source.volId)) {
        continue;
      }
      await index.remember(_deviceKey(b, showHidden, showNoMedia), [
        for (final e in result.entries)
          if (e.sourceVolId == b.source.volId)
            RawEntry(
              name: e.path,
              isDir: false,
              sizeBytes: e.sizeBytes,
              modifiedSecs: e.modifiedSecs,
            ),
      ]);
    }
  }

  Future<List<RawEntry>?> _loadIndexSeed(
    VaultFileIoApi api,
    MountedContainer vault,
    bool showHidden,
    bool showNoMedia,
  ) async {
    // The stored index was gathered without `.nomedia` folders, so it cannot
    // stand in for a scan that includes them.
    if (showNoMedia) return null;
    try {
      final store = categoryIndexStoreFor(api, vault);
      if (store == null) return null;
      final section = (await store.load()).sections[_categoryKey];
      if (section == null || section.entries.isEmpty) return null;
      return [
        for (final e in section.entries)
          if (showHidden || !e.path.split('/').any(isHiddenEntryName))
            RawEntry(
              name: e.path,
              isDir: false,
              sizeBytes: e.sizeBytes,
              modifiedSecs: e.modifiedSecs,
            ),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveIndex(
    VaultFileIoApi api,
    List<_CategorySourceBundle> bundles,
    CategoryAggregateSnapshot result,
  ) async {
    if (!result.finished || result.limitReached) return;
    final builtAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final b in bundles) {
      if (!b.source.isVault || result.failedSources.contains(b.source.volId)) {
        continue;
      }
      final store = categoryIndexStoreFor(api, b.container);
      if (store == null) continue;
      try {
        await store.saveSection(
          _categoryKey,
          CategoryIndexSection(
            builtAtSecs: builtAt,
            entries: [
              for (final e in result.entries)
                if (e.sourceVolId == b.source.volId)
                  CategoryIndexEntry(e.path, e.sizeBytes, e.modifiedSecs),
            ],
          ),
        );
      } catch (e) {
        VeLog.w('CategoryContentView', 'Could not save the category index', e);
      }
    }
  }

  CategoryAggregateSnapshot _withoutLockedVaults(
    CategoryAggregateSnapshot snapshot,
  ) {
    if (!_usesVaults) return snapshot;
    final mountedIds = {
      for (final v in ref.read(vaultDashboardControllerProvider).mounted)
        v.volId,
    };
    var result = snapshot;
    for (final volId in snapshot.contributingSources) {
      final source = _sources[volId];
      if (source != null && source.isVault && !mountedIds.contains(volId)) {
        result = result.withoutSource(volId);
      }
    }
    return result;
  }

  void _onMountedVaultsChanged(
    List<MountedContainer>? previous,
    List<MountedContainer> next,
  ) {
    if (_disposed) return;
    final prevIds = {
      if (previous != null)
        for (final v in previous) v.volId,
    };
    final nextIds = {for (final v in next) v.volId};
    if (nextIds.any((id) => !prevIds.contains(id))) {
      unawaited(_startScan(keepResults: true));
    }
  }

  List<CategoryEntry> _currentItems() {
    final location = _effectiveLocation;
    final gallery = _isGallery && !_folderMode;
    final filters = gallery ? _galleryFilter.filters : GalleryFilterSet.empty;
    final groupBy = gallery ? _galleryFilter.groupBy : GalleryGroupBy.none;
    final metaRevision = gallery ? (_metaIndex?.publishedRevision ?? 0) : 0;
    final queryHash = gallery ? _query.trim().hashCode : 0;
    final placesLoaded = gallery && _places != null;
    final unchanged =
        identical(_itemsSnapshot, _snapshot) &&
        _itemsFolderMode == _folderMode &&
        _itemsLocation == location &&
        _itemsQuery == _query &&
        _itemsSortBy == _sortBy &&
        _itemsSortAscending == _sortAscending &&
        _itemsFilters == filters &&
        _itemsGroupBy == groupBy &&
        _itemsMetaRevision == metaRevision &&
        _itemsQueryHash == queryHash &&
        _itemsPlacesLoaded == placesLoaded;
    if (unchanged) return _items;

    // In gallery mode the search box also looks at tags, camera and place,
    // so the name-only match of the plain listing is left out here.
    var list = _folderMode
        ? folderCategoryListing(
            _snapshot,
            location: location,
            labels: {for (final s in _sources.values) s.volId: s.label},
            query: _query,
          )
        : flatCategoryListing(
            _snapshot,
            location: location,
            query: gallery ? '' : _query,
          );
    _itemsUnfilteredCount = list.length;

    if (gallery) {
      final text = _query.trim();
      final queryFilter = text.isEmpty ? null : GalleryQueryFilter(text);
      if (queryFilter != null || filters.isNotEmpty) {
        list = [
          for (final e in list)
            if (_matchesGallery(e, queryFilter, filters)) e,
        ];
      }
    }

    // A gallery shows photos by when they were taken, so its date order is
    // the capture date the files carry (Exif, XMP), the modified date only
    // for what has none or is not read yet.
    final byCaptureDate = gallery && _sortBy == SortBy.date;
    list.sort((a, b) {
      if (_folderMode && a.isDir != b.isDir) return a.isDir ? -1 : 1;
      if (byCaptureDate) {
        final c = _compareByCaptureDate(a, b);
        if (c != 0) return _sortAscending ? c : -c;
      }
      return compareEntriesBySort(
        a,
        b,
        sortBy: _sortBy,
        sortAscending: _sortAscending,
      );
    });

    // Sections other than "none" need each section to be one run of the list.
    List<DateGroup<RawEntry>>? groups;
    if (gallery && groupBy != GalleryGroupBy.none) {
      final arranged = _galleryGrouper(
        groupBy,
      ).arrangeWithGroups<CategoryEntry>(list);
      list = arranged.items;
      groups = arranged.groups;
    }
    _itemsGroups = groups;

    if (gallery && !identical(_itemsSnapshot, _snapshot)) {
      _scheduleMetaIndexing(delay: groupBy.isDate ? Duration.zero : null);
    }
    if (gallery && (filters.isNotEmpty || _query.trim().isNotEmpty)) {
      _scheduleMetaWanted();
    }

    _itemsFilters = filters;
    _itemsGroupBy = groupBy;
    _itemsMetaRevision = metaRevision;
    _itemsQueryHash = queryHash;
    _itemsPlacesLoaded = placesLoaded;
    _itemsSnapshot = _snapshot;
    _itemsFolderMode = _folderMode;
    _itemsLocation = location;
    _itemsQuery = _query;
    _itemsSortBy = _sortBy;
    _itemsSortAscending = _sortAscending;
    return _items = list;
  }

  GalleryMetaIndex _createMetaIndex() {
    final io = ref.read(vaultFileIoApiProvider);
    final crypto = ref.read(vaultCryptoApiProvider);
    final storage = VaultGalleryMetaStorage(
      io,
      (volId) => _containers[volId],
      allowWrite: (volId) =>
          _metaCacheMode(volId) != ThumbnailCacheMode.disabled,
      metadataCacheMode: _metaCacheMode,
      appFilesOf: (container) =>
          AppGalleryMetaFiles(container: container, crypto: crypto),
    );
    final index = GalleryMetaIndex(
      readHeader: (volId, path, length) async {
        final container = _containers[volId];
        if (container == null) return null;
        return io.readFileChunk(container, path, 0, length);
      },
      readRange: (volId, path, offset, length) async {
        final container = _containers[volId];
        if (container == null) return null;
        return io.readFileChunk(container, path, offset, length);
      },
      storage: storage,
      // Sources without writable persistent metadata keep their parsed index
      // for this app session. Vault entries are cleared on lock.
      memory: ref.read(galleryMetaMemoryProvider),
      retain: (volId) => !storage.persists(volId),
      notifyEvery: const Duration(seconds: 1),
    );
    index.addListener(_onMetaIndexChanged);
    if (_userScrolling) index.paused = true;
    return index;
  }
}
