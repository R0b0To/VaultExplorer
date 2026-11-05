import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart'
    show namesAreCaseSensitive;
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
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
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/thumbnail_settings_resolver.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_chrome_hub.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart'
    show PathSegment;
import 'package:vaultexplorer/features/browser/controllers/file_browser_operations_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/file_open_dispatch.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/models/browser_back_policy.dart';
import 'package:vaultexplorer/features/browser/models/category_index.dart';
import 'package:vaultexplorer/features/browser/models/category_source.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/browser/models/file_category_presentation.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/services/category_aggregate_scan.dart';
import 'package:vaultexplorer/features/browser/services/category_listing.dart';
import 'package:vaultexplorer/features/browser/services/vault_category_index_io.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/pdf_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/bottom_search_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drag.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
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
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart'
    show kVaultMetaDir;

typedef CategoryShowInFolderCallback = void Function(
  MountedContainer container,
  String path,
);

class _CategorySourceBundle {
  _CategorySourceBundle(this.container, this.source);

  final MountedContainer container;
  final CategorySource source;
}

class _CategoryPathStep {
  const _CategoryPathStep({
    required this.segment,
    required this.location,
  });

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
  List<PathSegment> _forwardStack = const [];
  List<CategoryLocation> _forwardLocations = const [];
  CategoryAggregateSnapshot _snapshot = CategoryAggregateSnapshot.empty;
  Map<int, MountedContainer> _containers = const {};
  Map<int, CategorySource> _sources = const {};
  Map<int, ThumbnailSettings?> _thumbs = const {};
  CancellationToken? _token;
  bool _scanning = true;
  bool _disposed = false;
  bool _exitArmed = false;
  Timer? _exitArmTimer;

  bool _searchActive = false;
  String _query = '';
  final ScrollController _scrollController = ScrollController();

  List<CategoryEntry> _items = const [];
  CategoryAggregateSnapshot? _itemsSnapshot;
  bool? _itemsFolderMode;
  CategoryLocation? _itemsLocation;
  String? _itemsQuery;
  SortBy? _itemsSortBy;
  bool? _itemsSortAscending;

  late final BrowserChromeHub _chrome = ref.read(
    browserChromeProvider(widget.workspaceConfig),
  );

  String get _categoryKey => widget.category.storageKey;
  bool get _scoped => widget.scopedContainer != null;
  bool get _isGallery => widget.category == FileCategory.gallery;
  bool get _usesVaults =>
      _scoped ? !widget.scopedContainer!.isLocalStorage : widget.includeVaults;

  bool get _isActiveTab {
    final active = ref.read(activeBrowserTabProvider(widget.workspaceConfig));
    return active?.tabId == widget.tabId;
  }

  @override
  void initState() {
    super.initState();
    if (widget.scopedContainer != null) {
      _containers = {widget.scopedContainer!.volId: widget.scopedContainer!};
      final initialDir = widget.initialDirPath ?? '';
      // A scoped gallery keeps the folder it was opened from as its album
      // root; the category scan may cover the whole container, but the listing
      // is limited to this location.
      _location = CategoryLocation(widget.scopedContainer!.volId, initialDir);
      _folderMode = !_isGallery;
    } else {
      _location = CategoryLocation.top;
      final settings = ref.read(appSettingsControllerProvider).settings;
      _folderMode = !_isGallery &&
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
    _layout = visual ? BrowserLayoutMode.grid : BrowserLayoutMode.list;
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startScan());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    _exitArmTimer?.cancel();
    _events?.removeContainerLockedListener(_onVaultLocked);
    _scrollController.dispose();
    super.dispose();
  }

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
            label: isDevice ? l10n.localStorageCardTitle : scoped.displayName,
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

  static bool _skipPrivateAndroidFolders(String dirPath) =>
      dirPath == 'Android/data' || dirPath == 'Android/obb';

  static bool _skipVaultMetaFolder(String dirPath) => dirPath == kVaultMetaDir;

  Future<void> _startScan() async {
    _token?.cancel();
    final token = _token = CancellationToken();
    final showHidden = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config
        .showHiddenFiles;

    setState(() {
      _scanning = true;
      _snapshot = CategoryAggregateSnapshot.empty;
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
            _loadIndexSeed(api, b.container, showHidden).then((seed) {
              if (seed != null) seeds[b.source.volId] = seed;
            }),
      ]);
      if (_disposed || token.isCancelled) return;
    }

    final scanner = CategoryAggregateScanner(
      targets: [
        for (final b in bundles)
          CategoryScanTarget(
            source: b.source,
            listDirectory: (dir) => api.listDirectory(b.container, dir),
            skipDirectory: b.container.isRawLocal
                ? _skipPrivateAndroidFolders
                : b.source.isVault
                ? _skipVaultMetaFolder
                : null,
            seed: seeds[b.source.volId],
          ),
      ],
      matches: (name) => matchesFilter(name, widget.category.filterKey),
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
  }

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

