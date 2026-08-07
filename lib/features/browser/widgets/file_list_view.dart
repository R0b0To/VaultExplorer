import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/file_tile.dart';

class FileListView extends StatefulWidget {
  final List<RawEntry> items;
  final bool isSelectionMode;
  final bool isCompact;
  final Set<RawEntry> selectedItems;
  final List<FileDetailColumn> detailColumns;
  final ValueChanged<RawEntry> onDirTap;
  final ValueChanged<RawEntry> onFileTap;
  final ValueChanged<RawEntry> onItemLongPress;
  final ValueChanged<RawEntry>? onFileLongMenu;
  final String? searchQuery;
  final bool Function(RawEntry entry)? isFolderMounted;
  final bool Function(RawEntry entry)? isPinned;
  final bool Function(RawEntry entry)? isFavourite;
  final MountedContainer? container;
  final String currentDirPath;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;
  final bool showThumbnails;
  final double initialZoomLevel;
  final ValueChanged<double>? onZoomLevelChanged;

  const FileListView({
    super.key,
    required this.items,
    required this.isSelectionMode,
    this.isCompact = false,
    required this.selectedItems,
    this.detailColumns = const [FileDetailColumn.date, FileDetailColumn.size],
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    this.onFileLongMenu,
    this.searchQuery,
    this.isFolderMounted,
    this.isPinned,
    this.isFavourite,
    this.container,
    this.currentDirPath = '',
    this.thumbnailCacheMode = ThumbnailCacheMode.appCache,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    this.showThumbnails = true,
    this.initialZoomLevel = 1.0,
    this.onZoomLevelChanged,
  });

  @override
  State<FileListView> createState() => _FileListViewState();
}

class _FileListViewState extends State<FileListView> {
  double _baselineScale = 1.0;
  late double _zoomLevel;

  @override
  void initState() {
    super.initState();
    _zoomLevel = widget.initialZoomLevel;
  }

  @override
  void didUpdateWidget(covariant FileListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialZoomLevel != widget.initialZoomLevel &&
        _zoomLevel != widget.initialZoomLevel) {
      _zoomLevel = widget.initialZoomLevel;
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

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final listKey = ValueKey(
      widget.items
          .map((e) =>
              '${e.raw}:${widget.isPinned?.call(e)}:${widget.isFavourite?.call(e)}')
          .join(';'),
    );
    return Column(
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _handleScaleStart,
            onScaleUpdate: _handleScaleUpdate,
            onScaleEnd: _handleScaleEnd,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.textScalerOf(context).scale(1.0) * _zoomLevel,
                ),
              ),
              child: ListView.builder(
                key: listKey,
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
                  final isFav = widget.isFavourite?.call(entry) ?? false;
                  if (entry.isDir) {
                    return DirectoryTile(
                      key: ValueKey('dir:${entry.raw}:$isPinned:$isFav'),
                      entry: entry,
                      isSelectionMode: widget.isSelectionMode,
                      isSelected: isSelected,
                      isCompact: widget.isCompact,
                      zoomLevel: _zoomLevel,
                      detailColumns: widget.detailColumns,
                      searchQuery: widget.searchQuery,
                      isDocumentProviderMounted:
                          widget.isFolderMounted?.call(entry) ?? false,
                      isPinned: isPinned,
                      isFavourite: isFav,
                      onTap: () => widget.onDirTap(entry),
                      onLongPress: () => widget.onItemLongPress(entry),
                    );
                  }
                  return FileTile(
                    key: ValueKey('file:${entry.raw}:$isPinned:$isFav'),
                    entry: entry,
                    isSelectionMode: widget.isSelectionMode,
                    isSelected: isSelected,
                    isCompact: widget.isCompact,
                    zoomLevel: _zoomLevel,
                    detailColumns: widget.detailColumns,
                    searchQuery: widget.searchQuery,
                    container: widget.container,
                    currentDirPath: widget.currentDirPath,
                    thumbnailCacheMode: widget.thumbnailCacheMode,
                    thumbnailQuality: widget.thumbnailQuality,
                    showThumbnail: widget.showThumbnails,
                    isPinned: isPinned,
                    isFavourite: isFav,
                    onTap: () => widget.onFileTap(entry),
                    onLongPress: () => widget.onItemLongPress(entry),
                    onLongMenu: widget.onFileLongMenu,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}