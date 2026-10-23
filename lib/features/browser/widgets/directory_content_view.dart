import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/core/theme/app_skin_tokens.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/activity/clipboard_fab.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/grid_aspect_ratio.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/vault_delete_after_import_mode.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/thumbnail_settings_resolver.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';
import 'package:vaultexplorer/features/browser/archive_file_viewer.dart';
import 'package:vaultexplorer/features/browser/archive_preview_file.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_chrome_hub.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/models/browser_back_policy.dart';
import 'package:vaultexplorer/features/browser/models/browser_tab_origin.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_operations_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_pins_bookmarks_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_search_controller.dart';
import 'package:vaultexplorer/features/browser/widgets/archive_paste_options_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/file_browser_doc_provider_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_sort_controller.dart';
import 'package:vaultexplorer/features/browser/file_browser_listing.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/file_open_dispatch.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/services/folder_document_provider_service.dart';
import 'package:vaultexplorer/features/browser/services/media_scan_service.dart';
import 'package:vaultexplorer/features/browser/viewer/html_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/pdf_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_screen.dart';
import 'package:vaultexplorer/features/browser/widgets/add_item_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/file_manager_more_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/bookmark_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/bottom_search_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_app_bar_builder.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_app_bar_factory.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_body_builder.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/delete_originals_dialog.dart';
import 'package:vaultexplorer/features/browser/widgets/file_item_actions_sheet.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/file_manager_action_bar.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/widgets/filter_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_document_provider_sheet.dart';
import 'package:vaultexplorer/features/sync/services/sync_providers.dart';
import 'package:vaultexplorer/features/sync/services/sync_status.dart';
import 'package:vaultexplorer/features/sync/ui/sync_status_banner.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_thumbnail_preview.dart';
import 'package:vaultexplorer/features/browser/widgets/layout_mode_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/open_with_dialog.dart';
import 'package:vaultexplorer/features/browser/widgets/sort_menu_button.dart';
import 'package:vaultexplorer/features/camera/audio_capture_screen.dart';
import 'package:vaultexplorer/features/camera/camera_capture_screen.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_screen.dart';
import 'package:vaultexplorer/features/video_editor/video_editor_screen.dart';
import 'package:vaultexplorer/features/audio_editor/audio_editor_screen.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/features/sync/ui/sync_rule_editor_sheet.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/single_file_crypto_sheet.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_detail_screen.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_edit_screen.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';

// PathSegment used to be declared in this file; it now lives in the
// navigation controller (see FileBrowserNavigation). Re-exported from here
// rather than updating every other file that imports PathSegment via this
// file (breadcrumb_bar.dart, browser_app_bar_builder.dart,
// vault_browser_sheet.dart, and the decoy/local file explorer's own
// screens/controllers, which reuse the same type) -- keeps this a pure
// relocation with zero blast radius on unrelated files.
export 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart'
    show PathSegment;

// The recursive "play media here" scan (previously
// _scanMediaRecursively/_ScanSemaphore/the _maxScan* constants, all
// private to this file) now lives in MediaScanService
// (services/media_scan_service.dart) -- extracted so it's exercisable
// without a widget tree and so it can share BoundedSemaphore
// (core/utils/bounded_semaphore.dart) instead of duplicating it. This
// screen only keeps the thin "kick off a scan, show progress/cancel"
// glue -- see _startMediaViewerFromCurrentLocation and _cancelMediaScan
// below. FileBrowserSearch's own deep-search scan
// (file_browser_search_controller.dart) still keeps its own separate
// depth-guard constant; that one wasn't part of this pass.

double _fadeScrimOpacity(double progress) {
  const start = 0.08;
  const midpoint = 0.18;
  const end = 0.30;

  if (progress < start) {
    return 0.0;
  } else if (progress <= midpoint) {
    return ((progress - start) / (midpoint - start)).clamp(0.0, 1.0);
  } else if (progress < end) {
    return ((end - progress) / (end - midpoint)).clamp(0.0, 1.0);
  }
  return 0.0;
}

typedef _SelectedBrowserEntry = ({
  TabId stateKey,
  MountedContainer container,
  String currentDirPath,
  RawEntry entry,
  bool insideArchive,
});

typedef _BrowserAppBarBuilder =
    PreferredSizeWidget Function(
      BuildContext context, {
      required bool selectionMode,
    });

/// Stateful directory viewport. It owns only location-specific content and
/// delegates app bar, tab strip, FAB, and bottom chrome to its host.
class DirectoryContentView extends ConsumerStatefulWidget {
  final MountedContainer container;
  final MountedContainer? Function(int volId)? resolveContainer;
  final ThumbnailCacheMode? thumbnailCacheMode;
  final ThumbnailQuality? thumbnailQuality;
  final VoidCallback? onUserActivity;

  /// Passed straight through to [buildBrowserAppBar] -- see its doc
  /// comments. Both default to the screen's normal, always-pushed-from-
  /// the-dashboard behavior; decoy mode is the only caller that overrides
  /// them, since it embeds this screen with no dashboard route beneath it.
  final bool showBackButton;
  final Widget Function(Widget title)? wrapAppBarTitle;
  final VoidCallback? onOpenStorageSwitcher;

  /// Session identity supplied by the workspace that hosts this viewport.
  /// Every viewport belongs to a workspace; decoy mode hosts its own, flagged
  /// [BrowserTabsConfig.appRoot].
  final TabId tabId;
  final BrowserTabsConfig workspaceConfig;

  /// Directory to open at instead of the container root (new tabs opened on
  /// a folder). Only read when the screen is first created.
  final String? initialPath;
  final ScrollController? scrollController;

  const DirectoryContentView({
    super.key,
    required this.container,
    this.thumbnailCacheMode,
    this.thumbnailQuality,
    this.onUserActivity,
    this.resolveContainer,
    this.showBackButton = true,
    this.wrapAppBarTitle,
    this.onOpenStorageSwitcher,
    required this.tabId,
    required this.workspaceConfig,
    this.initialPath,
    this.scrollController,
  });

  @override
  ConsumerState<DirectoryContentView> createState() =>
      _DirectoryContentViewState();
}

