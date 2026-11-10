import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart'
    show AppBannerTone;
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/thumbnail_settings.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';
import 'package:vaultexplorer/data/services/thumbnail_settings_resolver.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/file_open_dispatch.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/models/category_index.dart';
import 'package:vaultexplorer/features/browser/models/category_source.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/browser/services/category_aggregate_scan.dart';
import 'package:vaultexplorer/features/browser/services/category_listing.dart';
import 'package:vaultexplorer/features/browser/services/category_walk_policy.dart';
import 'package:vaultexplorer/features/browser/services/device_category_index.dart';
import 'package:vaultexplorer/features/browser/services/device_category_index_provider.dart';
import 'package:vaultexplorer/features/browser/services/raw_local_category_lister.dart';
import 'package:vaultexplorer/features/browser/services/vault_category_index_io.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/pdf_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_screen.dart';
import 'package:vaultexplorer/features/browser/widgets/bottom_search_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/file_grid_view.dart';
import 'package:vaultexplorer/features/browser/widgets/file_list_view.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart'
    show kVaultMetaDir;
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Asks the host to open [container] at the folder holding [path], as if the
/// user had browsed there. Supplied by whoever opens the category browser
/// (the navigation drawer), because only it knows how to reach the file
/// manager.
typedef ShowInFolderCallback = void Function(
  MountedContainer container,
  String path,
);

/// Browses every file of one [FileCategory] across all the storage the user
/// can reach: phone storage, configured storage locations and unlocked vaults.
///
/// It is a virtual view. Nothing is copied or moved; each entry stays tied to
/// the source and path it was found at (see [CategoryEntry]), and every
/// action resolves that source, never "the folder being shown". Locked vaults
/// are never scanned, and a vault's entries disappear the moment it locks.
class CategoryBrowserScreen extends ConsumerStatefulWidget {
  const CategoryBrowserScreen({
    super.key,
    required this.category,
    this.primaryLocalContainer,
    this.onShowInFolder,
    this.scopedContainer,
    this.includeVaults = true,
  });

  final FileCategory category;

  /// Phone storage, when the user has granted access to it.
  final MountedContainer? primaryLocalContainer;

  final ShowInFolderCallback? onShowInFolder;

  /// When set, the browser looks only inside this one storage (a vault, phone
  /// storage or a storage location) and has no source selector. This is how
  /// the file manager's type filter works: like a category, but inside the
  /// storage it was used in.
  final MountedContainer? scopedContainer;

  /// Whether vaults take part at all. The decoy file manager passes false: it
  /// never reads the vault list or listens for vault events, and shows nothing
  /// that mentions vaults.
  final bool includeVaults;

  @override
  ConsumerState<CategoryBrowserScreen> createState() =>
      _CategoryBrowserScreenState();
}

class _SourceBundle {
  _SourceBundle(this.container, this.source);

  final MountedContainer container;
  final CategorySource source;
}

class _CategoryBrowserScreenState extends ConsumerState<CategoryBrowserScreen> {
  VaultEngineEvents? _events;
  late CategorySourceFilter _source;
  late bool _folderMode;
  late BrowserLayoutMode _layout;
  late SortBy _sortBy;
  late bool _sortAscending;

  CategoryLocation _location = CategoryLocation.top;
  CategoryAggregateSnapshot _snapshot = CategoryAggregateSnapshot.empty;
  Map<int, MountedContainer> _containers = const {};
  Map<int, CategorySource> _sources = const {};
  Map<int, ThumbnailSettings?> _thumbs = const {};
  CancellationToken? _token;
  // True from the start: the first scan begins right after the first frame.
  bool _scanning = true;
  bool _disposed = false;

  bool _searchActive = false;
  String _query = '';
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<FileGridViewState> _gridKey = GlobalKey<FileGridViewState>();
  final GlobalKey<FileListViewState> _listKey = GlobalKey<FileListViewState>();
  Set<RawEntry> _selected = {};

  // The listing is rebuilt (filtered and sorted) only when one of its inputs
  // changed, not on every build: a selection tap rebuilds this screen, and
  // sorting tens of thousands of entries per tap would be felt.
  List<CategoryEntry> _items = const [];
  CategoryAggregateSnapshot? _itemsSnapshot;
  bool? _itemsFolderMode;
  CategoryLocation? _itemsLocation;
  String? _itemsQuery;
  SortBy? _itemsSortBy;
  bool? _itemsSortAscending;

  String get _categoryKey => widget.category.storageKey;

  bool get _scoped => widget.scopedContainer != null;

