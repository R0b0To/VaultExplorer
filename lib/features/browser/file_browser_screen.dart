import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/browser/archive_file_viewer.dart';
import 'package:vaultexplorer/features/browser/browser_dialogs.dart';
import 'package:vaultexplorer/features/browser/viewer/html_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_screen.dart';
import 'package:vaultexplorer/features/browser/viewer/pdf_viewer_screen.dart';
import 'package:vaultexplorer/features/browser/mixins/selection_mixin.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/widgets/bookmark_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/bottom_search_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/conflict_resolution_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/file_manager_action_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/add_item_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/sort_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/layout_mode_menu_button.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_app_bar_builder.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_body_builder.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_document_provider_sheet.dart';
import 'package:vaultexplorer/features/browser/services/folder_document_provider_service.dart';
import 'package:vaultexplorer/features/camera/camera_capture_screen.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_detail_screen.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_edit_screen.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/features/browser/widgets/filter_menu_button.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/paste_conflict_detection.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/single_file_crypto_sheet.dart';
import '../../core/utils/file_type_utils.dart';
import '../../core/widgets/thumbnail/thumbnail_concurrency.dart';

class PathSegment {
  final String label;
  final String fatPath;
  final bool isArchiveRoot;

  /// Snapshot of the parent folder's contents/layout, captured only when
  /// this segment was reached by tapping into a folder (see
  /// [_FileBrowserScreenState._enterDirectory]). Lets a predictive-back
  /// swipe preview the parent instantly, with no re-read. Left null for
  /// segments reached via breadcrumb jump or a deep link - there's nothing
  /// to snapshot in those cases, so the swipe just falls back to a plain
  /// (non-previewed) navigate-up on release.
  List<RawEntry>? previewItems;
  BrowserLayoutMode? previewLayoutMode;

  PathSegment(this.label, this.fatPath, {this.isArchiveRoot = false});
}

/// Opacity of the black scrim used to dip-to-black between the current and
/// parent folder during a predictive-back swipe. Ramps 0->1 quickly as [progress]
/// goes 0->0.15 (fading out the current folder), then 1->0 as it goes 0.15->0.30
/// (fading in the parent preview early in the gesture), staying fully revealed
/// for the remainder of the swipe.
/// Opacity of the surface scrim used to dip through the background color
/// between the current and parent folder during a predictive-back swipe.
/// Ramps 0->1 quickly (fading to background), then 1->0 (fading up into
/// parent preview), avoiding ghosting artifacts while matching light/dark theme.
double _fadeScrimOpacity(double progress) {
  const start = 0.08;     // Deadzone: doesn't start fading until gesture is deliberate
  const midpoint = 0.18;  // Scrim reaches 100% background and content swaps
  const end = 0.30;       // Fade-in completes early in the gesture

  if (progress < start) {
    return 0.0;
  } else if (progress <= midpoint) {
    return ((progress - start) / (midpoint - start)).clamp(0.0, 1.0);
  } else if (progress < end) {
    return ((end - progress) / (end - midpoint)).clamp(0.0, 1.0);
  }
  return 0.0;
}

