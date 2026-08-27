import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/widgets/highlighted_text.dart';
import 'package:vaultexplorer/features/browser/widgets/hold_range_select_container.dart';

class FileGridView extends StatefulWidget {
  final MountedContainer container;
  final List<RawEntry> items;
  final bool isSelectionMode;
  final Set<RawEntry> selectedItems;
  final String currentDirPath;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;
  final bool showFileNames;
  final int initialColumns;
  final ValueChanged<int>? onColumnCountChanged;
  final ValueChanged<RawEntry> onDirTap;
  final ValueChanged<RawEntry> onFileTap;
  final ValueChanged<RawEntry> onItemLongPress;
  final ValueChanged<RawEntry>? onFileLongMenu;
  final ValueChanged<Set<RawEntry>>? onSelectionChanged;
  final String? searchQuery;
  final Set<String> mountedFolderPaths;
  final bool Function(RawEntry entry)? isPinned;
  final bool Function(RawEntry entry)? isBookmark;
  final ScrollController? scrollController;

  const FileGridView({
    super.key,
    required this.container,
    required this.items,
    required this.isSelectionMode,
    required this.selectedItems,
    required this.currentDirPath,
    required this.thumbnailCacheMode,
    required this.thumbnailQuality,
    this.showFileNames = true,
    this.initialColumns = 3,
    this.onColumnCountChanged,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    this.onFileLongMenu,
    this.onSelectionChanged,
    this.searchQuery,
    this.mountedFolderPaths = const {},
    this.isPinned,
    this.isBookmark,
    this.scrollController,
  });

  @override
  State<FileGridView> createState() => _FileGridViewState();
}

class _FileGridViewState extends State<FileGridView> {
  Orientation? _lastOrientation;
  late int _crossAxisCount;
  double _baselineScale = 1.0;

