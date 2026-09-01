import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';
import 'package:vaultexplorer/features/browser/archive_file_viewer.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_pins_bookmarks_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_search_controller.dart';
import 'package:vaultexplorer/features/browser/widgets/file_browser_doc_provider_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_sort_controller.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/paste_conflict_detection.dart';
import 'package:vaultexplorer/features/browser/services/folder_document_provider_service.dart';
import 'package:vaultexplorer/features/browser/viewer/html_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/pdf_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_screen.dart';
import 'package:vaultexplorer/features/browser/widgets/add_item_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/bookmark_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/bottom_search_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_app_bar_builder.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_body_builder.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/file_manager_action_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/filter_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_document_provider_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/layout_mode_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/sort_menu_button.dart';
import 'package:vaultexplorer/features/camera/camera_capture_screen.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_screen.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/single_file_crypto_sheet.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_detail_screen.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_edit_screen.dart';

// PathSegment used to be declared in this file; it now lives in the
// navigation controller (see FileBrowserNavigation). Re-exported from here
// rather than updating every other file that imports PathSegment via this
// file (breadcrumb_bar.dart, browser_app_bar_builder.dart,
// vault_browser_sheet.dart, and the decoy/local file explorer's own
// screens/controllers, which reuse the same type) -- keeps this a pure
// relocation with zero blast radius on unrelated files.
export 'controllers/file_browser_navigation_controller.dart' show PathSegment;