/// State of one directory viewport. The hosting `BrowserTabsShell` owns the
/// window chrome (app bar, tab strip, drawer, FAB, bottom bar); this state
/// only publishes the pieces it builds.
class _DirectoryContentViewState extends ConsumerState<DirectoryContentView>
    with WidgetsBindingObserver {
  _BrowserAppBarBuilder? _latestAppBarBuilder;
  int? _regularAppBarSignature;
  BrowserAppBarFactory? _regularAppBarFactory;
  int? _selectionAppBarSignature;
  BrowserAppBarFactory? _selectionAppBarFactory;

  BrowserAppBarFactory _appBarFactoryFor({
    required int signature,
    required bool selectionMode,
  }) {
    if (selectionMode) {
      if (_selectionAppBarSignature == signature &&
          _selectionAppBarFactory != null) {
        return _selectionAppBarFactory!;
      }
      _selectionAppBarSignature = signature;
      return _selectionAppBarFactory = (context) =>
          _latestAppBarBuilder!(context, selectionMode: true);
    }

    if (_regularAppBarSignature == signature && _regularAppBarFactory != null) {
      return _regularAppBarFactory!;
    }
    _regularAppBarSignature = signature;
    return _regularAppBarFactory = (context) =>
        _latestAppBarBuilder!(context, selectionMode: false);
  }

  // ── Navigation (FileBrowserNavigation controller) ────────────────────────
  // pathStack/currentItems/isLoading/isListingTruncated/statusMessage/
  // statusIsError/freeSpace/layoutMode/currentFilter/archiveContext/
  // isContainerLocked/back-gesture-preview state all moved to
  // fileBrowserNavigationProvider(tabId) -- see
  // controllers/file_browser_navigation_controller.dart. Kept as
  // same-named getters (matching the existing _search/_pinsBookmarks/
  // _mountedDocProviderFolders pattern already used in this file) so the
  // hundreds of read call-sites throughout this file don't need to change.
  TabId get _tabId => widget.tabId;
  TabId get _stateKey => widget.tabId;

  // ── Workspace state ──────────────────────────────────────────────────────
  bool _wasActiveTab = true;
  bool _wasMultiTab = false;
  bool _wasVisibleTab = true;
  ProviderSubscription<BrowserTabsState>? _workspaceSubscription;

  BrowserTabsState get _workspaceState =>
      ref.read(browserTabsProvider(widget.workspaceConfig));

  /// Where this viewport contributes its app bar, FAB and bottom bar, and
  /// where it learns which tabs are on screen.
  late final BrowserChromeHub _chrome = ref.read(
    browserChromeProvider(widget.workspaceConfig),
  );

  BrowserTabs get _workspaceNotifier =>
      ref.read(browserTabsProvider(widget.workspaceConfig).notifier);

  List<BrowserTabState> get _workspaceTabs => _workspaceState.tabs;

  /// True when this viewport is the active (focused) tab.
  /// Hidden tabs stay mounted in PageView's keep-alive cache, so anything that is
  /// app-global (predictive back, system back, auto-lock activity) must be
  /// gated on this or every hidden tab would react too.
  bool get _isActiveTab =>
      ref.read(activeBrowserTabProvider(widget.workspaceConfig))?.tabId ==
      _tabId;

  /// True when this viewport is on screen: the active tab, or the second pane
  /// in dual-pane browsing. An on-screen pane must keep its listing fresh even
  /// while the other pane has focus; focus alone only decides who gets back,
  /// chrome and activity.
  bool get _isVisibleTab => _isVisibleWhen(active: _isActiveTab);

  bool _isVisibleWhen({required bool active}) =>
      active || _chrome.visibleTabs.value.contains(widget.tabId);

  bool get _hasMultipleTabs => _workspaceState.hasMultiple;

  void _onWorkspaceChanged(BrowserTabsState? previous, BrowserTabsState next) {
    if (!mounted) return;
    final active = next.activeTabId == _tabId;
    final multi = next.hasMultiple;
    final flipped = active != _wasActiveTab || multi != _wasMultiTab;
    _wasActiveTab = active;
    _wasMultiTab = multi;

    // PopScope.canPop depends on both flags, so rebuild when they flip.
    if (flipped) setState(() {});

    _syncVisibility(active: active);
  }

  void _onVisibleTabsChanged() => _syncVisibility(active: _isActiveTab);

  /// Refreshes a stale listing the moment this viewport comes on screen.
  /// Operations targeting this location may have completed while it was off
  /// screen; its cached list is kept until then, and refreshed once before it
  /// is presented again.
  void _syncVisibility({required bool active}) {
    if (!mounted) return;
    final visible = _isVisibleWhen(active: active);
    final becameVisible = visible && !_wasVisibleTab;
    _wasVisibleTab = visible;
    if (!becameVisible) return;
    final nav = ref.read(fileBrowserNavigationProvider(_stateKey));
    if (nav.needsRefresh && nav.pathStack.isNotEmpty) {
      _loadDirectoryContents(_currentDirPath, refresh: true);
    }
  }

  FileBrowserNavigationState get _nav =>
      ref.watch(fileBrowserNavigationProvider(_stateKey));
  FileBrowserNavigation get _navNotifier =>
      ref.read(fileBrowserNavigationProvider(_stateKey).notifier);

  List<PathSegment> get _pathStack => _nav.pathStack;
  List<RawEntry> get _currentItems => _nav.currentItems;
  bool get _isLoading => _nav.isLoading;
  bool get _isListingTruncated => _nav.isListingTruncated;
  String? get _statusMessage => _nav.statusMessage;

  /// Key for the status banner's [AnimatedSwitcher]. Normally each distinct
  /// message should get its own cross-fade, so keying on the text itself is
  /// right. But the media-scan banner rewrites its text every
  /// [mediaScanProgressInterval] folders (MediaScanService), and on a
  /// large tree that can happen
  /// many times a second -- far faster than the fade can finish -- so
  /// keying on the literal text there restarts the transition mid-fade on
  /// every tick, which reads as the banner flickering/flashing instead of
  /// smoothly showing a live count. While a scan is in progress, use one
  /// stable key so the count updates in place without re-triggering the
  /// fade; a real change in what's shown (e.g. scanning -> cancelled/error)
  /// still swaps `_mediaScanInProgress` and gets its own transition.
  Object get _statusBannerKey =>
      _mediaScanInProgress ? 'media_scan_progress' : (_statusMessage ?? '');
  bool get _statusIsError => _nav.statusIsError;
  int? get _freeSpace => _nav.freeSpace;
  BrowserLayoutMode get _layoutMode => _nav.layoutMode;
  String? get _currentFilter => _nav.currentFilter;
  ArchiveContext? get _archiveContext => _nav.archiveContext;
  bool get _isContainerLocked => _nav.isContainerLocked;
  double? get _backGestureProgress => _nav.backGestureProgress;
  List<RawEntry>? get _backGesturePreviewItems => _nav.backGesturePreviewItems;
  BrowserLayoutMode? get _backGesturePreviewLayoutMode =>
      _nav.backGesturePreviewLayoutMode;
  String? get _backGesturePreviewDirPath => _nav.backGesturePreviewDirPath;
  bool get _backGesturePreviewAtRoot => _nav.backGesturePreviewAtRoot;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final rootLabel = context.l10n.rootFolderLabel;

      // Defer provider mutations and initial loading until after the first frame builds
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _navNotifier.initRoot(rootLabel: rootLabel);
        _navNotifier.setFreeSpace(
          widget.container.totalSpace > 0 && widget.container.freeSpace >= 0
              ? widget.container.freeSpace
              : null,
        );
        _initSettingsAndContents();
        _loadToolbarConfig();
        _refreshMountedDocProviderFolders();
      });
    }
  }

  ScrollController _browserScrollController = ScrollController();
  ScrollController _backGesturePreviewScrollController = ScrollController();

  void _resetBrowserScrollController({double initialOffset = 0.0}) {
    if (widget.scrollController != null) {
      if (_browserScrollController.hasClients) {
        _browserScrollController.jumpTo(initialOffset);
      }
      return;
    }
    final old = _browserScrollController;
    _browserScrollController = ScrollController(
      initialScrollOffset: initialOffset,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
    });
  }

  void _resetBackGesturePreviewScrollController({double initialOffset = 0.0}) {
    final old = _backGesturePreviewScrollController;
    _backGesturePreviewScrollController = ScrollController(
      initialScrollOffset: initialOffset,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
    });
  }

  Future<void> _saveExtensionPreference(String ext, String preference) async {
    final cleanExt = ext.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim();
    if (cleanExt.isEmpty) return;

    _appSettings.extensionPreferences[cleanExt] = preference;

    try {
      final currentSettings = ref.read(appSettingsControllerProvider).settings;
      final newPrefs = Map<String, String>.from(
        currentSettings.extensionPreferences,
      );
      newPrefs[cleanExt] = preference;

      await ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings((s) => s.copyWith(extensionPreferences: newPrefs));
    } catch (_) {
      // Fallback directly to AppSettingsService if controller is not yet active
      await ref.read(appSettingsServiceProvider).saveSettings(_appSettings);
    }
  }

  CrossContainerClipboard get _clip =>
      ref.read(crossContainerClipboardProvider.notifier);
  late final FileOperationService _opSvc;
  late final dynamic _vaultEvents;
  FolderDocumentProviderService get _docProviderService =>
      ref.read(folderDocumentProviderServiceProvider);
  FileManagerToolbarService get _toolbarSvc =>
      ref.read(fileManagerToolbarServiceProvider);

  FileBrowserSearchState get _search =>
      ref.watch(fileBrowserSearchProvider(_stateKey));
  FileBrowserSearch get _searchNotifier =>
      ref.read(fileBrowserSearchProvider(_stateKey).notifier);

  bool get _searchActive => _search.active;
  String get _searchQuery => _search.query;
  bool get _isDeepSearch => _search.isDeepSearch;
  bool get _isSearchingSubfolders => _search.isSearchingSubfolders;
  List<RawEntry> get _deepSearchResults => _search.deepSearchResults;

  /// Resolves the archive-root path the search controller needs (see
  /// file_browser_search_controller.dart's header) -- kept here since it's
  /// a _pathStack lookup, and _pathStack stays screen-owned.
  String? get _archiveRootPathForSearch => _archiveContext == null
      ? null
      : _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;

  AppSettings _appSettings = AppSettings();
  ThumbnailCacheMode _resolvedThumbnailCacheMode = ThumbnailCacheMode.appCache;
  ThumbnailQuality _resolvedThumbnailQuality = ThumbnailQuality.defaultQuality;

  /// The saved record of the vault being browsed (null for Local Storage and
  /// anything else without one). Kept so a change to the app-wide thumbnail
  /// default can be re-resolved immediately, for vaults that follow it,
  /// without re-reading the repository.
  ContainerRecord? _containerRecord;

  /// Re-derives [_resolvedThumbnailCacheMode] / [_resolvedThumbnailQuality]
  /// from [config] and [_containerRecord]. Call inside `setState`.
  void _applyResolvedThumbnails(FileManagerToolbarConfig config) {
    final resolved = resolveThumbnailSettings(
      config: config,
      isLocalStorage: widget.container.isLocalStorage,
      record: _containerRecord,
      overrideCacheMode: widget.thumbnailCacheMode,
      overrideQuality: widget.thumbnailQuality,
    );
    _resolvedThumbnailCacheMode = resolved.cacheMode;
    _resolvedThumbnailQuality = resolved.quality;
  }

  FileManagerToolbarConfig _toolbarConfig = FileManagerToolbarConfig.defaults();
  bool _toolbarConfigReady = false;
  int? _lastBuiltFloatingActionSignature;
  int? _lastPublishedFloatingActionSignature;
  Widget? _lastBuiltFloatingAction;
  List<RawEntry>? _itemsUsedForFloatingActionSignature;
  int _cachedFloatingActionItemsSignature = 0;

  int _floatingActionItemsSignature() {
    final items = _currentItems;
    if (identical(items, _itemsUsedForFloatingActionSignature)) {
      return _cachedFloatingActionItemsSignature;
    }
    _itemsUsedForFloatingActionSignature = items;
    _cachedFloatingActionItemsSignature = Object.hashAll(
      items.map(
        (entry) => Object.hash(
          entry.name,
          entry.isDir,
          entry.sizeBytes,
          entry.modifiedSecs,
          entry.isPlaceholder,
        ),
      ),
    );
    return _cachedFloatingActionItemsSignature;
  }

  FileBrowserPinsBookmarksState get _pinsBookmarks =>
      ref.watch(fileBrowserPinsBookmarksProvider(widget.container.volId));
  FileBrowserPinsBookmarks get _pinsBookmarksNotifier => ref.read(
    fileBrowserPinsBookmarksProvider(widget.container.volId).notifier,
  );
  Set<String> get _pinnedPaths => _pinsBookmarks.pinnedPaths;
  List<String> get _bookmarkPaths => _pinsBookmarks.bookmarkPaths;
  // Set as the very first line of dispose(). `mounted` alone isn't a
  // sufficient guard for the two native-event listeners below: Flutter
  // marks the element's lifecycle state defunct *before* running this
  // State's dispose(), so a listener invoked synchronously as a side
  // effect of something torn down inside dispose() (or a listener left
  // registered because an earlier dispose() step threw) can still see
  // `mounted == true` on an already-defunct element and trip
  // markNeedsBuild's assertion. `_disposed` closes that gap regardless of
  // how the listener ends up firing late.
  bool _disposed = false;

  bool get _atRoot => _nav.atRoot;
  String get _currentDirPath => _nav.currentDirPath;
  Set<String> get _mountedDocProviderFolders =>
      ref.watch(fileBrowserDocProviderProvider(widget.container.volId));
  FileBrowserDocProvider get _docProviderNotifier =>
      ref.read(fileBrowserDocProviderProvider(widget.container.volId).notifier);

  String _fullPathOf(RawEntry entry) => fullPathOf(entry, _currentDirPath);
  String _joinPath(String name) => joinPath(name, _currentDirPath);
  bool _isFolderMounted(RawEntry entry) =>
      isFolderMounted(entry, _currentDirPath, _mountedDocProviderFolders);
  bool _isPinned(RawEntry entry) =>
      isPinned(entry, _currentDirPath, _pinnedPaths);
  bool _isBookmark(RawEntry entry) =>
      isBookmark(entry, _currentDirPath, _bookmarkPaths);
  bool _isFolderSynced(RawEntry entry) {
    if (!entry.isDir || widget.container.isLocalStorage) return false;
    final path = _fullPathOf(entry);
    final synced = ref.watch(vaultSyncedFolderPathsProvider(widget.container));
    return synced.contains(path);
  }

  /// Pinned items first, then folders before files, then [compareItems]'s
  /// sort order within each group. Was independently redefined as a local
  /// closure at four separate call sites in this file (jump-to-item
  /// scrolling, the media-viewer swipe list built from the visible list,
  /// the media-viewer swipe list built from a fresh directory scan, and
  /// the main visible-list build) -- pulled out once here since all four
  /// were identical and needed to stay that way.
  int _compareOverall(RawEntry ea, RawEntry eb) {
    final sort = ref.read(fileBrowserSortProvider(_stateKey));
    return compareBrowserEntries(
      ea,
      eb,
      currentDirPath: _currentDirPath,
      pinnedPaths: _pinnedPaths,
      sortBy: sort.sortBy,
      sortAscending: sort.sortAscending,
    );
  }

  /// Whether [item] should be shown in the current directory listing --
  /// respects the hidden-files toggle, the active search [query], and the
  /// current type filter. Was duplicated identically between the main
  /// list build and _scrollToItem's own re-derivation of "what's
  /// currently visible" (needed to compute the same index the visible
  /// list uses) -- pulled out once here since both copies needed to stay
  /// identical for jump-to-item to land on the right row.
  ///
  /// [skipQueryCheck] is for entries sourced from the search controller's
  /// own scan (`_deepSearchResults`) rather than straight from the
  /// directory listing: the scan already matched [item] against [query] --
  /// by name *or*, for an Item Vault entry, by username/email (see
  /// file_browser_search_controller.dart) -- so re-checking [item].name
  /// here would wrongly drop a content-only match, whose name doesn't
  /// contain [query] at all. Hidden-files and the type filter still apply
  /// either way.
  bool _isVisibleInCurrentListing(
    RawEntry item,
    String query, {
    bool skipQueryCheck = false,
  }) => isVisibleInListing(
    item,
    query: query,
    showHidden: _toolbarConfig.showHiddenFiles,
    typeFilter: _currentFilter,
    skipQueryCheck: skipQueryCheck,
  );

  /// Search-aware view of [localItems] (the current directory's listing,
  /// already merged with placeholders/pending-deletes where the caller
  /// does that): folds in the search controller's own results so an Item
  /// Vault entry found by username/email -- not just by name -- shows up
  /// too, without waiting on it for the common case of a plain name
  /// search.
  ///
  /// Deep-search mode aside, [localItems] is filtered synchronously and
  /// instantly (same as before this existed) for the name-match case;
  /// `_deepSearchResults` (populated by a debounced scan even in
  /// non-deep-search mode now -- see file_browser_search_controller.dart's
  /// onQueryChanged) only has to contribute entries that check adds that
  /// the instant pass couldn't already find, so a plain name search never
  /// waits on it. In deep-search mode, `_deepSearchResults` already spans
  /// every matched folder, so it's used as-is instead -- `localItems`
  /// alone could never represent that.
  List<RawEntry> _searchAwareVisibleItems(
    List<RawEntry> localItems,
    String query,
  ) => searchAwareVisibleItems(
    localItems,
    query: query,
    searchActive: _searchActive,
    deepSearch: _isDeepSearch,
    deepSearchResults: _deepSearchResults,
    showHidden: _toolbarConfig.showHiddenFiles,
    typeFilter: _currentFilter,
  );

  void _onContainerLockedEvent(int volId) {
    if (_disposed || volId != widget.container.volId || !mounted) return;
    _navNotifier.setContainerLocked(true);
    // The hosting shell closes this vault's tabs and leaves the route once
    // none remain; this viewport only needs to stop touching the vault.
  }

  DateTime? _lastOpReloadTime;
  Timer? _opReloadTimer;

  void _onOperationsChanged() {
    if (!mounted) return;
    final hasActiveTargetingCurrent = _opSvc.activeOperations.any(
      (op) =>
          !op.isDelete &&
          op.destVolId == widget.container.volId &&
          (op.destDirPath == _currentDirPath ||
              op.destDirPath.startsWith(
                _currentDirPath.isEmpty ? '' : '$_currentDirPath/',
              )),
    );
    // Viewports that are off screen do not rebuild for transfer progress.
    // Record that their listing may be stale and refresh lazily when they
    // come back on screen.
    if (!_isVisibleTab) {
      if (hasActiveTargetingCurrent) _navNotifier.markNeedsRefresh();
      return;
    }
    setState(() {});
    if (!hasActiveTargetingCurrent) return;

    final now = DateTime.now();
    final last = _lastOpReloadTime;
    if (last == null ||
        now.difference(last) > const Duration(milliseconds: 350)) {
      _lastOpReloadTime = now;
      FolderThumbnailPreview.clearSessionCache();
      _loadDirectoryContents(_currentDirPath, refresh: true);
    } else {
      _opReloadTimer ??= Timer(const Duration(milliseconds: 350), () {
        _opReloadTimer = null;
        if (mounted) {
          _lastOpReloadTime = DateTime.now();
          FolderThumbnailPreview.clearSessionCache();
          _loadDirectoryContents(_currentDirPath, refresh: true);
        }
      });
    }
  }

  /// Delete operations this viewport started. It reconciles its own listing
  /// when they finish, so [_onVolumeContentChanged] must not do it twice.
  final Set<int> _ownedOpIds = <int>{};

  /// A finished operation changed this volume. The viewport that started it
  /// already updates itself; every other viewport of the same volume (the
  /// other pane in dual-pane browsing, or a background tab) is stale and
  /// refreshes here, or is flagged to refresh when it comes back on screen.
  void _onVolumeContentChanged(VolumeContentChange change) {
    if (_ownedOpIds.remove(change.opId)) return;
    if (_disposed || !mounted || change.volId != widget.container.volId) {
      return;
    }
    if (!_isVisibleTab) {
      _navNotifier.markNeedsRefresh();
      return;
    }
    final nav = ref.read(fileBrowserNavigationProvider(_stateKey));
    // Still on the first load: that load already reads the new state.
    if (nav.pathStack.isEmpty) return;
    FolderThumbnailPreview.clearSessionCache();
    _loadDirectoryContents(nav.currentDirPath, refresh: true);
  }

  @override
  void initState() {
    super.initState();
    if (widget.scrollController != null) {
      _browserScrollController = widget.scrollController!;
    }
    _opSvc = ref.read(fileOperationServiceProvider);
    _vaultEvents = ref.read(vaultEngineEventsProvider);

    _opSvc.addListener(_onOperationsChanged);
    _opSvc.addVolumeContentChangedListener(_onVolumeContentChanged);
    _workspaceSubscription = ref.listenManual<BrowserTabsState>(
      browserTabsProvider(widget.workspaceConfig),
      _onWorkspaceChanged,
    );
    _wasActiveTab = _isActiveTab;
    _wasMultiTab = _hasMultipleTabs;
    _wasVisibleTab = _isVisibleTab;
    _chrome.visibleTabs.addListener(_onVisibleTabsChanged);
    WidgetsBinding.instance.addObserver(this);
    _vaultEvents.addContainerLockedListener(_onContainerLockedEvent);
  }

  @override
  void dispose() {
    _disposed = true;
    _workspaceSubscription?.close();
    _chrome.visibleTabs.removeListener(_onVisibleTabsChanged);
    _mediaScanToken?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _opReloadTimer?.cancel();
    _opSvc.removeListener(_onOperationsChanged);
    _opSvc.removeVolumeContentChangedListener(_onVolumeContentChanged);
    if (widget.scrollController == null) _browserScrollController.dispose();
    _backGesturePreviewScrollController.dispose();
    _vaultEvents.removeContainerLockedListener(_onContainerLockedEvent);
    super.dispose();
  }

  void _scrollToItem(String fullPath) {
    if (!_browserScrollController.hasClients) return;

    final query = _searchQuery.trim().toLowerCase();
    final sortedItems = _searchAwareVisibleItems(_currentItems, query).toList()
      ..sort(_compareOverall);

    final targetIndex = sortedItems.indexWhere((e) {
      final itemFullPath =
          (_searchActive && _isDeepSearch && e.name.contains('/'))
          ? e.name
          : (_currentDirPath.isEmpty ? e.name : '$_currentDirPath/${e.name}');
      return itemFullPath == fullPath;
    });

    if (targetIndex == -1) return;

    final position = _browserScrollController.position;
    final maxScroll = position.maxScrollExtent;
    final viewportHeight = position.viewportDimension;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    double itemTop = 0.0;
    double itemHeight = 0.0;

    switch (_layoutMode) {
      case BrowserLayoutMode.list:
      case BrowserLayoutMode.compact:
      case BrowserLayoutMode.detailed:
        final isCompact = _layoutMode == BrowserLayoutMode.compact;
        final isDetailed = _layoutMode == BrowserLayoutMode.detailed;
        final zoom = _toolbarConfig.listZoomLevel;
        final textScaler = MediaQuery.textScalerOf(context);
        final effectiveTextScaler = TextScaler.linear(
          textScaler.scale(1.0) * zoom,
        );
        final baseContentHeight = (isCompact ? 32.0 : 44.0) * zoom;
        final scaledTextHeight = effectiveTextScaler.scale(
          isDetailed ? 46.0 : 24.0,
        );
        final contentHeight = math.max(baseContentHeight, scaledTextHeight);
        final itemExtent =
            contentHeight + (isCompact ? 8.0 : 20.0) * zoom + 2.0;

        itemHeight = itemExtent;
        itemTop = targetIndex * itemExtent;
        break;

      case BrowserLayoutMode.grid:
        final minCols = isLandscape ? 3 : 1;
        final maxCols = isLandscape ? 7 : 4;
        final columns =
            (isLandscape
                    ? _toolbarConfig.gridColumnsLandscape
                    : _toolbarConfig.gridColumnsPortrait)
                .clamp(minCols, maxCols);
        final row = targetIndex ~/ columns;
        final screenWidth = MediaQuery.sizeOf(context).width;
        final availableWidth = screenWidth - 20.0;
        final itemWidth = (availableWidth - (columns - 1) * 8.0) / columns;
        final previewRatio = _toolbarConfig
            .getGridAspectRatioForFolder(widget.container.uri, _currentDirPath)
            .ratio;
        final previewHeight = itemWidth / previewRatio;
        final labelHeight = _toolbarConfig.showGridFileNames ? 36.0 : 0.0;
        itemHeight = previewHeight + labelHeight;
        final rowHeight = itemHeight + 8.0;
        itemTop = 12.0 + (row * rowHeight);
        break;

      case BrowserLayoutMode.masonry:
        final minCols = isLandscape ? 2 : 1;
        final maxCols = isLandscape ? 6 : 3;
        final columns =
            (isLandscape
                    ? _toolbarConfig.masonryColumnsLandscape
                    : _toolbarConfig.masonryColumnsPortrait)
                .clamp(minCols, maxCols);
        final screenWidth = MediaQuery.sizeOf(context).width;
        final availableWidth = screenWidth - 20.0;
        final itemWidth = (availableWidth - (columns - 1) * 8.0) / columns;
        final colHeights = List<double>.filled(columns, 12.0);
        final showNames = _toolbarConfig.showGridFileNames;

        for (int i = 0; i <= targetIndex; i++) {
          final entry = sortedItems[i];
          int shortestCol = 0;
          for (int c = 1; c < columns; c++) {
            if (colHeights[c] < colHeights[shortestCol]) {
              shortestCol = c;
            }
          }

          final fullEntryPath = entry.name.contains('/')
              ? entry.name
              : (_currentDirPath.isEmpty
                    ? entry.name
                    : '$_currentDirPath/${entry.name}');

          double ratio = 1.0;
          if (!entry.isDir) {
            final cachedRatio = MediaAspectRatioCache.get(
              widget.container,
              fullEntryPath,
            );
            if (cachedRatio != null && cachedRatio > 0) {
              ratio = cachedRatio.clamp(0.5, 2.2);
            } else if (MediaViewerConstants.isVideo(entry.name)) {
              ratio = (16.0 / 9.0).clamp(0.5, 2.2);
            }
          }

          final hasLabel =
              showNames ||
              entry.isDir ||
              !MediaViewerConstants.hasRealThumbnail(entry.name);
          final previewHeight = itemWidth / ratio;
          final currentHeight = previewHeight + (hasLabel ? 36.0 : 0.0);
          if (i == targetIndex) {
            itemTop = colHeights[shortestCol];
            itemHeight = currentHeight;
          }
          colHeights[shortestCol] += currentHeight + 8.0;
        }
        break;
    }

    final currentOffset = position.pixels;
    const topMargin = 16.0;

    // Dynamically calculate bottom clearance to avoid toolbar & bottom padding overlap
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomMargin = AppSpacing.floatingStackClearance + bottomInset + 16.0;

    if (itemTop >= currentOffset + topMargin &&
        (itemTop + itemHeight) <=
            currentOffset + viewportHeight - bottomMargin) {
      return;
    }

    double targetOffset;
    if (itemTop < currentOffset + topMargin) {
      targetOffset = itemTop - topMargin;
    } else {
      targetOffset = (itemTop + itemHeight) - viewportHeight + bottomMargin;
    }

    final clampedOffset = targetOffset.clamp(0.0, maxScroll);
    _browserScrollController.jumpTo(clampedOffset);
  }

  BrowserLayoutMode _getLayoutModeForFolder(
    String dirPath, {
    AppSettings? appSettings,
  }) {
    final effectiveAppSettings = appSettings ?? _appSettings;
    if (_toolbarConfig.rememberPerFolderLayout) {
      final key = FileManagerToolbarConfig.folderKey(
        widget.container.uri,
        dirPath,
      );
      final savedModeStr = _toolbarConfig.folderLayoutModes[key];
      if (savedModeStr != null) {
        final savedMode = BrowserLayoutMode.fromJson(savedModeStr);
        if (savedMode != null) return savedMode;
      }
    }
    return effectiveAppSettings.defaultLayoutMode;
  }

  /// Sort-order counterpart to [_getLayoutModeForFolder]: this folder's own
  /// saved sort if per-folder memory is on and one was saved, otherwise the
  /// app-wide default sort. Called at every navigation point that changes
  /// [_currentDirPath] so each folder shows the sort it was last given
  /// rather than whatever folder the sort provider happened to be left on.
  ({SortBy sortBy, bool sortAscending}) _getSortStateForFolder(
    String dirPath, {
    AppSettings? appSettings,
  }) {
    final effectiveAppSettings = appSettings ?? _appSettings;
    final saved = decodeFolderSortState(
      _toolbarConfig.getRawFolderSortMode(widget.container.uri, dirPath),
    );
    if (saved != null) return saved;
    return (
      sortBy: effectiveAppSettings.defaultFileSortBy,
      sortAscending: effectiveAppSettings.defaultFileSortAscending,
    );
  }

  /// Narrows the selection to just [entry]. Selection-based handlers
  /// (`_exportSelectedToStorage`, `_runQuickCrypto`, ...) aggregate the
  /// selection across ALL tabs, so any selection held in other tabs is cleared
  /// first; otherwise the item sheet could act on items the user never picked.
  void _selectOnly(RawEntry entry) {
    exitSelectionMode();
    setSelectedItems({entry});
  }

  void _showItemActionsSheet(RawEntry entry) {
    _signalActivity();
    HapticFeedback.selectionClick();
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
        BrowserDialogs.showRename(
          context,
          container: widget.container,
          oldEntries: [entry],
          existingEntries: _currentItems,
          currentDirPath: _currentDirPath,
          onSuccess: () =>
              _loadDirectoryContents(_currentDirPath, refresh: true),
          readOnly: _isReadOnly,
        );
      },
      onDelete: () {
        BrowserDialogs.showBatchDelete(
          context,
          toDelete: [entry],
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
        _clip.set(
          volId: widget.container.volId,
          displayName: widget.container.displayName,
          cut: false,
          clipItems: [
            ClipboardItem(
              path: fullPath,
              isDir: entry.isDir,
              sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
              modifiedSecs: entry.modifiedSecs,
            ),
          ],
        );
        _setStatus(context.l10n.copiedSuffix(entry.name));
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
            ClipboardItem(
              path: fullPath,
              isDir: entry.isDir,
              sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
              modifiedSecs: entry.modifiedSecs,
            ),
          ],
        );
        _setStatus(context.l10n.clipboardVerbMoving);
      },
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
      onTogglePin: () async {
        await _pinsBookmarksNotifier.togglePins(widget.container, [
          fullPath,
        ], pin: !_isPinned(entry));
      },
      onToggleBookmark: () async {
        await _pinsBookmarksNotifier.toggleBookmarks(widget.container, [
          fullPath,
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
                    skipExtensions: _vaultItemExtensions,
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

  void _showSyncSettings(RawEntry entry) {
    unawaited(
      SyncRuleEditorSheet.show(
        context,
        vault: widget.container,
        folderPath: _fullPathOf(entry),
        folderName: entry.name,
      ),
    );
  }

  void _showRootSyncSettings() {
    unawaited(
      SyncRuleEditorSheet.show(
        context,
        vault: widget.container,
        folderPath: '',
        folderName: widget.container.displayName,
      ),
    );
  }

  Future<void> _refreshMountedDocProviderFolders() =>
      _docProviderNotifier.refresh(widget.container);

  Future<void> _toggleFolderDocumentProvider(RawEntry entry) async {
    final path = _fullPathOf(entry);
    final ok = await _docProviderNotifier.toggle(
      widget.container,
      path,
      entry.name,
    );
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(
        context,
        message: context.l10n.couldNotExpose(entry.name),
      );
      return;
    }
    showAppSnackBar(
      context,
      message: context.l10n.nowAvailableToOtherApps(entry.name),
    );
  }

  Future<void> _unmountFolderDocumentProvider(RawEntry entry) async {
    final path = _fullPathOf(entry);
    final ok = await _docProviderNotifier.unmount(widget.container, path);
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(
        context,
        message: context.l10n.couldNotUnmount(entry.name),
      );
    }
  }

  Future<void> _setFolderAutoMount(RawEntry entry, bool autoMount) async {
    final path = _fullPathOf(entry);
    await _docProviderService.setAutoMount(widget.container, path, autoMount);
  }

  Future<void> _showFolderDocumentProviderSheet(RawEntry entry) async {
    final path = _fullPathOf(entry);
    final records = await ref.read(containerRepositoryProvider).loadAll();
    final record = records[widget.container.uri];
    final matches =
        record?.documentProviderFolders.where((f) => f.path == path) ??
        const [];
    final existing = matches.isEmpty ? null : matches.first;
    if (!mounted) return;
    final action = await FolderDocumentProviderSheet.show(
      context,
      folderName: entry.name,
      initialAutoMount: existing?.autoMount ?? false,
      onAutoMountChanged: (value) => _setFolderAutoMount(entry, value),
    );
    if (action == FolderDocumentProviderAction.unmount) {
      await _unmountFolderDocumentProvider(entry);
    }
  }

  Future<void> _toggleBookmarkSelected({required bool bookmark}) async {
    _signalActivity();
    final selected = _uniqueSelectedBrowserEntries
        .where((item) => !item.insideArchive)
        .toList();
    final groups = <int, List<_SelectedBrowserEntry>>{};
    for (final item in selected) {
      groups.putIfAbsent(item.container.volId, () => []).add(item);
    }
    for (final group in groups.values) {
      final container = group.first.container;
      final paths = group
          .map((item) => fullPathOf(item.entry, item.currentDirPath))
          .toSet()
          .toList();
      await ref
          .read(fileBrowserPinsBookmarksProvider(container.volId).notifier)
          .toggleBookmarks(container, paths, bookmark: bookmark);
    }
    final count = selected.length;
    _setStatus(
      bookmark
          ? context.l10n.bookmarkedCount(count)
          : context.l10n.unbookmarkedCount(count),
    );
    exitSelectionMode();
  }

  Future<void> _togglePinSelected({required bool pin}) async {
    _signalActivity();
    final selected = _uniqueSelectedBrowserEntries
        .where((item) => !item.insideArchive)
        .toList();
    final groups = <int, List<_SelectedBrowserEntry>>{};
    for (final item in selected) {
      groups.putIfAbsent(item.container.volId, () => []).add(item);
    }
    for (final group in groups.values) {
      final container = group.first.container;
      final paths = group
          .map((item) => fullPathOf(item.entry, item.currentDirPath))
          .toSet()
          .toList();
      await ref
          .read(fileBrowserPinsBookmarksProvider(container.volId).notifier)
          .togglePins(container, paths, pin: pin);
    }
    final count = selected.length;
    _setStatus(
      pin ? context.l10n.pinnedCount(count) : context.l10n.unpinnedCount(count),
    );
    exitSelectionMode();
  }

  bool get _isReadOnly => widget.container.readOnly;
  void _signalActivity() => widget.onUserActivity?.call();
  Future<void> _initSettingsAndContents() async {
    _navNotifier.setLoading(true);
    _pinsBookmarksNotifier.load(widget.container);
    try {
      // Independent of one another, so they run together instead of each
      // waiting for the previous one's secure-storage round trip.
      final (appSettings, records, toolbarConfig) = await (
        ref.read(appSettingsServiceProvider).loadSettings(),
        ref.read(containerRepositoryProvider).loadAll(),
        _toolbarSvc.load(),
      ).wait;
      final record = records[widget.container.uri];
      if (mounted) {
        setState(() {
          _appSettings = appSettings;
          _toolbarConfig = toolbarConfig;
          _toolbarConfigReady = true;
          _containerRecord = record;
          _applyResolvedThumbnails(toolbarConfig);
        });
        _navNotifier.setLayoutMode(
          _getLayoutModeForFolder(_currentDirPath, appSettings: appSettings),
        );
        final initialSort = _getSortStateForFolder(
          _currentDirPath,
          appSettings: appSettings,
        );
        _sortNotifier.restore(initialSort.sortBy, initialSort.sortAscending);
      }
      if (mounted &&
          widget.container.readOnly &&
          _resolvedThumbnailCacheMode == ThumbnailCacheMode.inContainer) {
        showAppSnackBar(
          context,
          message: context.l10n.readOnlyThumbnailWarning,
          tone: AppBannerTone.warning,
        );
      }
    } catch (e) {
      VeLog.e('FileBrowserScreen', 'Failed to load settings/records', e);
      if (mounted) {
        setState(() => _toolbarConfigReady = true);
      }
    }
    final initialPath = widget.initialPath;
    if (initialPath != null && initialPath.isNotEmpty && mounted) {
      // New tab opened on a folder: go straight there (builds the path
      // stack from the root) instead of listing the root first.
      await _navigateToPath(initialPath, isDir: true);
      return;
    }
    await _loadDirectoryContents(_currentDirPath);
  }

  Future<void> _loadToolbarConfig() async {
    final config = await _toolbarSvc.load();
    final records = await ref.read(containerRepositoryProvider).loadAll();
    final record = records[widget.container.uri];
    if (!mounted) return;
    setState(() {
      _toolbarConfig = config;
      _toolbarConfigReady = true;
      _containerRecord = record;
      _applyResolvedThumbnails(config);
    });
    _navNotifier.setLayoutMode(_getLayoutModeForFolder(_currentDirPath));
    final currentSort = _getSortStateForFolder(_currentDirPath);
    _sortNotifier.restore(currentSort.sortBy, currentSort.sortAscending);
    _pinsBookmarksNotifier.load(widget.container);
  }

  /// True for a [FileOperation] that ended in an error state the person
  /// actually needs to see (e.g. ran out of space partway through, or some
  /// items failed while others succeeded) -- as opposed to a clean
  /// [FileOperationStatus.completed] or a user-initiated
  /// [FileOperationStatus.cancelled], neither of which needs a lingering
  /// explanation. Mirrors the "hasErrors" set [AppBarTransferButton]
  /// already uses to decide whether to keep itself visible instead of
  /// auto-hiding, so a failed op only stays around because *that* widget
  /// (and [FileOperationsSheet]'s per-item detail view) is designed to
  /// keep showing it -- not because this screen invented its own notion
  /// of "still important".
  bool _opNeedsAttention(FileOperation op) =>
      op.status == FileOperationStatus.failed ||
      op.status == FileOperationStatus.diskFull ||
      op.status == FileOperationStatus.completedWithErrors;

  void _setStatus(String msg, {bool error = false, Duration? autoClear}) {
    if (!mounted) return;
    _navNotifier.setStatus(msg, error: error);
    final delay =
        autoClear ??
        (error ? const Duration(seconds: 5) : const Duration(seconds: 3));
    Future.delayed(delay, () {
      if (mounted && _statusMessage == msg) {
        _navNotifier.clearStatus();
      }
    });
  }

  void _clearStatus() {
    if (mounted) _navNotifier.clearStatus();
  }

  Future<void> _loadDirectoryContents(
    String path, {
    bool refresh = false,
  }) async {
    try {
      await _navNotifier.loadDirectoryContents(
        widget.container,
        path,
        refresh: refresh,
        layoutMode: _getLayoutModeForFolder(path),
        onActivity: _signalActivity,
      );
    } catch (e) {
      if (mounted) {
        _setStatus(
          context.l10n.failedLoadingFolder('${e.runtimeType}'),
          error: true,
        );
      }
    }
  }

  Future<void> _openArchive(String fullPath, String archiveName) async {
    // Remember where the containing folder is scrolled to, so that leaving the
    // archive restores it exactly like leaving a sub-folder does. Read once,
    // before the (possibly repeated) open attempts below.
    final currentOffset = _browserScrollController.hasClients
        ? _browserScrollController.offset
        : 0.0;
    String? passphrase;
    try {
      while (true) {
        final ctx = await _navNotifier.openArchive(
          widget.container,
          fullPath,
          archiveName,
          passphrase: passphrase,
          layoutMode: _getLayoutModeForFolder(fullPath),
          onActivity: _signalActivity,
          currentScrollOffset: currentOffset,
        );

        if (ctx.status == ArchiveOpenStatus.ok) {
          final archiveSort = _getSortStateForFolder(fullPath);
          _sortNotifier.restore(archiveSort.sortBy, archiveSort.sortAscending);
          // The archive root starts at the top, not at the parent's offset.
          if (mounted) _resetBrowserScrollController(initialOffset: 0.0);
          _clearSearch();
          return;
        }

        if (!mounted) return;
        final entered = await BrowserDialogs.showArchivePasswordPrompt(
          context,
          wrongPassword: ctx.status == ArchiveOpenStatus.wrongPassphrase,
        );
        if (entered == null) return;
        passphrase = entered;
      }
    } catch (e) {
      if (mounted) {
        _setStatus(
          context.l10n.failedToReadArchive('${e.runtimeType}'),
          error: true,
        );
      }
    }
  }

  Future<ArchiveEntryExtractResult?> _extractArchiveEntryWithPassword(
    String entryPath,
  ) async {
    final currentArchive = _archiveContext;
    if (currentArchive == null) return null;
    var archive = currentArchive;

    while (mounted) {
      final result = await archive.extractEntryResult(entryPath);
      if (!result.needsPassphrase) return result;

      final entered = await BrowserDialogs.showArchivePasswordPrompt(
        context,
        wrongPassword: result.status == ArchiveOpenStatus.wrongPassphrase,
      );
      if (entered == null || !mounted) return null;

      archive = archive.withPassphrase(entered);
      _navNotifier.updateArchiveContext(archive);
    }
    return null;
  }

  Future<ArchiveEntryStageResult?> _stageArchiveEntryWithPassword(
    String entryPath,
  ) async {
    final currentArchive = _archiveContext;
    if (currentArchive == null) return null;
    var archive = currentArchive;

    while (mounted) {
      final result = await archive.stageEntryForBrowse(entryPath);
      if (!result.needsPassphrase) return result;

      final entered = await BrowserDialogs.showArchivePasswordPrompt(
        context,
        wrongPassword: result.status == ArchiveOpenStatus.wrongPassphrase,
      );
      if (entered == null || !mounted) return null;

      archive = archive.withPassphrase(entered);
      _navNotifier.updateArchiveContext(archive);
    }
    return null;
  }

  Future<ArchiveContext?> _ensureArchivePasswordForExtraction(
    ArchiveContext archive,
  ) async {
    if (archive.passphrase?.isNotEmpty == true) return archive;

    ArchiveEntryInfo? encryptedEntry;
    for (final entry in archive.allEntries) {
      if (!entry.isDirectory &&
          entry.isEncrypted &&
          entry.uncompressedSize > 0) {
        encryptedEntry = entry;
        break;
      }
    }
    if (encryptedEntry == null) return archive;

    var wrongPassword = false;
    while (mounted) {
      final entered = await BrowserDialogs.showArchivePasswordPrompt(
        context,
        wrongPassword: wrongPassword,
      );
      if (entered == null || !mounted) return null;
      if (entered.isEmpty) {
        wrongPassword = true;
        continue;
      }

      final candidate = await archive.rescanWithPassphrase(entered);
      if (candidate.status == ArchiveOpenStatus.ok) return candidate;
      if (candidate.status == ArchiveOpenStatus.passphraseRequired ||
          candidate.status == ArchiveOpenStatus.wrongPassphrase) {
        wrongPassword = candidate.status == ArchiveOpenStatus.wrongPassphrase;
        continue;
      }

      _setStatus(
        context.l10n.failedToReadArchive(
          candidate.indexResult.errorMessage.isEmpty
              ? 'Archive scan failed'
              : candidate.indexResult.errorMessage,
        ),
        error: true,
      );
      return null;
    }
    return null;
  }

  void _clearSearch() => _searchNotifier.clear();

  void _onSearchQueryChanged(String query) {
    _searchNotifier.onQueryChanged(
      query,
      container: widget.container,
      currentDirPath: _currentDirPath,
      showHiddenFiles: _toolbarConfig.showHiddenFiles,
      archiveContext: _archiveContext,
      archiveRootPath: _archiveRootPathForSearch,
    );
  }

  void _onDeepSearchToggled(bool enabled) {
    _searchNotifier.onDeepSearchToggled(
      enabled,
      container: widget.container,
      currentDirPath: _currentDirPath,
      showHiddenFiles: _toolbarConfig.showHiddenFiles,
      archiveContext: _archiveContext,
      archiveRootPath: _archiveRootPathForSearch,
    );
  }

  void _enterDirectory(RawEntry entry) {
    final currentOffset = _browserScrollController.hasClients
        ? _browserScrollController.offset
        : 0.0;
    final newPath = _fullPathOf(entry);
    _navNotifier.enterDirectory(
      entry,
      newPath: newPath,
      layoutMode: _getLayoutModeForFolder(newPath),
      currentScrollOffset: currentOffset,
    );
    final newSort = _getSortStateForFolder(newPath);
    _sortNotifier.restore(newSort.sortBy, newSort.sortAscending);
    _resetBrowserScrollController(initialOffset: 0.0);
    _clearSearch();
    _loadDirectoryContents(newPath);
  }

  Future<void> _navigateToPath(String fullPath, {required bool isDir}) async {
    _signalActivity();
    if (isSelectionMode) exitSelectionMode();
    final segments = fullPath.isEmpty ? [] : fullPath.split('/');
    if (segments.isEmpty) return;
    if (isDir) {
      final newPath = _navNotifier.navigateToPath(
        widget.container,
        fullPath,
        isDir: true,
        rootLabel: context.l10n.rootFolderLabel,
        layoutMode: _getLayoutModeForFolder(fullPath),
        resolveLayoutMode: _getLayoutModeForFolder,
      );
      final dirSort = _getSortStateForFolder(fullPath);
      _sortNotifier.restore(dirSort.sortBy, dirSort.sortAscending);
      _clearSearch();
      await _loadDirectoryContents(newPath);
    } else {
      final parentPath = segments.length > 1
          ? segments.sublist(0, segments.length - 1).join('/')
          : '';
      final fileName = segments.last;
      _navNotifier.navigateToPath(
        widget.container,
        fullPath,
        isDir: false,
        rootLabel: context.l10n.rootFolderLabel,
        layoutMode: _getLayoutModeForFolder(parentPath),
        resolveLayoutMode: _getLayoutModeForFolder,
      );
      final parentSort = _getSortStateForFolder(parentPath);
      _sortNotifier.restore(parentSort.sortBy, parentSort.sortAscending);
      _clearSearch();
      await _loadDirectoryContents(parentPath);
      final fileEntry = _currentItems.firstWhere(
        (e) => !e.isDir && e.name == fileName,
        orElse: () => RawEntry(
          name: fileName,
          isDir: false,
          sizeBytes: 0,
          modifiedSecs: 0,
        ),
      );
      await _handleFileTap(fileEntry);
    }
  }

  void _navigateUp() {
    if (_atRoot) return;
    final targetSegment = _pathStack.length >= 2
        ? _pathStack[_pathStack.length - 2]
        : null;
    final savedOffset = targetSegment?.scrollOffset ?? 0.0;
    _resetBrowserScrollController(initialOffset: savedOffset);

    final parentPath = targetSegment?.fatPath ?? '';
    final parentLayoutMode = _getLayoutModeForFolder(parentPath);

    final newPath = _navNotifier.navigateUp(layoutMode: parentLayoutMode);
    if (newPath == null) return;
    final parentSort = _getSortStateForFolder(parentPath);
    _sortNotifier.restore(parentSort.sortBy, parentSort.sortAscending);
    _clearSearch();
    _loadDirectoryContents(newPath);
  }

  /// Back arrow in the toolbar at the root. It is an explicit control, so it
  /// keeps going to Home (or closing the route) whatever the tab's origin;
  /// system back uses [_resolveBack] instead.
  bool _handleBackAtRoot() {
    final workspace = widget.workspaceConfig;
    // An app-root workspace (decoy mode) has nothing beneath it: at the root
    // the system leaves the app (see canPop in build).
    if (workspace.appRoot) return false;
    if (ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      // With tabs enabled, the location remains in its tab at the root.
      return false;
    }

    final tabs = ref.read(browserTabsProvider(workspace).notifier);
    if (tabs.returnToDashboardAtRoot(_tabId)) return true;
    if (workspace.includeDashboardTab) {
      tabs.replaceActiveWithDashboard();
      return true;
    }

    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return false;
    navigator.pop();
    return true;
  }

  BrowserTabOrigin get _tabOrigin =>
      _workspaceState.tabs
          .where((tab) => tab.tabId == _tabId)
          .firstOrNull
          ?.origin ??
      BrowserTabOrigin.other;

  /// What system back does right now, read from live state.
  BrowserBackAction _resolveBack() => resolveBrowserBack(
    selectionMode: isSelectionMode,
    searchActive: _searchActive,
    atRoot: _atRoot,
    origin: _tabOrigin,
    appRoot: widget.workspaceConfig.appRoot,
    hostsHome: widget.workspaceConfig.includeDashboardTab,
    tabsEnabled: ref.read(appSettingsControllerProvider).settings.useBrowserTabs,
  );

  void _onSystemBack() {
    switch (_resolveBack()) {
      case BrowserBackAction.exitSelection:
        exitSelectionMode();
      case BrowserBackAction.clearSearch:
        setState(() => _clearSearch());
      case BrowserBackAction.navigateUp:
        _navigateUp();
      case BrowserBackAction.returnHome:
        final tabs = _workspaceNotifier;
        if (!tabs.returnToDashboardAtRoot(_tabId)) {
          tabs.replaceActiveWithDashboard();
        }
      case BrowserBackAction.popRoute:
        final navigator = Navigator.of(context);
        if (navigator.canPop()) navigator.pop();
      case BrowserBackAction.stay:
      case BrowserBackAction.leave:
        break;
    }
  }

  bool get _canPreviewFolderBackGesture =>
      !_atRoot && !isSelectionMode && !_searchActive;

  /// Whether this screen should answer predictive-back events: its route is
  /// on top AND (inside tabs) it is the visible tab. Every mounted tab is a
  /// WidgetsBindingObserver, so without the tab check the first-registered
  /// hidden tab would swallow the gesture meant for the visible one.
  bool get _isOwnRouteCurrent =>
      (ModalRoute.of(context)?.isCurrent ?? false) && _isActiveTab;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!_isOwnRouteCurrent) return false;
    if (backEvent.isButtonEvent) return false;
    if (!_canPreviewFolderBackGesture) return false;
    final targetSegment = _pathStack.length >= 2
        ? _pathStack[_pathStack.length - 2]
        : null;
    final savedOffset = targetSegment?.scrollOffset ?? 0.0;
    _resetBackGesturePreviewScrollController(initialOffset: savedOffset);

    final parentPath = targetSegment?.fatPath ?? '';
    final parentLayoutMode = _getLayoutModeForFolder(parentPath);

    return _navNotifier.startBackGesture(
      backEvent.progress,
      layoutMode: parentLayoutMode,
    );
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_isOwnRouteCurrent) return;
    _navNotifier.updateBackGestureProgress(backEvent.progress);
  }

  @override
  void handleCancelBackGesture() {
    if (!_isOwnRouteCurrent) return;
    _navNotifier.cancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    if (!_isOwnRouteCurrent) return;
    final targetPath = _backGesturePreviewDirPath;
    _navNotifier.commitBackGesture();
    _navigateUp();
    if (targetPath != null) _hideBackGesturePreviewWhenReady(targetPath);
  }

  Future<void> _hideBackGesturePreviewWhenReady(String targetPath) async {
    while (mounted && _isLoading && _currentDirPath == targetPath) {
      await Future.delayed(const Duration(milliseconds: 30));
    }
    if (!mounted) return;
    _navNotifier.clearBackGesturePreview();
  }

  void _jumpTo(int index) {
    if (index == _pathStack.length - 1) return;
    final targetSegment = index >= 0 && index < _pathStack.length
        ? _pathStack[index]
        : null;
    final savedOffset = targetSegment?.scrollOffset ?? 0.0;
    _resetBrowserScrollController(initialOffset: savedOffset);
    final newPath = _navNotifier.jumpTo(index);
    if (newPath == null) return;
    _navNotifier.setLayoutMode(_getLayoutModeForFolder(newPath));
    final jumpSort = _getSortStateForFolder(newPath);
    _sortNotifier.restore(jumpSort.sortBy, jumpSort.sortAscending);
    _clearSearch();
    _loadDirectoryContents(newPath);
  }

  // ── Selection (FileBrowserSelection controller) ──────────────────────────
  Set<RawEntry> get selectedItems =>
      ref.read(fileBrowserSelectionProvider(_stateKey)).items;
  // The action bar can aggregate selected items across tabs, but each tab
  // enters selection mode only after the user selects something in that tab.
  bool get isSelectionMode =>
      ref.read(fileBrowserSelectionProvider(_stateKey)).isSelectionMode;
  int get selectedFolderCount =>
      ref.read(fileBrowserSelectionProvider(_stateKey)).selectedFolderCount;
  int get selectedTotalBytes =>
      ref.read(fileBrowserSelectionProvider(_stateKey)).selectedTotalBytes;
  bool get hasPendingFolderSizes =>
      ref.read(fileBrowserSelectionProvider(_stateKey)).hasPendingFolderSizes;

  List<_SelectedBrowserEntry> get _selectedBrowserEntries {
    final tabs = _workspaceState.tabs;
    return [
      for (final tab in tabs)
        if (!tab.isDashboard)
          for (final entry
              in ref.read(fileBrowserSelectionProvider(tab.tabId)).items)
            (
              stateKey: tab.tabId,
              container: tab.container!,
              currentDirPath: ref
                  .read(fileBrowserNavigationProvider(tab.tabId))
                  .currentDirPath,
              entry: entry,
              insideArchive:
                  ref
                      .read(fileBrowserNavigationProvider(tab.tabId))
                      .archiveContext !=
                  null,
            ),
    ];
  }

  List<_SelectedBrowserEntry> get _uniqueSelectedBrowserEntries {
    final seen = <(int, String)>{};
    final unique = <_SelectedBrowserEntry>[];
    for (final item in _selectedBrowserEntries) {
      final path = fullPathOf(item.entry, item.currentDirPath);
      if (seen.add((item.container.volId, path))) unique.add(item);
    }
    return unique;
  }

  int get _selectedBrowserEntryCount => _selectedBrowserEntries.length;

  int get _allSelectedTotalBytes {
    final keys = _workspaceState.tabs
        .where((tab) => !tab.isDashboard)
        .map((tab) => tab.tabId)
        .toList();
    return keys.fold<int>(
      0,
      (total, key) =>
          total +
          ref.read(fileBrowserSelectionProvider(key)).selectedTotalBytes,
    );
  }

  bool get _anySelectedFolderSizePending {
    final keys = _workspaceState.tabs
        .where((tab) => !tab.isDashboard)
        .map((tab) => tab.tabId)
        .toList();
    return keys.any(
      (key) =>
          ref.read(fileBrowserSelectionProvider(key)).hasPendingFolderSizes,
    );
  }

  void toggleSelectItem(RawEntry item) {
    ref
        .read(fileBrowserSelectionProvider(_stateKey).notifier)
        .toggleSelectItem(item);
    if (selectedFolderCount > 0) {
      fetchFolderSizes(widget.container, _currentDirPath);
    }
  }

  void setSelectedItems(Set<RawEntry> newSelection) {
    ref
        .read(fileBrowserSelectionProvider(_stateKey).notifier)
        .setSelectedItems(newSelection);
  }

  void exitSelectionMode() {
    for (final tab in _workspaceState.tabs) {
      if (tab.isDashboard) continue;
      ref
          .read(fileBrowserSelectionProvider(tab.tabId).notifier)
          .exitSelectionMode();
    }
  }

  Future<void> fetchFolderSizes(
    MountedContainer container,
    String currentDirPath,
  ) => ref
      .read(fileBrowserSelectionProvider(_stateKey).notifier)
      .fetchFolderSizes(container, currentDirPath);

  // ── Sort (FileBrowserSort controller) ─────────────────────────────────────
  SortBy get sortBy => ref.read(fileBrowserSortProvider(_stateKey)).sortBy;
  bool get sortAscending =>
      ref.read(fileBrowserSortProvider(_stateKey)).sortAscending;
  FileBrowserSort get _sortNotifier =>
      ref.read(fileBrowserSortProvider(_stateKey).notifier);

  void setSort(SortBy by) =>
      ref.read(fileBrowserSortProvider(_stateKey).notifier).setSort(by);

  int compareItems(RawEntry ea, RawEntry eb) =>
      ref.read(fileBrowserSortProvider(_stateKey)).compare(ea, eb);

  void _handleDirTap(RawEntry entry) {
    _signalActivity();
    if (isSelectionMode) {
      toggleSelectItem(entry);
    } else {
      _enterDirectory(entry);
    }
  }

  /// Tapping directly on a row's leading icon/thumbnail always toggles that
  /// item's selection (entering selection mode on the first tap, same as a
  /// long-press would), regardless of whether the row body would otherwise
  /// open the item. This mirrors [_handleItemLongPress]'s haptic feedback
  /// so both entry points into selection feel the same.
  void _handleIconTap(RawEntry entry) {
    _signalActivity();
    if (!isSelectionMode && _selectedBrowserEntryCount > 0) {
      if (entry.isDir) {
        _handleDirTap(entry);
      } else {
        unawaited(_handleFileTap(entry));
      }
      return;
    }
    HapticFeedback.selectionClick();
    toggleSelectItem(entry);
  }

  Future<void> _handleFileTap(RawEntry entry) async {
    ThumbnailConcurrency.videoLimiter.cancelAll();
    if (MediaViewerConstants.isVideo(entry.name)) {
      await PlaybackThrottleController.setActive(true);
    }
    _signalActivity();
    if (isSelectionMode) {
      toggleSelectItem(entry);
      return;
    }
    final fullPath = _fullPathOf(entry);
    final parts = entry.name.split('.');
    final ext =
        ArchiveService.splitPartExtension(entry.name) ??
        (parts.length > 1
            ? parts.last.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim()
            : '');
    if (ArchiveService.opensOnTap(ext)) {
      await _openArchive(fullPath, entry.name);
      return;
    }
    if (_archiveContext != null) {
      _signalActivity();
      _navNotifier.setLoading(true);
      try {
        final archiveRootPath =
            _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
        String subPath = '';
        if (fullPath.length > archiveRootPath.length) {
          subPath = fullPath.substring(archiveRootPath.length);
          if (subPath.startsWith('/')) subPath = subPath.substring(1);
        }
        if (mounted) {
          final opensInNativeViewer =
              ext == 'pdf' ||
              MediaViewerConstants.isImage(entry.name) ||
              MediaViewerConstants.isVideo(entry.name) ||
              MediaViewerConstants.isAudio(entry.name);
          final opensInTextEditor = const {
            'txt',
            'md',
            'markdown',
            'csv',
            'json',
            'xml',
          }.contains(ext);
          if (opensInNativeViewer || opensInTextEditor) {
            final stageResult = await _stageArchiveEntryWithPassword(subPath);
            final previewPath = stageResult?.path;
            if (previewPath != null) {
              if (opensInTextEditor) {
                await _openArchiveTextPreview(entry.name, previewPath);
              } else {
                await _openArchivePreview(entry.name, previewPath);
              }
            } else if (mounted) {
              _navNotifier.setLoading(false);
              if (stageResult != null) {
                _setStatus(
                  context.l10n.failedToReadFileFromArchive,
                  error: true,
                );
              }
            }
          } else {
            final extractResult = await _extractArchiveEntryWithPassword(
              subPath,
            );
            _navNotifier.setLoading(false);
            if (extractResult?.status == ArchiveOpenStatus.ok &&
                extractResult?.data != null) {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SkinAreaScope(
                    area: SkinArea.files,
                    child: ArchiveFileViewer(
                      bytes: extractResult!.data!,
                      fileName: entry.name,
                    ),
                  ),
                ),
              );
            } else if (extractResult != null) {
              _setStatus(context.l10n.failedToReadFileFromArchive, error: true);
            }
          }
        }
      } catch (e) {
        if (mounted) {
          _navNotifier.setLoading(false);
          _setStatus(
            context.l10n.failedToExtractFile('${e.runtimeType}'),
            error: true,
          );
        }
      }
      return;
    }
    if (VaultItemType.values.any((t) => t.name.toLowerCase() == ext)) {
      final item = await ref
          .read(vaultItemsServiceProvider)
          .loadItem(widget.container, fullPath);
      if (item != null) {
        final baseName = entry.name.substring(0, entry.name.lastIndexOf('.'));
        item.title = baseName;
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VaultItemDetailScreen(
                container: widget.container,
                item: item,
                filePath: fullPath,
              ),
            ),
          );
          _loadDirectoryContents(_currentDirPath);
        }
      } else {
        _setStatus(context.l10n.failedToReadSecureItem, error: true);
      }
      return;
    }
    final settings = await ref.read(appSettingsServiceProvider).loadSettings();
    final pref = settings.extensionPreferences[ext];
    // HTML is still a native, session-based viewer with no local-storage
    // counterpart (see LocalFileIoBackend's doc comment) -- checked ahead
    // of `pref` so a per-extension preference saved while browsing a real
    // vault (e.g. "always use the built-in viewer for .html") can't route
    // a local file into a viewer that can't render it. The device's own
    // browser already renders a real, already-plaintext HTML file fine, so
    // hand it off there instead. Video and audio are both exempt: the
    // native player reads local files directly off disk via its own local
    // branch (see NativePlayerManager.kt's buildMediaSource --
    // DefaultDataSource.Factory + Uri.fromFile), so they play in-app
    // exactly like vault content. PDF is exempt too: PdfViewerScreen has
    // its own isLocalStorage branch (VaultLocalShareApi.getLocalFileUri ->
    // PdfViewerRouter's localUri path), so it also renders in-app.
    final needsSystemAppForLocal =
        widget.container.isLocalStorage && (ext == 'html' || ext == 'htm');
    // Which viewer/action applies is decided by decideFileOpenAction
    // (file_open_dispatch.dart) -- a pure function of ext/pref/these two
    // booleans, extracted so the branch priority (needsSystemAppForLocal
    // first, then a saved preference, then the extension fallback) is
    // unit-tested directly instead of only reachable by tapping files in
    // a running app. This screen just computes the inputs and performs
    // whichever Navigator.push/side effect the result calls for.
    final action = decideFileOpenAction(
      ext: ext,
      extensionPreference: pref,
      needsSystemAppForLocal: needsSystemAppForLocal,
      isSupportedMedia: _isSupportedMedia(entry.name),
    );
    switch (action) {
      case OpenInEditor():
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TextEditorScreen(
              container: widget.container,
              filePath: fullPath,
            ),
          ),
        );
        _loadDirectoryContents(_currentDirPath);
      case OpenInMediaViewer():
        await _openMediaViewer(entry.name, fullPath);
      case OpenInPdfViewer():
        await _openPdfViewer(fullPath);
      case OpenInHtmlViewer():
        _openHtmlViewer(fullPath);
      case OpenWithSystemApp(packageName: final packageName):
        _openFileWithApp(entry.name, fullPath, packageName: packageName);
      case InstallApk():
        await _installApk(entry.name, fullPath);
      case OpenAsArchive():
        // An APK is a ZIP; the archive browser sniffs the format from the
        // bytes, so the same path a .zip takes works unchanged.
        await _openArchive(fullPath, entry.name);
      case ShowApkOpenChooser():
        if (!mounted) return;
        await _showApkOpenChooser(entry.name, fullPath, ext);
      case ShowOpenWithDialog():
        if (!mounted) return;
        await _showOpenWithDialog(entry.name, fullPath, ext, settings);
    }
  }

  Future<void> _openArchivePreview(String fileName, String previewPath) async {
    final archiveApi = ref.read(vaultArchiveApiProvider);
    final preview = ArchivePreviewFile.fromNativePath(previewPath);
    try {
      if (!mounted) return;

      final previewFile = preview;
      final previewContainer = buildLocalStorageContainer(
        rootPath: p.dirname(previewFile.path),
        displayName: fileName,
        readOnly: true,
      );
      final stagedFileName = p.basename(previewFile.path);

      // A normal open reaches the viewer with the image's aspect ratio already
      // cached (the grid's thumbnails put it there). An archive preview has no
      // thumbnails -- they are disabled so nothing from the archive reaches a
      // cache -- so the viewer would lay the image out blind and only settle
      // once it had decoded the picture, in the middle of the first pinch.
      // Read the size from the staged file's header and seed the cache so the
      // preview starts from the same geometry as any other image.
      if (MediaViewerConstants.isImage(fileName)) {
        final size = await previewFile.readImageSize();
        if (size != null) {
          MediaAspectRatioCache.put(
            previewContainer,
            stagedFileName,
            size.$1,
            size.$2,
          );
        }
      }
      if (!mounted) return;
      _navNotifier.setLoading(false);

      if (fileName.toLowerCase().endsWith('.pdf')) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              container: previewContainer,
              filePath: stagedFileName,
            ),
          ),
        );
      } else {
        await Navigator.push(
          context,
          _buildMediaViewerRoute(
            mediaFiles: [stagedFileName],
            initialIndex: 0,
            container: previewContainer,
            isArchivePreview: true,
          ),
        );
      }
    } finally {
      await preview.discard(secureDelete: archiveApi.discardBrowseFile);
    }
  }

  Future<void> _openArchiveTextPreview(
    String fileName,
    String previewPath,
  ) async {
    final archiveApi = ref.read(vaultArchiveApiProvider);
    final preview = ArchivePreviewFile.fromNativePath(previewPath);
    try {
      if (!mounted) return;

      final previewContainer = buildLocalStorageContainer(
        rootPath: p.dirname(preview.path),
        displayName: fileName,
        readOnly: true,
      );
      _navNotifier.setLoading(false);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TextEditorScreen(
            container: previewContainer,
            filePath: p.basename(preview.path),
          ),
        ),
      );
    } finally {
      await preview.discard(secureDelete: archiveApi.discardBrowseFile);
    }
  }

  Future<void> _openPdfViewer(String fullPath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PdfViewerScreen(container: widget.container, filePath: fullPath),
      ),
    );
    _loadDirectoryContents(_currentDirPath);
  }

  void _openHtmlViewer(String fullPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HtmlViewerScreen(container: widget.container, filePath: fullPath),
      ),
    );
  }

  Route<void> _buildMediaViewerRoute({
    required List<String> mediaFiles,
    required int initialIndex,
    MountedContainer? container,
    bool isArchivePreview = false,
  }) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) =>
          MediaViewerScreen(
            container: container ?? widget.container,
            mediaFiles: mediaFiles,
            initialIndex: initialIndex,
            startingFolder: isArchivePreview ? '' : _currentDirPath,
            thumbnailQuality: _resolvedThumbnailQuality,
            thumbnailCacheMode: isArchivePreview
                ? ThumbnailCacheMode.disabled
                : _resolvedThumbnailCacheMode,
            mediaFilter: _currentFilter,
            sortBy: sortBy,
            sortAscending: sortAscending,
            pinnedPaths: _pinnedPaths,
            onCurrentFileChanged: isArchivePreview ? null : _scrollToItem,
            isArchivePreview: isArchivePreview,
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
    );
  }

  Future<void> _editImage(String fileName, String fullPath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(
          container: widget.container,
          filePath: fullPath,
          thumbnailQuality: _resolvedThumbnailQuality,
        ),
      ),
    );
    if (!mounted) return;
    _loadDirectoryContents(_currentDirPath);
  }

  Future<void> _editVideo(String fullPath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VideoEditorScreen(container: widget.container, filePath: fullPath),
      ),
    );
    if (!mounted) return;
    // The editor writes new files next to the original.
    _loadDirectoryContents(_currentDirPath);
  }

  Future<void> _editAudio(String fullPath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AudioEditorScreen(container: widget.container, filePath: fullPath),
      ),
    );
    if (!mounted) return;
    // The editor writes new files next to the original.
    _loadDirectoryContents(_currentDirPath);
  }

  Future<void> _openMediaViewer(String fileName, String fullPath) async {
    List<String> mediaFiles = [fullPath];
    int initialIndex = 0;

    if (_toolbarConfig.autoStartPlaylistMode) {
      final query = _searchQuery.trim().toLowerCase();
      final baseItems = (_searchActive && _isDeepSearch && query.isNotEmpty)
          ? _deepSearchResults
          : _currentItems;
      final sortedItems = baseItems.where((item) {
        if (!_toolbarConfig.showHiddenFiles && isHiddenEntryName(item.name)) {
          return false;
        }
        final name = item.name;
        if (query.isNotEmpty && !name.toLowerCase().contains(query)) {
          return false;
        }
        if (item.isDir) return false;
        if (!_matchesFilter(name) || !_isSupportedMedia(name)) return false;
        return true;
      }).toList()..sort(_compareOverall);

      final resolvedMedia = sortedItems.map((e) {
        if (_searchActive && _isDeepSearch && e.name.contains('/')) {
          return e.name;
        }
        return _currentDirPath.isEmpty ? e.name : '$_currentDirPath/${e.name}';
      }).toList();

      final foundIdx = resolvedMedia.indexOf(fullPath);
      if (foundIdx != -1) {
        mediaFiles = resolvedMedia;
        initialIndex = foundIdx;
      }
    }

    final initialOffset = _browserScrollController.hasClients
        ? _browserScrollController.offset
        : null;
    String lastViewedFile = fullPath;
    bool filesDeletedInViewer = false;

    final result = await Navigator.push<bool>(
      context,
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) =>
            MediaViewerScreen(
              container: widget.container,
              mediaFiles: mediaFiles,
              initialIndex: initialIndex,
              startingFolder: _currentDirPath,
              thumbnailQuality: _resolvedThumbnailQuality,
              thumbnailCacheMode: _resolvedThumbnailCacheMode,
              mediaFilter: _currentFilter,
              sortBy: sortBy,
              sortAscending: sortAscending,
              pinnedPaths: _pinnedPaths,
              onCurrentFileChanged: (newFile) {
                lastViewedFile = newFile;
                _scrollToItem(newFile);
              },
              onFileDeleted: (_) => filesDeletedInViewer = true,
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

    // If the user viewed the same file without swiping to another,
    // restore the exact pixel offset so no sub-pixel rounding drift occurs.
    if (lastViewedFile == fullPath &&
        initialOffset != null &&
        _browserScrollController.hasClients) {
      // Navigator completes the pushed route's result while its reverse
      // transition is being finalized. Defer the scroll notification until
      // the next frame so it cannot bubble through an inactive route element
      // (which can happen when returning from an external app as well).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_browserScrollController.hasClients) return;
        if (ModalRoute.of(context)?.isCurrent == false) return;

        final position = _browserScrollController.position;
        if (!position.hasContentDimensions) return;
        final restoredOffset = initialOffset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if ((position.pixels - restoredOffset).abs() > 0.5) {
          _browserScrollController.jumpTo(restoredOffset);
        }
      });
    }

    // Only reload directory contents if files were actually modified/deleted in the viewer
    if (result == true || filesDeletedInViewer) {
      _loadDirectoryContents(_currentDirPath, refresh: true);
      _loadToolbarConfig();
    }
  }

  /// Asks whether an `.apk` should go to the package installer or open as a
  /// ZIP, and (optionally) remembers the answer for `.apk` -- stored as the
  /// `'installer'` / `'archive'` extension preferences, which
  /// [decideFileOpenAction] reads on the next tap and the file-associations
  /// settings list can clear.
  Future<void> _showApkOpenChooser(
    String fileName,
    String fullPath,
    String ext,
  ) async {
    final cleanExt = ext.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim();
    final choice = await OpenWithDialog.showApkChooser(
      context,
      fileName: fileName,
      ext: cleanExt,
    );
    final action = choice.action;
    if (action == null) return;
    if (choice.remember && cleanExt.isNotEmpty) {
      await _saveExtensionPreference(cleanExt, action);
    }
    if (!mounted) return;
    if (action == 'installer') {
      await _installApk(fileName, fullPath);
    } else if (action == 'archive') {
      await _openArchive(fullPath, fileName);
    }
  }

  Future<void> _showOpenWithDialog(
    String fileName,
    String fullPath,
    String ext,
    AppSettings settings,
  ) async {
    // Every explicit "Open with" -- the item's 3-dots sheet and the selection
    // menu both end up here -- asks installer vs. ZIP for an APK, even when a
    // choice was remembered for plain taps. It's the way back to the other
    // option once "remember" has been ticked.
    if (ext.toLowerCase() == 'apk') {
      await _showApkOpenChooser(fileName, fullPath, ext);
      return;
    }
    final choice = await OpenWithDialog.show(
      context,
      fileName: fileName,
      ext: ext,
    );
    final cleanExt = ext.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim();

    if (choice.action == 'editor') {
      if (choice.remember && cleanExt.isNotEmpty) {
        await _saveExtensionPreference(cleanExt, 'editor');
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TextEditorScreen(container: widget.container, filePath: fullPath),
        ),
      );
      _loadDirectoryContents(_currentDirPath);
    } else if (choice.action == 'media') {
      if (choice.remember && cleanExt.isNotEmpty) {
        await _saveExtensionPreference(cleanExt, 'media');
      }
      if (!mounted) return;
      await _openMediaViewer(fileName, fullPath);
    } else if (choice.action == 'external') {
      if (choice.remember && cleanExt.isNotEmpty) {
        await _saveExtensionPreference(cleanExt, 'external');
        _vaultEvents.onAppSelectedCallback = (selectedExt, pkg) async {
          final normalized = selectedExt
              .toLowerCase()
              .replaceFirst(RegExp(r'^\.+'), '')
              .trim();
          if (normalized == cleanExt) {
            await _saveExtensionPreference(cleanExt, 'package:$pkg');
            _vaultEvents.onAppSelectedCallback = null;
          }
        };
      }
      _openFileWithApp(fileName, fullPath);
    } else if (choice.action == 'open_as') {
      if (choice.mimeType != null) {
        _openFileWithApp(fileName, fullPath, mimeType: choice.mimeType!);
      }
    }
  }

  // ── "Play media here" recursive scan state ────────────────────────────
  // The scan algorithm itself now lives in MediaScanService (see the note
  // above _fadeScrimOpacity) -- this is just the "kick it off, show
  // progress, allow cancel" glue tying that service to this screen's
  // status banner. A fresh CancellationToken per attempt is the direct
  // replacement for the old shared generation counter: cancelling the
  // previous token before handing out a new one gives the same
  // "starting a new scan invalidates any scan already in flight"
  // guarantee the counter used to.
  CancellationToken? _mediaScanToken;
  bool _mediaScanInProgress = false;

  void _cancelMediaScan() => _mediaScanToken?.cancel();

  Future<void> _startMediaViewerFromCurrentLocation() async {
    _signalActivity();
    final sortedItems = _currentItems.where((e) {
      if (!_toolbarConfig.showHiddenFiles && isHiddenEntryName(e.name)) {
        return false;
      }
      return !e.isDir && _matchesFilter(e.name);
    }).toList()..sort(_compareOverall);

    final localMedia = sortedItems
        .map((e) => e.name)
        .where(_isSupportedMedia)
        .toList();
    if (localMedia.isNotEmpty) {
      final resolvedPaths = localMedia.map(_joinPath).toList();
      await Navigator.push(
        context,
        _buildMediaViewerRoute(mediaFiles: resolvedPaths, initialIndex: 0),
      );
      if (mounted) {
        _loadDirectoryContents(_currentDirPath);
        _loadToolbarConfig();
      }
      return;
    }

    _mediaScanToken?.cancel();
    final token = CancellationToken();
    _mediaScanToken = token;
    setState(() => _mediaScanInProgress = true);
    _navNotifier.setLoading(true);
    _navNotifier.setStatus(context.l10n.scanningSubfoldersForMedia);
    try {
      final result = await ref
          .read(mediaScanServiceProvider)
          .scan(
            container: widget.container,
            startPath: _currentDirPath,
            token: token,
            showHiddenFiles: _toolbarConfig.showHiddenFiles,
            sortBy: sortBy,
            sortAscending: sortAscending,
            pinnedPaths: _pinnedPaths,
            isSupportedMedia: _isSupportedMedia,
            onProgress: (foldersChecked) {
              if (!mounted) return;
              _navNotifier.setStatus(
                context.l10n.scanningSubfoldersForMediaProgress(foldersChecked),
              );
            },
          );
      if (!mounted) return;
      if (result.cancelled) {
        _setStatus(context.l10n.mediaScanCancelled);
        return;
      }
      if (result.mediaPaths.isNotEmpty) {
        _clearStatus();
        await Navigator.push(
          context,
          _buildMediaViewerRoute(
            mediaFiles: result.mediaPaths,
            initialIndex: 0,
          ),
        );
        if (mounted) {
          _loadDirectoryContents(_currentDirPath);
          _loadToolbarConfig();
        }
      } else if (result.limitReached) {
        _setStatus(context.l10n.mediaScanLimitReached, error: true);
      } else {
        _setStatus(context.l10n.noMediaFilesFoundRecursive, error: true);
      }
    } catch (e) {
      if (mounted)
        _setStatus(context.l10n.failedToScanSubfolders('$e'), error: true);
    } finally {
      if (mounted) {
        _navNotifier.setLoading(false);
        setState(() => _mediaScanInProgress = false);
      }
      if (identical(_mediaScanToken, token)) _mediaScanToken = null;
    }
  }

  void _handleItemLongPress(RawEntry entry) {
    _signalActivity();
    if (!isSelectionMode) {
      HapticFeedback.selectionClick();
      setSelectedItems({...selectedItems, entry});
      if (selectedFolderCount > 0) {
        fetchFolderSizes(widget.container, _currentDirPath);
      }
    } else if (!selectedItems.contains(entry)) {
      HapticFeedback.selectionClick();
      toggleSelectItem(entry);
    }
  }

  bool _isSupportedMedia(String fileName) =>
      MediaViewerConstants.isSupported(fileName);

  /// Hands an APK to the system package installer (see
  /// [VaultFileIoApi.installApk]).
  ///
  /// The two non-install outcomes -- the user hasn't allowed this app to
  /// install apps, or the device has no installer at all -- are already
  /// surfaced natively, next to the settings page the first one opens, so
  /// they're deliberately not reported a second time here. Only an
  /// outright failure of the call gets a status message.
  Future<void> _installApk(String cleanName, String fullPath) async {
    _signalActivity();
    try {
      final outcome = await ref
          .read(vaultFileIoApiProvider)
          .installApk(widget.container, fullPath);
      if (outcome == null && mounted) {
        _setStatus(context.l10n.couldNotOpenFile(cleanName), error: true);
      }
    } catch (_) {
      if (mounted) {
        _setStatus(context.l10n.couldNotOpenFile(cleanName), error: true);
      }
    }
  }

  Future<void> _openFileWithApp(
    String cleanName,
    String fullPath, {
    String? packageName,
    String? mimeType,
  }) async {
    _signalActivity();
    try {
      // Local storage has no vault session to serve the file from --
      // VaultLocalShareApi exposes the real path directly via its own
      // FileProvider instead (see vault_local_share_api.dart). It has no
      // packageName param (no native support for pre-picking an app for a
      // real file), so that preference is simply not applied for local
      // storage rather than failing outright.
      final ok = widget.container.isLocalStorage
          ? await ref
                .read(vaultLocalShareApiProvider)
                .openLocalFileWithApp(
                  p.join(widget.container.uri, fullPath),
                  mimeType: mimeType,
                )
          : await ref
                .read(vaultFileIoApiProvider)
                .openWithApp(
                  widget.container,
                  fullPath,
                  packageName: packageName,
                  mimeType: mimeType,
                );
      if (!ok && mounted) {
        _setStatus(context.l10n.noAppFoundForFileType, error: true);
      }
    } catch (_) {
      if (mounted) {
        _setStatus(context.l10n.couldNotOpenFile(cleanName), error: true);
      }
    }
  }

  /// Lower-case extensions of Item Vault pseudo-files (passwords, secure
  /// notes, etc. -- see [VaultItemType]). Share never hands these out: not as
  /// loose files, and not inside a shared folder's zip either, which is why
  /// they're forwarded to the native side alongside the folder paths.
  static final List<String> _vaultItemExtensions = [
    for (final t in VaultItemType.values) t.name.toLowerCase(),
  ];

  /// Shares every real file and folder in the current selection with another
  /// app via the system share sheet, skipping vault-item pseudo-files
  /// (passwords, secure notes, etc. -- see [VaultItemType]) the same way
  /// [_openFileWithApp] does for a single file. Folders are shared too, each
  /// as one zip, in every kind of container. Unlike [_openFileWithApp], this
  /// silently drops just the non-shareable entries rather than aborting
  /// the whole action, so sharing five photos alongside one accidentally
  /// co-selected password entry still shares the five photos.
  Future<void> _shareSelected() async {
    final entries = _uniqueSelectedBrowserEntries
        .where((item) => !item.insideArchive)
        .toList();
    exitSelectionMode();

    final shareable = entries.where((item) {
      final e = item.entry;
      if (e.isDir) return true;
      final parts = e.name.split('.');
      final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
      return !VaultItemType.values.any((t) => t.name.toLowerCase() == ext);
    }).toList();

    if (shareable.isEmpty) {
      if (mounted) {
        _setStatus(context.l10n.itemsCannotBeSharedMessage, error: true);
      }
      return;
    }
    final containers = shareable.map((item) => item.container.volId).toSet();
    if (containers.length != 1) {
      if (mounted) {
        _setStatus(context.l10n.couldNotShareFiles, error: true);
      }
      return;
    }
    final source = shareable.first.container;
    final paths = shareable
        .map((item) => fullPathOf(item.entry, item.currentDirPath))
        .toList();
    final directoryPaths = shareable
        .where((item) => item.entry.isDir)
        .map((item) => fullPathOf(item.entry, item.currentDirPath))
        .toList();

    _signalActivity();
    try {
      // Plain on-disk storage has no vault session/ContainerDocumentsProvider
      // to stream from -- VaultLocalShareApi exposes the real files directly
      // via its own FileProvider instead (see vault_local_share_api.dart).
      // A SAF tree is *not* that: it has no real path, so (unlike
      // _openFileWithApp, which keys on isLocalStorage) it goes through
      // VaultFileIoApi.shareFiles' SAF channel along with the vault containers.
      final ok = source.isRawLocal
          ? await ref
                .read(vaultLocalShareApiProvider)
                .shareLocalFiles(
                  shareable
                      .map(
                        (item) => p.join(
                          source.uri,
                          fullPathOf(item.entry, item.currentDirPath),
                        ),
                      )
                      .toList(),
                  directoryPaths: shareable
                      .where((item) => item.entry.isDir)
                      .map(
                        (item) => p.join(
                          source.uri,
                          fullPathOf(item.entry, item.currentDirPath),
                        ),
                      )
                      .toList(),
                )
          : await ref
                .read(vaultFileIoApiProvider)
                .shareFiles(
                  source,
                  paths,
                  directoryPaths: directoryPaths,
                  skipExtensions: _vaultItemExtensions,
                );
      if (!ok && mounted) {
        _setStatus(context.l10n.couldNotShareFiles, error: true);
      }
    } catch (_) {
      if (mounted) {
        _setStatus(context.l10n.couldNotShareFiles, error: true);
      }
    }
  }

  Future<void> _addVaultItem(VaultItemType type) async {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    _signalActivity();
    await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => VaultItemEditScreen(
          container: widget.container,
          type: type,
          currentDirPath: _currentDirPath,
        ),
      ),
    );
    _loadDirectoryContents(_currentDirPath);
  }

  // ── Cross-tab actions ─────────────────────────────────────────────────────

  /// A single selected folder (outside archives) can be opened in a new tab
  /// straight from the selection bar, so a long-press on a folder offers it
  /// too, not only the item's 3-dot sheet.
  _SelectedBrowserEntry? get _singleSelectedFolderForNewTab {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return null;
    }
    final selected = _selectedBrowserEntries;
    if (selected.length != 1 ||
        !selected.single.entry.isDir ||
        selected.single.insideArchive) {
      return null;
    }
    return selected.single;
  }

  void _openFolderInNewTab(
    MountedContainer container,
    String fullPath, {
    TabId? stateKey,
    RawEntry? selectedEntry,
  }) {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    final tabId = _workspaceNotifier.openTab(container, initialPath: fullPath);
    if (tabId == null) {
      _setStatus(
        context.l10n.browserTabLimitReached(kMaxBrowserTabs),
        error: true,
      );
    } else if (stateKey != null && selectedEntry != null) {
      ref
          .read(fileBrowserSelectionProvider(stateKey).notifier)
          .toggleSelectItem(selectedEntry);
    }
  }

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
    exitSelectionMode();
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

  Future<void> _paste() async {
    final clip = ref.read(crossContainerClipboardProvider);
    if (!clip.hasItems) return;
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyCantPaste, error: true);
      return;
    }
    _signalActivity();
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
        items: List.of(clip.items),
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
      return;
    }

    // ── Archive Extract Paste ───────────────────────────────────────────
    if (clip.isArchiveExtract) {
      final archiveName = clip.archiveName ?? 'archive.zip';
      var archiveContext = clip.archiveContext;
      if (archiveContext == null) return;

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
    final groupContainers = <int, MountedContainer>{srcVolId: srcContainer};
    final remainingItems = <(int, ClipboardItem)>[];
    for (final group in groups.entries) {
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
          _bindGroupedDeleteListener(op, container);
        }
      },
    );
  }

  void _bindGroupedDeleteListener(
    FileOperation op,
    MountedContainer container,
  ) {
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
        final deletedPaths = op.itemStatuses
            .where((status) => status.result == FileItemResult.success)
            .map((status) => status.item.path)
            .toSet();
        await ref
            .read(fileBrowserPinsBookmarksProvider(container.volId).notifier)
            .removeDeletedPaths(container, deletedPaths);
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

  Future<void> _compressSelected() async {
    final selected = _uniqueSelectedBrowserEntries
        .where((item) => !item.insideArchive)
        .toList();
    if (selected.isEmpty ||
        selected.map((item) => item.container.volId).toSet().length != 1) {
      return;
    }
    final entries = selected.map((item) => item.entry).toList();
    final source = selected.first.container;
    final currentDirPath = _currentDirPath;
    final existingEntries = _currentItems;
    String stem(RawEntry e) {
      if (e.isDir) return e.name;
      final dot = e.name.lastIndexOf('.');
      return dot > 0 ? e.name.substring(0, dot) : e.name;
    }

    final suggestedName = entries.length == 1
        ? '${stem(entries.first)}.zip'
        : '${currentDirPath.isEmpty ? source.displayName : currentDirPath.split('/').last}.zip';
    exitSelectionMode();
    if (!mounted) return;
    BrowserDialogs.showCreateArchive(
      context,
      container: widget.container,
      currentDirPath: currentDirPath,
      existingEntries: existingEntries,
      suggestedName: suggestedName,
      selectedEntries: entries,
      freeSpace: _freeSpace,
      readOnly: _isReadOnly,
      onCreate:
          (
            destPath,
            format,
            passphrase,
            encryptFilenames,
            compressionLevel,
            compressionMethod,
          ) async {
            final clipItems = selected.map((item) {
              final entry = item.entry;
              final path = fullPathOf(entry, item.currentDirPath);
              return ClipboardItem(
                path: path,
                isDir: entry.isDir,
                sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
                modifiedSecs: entry.modifiedSecs,
              );
            }).toList();

            final archiveName = destPath.split('/').last;
            _clip.setArchiveCreate(
              volId: source.volId,
              displayName: source.displayName,
              clipItems: clipItems,
              archiveName: archiveName,
              format: format,
              passphrase: passphrase,
              encryptFilenames: encryptFilenames,
              compressionLevel: compressionLevel,
              compressionMethod: compressionMethod,
            );
            _setStatus('${context.l10n.verbArchiving}: $archiveName');
          },
    );
  }

  // _performCompress (the old "compress directly, no staging" path) lived
  // here and is now deleted: grepping the whole file for its name found
  // zero call sites, not even a tear-off. Compress now goes entirely
  // through the same stage-in-clipboard-then-paste flow as copy/move/
  // extract (see _compressSelected below, and _paste's "Archive Create
  // Paste" branch) -- this was the pre-migration direct-compress
  // implementation that never got removed once that switch happened.
  // Found during the file-browser-screen decomposition (tech-debt audit,
  // Sept 2026) while mapping this cluster's call graph.

  Future<void> _extractSelectedArchive() async {
    // ── Inside archive: stage selected items for extraction ─────────────
    if (_archiveContext != null) {
      final entries = selectedItems.toList();
      if (entries.isEmpty) return;

      final archivePath =
          _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;

      final subPathPrefix = _currentDirPath.length > archivePath.length
          ? _currentDirPath
                .substring(archivePath.length)
                .replaceFirst(RegExp(r'^/+'), '')
          : '';

      final selectedPaths = entries.map((e) {
        final clean = subPathPrefix.isEmpty
            ? e.name
            : '$subPathPrefix/${e.name}';
        return clean.startsWith('/') ? clean.substring(1) : clean;
      }).toList();

      final clipItems = entries.map((e) {
        return ClipboardItem(
          path: subPathPrefix.isEmpty ? e.name : '$subPathPrefix/${e.name}',
          isDir: e.isDir,
          sizeBytes: e.sizeBytes,
          modifiedSecs: e.modifiedSecs,
        );
      }).toList();

      _clip.setArchiveExtract(
        volId: widget.container.volId,
        displayName: widget.container.displayName,
        archiveItem: ClipboardItem(
          path: archivePath,
          isDir: false,
          sizeBytes: 0,
        ),
        archiveContext: _archiveContext!,
        selectedEntryPaths: selectedPaths,
        stagedItems: clipItems,
      );
      exitSelectionMode();

      _setStatus(
        entries.length == 1
            ? 'Item staged for extraction. Navigate to destination and paste.'
            : '${entries.length} items staged for extraction. Navigate to destination and paste.',
      );
      return;
    }

    // ── Outside archive: stage full archive file for extraction ─────────
    if (selectedItems.length != 1) return;
    final entry = selectedItems.first;
    final ext =
        ArchiveService.splitPartExtension(entry.name) ??
        (entry.name.contains('.')
            ? entry.name.split('.').last.toLowerCase()
            : '');
    if (entry.isDir || !ArchiveService.isOpenableAsArchive(ext)) return;
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    final fullPath = _fullPathOf(entry);
    exitSelectionMode();

    ArchiveContext archiveContext;
    String? passphrase;
    try {
      while (true) {
        archiveContext = widget.container.isLocalStorage
            ? await ArchiveService.openLocal(
                pathOrUri: p.join(widget.container.uri, fullPath),
                archiveName: entry.name,
                pathStackEntryIndex: _pathStack.length,
                passphrase: passphrase,
              )
            : await ArchiveService.open(
                container: widget.container,
                archivePathInContainer: fullPath,
                pathStackEntryIndex: _pathStack.length,
                passphrase: passphrase,
              );
        if (archiveContext.status == ArchiveOpenStatus.ok) break;
        if (!mounted) return;
        final entered = await BrowserDialogs.showArchivePasswordPrompt(
          context,
          wrongPassword:
              archiveContext.status == ArchiveOpenStatus.wrongPassphrase,
        );
        if (entered == null) return;
        passphrase = entered;
      }
    } catch (e) {
      if (mounted) {
        _setStatus(
          context.l10n.failedToReadArchive('${e.runtimeType}'),
          error: true,
        );
      }
      return;
    }

    final clipItem = ClipboardItem(
      path: fullPath,
      isDir: false,
      sizeBytes: entry.sizeBytes,
      modifiedSecs: entry.modifiedSecs,
    );

    _clip.setArchiveExtract(
      volId: widget.container.volId,
      displayName: widget.container.displayName,
      archiveItem: clipItem,
      archiveContext: archiveContext,
      selectedEntryPaths: null, // Full archive
    );
    if (mounted) {
      _setStatus(
        'Archive "${entry.name}" staged. Navigate to destination and paste.',
      );
    }
  }

  Future<void> _encryptSelected() => _runQuickCrypto(CryptoDirection.encrypt);

  Future<void> _decryptSelected() => _runQuickCrypto(CryptoDirection.decrypt);

  Future<void> _runQuickCrypto(CryptoDirection direction) async {
    final files = _uniqueSelectedBrowserEntries.where((item) {
      if (item.insideArchive || item.entry.isDir) return false;
      final isEncrypted = isAppEncryptedFileName(item.entry.name);
      return direction == CryptoDirection.encrypt ? !isEncrypted : isEncrypted;
    }).toList();
    exitSelectionMode();
    if (files.isEmpty) return;

    final sources = files.map((item) {
      final source = item.container;
      final entry = item.entry;
      final relPath = fullPathOf(entry, item.currentDirPath);
      if (source.isLocalStorage) {
        final absPath = p.join(source.uri, relPath);
        return CryptoSourceItem.external(
          displayName: entry.name,
          externalUri: Uri.file(absPath).toString(),
        );
      } else {
        return CryptoSourceItem.vault(
          displayName: entry.name,
          container: source,
          relativePath: relPath,
        );
      }
    }).toList();

    final destinationIsLocal = widget.container.isLocalStorage;
    final folderLabel = _currentDirPath.isEmpty
        ? widget.container.displayName
        : '${widget.container.displayName} / ${_currentDirPath.split('/').last}';

    final destination = destinationIsLocal
        ? CryptoDestination.external(
            displayName: folderLabel,
            externalPath: _currentDirPath.isEmpty
                ? widget.container.uri
                : p.join(widget.container.uri, _currentDirPath),
          )
        : CryptoDestination.vault(
            displayName: folderLabel,
            container: widget.container,
            relativePath: _currentDirPath,
          );

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
    await _loadDirectoryContents(_currentDirPath, refresh: true);
  }

  Future<ConflictPlan?> _resolveImportConflicts(
    ImportPickResult pick, {
    required bool candidateIsDir,
  }) async {
    if (pick.conflicts.isEmpty) return const {};
    final entries = pick.conflicts
        .map(
          (c) => ConflictEntry(
            item: ClipboardItem(path: c.name, isDir: candidateIsDir),
            destIsDir: c.destIsDir,
          ),
        )
        .toList();
    if (!mounted) return null;
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
  }) {
    final fileIo = ref.read(vaultFileIoApiProvider);
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        unawaited(fileIo.clearImportSources(op.id));
        return;
      }
      final done =
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        // See _opNeedsAttention's doc comment (applied the same way in
        // bindOpListener, above) -- a failed/diskFull/partially-failed
        // import stays in the service's list instead of being dismissed out
        // from under the transfer button/sheet the moment it finishes.
        final keepVisible = _opNeedsAttention(op);
        if (op.status == FileOperationStatus.completed &&
            op.destDirPath == _currentDirPath) {
          _loadDirectoryContents(_currentDirPath).then((_) {
            _opSvc.dismiss(op.id);
          });
        } else if (!keepVisible) {
          _opSvc.dismiss(op.id);
        }
        if (op.status == FileOperationStatus.completed) {
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

  Future<void> _captureFromCamera() async {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    _signalActivity();
    try {
      final captured = await Navigator.push<({String savedName, bool isVideo})>(
        context,
        MaterialPageRoute(
          builder: (_) => CameraCaptureScreen(
            container: widget.container,
            targetDirPath: _currentDirPath,
          ),
        ),
      );
      if (captured == null || !mounted) return;
      await _loadDirectoryContents(_currentDirPath);
      _setStatus(
        captured.isVideo
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
      await _loadDirectoryContents(_currentDirPath);
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

  bool _matchesFilter(String fileName) =>
      matchesFilter(fileName, _currentFilter);

  Future<void> _extractArchive() async {
    if (_archiveContext == null) return;
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    final archivePath =
        _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
    final parentDir = archivePath.contains('/')
        ? archivePath.substring(0, archivePath.lastIndexOf('/'))
        : '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.extractArchive),
        content: Text(
          context.l10n.extractAllFilesToFolder(
            parentDir.isEmpty ? context.l10n.rootFolderLabel : parentDir,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.extract),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final verifiedArchive = await _ensureArchivePasswordForExtraction(
      _archiveContext!,
    );
    if (verifiedArchive == null || !mounted) return;
    _navNotifier.updateArchiveContext(verifiedArchive);
    _navNotifier.setLoading(true);
    try {
      // Same handling as FileOperationService._runArchiveExtract: entries
      // that differ only by case would replace one another on a
      // case-insensitive destination, so they are extracted one by one under
      // unique names ("notes (1).txt") instead of the bulk route.
      final caseSafePlan = isDestinationCaseSensitive(widget.container)
          ? null
          : ArchiveService.caseSafeExtractPlan(verifiedArchive);
      final count = caseSafePlan != null
          ? await ArchiveService.extractMappedToContainer(
              container: widget.container,
              archiveContext: verifiedArchive,
              destRelByEntryPath: caseSafePlan,
              targetDirInContainer: parentDir,
            )
          : await ArchiveService.extractAllToContainer(
              container: widget.container,
              archiveContext: verifiedArchive,
              targetDirInContainer: parentDir,
            );
      if (mounted) {
        _setStatus(
          context.l10n.extractedCount(count),
          autoClear: const Duration(seconds: 3),
        );
        _loadDirectoryContents(_currentDirPath, refresh: true);
      }
    } catch (e) {
      if (mounted) {
        _setStatus(
          context.l10n.failedToExtractGeneric('${e.runtimeType}'),
          error: true,
        );
      }
    } finally {
      if (mounted) _navNotifier.setLoading(false);
    }
  }

  Future<void> _onGridAspectRatioChanged(GridAspectRatio ratio) async {
    try {
      if (_toolbarConfig.rememberPerFolderLayout) {
        // Per-folder memory is on: record this folder's own aspect ratio
        // only. The app-wide `gridAspectRatio` below is the fallback for
        // folders that have never been set explicitly -- moving it here too
        // would make every such folder silently pick up whatever ratio was
        // last chosen in this one, the same bleed-through bug this whole
        // per-folder feature exists to avoid.
        final key = FileManagerToolbarConfig.folderKey(
          widget.container.uri,
          _currentDirPath,
        );
        final updatedRatios = Map<String, String>.from(
          _toolbarConfig.folderGridAspectRatios,
        );
        updatedRatios[key] = ratio.toJson();
        setState(() {
          _toolbarConfig = _toolbarConfig.copyWith(
            folderGridAspectRatios: updatedRatios,
          );
        });
      } else {
        setState(() {
          _toolbarConfig = _toolbarConfig.copyWith(gridAspectRatio: ratio);
        });
      }
      await _toolbarSvc.save(_toolbarConfig);

      // Keep the toolbar settings provider in sync so external listeners also reflect this ratio.
      final effectiveToolbarUri = widget.container.isLocalStorage
          ? null
          : widget.container.uri;
      ref
          .read(
            fileManagerToolbarSettingsProvider(effectiveToolbarUri).notifier,
          )
          .applyImportedConfig(_toolbarConfig);
    } catch (e) {
      if (mounted) {
        _setStatus(context.l10n.failedToSaveSettings, error: true);
      }
    }
  }

  Future<void> _onLayoutModeChanged(BrowserLayoutMode mode) async {
    // Only an actual switch counts: re-picking the current mode (e.g. the
    // grid aspect-ratio submenu, which re-selects grid) must not wipe the
    // size the user just pinched to.
    final resetSize =
        _toolbarConfig.resetSizeOnLayoutChange && mode != _layoutMode;
    if (resetSize) {
      // Applied synchronously, before the mode switch, so the incoming view
      // is built straight at the default size rather than flashing the old
      // one -- and so any follow-up handler (e.g. the aspect-ratio change
      // fired right after this one) copies from the already-reset config.
      setState(() {
        _toolbarConfig = _toolbarConfig.withDefaultSizes();
      });
    }
    _navNotifier.setLayoutMode(mode);
    try {
      if (_toolbarConfig.rememberPerFolderLayout) {
        // Per-folder memory is on: record this folder's own choice only --
        // never touch the app-wide default here. That default is the
        // fallback for folders that have never been set explicitly, and
        // updating it on every in-folder change is exactly what made other,
        // untouched folders appear to silently switch views on their own.
        final key = FileManagerToolbarConfig.folderKey(
          widget.container.uri,
          _currentDirPath,
        );
        final updatedFolderModes = Map<String, String>.from(
          _toolbarConfig.folderLayoutModes,
        );
        updatedFolderModes[key] = mode.toJson();
        _toolbarConfig = _toolbarConfig.copyWith(
          folderLayoutModes: updatedFolderModes,
        );
        await _toolbarSvc.save(_toolbarConfig);

        final effectiveToolbarUri = widget.container.isLocalStorage
            ? null
            : widget.container.uri;
        ref
            .read(
              fileManagerToolbarSettingsProvider(effectiveToolbarUri).notifier,
            )
            .applyImportedConfig(_toolbarConfig);
      } else {
        // Per-folder memory is off: this is a single app-wide layout mode,
        // same as before this feature existed.
        final settings = await ref
            .read(appSettingsServiceProvider)
            .loadSettings();
        final updatedSettings = settings.copyWith(defaultLayoutMode: mode);
        await ref
            .read(appSettingsServiceProvider)
            .saveSettings(updatedSettings);
        _appSettings = updatedSettings;

        // The per-folder branch above already saved the reset sizes along
        // with its folder map; this branch otherwise never touches the
        // toolbar config, so persist them here.
        if (resetSize) {
          await _toolbarSvc.save(_toolbarConfig);
          final effectiveToolbarUri = widget.container.isLocalStorage
              ? null
              : widget.container.uri;
          ref
              .read(
                fileManagerToolbarSettingsProvider(
                  effectiveToolbarUri,
                ).notifier,
              )
              .applyImportedConfig(_toolbarConfig);
        }
      }
    } catch (e) {
      if (mounted) {
        _setStatus(context.l10n.failedToSaveSettings, error: true);
      }
    }
  }

  Future<void> _onSortChanged(SortBy field) async {
    setSort(field);
    try {
      if (_toolbarConfig.rememberPerFolderLayout) {
        // Per-folder memory is on: record this folder's own sort only --
        // see _onLayoutModeChanged for why the app-wide default must not
        // also move.
        final key = FileManagerToolbarConfig.folderKey(
          widget.container.uri,
          _currentDirPath,
        );
        final updatedFolderSorts = Map<String, String>.from(
          _toolbarConfig.folderSortModes,
        );
        updatedFolderSorts[key] = encodeFolderSortState(sortBy, sortAscending);
        _toolbarConfig = _toolbarConfig.copyWith(
          folderSortModes: updatedFolderSorts,
        );
        await _toolbarSvc.save(_toolbarConfig);

        final effectiveToolbarUri = widget.container.isLocalStorage
            ? null
            : widget.container.uri;
        ref
            .read(
              fileManagerToolbarSettingsProvider(effectiveToolbarUri).notifier,
            )
            .applyImportedConfig(_toolbarConfig);
      } else {
        // Per-folder memory is off: a single app-wide sort order, same as
        // before per-folder sort existed.
        final settings = await ref
            .read(appSettingsServiceProvider)
            .loadSettings();
        final updatedSettings = settings.copyWith(
          defaultFileSortBy: sortBy,
          defaultFileSortAscending: sortAscending,
        );
        await ref
            .read(appSettingsServiceProvider)
            .saveSettings(updatedSettings);
        _appSettings = updatedSettings;
      }
    } catch (e) {
      if (mounted) {
        _setStatus(context.l10n.failedToSaveSettings, error: true);
      }
    }
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
    final hasLocalMedia = currentItems
        .where((e) => !e.isDir)
        .map((e) => e.name)
        .any(_isSupportedMedia);
    final hasSubfolders = currentItems.any((e) => e.isDir);
    final canPlayMedia = hasLocalMedia || hasSubfolders;
    return {
      FileManagerAction.search: (context) => IconButton(
        icon: Icon(
          searchActive ? Icons.search_off_rounded : Icons.search_rounded,
        ),
        tooltip: searchActive
            ? context.l10n.closeSearchTooltip
            : context.l10n.searchInThisFolderTooltip,
        onPressed: () => searchNotifier.toggleActive(),
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
        onLoadDirectoryContents: (path) =>
            _loadDirectoryContents(path, refresh: true),
        onCaptureFromCamera: _captureFromCamera,
        onRecordAudio: _recordAudio,
        onImportFilesFromDevice: _importFilesFromDevice,
        onImportFolderFromDevice: _importFolderFromDevice,
        onAddVaultItem: _addVaultItem,
        hideVaultOnlyActions: widget.container.isLocalStorage,
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
        onFilterChanged: (value) => navigationNotifier.setFilter(value),
        hideVaultOnlyActions: widget.container.isLocalStorage,
      ),
      FileManagerAction.playMedia: (context) => IconButton(
        icon: const Icon(Icons.play_circle_outline_rounded),
        tooltip: context.l10n.playMediaHereTooltip,
        onPressed: canPlayMedia ? _startMediaViewerFromCurrentLocation : null,
      ),
    };
  }

  final BrowserListingCache _listingCache = BrowserListingCache();

  BrowserListing _getFilteredAndSortedItems(
    String query,
    List<RawEntry> placeholders,
    Set<String> pendingDeletedNames,
  ) {
    final sortState = ref.read(fileBrowserSortProvider(_stateKey));
    return _listingCache.resolve(
      BrowserListingInputs(
        items: _currentItems,
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

    final showAddFab = _toolbarConfig.visible.contains(FileManagerAction.add);
    final moreActions = _toolbarConfig.visible
        .where((a) => a != FileManagerAction.add)
        .toList(growable: false);
    final showMore = moreActions.isNotEmpty;

    final widgets = <Widget>[];

    if (showMore) {
      final hasLocalMedia = _currentItems
          .where((e) => !e.isDir)
          .map((e) => e.name)
          .any(_isSupportedMedia);
      final hasSubfolders = _currentItems.any((e) => e.isDir);
      final canPlayMedia = hasLocalMedia || hasSubfolders;

      // When the Add FAB is visible, place More to its left (56dp FAB + 12dp spacing = 68dp).
      // If the Add FAB is hidden via config, More takes the primary bottom-right slot.
      final moreRight = showAddFab ? (baseRight + 68.0) : baseRight;

      widgets.add(
        Positioned(
          right: moreRight,
          bottom:
              bottomOffset +
              4.0, // 4dp offset centers the 48dp button against the 56dp Add FAB
          child: FileManagerMoreMenuButton(
            actions: moreActions,
            searchActive: _searchActive,
            onToggleSearch: () => _searchNotifier.toggleActive(),
            sortBy: sortBy,
            sortAscending: sortAscending,
            onSortChanged: _onSortChanged,
            currentFilter: _currentFilter,
            onFilterChanged: (value) => _navNotifier.setFilter(value),
            hideVaultOnlyActions: widget.container.isLocalStorage,
            layoutMode: _layoutMode,
            onLayoutModeChanged: _onLayoutModeChanged,
            gridAspectRatio: _toolbarConfig.getGridAspectRatioForFolder(
              widget.container.uri,
              _currentDirPath,
            ),
            onGridAspectRatioChanged: _onGridAspectRatioChanged,
            canPlayMedia: canPlayMedia,
            onPlayMedia: _startMediaViewerFromCurrentLocation,
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
            onLoadDirectoryContents: (path) =>
                _loadDirectoryContents(path, refresh: true),
            onCaptureFromCamera: _captureFromCamera,
            onRecordAudio: _recordAudio,
            onImportFilesFromDevice: _importFilesFromDevice,
            onImportFolderFromDevice: _importFolderFromDevice,
            onAddVaultItem: _addVaultItem,
            hideVaultOnlyActions: widget.container.isLocalStorage,
            asFab: true,
          ),
        ),
      );
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    // Every file/folder tile, and the bookmark bar, below this point reads the
    // user's chosen skin from here. Kept as a thin wrapper so the (very
    // large) screen body itself is untouched.
    final skinTokens = Theme.of(context).extension<AppSkinTokens>();
    return FileManagerSkinScope(
      skin: skinTokens == null
          ? _toolbarConfig.skin
          : skinTokens.fileManagerFollowsAppSkin
          ? skinTokens.fileManagerSkin
          : skinTokens.manualFileManagerSkin,
      child: _buildBrowser(context),
    );
  }

  Widget _buildBrowser(BuildContext context) {
    final useBrowserTabs = ref.watch(
      appSettingsControllerProvider.select(
        (settings) => settings.settings.useBrowserTabs,
      ),
    );
    ref.watch(fileBrowserSelectionProvider(_stateKey));
    if (_isActiveTab) {
      for (final tab in _workspaceTabs) {
        if (!tab.isDashboard && tab.tabId != _stateKey) {
          ref.watch(fileBrowserSelectionProvider(tab.tabId));
        }
      }
    }
    ref.watch(fileBrowserSortProvider(_stateKey));
    ref.watch(fileBrowserNavigationProvider(_stateKey));
    ref.watch(vaultSyncedFolderPathsProvider(widget.container));

    final effectiveToolbarUri = widget.container.isLocalStorage
        ? null
        : widget.container.uri;
    ref.listen<FileManagerToolbarSettingsState>(
      fileManagerToolbarSettingsProvider(effectiveToolbarUri),
      (previous, next) {
        if (next.loading) return;
        if (previous?.config != next.config) {
          setState(() {
            _toolbarConfig = next.config;
            _toolbarConfigReady = true;
            // The app-wide thumbnail default (or the Local Storage slot) may
            // be what changed, and this browser may be following it.
            _applyResolvedThumbnails(next.config);
          });
        }
        // Vault records were rewritten in bulk ("reset all vaults to the
        // default"); a vault's own thumbnail settings live in its record, so
        // re-read it.
        if (previous?.thumbnailOverridesRevision !=
            next.thumbnailOverridesRevision) {
          _loadToolbarConfig();
        }
      },
    );
    ref.listen<SyncStatus>(syncStatusProvider, (previous, next) {
      if (previous?.running == true &&
          !next.running &&
          next.lastCompletedReport?.didWork == true) {
        _loadDirectoryContents(_currentDirPath, refresh: true);
      }
    });
    // The hosting shell closes a vault's tabs when it locks, detaches, or its
    // external storage disappears, and leaves the route once none remain.
    if (_isContainerLocked) {
      return const ColoredBox(color: Colors.black, child: SizedBox.expand());
    }
    final query = _searchQuery.trim().toLowerCase();
    final placeholders = _opSvc.getActivePlaceholders(
      widget.container.volId,
      _currentDirPath,
    );
    final pendingDeletedNames = _opSvc.getPendingDeletedNames(
      widget.container.volId,
      _currentDirPath,
    );
    final itemResult = _getFilteredAndSortedItems(
      query,
      placeholders,
      pendingDeletedNames,
    );
    final filteredItems = itemResult.items;
    final dirCount = itemResult.dirCount;
    final fileCount = itemResult.fileCount;

    final previewDirPath = _backGesturePreviewDirPath ?? _currentDirPath;
    final previewArchiveRootPath = _archiveRootPathForSearch;
    final previewInsideArchive =
        previewArchiveRootPath != null &&
        (previewDirPath == previewArchiveRootPath ||
            previewDirPath.startsWith('$previewArchiveRootPath/'));
    final previewArchiveContext = previewInsideArchive ? _archiveContext : null;
    final sortedPreviewItems =
        (_backGestureProgress != null && _backGesturePreviewItems != null)
        ? (List<RawEntry>.of(
            _backGesturePreviewItems!.where((item) {
              if (!_toolbarConfig.showHiddenFiles &&
                  isHiddenEntryName(item.name)) {
                return false;
              }
              return true;
            }),
          )..sort(
            (ea, eb) => compareBrowserEntries(
              ea,
              eb,
              currentDirPath: previewDirPath,
              pinnedPaths: _pinnedPaths,
              sortBy: sortBy,
              sortAscending: sortAscending,
            ),
          ))
        : null;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final useFab = _toolbarConfig.useFabForToolbar;
    final showActionBar = !_searchActive && !useFab;
    final selectedForBar = _selectedBrowserEntries;
    final workspace = widget.workspaceConfig;
    final appBarNavigation = _nav;
    final appBarSearch = _search;
    final appBarPathStack = List<PathSegment>.unmodifiable(
      appBarNavigation.pathStack,
    );
    final appBarCurrentDirPath = appBarNavigation.currentDirPath;
    final appBarCurrentFilter = appBarNavigation.currentFilter;
    final appBarFreeSpace = appBarNavigation.freeSpace;
    final appBarArchiveContext = appBarNavigation.archiveContext;
    final appBarAtRoot = appBarNavigation.atRoot;
    final appBarSearchActive = appBarSearch.active;
    final appBarToolbarConfig = _toolbarConfig;
    final appBarCurrentItems = List<RawEntry>.unmodifiable(_currentItems);
    final appBarLayoutMode = appBarNavigation.layoutMode;
    final appBarSort = ref.read(fileBrowserSortProvider(_stateKey));
    final appBarSearchNotifier = _searchNotifier;
    final appBarNavigationNotifier = _navNotifier;
    final appBarMountedDocProviderFolders = _mountedDocProviderFolders;
    final appBarPinnedPaths = _pinnedPaths;
    final appBarBookmarkPaths = _bookmarkPaths;
    final appBarSettingsService = ref.read(appSettingsServiceProvider);
    final appBarSingleSelectedFolderForNewTab = _singleSelectedFolderForNewTab;
    final appBarSelectionCount = selectedForBar.length;
    final appBarSelectionHasReadOnlySource = selectedForBar.any(
      (item) => item.container.readOnly,
    );
    final appBarSelectedTotalBytes = selectedForBar.isEmpty
        ? 0
        : _allSelectedTotalBytes;
    final appBarHasPendingFolderSizes = selectedForBar.isNotEmpty
        ? _anySelectedFolderSizePending
        : false;
    final appBarPinsByVolId = <int, Set<String>>{};
    final appBarBookmarksByVolId = <int, List<String>>{};
    for (final item in selectedForBar) {
      appBarPinsByVolId.putIfAbsent(
        item.container.volId,
        () => ref
            .read(fileBrowserPinsBookmarksProvider(item.container.volId))
            .pinnedPaths,
      );
      appBarBookmarksByVolId.putIfAbsent(
        item.container.volId,
        () => ref
            .read(fileBrowserPinsBookmarksProvider(item.container.volId))
            .bookmarkPaths,
      );
    }
    bool appBarIsFolderMounted(RawEntry entry) => isFolderMounted(
      entry,
      appBarCurrentDirPath,
      appBarMountedDocProviderFolders,
    );
    bool appBarIsPinned(RawEntry entry) {
      final matches = selectedForBar.where((item) => item.entry == entry);
      if (matches.isEmpty) {
        return isPinned(entry, appBarCurrentDirPath, appBarPinnedPaths);
      }
      return matches.any((item) {
        final paths = appBarPinsByVolId[item.container.volId];
        return paths != null && isPinned(entry, item.currentDirPath, paths);
      });
    }

    bool appBarIsBookmarked(RawEntry entry) {
      final matches = selectedForBar.where((item) => item.entry == entry);
      if (matches.isEmpty) {
        return isBookmark(entry, appBarCurrentDirPath, appBarBookmarkPaths);
      }
      return matches.any((item) {
        final paths = appBarBookmarksByVolId[item.container.volId];
        return paths != null && isBookmark(entry, item.currentDirPath, paths);
      });
    }

    final actionBuilders = _buildActionBuilders(
      searchActive: appBarSearchActive,
      isReadOnly: widget.container.readOnly,
      hasArchiveContext: appBarArchiveContext != null,
      currentDirPath: appBarCurrentDirPath,
      currentItems: appBarCurrentItems,
      layoutMode: appBarLayoutMode,
      currentFilter: appBarCurrentFilter,
      toolbarConfig: appBarToolbarConfig,
      searchNotifier: appBarSearchNotifier,
      navigationNotifier: appBarNavigationNotifier,
      sortBy: appBarSort.sortBy,
      sortAscending: appBarSort.sortAscending,
    );
    final isFiltered = query.isNotEmpty || _currentFilter != null;
    final showBookmarkBar =
        _toolbarConfig.showBookmarkBar && _bookmarkPaths.isNotEmpty;
    final localSelectionIsNonEmpty = ref
        .read(fileBrowserSelectionProvider(_stateKey))
        .items
        .isNotEmpty;
    final aggregateSelection = _isActiveTab
        ? ref.watch(aggregatedTabsSelectionProvider(workspace))
        : localSelectionIsNonEmpty
        ? ref.read(aggregatedTabsSelectionProvider(workspace))
        : null;
    final selectionBarVisible =
        _isActiveTab &&
        (aggregateSelection?.hasSelection ?? _selectedBrowserEntryCount > 0);
    final selectionInBottomBar =
        selectionBarVisible && _toolbarConfig.bottomSelectionBar;
    final hasBookmarkBarViewportSlot = !isLandscape && !selectionInBottomBar;
    final showBookmarkBarInViewport =
        hasBookmarkBarViewportSlot && showBookmarkBar;

    Widget buildHorizontalBookmarkBar() => BookmarkBar(
      bookmarkPaths: _bookmarkPaths,
      axis: Axis.horizontal,
      onTapItem: (path) {
        final isDir = !path.split('/').last.contains('.') || path.endsWith('/');
        _navigateToPath(path, isDir: isDir);
      },
      onRemoveBookmark: (path) =>
          _pinsBookmarksNotifier.removeBookmark(widget.container, path),
    );

    final selectedForBarSet = {for (final item in selectedForBar) item.entry};
    final selectedVolIds = selectedForBar
        .map((item) => item.container.volId)
        .toSet();
    final allSelectionInOneTab =
        selectedForBar.isNotEmpty &&
        selectedForBar.every((item) => item.stateKey == _stateKey);
    final allSelectionOutsideArchives = selectedForBar.every(
      (item) => !item.insideArchive,
    );
    final selectedInOneContainer = selectedVolIds.length == 1;
    final canExtractCurrentSelection =
        selectedForBar.isNotEmpty &&
        selectedForBar.every(
          (item) =>
              item.stateKey == _stateKey &&
              (item.insideArchive || selectedForBar.length == 1),
        );
    final singleSelectionInCurrentTab =
        selectedForBar.length == 1 &&
        selectedForBar.single.stateKey == _stateKey &&
        !selectedForBar.single.insideArchive;
    final hideVaultOnlyActionsForSelection =
        selectedForBar.isNotEmpty &&
        selectedForBar.every((item) => item.container.isLocalStorage);

    final hasBottomNavBar = !isLandscape && showActionBar;
    final bottomSystemInset = hasBottomNavBar
        ? 0.0
        : MediaQuery.paddingOf(context).bottom;
    final baseBottomOffset =
        16.0 + (!isLandscape && showBookmarkBar ? 0.0 : bottomSystemInset);

    final bool hasClipboardFab =
        !selectionBarVisible &&
        !_searchActive &&
        ref.watch(crossContainerClipboardProvider).hasItems;
    final bool hasFabToolbar = useFab && !_searchActive;

    double fabClearance = 0.0;
    if (hasClipboardFab && hasFabToolbar) {
      fabClearance =
          132.0; // Two stacked FABs (56 + 12 + 56 = 124) + 8dp clearance
    } else if (hasClipboardFab || hasFabToolbar) {
      fabClearance = 64.0; // Single FAB (56) + 8dp clearance
    }

    final double bannerBottomOffset = _searchActive
        ? 0.0
        : (baseBottomOffset +
              ((selectionBarVisible && _toolbarConfig.bottomSelectionBar)
                  ? kToolbarHeight
                  : 0.0) +
              fabClearance);

    PreferredSizeWidget buildAppBar(
      BuildContext appBarContext, {
      required bool selectionMode,
    }) {
      return buildBrowserAppBar(
        appBarContext,
        appSettingsService: appBarSettingsService,
        container: widget.container,
        pathStack: appBarPathStack,
        onJumpTo: _jumpTo,
        filteredItems: filteredItems,
        dirCount: dirCount,
        fileCount: fileCount,
        isSelectionMode: selectionMode,
        selectedItems: selectionMode ? selectedForBarSet : const {},
        selectedCountOverride: selectionMode
            ? aggregateSelection?.count ?? appBarSelectionCount
            : null,
        singleSelectionInCurrentTab: singleSelectionInCurrentTab,
        allowRenameAction:
            allSelectionInOneTab &&
            allSelectionOutsideArchives &&
            !appBarSelectionHasReadOnlySource,
        allowShareAction: selectedInOneContainer && allSelectionOutsideArchives,
        allowCompressAction:
            selectedInOneContainer && allSelectionOutsideArchives,
        allowExportAction:
            selectedInOneContainer && allSelectionOutsideArchives,
        allowExtractAction: canExtractCurrentSelection,
        allowPinBookmarkActions: allSelectionOutsideArchives,
        hideVaultOnlyActionsOverride: hideVaultOnlyActionsForSelection,
        isReadOnly: selectionMode
            ? appBarSelectionHasReadOnlySource
            : widget.container.readOnly,
        searchActive: appBarSearchActive,
        currentDirPath: appBarCurrentDirPath,
        currentFilter: appBarCurrentFilter,
        freeSpace: appBarFreeSpace,
        selectedTotalBytes: selectionMode
            ? aggregateSelection?.bytes ?? appBarSelectedTotalBytes
            : 0,
        hasPendingFolderSizes: selectionMode
            ? aggregateSelection?.hasPendingFolderSizes ??
                  appBarHasPendingFolderSizes
            : false,
        toolbarConfig: useFab
            ? appBarToolbarConfig.copyWith(
                hidden: FileManagerAction.values.toSet(),
              )
            : appBarToolbarConfig,
        actionBuilders: actionBuilders,
        isFolderMounted: appBarIsFolderMounted,
        isPinned: appBarIsPinned,
        isBookmark: appBarIsBookmarked,
        isInsideArchive: selectionMode
            ? selectedForBar.any((item) => item.insideArchive)
            : appBarArchiveContext != null,
        onExitSelectionMode: exitSelectionMode,
        onSelectAll: () =>
            setSelectedItems({...selectedItems, ...filteredItems}),
        onCopy: () => _initClipboard(cut: false),
        onCut: () => _initClipboard(cut: true),
        onOpenInNewTab: appBarSingleSelectedFolderForNewTab == null
            ? null
            : () {
                final selected = appBarSingleSelectedFolderForNewTab;
                _openFolderInNewTab(
                  selected.container,
                  fullPathOf(selected.entry, selected.currentDirPath),
                  stateKey: selected.stateKey,
                  selectedEntry: selected.entry,
                );
              },
        onExport: _exportSelectedToStorage,
        onCompressSelected: _compressSelected,
        onExtractSelectedArchive: _extractSelectedArchive,
        onDelete: _batchDelete,
        onShare: _shareSelected,
        onEncryptSelected: _encryptSelected,
        onDecryptSelected: _decryptSelected,
        onTogglePin: _togglePinSelected,
        onToggleBookmark: _toggleBookmarkSelected,
        onDirectoryReload: _loadDirectoryContents,
        onSetStatus: (msg, {required bool error}) =>
            _setStatus(msg, error: error),
        onShowOpenWithDialog: _showOpenWithDialog,
        onShowFolderDocumentProviderSheet: _showFolderDocumentProviderSheet,
        onToggleFolderDocumentProvider: _toggleFolderDocumentProvider,
        onSyncSettings: _showSyncSettings,
        onSyncRoot: _showRootSyncSettings,
        onEditImage: _editImage,
        onEditVideo: _editVideo,
        onEditAudio: _editAudio,
        onSettingsClosed: _loadToolbarConfig,
        isFiltered: isFiltered,
        onPaste: widget.container.readOnly ? null : _paste,
        onNavigateUp: appBarAtRoot ? null : _navigateUp,
        onBackAtRoot: !useBrowserTabs ? _handleBackAtRoot : null,
        showBackButton: widget.showBackButton,
        wrapTitle: widget.wrapAppBarTitle,
        onOpenStorageSwitcher: widget.onOpenStorageSwitcher,
      );
    }

    final selectionInTopBar =
        selectedForBar.isNotEmpty && !_toolbarConfig.bottomSelectionBar;
    // App-bar factories are handed to the chrome hub. Recreating the closure on
    // every directory build makes its ValueListenable rebuild the AppBar for
    // unrelated viewport work (scrolling, thumbnails, banners), which appears
    // as a toolbar flash. Keep one factory per visible app-bar state and have
    // it delegate to the latest snapshot captured by this mounted view.
    final appBarEntriesSignature = identityHashCode(filteredItems);
    final selectedEntriesSignature = Object.hashAll(
      selectedForBar.map(
        (item) => Object.hash(
          item.stateKey,
          item.container.volId,
          item.currentDirPath,
          item.entry.name,
          item.entry.isDir,
          item.entry.sizeBytes,
          item.insideArchive,
          item.container.readOnly,
        ),
      ),
    );
    final appBarPathSignature = Object.hashAll(
      appBarPathStack.map(
        (segment) =>
            Object.hash(segment.label, segment.fatPath, segment.isArchiveRoot),
      ),
    );
    final appBarSignature = Object.hash(
      Object.hash(
        widget.container.volId,
        widget.container.displayName,
        widget.container.uri,
        appBarPathSignature,
        appBarCurrentDirPath,
        appBarCurrentFilter,
        appBarFreeSpace,
        appBarSearchActive,
        dirCount,
        fileCount,
        isFiltered,
        appBarEntriesSignature,
        appBarLayoutMode,
        appBarSort.sortBy,
        appBarSort.sortAscending,
      ),
      Object.hash(
        appBarArchiveContext == null,
        appBarToolbarConfig.showStatsBar,
        appBarToolbarConfig.useFabForToolbar,
        Object.hashAll(appBarToolbarConfig.visible),
        Object.hashAll(appBarToolbarConfig.hidden),
        Object.hashAll(appBarMountedDocProviderFolders),
        Object.hashAll(appBarPinnedPaths.toList()..sort()),
        Object.hashAll(appBarBookmarkPaths),
        selectedEntriesSignature,
        aggregateSelection?.count,
        aggregateSelection?.bytes,
        aggregateSelection?.hasPendingFolderSizes,
        selectionInTopBar,
        useBrowserTabs,
      ),
    );
    _latestAppBarBuilder = buildAppBar;
    final regularAppBarFactory = _appBarFactoryFor(
      signature: appBarSignature,
      selectionMode: selectionInTopBar,
    );
    final selectionAppBarFactory = _appBarFactoryFor(
      signature: Object.hash(appBarSignature, true),
      selectionMode: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chrome.setAppBar(widget.tabId, regularAppBarFactory);
    });
    if (_isActiveTab || localSelectionIsNonEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            (!_isActiveTab &&
                ref
                    .read(fileBrowserSelectionProvider(_stateKey))
                    .items
                    .isEmpty)) {
          return;
        }
        _chrome.setSelectionAppBar(
          widget.tabId,
          selectedForBar.isEmpty || _toolbarConfig.bottomSelectionBar
              ? null
              : selectionAppBarFactory,
        );
      });
    }

    // Only the focused tab has a say in back. It vetoes the system unless the
    // policy says there is nothing left for the browser to do (decoy at its
    // root). Hidden tabs never veto, so Home can hand back to the app shell,
    // which asks for a second back before exiting.
    final bool isActiveTab = _isActiveTab;
    final bool canPop =
        !isActiveTab || _resolveBack() == BrowserBackAction.leave;
    final systemOverlayStyle =
        Theme.of(context).appBarTheme.systemOverlayStyle ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppSystemUI.transparentDark
            : SystemUiOverlayStyle.dark);
    final Widget? browserBottomBar = (!isLandscape && showActionBar)
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FileManagerActionBar(
                axis: Axis.horizontal,
                actions: _toolbarConfig.visible,
                builders: actionBuilders,
              ),
            ],
          )
        : null;
    final embeddedBottomBar = selectionInBottomBar
        // The shell's bottom slot sits at the screen's edge, under the
        // keyboard. Lifting the bar by the keyboard's height keeps the
        // selection actions visible and tappable while a search is still open
        // (selecting a result with the keyboard up). Read from the slot's own
        // context: that is where the keyboard inset is still intact.
        ? Builder(
            builder: (slotContext) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(slotContext).bottom,
              ),
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                elevation: 4,
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: kToolbarHeight,
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      removeBottom: true,
                      child: buildAppBar(context, selectionMode: true),
                    ),
                  ),
                ),
              ),
            ),
          )
        : browserBottomBar;
    if (_isActiveTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_isActiveTab) return;
        _chrome.setBottomBar(widget.tabId, embeddedBottomBar);
      });
    }

    final currentItemsSignature = _floatingActionItemsSignature();
    final floatingActionSignature = Object.hash(
      _toolbarConfigReady,
      _toolbarConfig,
      useFab,
      hasClipboardFab,
      selectionBarVisible,
      _searchActive,
      _currentDirPath,
      _currentFilter,
      _archiveContext?.hashCode,
      _layoutMode,
      sortBy,
      sortAscending,
      Object.hashAll(_toolbarConfig.visible),
      currentItemsSignature,
      showBookmarkBarInViewport,
      widget.container.readOnly,
    );
    if (_lastBuiltFloatingActionSignature != floatingActionSignature) {
      _lastBuiltFloatingActionSignature = floatingActionSignature;
      final toolbarActions = useFab
          ? _buildFabToolbar(bottomOffset: 0)
                .whereType<Positioned>()
                .map((positioned) => positioned.child)
                .whereType<Widget>()
                .toList(growable: false)
          : const <Widget>[];
      _lastBuiltFloatingAction = !hasClipboardFab && toolbarActions.isEmpty
          ? null
          : AnimatedPadding(
              duration: AppMotion.short2,
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(
                bottom: showBookmarkBarInViewport ? 48 : 0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (hasClipboardFab)
                    ClipboardFab(
                      onPaste: _isReadOnly ? null : _paste,
                      heroTag:
                          'browser_clipboard_fab_${widget.container.volId}',
                    ),
                  if (hasClipboardFab && toolbarActions.isNotEmpty)
                    const SizedBox(height: 12),
                  if (toolbarActions.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (
                          var index = 0;
                          index < toolbarActions.length;
                          index++
                        )
                          if (index == 0)
                            toolbarActions[index]
                          else ...[
                            const SizedBox(width: 12),
                            toolbarActions[index],
                          ],
                      ],
                    ),
                ],
              ),
            );
    }
    final embeddedFloatingAction = _lastBuiltFloatingAction;
    if (_toolbarConfigReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _lastBuiltFloatingActionSignature != floatingActionSignature ||
            _lastPublishedFloatingActionSignature == floatingActionSignature) {
          return;
        }
        _lastPublishedFloatingActionSignature = floatingActionSignature;
        _chrome.setFloatingAction(widget.tabId, embeddedFloatingAction);
      });
    }

    final Widget browserBody = Stack(
      children: [
        SafeArea(
          bottom: false,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Row(
                            children: [
                              if (isLandscape && showBookmarkBar)
                                BookmarkBar(
                                  bookmarkPaths: _bookmarkPaths,
                                  axis: Axis.vertical,
                                  onTapItem: (path) {
                                    final isDir =
                                        !path.split('/').last.contains('.') ||
                                        path.endsWith('/');
                                    _navigateToPath(path, isDir: isDir);
                                  },
                                  onRemoveBookmark: (path) =>
                                      _pinsBookmarksNotifier.removeBookmark(
                                        widget.container,
                                        path,
                                      ),
                                ),
                              Expanded(
                                child: Column(
                                  children: [
                                    if (_toolbarConfig.showBreadcrumbBar)
                                      BreadcrumbBar(
                                        stack: _pathStack,
                                        onTap: _jumpTo,
                                      ),
                                    if (!widget.container.isLocalStorage &&
                                        _archiveContext == null)
                                      const SyncStatusBanner(),

                                    Expanded(
                                      child: Stack(
                                        children: [
                                          KeyedSubtree(
                                            key: ValueKey(_currentDirPath),
                                            child: buildBrowserBody(
                                              context,
                                              filteredItems,
                                              isLoading: _isLoading,
                                              currentItems: _currentItems,
                                              atRoot: _atRoot,
                                              onNavigateUp: _atRoot
                                                  ? null
                                                  : _navigateUp,
                                              searchQuery: _searchQuery,
                                              layoutMode: _layoutMode,
                                              container: widget.container,
                                              currentDirPath: _currentDirPath,
                                              thumbnailCacheMode:
                                                  _resolvedThumbnailCacheMode,
                                              thumbnailQuality:
                                                  _resolvedThumbnailQuality,
                                              toolbarConfig: _toolbarConfig,
                                              isSelectionMode: isSelectionMode,
                                              selectedItems: selectedItems,
                                              searchActive: _searchActive,
                                              mountedDocProviderFolders:
                                                  _mountedDocProviderFolders,
                                              isFolderMounted: _isFolderMounted,
                                              isPinned: _isPinned,
                                              isBookmark: _isBookmark,
                                              isFolderSynced: _isFolderSynced,
                                              onDirTap: _handleDirTap,
                                              onFileTap: _handleFileTap,
                                              onItemLongPress:
                                                  _handleItemLongPress,
                                              onIconTap: _handleIconTap,
                                              onItemMoreTap:
                                                  _showItemActionsSheet,
                                              onSelectionChanged:
                                                  setSelectedItems,
                                              onGridColumnCountChanged: (count) {
                                                _toolbarConfig = isLandscape
                                                    ? _toolbarConfig.copyWith(
                                                        gridColumnsLandscape:
                                                            count,
                                                      )
                                                    : _toolbarConfig.copyWith(
                                                        gridColumnsPortrait:
                                                            count,
                                                      );
                                                _toolbarSvc.save(
                                                  _toolbarConfig,
                                                );
                                                final effectiveToolbarUri =
                                                    widget
                                                        .container
                                                        .isLocalStorage
                                                    ? null
                                                    : widget.container.uri;
                                                ref
                                                    .read(
                                                      fileManagerToolbarSettingsProvider(
                                                        effectiveToolbarUri,
                                                      ).notifier,
                                                    )
                                                    .applyImportedConfig(
                                                      _toolbarConfig,
                                                    );
                                              },
                                              onMasonryColumnCountChanged: (count) {
                                                _toolbarConfig = isLandscape
                                                    ? _toolbarConfig.copyWith(
                                                        masonryColumnsLandscape:
                                                            count,
                                                      )
                                                    : _toolbarConfig.copyWith(
                                                        masonryColumnsPortrait:
                                                            count,
                                                      );
                                                _toolbarSvc.save(
                                                  _toolbarConfig,
                                                );
                                                final effectiveToolbarUri =
                                                    widget
                                                        .container
                                                        .isLocalStorage
                                                    ? null
                                                    : widget.container.uri;
                                                ref
                                                    .read(
                                                      fileManagerToolbarSettingsProvider(
                                                        effectiveToolbarUri,
                                                      ).notifier,
                                                    )
                                                    .applyImportedConfig(
                                                      _toolbarConfig,
                                                    );
                                              },
                                              onListZoomLevelChanged: (newZoom) {
                                                setState(() {
                                                  _toolbarConfig =
                                                      _toolbarConfig.copyWith(
                                                        listZoomLevel: newZoom,
                                                      );
                                                });
                                                _toolbarSvc.save(
                                                  _toolbarConfig,
                                                );
                                                final effectiveToolbarUri =
                                                    widget
                                                        .container
                                                        .isLocalStorage
                                                    ? null
                                                    : widget.container.uri;
                                                ref
                                                    .read(
                                                      fileManagerToolbarSettingsProvider(
                                                        effectiveToolbarUri,
                                                      ).notifier,
                                                    )
                                                    .applyImportedConfig(
                                                      _toolbarConfig,
                                                    );
                                              },
                                              onRefresh: () {
                                                FolderThumbnailPreview.clearSessionCache();
                                                return _loadDirectoryContents(
                                                  _currentDirPath,
                                                  refresh: true,
                                                );
                                              },
                                              isListingTruncated:
                                                  _isListingTruncated,
                                              scrollController:
                                                  _browserScrollController,
                                              archiveContext: _archiveContext,
                                              archiveRootPath:
                                                  _archiveRootPathForSearch,
                                              sortBy: sortBy,
                                            ),
                                          ),
                                          if (_backGestureProgress != null)
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    if (_backGestureProgress! >=
                                                            0.18 &&
                                                        sortedPreviewItems !=
                                                            null) ...[
                                                      ColoredBox(
                                                        color: Theme.of(
                                                          context,
                                                        ).scaffoldBackgroundColor,
                                                      ),
                                                      buildBrowserBody(
                                                        context,
                                                        sortedPreviewItems,
                                                        isLoading: false,
                                                        currentItems:
                                                            sortedPreviewItems,
                                                        atRoot:
                                                            _backGesturePreviewAtRoot,
                                                        onNavigateUp: null,
                                                        searchQuery: '',
                                                        layoutMode:
                                                            _backGesturePreviewLayoutMode ??
                                                            _layoutMode,
                                                        container:
                                                            widget.container,
                                                        currentDirPath:
                                                            previewDirPath,
                                                        thumbnailCacheMode:
                                                            _resolvedThumbnailCacheMode,
                                                        thumbnailQuality:
                                                            _resolvedThumbnailQuality,
                                                        toolbarConfig:
                                                            _toolbarConfig,
                                                        isSelectionMode: false,
                                                        selectedItems: const {},
                                                        searchActive: false,
                                                        mountedDocProviderFolders:
                                                            _mountedDocProviderFolders,
                                                        isFolderMounted: (e) =>
                                                            isFolderMounted(
                                                              e,
                                                              previewDirPath,
                                                              _mountedDocProviderFolders,
                                                            ),
                                                        isPinned: (e) =>
                                                            isPinned(
                                                              e,
                                                              previewDirPath,
                                                              _pinnedPaths,
                                                            ),
                                                        isBookmark: (e) =>
                                                            isBookmark(
                                                              e,
                                                              previewDirPath,
                                                              _bookmarkPaths,
                                                            ),
                                                        isFolderSynced:
                                                            _isFolderSynced,
                                                        onDirTap: (_) {},
                                                        onFileTap: (_) {},
                                                        onItemLongPress: (_) {},
                                                        onIconTap: (_) {},
                                                        onItemMoreTap: (_) {},
                                                        onGridColumnCountChanged:
                                                            (_) {},
                                                        onMasonryColumnCountChanged:
                                                            (_) {},
                                                        onListZoomLevelChanged:
                                                            (_) {},
                                                        onRefresh: () async {},
                                                        isListingTruncated:
                                                            false,
                                                        scrollController:
                                                            _backGesturePreviewScrollController,
                                                        archiveContext:
                                                            previewArchiveContext,
                                                        archiveRootPath:
                                                            previewArchiveRootPath,
                                                        sortBy: sortBy,
                                                      ),
                                                    ],
                                                    Opacity(
                                                      opacity: _fadeScrimOpacity(
                                                        _backGestureProgress!,
                                                      ),
                                                      child: ColoredBox(
                                                        color: Theme.of(
                                                          context,
                                                        ).scaffoldBackgroundColor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          AnimatedPositioned(
                            duration: AppMotion.short2,
                            curve: Curves.easeOutCubic,
                            left: 0,
                            right: 0,
                            bottom: bannerBottomOffset,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 600,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_statusMessage != null)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          bottom: _searchActive ? 16 : 8,
                                          left: 16,
                                          right: 16,
                                        ),
                                        child: AnimatedSwitcher(
                                          duration: AppMotion.short2,
                                          child: InlineBanner(
                                            _statusMessage!,
                                            key: ValueKey(_statusBannerKey),
                                            tone: _statusIsError
                                                ? AppBannerTone.error
                                                : AppBannerTone.info,
                                            trailing: _mediaScanInProgress
                                                ? TextButton(
                                                    style: TextButton.styleFrom(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                          ),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                    onPressed: _cancelMediaScan,
                                                    child: Text(
                                                      context.l10n.cancel,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                                    if (_searchActive)
                                      BottomSearchBar(
                                        initialQuery: _searchQuery,
                                        onChanged: _onSearchQueryChanged,
                                        isDeepSearch: _isDeepSearch,
                                        onDeepSearchToggle:
                                            _onDeepSearchToggled,
                                        isSearchingSubfolders:
                                            _isSearchingSubfolders,
                                        onClose: () =>
                                            setState(() => _clearSearch()),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasBookmarkBarViewportSlot)
                      AnimatedSize(
                        duration: AppMotion.short2,
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.bottomCenter,
                        child: showBookmarkBar
                            ? buildHorizontalBookmarkBar()
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final Widget screen = AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayStyle,
      child: PopScope(
        canPop: canPop,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop || !_isActiveTab) return;
          _onSystemBack();
        },
        child: browserBody,
      ),
    );
    return screen;
  }
}