  @override
  void initState() {
    super.initState();
    _crossAxisCount = widget.initialColumns;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != orientation) {
      _lastOrientation = orientation;
      _crossAxisCount = widget.initialColumns.clamp(_minColumns, _maxColumns);
    }
  }

  @override
  void didUpdateWidget(covariant FileGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialColumns != widget.initialColumns) {
      _crossAxisCount = widget.initialColumns.clamp(_minColumns, _maxColumns);
    }
  }

  int get _minColumns {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 3 : 1;
  }

  int get _maxColumns {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 7 : 4;
  }

  double _getAspectRatio(int columns) {
    if (!widget.showFileNames) {
      return 1.0;
    }
    switch (columns) {
      case 1:
        return 1.45;
      case 2:
        return 0.95;
      case 3:
        return 0.8;
      case 4:
        return 0.76;
      case 5:
        return 0.74;
      default:
        return 0.72;
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baselineScale = 1.0;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final scale = details.scale;
    final factor = scale / _baselineScale;
    if (factor > 1.35) {
      if (_crossAxisCount > _minColumns) {
        setState(() {
          _crossAxisCount--;
          _baselineScale = scale;
        });
        widget.onColumnCountChanged?.call(_crossAxisCount);
      }
    } else if (factor < 0.75) {
      if (_crossAxisCount < _maxColumns) {
        setState(() {
          _crossAxisCount++;
          _baselineScale = scale;
        });
        widget.onColumnCountChanged?.call(_crossAxisCount);
      }
    }
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
    return HoldRangeSelectContainer(
      items: widget.items,
      selectedItems: widget.selectedItems,
      isSelectionMode: widget.isSelectionMode,
      onSelectionChanged: (newSelection) =>
          widget.onSelectionChanged?.call(newSelection),
      onLongPressSelect: (entry) => widget.onItemLongPress(entry),
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: GridView.builder(
          controller: widget.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            10,
            12,
            10,
            AppSpacing.floatingStackClearance +
                MediaQuery.paddingOf(context).bottom,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _crossAxisCount,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: _getAspectRatio(_crossAxisCount),
          ),
          itemCount: total,
          itemBuilder: (context, index) {
            final entry = widget.items[index];
            final Widget cell;
            if (entry.isDir) {
              cell = _buildDirCell(context, entry);
            } else {
              cell = _buildFileCell(context, entry);
            }
            return HoldSelectableItem(
              index: index,
              entry: entry,
              child: cell,
            );
          },
        ),
      ),
    );
  }

  Widget _buildDirCell(BuildContext context, RawEntry entry) {
    final isSelected = widget.selectedItems.contains(entry);
    final isPinned = widget.isPinned?.call(entry) ?? false;
    final isBookmark = widget.isBookmark?.call(entry) ?? false;
    final cs = Theme.of(context).colorScheme;
    final fullPath = widget.currentDirPath.isEmpty
        ? entry.name
        : '${widget.currentDirPath}/${entry.name}';
    final isMounted = widget.mountedFolderPaths.contains(fullPath);
    return _GridCell(
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      showFileName: widget.showFileNames,
      isPinned: isPinned,
      isBookmark: isBookmark,
      isPlaceholder: entry.isPlaceholder,
      onTap: entry.isPlaceholder ? () {} : () => widget.onDirTap(entry),
      onLongPress: entry.isPlaceholder ? () {} : () => widget.onItemLongPress(entry),
      preview: Center(
        child: Icon(
          isMounted ? Icons.folder_shared_rounded : Icons.folder_rounded,
          size: _crossAxisCount == 1 ? AppIconSize.hero + 16 : AppIconSize.hero,
          color: isSelected ? cs.primary : (isMounted ? cs.tertiary : cs.secondary),
        ),
      ),
      label: entry.name,
      searchQuery: widget.searchQuery,
    );
  }

  Widget _buildFileCell(BuildContext context, RawEntry entry) {
    final cleanName = entry.name;
    final fullPath = widget.currentDirPath.isEmpty
        ? cleanName
        : '${widget.currentDirPath}/$cleanName';
    final isSelected = widget.selectedItems.contains(entry);
    final isPinned = widget.isPinned?.call(entry) ?? false;
    final isBookmark = widget.isBookmark?.call(entry) ?? false;
    String displayName = cleanName;
    final ext = cleanName.split('.').last;
    final vaultIcon = vaultIconForExt(ext);
    final vaultColor = vaultColorForExt(ext);
    if (vaultIcon != null) {
      final nameParts = cleanName.split('.');
      if (nameParts.length > 1) {
        nameParts.removeLast();
        displayName = nameParts.join('.');
      }
    }
    final isImg = MediaViewerConstants.isImage(cleanName) && !entry.isPlaceholder;
    final isVid = MediaViewerConstants.isVideo(cleanName) && !entry.isPlaceholder;
    Widget previewWidget;
    if (vaultIcon != null) {
      previewWidget = Center(
        child: Icon(
          vaultIcon,
          size: _crossAxisCount == 1 ? AppIconSize.hero : AppIconSize.feature,
          color: vaultColor,
        ),
      );
   } else if (isImg) {
      previewWidget = Hero(
        tag: 'media_hero_${widget.container.volId}_$fullPath',
        child: Material(
          type: MaterialType.transparency,
          child: _EncryptedImageGridThumb(
            container: widget.container,
            filePath: fullPath,
            cacheMode: widget.thumbnailCacheMode,
            quality: widget.thumbnailQuality,
          ),
        ),
      );
    } else if (isVid) {
      previewWidget = Hero(
        tag: 'media_hero_${widget.container.volId}_$fullPath',
        child: Material(
          type: MaterialType.transparency,
          child: _VideoThumb(
            container: widget.container,
            filePath: fullPath,
            cacheMode: widget.thumbnailCacheMode,
            quality: widget.thumbnailQuality,
          ),
        ),
      );
    } else {
      previewWidget = Center(
        child: Icon(
          iconForFile(cleanName),
          size: _crossAxisCount == 1 ? AppIconSize.hero : AppIconSize.feature,
          color: colorForFile(cleanName),
        ),
      );
    }
    return _GridCell(
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      showFileName: widget.showFileNames,
      isPinned: isPinned,
      isBookmark: isBookmark,
      isPlaceholder: entry.isPlaceholder,
      onTap: entry.isPlaceholder ? () {} : () => widget.onFileTap(entry),
      onLongPress: entry.isPlaceholder ? () {} : () => widget.onItemLongPress(entry),
      onMoreTap: (widget.isSelectionMode || entry.isPlaceholder)
          ? null
          : () => widget.onFileLongMenu?.call(entry),
      preview: previewWidget,
      label: displayName,
      searchQuery: widget.searchQuery,
    );
  }
}

class _GridCell extends StatelessWidget {
  final Widget preview;
  final String label;
  final String? searchQuery;
  final bool isSelected;
  final bool isSelectionMode;
  final bool showFileName;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onMoreTap;
  final bool isPinned;
  final bool isBookmark;
  final bool isPlaceholder;
  const _GridCell({
    required this.preview,
    required this.label,
    this.searchQuery,
    required this.isSelected,
    required this.isSelectionMode,
    this.showFileName = true,
    required this.onTap,
    required this.onLongPress,
    this.onMoreTap,
    this.isPinned = false,
    this.isBookmark = false,
    this.isPlaceholder = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    Widget cell = Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outlineVariant,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      color: isSelected
          ? cs.primaryContainer.withValues(alpha: 0.3)
          : cs.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  preview,
                  if (isSelected)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  if ((isPinned || isBookmark) && !isSelected)
                    Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color:
                                cs.surfaceContainerHigh.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isPinned)
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 14,
                                  color: cs.primary,
                                ),
                              if (isBookmark)
                                Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: context.semanticColors.bookmark,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (isSelected)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _CheckBadge(
                          color: cs.primary,
                          onColor: cs.onPrimary,
                        ),
                      ),
                    ),
                  if (isPlaceholder)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (showFileName)
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                color: isSelected
                    ? Colors.transparent
                    : cs.surfaceContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HighlightedText(
                      text: label,
                      query: searchQuery,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (isPlaceholder) {
      cell = Opacity(opacity: 0.5, child: cell);
    }
    return cell;
  }
}