class FileBrowserScreen extends StatefulWidget {
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
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen>
    with
        SelectionMixin<FileBrowserScreen>,
        SortMixin<FileBrowserScreen>,
        WidgetsBindingObserver {
  late final List<PathSegment> _pathStack;
  bool _pathStackInitialized = false;
  List<RawEntry> _currentItems = [];
 

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pathStackInitialized) {
      _pathStack = [PathSegment(context.l10n.rootFolderLabel, '')];
      _pathStackInitialized = true;
    }
  }

  final ScrollController _browserScrollController = ScrollController();
  // Separate controller for the (non-interactive) back-gesture preview, so
  // it never fights with the real list's scroll position/listeners.
  final ScrollController _backGesturePreviewScrollController =
      ScrollController();
  bool _isLoading = false;
  int? _freeSpace;
  bool _isListingTruncated = false;
  String? _statusMessage;
  bool _statusIsError = false;
  CrossContainerClipboard get _clip => CrossContainerClipboard.instance;
  FileOperationService get _opSvc => FileOperationService.instance;
  static const _docProviderService = FolderDocumentProviderService();
  bool _searchActive = false;
  String _searchQuery = '';
  AppSettings _appSettings = AppSettings();
  BrowserLayoutMode _layoutMode = BrowserLayoutMode.list;
  String? _currentFilter;
  bool _menuIsOpen = false;
  ArchiveContext? _archiveContext;
  ThumbnailCacheMode _resolvedThumbnailCacheMode = ThumbnailCacheMode.appCache;
  ThumbnailQuality _resolvedThumbnailQuality = ThumbnailQuality.defaultQuality;
  FileManagerToolbarConfig _toolbarConfig = FileManagerToolbarConfig.defaults();
  Set<String> _pinnedPaths = {};
  List<String> _bookmarkPaths = [];
  bool _isContainerLocked = false;
  bool _isDeepSearch = false;
  bool _isSearchingSubfolders = false;
  List<RawEntry> _deepSearchResults = [];
  int _searchGeneration = 0;
  Timer? _searchDebounceTimer;
  static const int _maxScanDepth = 20;

  bool get _atRoot => _pathStack.length == 1;
  String get _currentDirPath => _pathStack.last.fatPath;
  Set<String> _mountedDocProviderFolders = {};

  // Live predictive-back preview while browsing a subfolder (see the
  // WidgetsBindingObserver overrides near _navigateUp). All null/false
  // whenever no back gesture is in progress.
  double? _backGestureProgress;
  List<RawEntry>? _backGesturePreviewItems;
  BrowserLayoutMode? _backGesturePreviewLayoutMode;
  String? _backGesturePreviewDirPath;
  bool _backGesturePreviewAtRoot = false;

  void _clearBackGesturePreview() {
    _backGestureProgress = null;
    _backGesturePreviewItems = null;
    _backGesturePreviewLayoutMode = null;
    _backGesturePreviewDirPath = null;
    _backGesturePreviewAtRoot = false;
  }

  // Forwarding wrappers -- the actual logic lives in file_browser_predicates.dart
  // (pure functions, unit-tested there without needing widget-test infra).
  // Kept as same-named methods here so every existing call site below is
  // unchanged; only the implementations moved.
  String _fullPathOf(RawEntry entry) => fullPathOf(entry, _currentDirPath);
  String _joinPath(String name) => joinPath(name, _currentDirPath);
  bool _isFolderMounted(RawEntry entry) =>
      isFolderMounted(entry, _currentDirPath, _mountedDocProviderFolders);
  bool _isPinned(RawEntry entry) => isPinned(entry, _currentDirPath, _pinnedPaths);
  bool _isBookmark(RawEntry entry) => isBookmark(entry, _currentDirPath, _bookmarkPaths);

  void _onContainerLockedEvent(int volId) {
    if (volId == widget.container.volId && mounted) {
      setState(() => _isContainerLocked = true);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VaultExplorerApi.addContainerLockedListener(_onContainerLockedEvent);
    _freeSpace = widget.container.totalSpace > 0 && widget.container.freeSpace >= 0
        ? widget.container.freeSpace
        : null;
    _initSettingsAndContents();
    _loadToolbarConfig();
    _refreshMountedDocProviderFolders();
    VaultExplorerApi.addUsbContainerDetachedListener(_onContainerDetached);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
     _browserScrollController.dispose(); 
    _backGesturePreviewScrollController.dispose();
    VaultExplorerApi.removeContainerLockedListener(_onContainerLockedEvent);
    _closeArchive();
    VaultExplorerApi.removeUsbContainerDetachedListener(_onContainerDetached);
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
        // TODO: Handle this case.
        throw UnimplementedError();
    }

    final currentOffset = position.pixels;
    const topMargin = 12.0;
    const bottomMargin = 40.0;

    // If the item is already completely visible within the viewport, do nothing
    if (itemTop >= currentOffset + topMargin &&
        (itemTop + itemHeight) <= currentOffset + viewportHeight - bottomMargin) {
      return;
    }

    // Otherwise, scroll just enough to reveal it at the top or bottom edge
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

  Future<void> _refreshMountedDocProviderFolders() async {
    final folders = await _docProviderService.loadMountedFolders(
      widget.container,
    );
    if (!mounted) return;
    setState(() => _mountedDocProviderFolders = folders);
  }

  Future<void> _toggleFolderDocumentProvider(RawEntry entry) async {
    final path = _fullPathOf(entry);
    final ok = await _docProviderService.mountNative(
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
    setState(
      () => _mountedDocProviderFolders = {..._mountedDocProviderFolders, path},
    );
    await _docProviderService.persistExposed(
      widget.container,
      path,
      exposed: true,
    );
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: context.l10n.nowAvailableToOtherApps(entry.name),
    );
  }

  Future<void> _unmountFolderDocumentProvider(RawEntry entry) async {
    final path = _fullPathOf(entry);
    final ok = await _docProviderService.unmountNative(widget.container, path);
    if (!mounted) return;
    if (!ok) {
      showAppSnackBar(
        context,
        message: context.l10n.couldNotUnmount(entry.name),
      );
      return;
    }
    setState(() {
      _mountedDocProviderFolders = {..._mountedDocProviderFolders}
        ..remove(path);
    });
    await _docProviderService.persistExposed(
      widget.container,
      path,
      exposed: false,
    );
  }

  Future<void> _setFolderAutoMount(RawEntry entry, bool autoMount) async {
    final path = _fullPathOf(entry);
    await _docProviderService.setAutoMount(widget.container, path, autoMount);
  }

  Future<void> _showFolderDocumentProviderSheet(RawEntry entry) async {
    final path = _fullPathOf(entry);
    final records = await ContainerRepository.instance.loadAll();
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

  Future<void> _saveBookmarkPaths() async {
    final records = await ContainerRepository.instance.loadAll();
    var record = records[widget.container.uri];
    record ??= ContainerRecord(
      uri: widget.container.uri,
      label: widget.container.displayName,
      containerFormat: widget.container.containerFormat,
    );
    record = record.copyWith(bookmarkPaths: _bookmarkPaths);
    await ContainerRepository.instance.save(record);
  }

  Future<void> _toggleBookmarkSelected({required bool bookmark}) async {
    _signalActivity();
    final pathsToToggle = selectedItems.map((e) => _fullPathOf(e)).toList();
    setState(() {
      if (bookmark) {
        for (final p in pathsToToggle) {
          if (!_bookmarkPaths.contains(p)) {
            _bookmarkPaths.add(p);
          }
        }
      } else {
        _bookmarkPaths.removeWhere((p) => pathsToToggle.contains(p));
      }
    });
    await _saveBookmarkPaths();
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
    setState(() {
      if (pin) {
        _pinnedPaths.addAll(pathsToToggle);
      } else {
        _pinnedPaths.removeAll(pathsToToggle);
      }
    });
    final records = await ContainerRepository.instance.loadAll();
    var record = records[widget.container.uri];
    record ??= ContainerRecord(
      uri: widget.container.uri,
      label: widget.container.displayName,
      containerFormat: widget.container.containerFormat,
    );
    record = record.copyWith(pinnedPaths: _pinnedPaths.toList());
    await ContainerRepository.instance.save(record);
    final count = pathsToToggle.length;
    _setStatus(
      pin ? context.l10n.pinnedCount(count) : context.l10n.unpinnedCount(count),
    );
    exitSelectionMode();
  }

  bool get _isReadOnly => widget.container.readOnly;
  void _signalActivity() => widget.onUserActivity?.call();
  void _onContainerDetached(int volId) {
    if (!mounted || volId != widget.container.volId) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _initSettingsAndContents() async {
    setState(() => _isLoading = true);
    try {
      final appSettings = await AppSettingsService.loadSettings();
      final records = await ContainerRepository.instance.loadAll();
      final record = records[widget.container.uri];
      if (mounted) {
        setState(() {
          _appSettings = appSettings;
          if (record != null) {
            _pinnedPaths = Set<String>.from(record.pinnedPaths);
            _bookmarkPaths = List<String>.from(record.bookmarkPaths);
          }
          _resolvedThumbnailCacheMode =
              widget.thumbnailCacheMode ??
              record?.thumbnailCacheMode ??
              appSettings.defaultThumbnailCacheMode;
          _resolvedThumbnailQuality =
              widget.thumbnailQuality ??
              record?.thumbnailQuality ??
              appSettings.defaultThumbnailQuality;
          _layoutMode = _getLayoutModeForFolder(
            _currentDirPath,
            appSettings: appSettings,
          );
          sortBy = appSettings.defaultFileSortBy;
          sortAscending = appSettings.defaultFileSortAscending;
        });
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
    final config = await FileManagerToolbarService.instance.load();
    final records = await ContainerRepository.instance.loadAll();
    final record = records[widget.container.uri];
    if (!mounted) return;
    setState(() {
      _toolbarConfig = config;
      if (record != null) {
        _bookmarkPaths = List<String>.from(record.bookmarkPaths);
        _pinnedPaths = Set<String>.from(record.pinnedPaths);
      }
      _layoutMode = _getLayoutModeForFolder(_currentDirPath);
    });
  }

  void _setStatus(String msg, {bool error = false, Duration? autoClear}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = msg;
      _statusIsError = error;
    });
    final delay =
        autoClear ??
        (error ? const Duration(seconds: 5) : const Duration(seconds: 3));
    Future.delayed(delay, () {
      if (mounted && _statusMessage == msg) {
        setState(() => _statusMessage = null);
      }
    });
  }

  void _clearStatus() {
    if (mounted) setState(() => _statusMessage = null);
  }

int _loadGeneration = 0;
  Future<void> _loadDirectoryContents(String path, {bool refresh = false}) async {
    final generation = ++_loadGeneration;
    if (_currentItems.isEmpty) {
      setState(() => _isLoading = true);
    }
    _signalActivity();
    if (mounted) {
      setState(() {
        _layoutMode = _getLayoutModeForFolder(path);
      });
    }
    if (_archiveContext != null) {
      _loadArchiveContents(path);
      return;
    }
    try {
      final items = await vaultExplorerApi.listDirectory(
        widget.container,
        path,
        refresh: refresh,
      );
      if (mounted && generation == _loadGeneration && path == _currentDirPath) {
        final isTruncated = items?.any((f) => f == 'System:TRUNCATED') ?? false;
        setState(() {
          _currentItems =
              items
                  ?.where((f) => !f.startsWith('System:'))
                  .map(RawEntry.parse)
                  .toList() ??
              [];
          _isListingTruncated = isTruncated;
          _isLoading = false;
        });
      }
      vaultExplorerApi
          .getSpaceInfo(widget.container)
          .then((space) {
            if (mounted &&
                generation == _loadGeneration &&
                space != null &&
                space.length > 1 &&
                space[0] > 0 &&
                space[1] >= 0) {
              setState(() => _freeSpace = space[1]);
            }
          })
          .catchError((_) {});
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
        _setStatus(
          context.l10n.failedLoadingFolder('${e.runtimeType}'),
          error: true,
        );
      }
    }
  }

  void _loadArchiveContents(String path) {
    if (_archiveContext == null) return;
    final archiveRootPath =
        _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
    String subPath = '';
    if (path.length > archiveRootPath.length) {
      subPath = path.substring(archiveRootPath.length);
      if (subPath.startsWith('/')) subPath = subPath.substring(1);
    }
    final items = _archiveContext!.listDirectory(subPath);
    if (mounted) {
      setState(() {
        _currentItems = items.map(RawEntry.parse).toList();
        _isListingTruncated = false;
        _isLoading = false;
        _layoutMode = _getLayoutModeForFolder(path);
      });
    }
  }

  Future _openArchive(String fullPath, String archiveName) async {
    setState(() {
      _isLoading = true;
      _currentItems = [];
    });
    _signalActivity();
    try {
      final ctx = await ArchiveService.open(
        container: widget.container,
        archivePathInContainer: fullPath,
        pathStackEntryIndex: _pathStack.length,
      );
      setState(() {
        _archiveContext = ctx;
        _pathStack.add(PathSegment(archiveName, fullPath, isArchiveRoot: true));
        _clearSearch();
        _currentFilter = null;
        _layoutMode = _getLayoutModeForFolder(fullPath);
      });
      _loadArchiveContents(fullPath);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _setStatus(
          context.l10n.failedToReadArchive('${e.runtimeType}'),
          error: true,
        );
      }
    }
  }

  void _closeArchive() {
    _archiveContext?.dispose();
    _archiveContext = null;
  }

  void _clearSearch() {
    _searchActive = false;
    _searchQuery = '';
    _searchDebounceTimer?.cancel();
    _searchGeneration++;
    _isSearchingSubfolders = false;
    _deepSearchResults = [];
  }

  void _onSearchQueryChanged(String query) {
    setState(() => _searchQuery = query);
    _searchDebounceTimer?.cancel();
    if (!_isDeepSearch || query.trim().isEmpty) {
      setState(() {
        _isSearchingSubfolders = false;
        _deepSearchResults = [];
      });
      return;
    }
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _searchActive && _isDeepSearch) {
        _runDeepSearch(query);
      }
    });
  }

  void _onDeepSearchToggled(bool enabled) {
    setState(() => _isDeepSearch = enabled);
    _onSearchQueryChanged(_searchQuery);
  }

  Future<List<String>?> _listDirEntries(String path) async {
    if (_archiveContext != null) {
      final archiveRootPath =
          _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
      String subPath = '';
      if (path.length > archiveRootPath.length) {
        subPath = path.substring(archiveRootPath.length);
        if (subPath.startsWith('/')) subPath = subPath.substring(1);
      }
      return _archiveContext!.listDirectory(subPath);
    }
    return vaultExplorerApi.listDirectory(widget.container, path);
  }

  Future<void> _runDeepSearch(String query) async {
    final gen = ++_searchGeneration;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _deepSearchResults = [];
          _isSearchingSubfolders = false;
        });
      }
      return;
    }
    setState(() => _isSearchingSubfolders = true);
    final results = <RawEntry>[];
    await _scanDirectoryForQuery(
      _currentDirPath,
      q,
      gen,
      results,
      relativePrefix: '',
    );
    if (!mounted || gen != _searchGeneration) return;
    setState(() {
      _deepSearchResults = results;
      _isSearchingSubfolders = false;
    });
  }

  Future<void> _scanDirectoryForQuery(
    String dirPath,
    String query,
    int generation,
    List<RawEntry> results, {
    required String relativePrefix,
    int depth = 0,
  }) async {
    if (generation != _searchGeneration || depth > 15) return;
    try {
      final rawList = await _listDirEntries(dirPath);
      if (rawList == null || generation != _searchGeneration) return;
      final entries = RawEntry.parseAll(rawList);
      final subdirs = <RawEntry>[];
      for (final entry in entries) {
        if (generation != _searchGeneration) return;
        if (!_toolbarConfig.showHiddenFiles && isHiddenEntryName(entry.name)) {
          continue;
        }
        final relPath = relativePrefix.isEmpty
            ? entry.name
            : '$relativePrefix/${entry.name}';
        final nameMatches = entry.name.toLowerCase().contains(query);
        if (nameMatches) {
          results.add(
            RawEntry(
              name: relPath,
              isDir: entry.isDir,
              sizeBytes: entry.sizeBytes,
              modifiedSecs: entry.modifiedSecs,
            ),
          );
        }
        if (entry.isDir) {
          subdirs.add(entry);
        }
      }
      for (final sub in subdirs) {
        if (generation != _searchGeneration) return;
        final subRelPrefix = relativePrefix.isEmpty
            ? sub.name
            : '$relativePrefix/${sub.name}';
        final subFullPath = dirPath.isEmpty ? sub.name : '$dirPath/${sub.name}';
        await _scanDirectoryForQuery(
          subFullPath,
          query,
          generation,
          results,
          relativePrefix: subRelPrefix,
          depth: depth + 1,
        );
      }
    } catch (e) {
      VeLog.e('FileBrowserScreen', 'Deep search failed at ${VeLog.censorUri(dirPath)}', e);
    }
  }

  void _enterDirectory(RawEntry entry) {
    final newPath = _fullPathOf(entry);
    // Captured *before* _currentItems is cleared below, so a predictive-back
    // swipe out of the new folder can preview this folder instantly.
    final parentPreviewItems = List<RawEntry>.of(_currentItems);
    final parentPreviewLayoutMode = _layoutMode;
    setState(() {
      _pathStack.add(
        PathSegment(entry.name, newPath)
          ..previewItems = parentPreviewItems
          ..previewLayoutMode = parentPreviewLayoutMode,
      );
      _clearSearch();
      _currentFilter = null;
      _currentItems = [];
      _isLoading = true;
      _layoutMode = _getLayoutModeForFolder(newPath);
    });
    _loadDirectoryContents(newPath);
  }

  Future _navigateToPath(String fullPath, {required bool isDir}) async {
    _signalActivity();
    if (isSelectionMode) exitSelectionMode();
    final segments = fullPath.isEmpty ? [] : fullPath.split('/');
    if (segments.isEmpty) return;
    if (isDir) {
      final newStack = [PathSegment(context.l10n.rootFolderLabel, '')];
      String current = '';
      for (final seg in segments) {
        current = current.isEmpty ? seg : '$current/$seg';
        newStack.add(PathSegment(seg, current));
      }
      setState(() {
        _pathStack
          ..clear()
          ..addAll(newStack);
        _clearSearch();
        _currentFilter = null;
        _currentItems = [];
        _isLoading = true;
        _layoutMode = _getLayoutModeForFolder(current);
      });
      await _loadDirectoryContents(current);
    } else {
      final parentPath = segments.length > 1
          ? segments.sublist(0, segments.length - 1).join('/')
          : '';
      final fileName = segments.last;
      final newStack = [PathSegment(context.l10n.rootFolderLabel, '')];
      if (parentPath.isNotEmpty) {
        final parentSegments = parentPath.split('/');
        String current = '';
        for (final seg in parentSegments) {
          current = current.isEmpty ? seg : '$current/$seg';
          newStack.add(PathSegment(seg, current));
        }
      }
      setState(() {
        _pathStack
          ..clear()
          ..addAll(newStack);
        _clearSearch();
        _currentFilter = null;
        _currentItems = [];
        _isLoading = true;
        _layoutMode = _getLayoutModeForFolder(parentPath);
      });
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
    if (_archiveContext != null &&
        _pathStack.length - 1 <= _archiveContext!.pathStackEntryIndex) {
      _closeArchive();
    }
    final newPath = _pathStack[_pathStack.length - 2].fatPath;
    setState(() {
      _pathStack.removeLast();
      _clearSearch();
      _currentFilter = null;
      _currentItems = [];
      _isLoading = true;
      _layoutMode = _getLayoutModeForFolder(newPath);
    });
    _loadDirectoryContents(newPath);
  }

  // A predictive-back swipe actually results in _navigateUp() only when none
  // of PopScope's other cases (exit selection mode / close search) apply -
  // mirrors the `canPop` condition built in build() below.
  bool get _canPreviewFolderBackGesture =>
      !_atRoot && !isSelectionMode && !_searchActive;

  // These WidgetsBindingObserver back-gesture callbacks fire globally for as
  // long as this State is registered as an observer - which is this whole
  // screen's lifetime, including while a viewer (media/pdf/text/html/
  // archive) is pushed on top via Navigator.push. Without this check, a
  // back-swipe made while a viewer is open gets silently "claimed" here
  // (navigating the hidden browser up a folder) instead of reaching the
  // viewer route on top, so the viewer never closes until the browser has
  // been swiped all the way up to root and this stops intercepting.
  bool get _isOwnRouteCurrent => ModalRoute.of(context)?.isCurrent ?? false;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!_isOwnRouteCurrent) return false;
    if (backEvent.isButtonEvent || !_canPreviewFolderBackGesture) return false;
    final currentSegment = _pathStack.last;
    setState(() {
      _backGestureProgress = backEvent.progress;
      _backGesturePreviewItems = currentSegment.previewItems;
      _backGesturePreviewLayoutMode = currentSegment.previewLayoutMode;
      _backGesturePreviewDirPath = _pathStack[_pathStack.length - 2].fatPath;
      _backGesturePreviewAtRoot = _pathStack.length == 2;
    });
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_isOwnRouteCurrent) return;
    setState(() => _backGestureProgress = backEvent.progress);
  }

  @override
  void handleCancelBackGesture() {
    if (!_isOwnRouteCurrent) return;
    setState(_clearBackGesturePreview);
  }

  @override
  void handleCommitBackGesture() {
    if (!_isOwnRouteCurrent) return;
    final targetPath = _backGesturePreviewDirPath;
    // Snap straight to "fully revealed parent" regardless of the last
    // reported drag value, so there's never a partial-black artifact.
    setState(() => _backGestureProgress = 1.0);
    _navigateUp();
    if (targetPath != null) _hideBackGesturePreviewWhenReady(targetPath);
  }

  /// Keeps the (already fully-revealed) cached preview on screen until the
  /// real directory listing finishes loading, so removing it never flashes
  /// to a bare loading spinner.
  Future<void> _hideBackGesturePreviewWhenReady(String targetPath) async {
    while (mounted && _isLoading && _currentDirPath == targetPath) {
      await Future.delayed(const Duration(milliseconds: 30));
    }
    if (!mounted) return;
    setState(_clearBackGesturePreview);
  }

