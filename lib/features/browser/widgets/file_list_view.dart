import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/fast_scrollbar.dart';
import 'package:vaultexplorer/features/browser/widgets/file_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/hold_range_select_container.dart';

/// Rejects list scroll drag deltas while a 2-finger pinch gesture is active
/// without detaching the Scrollable's DragGestureRecognizer.
class _ZoomScrollPhysics extends AlwaysScrollableScrollPhysics {
  final ValueGetter<bool> isZooming;

  const _ZoomScrollPhysics({required this.isZooming, super.parent});

  @override
  _ZoomScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ZoomScrollPhysics(
      isZooming: isZooming,
      parent: buildParent(ancestor),
    );
  }

  // DO NOT override shouldAcceptUserOffset! Returning false causes
  // ScrollableState.setCanDrag(false), which deletes the DragGestureRecognizer
  // from the list and permanently breaks touch scrolling.
  // Instead, absorb user offset deltas directly while zooming:
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (isZooming()) return 0.0;
    return super.applyPhysicsToUserOffset(position, offset);
  }
}
class FileListView extends StatefulWidget {
  final List<RawEntry> items;
  final bool isSelectionMode;
  final bool isCompact;

  /// Two-row layout: filename on its own line, date and size stacked
  /// underneath on a second line instead of in aligned columns. Mutually
  /// exclusive with [isCompact] -- the caller picks at most one.
  final bool isDetailed;
  final Set<RawEntry> selectedItems;
  final List<FileDetailColumn> detailColumns;
  final LongFileNameDisplayMode longFileNameMode;
  final bool showItemActionsMenu;
  final ValueChanged<RawEntry> onDirTap;
  final ValueChanged<RawEntry> onFileTap;
  final ValueChanged<RawEntry> onItemLongPress;
  final ValueChanged<RawEntry>? onFileLongMenu;

  /// Called when the person taps directly on a row's leading icon/thumbnail
  /// rather than the row body -- toggles that item's selection instead of
  /// opening it. See `file_browser_screen.dart`'s `_handleIconTap`.
  final ValueChanged<RawEntry>? onIconTap;
  final ValueChanged<Set<RawEntry>>? onSelectionChanged;
  final String? searchQuery;
  final bool Function(RawEntry entry)? isFolderMounted;
  final bool Function(RawEntry entry)? isPinned;
  final bool Function(RawEntry entry)? isBookmark;
  final bool Function(RawEntry entry)? isFolderSynced;
  final MountedContainer? container;
  final String currentDirPath;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;
  final bool showThumbnails;
  final double initialZoomLevel;
  final ValueChanged<double>? onZoomLevelChanged;
  final ScrollController? scrollController;

  /// Set when [items] are being listed from inside an open archive rather
  /// than the real container filesystem -- see `file_tile.dart`'s
  /// `archiveContext` doc for what this changes about thumbnail fetching.
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;
  final SortBy? sortBy;

  const FileListView({
    super.key,
    required this.items,
    required this.isSelectionMode,
    this.isCompact = false,
    this.isDetailed = false,
    required this.selectedItems,
    this.detailColumns = const [FileDetailColumn.date, FileDetailColumn.size],
    this.longFileNameMode = LongFileNameDisplayMode.ellipsizeEnd,
    this.showItemActionsMenu = true,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    this.onFileLongMenu,
    this.onIconTap,
    this.onSelectionChanged,
    this.searchQuery,
    this.isFolderMounted,
    this.isPinned,
    this.isBookmark,
    this.isFolderSynced,
    this.container,
    this.currentDirPath = '',
    this.thumbnailCacheMode = ThumbnailCacheMode.appCache,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    this.showThumbnails = true,
    this.initialZoomLevel = 1.0,
    this.onZoomLevelChanged,
    this.scrollController,
    this.archiveContext,
    this.archiveRootPath,
    this.sortBy,
  });

  @override
  State<FileListView> createState() => _FileListViewState();
}

class _FileListViewState extends State<FileListView> {
  double _baselineScale = 1.0;
  late double _zoomLevel;
  final Map<Key, int> _keyIndexMap = {};
  int _lastPointerCount = 0;
  bool _isZooming = false;
  bool _isAtBottomAnchor = false;
  bool _isAtTopAnchor = false;
  double _anchorCenterItemIndex = 0.0;

  @override
  void initState() {
    super.initState();
    _zoomLevel = widget.initialZoomLevel;
    _updateKeyIndexMap();
  }

