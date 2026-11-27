import 'package:vaultexplorer/core/widgets/adaptive_action_strip.dart';
import 'package:vaultexplorer/core/utils/local_storage_name.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/features/browser/gallery/filter/app_gallery_meta_files.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/vault_gallery_meta_storage.dart';
import 'package:vaultexplorer/features/browser/metadata/metadata_edit_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart'
    show namesAreCaseSensitive;
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart'
    show isAppEncryptedFileName;
import 'package:vaultexplorer/core/utils/path_clipboard.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart'
    show AppBannerTone;
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/thumbnail_settings.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/data/models/vault_item.dart' show VaultItemType;
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/thumbnail_settings_resolver.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_transfer_service.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/windowing/view_focus.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_chrome_hub.dart';
import 'package:vaultexplorer/features/browser/controllers/chrome_bar_slot.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart'
    show PathSegment;
import 'package:vaultexplorer/features/browser/controllers/file_browser_pins_bookmarks_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_operations_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/file_open_dispatch.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_filter_controller.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_filter_l10n.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_filter_labels.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_filter_sheet.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_filters.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_grouping.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_index.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_memory_provider.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_places.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/models/browser_back_policy.dart';
import 'package:vaultexplorer/features/browser/models/category_index.dart';
import 'package:vaultexplorer/features/browser/models/category_source.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/browser/models/file_category_presentation.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_scope_sheet.dart';
import 'package:vaultexplorer/features/library/controllers/library_providers.dart';
import 'package:vaultexplorer/features/browser/remembered_app_capture.dart';
import 'package:vaultexplorer/features/browser/services/category_aggregate_scan.dart';
import 'package:vaultexplorer/features/browser/services/category_scan.dart';
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
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/auto_hide_scroll_host.dart';
import 'package:vaultexplorer/features/browser/widgets/bottom_search_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drag.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/date_group.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_screen.dart';
import 'package:vaultexplorer/features/browser/widgets/file_grid_view.dart';
import 'package:vaultexplorer/features/browser/widgets/file_item_actions_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/file_list_view.dart';
import 'package:vaultexplorer/features/browser/widgets/file_manager_action_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/file_manager_more_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/file_manager_options_menu_button.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_screen.dart';
import 'package:vaultexplorer/features/browser/widgets/file_masonry_view.dart';
import 'package:vaultexplorer/features/browser/widgets/filter_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/layout_mode_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/selection_app_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/sort_menu_button.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart'
    show CryptoDestination, CryptoDirection, CryptoSourceItem;
import 'package:vaultexplorer/features/tools/widgets/single_file_crypto_sheet.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart'
    show kVaultMetaDir;
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/menus/back_dismissible_menu_anchor.dart';

part 'category_content_view_actions.dart';
part 'category_content_view_chrome.dart';
part 'category_content_view_gallery.dart';
part 'category_content_view_scan.dart';

typedef CategoryShowInFolderCallback =
    void Function(MountedContainer container, String path);

class _CategorySourceBundle {
  _CategorySourceBundle(this.container, this.source);

  final MountedContainer container;
  final CategorySource source;
}

class _CategoryPathStep {
  const _CategoryPathStep({required this.segment, required this.location});

  final PathSegment segment;
  final CategoryLocation location;
}

/// Viewport for a category tab (e.g. Images, Videos, Audio, Documents).
///
/// Gathers matching files across phone storage, storage locations, and
/// unlocked vaults, while integrating seamlessly with the workspace chrome hub
/// (same toolbar, selection bar, and 3-dots menu as standard folder tabs).
class CategoryContentView extends ConsumerStatefulWidget {
  const CategoryContentView({
    super.key,
    required this.tabId,
    required this.category,
    required this.workspaceConfig,
    this.primaryLocalContainer,
    this.includeVaults = true,
    this.scopedContainer,
    this.initialDirPath,
    this.onShowInFolder,
    this.resolveContainer,
    this.onScopedFilterChanged,
  });

  final TabId tabId;
  final FileCategory category;
  final BrowserTabsConfig workspaceConfig;
  final MountedContainer? primaryLocalContainer;
  final bool includeVaults;
  final MountedContainer? scopedContainer;
  final String? initialDirPath;
  final CategoryShowInFolderCallback? onShowInFolder;
  final MountedContainer? Function(int volId)? resolveContainer;
  final void Function(String? filter, [String? destinationDir])?
  onScopedFilterChanged;

  @override
  ConsumerState<CategoryContentView> createState() =>
      _CategoryContentViewState();
}

class _CategoryContentViewState extends ConsumerState<CategoryContentView> {
  VaultEngineEvents? _events;
  late CategorySourceFilter _source;
  late bool _folderMode;
  late BrowserLayoutMode _layout;
  late SortBy _sortBy;
  late bool _sortAscending;

  CategoryLocation _location = CategoryLocation.top;
  late CategoryLocation _initialLocation;

  /// The folder a scoped gallery was opened from (its album root while no
  /// folders are chosen).
  String _openedDir = '';

  /// The folders the scoped gallery scans (paths from the storage root,
  /// subfolders included); empty scans the whole storage.
  List<String> _galleryRoots = const [];
  List<PathSegment> _forwardStack = const [];
  List<CategoryLocation> _forwardLocations = const [];
  CategoryAggregateSnapshot _snapshot = CategoryAggregateSnapshot.empty;
  Map<int, MountedContainer> _containers = const {};
  Map<int, CategorySource> _sources = const {};
  Map<int, ThumbnailSettings?> _thumbs = const {};
  Map<int, ThumbnailCacheMode> _galleryMetaModes = const {};
  CancellationToken? _token;
  bool _scanning = true;
  bool _disposed = false;
  bool _exitArmed = false;
  Timer? _exitArmTimer;

  bool _searchActive = false;
  String _query = '';
  final ScrollController _scrollController = ScrollController();

  // While the list is being scrolled nothing that would move its content is
  // applied: the filter index holds its results back, and scan progress is
  // kept aside, both applied when the scrolling has stopped. (An offset
  // correction cannot survive a fling, so a change landing mid-fling would
  // shift the photos under the finger.)
  bool _userScrolling = false;
  Timer? _scrollIdleTimer;
  CategoryAggregateSnapshot? _deferredSnapshot;
  final GlobalKey<FileGridViewState> _gridKey = GlobalKey<FileGridViewState>();
  final GlobalKey<FileMasonryViewState> _masonryKey =
      GlobalKey<FileMasonryViewState>();
  final GlobalKey<FileListViewState> _listKey = GlobalKey<FileListViewState>();

  List<CategoryEntry> _items = const [];
  CategoryAggregateSnapshot? _itemsSnapshot;
  bool? _itemsFolderMode;
  CategoryLocation? _itemsLocation;
  String? _itemsQuery;
  SortBy? _itemsSortBy;
  bool? _itemsSortAscending;

  // Gallery filter: what is applied, what is known about each photo (date
  // taken, place, tags...), and the cache keys of the filtered listing.
  final GalleryFilterController _galleryFilter = GalleryFilterController();
  GalleryMetaIndex? _metaIndex;
  final Set<int> _metaStoredLoadedSources = {};
  GalleryFilterSet? _itemsFilters;
  GalleryGroupBy? _itemsGroupBy;
  int _itemsMetaRevision = -1;
  int _itemsQueryHash = 0;
  int _itemsUnfilteredCount = 0;
  List<DateGroup<RawEntry>>? _itemsGroups;
  int _lastPublishedRevision = 0;
  bool _metaWanted = false;
  GalleryPlaceResolver? _places;
  bool _placesLoading = false;
  bool _itemsPlacesLoaded = false;
  Timer? _metaTimer;
  GalleryFilterLabels _galleryLabels = const GalleryFilterLabels();

  // Holds this tab's bottom bar for the chrome hub. See [ChromeBarSlot].
  final ChromeBarSlot _bottomBarSlot = ChromeBarSlot();

  late final BrowserChromeHub _chrome = ref.read(
    browserChromeProvider(widget.workspaceConfig),
  );

  String get _categoryKey => widget.category.storageKey;
  bool get _scoped => widget.scopedContainer != null;
  bool get _isGallery => widget.category == FileCategory.gallery;

  /// Which toolbar-settings provider holds this storage's per-storage state
  /// (phone storage shares the global one).
  String? get _scopedToolbarUri {
    final c = widget.scopedContainer;
    if (c == null) return null;
    return c.isLocalStorage ? null : c.uri;
  }

  List<String> _readGalleryRoots(FileManagerToolbarConfig config) {
    final c = widget.scopedContainer;
    if (c == null || !_isGallery) return const [];
    return normalizeScanRoots(config.galleryFoldersForStorage(c.uri));
  }