class _CheckBadge extends StatelessWidget {
  final Color color;
  final Color onColor;
  const _CheckBadge({required this.color, required this.onColor});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child:
            Icon(Icons.check_rounded, size: AppIconSize.inline, color: onColor),
      );
}

class _EncryptedImageGridThumb extends StatelessWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  const _EncryptedImageGridThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
  });
  static Future<Uint8List> _fetch(
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await ThumbnailCacheService.get(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }
    Uint8List? thumbBytes = await vaultExplorerApi.getImageThumbnail(
      container,
      path,
      targetSize: quality.scaledSize(180),
      quality: quality.jpegQuality,
    );
    if (thumbBytes == null || thumbBytes.isEmpty) {
      final size = await vaultExplorerApi.getFileSize(container, path);
      if (size <= 0) throw Exception('Empty file (size <= 0)');
      final raw = await vaultExplorerApi.readFileChunk(
        container,
        path,
        0,
        size,
      );
      if (raw == null || raw.isEmpty) throw Exception('File chunk read failed');
      if (raw.length < 200 * 1024) {
        ThumbnailCacheService.putInMemory(container, path, raw, quality);
      }
      return raw;
    }
    ThumbnailCacheService.putInMemory(container, path, thumbBytes, quality);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        ThumbnailCacheService.put(
          container: container,
          filePath: path,
          data: thumbBytes,
          mode: mode,
          quality: quality,
        ),
      );
    }
    return thumbBytes;
  }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AsyncThumbnail(
      key: ValueKey('img:$filePath'),
      container: container,
      filePath: filePath,
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: ThumbnailConcurrency.imageLimiter,
      fetchFn: (c, p) => _fetch(c, p, cacheMode, quality),
      debounce: const Duration(milliseconds: 100),
      syncLookup: () =>
          ThumbnailCacheService.getFromMemory(container, filePath, quality),
      cacheHeight: quality.scaledSize(180),
      imageBuilder: (context, bytes, cacheHeight) => Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheHeight: cacheHeight,
        errorBuilder: (_, _, _) => _errorPlaceholder(cs),
      ),
      loadingBuilder: (context) => Container(
        color: cs.surfaceContainerLow,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: cs.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
      errorBuilder: (context) => _errorPlaceholder(cs),
    );
  }
  Widget _errorPlaceholder(ColorScheme cs) => Container(
        color: cs.surfaceContainerLow,
        child: Center(
          child: Icon(Icons.broken_image_rounded,
              size: AppIconSize.feature, color: cs.outline),
        ),
      );
}

class _VideoThumb extends StatelessWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  const _VideoThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
  });
  static Future<Uint8List> _fetch(
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
  ) =>
      VideoThumbnailFetcher.fetch(
        container,
        path,
        mode: mode,
        quality: quality,
        targetSize: quality.scaledSize(180),
      );
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        AsyncThumbnail(
          key: ValueKey('vid:$filePath'),
          container: container,
          filePath: filePath,
          cache: ThumbnailConcurrency.inFlightThumbnails,
          limiter: ThumbnailConcurrency.videoLimiter,
          fetchFn: (c, p) => _fetch(c, p, cacheMode, quality),
          debounce: const Duration(milliseconds: 150),
          syncLookup: () =>
              ThumbnailCacheService.getFromMemory(container, filePath, quality),
          cacheHeight: quality.scaledSize(180),
          imageBuilder: (context, bytes, cacheHeight) => Image.memory(
            bytes,
            fit: BoxFit.cover,
            cacheHeight: cacheHeight,
            errorBuilder: (_, _, _) => _errorPlaceholder(cs),
          ),
          loadingBuilder: (context) => Container(
            color: cs.surfaceContainerLow,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: cs.primary.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          errorBuilder: (context) => _errorPlaceholder(cs),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Icons.play_circle_outline_rounded,
              size: AppIconSize.action,
              color: cs.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
  Widget _errorPlaceholder(ColorScheme cs) => Container(
        color: cs.surfaceContainerLow,
        child: Center(
          child: Icon(Icons.broken_image_rounded,
              size: AppIconSize.feature, color: cs.outline),
        ),
      );
}