  void _updateKeyIndexMap() {
    _keyIndexMap.clear();
    for (int i = 0; i < widget.items.length; i++) {
      _keyIndexMap[ValueKey(widget.items[i])] = i;
    }
  }

  @override
  void didUpdateWidget(covariant FileListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialZoomLevel != widget.initialZoomLevel) {
      _zoomLevel = widget.initialZoomLevel;
    }
    if (oldWidget.items != widget.items) {
      _updateKeyIndexMap();
    }
  }

  double _computeItemExtent(double zoom) {
    final textScaler = MediaQuery.textScalerOf(context);
    final effectiveTextScaler = TextScaler.linear(
      textScaler.scale(1.0) * zoom,
    );
    final baseContentHeight = (widget.isCompact ? 32.0 : 44.0) * zoom;
    final scaledTextHeight = effectiveTextScaler.scale(
      widget.isDetailed ? 46.0 : 24.0,
    );
    final contentHeight = math.max(baseContentHeight, scaledTextHeight);
    return contentHeight + (widget.isCompact ? 8.0 : 20.0) * zoom + 2.0;
  }

  double _computeMaxScroll(double itemExtent, double viewport) {
    final bottomPadding = AppSpacing.floatingStackClearance +
        MediaQuery.paddingOf(context).bottom;
    final totalHeight = (widget.items.length * itemExtent) + bottomPadding + 8.0;
    return math.max(0.0, totalHeight - viewport);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baselineScale = _zoomLevel;
    _lastPointerCount = details.pointerCount;
    _isZooming = true;

    final controller = widget.scrollController;
    if (controller != null && controller.hasClients) {
      final currentExtent = _computeItemExtent(_zoomLevel);
      final viewport = controller.position.viewportDimension;
      final maxScroll = controller.position.maxScrollExtent;
      final offset = controller.offset;

      _isAtTopAnchor = offset <= 24.0;
      _isAtBottomAnchor = offset >= (maxScroll - 24.0);

      if (!_isAtTopAnchor && !_isAtBottomAnchor) {
        final centerY = offset + (viewport / 2.0);
        _anchorCenterItemIndex = currentExtent > 0 ? (centerY / currentExtent) : 0.0;
      }
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      if (_isZooming) {
        _handleScaleEnd(ScaleEndDetails(pointerCount: details.pointerCount));
      }
      _lastPointerCount = details.pointerCount;
      return;
    }

    if (!_isZooming || _lastPointerCount < 2) {
      _handleScaleStart(ScaleStartDetails(
        focalPoint: details.focalPoint,
        localFocalPoint: details.localFocalPoint,
        pointerCount: details.pointerCount,
      ));
    }
    _lastPointerCount = details.pointerCount;

    final newZoom = (_baselineScale * details.scale).clamp(0.75, 2.0);
    if ((newZoom - _zoomLevel).abs() > 0.005) {
      setState(() {
        _zoomLevel = newZoom;
      });

      final controller = widget.scrollController;
      if (controller != null && controller.hasClients) {
        final newExtent = _computeItemExtent(newZoom);
        final viewport = controller.position.viewportDimension;
        final trueMaxScroll = _computeMaxScroll(newExtent, viewport);

        final double targetOffset;
        if (_isAtTopAnchor) {
          targetOffset = 0.0;
        } else if (_isAtBottomAnchor) {
          targetOffset = trueMaxScroll;
        } else {
          final targetCenterY = _anchorCenterItemIndex * newExtent;
          targetOffset = (targetCenterY - (viewport / 2.0))
              .clamp(0.0, trueMaxScroll)
              .toDouble();
        }

        controller.jumpTo(targetOffset);
      }
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (!_isZooming) return;
    _isZooming = false;
    _lastPointerCount = 0;
    _isAtBottomAnchor = false;
    _isAtTopAnchor = false;
    widget.onZoomLevelChanged?.call(_zoomLevel);
  }


  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta?.abs() ?? 0.0;
      if (delta > 25.0) {
        ThumbnailConcurrency.imageLimiter.cancelTier(TaskPriority.visible);
        ThumbnailConcurrency.videoLimiter.cancelTier(TaskPriority.visible);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final itemExtent = _computeItemExtent(_zoomLevel);
    final scrollPhysics = _ZoomScrollPhysics(isZooming: () => _isZooming);

    // Zoom start/update/end are driven entirely by HoldRangeSelectContainer's
    // onScale* callbacks below (backed by _PinchScaleGestureRecognizer), which
    // are the single source of truth for "is a real 2-finger pinch active".
    // This used to *also* track raw pointer down/up/cancel counts here and
    // force _isZooming back to false as soon as the count dropped below 2 --
    // but that count was independent of (and could desync from) the gesture
    // recognizer's own pointer tracking, which could flip _isZooming off
    // mid-gesture and left the two objects disagreeing about whether a pinch
    // was still in progress. Trusting the scale callbacks alone avoids that.
    return HoldRangeSelectContainer(
        items: widget.items,
        selectedItems: widget.selectedItems,
        isSelectionMode: widget.isSelectionMode,
        onSelectionChanged: (newSelection) =>
            widget.onSelectionChanged?.call(newSelection),
        onLongPressSelect: (entry) => widget.onItemLongPress(entry),
        onScaleStart: _handleScaleStart,
        onScaleUpdate: _handleScaleUpdate,
        onScaleEnd: _handleScaleEnd,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    MediaQuery.textScalerOf(context).scale(1.0) * _zoomLevel,
                  ),
                ),
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: widget.scrollController == null
                      ? ListView.builder(
                          controller: widget.scrollController,
                          physics: scrollPhysics,
                          itemExtent: itemExtent,
                          findChildIndexCallback: (Key key) => _keyIndexMap[key],
                          padding: EdgeInsets.only(
                            top: 0,
                            bottom: AppSpacing.floatingStackClearance +
                                MediaQuery.paddingOf(context).bottom,
                          ),
                          itemCount: total,
                          itemBuilder: (_, index) {
                            final entry = widget.items[index];
                            final isSelected = widget.selectedItems.contains(entry);
                            final isPinned = widget.isPinned?.call(entry) ?? false;
                            final isBookmark = widget.isBookmark?.call(entry) ?? false;
                            final Widget tile;
                            if (entry.isDir) {
                              tile = DirectoryTile(
                                key: ValueKey('dir:${entry.raw}:$isPinned:$isBookmark'),
                                entry: entry,
                                isSelectionMode: widget.isSelectionMode,
                                isSelected: isSelected,
                                isCompact: widget.isCompact,
                                isDetailed: widget.isDetailed,
                                zoomLevel: _zoomLevel,
                                detailColumns: widget.detailColumns,
                                longFileNameMode: widget.longFileNameMode,
                                searchQuery: widget.searchQuery,
                                isDocumentProviderMounted:
                                    widget.isFolderMounted?.call(entry) ?? false,
                                isPinned: isPinned,
                                isBookmark: isBookmark,
                                isSynced: widget.isFolderSynced?.call(entry) ?? false,
                                container: widget.container,
                                currentDirPath: widget.currentDirPath,
                                cacheMode: widget.thumbnailCacheMode,
                                quality: widget.thumbnailQuality,
                                showThumbnailPreview: widget.showThumbnails,
                                showItemActionsMenu: widget.showItemActionsMenu,
                                onTap: () => widget.onDirTap(entry),
                                onLongPress: () {},
                                onMoreTap: widget.onFileLongMenu,
                                onIconTap: widget.onIconTap == null
                                    ? null
                                    : () => widget.onIconTap!(entry),
                              );
                            } else {
                              tile = FileTile(
                                key: ValueKey('file:${entry.raw}:$isPinned:$isBookmark'),
                                entry: entry,
                                isSelectionMode: widget.isSelectionMode,
                                isSelected: isSelected,
                                isCompact: widget.isCompact,
                                isDetailed: widget.isDetailed,
                                zoomLevel: _zoomLevel,
                                detailColumns: widget.detailColumns,
                                longFileNameMode: widget.longFileNameMode,
                                searchQuery: widget.searchQuery,
                                container: widget.container,
                                currentDirPath: widget.currentDirPath,
                                thumbnailCacheMode: widget.thumbnailCacheMode,
                                thumbnailQuality: widget.thumbnailQuality,
                                showThumbnail: widget.showThumbnails,
                                isPinned: isPinned,
                                isBookmark: isBookmark,
                                showItemActionsMenu: widget.showItemActionsMenu,
                                onTap: () => widget.onFileTap(entry),
                                onLongPress: () {},
                                onLongMenu: widget.onFileLongMenu,
                                onIconTap: widget.onIconTap == null
                                    ? null
                                    : () => widget.onIconTap!(entry),
                                archiveContext: widget.archiveContext,
                                archiveRootPath: widget.archiveRootPath,
                              );
                            }
                            return HoldSelectableItem(
                              key: ValueKey(entry),
                              index: index,
                              entry: entry,
                              child: tile,
                            );
                          },
                        )
                      : FastScrollbar(
                          controller: widget.scrollController!,
                          items: widget.items,
                          sortBy: widget.sortBy,
                          padding: EdgeInsets.only(
                            top: 0,
                            bottom: AppSpacing.floatingStackClearance +
                                MediaQuery.paddingOf(context).bottom,
                          ),
                          child: ListView.builder(
                            controller: widget.scrollController,
                            physics: scrollPhysics,
                            itemExtent: itemExtent,
                            findChildIndexCallback: (Key key) => _keyIndexMap[key],
                            padding: EdgeInsets.only(
                              top: 0,
                              bottom: AppSpacing.floatingStackClearance +
                                  MediaQuery.paddingOf(context).bottom,
                            ),
                            itemCount: total,
                            itemBuilder: (_, index) {
                              final entry = widget.items[index];
                              final isSelected = widget.selectedItems.contains(entry);
                              final isPinned = widget.isPinned?.call(entry) ?? false;
                              final isBookmark = widget.isBookmark?.call(entry) ?? false;
                              final Widget tile;
                              if (entry.isDir) {
                                tile = DirectoryTile(
                                  key: ValueKey('dir:${entry.raw}:$isPinned:$isBookmark'),
                                  entry: entry,
                                  isSelectionMode: widget.isSelectionMode,
                                  isSelected: isSelected,
                                  isCompact: widget.isCompact,
                                  isDetailed: widget.isDetailed,
                                  zoomLevel: _zoomLevel,
                                  detailColumns: widget.detailColumns,
                                  longFileNameMode: widget.longFileNameMode,
                                  searchQuery: widget.searchQuery,
                                  isDocumentProviderMounted:
                                      widget.isFolderMounted?.call(entry) ?? false,
                                  isPinned: isPinned,
                                  isBookmark: isBookmark,
                                  isSynced: widget.isFolderSynced?.call(entry) ?? false,
                                  container: widget.container,
                                  currentDirPath: widget.currentDirPath,
                                  cacheMode: widget.thumbnailCacheMode,
                                  quality: widget.thumbnailQuality,
                                  showThumbnailPreview: widget.showThumbnails,
                                  showItemActionsMenu: widget.showItemActionsMenu,
                                  onTap: () => widget.onDirTap(entry),
                                  onLongPress: () {},
                                  onMoreTap: widget.onFileLongMenu,
                                  onIconTap: widget.onIconTap == null
                                      ? null
                                      : () => widget.onIconTap!(entry),
                                );
                              } else {
                                tile = FileTile(
                                  key: ValueKey('file:${entry.raw}:$isPinned:$isBookmark'),
                                  entry: entry,
                                  isSelectionMode: widget.isSelectionMode,
                                  isSelected: isSelected,
                                  isCompact: widget.isCompact,
                                  isDetailed: widget.isDetailed,
                                  zoomLevel: _zoomLevel,
                                  detailColumns: widget.detailColumns,
                                  longFileNameMode: widget.longFileNameMode,
                                  searchQuery: widget.searchQuery,
                                  container: widget.container,
                                  currentDirPath: widget.currentDirPath,
                                  thumbnailCacheMode: widget.thumbnailCacheMode,
                                  thumbnailQuality: widget.thumbnailQuality,
                                  showThumbnail: widget.showThumbnails,
                                  isPinned: isPinned,
                                  isBookmark: isBookmark,
                                  showItemActionsMenu: widget.showItemActionsMenu,
                                  onTap: () => widget.onFileTap(entry),
                                  onLongPress: () {},
                                  onLongMenu: widget.onFileLongMenu,
                                  onIconTap: widget.onIconTap == null
                                      ? null
                                      : () => widget.onIconTap!(entry),
                                  archiveContext: widget.archiveContext,
                                  archiveRootPath: widget.archiveRootPath,
                                );
                              }
                              return HoldSelectableItem(
                                key: ValueKey(entry),
                                index: index,
                                entry: entry,
                                child: tile,
                              );
                            },
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
    );
  }
}