  /// Whether anything vault-related is involved: the scoped storage is a
  /// vault, or (when not scoped) vaults take part. When false the screen never
  /// touches the vault list, the engine's events or the vault index.
  bool get _usesVaults =>
      _scoped ? !widget.scopedContainer!.isLocalStorage : widget.includeVaults;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsControllerProvider).settings;
    // A scoped browser has no selector, and neither does one without vaults
    // (the decoy), so the remembered choice does not apply to them and they
    // never overwrite it.
    _source = _scoped || !widget.includeVaults
        ? CategorySourceFilter.all
        : CategorySourceFilter.fromStorageKey(
            settings.categorySources[_categoryKey],
          );
    _folderMode = settings.categoryFolderStructure.contains(_categoryKey);
    final visual =
        widget.category == FileCategory.images ||
        widget.category == FileCategory.videos;
    // This screen only has grid, list and detailed: a layout remembered from
    // the tabbed browser that it cannot show becomes the closest one it can.
    final remembered = BrowserLayoutMode.fromJson(
      settings.categoryLayouts[_categoryKey],
    );
    _layout = switch (remembered) {
      BrowserLayoutMode.grid ||
      BrowserLayoutMode.masonry => BrowserLayoutMode.grid,
      BrowserLayoutMode.list ||
      BrowserLayoutMode.compact => BrowserLayoutMode.list,
      BrowserLayoutMode.detailed => BrowserLayoutMode.detailed,
      null => visual ? BrowserLayoutMode.grid : BrowserLayoutMode.list,
    };
    _sortBy = visual ? SortBy.date : SortBy.name;
    _sortAscending = !visual;

    if (_usesVaults) {
      _events = ref.read(vaultEngineEventsProvider)
        ?..addContainerLockedListener(_onVaultLocked);
      ref.listenManual<List<MountedContainer>>(
        vaultDashboardControllerProvider.select((s) => s.mounted),
        _onMountedVaultsChanged,
      );
    }
    // Not here: collecting the sources reads localized labels, which cannot
    // be looked up before initState has finished.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startScan());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    _events?.removeContainerLockedListener(_onVaultLocked);
    _scrollController.dispose();
    super.dispose();
  }

  // ── Sources ────────────────────────────────────────────────────────────────

  /// Everything the user can currently reach. Only vaults that are unlocked
  /// (mounted) are ever listed here, so a locked vault cannot be scanned.
  Future<List<_SourceBundle>> _collectSources() async {
    final l10n = context.l10n;
    final scoped = widget.scopedContainer;
    if (scoped != null) {
      final isVault = !scoped.isLocalStorage;
      final isDevice = !isVault && scoped.isPrimaryLocalStorage;
      return [
        _SourceBundle(
          scoped,
          CategorySource(
            volId: scoped.volId,
            type: isVault
                ? CategorySourceType.vault
                : isDevice
                ? CategorySourceType.device
                : CategorySourceType.storageLocation,
            label: isDevice ? l10n.localStorageCardTitle : scoped.displayName,
            dedupeRoot: !isVault && scoped.isRawLocal ? scoped.uri : null,
          ),
        ),
      ];
    }
    final bundles = <_SourceBundle>[];
    final primary = widget.primaryLocalContainer;
    if (primary != null) {
      bundles.add(
        _SourceBundle(
          primary,
          CategorySource(
            volId: primary.volId,
            type: CategorySourceType.device,
            label: l10n.localStorageCardTitle,
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
        _SourceBundle(
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
        _SourceBundle(
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

  /// Android keeps these two off limits to other apps; listing them only
  /// costs time.
  /// A vault's own configuration folder holds the app's files, not the
  /// person's; it never belongs in a category.
  static bool _skipVaultMetaFolder(String dirPath) => dirPath == kVaultMetaDir;

  /// Gathers the category's files from every source in play.
  ///
  /// Phone storage is not walked from scratch each time: the last result is
  /// shown at once, the platform's file index supplies the fresh one, and the
  /// folders are only visited when that cannot answer (see
  /// [DeviceCategoryIndex]). [deep] skips the index and walks, for the cases
  /// where it must not be trusted to know about a change: a pull to refresh,
  /// and a rescan after an operation that wrote files.
  Future<void> _startScan({bool deep = false}) async {
    _token?.cancel();
    final token = _token = CancellationToken();
    final showHidden = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config
        .showHiddenFiles;
    setState(() {
      _scanning = true;
      _snapshot = CategoryAggregateSnapshot.empty;
      _selected = {};
    });

    final all = await _collectSources();
    if (_disposed || token.isCancelled) return;
    final bundles = all
        .where((b) => b.source.isIncludedBy(_source))
        .toList(growable: false);
    _containers = {for (final b in all) b.container.volId: b.container};
    _sources = {for (final b in all) b.source.volId: b.source};

    final api = ref.read(vaultFileIoApiProvider);
    final indexEnabled =
        _usesVaults &&
        ref.read(appSettingsControllerProvider).settings.categoryIndexInVaults;
    // What each unlocked vault's stored index says, shown at once while the
    // vault is read again.
    final seeds = <int, List<RawEntry>>{};
    if (indexEnabled) {
      await Future.wait([
        for (final b in bundles)
          if (b.source.isVault)
            _loadIndexSeed(api, b.container, showHidden).then((seed) {
              if (seed != null) seeds[b.source.volId] = seed;
            }),
      ]);
      if (_disposed || token.isCancelled) return;
    }
    bool matches(String name) => matchesFilter(name, widget.category.filterKey);
    final deviceIndex = ref.read(deviceCategoryIndexProvider);
    final extensions = categoryFileExtensions(widget.category);
    // Phone storage remembers its last result, so the view opens filled.
    await Future.wait([
      for (final b in bundles)
        if (b.container.isRawLocal)
          deviceIndex.seed(_deviceKey(b, showHidden)).then((seed) {
            if (seed != null) seeds[b.source.volId] = seed;
          }),
    ]);
    if (_disposed || token.isCancelled) return;

    final scanner = CategoryAggregateScanner(
      targets: [
        for (final b in bundles)
          if (b.container.isRawLocal)
            CategoryScanTarget(
              source: b.source,
              listDirectory: rawLocalCategoryLister(
                rootPath: b.container.uri,
                matches: matches,
              ),
              skipDirectory: skipDeviceCategoryFolder,
              // `.nomedia` means "not for browsing" for media; documents are
              // not media, so a marker does not hide them.
              respectNoMedia: widget.category != FileCategory.documents,
              indexLookup: deep
                  ? null
                  : () => deviceIndex.lookup(
                      _deviceKey(b, showHidden),
                      extensions: extensions,
                      matches: matches,
                      isHidden: isHiddenEntryName,
                      skipDirectory: skipDeviceCategoryFolder,
                    ),
              seed: seeds[b.source.volId],
            )
          else
            CategoryScanTarget(
              source: b.source,
              listDirectory: (dir) => api.listDirectory(b.container, dir),
              skipDirectory: b.source.isVault ? _skipVaultMetaFolder : null,
              seed: seeds[b.source.volId],
            ),
      ],
      matches: matches,
      isHidden: isHiddenEntryName,
      showHidden: showHidden,
    );
    final result = await scanner.scan(
      token: token,
      onProgress: (snapshot) {
        if (_disposed || token.isCancelled) return;
        setState(() => _snapshot = _withoutLockedVaults(snapshot));
      },
    );
    if (_disposed || token.isCancelled) return;
    setState(() {
      _snapshot = _withoutLockedVaults(result);
      _scanning = false;
    });
    if (indexEnabled) unawaited(_saveIndex(api, bundles, result));
    unawaited(_rememberDevice(deviceIndex, bundles, result, showHidden));
  }

  DeviceCategoryIndexKey _deviceKey(_SourceBundle bundle, bool showHidden) =>
      DeviceCategoryIndexKey(
        rootPath: bundle.container.uri,
        categoryKey: _categoryKey,
        showHidden: showHidden,
      );

  /// Keeps what a finished scan found in phone storage, to show at once the
  /// next time this category opens. A scan that was cut off, or that could
  /// not read a source, would leave a wrong list behind, so it keeps nothing.
  Future<void> _rememberDevice(
    DeviceCategoryIndex index,
    List<_SourceBundle> bundles,
    CategoryAggregateSnapshot result,
    bool showHidden,
  ) async {
    if (!result.finished || result.limitReached) return;
    for (final b in bundles) {
      if (!b.container.isRawLocal ||
          result.failedSources.contains(b.source.volId)) {
        continue;
      }
      await index.remember(_deviceKey(b, showHidden), [
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

  /// The files a vault's stored index lists for this category, or null when
  /// it has none.
  Future<List<RawEntry>?> _loadIndexSeed(
    VaultFileIoApi api,
    MountedContainer vault,
    bool showHidden,
  ) async {
    try {
      final store = categoryIndexStoreFor(api, vault);
      if (store == null) return null;
      final section = (await store.load()).sections[_categoryKey];
      if (section == null || section.entries.isEmpty) return null;
      return [
        for (final e in section.entries)
          // Hidden folders are skipped by a scan unless the person shows
          // hidden files, so the stand-in must not show them either.
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

  /// Keeps what a finished scan found inside each vault it read, for the next
  /// visit. Only writable vaults are written to.
  Future<void> _saveIndex(
    VaultFileIoApi api,
    List<_SourceBundle> bundles,
    CategoryAggregateSnapshot result,
  ) async {
    // A scan that stopped at a limit did not see everything; indexing it
    // would make files vanish from the next visit's first look.
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
      } catch (_) {
        // The index is a convenience; failing to keep it changes nothing
        // the person sees.
      }
    }
  }

  /// [snapshot] minus any vault that is no longer unlocked, so a scan that
  /// was still running when a vault locked cannot bring its names back.
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

  void _onVaultLocked(int volId) => _dropVault(volId);

  void _onMountedVaultsChanged(
    List<MountedContainer>? previous,
    List<MountedContainer> next,
  ) {
    if (_disposed) return;
    final before = {
      for (final v in previous ?? const <MountedContainer>[]) v.volId,
    };
    final after = {for (final v in next) v.volId};
    for (final gone in before.difference(after)) {
      _dropVault(gone);
    }
    // A vault that was just unlocked belongs in the aggregate views.
    final added = after.difference(before);
    if (!_scoped &&
        added.isNotEmpty &&
        (_source.kind == CategorySourceKind.all ||
            _source.kind == CategorySourceKind.vaults)) {
      unawaited(_startScan());
    }
  }

  /// Removes everything of a vault that just locked, immediately.
  void _dropVault(int volId) {
    if (_disposed || !mounted) return;
    if (_scoped) {
      // Scoped to the vault that just locked: nothing is left to show.
      if (widget.scopedContainer!.volId == volId) {
        setState(() {
          _snapshot = _snapshot.withoutSource(volId);
          _selected = {};
        });
        Navigator.of(context).maybePop();
      }
      return;
    }
    final removedSelected = _selected
        .whereType<CategoryEntry>()
        .where((e) => e.sourceVolId == volId)
        .toSet();
    final switchSource =
        _source.kind == CategorySourceKind.vault && _source.volId == volId;
    setState(() {
      _snapshot = _snapshot.withoutSource(volId);
      _selected = {..._selected}..removeAll(removedSelected);
      if (_location.volId == volId) _location = CategoryLocation.top;
      if (switchSource) _source = CategorySourceFilter.all;
    });
    if (switchSource) {
      _persistSource(CategorySourceFilter.all);
      unawaited(_startScan());
    }
  }

  void _setSource(CategorySourceFilter source) {
    if (source == _source) return;
    setState(() {
      _source = source;
      _location = CategoryLocation.top;
    });
    _persistSource(source);
    unawaited(_startScan());
  }

  /// Switches the layout and remembers it for this category.
  void _setLayout(BrowserLayoutMode mode) {
    if (mode == _layout) return;
    setState(() => _layout = mode);
    ref
        .read(appSettingsControllerProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(
            categoryLayouts: {...s.categoryLayouts, _categoryKey: mode.toJson()},
          ),
        );
  }

  void _persistSource(CategorySourceFilter source) {
    ref
        .read(appSettingsControllerProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(
            categorySources: {
              ...s.categorySources,
              _categoryKey: source.storageKey,
            },
          ),
        );
  }

  void _setFolderMode(bool on) {
    if (on == _folderMode) return;
    setState(() {
      _folderMode = on;
      _location = CategoryLocation.top;
      _selected = {};
    });
    ref.read(appSettingsControllerProvider.notifier).updateSettings((s) {
      final keys = {...s.categoryFolderStructure};
      on ? keys.add(_categoryKey) : keys.remove(_categoryKey);
      return s.copyWith(categoryFolderStructure: keys.toList());
    });
  }

  // ── Listing ────────────────────────────────────────────────────────────────

  CategoryLocation get _effectiveLocation =>
      effectiveCategoryLocation(_snapshot, _location);

  List<CategoryEntry> _currentItems() {
    final location = _effectiveLocation;
    final unchanged =
        identical(_itemsSnapshot, _snapshot) &&
        _itemsFolderMode == _folderMode &&
        _itemsLocation == location &&
        _itemsQuery == _query &&
        _itemsSortBy == _sortBy &&
        _itemsSortAscending == _sortAscending;
    if (unchanged) return _items;
    final list = _folderMode
        ? folderCategoryListing(
            _snapshot,
            location: location,
            labels: {for (final s in _sources.values) s.volId: s.label},
            query: _query,
          )
        : flatCategoryListing(_snapshot, query: _query);
    list.sort((a, b) {
      if (_folderMode && a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return compareEntriesBySort(
        a,
        b,
        sortBy: _sortBy,
        sortAscending: _sortAscending,
      );
    });
    _itemsSnapshot = _snapshot;
    _itemsFolderMode = _folderMode;
    _itemsLocation = location;
    _itemsQuery = _query;
    _itemsSortBy = _sortBy;
    _itemsSortAscending = _sortAscending;
    return _items = list;
  }

  bool get _canGoUp =>
      _folderMode &&
      parentCategoryLocation(_snapshot, _effectiveLocation) != null;

  void _goUp() {
    final parent = parentCategoryLocation(_snapshot, _effectiveLocation);
    if (parent == null) return;
    setState(() {
      _location = parent;
      _selected = {};
    });
    _jumpToTop();
  }

  void _enterFolder(CategoryEntry folder) {
    setState(() {
      _location = CategoryLocation(folder.sourceVolId, folder.path);
      _selected = {};
    });
    _jumpToTop();
  }

  void _jumpToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  MountedContainer? _containerOfEntry(RawEntry entry) =>
      entry is CategoryEntry ? _containers[entry.sourceVolId] : null;

  /// The thumbnail cache policy of the vault or storage an entry lives in.
  ///
  /// Until that container's settings have loaded the answer is "disabled": a
  /// vault whose owner turned thumbnail caching off must not get a cached one
  /// just because its settings had not arrived yet.
  ThumbnailCacheMode _cacheModeOf(RawEntry entry) {
    if (entry is! CategoryEntry) return ThumbnailCacheMode.disabled;
    return _thumbs[entry.sourceVolId]?.cacheMode ?? ThumbnailCacheMode.disabled;
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  List<CategoryEntry> get _selectedEntries =>
      _selected.whereType<CategoryEntry>().toList();

  /// Folders are never selectable. In the folder view they stand for a whole
  /// directory, including files that are not part of this category, so acting
  /// on one would reach far beyond what the view shows.
  Set<RawEntry> _filesOnly(Iterable<RawEntry> entries) => {
    for (final e in entries)
      if (!e.isDir) e,
  };

  void _toggle(RawEntry entry) {
    if (entry.isDir) return;
    setState(() {
      final next = {..._selected};
      next.contains(entry) ? next.remove(entry) : next.add(entry);
      _selected = next;
    });
  }

  void _clearSelection() => setState(() => _selected = {});

  void _selectAll() => setState(() => _selected = _filesOnly(_items));

  // ── Opening ────────────────────────────────────────────────────────────────

  void _onFileTap(RawEntry entry) {
    if (entry is! CategoryEntry) return;
    if (_selected.isNotEmpty) {
      _toggle(entry);
      return;
    }
    unawaited(_open(entry));
  }

  void _onDirTap(RawEntry entry) {
    if (entry is! CategoryEntry || _selected.isNotEmpty) return;
    _enterFolder(entry);
  }

  /// Long-pressing starts a selection. Once one is going the range-select
  /// gesture reports through onSelectionChanged instead, so this only ever
  /// adds, never toggles.
  void _onItemLongPress(RawEntry entry) {
    if (entry.isDir || _selected.contains(entry)) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = {..._selected, entry});
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
        await _openWithApp(container, entry, packageName: package);
      default:
        // The readers and viewers that need a folder to work in (books,
        // archives, HTML) live in the ordinary file manager; here the system
        // app is the way to open them.
        await _openWithApp(container, entry);
    }
  }

  Future<void> _openMedia(
    CategoryEntry entry,
    MountedContainer container,
  ) async {
    // The playlist is this source's media in the order shown, since the
    // viewer plays one container at a time.
    final playlist = [
      for (final e in _items)
        if (!e.isDir &&
            e.sourceVolId == entry.sourceVolId &&
            MediaViewerConstants.isSupported(e.baseName))
          e.path,
    ];
    final index = playlist.indexOf(entry.path);
    final settings = _thumbs[entry.sourceVolId];
    final deleted = <String>{};

    final initialOffset = _scrollController.hasClients
        ? _scrollController.offset
        : null;
    String lastViewedFile = entry.path;

    await Navigator.push<bool>(
      context,
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => MediaViewerScreen(
          container: container,
          mediaFiles: playlist,
          initialIndex: index < 0 ? 0 : index,
          startingFolder: entry.parentPath,
          thumbnailQuality:
              settings?.quality ?? ThumbnailQuality.defaultQuality,
          thumbnailCacheMode:
              settings?.cacheMode ?? ThumbnailCacheMode.disabled,
          sortBy: _sortBy,
          sortAscending: _sortAscending,
          onCurrentFileChanged: (newFile) {
            lastViewedFile = newFile;
          },
          onFileDeleted: deleted.add,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: child,
          );
        },
      ),
    );
    if (!mounted) return;

    if (lastViewedFile == entry.path &&
        initialOffset != null &&
        _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        if (ModalRoute.of(context)?.isCurrent == false) return;

        final position = _scrollController.position;
        if (!position.hasContentDimensions) return;
        final restoredOffset = initialOffset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if ((position.pixels - restoredOffset).abs() > 0.5) {
          _scrollController.jumpTo(restoredOffset);
        }
      });
    } else if (lastViewedFile != entry.path &&
        _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        if (ModalRoute.of(context)?.isCurrent == false) return;
        _scrollToItem(lastViewedFile, entry.sourceVolId);
      });
    }

    if (deleted.isEmpty) return;
    setState(() {
      _snapshot = _snapshot.withoutPaths({
        for (final path in deleted) (entry.sourceVolId, path),
      });
    });
  }

  Map<int, ({double top, double height})> _tileGeometries(
    List<CategoryEntry> items,
    Set<int> targets,
    double viewportWidth,
  ) {
    final result = <int, ({double top, double height})>{};
    if (targets.isEmpty) return result;

    if (_layout == BrowserLayoutMode.grid) {
      final live =
          _gridKey.currentState?.geometriesForGlobalIndices(targets);
      if (live != null && live.isNotEmpty) {
        result.addAll(live);
      }
    } else {
      final live =
          _listKey.currentState?.geometriesForGlobalIndices(targets);
      if (live != null && live.isNotEmpty) {
        result.addAll(live);
      }
    }
    return result;
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

    _ensureTilesVisible(
      items,
      {targetIndex},
      animate: false,
      center: false,
    );
  }

  Future<void> _openWithApp(
    MountedContainer container,
    CategoryEntry entry, {
    String? packageName,
  }) async {
    try {
      final ok = container.isLocalStorage
          ? await ref
                .read(vaultLocalShareApiProvider)
                .openLocalFileWithApp(p.join(container.uri, entry.path))
          : await ref
                .read(vaultFileIoApiProvider)
                .openWithApp(container, entry.path, packageName: packageName);
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

  // ── Actions on files, always through their own source ─────────────────────

  Map<int, List<CategoryEntry>> _bySource(List<CategoryEntry> entries) {
    final groups = <int, List<CategoryEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(e.sourceVolId, () => []).add(e);
    }
    return groups;
  }

  Future<void> _share(List<CategoryEntry> entries) async {
    final files = entries.where((e) => !e.isDir).toList();
    if (files.isEmpty) return;
    final groups = _bySource(files);
    if (groups.length != 1) {
      _notify(context.l10n.categoryShareOneSource, error: true);
      return;
    }
    final container = _containers[groups.keys.single];
    if (container == null) return;
    try {
      final paths = [for (final e in files) e.path];
      final ok = container.isRawLocal
          ? await ref.read(vaultLocalShareApiProvider).shareLocalFiles([
              for (final e in paths) p.join(container.uri, e),
            ])
          : await ref.read(vaultFileIoApiProvider).shareFiles(container, paths);
      if (!ok && mounted) {
        _notify(context.l10n.couldNotShareFiles, error: true);
      }
    } catch (_) {
      if (mounted) _notify(context.l10n.couldNotShareFiles, error: true);
    }
  }

  /// Puts [entries] on the app's cross-container clipboard, which already
  /// carries a source per item, so pasting into any folder of any container
  /// copies or moves each file from where it really is.
  void _stage(List<CategoryEntry> entries, {required bool cut}) {
    final files = entries.where((e) => !e.isDir).toList();
    if (files.isEmpty) return;
    final containers = [
      for (final e in files)
        if (_containers[e.sourceVolId] != null) _containers[e.sourceVolId]!,
    ];
    if (cut && containers.any((c) => c.readOnly)) {
      _notify(context.l10n.readOnlyCantMove, error: true);
      return;
    }
    final primary = _containers[files.first.sourceVolId];
    if (primary == null) return;
    ref
        .read(crossContainerClipboardProvider.notifier)
        .set(
          volId: primary.volId,
          displayName: primary.displayName,
          cut: cut,
          clipItems: [
            for (final e in files)
              ClipboardItem(
                path: e.path,
                isDir: false,
                sizeBytes: e.sizeBytes,
                modifiedSecs: e.modifiedSecs,
                volId: e.sourceVolId == primary.volId ? null : e.sourceVolId,
              ),
          ],
        );
    _clearSelection();
    _notify(context.l10n.categoryClipboardReady(files.length));
  }

  void _delete(List<CategoryEntry> entries) {
    final files = entries.where((e) => !e.isDir).toList();
    if (files.isEmpty) return;
    final groups = _bySource(files);
    if (groups.keys.any((id) => _containers[id]?.readOnly ?? false)) {
      _notify(context.l10n.readOnlyCantDelete, error: true);
      return;
    }
    HapticFeedback.heavyImpact();
    BrowserDialogs.showBatchDelete(
      context,
      toDelete: files,
      onConfirmed: (_) {
        _clearSelection();
        final opService = ref.read(fileOperationServiceProvider);
        for (final group in groups.entries) {
          final container = _containers[group.key];
          if (container == null) continue;
          final op = opService.enqueueDelete(
            container: container,
            items: [
              for (final e in group.value)
                ClipboardItem(path: e.path, isDir: false),
            ],
            locationLabel: '',
            l10n: context.l10n,
          );
          void listener() {
            final done =
                op.status != FileOperationStatus.running &&
                op.status != FileOperationStatus.pending;
            if (!done) return;
            op.removeListener(listener);
            if (!mounted) return;
            final removed = {
              for (final status in op.itemStatuses)
                if (status.result == FileItemResult.success)
                  (group.key, status.item.path),
            };
            setState(() => _snapshot = _snapshot.withoutPaths(removed));
          }

          op.addListener(listener);
        }
      },
    );
  }

  Future<void> _rename(CategoryEntry entry) async {
    final container = _containers[entry.sourceVolId];
    if (container == null || entry.isDir) return;
    final parent = entry.parentPath;
    // The folder's current names, so the dialog can refuse a name that is
    // already taken.
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
      // The new name may no longer belong to the category (its extension
      // changed), so look again instead of patching the list.
      onSuccess: () {
        if (!mounted) return;
        _clearSelection();
        unawaited(_startScan(deep: true));
      },
    );
  }

  void _showInFolder(CategoryEntry entry) {
    final container = _containers[entry.sourceVolId];
    final callback = widget.onShowInFolder;
    if (container == null || callback == null) return;
    Navigator.of(context).pop();
    callback(container, entry.path);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  String _categoryLabel() => switch (widget.category) {
    FileCategory.images => context.l10n.filterImagesOption,
    FileCategory.videos => context.l10n.filterVideosOption,
    FileCategory.audio => context.l10n.filterAudioOption,
    FileCategory.documents => context.l10n.filterDocumentsOption,
    FileCategory.gallery => context.l10n.galleryModeAction,
  };

  String _sourceLabel(List<MountedContainer> mounted) {
    final l10n = context.l10n;
    final scoped = widget.scopedContainer;
    if (scoped != null) {
      return _sources[scoped.volId]?.label ?? scoped.displayName;
    }
    switch (_source.kind) {
      case CategorySourceKind.all:
        return l10n.categorySourceAll;
      case CategorySourceKind.device:
        return l10n.localStorageCardTitle;
      case CategorySourceKind.vaults:
        return l10n.vaultsSectionTitle;
      case CategorySourceKind.vault:
        for (final v in mounted) {
          if (v.volId == _source.volId) return v.displayName;
        }
        return l10n.vaultsSectionTitle;
    }
  }

  void _handleBack() {
    if (_selected.isNotEmpty) {
      _clearSelection();
    } else if (_searchActive) {
      _closeSearch();
    } else if (_canGoUp) {
      _goUp();
    }
  }

  void _closeSearch() {
    setState(() {
      _searchActive = false;
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final toolbarConfig = ref
        .watch(fileManagerToolbarSettingsProvider(null))
        .config;
    final mountedVaults = _usesVaults
        ? ref.watch(vaultDashboardControllerProvider.select((s) => s.mounted))
        : const <MountedContainer>[];
    final hasLocations = ref.watch(externalStorageLocationsProvider).isNotEmpty;

    // Each container's own thumbnail policy, resolved once per build.
    final thumbs = <int, ThumbnailSettings?>{};
    for (final container in _containers.values) {
      final state = ref.watch(
        fileManagerToolbarSettingsProvider(
          container.isLocalStorage ? null : container.uri,
        ),
      );
      thumbs[container.volId] = state.loading
          ? null
          : resolveThumbnailSettings(
              config: state.config,
              isLocalStorage: container.isLocalStorage,
              record: state.record,
            );
    }
    _thumbs = thumbs;

    final items = _currentItems();
    final selecting = _selected.isNotEmpty;
    final location = _effectiveLocation;

    return PopScope(
      canPop: !selecting && !_searchActive && !_canGoUp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        // Same as the file manager: the search bar lifts itself by the
        // keyboard's inset instead of the whole body being squeezed above it.
        resizeToAvoidBottomInset: false,
        appBar: selecting && !toolbarConfig.bottomSelectionBar
            ? _buildSelectionBar(l10n)
            : _buildAppBar(l10n, mountedVaults, hasLocations),
        bottomNavigationBar: selecting && toolbarConfig.bottomSelectionBar
            ? Builder(
                builder: (slotContext) => Padding(
                  // The search bar rides above the keyboard; so does this.
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(slotContext).bottom,
                  ),
                  child: Material(
                    color: Theme.of(slotContext).colorScheme.surfaceContainer,
                    elevation: 0,
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        height: kToolbarHeight,
                        child: MediaQuery.removePadding(
                          context: slotContext,
                          removeTop: true,
                          removeBottom: true,
                          child: _buildSelectionBar(l10n),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
        body: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  if (_scanning) const LinearProgressIndicator(minHeight: 2),
                  if (_snapshot.limitReached && !_scanning)
                    _NoticeBar(message: l10n.categoryScanLimitReached),
                  if (_folderMode && !location.isTop)
                    _buildLocationBar(location),
                  Expanded(
                    child: _buildBody(items, toolbarConfig, mountedVaults),
                  ),
                ],
              ),
            ),
            if (_searchActive)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BottomSearchBar(
                  initialQuery: _query,
                  hintText: l10n.search,
                  onChanged: (value) => setState(() => _query = value),
                  onClose: _closeSearch,
                ),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    AppLocalizations l10n,
    List<MountedContainer> mountedVaults,
    bool hasLocations,
  ) {
    final subtitle = _scanning
        ? l10n.categoryScanning(_snapshot.foldersChecked)
        : '${_snapshot.entries.length} · ${_sourceLabel(mountedVaults)}';
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_categoryLabel()),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _searchActive ? Icons.search_off_rounded : Icons.search_rounded,
            color: _searchActive
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          tooltip: _searchActive ? l10n.closeSearchTooltip : l10n.search,
          onPressed: () {
            if (_searchActive) {
              _closeSearch();
            } else {
              setState(() => _searchActive = true);
            }
          },
        ),
        if (!_scoped && widget.includeVaults)
          PopupMenuButton<CategorySourceFilter>(
            icon: const Icon(Icons.storage_rounded),
            tooltip: l10n.categorySourceTooltip,
            onSelected: _setSource,
            itemBuilder: (context) => [
              _sourceItem(CategorySourceFilter.all, l10n.categorySourceAll),
              if (widget.primaryLocalContainer != null || hasLocations)
                _sourceItem(
                  CategorySourceFilter.device,
                  l10n.localStorageCardTitle,
                ),
              if (mountedVaults.isNotEmpty)
                _sourceItem(
                  CategorySourceFilter.vaults,
                  l10n.vaultsSectionTitle,
                ),
              for (final vault in mountedVaults)
                _sourceItem(
                  CategorySourceFilter.vault(vault.volId),
                  vault.displayName,
                  indent: true,
                ),
            ],
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) {
            switch (value) {
              case 'folders':
                _setFolderMode(!_folderMode);
              case 'grid':
                _setLayout(BrowserLayoutMode.grid);
              case 'list':
                _setLayout(BrowserLayoutMode.list);
              case 'detailed':
                _setLayout(BrowserLayoutMode.detailed);
              case 'refresh':
                unawaited(_startScan(deep: true));
              default:
                if (value.startsWith('sort:')) {
                  final field = SortBy.fromJson(value.substring(5));
                  setState(() {
                    if (_sortBy == field) {
                      _sortAscending = !_sortAscending;
                    } else {
                      _sortBy = field;
                      _sortAscending = field == SortBy.name;
                    }
                  });
                }
            }
          },
          itemBuilder: (context) => [
            CheckedPopupMenuItem<String>(
              value: 'folders',
              checked: _folderMode,
              child: Text(l10n.categoryFolderStructure),
            ),
            const PopupMenuDivider(),
            CheckedPopupMenuItem<String>(
              value: 'grid',
              checked: _layout == BrowserLayoutMode.grid,
              child: Text(l10n.layoutModeGrid),
            ),
            CheckedPopupMenuItem<String>(
              value: 'list',
              checked: _layout == BrowserLayoutMode.list,
              child: Text(l10n.layoutModeList),
            ),
            CheckedPopupMenuItem<String>(
              value: 'detailed',
              checked: _layout == BrowserLayoutMode.detailed,
              child: Text(l10n.layoutModeDetailedList),
            ),
            const PopupMenuDivider(),
            for (final entry in {
              SortBy.name: l10n.sortFieldName,
              SortBy.date: l10n.sortFieldDate,
              SortBy.size: l10n.sortFieldSize,
              SortBy.extension: l10n.sortFieldType,
            }.entries)
              CheckedPopupMenuItem<String>(
                value: 'sort:${entry.key.toJson()}',
                checked: _sortBy == entry.key,
                child: Text(entry.value),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'refresh',
              child: Text(l10n.refreshListButton),
            ),
          ],
        ),
      ],
    );
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

  PreferredSizeWidget _buildSelectionBar(AppLocalizations l10n) {
    final selected = _selectedEntries;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: _clearSelection,
      ),
      title: Text(l10n.selectionBarSelectedCount(selected.length)),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all_rounded),
          tooltip: l10n.selectAllAction,
          onPressed: _selectAll,
        ),
        IconButton(
          icon: const Icon(Icons.share_rounded),
          tooltip: l10n.shareAction,
          onPressed: () => _share(selected),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded),
          tooltip: l10n.copyAction,
          onPressed: () => _stage(selected, cut: false),
        ),
        IconButton(
          icon: const Icon(Icons.content_cut_rounded),
          tooltip: l10n.cutTooltip,
          onPressed: () => _stage(selected, cut: true),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: l10n.delete,
          onPressed: () => _delete(selected),
        ),
        if (selected.length == 1)
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  unawaited(_rename(selected.single));
                case 'locate':
                  _showInFolder(selected.single);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'rename',
                child: Text(l10n.renameAction),
              ),
              if (widget.onShowInFolder != null)
                PopupMenuItem<String>(
                  value: 'locate',
                  child: Text(l10n.goToLocationAction),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildLocationBar(CategoryLocation location) {
    final source = _sources[location.volId];
    final text = [
      if (source != null) source.label,
      if (location.dirPath.isNotEmpty) location.dirPath,
    ].join(' / ');
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: InkWell(
        onTap: _canGoUp ? _goUp : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.arrow_upward_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    List<CategoryEntry> items,
    FileManagerToolbarConfig toolbarConfig,
    List<MountedContainer> mountedVaults,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      if (_scanning) return const Center(child: CircularProgressIndicator());
      final noVaults =
          _source.kind != CategorySourceKind.all &&
          _source.kind != CategorySourceKind.device &&
          mountedVaults.isEmpty;
      return RefreshIndicator(
        onRefresh: () => _startScan(deep: true),
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          noVaults
                              ? context.l10n.categoryNoVaultsUnlocked
                              : context.l10n.categoryEmpty,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final anyContainer =
        _containers[items.first.sourceVolId] ?? _containers.values.first;
    final location = _effectiveLocation;
    // In the folder view the entries carry bare names and resolve against the
    // folder shown; in the flat view each carries its path from its source's
    // root, which resolves against the root.
    final currentDirPath = _folderMode && !location.isTop
        ? location.dirPath
        : '';
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final query = _searchActive && _query.trim().isNotEmpty
        ? _query.trim().toLowerCase()
        : null;
    final isGrid = _layout == BrowserLayoutMode.grid;
    // The docked search bar floats over the results, so they have to clear it
    // (and the keyboard it rides on), as in the file manager.
    final searchClearance = _searchActive
        ? 64.0 +
              math.max(
                MediaQuery.viewInsetsOf(context).bottom,
                MediaQuery.viewPaddingOf(context).bottom,
              )
        : 0.0;
    final Widget content = isGrid
        ? FileGridView(
            key: _gridKey,
            scrollController: _scrollController,
            container: anyContainer,
            containerFor: (e) => _containerOfEntry(e) ?? anyContainer,
            cacheModeFor: _cacheModeOf,
            items: items,
            isSelectionMode: _selected.isNotEmpty,
            selectedItems: _selected,
            currentDirPath: currentDirPath,
            thumbnailCacheMode: ThumbnailCacheMode.disabled,
            thumbnailQuality: ThumbnailQuality.defaultQuality,
            showFileNames: toolbarConfig.showGridFileNames,
            showFileExtensions: toolbarConfig.showFileExtensions,
            cornerRadius: toolbarConfig.gridCornerStyle.radius,
            spacing: toolbarConfig.gridSpacing.toDouble(),
            longFileNameMode: toolbarConfig.longFileNameDisplayMode,
            initialColumns: landscape
                ? toolbarConfig.gridColumnsLandscape
                : toolbarConfig.gridColumnsPortrait,
            onDirTap: _onDirTap,
            onFileTap: _onFileTap,
            onItemLongPress: _onItemLongPress,
            onFileLongMenu: (e) {
              if (e is CategoryEntry) _showItemMenu(e);
            },
            showItemActionsMenu: toolbarConfig.showItemActionsMenu,
            onSelectionChanged: (set) =>
                setState(() => _selected = _filesOnly(set)),
            searchQuery: query,
            sortBy: _sortBy,
            bottomClearance: searchClearance,
          )
        : FileListView(
            key: _listKey,
            scrollController: _scrollController,
            container: anyContainer,
            containerFor: (e) => _containerOfEntry(e) ?? anyContainer,
            cacheModeFor: _cacheModeOf,
            currentDirPath: currentDirPath,
            thumbnailCacheMode: ThumbnailCacheMode.disabled,
            thumbnailQuality: ThumbnailQuality.defaultQuality,
            showThumbnails: toolbarConfig.showListThumbnails,
            initialZoomLevel: toolbarConfig.listZoomLevel,
            items: items,
            isSelectionMode: _selected.isNotEmpty,
            isCompact: false,
            isDetailed: _layout == BrowserLayoutMode.detailed,
            selectedItems: _selected,
            detailColumns: toolbarConfig.visibleDetailColumns,
            longFileNameMode: toolbarConfig.longFileNameDisplayMode,
            showItemActionsMenu: toolbarConfig.showItemActionsMenu,
            showFileExtensions: toolbarConfig.showFileExtensions,
            onDirTap: _onDirTap,
            onFileTap: _onFileTap,
            onItemLongPress: _onItemLongPress,
            onFileLongMenu: (e) {
              if (e is CategoryEntry) _showItemMenu(e);
            },
            onSelectionChanged: (set) =>
                setState(() => _selected = _filesOnly(set)),
            searchQuery: query,
            sortBy: _sortBy,
            bottomClearance: searchClearance,
          );
    return RefreshIndicator(
      onRefresh: () => _startScan(deep: true),
      child: content,
    );
  }

  void _showItemMenu(CategoryEntry entry) {
    final l10n = context.l10n;
    final source = _sources[entry.sourceVolId];
    final parent = entry.parentPath;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget action(IconData icon, String label, VoidCallback onTap) =>
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () {
                Navigator.pop(sheetContext);
                onTap();
              },
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  entry.baseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Where the file really is: which storage, which folder.
                subtitle: Text(
                  [
                    if (source != null) source.label,
                    parent.isEmpty ? '/' : parent,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              if (widget.onShowInFolder != null)
                action(
                  Icons.folder_open_rounded,
                  l10n.goToLocationAction,
                  () => _showInFolder(entry),
                ),
              action(
                Icons.share_rounded,
                l10n.shareAction,
                () => _share([entry]),
              ),
              action(
                Icons.copy_rounded,
                l10n.copyAction,
                () => _stage([entry], cut: false),
              ),
              action(
                Icons.content_cut_rounded,
                l10n.cutTooltip,
                () => _stage([entry], cut: true),
              ),
              action(
                Icons.drive_file_rename_outline_rounded,
                l10n.renameAction,
                () => unawaited(_rename(entry)),
              ),
              action(
                Icons.delete_outline_rounded,
                l10n.delete,
                () => _delete([entry]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
