import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
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
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';
import 'package:vaultexplorer/features/browser/archive_file_viewer.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_operations_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_pins_bookmarks_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_search_controller.dart';
import 'package:vaultexplorer/features/browser/widgets/archive_paste_options_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/file_browser_doc_provider_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_sort_controller.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/file_open_dispatch.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/services/folder_document_provider_service.dart';
import 'package:vaultexplorer/features/browser/services/media_scan_service.dart';
import 'package:vaultexplorer/features/browser/viewer/html_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown_viewer_screen.dart';
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
import 'package:vaultexplorer/features/browser/widgets/browser_body_builder.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/delete_originals_dialog.dart';
import 'package:vaultexplorer/features/browser/widgets/file_item_actions_sheet.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/file_manager_action_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/filter_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_document_provider_sheet.dart';
import 'package:vaultexplorer/features/sync/services/sync_providers.dart';
import 'package:vaultexplorer/features/sync/services/sync_status.dart';
import 'package:vaultexplorer/features/sync/ui/sync_status_banner.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_thumbnail_preview.dart';
import 'package:vaultexplorer/features/browser/widgets/layout_mode_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/open_with_dialog.dart';
import 'package:vaultexplorer/features/browser/widgets/sort_menu_button.dart';
import 'package:vaultexplorer/features/camera/camera_capture_screen.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_screen.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/features/sync/services/sync_providers.dart';
import 'package:vaultexplorer/features/sync/ui/sync_rule_editor_sheet.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/single_file_crypto_sheet.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_detail_screen.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_edit_screen.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

// PathSegment used to be declared in this file; it now lives in the
// navigation controller (see FileBrowserNavigation). Re-exported from here
// rather than updating every other file that imports PathSegment via this
// file (breadcrumb_bar.dart, browser_app_bar_builder.dart,
// vault_browser_sheet.dart, and the decoy/local file explorer's own
// screens/controllers, which reuse the same type) -- keeps this a pure
// relocation with zero blast radius on unrelated files.
export 'controllers/file_browser_navigation_controller.dart' show PathSegment;

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

class FileBrowserScreen extends ConsumerStatefulWidget {
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
  final Widget? drawer;

  const FileBrowserScreen({
    super.key,
    required this.container,
    this.thumbnailCacheMode,
    this.thumbnailQuality,
    this.onUserActivity,
    this.resolveContainer,
    this.showBackButton = true,
    this.wrapAppBarTitle,
    this.onOpenStorageSwitcher,
    this.drawer,
  });

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  double _drawerDragDistance = 0.0;
  bool _isTouchFromEdge = false;
  // ── Navigation (FileBrowserNavigation controller) ────────────────────────
  // pathStack/currentItems/isLoading/isListingTruncated/statusMessage/
  // statusIsError/freeSpace/layoutMode/currentFilter/archiveContext/
  // isContainerLocked/back-gesture-preview state all moved to
  // fileBrowserNavigationProvider(volId) -- see
  // controllers/file_browser_navigation_controller.dart. Kept as
  // same-named getters (matching the existing _search/_pinsBookmarks/
  // _mountedDocProviderFolders pattern already used in this file) so the
  // hundreds of read call-sites throughout this file don't need to change.
  FileBrowserNavigationState get _nav =>
      ref.watch(fileBrowserNavigationProvider(widget.container.volId));
  FileBrowserNavigation get _navNotifier =>
      ref.read(fileBrowserNavigationProvider(widget.container.volId).notifier);

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
  BrowserLayoutMode? get _backGesturePreviewLayoutMode => _nav.backGesturePreviewLayoutMode;
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