  void _onVaultLocked(int volId) {
    if (_disposed) return;
    setState(() {
      _containers = Map.of(_containers)..remove(volId);
      _sources = Map.of(_sources)..remove(volId);
      _snapshot = _snapshot.withoutSource(volId);
      _forwardStack = const [];
      _forwardLocations = const [];
    });
  }

  void _onMountedVaultsChanged(
    List<MountedContainer>? previous,
    List<MountedContainer> next,
  ) {
    if (_disposed) return;
    final prevIds = {if (previous != null) for (final v in previous) v.volId};
    final nextIds = {for (final v in next) v.volId};
    if (nextIds.any((id) => !prevIds.contains(id))) {
      unawaited(_startScan());
    }
  }

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
        : flatCategoryListing(
            _snapshot,
            location: location,
            query: _query,
          );

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
      widget.onScopedFilterChanged?.call(
        'gallery',
        _effectiveLocation.dirPath,
      );
    }
  }

  void _handleScopedGalleryBackAtRoot() {
    final settings = ref.read(appSettingsControllerProvider).settings;
    final action = resolveBrowserBack(
      selectionMode: false,
      searchActive: false,
      atRoot: true,
      appRoot: widget.workspaceConfig.appRoot,
      hostsHome: widget.workspaceConfig.includeDashboardTab,
      tabsEnabled: settings.useBrowserTabs,
    );
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

    final followsForward = _forwardStack.isNotEmpty &&
        _forwardStack.first.fatPath == newFatPath;

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
      _forwardStack = [
        ...removedSteps.map((s) => s.segment),
        ..._forwardStack,
      ];
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
        await _openWithApp(container, entry, packageName: package);
      default:
        await _openWithApp(container, entry);
    }
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
          onFileDeleted: deleted.add,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (!mounted || deleted.isEmpty) return;
    setState(() {
      _snapshot = _snapshot.withoutPaths({
        for (final path in deleted) (entry.sourceVolId, path),
      });
    });
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
      onSuccess: () {
        if (!mounted) return;
        _clearSelection();
        unawaited(_startScan());
      },
    );
  }

  Future<void> _editImage(CategoryEntry entry) async {
    final container = _containers[entry.sourceVolId];
    if (container == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(
          container: container,
          filePath: entry.path,
        ),
      ),
    );
    if (!mounted) return;
    unawaited(_startScan());
  }

  void _showInFolder(CategoryEntry entry) {
    final container = _containers[entry.sourceVolId];
    final callback = widget.onShowInFolder;
    if (container == null || callback == null) return;
    _clearSelection();
    callback(container, entry.path);
  }

  void _showFileInfo(CategoryEntry entry) {
    final container = _containers[entry.sourceVolId];
    if (container == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FileInfoSheet(
        container: container,
        entry: entry,
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
    FileItemActionsSheet.show(
      context,
      entry: entry,
      container: container,
      currentDirPath: entry.parentPath,
      isReadOnly: container.readOnly,
      isPinned: false,
      isBookmark: false,
      thumbnailCacheMode:
          thumbSettings?.cacheMode ?? ThumbnailCacheMode.appCache,
      thumbnailQuality:
          thumbSettings?.quality ?? ThumbnailQuality.defaultAutoQuality,
      onRename: () => unawaited(_rename(entry)),
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
      onEditImage: (isImg && !container.readOnly) ? () => _editImage(entry) : null,
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

  /// Builds breadcrumb steps linking segments to locations.
  List<_CategoryPathStep> _buildPathSteps(CategoryLocation location) {
    final l10n = context.l10n;
    final topLocation = _snapshot.contributingSources.length == 1
        ? CategoryLocation(_snapshot.contributingSources.first, '')
        : CategoryLocation.top;

    final rootLabel = _scoped
        ? widget.scopedContainer!.displayName
        : widget.category.label(l10n);

    final steps = <_CategoryPathStep>[
      _CategoryPathStep(
        segment: PathSegment(rootLabel, ''),
        location: topLocation,
      ),
    ];
    if (location.volId == null) return steps;

    final multipleSources = _snapshot.contributingSources.length > 1;
    final source = _sources[location.volId];
    if (source != null && multipleSources) {
      steps.add(
        _CategoryPathStep(
          segment: PathSegment(source.label, source.label),
          location: CategoryLocation(location.volId, ''),
        ),
      );
    }

    if (location.dirPath.isNotEmpty) {
      final parts = location.dirPath.split('/');
      var accumulated = '';
      for (final part in parts) {
        accumulated = accumulated.isEmpty ? part : '$accumulated/$part';
        final fat = multipleSources && source != null
            ? '${source.label}/$accumulated'
            : accumulated;
        steps.add(
          _CategoryPathStep(
            segment: PathSegment(part, fat),
            location: CategoryLocation(location.volId, accumulated),
          ),
        );
      }
    }

    return steps;
  }

  List<PathSegment> _buildPathStack(CategoryLocation location) {
    return _buildPathSteps(location).map((s) => s.segment).toList();
  }

  String _buildLeftTruncatedPath(
    String rootName,
    List<PathSegment> stack,
    double maxWidth,
    TextStyle style,
  ) {
    if (stack.length == 1) return rootName;
    final allLabels = [rootName, ...stack.sublist(1).map((s) => s.label)];
    final fullPath = allLabels.join('/');
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    if (measure(fullPath) <= maxWidth) {
      return fullPath;
    }
    int low = 0;
    int high = fullPath.length - 1;
    int bestK = fullPath.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final candidate = '…${fullPath.substring(mid)}';
      if (measure(candidate) <= maxWidth) {
        bestK = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return '…${fullPath.substring(bestK)}';
  }

  String _buildStatsSubtitle(
    List<CategoryEntry> items,
    List<MountedContainer> mountedVaults,
  ) {
    final l10n = context.l10n;
    final sourceOrCategory =
        _scoped ? widget.category.label(l10n) : _sourceLabel(mountedVaults);
    if (_folderMode) {
      final dirCount = items.where((e) => e.isDir).length;
      final fileCount = items.where((e) => !e.isDir).length;
      final parts = <String>[];
      if (dirCount > 0) parts.add(l10n.statsFolderCount(dirCount));
      parts.add(l10n.statsFileCount(fileCount));
      parts.add(sourceOrCategory);
      return parts.join(' · ');
    }
    return '${l10n.statsFileCount(items.length)} · $sourceOrCategory';
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
    final selection = ref.watch(fileBrowserSelectionProvider(widget.tabId));
    final isSelecting = selection.items.isNotEmpty;
    final location = _effectiveLocation;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
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
        onLayoutModeChanged: (mode) => setState(() => _layout = mode),
        gridAspectRatio: toolbarConfig.gridAspectRatio,
        onGridAspectRatioChanged: (ratio) => _updateToolbarConfig(
          (c) => c.copyWith(gridAspectRatio: ratio),
        ),
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
      FileManagerAction.filter: (context) => _scoped
          ? FilterMenuButton(
              currentFilter: widget.category.filterKey,
              onFilterChanged: (filter) =>
                  widget.onScopedFilterChanged?.call(
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
          _startScan();
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
      ),
    };

    final visibleActions = toolbarConfig.visible.where((a) {
      if (_isGallery && a == FileManagerAction.filter) return false;
      return actionBuilders.containsKey(a);
    }).toList();

    // 1. Regular AppBar
    PreferredSizeWidget regularAppBarFactory(BuildContext context) {
      final appBarTheme = Theme.of(context).appBarTheme;
      final cs = Theme.of(context).colorScheme;
      final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ) ??
          const TextStyle(fontWeight: FontWeight.bold);
      final pathStack = _buildPathStack(location);

      return AppBar(
        leading: Builder(
          builder: (ctx) {
            final fullScreenDrawer = FullScreenDragDrawerScope.maybeOf(ctx);
            final scaffold = Scaffold.maybeOf(ctx);
            return IconButton(
              icon: Icon(Icons.menu_rounded, color: appBarTheme.foregroundColor),
              tooltip: ctx.l10n.storageLocationsTitle,
              onPressed: () {
                if (fullScreenDrawer != null) {
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
                final availableWidth =
                    (constraints.maxWidth - reservedSpace).clamp(
                  60.0,
                  2000.0,
                );
                final displayTitle = _buildLeftTruncatedPath(
                  widget.category.label(l10n),
                  pathStack,
                  availableWidth,
                  titleStyle,
                );
                return MenuAnchor(
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
                            SizedBox(
                              width: (pathStack.length + f - 1) * 12.0,
                            ),
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
                            color: cs.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
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
                    : _buildStatsSubtitle(items, mountedVaults),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _folderMode
                  ? Icons.folder_copy_rounded
                  : Icons.folder_copy_outlined,
              color: _folderMode ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: l10n.categoryFolderStructure,
            onPressed: () => _setFolderMode(!_folderMode),
          ),
          if (isLandscape && showActionBar)
            ...visibleActions.map((a) => actionBuilders[a]!(context)),
        ],
      );
    }

    // 2. Selection AppBar
    PreferredSizeWidget selectionAppBarFactory(BuildContext context) {
      final selectedList =
          selection.items.whereType<CategoryEntry>().toList();
      final single = selectedList.length == 1 ? selectedList.single : null;

      return SelectionAppBar(
        selectedCount: selectedList.length,
        selectionLabel: l10n.selectionBarSelectedCount(selectedList.length),
        singleSelected: selectedList.length == 1,
        singleFileSelected: single != null && !single.isDir,
        singleFolderSelected: single != null && single.isDir,
        onClose: _clearSelection,
        onSelectAll: _selectAll,
        onRename: () {
          if (single != null) unawaited(_rename(single));
        },
        allowRenameAction: single != null && !single.isSourceRoot,
        onCopy: () => _stage(selectedList, cut: false),
        onCut: () => _stage(selectedList, cut: true),
        onDelete: () => _delete(selectedList),
        onShare: () => _share(selectedList),
        showShareOption: true,
        onFileInfo: () {
          if (single != null) _showFileInfo(single);
        },
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
        onExport: () {},
        allowExportAction: false,
        allowExtractAction: false,
        onCompressSelection: () {},
        allowCompressAction: false,
        onExtractSelectedArchive: () {},
        showPinOption: false,
        showUnpinOption: false,
        onPin: () {},
        onUnpin: () {},
        showBookmarkOption: false,
        showUnbookmarkOption: false,
        onBookmark: () {},
        onUnbookmark: () {},
        showEncryptOption: false,
        showDecryptOption: false,
        onEncrypt: () {},
        onDecrypt: () {},
        showEditImageOption: single != null &&
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

      final bottomBarWidget = isSelecting && toolbarConfig.bottomSelectionBar
          ? Builder(builder: (c) => selectionAppBarFactory(c))
          : (!isLandscape && showActionBar
              ? FileManagerActionBar(
                  axis: Axis.horizontal,
                  actions: visibleActions,
                  builders: actionBuilders,
                )
              : null);
      _chrome.setBottomBar(widget.tabId, bottomBarWidget);

      final showFloatingAction =
          useFab && !_searchActive && visibleActions.isNotEmpty;
      final floatingWidget = showFloatingAction
          ? FileManagerMoreMenuButton(
              actions: visibleActions,
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
              layoutMode: _layout,
              onLayoutModeChanged: (mode) => setState(() => _layout = mode),
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
                _startScan();
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
            )
          : null;
      _chrome.setFloatingAction(widget.tabId, floatingWidget);
    });

    final canPop = !isSelecting && !_searchActive && !_canGoUp && !_scoped;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_isActiveTab) return;
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
          if (_scanning) const LinearProgressIndicator(minHeight: 2),
          if (_snapshot.limitReached && !_scanning)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  l10n.categoryScanLimitReached,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          if (toolbarConfig.showBreadcrumbBar && (_folderMode || _scoped))
            BreadcrumbBar(
              stack: _buildPathStack(location),
              onTap: _onJumpTo,
              forwardStack: _forwardStack,
              onForwardTap: _onForwardTo,
            ),
          Expanded(child: _buildBody(items, toolbarConfig, mountedVaults)),
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

  void _updateToolbarConfig(
    FileManagerToolbarConfig Function(FileManagerToolbarConfig) update,
  ) {
    final current = ref.read(fileManagerToolbarSettingsProvider(null)).config;
    final updated = update(current);
    ref.read(fileManagerToolbarServiceProvider).save(updated);
    ref
        .read(fileManagerToolbarSettingsProvider(null).notifier)
        .applyImportedConfig(updated);
  }

  Future<void> _openFileManagerSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SkinAreaScope(
          area: SkinArea.settings,
          child: FileManagerToolbarSettingsScreen(),
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
        onRefresh: _startScan,
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
        MediaQuery.orientationOf(context) == Orientation.landscape;
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

    // Drag-and-drop: enable drag unless all containers are read-only.
    final enableDrag =
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
          isMove ? context.l10n.readOnlyCantMove : context.l10n.readOnlyCantPaste,
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
      if (mounted) unawaited(_startScan());
    }

    final Widget content;
    switch (_layout) {
      case BrowserLayoutMode.grid:
        content = FileGridView(
          scrollController: _scrollController,
          container: anyContainer,
          containerFor: (e) => _containerOfEntry(e) ?? anyContainer,
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
          groupByDate: _isGallery && !_folderMode,
        );
      case BrowserLayoutMode.masonry:
        content = FileMasonryView(
          scrollController: _scrollController,
          container: anyContainer,
          containerFor: (e) => _containerOfEntry(e) ?? anyContainer,
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
          groupByDate: _isGallery && !_folderMode,
        );
      case BrowserLayoutMode.list:
      case BrowserLayoutMode.detailed:
      case BrowserLayoutMode.compact:
        content = FileListView(
          scrollController: _scrollController,
          container: anyContainer,
          containerFor: (e) => _containerOfEntry(e) ?? anyContainer,
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
          groupByDate: _isGallery && !_folderMode,
          largeThumbnail: _isGallery,
        );
    }
    return RefreshIndicator(onRefresh: _startScan, child: content);
  }
}