/// Shared recursion-depth guard for this screen's directory-tree walks --
/// used by both [_FileBrowserScreenState._scanMediaRecursively] (media
/// discovery for playback) and FileBrowserSearch's own deep-search scan
/// (file_browser_search_controller.dart keeps its own copy since that
/// scan is now fully controller-owned; this one is only for the
/// media-scan use still living in this widget).
const _maxScanDepth = 20;

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

  const FileBrowserScreen({
    super.key,
    required this.container,
    this.thumbnailCacheMode,
    this.thumbnailQuality,
    this.onUserActivity,
    this.resolveContainer,
  });

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen>
    with WidgetsBindingObserver {
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

  bool _navRootInitialized = false;
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

  final ScrollController _browserScrollController = ScrollController();
  final ScrollController _backGesturePreviewScrollController = ScrollController();

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

  void _onContainerLockedEvent(int volId) {
    if (_disposed || volId != widget.container.volId || !mounted) return;
    _navNotifier.setContainerLocked(true);
  }

  DateTime? _lastOpReloadTime;
  Timer? _opReloadTimer;

  void _onOperationsChanged() {
    if (!mounted) return;
    setState(() {});

    final hasActiveTargetingCurrent = _opSvc.activeOperations.any(
      (op) =>
          !op.isDelete &&
          op.destVolId == widget.container.volId &&
          op.destDirPath == _currentDirPath,
    );
    if (!hasActiveTargetingCurrent) return;

    final now = DateTime.now();
    final last = _lastOpReloadTime;
    if (last == null || now.difference(last) > const Duration(milliseconds: 350)) {
      _lastOpReloadTime = now;
      _loadDirectoryContents(_currentDirPath, refresh: true);
    } else if (_opReloadTimer == null) {
      _opReloadTimer = Timer(const Duration(milliseconds: 350), () {
        _opReloadTimer = null;
        if (mounted) {
          _lastOpReloadTime = DateTime.now();
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
    WidgetsBinding.instance.removeObserver(this);
    _opReloadTimer?.cancel();
    _opSvc.removeListener(_onOperationsChanged);
    _browserScrollController.dispose();
    _backGesturePreviewScrollController.dispose();
    _vaultEvents.removeContainerLockedListener(_onContainerLockedEvent);
    _vaultEvents.removeUsbContainerDetachedListener(_onContainerDetached);
    super.dispose();
  }

  void _scrollToItem(String fullPath) {
    if (!_browserScrollController.hasClients) return;

    final query = _searchQuery.trim().toLowerCase();
    final baseItems = (_searchActive && _isDeepSearch && query.isNotEmpty)
        ? _deepSearchResults
        : _currentItems;

    int compareOverall(RawEntry ea, RawEntry eb) {
      final aPinned = _isPinned(ea);
      final bPinned = _isPinned(eb);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      if (ea.isDir != eb.isDir) {
        return ea.isDir ? -1 : 1;
      }
      return compareItems(ea, eb);
    }

    final sortedItems = baseItems.where((item) {
      if (!_toolbarConfig.showHiddenFiles && isHiddenEntryName(item.name)) {
        return false;
      }
      final name = item.name;
      if (query.isNotEmpty && !name.toLowerCase().contains(query)) return false;
      if (item.isDir) {
        if (query.isEmpty && _currentFilter != null) return false;
        return true;
      }
      return _matchesFilter(name);
    }).toList()..sort(compareOverall);

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
      case BrowserLayoutMode.grid:
        final columns = (isLandscape
                ? _toolbarConfig.gridColumnsLandscape
                : _toolbarConfig.gridColumnsPortrait)
            .clamp(1, 10);
        final row = targetIndex ~/ columns;
        final screenWidth = MediaQuery.of(context).size.width;
        final availableWidth = screenWidth - 20.0;
        final itemWidth = (availableWidth - (columns - 1) * 8.0) / columns;
        final double aspectRatio = !_toolbarConfig.showGridFileNames
            ? 1.0
            : (columns == 1
                ? 1.45
                : columns == 2
                    ? 0.95
                    : columns == 3
                        ? 0.8
                        : 0.74);
        itemHeight = itemWidth / aspectRatio;
        final rowHeight = itemHeight + 8.0;
        itemTop = 12.0 + (row * rowHeight);
        break;

      case BrowserLayoutMode.list:
      case BrowserLayoutMode.compact:
        final isCompact = _layoutMode == BrowserLayoutMode.compact;
        final zoom = _toolbarConfig.listZoomLevel;
        itemHeight = (isCompact ? 40.0 : 64.0) * zoom + 4.0;
        itemTop = 8.0 + (targetIndex * itemHeight);
        break;

      case BrowserLayoutMode.masonry:
        final columns = (isLandscape
                ? _toolbarConfig.masonryColumnsLandscape
                : _toolbarConfig.masonryColumnsPortrait)
            .clamp(1, 10);
        final screenWidth = MediaQuery.of(context).size.width;
        final availableWidth = screenWidth - 20.0;
        final itemWidth = (availableWidth - (columns - 1) * 8.0) / columns;
        final colHeights = List<double>.filled(columns, 12.0);

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

          final currentHeight = itemWidth / ratio;
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
      if (mounted) {
        setState(() {
          _appSettings = appSettings;
          _resolvedThumbnailCacheMode =
              widget.thumbnailCacheMode ??
              record?.thumbnailCacheMode ??
              appSettings.defaultThumbnailCacheMode;
          _resolvedThumbnailQuality =
              widget.thumbnailQuality ??
              record?.thumbnailQuality ??
              appSettings.defaultThumbnailQuality;
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
    if (!mounted) return;
    setState(() {
      _toolbarConfig = config;
    });
    _navNotifier.setLayoutMode(_getLayoutModeForFolder(_currentDirPath));
    _pinsBookmarksNotifier.load(widget.container);
  }

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
    try {
      await _navNotifier.openArchive(
        widget.container,
        fullPath,
        archiveName,
        layoutMode: _getLayoutModeForFolder(fullPath),
        onActivity: _signalActivity,
      );
      _clearSearch();
    } catch (e) {
      if (mounted) {
        _setStatus(
          context.l10n.failedToReadArchive('${e.runtimeType}'),
          error: true,
        );
      }
    }
  }

  void _closeArchive() => _navNotifier.closeArchive();

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
    final newPath = _fullPathOf(entry);
    _navNotifier.enterDirectory(
      entry,
      newPath: newPath,
      layoutMode: _getLayoutModeForFolder(newPath),
    );
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
    final newPath = _navNotifier.navigateUp();
    if (newPath == null) return;
    _navNotifier.setLayoutMode(_getLayoutModeForFolder(newPath));
    _clearSearch();
    _loadDirectoryContents(newPath);
  }

  bool get _canPreviewFolderBackGesture => !_atRoot && !isSelectionMode && !_searchActive;
  bool get _isOwnRouteCurrent => ModalRoute.of(context)?.isCurrent ?? false;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!_isOwnRouteCurrent) return false;
    if (backEvent.isButtonEvent || !_canPreviewFolderBackGesture) return false;
    return _navNotifier.startBackGesture(backEvent.progress);
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

  void setSelectedItems(Set<RawEntry> newSelection) =>
      ref.read(fileBrowserSelectionProvider(widget.container.volId).notifier).setSelectedItems(newSelection);

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
    final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
    if (ArchiveService.isArchive(ext)) {
      if (ArchiveService.isSupported(ext)) {
        await _openArchive(fullPath, entry.name);
      } else {
        _setStatus(context.l10n.archiveFormatNotSupported(ext), error: true);
      }
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
    if (pref == 'editor') {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TextEditorScreen(container: widget.container, filePath: fullPath),
        ),
      );
      _loadDirectoryContents(_currentDirPath);
    } else if (pref == 'media') {
      await _openMediaViewer(entry.name, fullPath);
    } else if (pref == 'pdf') {
      await _openPdfViewer(fullPath);
    } else if (pref == 'html') {
      _openHtmlViewer(fullPath);
    } else if (pref != null && pref.startsWith('package:')) {
      _openFileWithApp(entry.name, fullPath, packageName: pref.substring(8));
    } else if (pref == 'external') {
      _openFileWithApp(entry.name, fullPath);
    } else {
      if (_isSupportedMedia(entry.name)) {
        await _openMediaViewer(entry.name, fullPath);
      } else if (ext == 'pdf') {
        await _openPdfViewer(fullPath);
      } else if (ext == 'html' || ext == 'htm') {
        _openHtmlViewer(fullPath);
      } else {
        if (!mounted) return;
        await _showOpenWithDialog(entry.name, fullPath, ext, settings);
      }
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
      int compareOverall(RawEntry ea, RawEntry eb) {
        final aPinned = _isPinned(ea);
        final bPinned = _isPinned(eb);
        if (aPinned != bPinned) {
          return aPinned ? -1 : 1;
        }
        if (ea.isDir != eb.isDir) {
          return ea.isDir ? -1 : 1;
        }
        return compareItems(ea, eb);
      }

      final sortedItems = baseItems.where((item) {
        if (!_toolbarConfig.showHiddenFiles && isHiddenEntryName(item.name)) {
          return false;
        }
        final name = item.name;
        if (query.isNotEmpty && !name.toLowerCase().contains(query)) {
          return false;
        }
        if (item.isDir) return false;
        return _matchesFilter(name) && _isSupportedMedia(name);
      }).toList()..sort(compareOverall);

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

    await Navigator.push(
      context,
      _buildMediaViewerRoute(
        mediaFiles: mediaFiles,
        initialIndex: initialIndex,
      ),
    );
    if (!mounted) return;
    _loadDirectoryContents(_currentDirPath);
    _loadToolbarConfig();
  }

  Future<void> _showOpenWithDialog(
    String fileName,
    String fullPath,
    String ext,
    AppSettings settings,
  ) async {
    bool remember = false;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMedia = _isSupportedMedia(fileName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(context.l10n.openFileDialogTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.chooseHowToOpen(fileName),
                    style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(isMedia ? 'media' : 'editor'),
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isMedia ? Icons.play_circle_outline_rounded : Icons.edit_note_rounded,
                            color: cs.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isMedia
                                      ? context.l10n.fileAssocInAppMediaViewer
                                      : context.l10n.fileAssocInAppTextEditor,
                                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  isMedia
                                      ? context.l10n.playVideoAudioViewImageInApp
                                      : context.l10n.viewEditTextMarkdownCode,
                                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => Navigator.of(context).pop('external'),
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.open_in_new_rounded, color: cs.secondary, size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.fileAssocExternalApp,
                                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  context.l10n.sendFileToThirdPartyApp,
                                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => Navigator.of(context).pop('open_as'),
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.app_registration_rounded, color: cs.secondary, size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.openAsEllipsis,
                                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  context.l10n.chooseFileTypeToOpenAs,
                                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: remember,
                        onChanged: (val) {
                          setDialogState(() {
                            remember = val ?? false;
                          });
                        },
                      ),
                      Expanded(
                        child: Text(
                          ext.isNotEmpty
                              ? context.l10n.alwaysRememberChoiceExt(ext)
                              : context.l10n.alwaysRememberChoiceNoExt,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == 'editor') {
      if (remember) {
        settings.extensionPreferences[ext] = 'editor';
        await ref.read(appSettingsServiceProvider).saveSettings(settings);
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TextEditorScreen(container: widget.container, filePath: fullPath),
        ),
      );
      _loadDirectoryContents(_currentDirPath);
    } else if (result == 'media') {
      if (remember) {
        settings.extensionPreferences[ext] = 'media';
        await ref.read(appSettingsServiceProvider).saveSettings(settings);
      }
      if (!mounted) return;
      await _openMediaViewer(fileName, fullPath);
    } else if (result == 'external') {
      if (remember) {
        _vaultEvents.onAppSelectedCallback = (selectedExt, pkg) {
          if (selectedExt.toLowerCase() == ext.toLowerCase()) {
            settings.extensionPreferences[ext] = 'package:$pkg';
            ref.read(appSettingsServiceProvider).saveSettings(settings);
            _vaultEvents.onAppSelectedCallback = null;
          }
        };
      }
      _openFileWithApp(fileName, fullPath);
    } else if (result == 'open_as') {
      if (!mounted) return;
      final mimeType = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(context.l10n.openAsDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.text_fields_rounded),
                  title: Text(context.l10n.mimeTypeText),
                  onTap: () => Navigator.of(context).pop('text/plain'),
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: Text(context.l10n.mimeTypeImage),
                  onTap: () => Navigator.of(context).pop('image/*'),
                ),
                ListTile(
                  leading: const Icon(Icons.ondemand_video_outlined),
                  title: Text(context.l10n.mimeTypeVideo),
                  onTap: () => Navigator.of(context).pop('video/*'),
                ),
                ListTile(
                  leading: const Icon(Icons.audio_file_outlined),
                  title: Text(context.l10n.mimeTypeAudio),
                  onTap: () => Navigator.of(context).pop('audio/*'),
                ),
                ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(context.l10n.mimeTypeArchive),
                  onTap: () => Navigator.of(context).pop('application/zip'),
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(context.l10n.mimeTypeOther),
                  onTap: () => Navigator.of(context).pop('*/*'),
                ),
              ],
            ),
          );
        },
      );
      if (mimeType != null) {
        _openFileWithApp(fileName, fullPath, mimeType: mimeType);
      }
    }
  }

  Future<void> _startMediaViewerFromCurrentLocation() async {
    _signalActivity();
    int compareOverall(RawEntry ea, RawEntry eb) {
      final aPinned = _isPinned(ea);
      final bPinned = _isPinned(eb);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      if (ea.isDir != eb.isDir) {
        return ea.isDir ? -1 : 1;
      }
      return compareItems(ea, eb);
    }

    final sortedItems = _currentItems.where((e) {
      if (!_toolbarConfig.showHiddenFiles && isHiddenEntryName(e.name)) {
        return false;
      }
      return !e.isDir && _matchesFilter(e.name);
    }).toList()..sort(compareOverall);

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
    _navNotifier.setLoading(true);
    _setStatus(
      context.l10n.scanningSubfoldersForMedia,
      autoClear: const Duration(seconds: 15),
    );
    try {
      final recursiveMedia = await _scanMediaRecursively(_currentDirPath);
      if (!mounted) return;
      if (recursiveMedia.isNotEmpty) {
        _clearStatus();
        await Navigator.push(
          context,
          _buildMediaViewerRoute(
            mediaFiles: recursiveMedia,
            initialIndex: 0,
          ),
        );
        if (mounted) {
          _loadDirectoryContents(_currentDirPath);
          _loadToolbarConfig();
        }
      } else {
        _setStatus(context.l10n.noMediaFilesFoundRecursive, error: true);
      }
    } catch (e) {
      _setStatus(context.l10n.failedToScanSubfolders('$e'), error: true);
    } finally {
      if (mounted) _navNotifier.setLoading(false);
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

  Future<List<String>> _scanMediaRecursively(
    String dirPath, {
    int depth = 0,
  }) async {
    if (depth > _maxScanDepth) return [];
    final foundFiles = <String>[];
    final matchedEntries = <RawEntry>[];
    final subdirNames = <String>[];
    try {
      final items = await ref.read(vaultFileIoApiProvider).listDirectory(
            widget.container,
            dirPath,
          );
      if (items != null) {
        for (final item in items) {
          if (item.startsWith('System:')) continue;
          final e = RawEntry.parse(item);
          if (!_toolbarConfig.showHiddenFiles && isHiddenEntryName(e.name)) {
            continue;
          }
          if (e.isDir) {
            subdirNames.add(e.name);
          } else if (_isSupportedMedia(e.name)) {
            matchedEntries.add(e);
          }
        }
        matchedEntries.sort(
          (a, b) => compareEntriesWithPinned(
            a,
            b,
            sortBy: sortBy,
            sortAscending: sortAscending,
            pinnedPaths: _pinnedPaths,
            parentPath: dirPath,
          ),
        );
        foundFiles.addAll(
          matchedEntries.map((e) => dirPath.isEmpty ? e.name : '$dirPath/${e.name}'),
        );
        if (subdirNames.isNotEmpty) {
          final nested = await Future.wait(
            subdirNames.map((name) {
              final subPath = dirPath.isEmpty ? name : '$dirPath/$name';
              return _scanMediaRecursively(subPath, depth: depth + 1);
            }),
          );
          for (final list in nested) {
            foundFiles.addAll(list);
          }
        }
      }
    } catch (e) {
      VeLog.e('FileBrowserScreen', 'Media scan failed at ${VeLog.censorUri(dirPath)}', e);
    }
    return foundFiles;
  }

  Future<void> _openFileWithApp(
    String cleanName,
    String fullPath, {
    String? packageName,
    String? mimeType,
  }) async {
    _signalActivity();
    try {
      final ok = await ref.read(vaultFileIoApiProvider).openWithApp(
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
    if (!_clip.hasItems) return;
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyCantPaste, error: true);
      return;
    }
    _signalActivity();
    final srcVolId = _clip.sourceVolId;
    if (srcVolId == null) {
      _setStatus(context.l10n.clipboardSourceInvalid, error: true);
      _clip.clear();
      return;
    }
    final isCrossContainer = !_clip.isFromVolume(widget.container.volId);
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
    final items = List<ClipboardItem>.from(_clip.items);
    final isCut = _clip.isCutOperation;
    final existingRaw =
        await ref.read(vaultFileIoApiProvider).listDirectory(
              widget.container,
              _currentDirPath,
            ) ??
            [];
    if (!mounted) return;
    final existingNames = <String>{};
    final existingDirs = <String>{};
    for (final raw in existingRaw) {
      if (raw.startsWith('System:')) continue;
      final e = RawEntry.parse(raw);
      existingNames.add(e.name.toLowerCase());
      if (e.isDir) existingDirs.add(e.name.toLowerCase());
    }
    final conflicts = detectPasteConflicts(
      items: items,
      existingNamesLower: existingNames,
      existingDirsLower: existingDirs,
      isCrossContainer: isCrossContainer,
      currentDirPath: _currentDirPath,
    );
    ConflictPlan conflictPlan = const {};
    if (conflicts.isNotEmpty) {
      if (!mounted) return;
      final result = await ConflictResolutionSheet.show(
        context,
        conflicts: conflicts,
      );
      if (!mounted) return;
      if (result == null) return;
      conflictPlan = result;
    }
    final op = _opSvc.enqueue(
      isCut: isCut,
      source: srcContainer,
      dest: widget.container,
      destDirPath: _currentDirPath,
      items: items,
      conflictPlan: conflictPlan,
      l10n: context.l10n,
    );
    _clip.clear();
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done = op.status != FileOperationStatus.running && op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        if (op.destDirPath == _currentDirPath) {
          _loadDirectoryContents(_currentDirPath).then((_) {
            _opSvc.dismiss(op.id);
          });
        } else {
          _opSvc.dismiss(op.id);
        }
      }
    }

    op.addListener(listener);
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

    await _pinsBookmarksNotifier.removeDeletedPaths(widget.container, deletedPaths);
    if (!mounted) return;
    await _loadDirectoryContents(_currentDirPath);
    _opSvc.dismiss(op.id);
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
      _opSvc.dismiss(op.id);
      final count = op.doneCount;
      _setStatus(
        count > 0 ? context.l10n.exportedCount(count) : context.l10n.exportCancelledOrFailed,
        error: count == 0,
      );
    }

    op.addListener(listener);
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

    final sources = files
        .map((e) => CryptoSourceItem.vault(
              displayName: e.name,
              container: widget.container,
              relativePath: _fullPathOf(e),
            ))
        .toList();
    final folderLabel = _currentDirPath.isEmpty
        ? widget.container.displayName
        : '${widget.container.displayName} / ${_currentDirPath.split('/').last}';
    final destination = CryptoDestination.vault(
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
    await _loadDirectoryContents(_currentDirPath);
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
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running && op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        if (op.status == FileOperationStatus.completed && op.destDirPath == _currentDirPath) {
          _loadDirectoryContents(_currentDirPath).then((_) {
            _opSvc.dismiss(op.id);
          });
        } else {
          _opSvc.dismiss(op.id);
        }
        if (op.status == FileOperationStatus.completed ||
            op.status == FileOperationStatus.completedWithErrors) {
          _maybeDeleteImportSources(op, isFolder: false);
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
        bool dontAskAgain = false;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (dialogCtx, setDialogState) => AlertDialog(
              title: Text(context.l10n.deleteOriginalTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFolder
                        ? context.l10n.deleteOriginalFolderMessage
                        : context.l10n.deleteOriginalFilesMessage,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setDialogState(() {
                        dontAskAgain = !dontAskAgain;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: dontAskAgain,
                              onChanged: (val) {
                                setDialogState(() {
                                  dontAskAgain = val ?? false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.l10n.dontAskAgain,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: Text(context.l10n.keepOriginal),
                ),
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  child: Text(context.l10n.deleteOriginalButton),
                ),
              ],
            ),
          ),
        );

        if (confirm == null || !mounted) return;

        if (dontAskAgain) {
          final newMode = confirm ? DeleteAfterImportMode.delete : DeleteAfterImportMode.keep;
          final updated = settings.copyWith(deleteAfterImportMode: newMode);
          await ref.read(appSettingsServiceProvider).saveSettings(updated);
          if (mounted) {
            _appSettings = updated;
          }
        }

        shouldDelete = confirm;
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
    void listener() {
      if (!mounted) {
        op.removeListener(listener);
        return;
      }
      final done =
          op.status != FileOperationStatus.running && op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        if (op.status == FileOperationStatus.completed && op.destDirPath == _currentDirPath) {
          _loadDirectoryContents(_currentDirPath).then((_) {
            _opSvc.dismiss(op.id);
          });
        } else {
          _opSvc.dismiss(op.id);
        }
        if (op.status == FileOperationStatus.completed ||
            op.status == FileOperationStatus.completedWithErrors) {
          _maybeDeleteImportSources(op, isFolder: true);
        }
      }
    }

    op.addListener(listener);
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

  Future<void> _onLayoutModeChanged(BrowserLayoutMode mode) async {
    _navNotifier.setLayoutMode(mode);
    try {
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
      } else {
        final settings = await ref.read(appSettingsServiceProvider).loadSettings();
        final updatedSettings = settings.copyWith(defaultLayoutMode: mode);
        await ref.read(appSettingsServiceProvider).saveSettings(updatedSettings);
        _appSettings = updatedSettings;
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
        onLoadDirectoryContents: _loadDirectoryContents,
        onCaptureFromCamera: _captureFromCamera,
        onImportFilesFromDevice: _importFilesFromDevice,
        onImportFolderFromDevice: _importFolderFromDevice,
        onAddVaultItem: _addVaultItem,
      ),
      FileManagerAction.viewToggle: (context) => LayoutModeMenuButton(
        layoutMode: _layoutMode,
        onLayoutModeChanged: _onLayoutModeChanged,
      ),
      FileManagerAction.sort: (context) => SortMenuButton(
        sortBy: sortBy,
        sortAscending: sortAscending,
        onSortChanged: _onSortChanged,
      ),
      FileManagerAction.filter: (context) => FilterMenuButton(
        currentFilter: _currentFilter,
        onFilterChanged: (value) => _navNotifier.setFilter(value),
      ),
      FileManagerAction.playMedia: (context) => IconButton(
        icon: const Icon(Icons.play_circle_outline_rounded),
        tooltip: context.l10n.playMediaHereTooltip,
        onPressed: canPlayMedia ? _startMediaViewerFromCurrentLocation : null,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(fileBrowserSelectionProvider(widget.container.volId));
    ref.watch(fileBrowserSortProvider(widget.container.volId));
    ref.watch(fileBrowserNavigationProvider(widget.container.volId));
    if (_isContainerLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    int compareOverall(RawEntry ea, RawEntry eb) {
      final aPinned = _isPinned(ea);
      final bPinned = _isPinned(eb);
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      if (ea.isDir != eb.isDir) {
        return ea.isDir ? -1 : 1;
      }
      return compareItems(ea, eb);
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
    final visibleCurrentItems = _currentItems.where(
      (e) => !pendingDeletedNames.contains(e.name.toLowerCase()),
    );
    final existingNamesLower = visibleCurrentItems.map((e) => e.name.toLowerCase()).toSet();
    final uniquePlaceholders = placeholders.where(
      (p) => !existingNamesLower.contains(p.name.toLowerCase()),
    );
    final combinedItems = [
      ...visibleCurrentItems,
      ...uniquePlaceholders,
    ];
    final baseItems =
        (_searchActive && _isDeepSearch && query.isNotEmpty) ? _deepSearchResults : combinedItems;
    final filteredItems = baseItems.where((item) {
      if (!_toolbarConfig.showHiddenFiles && isHiddenEntryName(item.name)) {
        return false;
      }
      final name = item.name;
      if (query.isNotEmpty && !name.toLowerCase().contains(query)) return false;
      if (item.isDir) {
        if (query.isEmpty && _currentFilter != null) return false;
        return true;
      }
      return _matchesFilter(name);
    }).toList()..sort(compareOverall);

    final previewDirPath = _backGesturePreviewDirPath ?? _currentDirPath;
    final sortedPreviewItems = _backGesturePreviewItems == null
        ? null
        : (List<RawEntry>.of(
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
          }));

    final dirCount = filteredItems.where((e) => e.isDir).length;
    final fileCount = filteredItems.where((e) => !e.isDir).length;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final showActionBar = !_searchActive;
    final actionBuilders = _buildActionBuilders();
    final isFiltered = query.isNotEmpty || _currentFilter != null;
    final showBookmarkBar = _toolbarConfig.showBookmarkBar && _bookmarkPaths.isNotEmpty;
    final bool canPop = _atRoot && !isSelectionMode && !_searchActive;

    return PopScope(
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
        resizeToAvoidBottomInset: false,
        appBar: buildBrowserAppBar(
          context,
          ref: ref,
          container: widget.container,
          pathStack: _pathStack,
          onJumpTo: _jumpTo,
          filteredItems: filteredItems,
          dirCount: dirCount,
          fileCount: fileCount,
          isSelectionMode: isSelectionMode,
          selectedItems: selectedItems,
          isReadOnly: _isReadOnly,
          searchActive: _searchActive,
          currentDirPath: _currentDirPath,
          toolbarConfig: _toolbarConfig,
          currentFilter: _currentFilter,
          freeSpace: _freeSpace,
          selectedTotalBytes: selectedTotalBytes,
          hasPendingFolderSizes: hasPendingFolderSizes,
          actionBuilders: actionBuilders,
          isFolderMounted: _isFolderMounted,
          isPinned: _isPinned,
          isBookmark: _isBookmark,
          onExitSelectionMode: exitSelectionMode,
          onSelectAll: () => setSelectedItems({...selectedItems, ...filteredItems}),
          onCopy: () => _initClipboard(cut: false),
          onCut: () => _initClipboard(cut: true),
          onExport: _exportSelectedToStorage,
          onDelete: _batchDelete,
          onEncryptSelected: _encryptSelected,
          onDecryptSelected: _decryptSelected,
          onTogglePin: _togglePinSelected,
          onToggleBookmark: _toggleBookmarkSelected,
          onDirectoryReload: _loadDirectoryContents,
          onSetStatus: (msg, {required bool error}) => _setStatus(msg, error: error),
          onShowOpenWithDialog: _showOpenWithDialog,
          onShowFolderDocumentProviderSheet: _showFolderDocumentProviderSheet,
          onToggleFolderDocumentProvider: _toggleFolderDocumentProvider,
          onEditImage: _editImage,
          onSettingsClosed: _loadToolbarConfig,
          isFiltered: isFiltered,
          onPaste: _isReadOnly ? null : _paste,
        ),
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
                        BreadcrumbBar(stack: _pathStack, onTap: _jumpTo),
                        const Divider(),
                      ],
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
                                onDirTap: _handleDirTap,
                                onFileTap: _handleFileTap,
                                onItemLongPress: _handleItemLongPress,
                                onSelectionChanged: setSelectedItems,
                                onGridColumnCountChanged: (count) {
                                  _toolbarConfig = isLandscape
                                      ? _toolbarConfig.copyWith(gridColumnsLandscape: count)
                                      : _toolbarConfig.copyWith(gridColumnsPortrait: count);
                                  _toolbarSvc.save(_toolbarConfig);
                                },
                                onMasonryColumnCountChanged: (count) {
                                  _toolbarConfig = isLandscape
                                      ? _toolbarConfig.copyWith(masonryColumnsLandscape: count)
                                      : _toolbarConfig.copyWith(masonryColumnsPortrait: count);
                                  _toolbarSvc.save(_toolbarConfig);
                                },
                                onListZoomLevelChanged: (newZoom) {
                                  _toolbarConfig = _toolbarConfig.copyWith(listZoomLevel: newZoom);
                                  _toolbarSvc.save(_toolbarConfig);
                                },
                                onRefresh: () => _loadDirectoryContents(_currentDirPath, refresh: true),
                                isListingTruncated: _isListingTruncated,
                                scrollController: _browserScrollController,
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
                                          onDirTap: (_) {},
                                          onFileTap: (_) {},
                                          onItemLongPress: (_) {},
                                          onGridColumnCountChanged: (_) {},
                                          onMasonryColumnCountChanged: (_) {},
                                          onListZoomLevelChanged: (_) {},
                                          onRefresh: () async {},
                                          isListingTruncated: false,
                                          scrollController: _backGesturePreviewScrollController,
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
            Positioned(
              left: 0,
              right: 0,
              bottom: _searchActive ? 0 : 16,
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
                          key: ValueKey(_statusMessage),
                          tone: _statusIsError ? AppBannerTone.error : AppBannerTone.info,
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
          ],
        ),
      ),
    );
  }
}