import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/file_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/hold_range_select_container.dart';

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
              child: ListView.builder(
                controller: widget.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
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
                      zoomLevel: _zoomLevel,
                      detailColumns: widget.detailColumns,
                      searchQuery: widget.searchQuery,
                      isDocumentProviderMounted:
                          widget.isFolderMounted?.call(entry) ?? false,
                      isPinned: isPinned,
                      isBookmark: isBookmark,
                      onTap: () => widget.onDirTap(entry),
                      onLongPress: () => widget.onItemLongPress(entry),
                    );
                  } else {
                    tile = FileTile(
                      key: ValueKey('file:${entry.raw}:$isPinned:$isBookmark'),
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
                      isBookmark: isBookmark,
                      onTap: () => widget.onFileTap(entry),
                      onLongPress: () => widget.onItemLongPress(entry),
                      onLongMenu: widget.onFileLongMenu,
                    );
                  }
                  return HoldSelectableItem(
                    index: index,
                    entry: entry,
                    child: tile,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}