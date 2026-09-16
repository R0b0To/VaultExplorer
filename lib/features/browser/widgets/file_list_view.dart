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
    // Only update zoom if the incoming initialZoomLevel actually changed
    // from a fresh external configuration load, while keeping user's scale intact
    if (oldWidget.initialZoomLevel != widget.initialZoomLevel) {
      _zoomLevel = widget.initialZoomLevel;
    }
    if (oldWidget.items != widget.items) {
      _updateKeyIndexMap();
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baselineScale = _zoomLevel;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _zoomLevel = (_baselineScale * details.scale).clamp(0.75, 2.0);
    });
  }

  void _handleScaleEnd(ScaleEndDetails details) {
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
    final textScaler = MediaQuery.textScalerOf(context);
    final effectiveTextScaler = TextScaler.linear(
      textScaler.scale(1.0) * _zoomLevel,
    );
    final baseContentHeight = (widget.isCompact ? 32.0 : 44.0) * _zoomLevel;
    final scaledTextHeight = effectiveTextScaler.scale(
      widget.isDetailed ? 46.0 : 24.0,
    );
    final contentHeight = math.max(baseContentHeight, scaledTextHeight);
    final itemExtent =
        contentHeight + (widget.isCompact ? 8.0 : 20.0) * _zoomLevel + 2.0;

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
                        physics: const AlwaysScrollableScrollPhysics(),
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
                          physics: const AlwaysScrollableScrollPhysics(),
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