  late final AnimationController _appBarAnimController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1.0,
  );

  ScrollController _browserScrollController = ScrollController();
  ScrollController _backGesturePreviewScrollController = ScrollController();

  void _resetBrowserScrollController({double initialOffset = 0.0}) {
    final old = _browserScrollController;
    _browserScrollController = ScrollController(initialScrollOffset: initialOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
    });
  }

  void _resetBackGesturePreviewScrollController({double initialOffset = 0.0}) {
    final old = _backGesturePreviewScrollController;
    _backGesturePreviewScrollController =
        ScrollController(initialScrollOffset: initialOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    // Freeze app bar collapse while 2 fingers are on screen so it doesn't fight pinch gestures
    if (_isMultiTouch || _pointerCount >= 2) return false;

    // Keep app bar locked open if disabled in settings, or when in selection/search
    if (!_toolbarConfig.autoHideAppBar) {
      if (_appBarAnimController.value < 1.0) {
        _appBarAnimController.value = 1.0;
      }
      return false;
    }
  if (_searchActive) {
      if (_appBarAnimController.value < 1.0) {
        _appBarAnimController.value = 1.0;
      }
      return false;
    }

    final canScroll = notification.metrics.maxScrollExtent > 0.0;

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      final pixels = notification.metrics.pixels;

      if (isSelectionMode) {
        // In selection mode: never collapse (delta > 0).
        // If app bar was hidden, allow scrolling up (delta < 0) or pulling at top to reveal it.
        if ((delta < 0.0 || pixels <= 0.0) && _appBarAnimController.value < 1.0) {
          final newFactor = (_appBarAnimController.value - (delta / kToolbarHeight)).clamp(0.0, 1.0);
          if (newFactor != _appBarAnimController.value) {
            _appBarAnimController.value = newFactor;
          }
        }
        return false;
      }

      // On a scrollable list, lock to fully open only when actively scrolling down
      // into the top boundary (delta <= 0). If dragging up (delta > 0), allow collapsing.
      if (canScroll && pixels <= 0.0 && delta <= 0.0) {
        if (_appBarAnimController.value != 1.0) {
          _appBarAnimController.value = 1.0;
        }
      } else if (delta != 0.0) {
        final newFactor = (_appBarAnimController.value - (delta / kToolbarHeight)).clamp(0.0, 1.0);
        if (newFactor != _appBarAnimController.value) {
          _appBarAnimController.value = newFactor;
        }
      }
    } else if (notification is OverscrollNotification) {
      final overscroll = notification.overscroll;
      if (overscroll < 0.0) {
        // Pulling down reveals the app bar
        final newFactor = (_appBarAnimController.value - (overscroll / kToolbarHeight)).clamp(0.0, 1.0);
        if (newFactor != _appBarAnimController.value) {
          _appBarAnimController.value = newFactor;
        }
      } else if (overscroll > 0.0 && !isSelectionMode) {
        // Pulling up past the bottom hides the app bar (only in normal mode)
        final newFactor = (_appBarAnimController.value - (overscroll / kToolbarHeight)).clamp(0.0, 1.0);
        if (newFactor != _appBarAnimController.value) {
          _appBarAnimController.value = newFactor;
        }
      }
    } else if (notification is ScrollEndNotification) {
      final pixels = notification.metrics.pixels;
      // Force snap-open on release if at the very top or if in selection mode and partially open
      if (canScroll && pixels <= 0.0) {
        if (_appBarAnimController.value != 1.0) {
          _appBarAnimController.animateTo(1.0, duration: AppMotion.short2, curve: Curves.easeOutCubic);
        }
      } else if (isSelectionMode && _appBarAnimController.value > 0.0 && _appBarAnimController.value < 1.0) {
        _appBarAnimController.animateTo(1.0, duration: AppMotion.short2, curve: Curves.easeOutCubic);
      } else if (!isSelectionMode && _appBarAnimController.value > 0.0 && _appBarAnimController.value < 1.0) {
        final target = _appBarAnimController.value >= 0.5 ? 1.0 : 0.0;
        _appBarAnimController.animateTo(
          target,
          duration: AppMotion.short2,
          curve: Curves.easeOutCubic,
        );
      }
    }

    return false;
  }

  Future<void> _saveExtensionPreference(String ext, String preference) async {
  final cleanExt = ext.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim();
  if (cleanExt.isEmpty) return;

  _appSettings.extensionPreferences[cleanExt] = preference;

  try {
    final currentSettings = ref.read(appSettingsControllerProvider).settings;
    final newPrefs = Map<String, String>.from(currentSettings.extensionPreferences);
    newPrefs[cleanExt] = preference;

    await ref.read(appSettingsControllerProvider.notifier).updateSettings(
          (s) => s.copyWith(extensionPreferences: newPrefs),
        );
  } catch (_) {
    // Fallback directly to AppSettingsService if controller is not yet active
    await ref.read(appSettingsServiceProvider).saveSettings(_appSettings);
  }
}

  CrossContainerClipboard get _clip => ref.read(crossContainerClipboardProvider.notifier);
  late final FileOperationService _opSvc;
  late final dynamic _vaultEvents;
  FolderDocumentProviderService get _docProviderService =>
      ref.read(folderDocumentProviderServiceProvider);
  FileManagerToolbarService get _toolbarSvc => ref.read(fileManagerToolbarServiceProvider);

  FileBrowserSearchState get _search => ref.watch(fileBrowserSearchProvider(widget.container.volId));
  FileBrowserSearch get _searchNotifier =>
      ref.read(fileBrowserSearchProvider(widget.container.volId).notifier);

  bool get _searchActive => _search.active;
  String get _searchQuery => _search.query;
  bool get _isDeepSearch => _search.isDeepSearch;
  bool get _isSearchingSubfolders => _search.isSearchingSubfolders;
  List<RawEntry> get _deepSearchResults => _search.deepSearchResults;

  /// Resolves the archive-root path the search controller needs (see
  /// file_browser_search_controller.dart's header) -- kept here since it's
  /// a _pathStack lookup, and _pathStack stays screen-owned.
  String? get _archiveRootPathForSearch =>
      _archiveContext == null ? null : _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;


  AppSettings _appSettings = AppSettings();
  ThumbnailCacheMode _resolvedThumbnailCacheMode = ThumbnailCacheMode.appCache;
  ThumbnailQuality _resolvedThumbnailQuality = ThumbnailQuality.defaultQuality;
  FileManagerToolbarConfig _toolbarConfig = FileManagerToolbarConfig.defaults();
  FileBrowserPinsBookmarksState get _pinsBookmarks =>
      ref.watch(fileBrowserPinsBookmarksProvider(widget.container.volId));
  FileBrowserPinsBookmarks get _pinsBookmarksNotifier =>
      ref.read(fileBrowserPinsBookmarksProvider(widget.container.volId).notifier);
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
  bool _isPinned(RawEntry entry) => isPinned(entry, _currentDirPath, _pinnedPaths);
  bool _isBookmark(RawEntry entry) => isBookmark(entry, _currentDirPath, _bookmarkPaths);
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
    if (_pinnedPaths.isNotEmpty) {
      final aPinned = _isPinned(ea);
      final bPinned = _isPinned(eb);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
    }
    if (ea.isDir != eb.isDir) {
      return ea.isDir ? -1 : 1;
    }
    return compareItems(ea, eb);
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
  bool _isVisibleInCurrentListing(RawEntry item, String query, {bool skipQueryCheck = false}) {
    if (!_toolbarConfig.showHiddenFiles && isHiddenEntryName(item.name)) {
      return false;
    }
    if (!skipQueryCheck) {
      final name = item.name;
      if (query.isNotEmpty && !name.toLowerCase().contains(query)) return false;
    }
    if (item.isDir) {
      if (query.isEmpty && _currentFilter != null) return false;
      return true;
    }
    return _matchesFilter(item.name);
  }

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
  List<RawEntry> _searchAwareVisibleItems(List<RawEntry> localItems, String query) {
    if (!_searchActive || query.isEmpty) {
      return localItems.where((item) => _isVisibleInCurrentListing(item, query)).toList();
    }
    if (_isDeepSearch) {
      return _deepSearchResults
          .where((item) => _isVisibleInCurrentListing(item, query, skipQueryCheck: true))
          .toList();
    }
    final instant = localItems.where((item) => _isVisibleInCurrentListing(item, query)).toList();
    final instantLowerNames = instant.map((e) => e.lowercaseName).toSet();
    final contentOnlyMatches = _deepSearchResults.where(
      (item) =>
          !instantLowerNames.contains(item.lowercaseName) &&
          _isVisibleInCurrentListing(item, query, skipQueryCheck: true),
    );
    return [...instant, ...contentOnlyMatches];
  }

  void _onContainerLockedEvent(int volId) {
    if (_disposed || volId != widget.container.volId || !mounted) return;
    _navNotifier.setContainerLocked(true);
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  DateTime? _lastOpReloadTime;
  Timer? _opReloadTimer;

  int _pointerCount = 0;
  bool _isMultiTouch = false;

  void _handlePointerDown(PointerDownEvent event) {
    _pointerCount++;
    if (_pointerCount >= 2) {
      _isMultiTouch = true;
    }
    final edgeInset = math.max(
      72.0,
      MediaQuery.systemGestureInsetsOf(context).left,
    );
    _isTouchFromEdge = event.position.dx <= edgeInset;
    _drawerDragDistance = 0.0;
  }

  void _handlePointerUp(PointerEvent event) {
    _pointerCount = math.max(0, _pointerCount - 1);
    if (_pointerCount < 2) {
      _isMultiTouch = false;
    }
    if (_pointerCount == 0) {
      _drawerDragDistance = 0.0;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pointerCount = 0;
    _isMultiTouch = false;
    _drawerDragDistance = 0.0;
  }

  void _onOperationsChanged() {
    if (!mounted) return;
    setState(() {});

    final hasActiveTargetingCurrent = _opSvc.activeOperations.any(
      (op) =>
          !op.isDelete &&
          op.destVolId == widget.container.volId &&
          (op.destDirPath == _currentDirPath ||
              op.destDirPath.startsWith(
                _currentDirPath.isEmpty ? '' : '$_currentDirPath/',
              )),
    );
    if (!hasActiveTargetingCurrent) return;

    final now = DateTime.now();
    final last = _lastOpReloadTime;
    if (last == null || now.difference(last) > const Duration(milliseconds: 350)) {
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

  @override
  void initState() {
    super.initState();
    _opSvc = ref.read(fileOperationServiceProvider);
    _vaultEvents = ref.read(vaultEngineEventsProvider);

    _opSvc.addListener(_onOperationsChanged);
    WidgetsBinding.instance.addObserver(this);
    _vaultEvents.addContainerLockedListener(_onContainerLockedEvent);
    _vaultEvents.addUsbContainerDetachedListener(_onContainerDetached);
  }



  @override
  void dispose() {
    _disposed = true;
    _mediaScanToken?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _opReloadTimer?.cancel();
    _opSvc.removeListener(_onOperationsChanged);
    _appBarAnimController.dispose();
    _browserScrollController.dispose();
    _backGesturePreviewScrollController.dispose();
    _vaultEvents.removeContainerLockedListener(_onContainerLockedEvent);
    _vaultEvents.removeUsbContainerDetachedListener(_onContainerDetached);
    super.dispose();
  }

  void _scrollToItem(String fullPath) {
    if (!_browserScrollController.hasClients) return;

    final query = _searchQuery.trim().toLowerCase();
    final sortedItems = _searchAwareVisibleItems(_currentItems, query).toList()
      ..sort(_compareOverall);

    final targetIndex = sortedItems.indexWhere((e) {
      final itemFullPath = (_searchActive && _isDeepSearch && e.name.contains('/'))
          ? e.name
          : (_currentDirPath.isEmpty ? e.name : '$_currentDirPath/${e.name}');
      return itemFullPath == fullPath;
    });

    if (targetIndex == -1) return;

    final position = _browserScrollController.position;
    final maxScroll = position.maxScrollExtent;
    final viewportHeight = position.viewportDimension;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

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
        final columns = (isLandscape
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
        final columns = (isLandscape
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
              : (_currentDirPath.isEmpty ? entry.name : '$_currentDirPath/${entry.name}');

          double ratio = 1.0;
          if (!entry.isDir) {
            final cachedRatio = MediaAspectRatioCache.get(widget.container, fullEntryPath);
            if (cachedRatio != null && cachedRatio > 0) {
              ratio = cachedRatio.clamp(0.5, 2.2);
            } else if (MediaViewerConstants.isVideo(entry.name)) {
              ratio = (16.0 / 9.0).clamp(0.5, 2.2);
            }
          }

          final hasLabel = showNames ||
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
        (itemTop + itemHeight) <= currentOffset + viewportHeight - bottomMargin) {
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
      final key = '${widget.container.uri}:$dirPath';
      final savedModeStr = _toolbarConfig.folderLayoutModes[key];
      if (savedModeStr != null) {
        final savedMode = BrowserLayoutMode.fromJson(savedModeStr);
        if (savedMode != null) return savedMode;
      }
    }
    return effectiveAppSettings.defaultLayoutMode;
  }

void _showItemActionsSheet(RawEntry entry) {
    _signalActivity();
    HapticFeedback.selectionClick();
    final fullPath = _fullPathOf(entry);
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
          onSuccess: () => _loadDirectoryContents(_currentDirPath, refresh: true),
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
            void listener() {
              if (!mounted) {
                op.removeListener(listener);
                return;
              }
              final done = op.status != FileOperationStatus.running &&
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
      onTogglePin: () async {
        await _pinsBookmarksNotifier.togglePins(
          widget.container,
          [fullPath],
          pin: !_isPinned(entry),
        );
      },
      onToggleBookmark: () async {
        await _pinsBookmarksNotifier.toggleBookmarks(
          widget.container,
          [fullPath],
          bookmark: !_isBookmark(entry),
        );
      },
      onInfo: () {
        FileInfoSheet.show(
          context,
          container: widget.container,
          entry: entry,
          currentDirPath: _currentDirPath,
        );
      },
      onOpenWith: !entry.isDir
          ? () async {
              final parts = entry.name.split('.');
              final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
              final settings =
                  await ref.read(appSettingsServiceProvider).loadSettings();
              if (mounted) {
                await _showOpenWithDialog(entry.name, fullPath, ext, settings);
              }
            }
          : null,
      onShare: !entry.isDir
          ? () async {
              final ok = widget.container.isLocalStorage
                  ? await ref.read(vaultLocalShareApiProvider).shareLocalFiles(
                      [p.join(widget.container.uri, fullPath)],
                    )
                  : await ref.read(vaultFileIoApiProvider).shareFiles(
                      widget.container,
                      [fullPath],
                    );
              if (!ok && mounted) {
                _setStatus(context.l10n.couldNotShareFiles, error: true);
              }
            }
          : null,
      onEditImage: (!entry.isDir && MediaViewerConstants.isImage(entry.name))
          ? () => _editImage(entry.name, fullPath)
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
          entry.isDir && !widget.container.isLocalStorage && _archiveContext == null
          ? () => _showSyncSettings(entry)
          : null,
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
    final ok = await _docProviderNotifier.toggle(widget.container, path, entry.name);
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(context, message: context.l10n.couldNotExpose(entry.name));
      return;
    }
    showAppSnackBar(context, message: context.l10n.nowAvailableToOtherApps(entry.name));
  }

  Future<void> _unmountFolderDocumentProvider(RawEntry entry) async {
    final path = _fullPathOf(entry);
    final ok = await _docProviderNotifier.unmount(widget.container, path);
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(context, message: context.l10n.couldNotUnmount(entry.name));
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
    final matches = record?.documentProviderFolders.where((f) => f.path == path) ?? const [];
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
    final pathsToToggle = selectedItems.map((e) => _fullPathOf(e)).toList();
    await _pinsBookmarksNotifier.toggleBookmarks(widget.container, pathsToToggle, bookmark: bookmark);
    final count = pathsToToggle.length;
    _setStatus(
      bookmark
          ? context.l10n.bookmarkedCount(count)
          : context.l10n.unbookmarkedCount(count),
    );
    exitSelectionMode();
  }

  Future<void> _togglePinSelected({required bool pin}) async {
    _signalActivity();
    final pathsToToggle = selectedItems.map((e) => _fullPathOf(e)).toList();
    await _pinsBookmarksNotifier.togglePins(widget.container, pathsToToggle, pin: pin);
    final count = pathsToToggle.length;
    _setStatus(
      pin ? context.l10n.pinnedCount(count) : context.l10n.unpinnedCount(count),
    );
    exitSelectionMode();
  }

  bool get _isReadOnly => widget.container.readOnly;
  void _signalActivity() => widget.onUserActivity?.call();
  void _onContainerDetached(int volId) {
    if (_disposed || volId != widget.container.volId || !mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _initSettingsAndContents() async {
    _navNotifier.setLoading(true);
    _pinsBookmarksNotifier.load(widget.container);
    try {
      final appSettings = await ref.read(appSettingsServiceProvider).loadSettings();
      final records = await ref.read(containerRepositoryProvider).loadAll();
      final record = records[widget.container.uri];
      final toolbarConfig = await _toolbarSvc.load();
      if (mounted) {
        setState(() {
          _appSettings = appSettings;
          _toolbarConfig = toolbarConfig;
          _resolvedThumbnailCacheMode =
              widget.thumbnailCacheMode ??
              record?.thumbnailCacheMode ??
              toolbarConfig.defaultThumbnailCacheMode;
          _resolvedThumbnailQuality =
              widget.thumbnailQuality ??
              record?.thumbnailQuality ??
              toolbarConfig.defaultThumbnailQuality;
        });
        _navNotifier.setLayoutMode(
          _getLayoutModeForFolder(_currentDirPath, appSettings: appSettings),
        );
        ref
            .read(fileBrowserSortProvider(widget.container.volId).notifier)
            .restore(
              appSettings.defaultFileSortBy,
              appSettings.defaultFileSortAscending,
            );
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
      _resolvedThumbnailCacheMode =
          widget.thumbnailCacheMode ??
          record?.thumbnailCacheMode ??
          config.defaultThumbnailCacheMode;
      _resolvedThumbnailQuality =
          widget.thumbnailQuality ??
          record?.thumbnailQuality ??
          config.defaultThumbnailQuality;
    });
    if (!config.autoHideAppBar && _appBarAnimController.value < 1.0) {
      _appBarAnimController.value = 1.0;
    }
    _navNotifier.setLayoutMode(_getLayoutModeForFolder(_currentDirPath));
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
    final delay = autoClear ?? (error ? const Duration(seconds: 5) : const Duration(seconds: 3));
    Future.delayed(delay, () {
      if (mounted && _statusMessage == msg) {
        _navNotifier.clearStatus();
      }
    });
  }

  void _clearStatus() {
    if (mounted) _navNotifier.clearStatus();
  }

  Future<void> _loadDirectoryContents(String path, {bool refresh = false}) async {
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
        );

        if (ctx.status == ArchiveOpenStatus.ok) {
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

  void _closeArchive() {
    _navNotifier.closeArchive();
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
    final currentOffset =
        _browserScrollController.hasClients ? _browserScrollController.offset : 0.0;
    final newPath = _fullPathOf(entry);
    _navNotifier.enterDirectory(
      entry,
      newPath: newPath,
      layoutMode: _getLayoutModeForFolder(newPath),
      currentScrollOffset: currentOffset,
    );
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
      _clearSearch();
      await _loadDirectoryContents(newPath);
    } else {
      final parentPath = segments.length > 1 ? segments.sublist(0, segments.length - 1).join('/') : '';
      final fileName = segments.last;
      _navNotifier.navigateToPath(
        widget.container,
        fullPath,
        isDir: false,
        rootLabel: context.l10n.rootFolderLabel,
        layoutMode: _getLayoutModeForFolder(parentPath),
        resolveLayoutMode: _getLayoutModeForFolder,
      );
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
    final targetSegment =
        _pathStack.length >= 2 ? _pathStack[_pathStack.length - 2] : null;
    final savedOffset = targetSegment?.scrollOffset ?? 0.0;
    _resetBrowserScrollController(initialOffset: savedOffset);

    final parentPath = targetSegment?.fatPath ?? '';
    final parentLayoutMode = _getLayoutModeForFolder(parentPath);

    final newPath = _navNotifier.navigateUp(layoutMode: parentLayoutMode);
    if (newPath == null) return;
    _clearSearch();
    _loadDirectoryContents(newPath);
  }

  bool get _canPreviewFolderBackGesture =>
      !_atRoot && !isSelectionMode && !_searchActive;
  bool get _isOwnRouteCurrent => ModalRoute.of(context)?.isCurrent ?? false;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    _drawerDragDistance = 0.0;
    _isTouchFromEdge = true;

    if (!_isOwnRouteCurrent) return false;
    if (backEvent.isButtonEvent || !_canPreviewFolderBackGesture) return false;
    final targetSegment =
        _pathStack.length >= 2 ? _pathStack[_pathStack.length - 2] : null;
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
    _drawerDragDistance = 0.0;
    _isTouchFromEdge = true;
    if (!_isOwnRouteCurrent) return;
    _navNotifier.updateBackGestureProgress(backEvent.progress);
  }

  @override
  void handleCancelBackGesture() {
    _drawerDragDistance = 0.0;
    if (!_isOwnRouteCurrent) return;
    _navNotifier.cancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    _drawerDragDistance = 0.0;
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
    final targetSegment =
        index >= 0 && index < _pathStack.length ? _pathStack[index] : null;
    final savedOffset = targetSegment?.scrollOffset ?? 0.0;
    _resetBrowserScrollController(initialOffset: savedOffset);
    final newPath = _navNotifier.jumpTo(index);
    if (newPath == null) return;
    _navNotifier.setLayoutMode(_getLayoutModeForFolder(newPath));
    _clearSearch();
    _loadDirectoryContents(newPath);
  }

  // ── Selection (FileBrowserSelection controller) ──────────────────────────
  Set<RawEntry> get selectedItems =>
      ref.read(fileBrowserSelectionProvider(widget.container.volId)).items;
  bool get isSelectionMode =>
      ref.read(fileBrowserSelectionProvider(widget.container.volId)).isSelectionMode;
  int get selectedFolderCount =>
      ref.read(fileBrowserSelectionProvider(widget.container.volId)).selectedFolderCount;
  int get selectedTotalBytes =>
      ref.read(fileBrowserSelectionProvider(widget.container.volId)).selectedTotalBytes;
  bool get hasPendingFolderSizes =>
      ref.read(fileBrowserSelectionProvider(widget.container.volId)).hasPendingFolderSizes;

  void toggleSelectItem(RawEntry item) {
    ref.read(fileBrowserSelectionProvider(widget.container.volId).notifier).toggleSelectItem(item);
    if (selectedFolderCount > 0) {
      fetchFolderSizes(widget.container, _currentDirPath);
    }
  }

  void setSelectedItems(Set<RawEntry> newSelection) {
    ref.read(fileBrowserSelectionProvider(widget.container.volId).notifier).setSelectedItems(newSelection);
  }

  void exitSelectionMode() =>
      ref.read(fileBrowserSelectionProvider(widget.container.volId).notifier).exitSelectionMode();

  Future<void> fetchFolderSizes(
    MountedContainer container,
    String currentDirPath,
  ) =>
      ref
          .read(fileBrowserSelectionProvider(widget.container.volId).notifier)
          .fetchFolderSizes(container, currentDirPath);

  // ── Sort (FileBrowserSort controller) ─────────────────────────────────────
  SortBy get sortBy => ref.read(fileBrowserSortProvider(widget.container.volId)).sortBy;
  bool get sortAscending => ref.read(fileBrowserSortProvider(widget.container.volId)).sortAscending;

  void setSort(SortBy by) =>
      ref.read(fileBrowserSortProvider(widget.container.volId).notifier).setSort(by);

  int compareItems(RawEntry ea, RawEntry eb) =>
      ref.read(fileBrowserSortProvider(widget.container.volId)).compare(ea, eb);

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
    final ext = parts.length > 1 ? parts.last.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim() : '';
    if (ArchiveService.isArchive(ext)) {
      await _openArchive(fullPath, entry.name);
      return;
    }
    if (_archiveContext != null) {
      _signalActivity();
      _navNotifier.setLoading(true);
      try {
        final archiveRootPath = _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
        String subPath = '';
        if (fullPath.length > archiveRootPath.length) {
          subPath = fullPath.substring(archiveRootPath.length);
          if (subPath.startsWith('/')) subPath = subPath.substring(1);
        }
        final entryBytes = await _archiveContext!.extractEntry(subPath);
        if (mounted) {
          _navNotifier.setLoading(false);
          if (entryBytes != null) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ArchiveFileViewer(bytes: entryBytes, fileName: entry.name),
              ),
            );
          } else {
            _setStatus(context.l10n.failedToReadFileFromArchive, error: true);
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
      final item = await ref.read(vaultItemsServiceProvider).loadItem(
            widget.container,
            fullPath,
          );
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
    // Audio/HTML are still native, session-based viewers with no
    // local-storage counterpart (see LocalFileIoBackend's doc comment) --
    // checked ahead of `pref` so a per-extension preference saved while
    // browsing a real vault (e.g. "always use the built-in viewer for
    // .html") can't route a local file into a viewer that can't render it.
    // The device's own app already plays/renders a real, already-plaintext
    // file fine, so hand it off there instead. Video is exempt: the native
    // player reads local files directly off disk via its own local branch
    // (see NativePlayerManager.kt's buildMediaSource), so it plays in-app
    // exactly like vault content. PDF is exempt too: PdfViewerScreen has its
    // own isLocalStorage branch (VaultLocalShareApi.getLocalFileUri ->
    // PdfViewerRouter's localUri path), so it also renders in-app.
    final needsSystemAppForLocal = widget.container.isLocalStorage &&
        (MediaViewerConstants.isAudio(entry.name) ||
            ext == 'html' ||
            ext == 'htm');
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
            builder: (_) => TextEditorScreen(container: widget.container, filePath: fullPath),
          ),
        );
        _loadDirectoryContents(_currentDirPath);
      case OpenInMediaViewer():
        await _openMediaViewer(entry.name, fullPath);
      case OpenInPdfViewer():
        await _openPdfViewer(fullPath);
      case OpenInHtmlViewer():
        _openHtmlViewer(fullPath);
      case OpenInMarkdownViewer():
        await _openMarkdownViewer(fullPath);
      case OpenWithSystemApp(packageName: final packageName):
        _openFileWithApp(entry.name, fullPath, packageName: packageName);
      case InstallApk():
        await _installApk(entry.name, fullPath);
      case ShowOpenWithDialog():
        if (!mounted) return;
        await _showOpenWithDialog(entry.name, fullPath, ext, settings);
    }
  }

  Future<void> _openPdfViewer(String fullPath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(container: widget.container, filePath: fullPath),
      ),
    );
    _loadDirectoryContents(_currentDirPath);
  }

  void _openHtmlViewer(String fullPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HtmlViewerScreen(container: widget.container, filePath: fullPath),
      ),
    );
  }

  Future<void> _openMarkdownViewer(String fullPath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MarkdownViewerScreen(container: widget.container, filePath: fullPath),
      ),
    );
    _loadDirectoryContents(_currentDirPath);
  }

  Route<void> _buildMediaViewerRoute({
    required List<String> mediaFiles,
    required int initialIndex,
  }) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) => MediaViewerScreen(
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
        onCurrentFileChanged: _scrollToItem,
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
        // Local storage: images and video play in-app now (see
        // _handleFileTap/NativePlayerManager.kt's local branch); audio
        // still doesn't, so it stays out of the swipeable playlist.
        if (widget.container.isLocalStorage && MediaViewerConstants.isAudio(name)) {
          return false;
        }
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
        pageBuilder: (context, animation, secondaryAnimation) => MediaViewerScreen(
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
      if ((_browserScrollController.offset - initialOffset).abs() > 0.5) {
        _browserScrollController.jumpTo(initialOffset);
      }
    }

    // Only reload directory contents if files were actually modified/deleted in the viewer
    if (result == true || filesDeletedInViewer) {
      _loadDirectoryContents(_currentDirPath, refresh: true);
      _loadToolbarConfig();
    }
  }

  Future<void> _showOpenWithDialog(
  String fileName,
  String fullPath,
  String ext,
  AppSettings settings,
) async {
  final choice = await OpenWithDialog.show(context, fileName: fileName, ext: ext);
  final cleanExt = ext.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim();

  if (choice.action == 'editor') {
    if (choice.remember && cleanExt.isNotEmpty) {
      await _saveExtensionPreference(cleanExt, 'editor');
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TextEditorScreen(container: widget.container, filePath: fullPath),
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
        final normalized = selectedExt.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim();
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

    final localMedia = sortedItems.map((e) => e.name).where(_isSupportedMedia).toList();
    if (localMedia.isNotEmpty) {
      final resolvedPaths = localMedia.map(_joinPath).toList();
      await Navigator.push(
        context,
        _buildMediaViewerRoute(
          mediaFiles: resolvedPaths,
          initialIndex: 0,
        ),
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
      final result = await ref.read(mediaScanServiceProvider).scan(
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
      if (mounted) _setStatus(context.l10n.failedToScanSubfolders('$e'), error: true);
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

  bool _isSupportedMedia(String fileName) => MediaViewerConstants.isSupported(fileName);

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
      final outcome = await ref.read(vaultFileIoApiProvider).installApk(
            widget.container,
            fullPath,
          );
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
          ? await ref.read(vaultLocalShareApiProvider).openLocalFileWithApp(
                p.join(widget.container.uri, fullPath),
                mimeType: mimeType,
              )
          : await ref.read(vaultFileIoApiProvider).openWithApp(
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

  /// Shares every real file in the current selection with another app via
  /// the system share sheet, skipping folders and vault-item pseudo-files
  /// (passwords, secure notes, etc. -- see [VaultItemType]) the same way
  /// [_openFileWithApp] does for a single file. Unlike that one, this
  /// silently drops just the non-shareable entries rather than aborting
  /// the whole action, so sharing five photos alongside one accidentally
  /// co-selected password entry still shares the five photos.
  Future<void> _shareSelected() async {
    final entries = selectedItems.toList();
    exitSelectionMode();

    final shareable = entries.where((e) {
      if (e.isDir) return false;
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

    _signalActivity();
    try {
      // Local storage has no vault session/ContainerDocumentsProvider to
      // stream from -- VaultLocalShareApi exposes the real files directly
      // via its own FileProvider instead (see vault_local_share_api.dart),
      // same split _openFileWithApp makes above.
      final ok = widget.container.isLocalStorage
          ? await ref.read(vaultLocalShareApiProvider).shareLocalFiles(
                shareable.map((e) => p.join(widget.container.uri, _fullPathOf(e))).toList(),
              )
          : await ref.read(vaultFileIoApiProvider).shareFiles(
                widget.container,
                shareable.map(_fullPathOf).toList(),
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

  void _initClipboard({required bool cut}) {
    if (cut && _isReadOnly) {
      _setStatus(context.l10n.readOnlyCantMove, error: true);
      return;
    }
    _signalActivity();
    final clipItems = selectedItems.map((entry) {
      final path = _fullPathOf(entry);
      return ClipboardItem(
        path: path,
        isDir: entry.isDir,
        sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
        modifiedSecs: entry.modifiedSecs,
      );
    }).toList();
    _clip.set(
      volId: widget.container.volId,
      displayName: widget.container.displayName,
      cut: cut,
      clipItems: clipItems,
    );
    exitSelectionMode();
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

    void bindOpListener(FileOperation op) {
      void listener() {
        if (!mounted) {
          op.removeListener(listener);
          return;
        }
        final done = op.status != FileOperationStatus.running &&
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
            _loadDirectoryContents(_currentDirPath, refresh: true).then((_) {
              if (!keepVisible) _opSvc.dismiss(op.id);
            });
          } else if (!keepVisible) {
            _opSvc.dismiss(op.id);
          }
        }
      }
      op.addListener(listener);
    }

    // ── Archive Create Paste ────────────────────────────────────────────
    if (clip.isArchiveCreate) {
      final archiveName = clip.archiveName ?? 'archive.zip';
      final options = await ArchivePasteOptionsSheet.show(
        context,
        isExtract: false,
        archiveName: archiveName,
        destDirPath: _currentDirPath,
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
        deleteSourceAfter: options.deleteSourceAfter,
        l10n: context.l10n,
      );
      _clip.clear();
      bindOpListener(op);
      return;
    }

    // ── Archive Extract Paste ───────────────────────────────────────────
    if (clip.isArchiveExtract) {
      final archiveName = clip.archiveName ?? 'archive.zip';
      final archiveContext = clip.archiveContext;
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
      bindOpListener(op);
      return;
    }

    // ── Standard Copy / Move Paste ──────────────────────────────────────
    // Conflict detection + local-vs-general transfer-mode selection now
    // live in FileBrowserOperationsController (see the note above
    // _fadeScrimOpacity's file for the media-scan equivalent of this
    // note) -- this is just "show the sheet if asked, then hand back to
    // the widget for listener binding", same as before.
    final items = List<ClipboardItem>.from(clip.items);
    final isCut = clip.isCutOperation;
    final op = await ref.read(fileBrowserOperationsControllerProvider).pasteStandardTransfer(
          destContainer: widget.container,
          srcContainer: srcContainer,
          destDirPath: _currentDirPath,
          items: items,
          isCut: isCut,
          isCrossContainer: isCrossContainer,
          resolveConflicts: (conflicts) async {
            if (!mounted) return null;
            return ConflictResolutionSheet.show(context, conflicts: conflicts);
          },
          l10n: context.l10n,
        );
    if (!mounted || op == null) return;
    _clip.clear();
    bindOpListener(op);
  }
 void _batchDelete() {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyCantDelete, error: true);
      return;
    }
    HapticFeedback.heavyImpact();
    _signalActivity();
    BrowserDialogs.showBatchDelete(
      context,
      toDelete: List<RawEntry>.from(selectedItems),
      onConfirmed: (entries) {
        final clipItems = entries.map((e) {
          final path = _fullPathOf(e);
          return ClipboardItem(path: path, isDir: e.isDir);
        }).toList();
        final op = _opSvc.enqueueDelete(
          container: widget.container,
          items: clipItems,
          locationLabel: _currentDirPath,
          l10n: context.l10n,
        );
        exitSelectionMode();
        void listener() {
          if (!mounted) {
            op.removeListener(listener);
            return;
          }
          final done =
              op.status != FileOperationStatus.running && op.status != FileOperationStatus.pending;
          if (!done) return;
          op.removeListener(listener);
          _finishBatchDelete(op);
        }

        op.addListener(listener);
      },
    );
  }

  Future<void> _finishBatchDelete(FileOperation op) async {
    final deletedNames = op.itemStatuses
        .where((s) => s.result == FileItemResult.success)
        .map((s) => s.item.name.toLowerCase())
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

    await _pinsBookmarksNotifier.removeDeletedPaths(widget.container, deletedPaths);
    if (!mounted) return;
    await _loadDirectoryContents(_currentDirPath, refresh: true);
    if (!_opNeedsAttention(op)) _opSvc.dismiss(op.id);
  }

  void _exportSelectedToStorage() {
    _signalActivity();
    final items = selectedItems.map((e) {
      final path = _fullPathOf(e);
      return ClipboardItem(path: path, isDir: e.isDir, sizeBytes: e.sizeBytes);
    }).toList();
    if (items.isEmpty) return;
    exitSelectionMode();
    final op = _opSvc.enqueueExport(
      source: widget.container,
      items: items,
      performExport: (opId) => ref.read(vaultFileIoApiProvider).exportSelectedToFolder(
        widget.container,
        items.map((i) => <String, dynamic>{'path': i.path, 'isDir': i.isDir}).toList(),
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
          op.status != FileOperationStatus.running && op.status != FileOperationStatus.pending;
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
        count > 0 ? context.l10n.exportedCount(count) : context.l10n.exportCancelledOrFailed,
        error: count == 0,
      );
    }

    op.addListener(listener);
  }

  Future<void> _compressSelected() async {
    final entries = selectedItems.toList();
    if (entries.isEmpty) return;
    final currentDirPath = _currentDirPath;
    final existingEntries = _currentItems;
    String stem(RawEntry e) {
      if (e.isDir) return e.name;
      final dot = e.name.lastIndexOf('.');
      return dot > 0 ? e.name.substring(0, dot) : e.name;
    }

    final suggestedName = entries.length == 1
        ? '${stem(entries.first)}.zip'
        : '${currentDirPath.isEmpty ? widget.container.displayName : currentDirPath.split('/').last}.zip';
    exitSelectionMode();
    if (!mounted) return;
    BrowserDialogs.showCreateArchive(
      context,
      container: widget.container,
      currentDirPath: currentDirPath,
      existingEntries: existingEntries,
      suggestedName: suggestedName,
      readOnly: _isReadOnly,
      onCreate: (destPath, format, passphrase) async {
        final clipItems = entries.map((e) {
          final path = _fullPathOf(e);
          return ClipboardItem(
            path: path,
            isDir: e.isDir,
            sizeBytes: e.isDir ? 0 : e.sizeBytes,
            modifiedSecs: e.modifiedSecs,
          );
        }).toList();

        final archiveName = destPath.split('/').last;
        _clip.setArchiveCreate(
          volId: widget.container.volId,
          displayName: widget.container.displayName,
          clipItems: clipItems,
          archiveName: archiveName,
          format: format,
          passphrase: passphrase,
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

      final archivePath = _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;

      final subPathPrefix = _currentDirPath.length > archivePath.length
          ? _currentDirPath.substring(archivePath.length).replaceFirst(RegExp(r'^/+'), '')
          : '';

      final selectedPaths = entries.map((e) {
        final clean = subPathPrefix.isEmpty ? e.name : '$subPathPrefix/${e.name}';
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
    final ext = entry.name.contains('.') ? entry.name.split('.').last.toLowerCase() : '';
    if (entry.isDir || !ArchiveService.isArchive(ext)) return;
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
          wrongPassword: archiveContext.status == ArchiveOpenStatus.wrongPassphrase,
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
      _setStatus('Archive "${entry.name}" staged. Navigate to destination and paste.');
    }
  }
  Future<void> _encryptSelected() => _runQuickCrypto(CryptoDirection.encrypt);

  Future<void> _decryptSelected() => _runQuickCrypto(CryptoDirection.decrypt);

  Future<void> _runQuickCrypto(CryptoDirection direction) async {
    final files = selectedItems.where((e) {
      if (e.isDir) return false;
      final isEncrypted = isAppEncryptedFileName(e.name);
      return direction == CryptoDirection.encrypt ? !isEncrypted : isEncrypted;
    }).toList();
    exitSelectionMode();
    if (files.isEmpty) return;

    final isLocal = widget.container.isLocalStorage;

    final sources = files.map((e) {
      final relPath = _fullPathOf(e);
      if (isLocal) {
        final absPath = p.join(widget.container.uri, relPath);
        return CryptoSourceItem.external(
          displayName: e.name,
          externalUri: Uri.file(absPath).toString(),
        );
      } else {
        return CryptoSourceItem.vault(
          displayName: e.name,
          container: widget.container,
          relativePath: relPath,
        );
      }
    }).toList();

    final folderLabel = _currentDirPath.isEmpty
        ? widget.container.displayName
        : '${widget.container.displayName} / ${_currentDirPath.split('/').last}';

    final destination = isLocal
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
        builder: (_) => SingleFileCryptoSheet(
          initialSources: sources,
          initialDestination: destination,
          initialDirection: direction,
          allowEditingSelection: false,
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
    final pick = await ref.read(vaultFileIoApiProvider).pickFilesForImport(
          widget.container,
          _currentDirPath,
        );
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
      performImport: (opId) => ref.read(vaultFileIoApiProvider).importFiles(
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
  void _attachImportCompletionListener(FileOperation op, {required bool isFolder}) {
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running && op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        // See _opNeedsAttention's doc comment (applied the same way in
        // bindOpListener, above) -- a failed/diskFull/partially-failed
        // import stays in the service's list instead of being dismissed out
        // from under the transfer button/sheet the moment it finishes.
        final keepVisible = _opNeedsAttention(op);
        if (op.status == FileOperationStatus.completed && op.destDirPath == _currentDirPath) {
          _loadDirectoryContents(_currentDirPath).then((_) {
            _opSvc.dismiss(op.id);
          });
        } else if (!keepVisible) {
          _opSvc.dismiss(op.id);
        }
        if (op.status == FileOperationStatus.completed ||
            op.status == FileOperationStatus.completedWithErrors) {
          _maybeDeleteImportSources(op, isFolder: isFolder);
        }
      }
    }

    op.addListener(listener);
  }

  Future<void> _maybeDeleteImportSources(
    FileOperation op, {
    required bool isFolder,
  }) async {
    if (!mounted) return;
    final settings = await ref.read(appSettingsServiceProvider).loadSettings();
    if (mounted) {
      _appSettings = settings;
    }

    bool shouldDelete = false;

    switch (settings.deleteAfterImportMode) {
      case DeleteAfterImportMode.keep:
        return;
      case DeleteAfterImportMode.delete:
        shouldDelete = true;
        break;
      case DeleteAfterImportMode.ask:
        final choice = await DeleteOriginalsDialog.show(context, isFolder: isFolder);
        if (choice == null || !mounted) return;

        if (choice.dontAskAgain) {
          final newMode = choice.confirmed ? DeleteAfterImportMode.delete : DeleteAfterImportMode.keep;
          final updated = settings.copyWith(deleteAfterImportMode: newMode);
          await ref.read(appSettingsServiceProvider).saveSettings(updated);
          if (mounted) {
            _appSettings = updated;
          }
        }

        shouldDelete = choice.confirmed;
        break;
    }

    if (!shouldDelete || !mounted) return;
    final deleted = await ref.read(vaultFileIoApiProvider).deleteImportSources(op.id);
    if (!mounted) return;
    _setStatus(
      deleted > 0 ? context.l10n.deletedOriginalCount(deleted) : context.l10n.couldNotDeleteOriginals,
      error: deleted == 0,
      autoClear: const Duration(seconds: 3),
    );
  }

  Future<void> _importFolderFromDevice() async {
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    _signalActivity();
    final pick = await ref.read(vaultFileIoApiProvider).pickFolderForImport(
          widget.container,
          _currentDirPath,
        );
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
      performImport: (opId) => ref.read(vaultFileIoApiProvider).importFolder(
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

  bool _matchesFilter(String fileName) => matchesFilter(fileName, _currentFilter);

  Future<void> _extractArchive() async {
    if (_archiveContext == null) return;
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    final archivePath = _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
    final parentDir =
        archivePath.contains('/') ? archivePath.substring(0, archivePath.lastIndexOf('/')) : '';
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
    _navNotifier.setLoading(true);
    try {
      final count = await ArchiveService.extractAllToContainer(
        container: widget.container,
        archiveContext: _archiveContext!,
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
        final key = '${widget.container.uri}:$_currentDirPath';
        final updatedRatios = Map<String, String>.from(
          _toolbarConfig.folderGridAspectRatios,
        );
        updatedRatios[key] = ratio.toJson();
        setState(() {
          _toolbarConfig = _toolbarConfig.copyWith(
            gridAspectRatio: ratio,
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
      final effectiveToolbarUri =
          widget.container.isLocalStorage ? null : widget.container.uri;
      ref
          .read(fileManagerToolbarSettingsProvider(effectiveToolbarUri).notifier)
          .applyImportedConfig(_toolbarConfig);
    } catch (e) {
      if (mounted) {
        _setStatus(context.l10n.failedToSaveSettings, error: true);
      }
    }
  }

  Future<void> _onLayoutModeChanged(BrowserLayoutMode mode) async {
    _navNotifier.setLayoutMode(mode);
    try {
      // 1. Always update app-wide default layout mode so any folder without
      // an override opens in the user's preferred view
      final settings = await ref.read(appSettingsServiceProvider).loadSettings();
      final updatedSettings = settings.copyWith(defaultLayoutMode: mode);
      await ref.read(appSettingsServiceProvider).saveSettings(updatedSettings);
      _appSettings = updatedSettings;

      // 2. If per-folder memory is enabled, also record the choice for this path
      if (_toolbarConfig.rememberPerFolderLayout) {
        final key = '${widget.container.uri}:$_currentDirPath';
        final updatedFolderModes = Map<String, String>.from(
          _toolbarConfig.folderLayoutModes,
        );
        updatedFolderModes[key] = mode.toJson();
        _toolbarConfig = _toolbarConfig.copyWith(
          folderLayoutModes: updatedFolderModes,
        );
        await _toolbarSvc.save(_toolbarConfig);

        final effectiveToolbarUri =
            widget.container.isLocalStorage ? null : widget.container.uri;
        ref
            .read(fileManagerToolbarSettingsProvider(effectiveToolbarUri).notifier)
            .applyImportedConfig(_toolbarConfig);
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
      final settings = await ref.read(appSettingsServiceProvider).loadSettings();
      final updatedSettings = settings.copyWith(
        defaultFileSortBy: sortBy,
        defaultFileSortAscending: sortAscending,
      );
      await ref.read(appSettingsServiceProvider).saveSettings(updatedSettings);
    } catch (e) {
      if (mounted) {
        _setStatus(context.l10n.failedToSaveSettings, error: true);
      }
    }
  }

  Map<FileManagerAction, WidgetBuilder> _buildActionBuilders() {
    final hasLocalMedia =
        _currentItems.where((e) => !e.isDir).map((e) => e.name).any(_isSupportedMedia);
    final hasSubfolders = _currentItems.any((e) => e.isDir);
    final canPlayMedia = hasLocalMedia || hasSubfolders;
    return {
      FileManagerAction.search: (context) => IconButton(
        icon: Icon(
          _searchActive ? Icons.search_off_rounded : Icons.search_rounded,
        ),
        tooltip: _searchActive
            ? context.l10n.closeSearchTooltip
            : context.l10n.searchInThisFolderTooltip,
        onPressed: () => _searchNotifier.toggleActive(),
      ),
      FileManagerAction.add: (context) => AddItemMenuButton(
        isReadOnly: _isReadOnly,
        hasArchiveContext: _archiveContext != null,
        container: widget.container,
        currentDirPath: _currentDirPath,
        currentItems: _currentItems,
        onSetStatus: _setStatus,
        onExtractArchive: _extractArchive,
        onSignalActivity: _signalActivity,
        onLoadDirectoryContents: (path) => _loadDirectoryContents(path, refresh: true), 
        onCaptureFromCamera: _captureFromCamera,
        onImportFilesFromDevice: _importFilesFromDevice,
        onImportFolderFromDevice: _importFolderFromDevice,
        onAddVaultItem: _addVaultItem,
        hideVaultOnlyActions: widget.container.isLocalStorage,
      ),
      FileManagerAction.viewToggle: (context) => LayoutModeMenuButton(
        layoutMode: _layoutMode,
        onLayoutModeChanged: _onLayoutModeChanged,
        gridAspectRatio: _toolbarConfig.getGridAspectRatioForFolder(
          widget.container.uri,
          _currentDirPath,
        ),
        onGridAspectRatioChanged: _onGridAspectRatioChanged,
      ),
      FileManagerAction.sort: (context) => SortMenuButton(
        sortBy: sortBy,
        sortAscending: sortAscending,
        onSortChanged: _onSortChanged,
      ),
      FileManagerAction.filter: (context) => FilterMenuButton(
        currentFilter: _currentFilter,
        onFilterChanged: (value) => _navNotifier.setFilter(value),
        hideVaultOnlyActions: widget.container.isLocalStorage,
      ),
      FileManagerAction.playMedia: (context) => IconButton(
        icon: const Icon(Icons.play_circle_outline_rounded),
        tooltip: context.l10n.playMediaHereTooltip,
        onPressed: canPlayMedia ? _startMediaViewerFromCurrentLocation : null,
      ),
    };
  }

  List<RawEntry>? _cachedFilteredItems;
  int _cachedDirCount = 0;
  int _cachedFileCount = 0;

  List<RawEntry>? _memoCurrentItems;
  String? _memoDirPath;
  String? _memoQuery;
  bool? _memoSearchActive;
  bool? _memoIsDeepSearch;
  List<RawEntry>? _memoDeepSearchResults;
  String? _memoFilter;
  bool? _memoShowHidden;
  SortBy? _memoSortBy;
  bool? _memoSortAscending;
  int? _memoPlaceholdersLen;
  int? _memoPendingDeletedLen;
  int? _memoPinnedPathsLen;

  ({List<RawEntry> items, int dirCount, int fileCount}) _getFilteredAndSortedItems(
    String query,
    List<RawEntry> placeholders,
    Set<String> pendingDeletedNames,
  ) {
    final sortState = ref.read(fileBrowserSortProvider(widget.container.volId));
    final showHidden = _toolbarConfig.showHiddenFiles;
    final currentFilter = _currentFilter;
    final searchActive = _searchActive;
    final isDeep = _isDeepSearch;
    final deepResults = _deepSearchResults;
    final pinnedLen = _pinnedPaths.length;

    final isCacheValid = _cachedFilteredItems != null &&
        identical(_memoCurrentItems, _currentItems) &&
        _memoDirPath == _currentDirPath &&
        _memoQuery == query &&
        _memoSearchActive == searchActive &&
        _memoIsDeepSearch == isDeep &&
        identical(_memoDeepSearchResults, deepResults) &&
        _memoFilter == currentFilter &&
        _memoShowHidden == showHidden &&
        _memoSortBy == sortState.sortBy &&
        _memoSortAscending == sortState.sortAscending &&
        _memoPlaceholdersLen == placeholders.length &&
        _memoPendingDeletedLen == pendingDeletedNames.length &&
        _memoPinnedPathsLen == pinnedLen;

    if (isCacheValid) {
      return (
        items: _cachedFilteredItems!,
        dirCount: _cachedDirCount,
        fileCount: _cachedFileCount,
      );
    }

    final visibleCurrentItems = _currentItems.where(
      (e) => !pendingDeletedNames.contains(e.lowercaseName),
    );
    final existingNamesLower =
        visibleCurrentItems.map((e) => e.lowercaseName).toSet();
    final uniquePlaceholders = placeholders.where(
      (p) => !existingNamesLower.contains(p.lowercaseName),
    );
    final combinedItems = [
      ...visibleCurrentItems,
      ...uniquePlaceholders,
    ];
    final filteredItems = _searchAwareVisibleItems(combinedItems, query).toList()
      ..sort(_compareOverall);

    int dirCount = 0;
    for (final item in filteredItems) {
      if (item.isDir) dirCount++;
    }
    final fileCount = filteredItems.length - dirCount;

    _cachedFilteredItems = filteredItems;
    _cachedDirCount = dirCount;
    _cachedFileCount = fileCount;

    _memoCurrentItems = _currentItems;
    _memoDirPath = _currentDirPath;
    _memoQuery = query;
    _memoSearchActive = searchActive;
    _memoIsDeepSearch = isDeep;
    _memoDeepSearchResults = deepResults;
    _memoFilter = currentFilter;
    _memoShowHidden = showHidden;
    _memoSortBy = sortState.sortBy;
    _memoSortAscending = sortState.sortAscending;
    _memoPlaceholdersLen = placeholders.length;
    _memoPendingDeletedLen = pendingDeletedNames.length;
    _memoPinnedPathsLen = pinnedLen;

    return (
      items: filteredItems,
      dirCount: dirCount,
      fileCount: fileCount,
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
      final hasLocalMedia =
          _currentItems.where((e) => !e.isDir).map((e) => e.name).any(_isSupportedMedia);
      final hasSubfolders = _currentItems.any((e) => e.isDir);
      final canPlayMedia = hasLocalMedia || hasSubfolders;

      // When the Add FAB is visible, place More to its left (56dp FAB + 12dp spacing = 68dp).
      // If the Add FAB is hidden via config, More takes the primary bottom-right slot.
      final moreRight = showAddFab ? (baseRight + 68.0) : baseRight;

      widgets.add(
        Positioned(
          right: moreRight,
          bottom: bottomOffset + 4.0, // 4dp offset centers the 48dp button against the 56dp Add FAB
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
    ref.watch(fileBrowserSelectionProvider(widget.container.volId));
    ref.watch(fileBrowserSortProvider(widget.container.volId));
    ref.watch(fileBrowserNavigationProvider(widget.container.volId));
    ref.watch(vaultSyncedFolderPathsProvider(widget.container));

    final effectiveToolbarUri =
        widget.container.isLocalStorage ? null : widget.container.uri;
    ref.listen<FileManagerToolbarSettingsState>(
      fileManagerToolbarSettingsProvider(effectiveToolbarUri),
      (previous, next) {
        if (!next.loading && previous?.config != next.config) {
          setState(() {
            _toolbarConfig = next.config;
          });
        }
      },
    );
     ref.listen<SyncStatus>(
      syncStatusProvider,
      (previous, next) {
        if (previous?.running == true &&
            !next.running &&
            next.lastCompletedReport?.didWork == true) {
          _loadDirectoryContents(_currentDirPath, refresh: true);
        }
      },
    );
    if (widget.container.isExternalStorage) {
      ref.listen<List<ExternalStorageLocation>>(
        externalStorageLocationsProvider,
        (previous, next) {
          if (previous != null &&
              !next.any((loc) => loc.volId == widget.container.volId)) {
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          }
        },
      );
    }
   if (_isContainerLocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
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
    final itemResult =
        _getFilteredAndSortedItems(query, placeholders, pendingDeletedNames);
    final filteredItems = itemResult.items;
    final dirCount = itemResult.dirCount;
    final fileCount = itemResult.fileCount;

    final previewDirPath = _backGesturePreviewDirPath ?? _currentDirPath;
    final previewArchiveRootPath = _archiveRootPathForSearch;
    final previewInsideArchive = previewArchiveRootPath != null &&
        (previewDirPath == previewArchiveRootPath ||
            previewDirPath.startsWith('$previewArchiveRootPath/'));
    final previewArchiveContext = previewInsideArchive ? _archiveContext : null;
    final sortedPreviewItems = (_backGestureProgress != null && _backGesturePreviewItems != null)
        ? (List<RawEntry>.of(
            _backGesturePreviewItems!.where((item) {
              if (!_toolbarConfig.showHiddenFiles && isHiddenEntryName(item.name)) {
                return false;
              }
              return true;
            }),
          )..sort((ea, eb) {
            final aPinned = isPinned(ea, previewDirPath, _pinnedPaths);
            final bPinned = isPinned(eb, previewDirPath, _pinnedPaths);
            if (aPinned != bPinned) {
              return aPinned ? -1 : 1;
            }
            if (ea.isDir != eb.isDir) {
              return ea.isDir ? -1 : 1;
            }
            return compareItems(ea, eb);
          }))
        : null;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final useFab = _toolbarConfig.useFabForToolbar;
    final showActionBar = !_searchActive && !useFab;
    final actionBuilders = _buildActionBuilders();
    final isFiltered = query.isNotEmpty || _currentFilter != null;
    final showBookmarkBar = _toolbarConfig.showBookmarkBar && _bookmarkPaths.isNotEmpty;

    final hasBottomNavBar = !isLandscape && (showActionBar || showBookmarkBar);
    final bottomSystemInset = hasBottomNavBar ? 0.0 : MediaQuery.paddingOf(context).bottom;
    final baseBottomOffset = 16.0 + (!isLandscape && showBookmarkBar ? 0.0 : bottomSystemInset);

    final bool hasClipboardFab = !isSelectionMode &&
        !_searchActive &&
        ref.watch(crossContainerClipboardProvider).hasItems;
    final bool hasFabToolbar = useFab && !_searchActive;

    double fabClearance = 0.0;
    if (hasClipboardFab && hasFabToolbar) {
      fabClearance = 132.0; // Two stacked FABs (56 + 12 + 56 = 124) + 8dp clearance
    } else if (hasClipboardFab || hasFabToolbar) {
      fabClearance = 64.0; // Single FAB (56) + 8dp clearance
    }

    final double bannerBottomOffset = _searchActive
        ? 0.0
        : (baseBottomOffset +
            ((isSelectionMode && _toolbarConfig.bottomSelectionBar) ? kToolbarHeight : 0.0) +
            fabClearance);

    PreferredSizeWidget buildAppBar({required bool selectionMode}) {
      return buildBrowserAppBar(
        context,
        ref: ref,
        container: widget.container,
        pathStack: _pathStack,
        onJumpTo: _jumpTo,
        filteredItems: filteredItems,
        dirCount: dirCount,
        fileCount: fileCount,
        isSelectionMode: selectionMode,
        selectedItems: selectionMode ? selectedItems : const {},
        isReadOnly: _isReadOnly,
        searchActive: _searchActive,
        currentDirPath: _currentDirPath,
        currentFilter: _currentFilter,
        freeSpace: _freeSpace,
        selectedTotalBytes: selectionMode ? selectedTotalBytes : 0,
        hasPendingFolderSizes: selectionMode ? hasPendingFolderSizes : false,
        toolbarConfig: useFab
            ? _toolbarConfig.copyWith(hidden: FileManagerAction.values.toSet())
            : _toolbarConfig,
        actionBuilders: actionBuilders,
        isFolderMounted: _isFolderMounted,
        isPinned: _isPinned,
        isBookmark: _isBookmark,
        isInsideArchive: _archiveContext != null,
        onExitSelectionMode: exitSelectionMode,
        onSelectAll: () => setSelectedItems({...selectedItems, ...filteredItems}),
        onCopy: () => _initClipboard(cut: false),
        onCut: () => _initClipboard(cut: true),
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
        onSetStatus: (msg, {required bool error}) => _setStatus(msg, error: error),
        onShowOpenWithDialog: _showOpenWithDialog,
        onShowFolderDocumentProviderSheet: _showFolderDocumentProviderSheet,
        onToggleFolderDocumentProvider: _toggleFolderDocumentProvider,
        onSyncSettings: _showSyncSettings,
        onSyncRoot: _showRootSyncSettings,
        onEditImage: _editImage,
        onSettingsClosed: _loadToolbarConfig,
        isFiltered: isFiltered,
        onPaste: _isReadOnly ? null : _paste,
        onNavigateUp: _atRoot ? null : _navigateUp,
        showBackButton: widget.showBackButton,
        wrapTitle: widget.wrapAppBarTitle,
        onOpenStorageSwitcher: widget.onOpenStorageSwitcher,
      );
    }

    final bool canPop =
        _atRoot && !isSelectionMode && !_searchActive;

    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: PopScope(
        canPop: canPop,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) return;
          if (isSelectionMode) {
            exitSelectionMode();
          } else if (_searchActive) {
            setState(() => _clearSearch());
          } else if (!_atRoot) {
            _navigateUp();
          }
        },
        child: Scaffold(
          key: _scaffoldKey,
          resizeToAvoidBottomInset: false,
          drawerEnableOpenDragGesture: false,
          drawer: widget.drawer,
          bottomNavigationBar: (!isLandscape && (showActionBar || showBookmarkBar))
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showBookmarkBar)
                    BookmarkBar(
                      bookmarkPaths: _bookmarkPaths,
                      axis: Axis.horizontal,
                      onTapItem: (path) {
                        final isDir = !path.split('/').last.contains('.') || path.endsWith('/');
                        _navigateToPath(path, isDir: isDir);
                      },
                      onRemoveBookmark: (path) => _pinsBookmarksNotifier.removeBookmark(widget.container, path),
                    ),
                  if (!isLandscape && showActionBar)
                    FileManagerActionBar(
                      axis: Axis.horizontal,
                      actions: _toolbarConfig.visible,
                      builders: actionBuilders,
                    ),
                ],
              )
            : null,
         body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  dragStartBehavior: DragStartBehavior.start,
                  onHorizontalDragStart: widget.drawer == null
                      ? null
                      : (details) {
                          final edgeInset = math.max(
                            72.0,
                            MediaQuery.systemGestureInsetsOf(context).left,
                          );
                          if (_isMultiTouch ||
                              _isTouchFromEdge ||
                              details.globalPosition.dx <= edgeInset ||
                              _backGestureProgress != null) {
                            _isTouchFromEdge = true;
                            _drawerDragDistance = 0.0;
                            return;
                          }
                          _drawerDragDistance = 0.0;
                        },
                  onHorizontalDragUpdate: widget.drawer == null
                      ? null
                      : (details) {
                          if (_isMultiTouch ||
                              _isTouchFromEdge ||
                              _backGestureProgress != null ||
                              widget.drawer == null) {
                            _drawerDragDistance = 0.0;
                            return;
                          }
                          _drawerDragDistance += details.primaryDelta ?? 0.0;
                          if (_drawerDragDistance > 60.0) {
                            _scaffoldKey.currentState?.openDrawer();
                            _drawerDragDistance = 0.0;
                            _isTouchFromEdge = true;
                          }
                        },
                  onHorizontalDragEnd: widget.drawer == null
                      ? null
                      : (_) {
                          _drawerDragDistance = 0.0;
                        },
                  onHorizontalDragCancel: widget.drawer == null
                      ? null
                      : () {
                          _drawerDragDistance = 0.0;
                        },
                  child: Stack(
                    children: [
                      Column(
                        children: [
                       ClipRect(
                          key: const Key('browser_app_bar_clip_rect'),
                          child: AnimatedBuilder(
                            animation: _appBarAnimController,
                            builder: (context, _) {
                              // Follow current status: if it was hidden, stay hidden
                              final factor = (!_toolbarConfig.autoHideAppBar || _searchActive)
                                  ? 1.0
                                  : _appBarAnimController.value;
                              if (factor == 0.0) {
                                return const SizedBox.shrink();
                              }
                              return Align(
                                key: const Key('browser_app_bar_align'),
                                alignment: Alignment.bottomCenter,
                                heightFactor: factor,
                                child: SizedBox(
                                  height: kToolbarHeight,
                                  child: MediaQuery.removePadding(
                                    context: context,
                                    removeTop: true,
                                    child: buildAppBar(selectionMode: false),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
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
                          final isDir = !path.split('/').last.contains('.') || path.endsWith('/');
                          _navigateToPath(path, isDir: isDir);
                        },
                        onRemoveBookmark: (path) => _pinsBookmarksNotifier.removeBookmark(widget.container, path),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                         if (_toolbarConfig.showBreadcrumbBar) ...[
                        BreadcrumbBar(
                          stack: _pathStack,
                          onTap: _jumpTo,
                          backgroundColor: isSelectionMode
                              ? Theme.of(context).colorScheme.surfaceContainer
                              : null,
                        ),
                      ],
                          if (!widget.container.isLocalStorage && _archiveContext == null)
                            const SyncStatusBanner(),
                          if (_archiveContext?.isSolid == true)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                              child: InlineBanner(
                                context.l10n.archiveSolidWarning,
                                tone: AppBannerTone.warning,
                              ),
                            ),
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
                                    onNavigateUp: _atRoot ? null : _navigateUp,
                                    searchQuery: _searchQuery,
                                    layoutMode: _layoutMode,
                                    container: widget.container,
                                    currentDirPath: _currentDirPath,
                                    thumbnailCacheMode: _resolvedThumbnailCacheMode,
                                    thumbnailQuality: _resolvedThumbnailQuality,
                                    toolbarConfig: _toolbarConfig,
                                    isSelectionMode: isSelectionMode,
                                    selectedItems: selectedItems,
                                    searchActive: _searchActive,
                                    mountedDocProviderFolders: _mountedDocProviderFolders,
                                    isFolderMounted: _isFolderMounted,
                                    isPinned: _isPinned,
                                    isBookmark: _isBookmark,
                                    isFolderSynced: _isFolderSynced,
                                    onDirTap: _handleDirTap,
                                    onFileTap: _handleFileTap,
                                    onItemLongPress: _handleItemLongPress,
                                    onIconTap: _handleIconTap,
                                    onItemMoreTap: _showItemActionsSheet,
                                    onSelectionChanged: setSelectedItems,
                                    onGridColumnCountChanged: (count) {
                                      _toolbarConfig = isLandscape
                                          ? _toolbarConfig.copyWith(gridColumnsLandscape: count)
                                          : _toolbarConfig.copyWith(gridColumnsPortrait: count);
                                      _toolbarSvc.save(_toolbarConfig);
                                      final effectiveToolbarUri =
                                          widget.container.isLocalStorage ? null : widget.container.uri;
                                      ref
                                          .read(fileManagerToolbarSettingsProvider(effectiveToolbarUri).notifier)
                                          .applyImportedConfig(_toolbarConfig);
                                    },
                                    onMasonryColumnCountChanged: (count) {
                                      _toolbarConfig = isLandscape
                                          ? _toolbarConfig.copyWith(masonryColumnsLandscape: count)
                                          : _toolbarConfig.copyWith(masonryColumnsPortrait: count);
                                      _toolbarSvc.save(_toolbarConfig);
                                      final effectiveToolbarUri =
                                          widget.container.isLocalStorage ? null : widget.container.uri;
                                      ref
                                          .read(fileManagerToolbarSettingsProvider(effectiveToolbarUri).notifier)
                                          .applyImportedConfig(_toolbarConfig);
                                    },
                                    onListZoomLevelChanged: (newZoom) {
                                      setState(() {
                                        _toolbarConfig = _toolbarConfig.copyWith(listZoomLevel: newZoom);
                                      });
                                      _toolbarSvc.save(_toolbarConfig);
                                      final effectiveToolbarUri =
                                          widget.container.isLocalStorage ? null : widget.container.uri;
                                      ref
                                          .read(fileManagerToolbarSettingsProvider(effectiveToolbarUri).notifier)
                                          .applyImportedConfig(_toolbarConfig);
                                    },
                                    onRefresh: () {
                                      FolderThumbnailPreview.clearSessionCache();
                                      return _loadDirectoryContents(_currentDirPath, refresh: true);
                                    },
                                    isListingTruncated: _isListingTruncated,
                                    scrollController: _browserScrollController,
                                    archiveContext: _archiveContext,
                                    archiveRootPath: _archiveRootPathForSearch,
                                    sortBy: sortBy,
                                  ),
                                ),
                                if (_backGestureProgress != null)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          if (_backGestureProgress! >= 0.18 &&
                                              sortedPreviewItems != null) ...[
                                            ColoredBox(
                                              color: Theme.of(context).scaffoldBackgroundColor,
                                            ),
                                            buildBrowserBody(
                                              context,
                                              sortedPreviewItems,
                                              isLoading: false,
                                              currentItems: sortedPreviewItems,
                                              atRoot: _backGesturePreviewAtRoot,
                                              onNavigateUp: null,
                                              searchQuery: '',
                                              layoutMode: _backGesturePreviewLayoutMode ?? _layoutMode,
                                              container: widget.container,
                                              currentDirPath: previewDirPath,
                                              thumbnailCacheMode: _resolvedThumbnailCacheMode,
                                              thumbnailQuality: _resolvedThumbnailQuality,
                                              toolbarConfig: _toolbarConfig,
                                              isSelectionMode: false,
                                              selectedItems: const {},
                                              searchActive: false,
                                              mountedDocProviderFolders: _mountedDocProviderFolders,
                                              isFolderMounted: (e) => isFolderMounted(
                                                e,
                                                previewDirPath,
                                                _mountedDocProviderFolders,
                                              ),
                                              isPinned: (e) => isPinned(
                                                e,
                                                previewDirPath,
                                                _pinnedPaths,
                                              ),
                                              isBookmark: (e) => isBookmark(
                                                e,
                                                previewDirPath,
                                                _bookmarkPaths,
                                              ),
                                              isFolderSynced: _isFolderSynced,
                                              onDirTap: (_) {},
                                              onFileTap: (_) {},
                                              onItemLongPress: (_) {},
                                              onIconTap: (_) {},
                                              onItemMoreTap: (_) {},
                                              onGridColumnCountChanged: (_) {},
                                              onMasonryColumnCountChanged: (_) {},
                                              onListZoomLevelChanged: (_) {},
                                              onRefresh: () async {},
                                              isListingTruncated: false,
                                              scrollController: _backGesturePreviewScrollController,
                                              archiveContext: previewArchiveContext,
                                              archiveRootPath: previewArchiveRootPath,
                                              sortBy: sortBy,
                                            ),
                                          ],
                                          Opacity(
                                            opacity: _fadeScrimOpacity(_backGestureProgress!),
                                            child: ColoredBox(
                                              color: Theme.of(context).scaffoldBackgroundColor,
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
                      constraints: const BoxConstraints(maxWidth: 600),
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
                                  tone: _statusIsError ? AppBannerTone.error : AppBannerTone.info,
                                  trailing: _mediaScanInProgress
                                      ? TextButton(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          onPressed: _cancelMediaScan,
                                          child: Text(context.l10n.cancel),
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
                              onDeepSearchToggle: _onDeepSearchToggled,
                              isSearchingSubfolders: _isSearchingSubfolders,
                              onClose: () => setState(() => _clearSearch()),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
      // ── FAB Toolbar: Add FAB + "More" cascade (search/sort/filter/view/play) ──
      if (hasFabToolbar)
        ..._buildFabToolbar(
          bottomOffset: baseBottomOffset +
              ((isSelectionMode && _toolbarConfig.bottomSelectionBar)
                  ? kToolbarHeight
                  : 0.0),
        ),
        

      // ── Clipboard Paste FAB ────────────────────────────────────────────────
      if (!isSelectionMode && !_searchActive)
        Positioned(
          right: 16.0 + MediaQuery.paddingOf(context).right,
          bottom: useFab
              ? (baseBottomOffset + 68.0)
              : baseBottomOffset,
          child: ClipboardFab(
            onPaste: _isReadOnly ? null : _paste,
            heroTag: 'browser_clipboard_fab_${widget.container.volId}',
          ),
        ),
    ],
    ),
    ),
    ),
    ),
      // ── Top Selection Bar Overlay (when bottomSelectionBar is DISABLED) ──
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: AnimatedSwitcher(
          duration: AppMotion.short2,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.topCenter,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          transitionBuilder: (child, animation) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, -1.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              )),
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          child: (isSelectionMode && !_toolbarConfig.bottomSelectionBar)
              ? Material(
                  key: const ValueKey('browser_selection_app_bar_overlay'),
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  elevation: 0.0,
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: kToolbarHeight,
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: buildAppBar(selectionMode: true),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no_selection_top_bar')),
        ),
      ),

      // ── Bottom Selection Bar Overlay (when bottomSelectionBar is ENABLED) ──
      // bottom is offset by the keyboard inset (same fix BottomSearchBar
      // already applies to itself) -- the Scaffold above uses
      // resizeToAvoidBottomInset: false, so nothing else shifts this bar
      // out from under the on-screen keyboard. Without it, entering
      // selection mode while the keyboard is up (e.g. selecting a result
      // while search is active) pins the bar to the physical bottom of the
      // screen, underneath the keyboard, where it's invisible and untappable.
      Positioned(
        key: const Key('browser_selection_bottom_bar_overlay_container'),
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 0,
        right: 0,
        child: AnimatedSwitcher(
          duration: AppMotion.short2,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.bottomCenter,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          transitionBuilder: (child, animation) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 1.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              )),
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          child: (isSelectionMode && _toolbarConfig.bottomSelectionBar)
              ? Material(
                  key: const ValueKey('browser_selection_bottom_bar_overlay'),
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  elevation: 4.0,
                  child: SafeArea(
                    top: false,
                    bottom: !(!isLandscape && (showActionBar || showBookmarkBar)),
                    child: SizedBox(
                      height: kToolbarHeight,
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        removeBottom: true,
                        child: buildAppBar(selectionMode: true),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no_selection_bottom_bar')),
        ),
      ),
    ],
  ),
),
),
);
  }
}