void _jumpTo(int index) {
    if (index == _pathStack.length - 1) return;
    if (_archiveContext != null &&
        index < _archiveContext!.pathStackEntryIndex) {
      _closeArchive();
    }
    final newPath = _pathStack[index].fatPath;
    setState(() {
      _pathStack.removeRange(index + 1, _pathStack.length);
      _clearSearch();
      _currentFilter = null;
      _currentItems = [];
      _isLoading = true;
      _layoutMode = _getLayoutModeForFolder(newPath);
    });
    _loadDirectoryContents(newPath);
  }

  @override
  void toggleSelectItem(RawEntry item) {
    super.toggleSelectItem(item);
    if (selectedFolderCount > 0) {
      fetchFolderSizes(widget.container, _currentDirPath);
    }
  }

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
      setState(() => _isLoading = true);
      try {
        final archiveRootPath =
            _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
        String subPath = '';
        if (fullPath.length > archiveRootPath.length) {
          subPath = fullPath.substring(archiveRootPath.length);
          if (subPath.startsWith('/')) subPath = subPath.substring(1);
        }
        final entryBytes = await _archiveContext!.extractEntry(subPath);
        if (mounted) {
          setState(() => _isLoading = false);
          if (entryBytes != null) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ArchiveFileViewer(bytes: entryBytes, fileName: entry.name),
              ),
            );
          } else {
            _setStatus(context.l10n.failedToReadFileFromArchive, error: true);
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          _setStatus(
            context.l10n.failedToExtractFile('${e.runtimeType}'),
            error: true,
          );
        }
      }
      return;
    }
    if (VaultItemType.values.any((t) => t.name.toLowerCase() == ext)) {
      final item = await VaultItemsService.instance.loadItem(
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
    final settings = await AppSettingsService.loadSettings();
    final pref = settings.extensionPreferences[ext];
    if (pref == 'editor') {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TextEditorScreen(container: widget.container, filePath: fullPath),
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

  // Awaits the push and reloads on return -- mirrors _openPdfViewer /
  // the TextEditorScreen / VaultItemDetailScreen call sites above, which
  // all refresh browser state after a pushed viewer pops. The media
  // viewer needs this too: it's the one viewer that can rename, delete,
  // *and* toggle bookmarks, none of which this screen picks up on its
  // own since it stays mounted underneath (no rebuild/initState) while
  // the media viewer is on top.
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
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () =>
                        Navigator.of(context).pop(isMedia ? 'media' : 'editor'),
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
                            isMedia
                                ? Icons.play_circle_outline_rounded
                                : Icons.edit_note_rounded,
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
                                  style: textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  isMedia
                                      ? context
                                            .l10n
                                            .playVideoAudioViewImageInApp
                                      : context.l10n.viewEditTextMarkdownCode,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant,
                          ),
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
                          Icon(
                            Icons.open_in_new_rounded,
                            color: cs.secondary,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.fileAssocExternalApp,
                                  style: textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  context.l10n.sendFileToThirdPartyApp,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant,
                          ),
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
                          Icon(
                            Icons.app_registration_rounded,
                            color: cs.secondary,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.openAsEllipsis,
                                  style: textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  context.l10n.chooseFileTypeToOpenAs,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant,
                          ),
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
        await AppSettingsService.saveSettings(settings);
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
    } else if (result == 'media') {
      if (remember) {
        settings.extensionPreferences[ext] = 'media';
        await AppSettingsService.saveSettings(settings);
      }
      if (!mounted) return;
      await _openMediaViewer(fileName, fullPath);
    } else if (result == 'external') {
      if (remember) {
        VaultExplorerApi.onAppSelectedCallback = (selectedExt, pkg) {
          if (selectedExt.toLowerCase() == ext.toLowerCase()) {
            settings.extensionPreferences[ext] = 'package:$pkg';
            AppSettingsService.saveSettings(settings);
            VaultExplorerApi.onAppSelectedCallback = null;
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

    final sortedItems =
        _currentItems.where((e) {
          if (!_toolbarConfig.showHiddenFiles && isHiddenEntryName(e.name)) {
            return false;
          }
          return !e.isDir && _matchesFilter(e.name);
        }).toList()
          ..sort(compareOverall);
    final localMedia = sortedItems
        .map((e) => e.name)
        .where(_isSupportedMedia)
        .toList();
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
    setState(() => _isLoading = true);
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleItemLongPress(RawEntry entry) {
    HapticFeedback.selectionClick();
    _signalActivity();
    if (!isSelectionMode) {
      setState(() {
        isSelectionMode = true;
        selectedItems.add(entry);
      });
      if (selectedFolderCount > 0) {
        fetchFolderSizes(widget.container, _currentDirPath);
      }
    } else {
      toggleSelectItem(entry);
    }
  }

  bool _isSupportedMedia(String fileName) =>
      MediaViewerConstants.isSupported(fileName);

  Future<List<String>> _scanMediaRecursively(
    String dirPath, {
    int depth = 0,
  }) async {
    if (depth > _maxScanDepth) return [];
    final foundFiles = <String>[];
    final matchedEntries = <RawEntry>[];
    final subdirNames = <String>[];
    try {
      final items = await vaultExplorerApi.listDirectory(
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
          matchedEntries.map(
            (e) => dirPath.isEmpty ? e.name : '$dirPath/${e.name}',
          ),
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
      final ok = await vaultExplorerApi.openWithApp(
        widget.container,
        fullPath,
        packageName: packageName,
        mimeType: mimeType,
      );
      if (!ok && mounted) {
        _setStatus(context.l10n.noAppFoundForFileType, error: true);
      }
    } catch (_) {
      if (mounted)
        _setStatus(context.l10n.couldNotOpenFile(cleanName), error: true);
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
        await vaultExplorerApi.listDirectory(
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
      final done =
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        if (op.destDirPath == _currentDirPath) {
          _loadDirectoryContents(_currentDirPath);
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
              op.status != FileOperationStatus.running &&
              op.status != FileOperationStatus.pending;
          if (!done) return;
          op.removeListener(listener);
          _finishBatchDelete(op);
        }

        op.addListener(listener);
      },
    );
  }

  Future<void> _finishBatchDelete(FileOperation op) async {
    final deleted = op.doneCount;
    final failCount = op.failCount;
    final deletedPaths = op.itemStatuses
        .where((s) => s.result == FileItemResult.success)
        .map((s) => s.item.path)
        .toSet();
    bool changed = false;
    if (_pinnedPaths.any((p) => deletedPaths.contains(p))) {
      _pinnedPaths.removeWhere((p) => deletedPaths.contains(p));
      changed = true;
    }
    if (_bookmarkPaths.any((p) => deletedPaths.contains(p))) {
      _bookmarkPaths.removeWhere((p) => deletedPaths.contains(p));
      changed = true;
    }
    if (changed) {
      final records = await ContainerRepository.instance.loadAll();
      var record = records[widget.container.uri];
      if (record != null) {
        await ContainerRepository.instance.save(
          record.copyWith(
            pinnedPaths: _pinnedPaths.toList(),
            bookmarkPaths: _bookmarkPaths,
          ),
        );
      }
    }
    if (!mounted) return;
    await _loadDirectoryContents(_currentDirPath);
    if (!mounted) return;
    if (op.status == FileOperationStatus.cancelled) return;
  }

  Future<void> _exportSelectedToStorage() async {
    _signalActivity();
    final items = selectedItems.map((e) {
      final path = _fullPathOf(e);
      return <String, dynamic>{'path': path, 'isDir': e.isDir};
    }).toList();
    if (items.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final count = await vaultExplorerApi.exportSelectedToFolder(
        widget.container,
        items,
      );
      _setStatus(
        count > 0
            ? context.l10n.exportedCount(count)
            : context.l10n.exportCancelledOrFailed,
        error: count == 0,
      );
    } catch (e) {
      _setStatus(context.l10n.exportError('${e.runtimeType}'), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    exitSelectionMode();
  }

  Future<void> _encryptSelected() => _runQuickCrypto(CryptoDirection.encrypt);

  Future<void> _decryptSelected() => _runQuickCrypto(CryptoDirection.decrypt);

  /// Opens [SingleFileCryptoSheet] pre-populated with the selected files
  /// (filtered to the ones [direction] actually applies to -- see
  /// [isAppEncryptedFileName]) and the current folder as destination, so
  /// encrypting/decrypting a file already open in the file manager needs
  /// no re-picking through the Tools tab. Output lands alongside the
  /// source in the same folder, named by the same `.vxenc`/strip-extension
  /// convention the native engine already applies for any vault
  /// destination (see SingleFileCryptoHandlers.kt).
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

  /// Shows the paste-style conflict-resolution sheet for any names an
  /// import's [pick] collided with in the destination directory, and
  /// returns the resulting [ConflictPlan] to hand to
  /// [VaultExplorerApi.importFiles]/[importFolder]. [candidateIsDir] is
  /// whether the picked item(s) themselves are folders (always `true` from
  /// [_importFolderFromDevice], always `false` from [_importFilesFromDevice]
  /// since the system file picker can't pick a folder) -- it only decides
  /// which icon the sheet shows next to each name.
  ///
  /// Returns an empty plan straight away when [pick] had no conflicts.
  /// Returns `null` if the person cancelled the sheet instead of
  /// resolving it, in which case the caller must abort the whole import
  /// rather than proceed with an empty plan -- this also releases the
  /// picked documents via [VaultExplorerApi.cancelPickedImport] so native
  /// doesn't hold onto them for a pick that's going nowhere.
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
      await vaultExplorerApi.cancelPickedImport(pick.pickToken);
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
    final pick = await vaultExplorerApi.pickFilesForImport(
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
      isFolder: false,
      performImport: (opId) => vaultExplorerApi.importFiles(
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
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        if (op.status == FileOperationStatus.completed &&
            op.destDirPath == _currentDirPath) {
          _loadDirectoryContents(_currentDirPath);
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.deleteOriginalTitle),
        content: Text(
          isFolder
              ? context.l10n.deleteOriginalFolderMessage
              : context.l10n.deleteOriginalFilesMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.keepOriginal),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.deleteOriginalButton),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final deleted = await vaultExplorerApi.deleteImportSources(op.id);
    if (!mounted) return;
    _setStatus(
      deleted > 0
          ? context.l10n.deletedOriginalCount(deleted)
          : context.l10n.couldNotDeleteOriginals,
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
    final pick = await vaultExplorerApi.pickFolderForImport(
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
      isFolder: true,
      performImport: (opId) => vaultExplorerApi.importFolder(
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
          op.status != FileOperationStatus.running &&
          op.status != FileOperationStatus.pending;
      if (done) {
        op.removeListener(listener);
        if (op.status == FileOperationStatus.completed &&
            op.destDirPath == _currentDirPath) {
          _loadDirectoryContents(_currentDirPath);
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
    setState(() => _isLoading = true);
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onLayoutModeChanged(BrowserLayoutMode mode) async {
    setState(() => _layoutMode = mode);
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
        await FileManagerToolbarService.instance.save(_toolbarConfig);
      } else {
        final settings = await AppSettingsService.loadSettings();
        final updatedSettings = settings.copyWith(defaultLayoutMode: mode);
        await AppSettingsService.saveSettings(updatedSettings);
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
      final settings = await AppSettingsService.loadSettings();
      final updatedSettings = settings.copyWith(
        defaultFileSortBy: sortBy,
        defaultFileSortAscending: sortAscending,
      );
      await AppSettingsService.saveSettings(updatedSettings);
    } catch (e) {
      if (mounted) {
        _setStatus(context.l10n.failedToSaveSettings, error: true);
      }
    }
  }

  Map<FileManagerAction, WidgetBuilder> _buildActionBuilders() {
    final hasLocalMedia = _currentItems
        .where((e) => !e.isDir)
        .map((e) => e.name)
        .any(_isSupportedMedia);
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
        onPressed: () => setState(() {
          _searchActive = !_searchActive;
          if (!_searchActive) _searchQuery = '';
        }),
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
        onFilterChanged: (value) => setState(() => _currentFilter = value),
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
    final baseItems = (_searchActive && _isDeepSearch && query.isNotEmpty)
        ? _deepSearchResults
        : _currentItems;
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
          )
          ..sort((ea, eb) {
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
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final showActionBar = !_searchActive;
    final actionBuilders = _buildActionBuilders();
      final isFiltered = query.isNotEmpty || _currentFilter != null;
    final showBookmarkBar =
        _toolbarConfig.showBookmarkBar && _bookmarkPaths.isNotEmpty;
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
          onSelectAll: () =>
              setState(() => selectedItems.addAll(filteredItems)),
          onCopy: () => _initClipboard(cut: false),
          onCut: () => _initClipboard(cut: true),
          onExport: _exportSelectedToStorage,
          onDelete: _batchDelete,
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
          onSettingsClosed: _loadToolbarConfig,
          isFiltered: isFiltered,
          onPaste: _isReadOnly ? null : _paste,
        ),
        bottomNavigationBar:
            (!isLandscape && (showActionBar || showBookmarkBar))
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showBookmarkBar)
                    BookmarkBar(
                      bookmarkPaths: _bookmarkPaths,
                      axis: Axis.horizontal,
                      onTapItem: (path) {
                        final isDir =
                            !path.split('/').last.contains('.') ||
                            path.endsWith('/');
                        _navigateToPath(path, isDir: isDir);
                      },
                      onRemoveBookmark: (path) {
                        setState(() => _bookmarkPaths.remove(path));
                        _saveBookmarkPaths();
                      },
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
                      final isDir =
                          !path.split('/').last.contains('.') ||
                          path.endsWith('/');
                      _navigateToPath(path, isDir: isDir);
                    },
                    onRemoveBookmark: (path) {
                      setState(() => _bookmarkPaths.remove(path));
                      _saveBookmarkPaths();
                    },
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
                            onGridColumnCountChanged: (count) {
                              _toolbarConfig = isLandscape
                                  ? _toolbarConfig.copyWith(
                                      gridColumnsLandscape: count,
                                    )
                                  : _toolbarConfig.copyWith(
                                      gridColumnsPortrait: count,
                                    );
                              FileManagerToolbarService.instance.save(
                                _toolbarConfig,
                              );
                            },
                            onMasonryColumnCountChanged: (count) {
                              _toolbarConfig = isLandscape
                                  ? _toolbarConfig.copyWith(
                                      masonryColumnsLandscape: count,
                                    )
                                  : _toolbarConfig.copyWith(
                                      masonryColumnsPortrait: count,
                                    );
                              FileManagerToolbarService.instance.save(
                                _toolbarConfig,
                              );
                            },
                            onListZoomLevelChanged: (newZoom) {
                              _toolbarConfig = _toolbarConfig.copyWith(
                                listZoomLevel: newZoom,
                              );
                              FileManagerToolbarService.instance.save(
                                _toolbarConfig,
                              );
                            },
                            onRefresh: () =>
                                _loadDirectoryContents(_currentDirPath, refresh: true),
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
                                      // Only mount the backdrop & parent preview once
                                      // the current folder has fully faded out into the background
                                      if (_backGestureProgress! >= 0.18 &&
                                          sortedPreviewItems != null) ...[
                                        ColoredBox(
                                          color: Theme.of(
                                            context,
                                          ).scaffoldBackgroundColor,
                                        ),
                                        buildBrowserBody(
                                          context,
                                          sortedPreviewItems,
                                          isLoading: false,
                                          currentItems: sortedPreviewItems,
                                          atRoot: _backGesturePreviewAtRoot,
                                          onNavigateUp: null,
                                          searchQuery: '',
                                          layoutMode:
                                              _backGesturePreviewLayoutMode ??
                                              _layoutMode,
                                          container: widget.container,
                                          currentDirPath: previewDirPath,
                                          thumbnailCacheMode:
                                              _resolvedThumbnailCacheMode,
                                          thumbnailQuality: _resolvedThumbnailQuality,
                                          toolbarConfig: _toolbarConfig,
                                          isSelectionMode: false,
                                          selectedItems: const {},
                                          searchActive: false,
                                          mountedDocProviderFolders:
                                              _mountedDocProviderFolders,
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
                                          scrollController:
                                              _backGesturePreviewScrollController,
                                        ),
                                      ],
                                      Opacity(
                                        opacity: _fadeScrimOpacity(
                                          _backGestureProgress!,
                                        ),
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
                          tone: _statusIsError
                              ? AppBannerTone.error
                              : AppBannerTone.info,
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