  static bool _sameRoots(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool get _usesVaults =>
      _scoped ? !widget.scopedContainer!.isLocalStorage : widget.includeVaults;

  bool get _isActiveTab {
    final active = ref.read(activeBrowserTabProvider(widget.workspaceConfig));
    return active?.tabId == widget.tabId;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollTick);
    _galleryFilter.addListener(_onGalleryFilterChanged);
    if (widget.scopedContainer != null) {
      _containers = {widget.scopedContainer!.volId: widget.scopedContainer!};
      final initialDir = widget.initialDirPath ?? '';
      _openedDir = initialDir;
      _galleryRoots = _readGalleryRoots(
        ref.read(fileManagerToolbarSettingsProvider(_scopedToolbarUri)).config,
      );
      // A scoped gallery keeps the folder it was opened from as its album
      // root; the category scan may cover the whole container, but the listing
      // is limited to this location. Once folders were chosen for the gallery
      // they can lie anywhere, so it then starts at the storage root.
      _location = CategoryLocation(
        widget.scopedContainer!.volId,
        _galleryRoots.isEmpty ? initialDir : '',
      );
      _folderMode = !_isGallery;
    } else {
      _location = CategoryLocation.top;
      final settings = ref.read(appSettingsControllerProvider).settings;
      _folderMode =
          !_isGallery &&
          settings.categoryFolderStructure.contains(_categoryKey);
    }
    _initialLocation = _location;
    final settings = ref.read(appSettingsControllerProvider).settings;
    _source = _scoped || !widget.includeVaults
        ? CategorySourceFilter.all
        : CategorySourceFilter.fromStorageKey(
            settings.categorySources[_categoryKey],
          );
    final visual =
        widget.category == FileCategory.images ||
        widget.category == FileCategory.videos ||
        _isGallery;
    // The layout this category was last left in; the default grid/list only
    // the first time.
    _layout =
        BrowserLayoutMode.fromJson(settings.categoryLayouts[_categoryKey]) ??
        (visual ? BrowserLayoutMode.grid : BrowserLayoutMode.list);
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

    // Showing hidden files or `.nomedia` folders changes what a scan finds, so
    // rescan once the new value is really in the provider. The toggles save
    // through a microtask, so scanning right after the tap would still read
    // the old value.
    ref.listenManual<FileManagerToolbarSettingsState>(
      fileManagerToolbarSettingsProvider(null),
      (previous, next) {
        if (_disposed || previous == null) return;
        final was = previous.config;
        final now = next.config;
        if (was.showHiddenFiles != now.showHiddenFiles ||
            was.showNoMediaFolders != now.showNoMediaFolders) {
          unawaited(_startScan());
        }
      },
    );
    if (_scoped && _isGallery) {
      ref.listenManual<FileManagerToolbarSettingsState>(
        fileManagerToolbarSettingsProvider(_scopedToolbarUri),
        (previous, next) {
          if (_disposed || next.loading) return;
          final roots = _readGalleryRoots(next.config);
          if (!_sameRoots(roots, _galleryRoots)) _applyGalleryRoots(roots);
        },
      );
    }

    HardwareKeyboard.instance.addHandler(_handleCategoryKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startScan());
    });
  }

  bool _deactivated = false;

  @override
  void deactivate() {
    _deactivated = true;
    super.deactivate();
  }

  @override
  void activate() {
    _deactivated = false;
    super.activate();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleCategoryKey);
    _disposed = true;
    _deactivated = true;
    _token?.cancel();
    _exitArmTimer?.cancel();
    _events?.removeContainerLockedListener(_onVaultLocked);
    _galleryFilter.removeListener(_onGalleryFilterChanged);
    _galleryFilter.dispose();
    _metaTimer?.cancel();
    final meta = _metaIndex;
    if (meta != null) {
      meta.removeListener(_onMetaIndexChanged);
      meta.cancel();
      unawaited(meta.flush());
      meta.dispose();
    }
    _scrollIdleTimer?.cancel();
    _scrollController.removeListener(_onScrollTick);
    _scrollController.dispose();
    super.dispose();
  }

  static bool _skipVaultMetaFolder(String dirPath) => dirPath == kVaultMetaDir;

  /// Gathers the category's files from every source in play.
  ///
  /// Phone storage is not walked from scratch each time: the last result is
  /// shown at once, the platform's file index supplies the fresh one, and the
  /// folders are only visited when that cannot answer (see
  /// [DeviceCategoryIndex]). [deep] skips the index and walks, for the cases
  /// where it must not be trusted to know about a change: a pull to refresh,
  /// and a rescan after an operation that wrote files.
  Future<void> _startScan({bool deep = false, bool keepResults = false}) async {
    _token?.cancel();
    final token = _token = CancellationToken();
    final toolbar = ref.read(fileManagerToolbarSettingsProvider(null)).config;
    final showHidden = toolbar.showHiddenFiles;
    final showNoMedia = toolbar.showNoMediaFolders;
    // Folders chosen for the gallery; empty scans each source whole.
    final roots = _scoped && _isGallery ? _galleryRoots : const <String>[];

    // A rescan of what is already shown (after an operation, a refresh, a
    // vault mounted) leaves the list on screen until the result is in: blanking
    // it first loses the scroll position. A scan of something else (another
    // source or folder choice, hidden files shown) starts from nothing.
    final keep = (deep || keepResults) && _snapshot.entries.isNotEmpty;
    _deferredSnapshot = null;

    setState(() {
      _scanning = true;
      if (!keep) _snapshot = CategoryAggregateSnapshot.empty;
      _forwardStack = const [];
      _forwardLocations = const [];
    });
    _clearSelection();

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

    final seeds = <int, List<RawEntry>>{};
    if (indexEnabled) {
      await Future.wait([
        for (final b in bundles)
          if (b.source.isVault)
            _loadIndexSeed(api, b.container, showHidden, showNoMedia).then((
              seed,
            ) {
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
          deviceIndex.seed(_deviceKey(b, showHidden, showNoMedia)).then((seed) {
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
                      _deviceKey(b, showHidden, showNoMedia),
                      extensions: extensions,
                      matches: matches,
                      isHidden: isHiddenEntryName,
                      skipDirectory: skipDeviceCategoryFolder,
                    ),
              seed: seeds[b.source.volId],
              roots: roots,
            )
          else
            CategoryScanTarget(
              source: b.source,
              listDirectory: (dir) => api.listDirectory(b.container, dir),
              skipDirectory: b.source.isVault ? _skipVaultMetaFolder : null,
              // Vaults and external locations honour `.nomedia` like phone
              // storage does; before, only phone storage did.
              respectNoMedia: widget.category != FileCategory.documents,
              seed: seeds[b.source.volId],
              roots: roots,
            ),
      ],
      matches: matches,
      isHidden: isHiddenEntryName,
      showHidden: showHidden,
      showNoMedia: showNoMedia,
    );

    final result = await scanner.scan(
      token: token,
      progressInterval: const Duration(milliseconds: 500),
      onProgress: (snapshot) {
        if (_disposed || token.isCancelled) return;
        if (keep) return; // what is shown stays until the scan is done
        if (_userScrolling && _snapshot.entries.isNotEmpty) {
          _deferredSnapshot = snapshot;
          return;
        }
        setState(() => _snapshot = _withoutLockedVaults(snapshot));
      },
    );
    if (_disposed || token.isCancelled) return;
    _deferredSnapshot = null;
    setState(() {
      _snapshot = _withoutLockedVaults(result);
      _scanning = false;
    });
    // A scan that includes `.nomedia` folders must not become the stored
    // index, which the next default scan would show before it finishes.
    // A scan limited to chosen folders is only part of the storage, so it
    // must not stand in for the whole in the stored or remembered index.
    if (roots.isEmpty) {
      if (indexEnabled && !showNoMedia) {
        unawaited(_saveIndex(api, bundles, result));
      }
      unawaited(
        _rememberDevice(deviceIndex, bundles, result, showHidden, showNoMedia),
      );
    }
  }

  // Covers for the folder tiles, taken from what the scan already found: for
  // every folder, the best few photos or videos anywhere beneath it. Listing
  // the folder instead only sees files directly inside, so a folder that holds
  // nothing but sub-folders (DCIM, say) never got a cover.
  static const int _coversPerFolder = 8;
  CategoryAggregateSnapshot? _coversSnapshot;
  Map<String, List<CategoryEntry>> _covers = const {};

  /// Photos before videos (only photos can be turned into a cover), newer
  /// first.
  static int _coverOrder(CategoryEntry a, CategoryEntry b) {
    final aImage = MediaViewerConstants.isImage(a.baseName);
    final bImage = MediaViewerConstants.isImage(b.baseName);
    if (aImage != bImage) return aImage ? -1 : 1;
    return b.modifiedSecs.compareTo(a.modifiedSecs);
  }

  /// Applies a new choice of gallery folders and rescans.
  void _applyGalleryRoots(List<String> roots) {
    final scoped = widget.scopedContainer;
    if (scoped == null) return;
    setState(() {
      _galleryRoots = roots;
      _location = CategoryLocation(
        scoped.volId,
        roots.isEmpty ? _openedDir : '',
      );
      _initialLocation = _location;
      _forwardStack = const [];
      _forwardLocations = const [];
    });
    unawaited(_startScan());
  }

  void _onVaultLocked(int volId) {
    if (_disposed) return;
    setState(() {
      _containers = Map.of(_containers)..remove(volId);
      _sources = Map.of(_sources)..remove(volId);
      _snapshot = _snapshot.withoutSource(volId);
      _forwardStack = const [];
      _forwardLocations = const [];
    });
    _metaStoredLoadedSources.remove(volId);
    _metaIndex?.forget(volId);
  }

  CategoryLocation get _effectiveLocation =>
      effectiveCategoryLocation(_snapshot, _location);

  // ── Gallery filter ───────────────────────────────────────────────────────

  GalleryMetaIndex get _meta => _metaIndex ??= _createMetaIndex();

  ThumbnailCacheMode _metaCacheMode(int volId) {
    final selected = _galleryMetaModes[volId];
    if (selected != null) return selected;
    final container = _containers[volId];
    if (container == null) return ThumbnailCacheMode.disabled;
    final settings = ref.read(
      fileManagerToolbarSettingsProvider(
        container.isLocalStorage ? null : container.uri,
      ),
    );
    if (container.isLocalStorage) {
      return settings.config.localStorageGalleryMetadataCacheMode;
    }
    return settings.record?.galleryMetadataCacheMode ??
        settings.config.defaultGalleryMetadataCacheMode;
  }

  /// Every move of the list. The first one holds back what would change the
  /// list under the finger; [_onScrollIdle] lets it through again once the
  /// scrolling has been quiet for a moment.
  void _onScrollTick() {
    if (_disposed) return;
    if (!_userScrolling) {
      _userScrolling = true;
      _metaIndex?.paused = true;
    }
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(const Duration(milliseconds: 250), _onScrollIdle);
  }

  void _onScrollIdle() {
    _scrollIdleTimer = null;
    if (_disposed || !mounted) return;
    _userScrolling = false;
    _metaIndex?.paused = false;
    final deferred = _deferredSnapshot;
    if (deferred != null) {
      _deferredSnapshot = null;
      setState(() => _snapshot = _withoutLockedVaults(deferred));
    }
  }

  void _onMetaIndexChanged() {
    if (!mounted || _disposed) return;
    final pubRev = _metaIndex?.publishedRevision ?? 0;
    if (pubRev != _lastPublishedRevision) {
      _lastPublishedRevision = pubRev;
      setState(() {});
    }
  }

  void _onGalleryFilterChanged() {
    if (!mounted || _disposed) return;
    final g = _galleryFilter.groupBy;
    if (g.isDate) _scheduleMetaIndexing(delay: Duration.zero);
    if (_galleryFilter.hasFilters ||
        g == GalleryGroupBy.place ||
        g == GalleryGroupBy.camera) {
      _markMetaWanted();
    }
    setState(() {});
  }

  /// The bundled city list, loaded once when places are first needed. Until it
  /// is there (a fraction of a second) places show as coordinates.
  Future<void> _loadPlaces() async {
    if (_places != null || _placesLoading) return;
    _placesLoading = true;
    try {
      final data = await rootBundle.load('assets/geo/cities.bin');
      final resolver = GalleryPlaceResolver.fromBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      if (!mounted || _disposed) return;
      setState(() => _places = resolver);
    } catch (_) {
      // No city list: places stay coordinates.
    } finally {
      _placesLoading = false;
    }
  }

  Future<void> _loadMetaIndex() async {
    final meta = _meta;
    final entries = _snapshot.entries;
    final sourceIds = {for (final e in entries) e.sourceVolId};

    // Restore saved capture dates before displaying a date-grouped gallery, so
    // a cold launch does not first paint the same files in modified-time order.
    await meta.loadStored(sourceIds);
    if (_disposed || !mounted) return;

    final newSources = sourceIds.difference(_metaStoredLoadedSources);
    _metaStoredLoadedSources.addAll(sourceIds);
    if (newSources.isNotEmpty) setState(() {});

    // Date-grouped gallery sections use the camera's capture date when one is
    // available. Index those dates on entry instead of waiting for the filter
    // sheet to request metadata; until then the listing only knows file mtimes.
    if (!_metaWanted && !_galleryFilter.groupBy.isDate) return;
    final requests = <GalleryIndexRequest>[
      for (final e in entries)
        if (!e.isDir)
          GalleryIndexRequest(
            e.sourceVolId,
            e.path,
            e.sizeBytes,
            e.modifiedSecs,
          ),
    ]..sort((a, b) => b.mtime.compareTo(a.mtime)); // newest first
    unawaited(meta.ensure(requests));
  }

  bool get _canGoUp {
    if (_scoped && _isGallery) {
      return _effectiveLocation.dirPath.isNotEmpty;
    }
    if (!_folderMode) return false;
    if (_scoped) {
      return _location != _initialLocation &&
          _buildPathSteps(_effectiveLocation).length > 1;
    }
    return _buildPathSteps(_effectiveLocation).length > 1;
  }

  /// Leaves a scoped category, including gallery mode, at the folder it
  /// represents in the underlying file manager.
  void _exitScopedCategory() {
    if (!_scoped) return;
    widget.onScopedFilterChanged?.call(null, _effectiveLocation.dirPath);
  }

  void _toggleScopedGallery() {
    if (!_scoped) return;
    if (_isGallery) {
      _exitScopedCategory();
    } else {
      widget.onScopedFilterChanged?.call('gallery', _effectiveLocation.dirPath);
    }
  }

  /// What back means at the root of a scoped gallery. Shared by the back
  /// handler and by [PopScope.canPop], so what the system is told can never
  /// drift from what actually happens.
  BrowserBackAction _resolveScopedGalleryRootBack() {
    final settings = ref.read(appSettingsControllerProvider).settings;
    return resolveBrowserBack(
      selectionMode: false,
      searchActive: false,
      atRoot: true,
      appRoot: widget.workspaceConfig.appRoot,
      hostsHome: widget.workspaceConfig.includeDashboardTab,
      tabsEnabled: settings.useBrowserTabs,
    );
  }

  void _handleScopedGalleryBackAtRoot() {
    final action = _resolveScopedGalleryRootBack();
    switch (action) {
      case BrowserBackAction.returnHome:
        final tabs = ref.read(
          browserTabsProvider(widget.workspaceConfig).notifier,
        );
        if (!tabs.returnToDashboardAtRoot(widget.tabId)) {
          tabs.replaceActiveWithDashboard();
        }
      case BrowserBackAction.popRoute:
        final navigator = Navigator.of(context);
        if (navigator.canPop()) navigator.pop();
      case BrowserBackAction.leave:
        if (_exitArmed) {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
        } else {
          _armExit();
        }
      case BrowserBackAction.stay:
        break;
      case BrowserBackAction.exitSelection:
      case BrowserBackAction.clearSearch:
      case BrowserBackAction.navigateUp:
        break;
    }
  }

  void _armExit() {
    _exitArmTimer?.cancel();
    setState(() => _exitArmed = true);
    showAppSnackBar(
      context,
      message: context.l10n.pressBackAgainToExit,
      tone: AppBannerTone.info,
    );
    _exitArmTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _exitArmed = false);
    });
  }

  void _goUp() {
    final currentSteps = _buildPathSteps(_effectiveLocation);
    if (currentSteps.length <= 1) return;

    final removedStep = currentSteps.last;
    final parentStep = currentSteps[currentSteps.length - 2];

    setState(() {
      _location = parentStep.location;
      _forwardStack = [removedStep.segment, ..._forwardStack];
      _forwardLocations = [removedStep.location, ..._forwardLocations];
    });
    _clearSelection();
    _jumpToTop();
  }

  void _enterFolder(CategoryEntry folder) {
    final newLocation = CategoryLocation(folder.sourceVolId, folder.path);
    final newPathSteps = _buildPathSteps(newLocation);
    final newFatPath = newPathSteps.last.segment.fatPath;

    final followsForward =
        _forwardStack.isNotEmpty && _forwardStack.first.fatPath == newFatPath;

    setState(() {
      _location = newLocation;
      if (followsForward) {
        _forwardStack = _forwardStack.sublist(1);
        _forwardLocations = _forwardLocations.sublist(1);
      } else {
        _forwardStack = const [];
        _forwardLocations = const [];
      }
    });
    _clearSelection();
    _jumpToTop();
  }

  void _onJumpTo(int index) {
    final currentSteps = _buildPathSteps(_effectiveLocation);
    if (index < 0 || index >= currentSteps.length - 1) return;

    final removedSteps = currentSteps.sublist(index + 1);
    final targetStep = currentSteps[index];

    setState(() {
      _location = targetStep.location;
      _forwardStack = [...removedSteps.map((s) => s.segment), ..._forwardStack];
      _forwardLocations = [
        ...removedSteps.map((s) => s.location),
        ..._forwardLocations,
      ];
    });
    _clearSelection();
    _jumpToTop();
  }

  void _onForwardTo(int index) {
    if (index < 0 || index >= _forwardStack.length) return;

    final targetLocation = _forwardLocations[index];
    final remainingStack = _forwardStack.sublist(index + 1);
    final remainingLocations = _forwardLocations.sublist(index + 1);

    setState(() {
      _location = targetLocation;
      _forwardStack = remainingStack;
      _forwardLocations = remainingLocations;
    });
    _clearSelection();
    _jumpToTop();
  }

  void _jumpToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _setSource(CategorySourceFilter source) {
    if (source == _source) return;
    setState(() {
      _source = source;
      _location = CategoryLocation.top;
      _forwardStack = const [];
      _forwardLocations = const [];
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
            categoryLayouts: {
              ...s.categoryLayouts,
              _categoryKey: mode.toJson(),
            },
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
      if (!_scoped) {
        _location = CategoryLocation.top;
        _forwardStack = const [];
        _forwardLocations = const [];
      }
    });
    _clearSelection();
    ref.read(appSettingsControllerProvider.notifier).updateSettings((s) {
      final keys = {...s.categoryFolderStructure};
      on ? keys.add(_categoryKey) : keys.remove(_categoryKey);
      return s.copyWith(categoryFolderStructure: keys.toList());
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchActive = !_searchActive;
      if (!_searchActive) {
        _query = '';
      }
    });
  }

  MountedContainer? _containerOfEntry(RawEntry entry) =>
      entry is CategoryEntry ? _containers[entry.sourceVolId] : null;

  ThumbnailCacheMode _cacheModeOf(RawEntry entry) {
    if (entry is! CategoryEntry) return ThumbnailCacheMode.appCache;
    return _thumbs[entry.sourceVolId]?.cacheMode ?? ThumbnailCacheMode.appCache;
  }

  ThumbnailQuality _qualityOf(RawEntry entry) {
    if (entry is! CategoryEntry) return ThumbnailQuality.defaultAutoQuality;
    return _thumbs[entry.sourceVolId]?.quality ??
        ThumbnailQuality.defaultAutoQuality;
  }

  Set<RawEntry> _filesOnly(Iterable<RawEntry> entries) => {
    for (final e in entries)
      if (!e.isDir) e,
  };

  void _clearSelection() {
    ref
        .read(fileBrowserSelectionProvider(widget.tabId).notifier)
        .exitSelectionMode();
  }

  void _selectAll() {
    ref
        .read(fileBrowserSelectionProvider(widget.tabId).notifier)
        .setSelectedItems(_filesOnly(_items));
  }

  Future<void> _openMedia(
    CategoryEntry entry,
    MountedContainer container,
  ) async {
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
              settings?.quality ?? ThumbnailQuality.defaultAutoQuality,
          thumbnailCacheMode:
              settings?.cacheMode ?? ThumbnailCacheMode.appCache,
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
    } else if (lastViewedFile != entry.path && _scrollController.hasClients) {
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

    switch (_layout) {
      case BrowserLayoutMode.masonry:
        final live = _masonryKey.currentState?.geometriesForGlobalIndices(
          targets,
        );
        if (live != null && live.isNotEmpty) {
          result.addAll(live);
        }
        break;
      case BrowserLayoutMode.grid:
        final live = _gridKey.currentState?.geometriesForGlobalIndices(targets);
        if (live != null && live.isNotEmpty) {
          result.addAll(live);
        }
        break;
      case BrowserLayoutMode.list:
      case BrowserLayoutMode.detailed:
      case BrowserLayoutMode.compact:
        final live = _listKey.currentState?.geometriesForGlobalIndices(targets);
        if (live != null && live.isNotEmpty) {
          result.addAll(live);
        }
        break;
    }
    return result;
  }

  void _openFileManagerForStagedItems(List<CategoryEntry> entries) {
    final first = entries.where((entry) => !entry.isSourceRoot).firstOrNull;
    if (first == null) return;
    final tabs = ref.read(browserTabsProvider(widget.workspaceConfig));
    final writableFolderTab = tabs.tabs
        .where(
          (tab) =>
              !tab.isCategory &&
              !tab.isDashboard &&
              tab.container != null &&
              !tab.container!.readOnly,
        )
        .firstOrNull;
    final source = _containers[first.sourceVolId];
    final container = source != null && !source.readOnly
        ? source
        : widget.primaryLocalContainer != null &&
              !widget.primaryLocalContainer!.readOnly
        ? widget.primaryLocalContainer
        : _containers.values
              .where((candidate) => !candidate.readOnly)
              .firstOrNull;
    if (container == null) {
      if (writableFolderTab != null) {
        ref
            .read(browserTabsProvider(widget.workspaceConfig).notifier)
            .activate(writableFolderTab.tabId);
      }
      return;
    }
    if (_scoped && container.volId != widget.scopedContainer!.volId) {
      final targetTab = tabs.tabs
          .where((tab) => !tab.isCategory && tab.volId == container.volId)
          .firstOrNull;
      if (targetTab != null) {
        ref
            .read(browserTabsProvider(widget.workspaceConfig).notifier)
            .activate(targetTab.tabId);
      }
      return;
    }
    final path = container.volId == first.sourceVolId ? first.path : '';
    final showInFolder = widget.onShowInFolder;
    if (showInFolder != null) {
      // The category viewport has no paste target. Opening the first staged
      // item's real folder switches to the regular browser (or clears a
      // scoped filter), where the shared clipboard's Paste action is shown.
      showInFolder(container, path);
      return;
    }

    setState(() {
      _folderMode = true;
      _location = CategoryLocation(
        container.volId,
        path.isEmpty ? '' : parentOfPath(path),
      );
      _forwardStack = const [];
      _forwardLocations = const [];
    });
    _jumpToTop();
  }

  void _delete(List<CategoryEntry> entries) {
    final eligible = entries.where((e) => !e.isSourceRoot).toList();
    if (eligible.isEmpty) return;
    final groups = _bySource(eligible);
    if (groups.keys.any((id) => _containers[id]?.readOnly ?? false)) {
      _notify(context.l10n.readOnlyCantDelete, error: true);
      return;
    }
    HapticFeedback.heavyImpact();
    BrowserDialogs.showBatchDelete(
      context,
      toDelete: eligible,
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
                ClipboardItem(path: e.path, isDir: e.isDir),
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
            ref
                .read(crossContainerClipboardProvider.notifier)
                .removeDeletedPaths(group.key, removed.map((e) => e.$2));
            setState(() => _snapshot = _snapshot.withoutPaths(removed));
          }

          op.addListener(listener);
        }
      },
    );
  }

  bool get _isCategoryKeyboardTarget {
    if (!PlatformFeatures.isDesktop) return false;
    if (!mounted || _disposed || _deactivated || !_isActiveTab) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    var hidden = false;
    context.visitAncestorElements((element) {
      final w = element.widget;
      if (w is Offstage && w.offstage) {
        hidden = true;
        return false;
      }
      return true;
    });
    if (hidden) return false;
    if (!keyboardFocusIsInViewOf(context)) return false;
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused?.findAncestorWidgetOfExactType<EditableText>() == null;
  }

  bool _handleCategoryKey(KeyEvent event) {
    if (event is! KeyDownEvent || !_isCategoryKeyboardTarget) return false;
    final kb = HardwareKeyboard.instance;
    final primary = kb.isControlPressed || kb.isMetaPressed;
    if (!primary || kb.isAltPressed || kb.isShiftPressed) return false;
    final selected = ref
        .read(fileBrowserSelectionProvider(widget.tabId))
        .items
        .whereType<CategoryEntry>()
        .toList();
    if (event.logicalKey == LogicalKeyboardKey.keyA && _items.isNotEmpty) {
      _selectAll();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC && selected.isNotEmpty) {
      _stage(selected, cut: false);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyX && selected.isNotEmpty) {
      _stage(selected, cut: true);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    _galleryLabels = context.galleryFilterLabels;
    final l10n = context.l10n;
    final toolbarConfig = ref
        .watch(fileManagerToolbarSettingsProvider(null))
        .config;
    final mountedVaults = _usesVaults
        ? ref.watch(vaultDashboardControllerProvider.select((s) => s.mounted))
        : const <MountedContainer>[];
    final hasLocations = ref.watch(externalStorageLocationsProvider).isNotEmpty;

    final thumbs = <int, ThumbnailSettings?>{};
    final galleryMetaModes = <int, ThumbnailCacheMode>{};
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
      galleryMetaModes[container.volId] = container.isLocalStorage
          ? state.config.localStorageGalleryMetadataCacheMode
          : (state.record?.galleryMetadataCacheMode ??
                state.config.defaultGalleryMetadataCacheMode);
    }
    _thumbs = thumbs;
    _galleryMetaModes = galleryMetaModes;

    final items = _currentItems();
    final selection = ref.watch(fileBrowserSelectionProvider(widget.tabId));
    final isSelecting = selection.items.isNotEmpty;
    final selectedForMarks = selection.items
        .whereType<CategoryEntry>()
        .where((entry) => !entry.isSourceRoot)
        .toList(growable: false);
    final marksBySource = <int, VaultMarks>{};
    for (final volId
        in selectedForMarks.map((entry) => entry.sourceVolId).toSet()) {
      marksBySource[volId] = ref.watch(fileBrowserPinsBookmarksProvider(volId));
      final container = _containers[volId];
      if (container != null) {
        unawaited(
          ref
              .read(fileBrowserPinsBookmarksProvider(volId).notifier)
              .ensureLoaded(container),
        );
      }
    }
    final location = _effectiveLocation;
    final isLandscape =
        context.screen.useLandscapeLayout;
    final useFab = toolbarConfig.useFabForToolbar;
    final showActionBar = !_searchActive && !useFab;

    final canPlayMedia = items.any(
      (e) => !e.isDir && MediaViewerConstants.isSupported(e.baseName),
    );

    final actionBuilders = <FileManagerAction, WidgetBuilder>{
      FileManagerAction.search: (context) => IconButton(
        icon: Icon(
          _searchActive ? Icons.search_off_rounded : Icons.search_rounded,
        ),
        tooltip: _searchActive
            ? l10n.closeSearchTooltip
            : l10n.searchInThisFolderTooltip,
        onPressed: _toggleSearch,
      ),
      FileManagerAction.viewToggle: (context) => LayoutModeMenuButton(
        layoutMode: _layout,
        onLayoutModeChanged: _setLayout,
        gridAspectRatio: toolbarConfig.gridAspectRatio,
        onGridAspectRatioChanged: (ratio) =>
            _updateToolbarConfig((c) => c.copyWith(gridAspectRatio: ratio)),
      ),
      FileManagerAction.sort: (context) => SortMenuButton(
        sortBy: _sortBy,
        sortAscending: _sortAscending,
        onSortChanged: (field) {
          setState(() {
            if (_sortBy == field) {
              _sortAscending = !_sortAscending;
            } else {
              _sortBy = field;
              _sortAscending = field == SortBy.name;
            }
          });
        },
      ),
      FileManagerAction.filter: (context) => _isGallery
          ? _galleryFilterButton(context)
          : _scoped
          ? FilterMenuButton(
              currentFilter: widget.category.filterKey,
              onFilterChanged: (filter) => widget.onScopedFilterChanged?.call(
                filter,
                _effectiveLocation.dirPath,
              ),
              hideVaultOnlyActions: widget.scopedContainer!.isLocalStorage,
            )
          : PopupMenuButton<CategorySourceFilter>(
              icon: const Icon(Icons.storage_rounded),
              tooltip: l10n.categorySourceTooltip,
              onSelected: _setSource,
              itemBuilder: (context) => [
                _sourceItem(CategorySourceFilter.all, l10n.categorySourceAll),
                if (widget.primaryLocalContainer != null || hasLocations)
                  _sourceItem(
                    CategorySourceFilter.device,
                    localStorageDisplayName(l10n.localStorageCardTitle),
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
      FileManagerAction.playMedia: (context) => IconButton(
        icon: const Icon(Icons.play_circle_outline_rounded),
        tooltip: l10n.playMediaHereTooltip,
        onPressed: canPlayMedia ? _playMediaFromFirst : null,
      ),
      FileManagerAction.gallery: (context) => IconButton(
        icon: Icon(
          _isGallery
              ? Icons.photo_library_rounded
              : Icons.photo_library_outlined,
          color: _isGallery ? Theme.of(context).colorScheme.primary : null,
        ),
        tooltip: l10n.galleryModeTooltip,
        onPressed: _toggleScopedGallery,
      ),
      FileManagerAction.options: (context) => FileManagerOptionsMenuButton(
        toolbarConfig: toolbarConfig,
        onToggleShowHiddenFiles: (v) {
          _updateToolbarConfig((c) => c.copyWith(showHiddenFiles: v));
        },
        onToggleShowNoMediaFolders: (v) {
          _updateToolbarConfig((c) => c.copyWith(showNoMediaFolders: v));
        },
        onToggleShowGridFileNames: (v) {
          _updateToolbarConfig((c) => c.copyWith(showGridFileNames: v));
        },
        onToggleShowFileExtensions: (v) {
          _updateToolbarConfig((c) => c.copyWith(showFileExtensions: v));
        },
        onToggleShowListThumbnails: (v) {
          _updateToolbarConfig((c) => c.copyWith(showListThumbnails: v));
        },
        onOpenSettings: _openFileManagerSettings,
        onPickGalleryFolders: _scoped && _isGallery
            ? _pickGalleryFolders
            : null,
        galleryFolderCount: _galleryRoots.length,
      ),
    };

    // The storage picker behind the Filter action of the categories shortcut
    // screen, as menu entries for the floating toolbar's cascading menu (the
    // app bar keeps its PopupMenuButton with the same choices).
    List<Widget> buildSourceMenuItems(BuildContext menuContext) {
      MenuItemButton entry(
        CategorySourceFilter filter,
        String label, {
        bool indent = false,
      }) {
        final selected = _source == filter;
        return MenuItemButton(
          leadingIcon: Icon(selected ? Icons.check_rounded : null, size: 18),
          onPressed: () => _setSource(filter),
          child: Padding(
            padding: EdgeInsets.only(left: indent ? 16 : 0),
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
        );
      }

      return [
        entry(CategorySourceFilter.all, l10n.categorySourceAll),
        if (widget.primaryLocalContainer != null || hasLocations)
          entry(CategorySourceFilter.device, localStorageDisplayName(l10n.localStorageCardTitle)),
        if (mountedVaults.isNotEmpty)
          entry(CategorySourceFilter.vaults, l10n.vaultsSectionTitle),
        for (final vault in mountedVaults)
          entry(
            CategorySourceFilter.vault(vault.volId),
            vault.displayName,
            indent: true,
          ),
      ];
    }

    final visibleActions = toolbarConfig.visible.where((a) {
      // Gallery mode is a view of one storage's files; the categories
      // shortcut screen spans storages, so toggling it there did nothing.
      if (!_scoped && a == FileManagerAction.gallery) return false;
      return actionBuilders.containsKey(a);
    }).toList();

    // One model of every toolbar action's menu form, shared by the floating
    // toolbar's "More" button and the app bar's adaptive overflow menu.
    FileManagerMoreMenuButton moreMenuModel(
      List<FileManagerAction> actions,
    ) => FileManagerMoreMenuButton(
              actions: actions,
              searchActive: _searchActive,
              onToggleSearch: _toggleSearch,
              sortBy: _sortBy,
              sortAscending: _sortAscending,
              onSortChanged: (field) {
                setState(() {
                  if (_sortBy == field) {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortBy = field;
                    _sortAscending = field == SortBy.name;
                  }
                });
              },
              currentFilter: _scoped ? widget.category.filterKey : null,
              onFilterChanged: _scoped
                  ? (filter) => widget.onScopedFilterChanged?.call(filter)
                  : (_) {},
              hideVaultOnlyActions:
                  !_scoped || widget.scopedContainer!.isLocalStorage,
              customFilterMenuBuilder: _isGallery
                  ? _galleryFilterMenuItems
                  : (_scoped ? null : buildSourceMenuItems),
              customFilterActive: _isGallery
                  ? _galleryFilter.hasFilters
                  : _source != CategorySourceFilter.all,
              customFilterIcon: _isGallery
                  ? Icons.filter_alt_outlined
                  : Icons.storage_rounded,
              customFilterTooltip: _isGallery
                  ? l10n.galleryFilterTooltip
                  : l10n.categorySourceTooltip,
              layoutMode: _layout,
              onLayoutModeChanged: _setLayout,
              gridAspectRatio: toolbarConfig.gridAspectRatio,
              onGridAspectRatioChanged: (ratio) => _updateToolbarConfig(
                (c) => c.copyWith(gridAspectRatio: ratio),
              ),
              canPlayMedia: canPlayMedia,
              onPlayMedia: _playMediaFromFirst,
              isGalleryMode: _isGallery,
              onToggleGallery: _toggleScopedGallery,
              toolbarConfig: toolbarConfig,
              onToggleShowHiddenFiles: (v) {
                _updateToolbarConfig((c) => c.copyWith(showHiddenFiles: v));
              },
              onToggleShowNoMediaFolders: (v) {
                _updateToolbarConfig((c) => c.copyWith(showNoMediaFolders: v));
              },
              onToggleShowGridFileNames: (v) {
                _updateToolbarConfig((c) => c.copyWith(showGridFileNames: v));
              },
              onToggleShowFileExtensions: (v) {
                _updateToolbarConfig((c) => c.copyWith(showFileExtensions: v));
              },
              onToggleShowListThumbnails: (v) {
                _updateToolbarConfig((c) => c.copyWith(showListThumbnails: v));
              },
              onOpenSettings: _openFileManagerSettings,
              onPickGalleryFolders: _scoped && _isGallery
                  ? _pickGalleryFolders
                  : null,
              galleryFolderCount: _galleryRoots.length,
            );

    // 1. Regular AppBar
    PreferredSizeWidget regularAppBarFactory(BuildContext context) {
      if (_deactivated || _disposed) {
        return const PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight),
          child: SizedBox.shrink(),
        );
      }
      final appBarTheme = Theme.of(context).appBarTheme;
      final cs = Theme.of(context).colorScheme;
      final l10n = context.l10n;
      final titleStyle =
          Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ) ??
          const TextStyle(fontWeight: FontWeight.bold);
      final pathStack = _buildPathStack(location, l10n);

      final dockedSidebar = DockedSidebarScope.of(context);
      final titleBarOwnsMenu = context.titleBarHostsSidebarMenu;
      final hideLeadingMenu = dockedSidebar || titleBarOwnsMenu;
      // A hidden docked sidebar comes back in place, since the browser has no
      // modal drawer of its own then.
      final showSidebar = context.showSidebarAction;
      final overflowModel = moreMenuModel(visibleActions);
      // An AppBar lays its actions out with unbounded width, so the bar is
      // measured and the actions that do not fit collapse into a "more" menu
      // instead of overlapping the title when the window is resized.
      return WidthAwareAppBar(
        builder: (context, barWidth) => AppBar(
        // Beside a docked sidebar or under a Windows title bar toggle there is
        // no drawer button to show here.
        leading: hideLeadingMenu
            ? null
            : Builder(
          builder: (ctx) {
            final fullScreenDrawer = FullScreenDragDrawerScope.maybeOf(ctx);
            final scaffold = Scaffold.maybeOf(ctx);
            return IconButton(
              icon: Icon(
                Icons.menu_rounded,
                color: appBarTheme.foregroundColor,
              ),
              tooltip: ctx.l10n.showSidebarTooltip,
              onPressed: () {
                if (showSidebar != null) {
                  showSidebar();
                } else if (fullScreenDrawer != null) {
                  fullScreenDrawer.openDrawer();
                } else {
                  scaffold?.openDrawer();
                }
              },
            );
          },
        ),
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final reservedSpace = 22.0 + 12.0;
                final availableWidth = (constraints.maxWidth - reservedSpace)
                    .clamp(60.0, 2000.0);
                final displayTitle = _buildLeftTruncatedPath(
                  widget.category.label(l10n),
                  pathStack,
                  availableWidth,
                  titleStyle,
                );
                return BackDismissibleMenuAnchor(
                  builder: (ctx, controller, child) => InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 22,
                            color: cs.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  menuChildren: [
                    for (int i = 0; i < pathStack.length; i++) ...[
                      (() {
                        final segment = pathStack[i];
                        final isCurrent = i == pathStack.length - 1;
                        final isRoot = i == 0;
                        final IconData icon = isRoot
                            ? (_scoped
                                  ? Icons.home_rounded
                                  : widget.category.icon)
                            : (i == 1 &&
                                      _snapshot.contributingSources.length > 1
                                  ? Icons.storage_rounded
                                  : Icons.folder_rounded);
                        final Color iconColor = isRoot
                            ? cs.primary
                            : cs.secondary;
                        return MenuItemButton(
                          onPressed: isCurrent ? null : () => _onJumpTo(i),
                          leadingIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (i > 0) SizedBox(width: (i - 1) * 12.0),
                              Icon(
                                icon,
                                size: 18,
                                color: isCurrent ? cs.primary : iconColor,
                              ),
                            ],
                          ),
                          child: Text(
                            segment.label,
                            style: TextStyle(
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrent ? cs.primary : cs.onSurface,
                            ),
                          ),
                        );
                      })(),
                    ],
                    for (int f = 0; f < _forwardStack.length; f++)
                      MenuItemButton(
                        onPressed: () => _onForwardTo(f),
                        leadingIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: (pathStack.length + f - 1) * 12.0),
                            Icon(
                              Icons.folder_rounded,
                              size: 18,
                              color: cs.onSurfaceVariant.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ],
                        ),
                        child: Text(
                          _forwardStack[f].label,
                          style: TextStyle(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (toolbarConfig.showStatsBar)
              Text(
                _scanning
                    ? l10n.categoryScanning(_snapshot.foldersChecked)
                    : _buildStatsSubtitle(items, mountedVaults, l10n),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
            AdaptiveActionStrip(
            availableWidth: appBarActionsBudget(
              barWidth: barWidth,
              hasLeading: !hideLeadingMenu,
            ),
            items: [
              AdaptiveActionItem(
                id: 'folder-structure',
                builder: (context) => IconButton(
                  icon: Icon(
                    _folderMode
                        ? Icons.folder_copy_rounded
                        : Icons.folder_copy_outlined,
                    color: _folderMode
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: l10n.categoryFolderStructure,
                  onPressed: () => _setFolderMode(!_folderMode),
                ),
                menuBuilder: (context) => MenuItemButton(
                  leadingIcon: Icon(
                    _folderMode
                        ? Icons.folder_copy_rounded
                        : Icons.folder_copy_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () => _setFolderMode(!_folderMode),
                  child: Text(l10n.categoryFolderStructure),
                ),
                priority: 2,
              ),
              if (_scoped && _isGallery)
                AdaptiveActionItem(
                  id: 'gallery-folders',
                  builder: (context) => IconButton(
                    icon: Badge(
                      isLabelVisible: _galleryRoots.isNotEmpty,
                      label: Text('${_galleryRoots.length}'),
                      child: const Icon(Icons.folder_outlined),
                    ),
                    tooltip: l10n.galleryFoldersMenu,
                    onPressed: _pickGalleryFolders,
                  ),
                  menuBuilder: (context) => MenuItemButton(
                    leadingIcon: Icon(
                      Icons.folder_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: _pickGalleryFolders,
                    child: Text(l10n.galleryFoldersMenu),
                  ),
                  priority: 2,
                ),
              if (isLandscape && showActionBar)
                for (final a in visibleActions)
                  AdaptiveActionItem(
                    id: a,
                    builder: actionBuilders[a]!,
                    // Search stays inline; add has no menu form.
                    menuBuilder:
                        a == FileManagerAction.add ||
                            a == FileManagerAction.search
                        ? null
                        : (context) => overflowModel.menuEntryFor(context, a),
                    priority: 1,
                  ),
            ],
          ),
        ],
      ),
      );
    }

    // 2. Selection AppBar
    PreferredSizeWidget selectionAppBarFactory(BuildContext context) {
      if (_deactivated || _disposed) {
        return const PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight),
          child: SizedBox.shrink(),
        );
      }
      final l10n = context.l10n;
      final selectedList = selection.items.whereType<CategoryEntry>().toList();
      final single = selectedList.length == 1 ? selectedList.single : null;
      final firstSelected = selectedList.isEmpty ? null : selectedList.first;
      final realSelected = selectedList
          .where((entry) => !entry.isSourceRoot)
          .toList(growable: false);
      final selectedGroups = _bySource(realSelected);
      final oneSource = selectedGroups.length == 1;
      final selectedContainer = oneSource
          ? _containers[selectedGroups.keys.single]
          : null;
      final renameContainer = firstSelected == null
          ? null
          : _containers[firstSelected.sourceVolId];
      final canRenameSelection =
          firstSelected != null &&
          !firstSelected.isDir &&
          !firstSelected.isSourceRoot &&
          renameContainer != null &&
          !renameContainer.readOnly &&
          selectedList.every(
            (entry) =>
                !entry.isDir &&
                !entry.isSourceRoot &&
                entry.sourceVolId == firstSelected.sourceVolId &&
                entry.parentPath == firstSelected.parentPath,
          );
      final canCompressSelection =
          realSelected.isNotEmpty &&
          oneSource &&
          selectedContainer != null &&
          !selectedContainer.readOnly;
      final canExportSelection =
          realSelected.isNotEmpty &&
          oneSource &&
          selectedContainer != null &&
          !selectedContainer.isLocalStorage;
      final shareableSelection = realSelected
          .where((entry) => entry.isDir || !isVaultItemFileName(entry.baseName))
          .toList(growable: false);
      final shareGroups = _bySource(shareableSelection);
      final canShareSelection =
          shareableSelection.isNotEmpty && shareGroups.length == 1;
      bool isPinned(CategoryEntry entry) =>
          marksBySource[entry.sourceVolId]?.pinnedPaths.contains(entry.path) ??
          false;
      bool isBookmarked(CategoryEntry entry) =>
          marksBySource[entry.sourceVolId]?.isBookmarked(entry.path) ?? false;
      final showPin = realSelected.any((entry) => !isPinned(entry));
      final showUnpin = realSelected.any(isPinned);
      final showBookmark = realSelected.any((entry) => !isBookmarked(entry));
      final showUnbookmark = realSelected.any(isBookmarked);
      final showEncrypt = realSelected.any(
        (entry) => !entry.isDir && !isAppEncryptedFileName(entry.baseName),
      );
      final showDecrypt = realSelected.any(
        (entry) => !entry.isDir && isAppEncryptedFileName(entry.baseName),
      );
      final hasReadOnlySource = selectedList.any(
        (entry) => _containers[entry.sourceVolId]?.readOnly ?? true,
      );

      return SelectionAppBar(
        selectedCount: selectedList.length,
        selectionLabel: l10n.selectionBarSelectedCount(selectedList.length),
        singleSelected: selectedList.length == 1,
        singleFileSelected: single != null && !single.isDir,
        singleFolderSelected: single != null && single.isDir,
        onClose: _clearSelection,
        onSelectAll: _selectAll,
        onRename: () => unawaited(_rename(selectedList)),
        allowRenameAction: canRenameSelection,
        onCopy: () => _stage(selectedList, cut: false),
        onCut: () => _stage(selectedList, cut: true),
        onDelete: () => _delete(selectedList),
        onShare: () => _share(selectedList),
        showShareOption: canShareSelection,
        hideVaultOnlyActions: selectedContainer?.isLocalStorage ?? true,
        readOnly: hasReadOnlySource,
        onFileInfo: () {
          if (single != null) _showFileInfo(single);
        },
        onEditMetadata: selectedList.every((e) => !e.isDir)
            ? () => _editMetadata(selectedList)
            : null,
        onOpenWithApp: () {
          if (single != null) {
            final c = _containers[single.sourceVolId];
            if (c != null) unawaited(_openWithApp(c, single));
          }
        },
        onGoToLocation: widget.onShowInFolder != null && single != null
            ? () => _showInFolder(single)
            : null,
        onCopyPath: single != null ? () => _copyPath(single) : null,
        onExport: () => _exportSelection(selectedList),
        allowExportAction: canExportSelection,
        allowExtractAction: false,
        onCompressSelection: () => unawaited(_compressSelection(selectedList)),
        allowCompressAction: canCompressSelection,
        onExtractSelectedArchive: () {},
        showPinOption: showPin,
        showUnpinOption: showUnpin,
        onPin: () => unawaited(
          _toggleSelectedMarks(selectedList, pin: true, enabled: true),
        ),
        onUnpin: () => unawaited(
          _toggleSelectedMarks(selectedList, pin: true, enabled: false),
        ),
        showBookmarkOption: showBookmark,
        showUnbookmarkOption: showUnbookmark,
        onBookmark: () => unawaited(
          _toggleSelectedMarks(selectedList, pin: false, enabled: true),
        ),
        onUnbookmark: () => unawaited(
          _toggleSelectedMarks(selectedList, pin: false, enabled: false),
        ),
        showEncryptOption: showEncrypt,
        showDecryptOption: showDecrypt,
        onEncrypt: () => unawaited(
          _runCategoryCrypto(selectedList, CryptoDirection.encrypt),
        ),
        onDecrypt: () => unawaited(
          _runCategoryCrypto(selectedList, CryptoDirection.decrypt),
        ),
        showEditImageOption:
            single != null &&
            !single.isDir &&
            MediaViewerConstants.isImage(single.baseName) &&
            !(_containers[single.sourceVolId]?.readOnly ?? true),
        onEditImage: () {
          if (single != null) unawaited(_editImage(single));
        },
        showEditVideoOption: false,
        onEditVideo: () {},
        itemActionOrder: toolbarConfig.itemActionsOrder,
        quickItemActions: toolbarConfig.quickItemActions,
        hiddenItemActions: toolbarConfig.hiddenItemActions,
      );
    }

    // Publish chrome to hub
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chrome.setAppBar(widget.tabId, regularAppBarFactory);
      _chrome.setSelectionAppBar(
        widget.tabId,
        isSelecting && !toolbarConfig.bottomSelectionBar
            ? selectionAppBarFactory
            : null,
      );

      // SelectionAppBar is an AppBar, which fills whatever height it is
      // given and pads for the status bar. In the shell's bottom slot that
      // made it span the screen, so it is fitted to one toolbar height here,
      // as the file manager does, and lifted by the keyboard's inset.
      final bottomBarWidget = isSelecting && toolbarConfig.bottomSelectionBar
          ? Builder(
              builder: (slotContext) => Padding(
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
                        child: selectionAppBarFactory(slotContext),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : (!isLandscape && showActionBar
                ? FileManagerActionBar(
                    axis: Axis.horizontal,
                    actions: visibleActions,
                    builders: actionBuilders,
                  )
                : null);
      // A stable slot, not the freshly built bar: see [ChromeBarSlot].
      _chrome.setBottomBar(
        widget.tabId,
        _bottomBarSlot.publish(bottomBarWidget),
      );

      final showFloatingAction =
          useFab && !_searchActive && visibleActions.isNotEmpty;
      final floatingWidget = showFloatingAction
          ? moreMenuModel(visibleActions)
          : null;
      _chrome.setFloatingAction(widget.tabId, floatingWidget);
    });

    // Only the focused tab has a say in back. Hidden tabs stay mounted (and so
    // keep their PopScope registered with the route), so a background gallery
    // tab with a scoped gallery open must not veto the system back, or the
    // shell's "press back again to exit" can never actually exit. Watched, so
    // the PopScope updates when this tab gains or loses focus.
    final isActiveTabForBack = ref.watch(
      activeBrowserTabProvider(
        widget.workspaceConfig,
      ).select((tab) => tab?.tabId == widget.tabId),
    );
    // Mask mode (app root): at the root of a scoped gallery the first back
    // arms the exit, and the second must be handed to the system. Nothing
    // lies beneath this route, so Navigator.pop() is a no-op there and the
    // app would never leave.
    final bool galleryRootMayLeave =
        _scoped &&
        _isGallery &&
        _exitArmed &&
        _resolveScopedGalleryRootBack() == BrowserBackAction.leave;
    final canPop =
        !isActiveTabForBack ||
        (!isSelecting &&
            !_searchActive &&
            !_canGoUp &&
            (!_scoped || galleryRootMayLeave));

    // On desktop the shell shows no app bar slot (the file manager's toolbar
    // lives inside its folder view), so a scoped category such as gallery mode
    // draws its own toolbar. Without it there was no button to leave gallery
    // mode again.
    final PreferredSizeWidget? inlineToolbar =
        _scoped && PlatformFeatures.isDesktop
        ? (isSelecting && !toolbarConfig.bottomSelectionBar
              ? selectionAppBarFactory(context)
              : regularAppBarFactory(context))
        : null;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_isActiveTab) return;
        // A menu is open: this press closes it (BackDismissibleMenuAnchor).
        if (OpenMenuBackGuard.hasOpenMenu) return;
        if (OpenDrawerBackGuard.hasOpenDrawer) return;
        if (isSelecting) {
          _clearSelection();
        } else if (_searchActive) {
          _toggleSearch();
        } else if (_canGoUp) {
          _goUp();
        } else if (_scoped && _isGallery) {
          _handleScopedGalleryBackAtRoot();
        } else if (_scoped && !_isGallery) {
          _exitScopedCategory();
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                if (inlineToolbar != null)
                  MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: SizedBox(
                      height: inlineToolbar.preferredSize.height,
                      child: inlineToolbar,
                    ),
                  ),
                if (_scanning) const LinearProgressIndicator(minHeight: 2),
                if (_snapshot.limitReached && !_scanning)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        l10n.categoryScanLimitReached,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: AutoHideScrollHost(
                    enabled: toolbarConfig.autoHideBreadcrumbBar,
                    resetKey: location,
                    bar:
                        (toolbarConfig.showBreadcrumbBar &&
                            (_folderMode || _scoped))
                        ? BreadcrumbBar(
                            stack: _buildPathStack(location, l10n),
                            onTap: _onJumpTo,
                            forwardStack: _forwardStack,
                            onForwardTap: _onForwardTo,
                            // The first step already carries the category's
                            // (or the scoped storage's) name.
                            rootLabel: _buildPathStack(location, l10n)
                                .first
                                .label,
                            rootIcon: _scoped
                                ? breadcrumbRootIconFor(widget.scopedContainer!)
                                : widget.category.icon,
                          )
                        : null,
                    child: Column(
                      children: [
                        if (_isGallery && !_folderMode)
                          GalleryFilterBar(
                            controller: _galleryFilter,
                            index: _meta,
                            shown: items.length,
                            total: _itemsUnfilteredCount,
                            onOpen: _openGalleryFilter,
                          ),
                        Expanded(
                          child: _buildBody(
                            items,
                            toolbarConfig,
                            mountedVaults,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Same docked search bar as the file manager's folder view.
          if (_searchActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: BottomSearchBar(
                    initialQuery: _query,
                    hintText: l10n.search,
                    onChanged: (value) => setState(() => _query = value),
                    onClose: _toggleSearch,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool get _galleryStoredDateIndexReady {
    if (!_isGallery || _folderMode || !_galleryFilter.groupBy.isDate) {
      return true;
    }
    final sourceIds = {
      for (final entry in _snapshot.entries) entry.sourceVolId,
    };
    return _metaStoredLoadedSources.containsAll(sourceIds);
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

    if (!_galleryStoredDateIndexReady) {
      return const Center(child: CircularProgressIndicator());
    }

    final anyContainer =
        _containers[items.first.sourceVolId] ?? _containers.values.first;
    final scoped = widget.scopedContainer;
    final fallbackThumb = scoped != null
        ? _thumbs[scoped.volId]
        : _thumbs.values.firstWhere((t) => t != null, orElse: () => null);
    final effectiveThumbnailQuality =
        fallbackThumb?.quality ?? ThumbnailQuality.defaultAutoQuality;
    final effectiveThumbnailCacheMode =
        fallbackThumb?.cacheMode ?? ThumbnailCacheMode.appCache;
    final location = _effectiveLocation;
    // Flat scoped categories still display names relative to the folder the
    // filter was opened in. Keep that folder as the base path for thumbnail
    // lookup so `currentDirPath + entry.name` resolves to the source path.
    final currentDirPath = !location.isTop ? location.dirPath : '';
    final landscape =
        context.screen.useLandscapeLayout;
    final query = _searchActive && _query.trim().isNotEmpty
        ? _query.trim().toLowerCase()
        : null;
    // The docked search bar floats over the results, so they have to clear it
    // and the keyboard it rides on, as in the file manager.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final systemInset = MediaQuery.viewPaddingOf(context).bottom;
    final searchClearance = _searchActive
        ? 64.0 + (keyboardInset > systemInset ? keyboardInset : systemInset)
        : 0.0;
    final selection = ref.watch(fileBrowserSelectionProvider(widget.tabId));

    void onMoreTap(RawEntry e) {
      if (e is CategoryEntry) _showItemMenu(e);
    }

    void onSelectionChanged(Set<RawEntry> set) => ref
        .read(fileBrowserSelectionProvider(widget.tabId).notifier)
        .setSelectedItems(_filesOnly(set));

    // Drag-and-drop: allow outbound OS drag on desktop even when read-only;
    // in-app folder drop targets reject read-only destinations cleanly.
    final enableDrag =
        PlatformFeatures.isDesktop ||
        _containers.values.any((c) => !c.readOnly);

    Future<void> onFileDrop(
      BrowserItemDragData data,
      MountedContainer destination,
      String destinationPath,
      BrowserDropMode mode,
    ) async {
      if (!mounted || data.entries.isEmpty) return;
      final isMove = mode == BrowserDropMode.move;
      if (destination.readOnly || (isMove && data.source.readOnly)) {
        _notify(
          isMove
              ? context.l10n.readOnlyCantMove
              : context.l10n.readOnlyCantPaste,
          error: true,
        );
        return;
      }
      final allowed = isMove
          ? data.canMoveInto(destination, destinationPath)
          : data.canCopyInto(destination, destinationPath);
      if (!allowed) return;

      final dropItems = data.entries
          .map(
            (entry) => ClipboardItem(
              path: data.pathFor(entry),
              isDir: entry.isDir,
              sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
              modifiedSecs: entry.modifiedSecs,
            ),
          )
          .toList(growable: false);

      final op = await ref
          .read(fileBrowserOperationsControllerProvider)
          .pasteStandardTransfer(
            destContainer: destination,
            srcContainer: data.source,
            destDirPath: destinationPath,
            items: dropItems,
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
      _clearSelection();
      if (mounted) unawaited(_startScan(deep: true));
    }

    final Widget content;
    switch (_layout) {
      case BrowserLayoutMode.grid:
        content = FileGridView(
          key: _gridKey,
          scrollController: _scrollController,
          container: anyContainer,
          containerFor: (e) => _containerOfEntry(e) ?? anyContainer,
          folderPreviewPaths: _folderCoverPaths,
          cacheModeFor: _cacheModeOf,
          qualityFor: _qualityOf,
          items: items,
          isSelectionMode: selection.items.isNotEmpty,
          selectedItems: selection.items,
          currentDirPath: currentDirPath,
          thumbnailCacheMode: effectiveThumbnailCacheMode,
          thumbnailQuality: effectiveThumbnailQuality,
          showFileNames: toolbarConfig.showGridFileNames,
          showFileExtensions: toolbarConfig.showFileExtensions,
          cornerRadius: toolbarConfig.gridCornerStyle.radius,
          spacing: toolbarConfig.gridSpacing.toDouble(),
          longFileNameMode: toolbarConfig.longFileNameDisplayMode,
          gridAspectRatio: toolbarConfig.gridAspectRatio,
          initialColumns: landscape
              ? toolbarConfig.gridColumnsLandscape
              : toolbarConfig.gridColumnsPortrait,
          onColumnCountChanged: (count) {
            _updateToolbarConfig(
              (c) => landscape
                  ? c.copyWith(gridColumnsLandscape: count)
                  : c.copyWith(gridColumnsPortrait: count),
            );
          },
          onDirTap: _onDirTap,
          onFileTap: _onFileTap,
          onItemLongPress: _onItemLongPress,
          onFileLongMenu: onMoreTap,
          showItemActionsMenu: toolbarConfig.showItemActionsMenu,
          onSelectionChanged: onSelectionChanged,
          enableFileDrag: enableDrag,
          onFileDrop: onFileDrop,
          searchQuery: query,
          bottomClearance: searchClearance,
          sortBy: _sortBy,
          anchorOnItemsChange: _isGallery && !_folderMode,
          groupByDate:
              _isGallery &&
              !_folderMode &&
              _galleryFilter.groupBy != GalleryGroupBy.none,
          groupBuilder: _isGallery && !_folderMode
              ? (entries) => identical(entries, _items) && _itemsGroups != null
                    ? _itemsGroups!
                    : _galleryGrouper(_galleryFilter.groupBy).call(entries)
              : null,
        );
      case BrowserLayoutMode.masonry:
        content = FileMasonryView(
          key: _masonryKey,
          scrollController: _scrollController,
          container: anyContainer,
          containerFor: (e) => _containerOfEntry(e) ?? anyContainer,
          folderPreviewPaths: _folderCoverPaths,
          cacheModeFor: _cacheModeOf,
          qualityFor: _qualityOf,
          items: items,
          isSelectionMode: selection.items.isNotEmpty,
          selectedItems: selection.items,
          currentDirPath: currentDirPath,
          thumbnailCacheMode: effectiveThumbnailCacheMode,
          thumbnailQuality: effectiveThumbnailQuality,
          showFileNames: toolbarConfig.showGridFileNames,
          showFileExtensions: toolbarConfig.showFileExtensions,
          cornerRadius: toolbarConfig.gridCornerStyle.radius,
          spacing: toolbarConfig.gridSpacing.toDouble(),
          longFileNameMode: toolbarConfig.longFileNameDisplayMode,
          initialColumns: landscape
              ? toolbarConfig.masonryColumnsLandscape
              : toolbarConfig.masonryColumnsPortrait,
          onColumnCountChanged: (count) {
            _updateToolbarConfig(
              (c) => landscape
                  ? c.copyWith(masonryColumnsLandscape: count)
                  : c.copyWith(masonryColumnsPortrait: count),
            );
          },
          onDirTap: _onDirTap,
          onFileTap: _onFileTap,
          onItemLongPress: _onItemLongPress,
          onFileLongMenu: onMoreTap,
          showItemActionsMenu: toolbarConfig.showItemActionsMenu,
          onSelectionChanged: onSelectionChanged,
          enableFileDrag: enableDrag,
          onFileDrop: onFileDrop,
          searchQuery: query,
          bottomClearance: searchClearance,
          sortBy: _sortBy,
          anchorOnItemsChange: _isGallery && !_folderMode,
          groupByDate:
              _isGallery &&
              !_folderMode &&
              _galleryFilter.groupBy != GalleryGroupBy.none,
          groupBuilder: _isGallery && !_folderMode
              ? (entries) => identical(entries, _items) && _itemsGroups != null
                    ? _itemsGroups!
                    : _galleryGrouper(_galleryFilter.groupBy).call(entries)
              : null,
        );
      case BrowserLayoutMode.list:
      case BrowserLayoutMode.detailed:
      case BrowserLayoutMode.compact:
        content = FileListView(
          key: _listKey,
          scrollController: _scrollController,
          container: anyContainer,
          containerFor: (e) => _containerOfEntry(e) ?? anyContainer,
          folderPreviewPaths: _folderCoverPaths,
          cacheModeFor: _cacheModeOf,
          qualityFor: _qualityOf,
          currentDirPath: currentDirPath,
          thumbnailCacheMode: effectiveThumbnailCacheMode,
          thumbnailQuality: effectiveThumbnailQuality,
          showThumbnails: toolbarConfig.showListThumbnails,
          initialZoomLevel: toolbarConfig.listZoomLevel,
          onZoomLevelChanged: (zoom) {
            _updateToolbarConfig((c) => c.copyWith(listZoomLevel: zoom));
          },
          items: items,
          isSelectionMode: selection.items.isNotEmpty,
          isCompact: _layout == BrowserLayoutMode.compact,
          isDetailed: _layout == BrowserLayoutMode.detailed,
          selectedItems: selection.items,
          detailColumns: toolbarConfig.visibleDetailColumns,
          longFileNameMode: toolbarConfig.longFileNameDisplayMode,
          showItemActionsMenu: toolbarConfig.showItemActionsMenu,
          showFileExtensions: toolbarConfig.showFileExtensions,
          onDirTap: _onDirTap,
          onFileTap: _onFileTap,
          onItemLongPress: _onItemLongPress,
          onFileLongMenu: onMoreTap,
          onSelectionChanged: onSelectionChanged,
          enableFileDrag: enableDrag,
          onFileDrop: onFileDrop,
          searchQuery: query,
          bottomClearance: searchClearance,
          sortBy: _sortBy,
          anchorOnItemsChange: _isGallery && !_folderMode,
          groupByDate:
              _isGallery &&
              !_folderMode &&
              _galleryFilter.groupBy != GalleryGroupBy.none,
          groupBuilder: _isGallery && !_folderMode
              ? (entries) => identical(entries, _items) && _itemsGroups != null
                    ? _itemsGroups!
                    : _galleryGrouper(_galleryFilter.groupBy).call(entries)
              : null,
          largeThumbnail: _isGallery,
        );
    }
    return RefreshIndicator(
      onRefresh: () => _startScan(deep: true),
      child: content,
    );
  }
}
