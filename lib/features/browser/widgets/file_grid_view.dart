import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/grid_aspect_ratio.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/widgets/apk_icon_support.dart';
import 'package:vaultexplorer/features/browser/widgets/archive_thumbnail_support.dart';
import 'package:vaultexplorer/features/browser/widgets/fast_scrollbar.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_thumbnail_preview.dart';
import 'package:vaultexplorer/features/browser/widgets/grid_card_shell.dart';
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
  final LongFileNameDisplayMode longFileNameMode;
  final GridAspectRatio gridAspectRatio;
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
  final bool Function(RawEntry entry)? isFolderSynced;
  final ScrollController? scrollController;

  final ArchiveContext? archiveContext;
  final String? archiveRootPath;
  final SortBy? sortBy;

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
    this.longFileNameMode = LongFileNameDisplayMode.ellipsizeEnd,
    this.gridAspectRatio = GridAspectRatio.square,
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
    this.isFolderSynced,
    this.scrollController,
    this.archiveContext,
    this.archiveRootPath,
    this.sortBy,
  });
  
  @override
  State<FileGridView> createState() => _FileGridViewState();
}

class _FileGridViewState extends State<FileGridView>
    with SingleTickerProviderStateMixin {
  Orientation? _lastOrientation;
  late int _crossAxisCount;
  double _baselineScale = 1.0;
  final Map<Key, int> _keyIndexMap = {};

  int? _anchorItemIndex;

  // Animation controller for clearly visible column morph transition
  late final AnimationController _morphController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _crossAxisCount = widget.initialColumns;
    _updateKeyIndexMap();

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1.0,
    );
    _scaleAnimation = const AlwaysStoppedAnimation<double>(1.0);
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  void _updateKeyIndexMap() {
    _keyIndexMap.clear();
    for (int i = 0; i < widget.items.length; i++) {
      _keyIndexMap[ValueKey(widget.items[i])] = i;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != orientation) {
      _crossAxisCount = widget.initialColumns.clamp(_minColumns, _maxColumns);
      _lastOrientation = orientation;
    }
  }

  @override
  void didUpdateWidget(covariant FileGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialColumns != widget.initialColumns) {
      final newCols = widget.initialColumns.clamp(_minColumns, _maxColumns);
      if (newCols != _crossAxisCount) {
        _changeColumns(newCols, 1.0);
      }
    }
    if (oldWidget.items != widget.items) {
      _updateKeyIndexMap();
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
    final previewRatio = widget.gridAspectRatio.ratio;
    if (!widget.showFileNames) {
      return previewRatio;
    }
    final width = MediaQuery.sizeOf(context).width;
    final tileWidth = (width - 20 - (columns - 1) * 8) / columns;
    const labelHeight = 36.0;
    final previewHeight = tileWidth / previewRatio;
    final totalHeight = previewHeight + labelHeight;
    return tileWidth / totalHeight;
  }

  double _getTileHeight(int columns) {
    final width = MediaQuery.sizeOf(context).width;
    final tileWidth = (width - 20 - (columns - 1) * 8) / columns;
    final previewRatio = widget.gridAspectRatio.ratio;
    final labelHeight = widget.showFileNames ? 36.0 : 0.0;
    return (tileWidth / previewRatio) + labelHeight;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baselineScale = 1.0;

    final controller = widget.scrollController;
    if (controller != null && controller.hasClients) {
      final currentTileHeight = _getTileHeight(_crossAxisCount);
      final rowHeight = currentTileHeight + 8.0;
      final viewport = controller.position.viewportDimension;
      final viewportCenter = controller.offset + (viewport / 2.0);
      final centerRow = math.max(0, ((viewportCenter - 12.0) / rowHeight).round());
      // Lock the center item index ONCE for the whole gesture so continuous zooming never drifts to 0
      _anchorItemIndex = (centerRow * _crossAxisCount).clamp(0, widget.items.length - 1);
    }
  }

  void _changeColumns(int newColumns, double newBaseline) {
    HapticFeedback.selectionClick();

    final oldColumns = _crossAxisCount;
    final isZoomIn = newColumns < oldColumns;

    setState(() {
      _crossAxisCount = newColumns;
      _baselineScale = newBaseline;
    });
    widget.onColumnCountChanged?.call(_crossAxisCount);

    // Snappy physical pop — NO black fade, 100% solid & bright at all times!
    final startScale = isZoomIn ? 0.90 : 1.10;
    _scaleAnimation = Tween<double>(begin: startScale, end: 1.0).animate(
      CurvedAnimation(parent: _morphController, curve: Curves.easeOutCubic),
    );
    _morphController.forward(from: 0.0);

    final controller = widget.scrollController;
    final anchor = _anchorItemIndex;
    if (controller != null && controller.hasClients && anchor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!controller.hasClients) return;
        final newTileHeight = _getTileHeight(newColumns);
        final newRowHeight = newTileHeight + 8.0;
        final targetRow = anchor ~/ newColumns;
        final targetRowCenter = 12.0 + (targetRow * newRowHeight) + (newTileHeight / 2.0);
        final viewport = controller.position.viewportDimension;
        final maxScroll = controller.position.maxScrollExtent;
        final targetOffset = (targetRowCenter - (viewport / 2.0))
            .clamp(0.0, math.max<double>(0.0, maxScroll))
            .toDouble();
        controller.jumpTo(targetOffset);
      });
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    if (_anchorItemIndex == null) {
      _handleScaleStart(ScaleStartDetails(
        focalPoint: details.focalPoint,
        localFocalPoint: details.localFocalPoint,
        pointerCount: details.pointerCount,
      ));
    }

    final scale = details.scale;
    final factor = scale / _baselineScale;

    // Trigger column shift only on crossing threshold; no pre-threshold jitter
    if (factor > 1.18 && _crossAxisCount > _minColumns) {
      _changeColumns(_crossAxisCount - 1, scale);
    } else if (factor < 0.82 && _crossAxisCount < _maxColumns) {
      _changeColumns(_crossAxisCount + 1, scale);
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _anchorItemIndex = null;
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

  Widget _buildAnimatedGridView(ScrollController? controller, int total) {
    return AnimatedBuilder(
      animation: _morphController,
      builder: (context, child) {
        return ClipRect(
          child: Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: GridView.builder(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(), // Native scroll physics that cannot freeze
        findChildIndexCallback: (Key key) => _keyIndexMap[key],
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
          return HoldSelectableItem(
            key: ValueKey(entry),
            index: index,
            entry: entry,
            child: entry.isDir
                ? _buildDirCell(context, entry)
                : _buildFileCell(context, entry),
          );
        },
      ),
    );
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
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: widget.scrollController == null
            ? _buildAnimatedGridView(null, total)
            : FastScrollbar(
                controller: widget.scrollController!,
                items: widget.items,
                sortBy: widget.sortBy,
                padding: EdgeInsets.only(
                  top: 12,
                  bottom: AppSpacing.floatingStackClearance +
                      MediaQuery.paddingOf(context).bottom,
                ),
                child: _buildAnimatedGridView(widget.scrollController, total),
              ),
      ),
    );
  }

  Widget _buildDirCell(BuildContext context, RawEntry entry) {
    final isSelected = widget.selectedItems.contains(entry);
    final cs = Theme.of(context).colorScheme;
    final fullPath = widget.currentDirPath.isEmpty
        ? entry.name
        : '${widget.currentDirPath}/${entry.name}';
    final isMounted = widget.mountedFolderPaths.contains(fullPath);

    final iconSize = GridCardUtils.calculateIconSize(context, _crossAxisCount);
    final folderIcon = Icon(
      Icons.folder_rounded,
      size: iconSize,
      color: isSelected ? cs.primary : cs.secondary,
    );

    return GridCardShell(
      cardColor: GridCardUtils.folderCardColor(cs, isMounted: false),
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      showFileName: true,
      longFileNameMode: widget.longFileNameMode,
      isPinned: widget.isPinned?.call(entry) ?? false,
      isBookmark: widget.isBookmark?.call(entry) ?? false,
      isDocumentProviderMounted: isMounted,
      isSynced: widget.isFolderSynced?.call(entry) ?? false,
      isPlaceholder: entry.isPlaceholder,
      onTap: entry.isPlaceholder ? () {} : () => widget.onDirTap(entry),
      onLongPress: entry.isPlaceholder
          ? () {}
          : () => widget.onItemLongPress(entry),
      preview: entry.isPlaceholder
          ? Center(child: folderIcon)
          : FolderThumbnailPreview(
              key: ValueKey('folder_preview:${widget.container.uri}:$fullPath'),
              container: widget.container,
              folderPath: fullPath,
              cacheMode: widget.thumbnailCacheMode,
              quality: widget.thumbnailQuality,
              iconSize: iconSize,
              child: folderIcon,
            ),
      label: entry.name,
      searchQuery: widget.searchQuery,
    );
  }

  Widget _buildFileCell(BuildContext context, RawEntry entry) {
    final cs = Theme.of(context).colorScheme;
    final cleanName = entry.name;
    final fullPath = widget.currentDirPath.isEmpty
        ? cleanName
        : '${widget.currentDirPath}/$cleanName';
    final isSelected = widget.selectedItems.contains(entry);
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
    final isImg =
        MediaViewerConstants.isImage(cleanName) && !entry.isPlaceholder;
    final isVid =
        MediaViewerConstants.isVideo(cleanName) && !entry.isPlaceholder;
    final isApk = isApkFile(cleanName) && !entry.isPlaceholder;
    final hasRealThumbnail = MediaViewerConstants.hasRealThumbnail(
      cleanName,
      insideArchive: widget.archiveContext != null,
      isPlaceholder: entry.isPlaceholder,
    );

    Widget previewWidget;
    final iconSize = GridCardUtils.calculateIconSize(context, _crossAxisCount);

    if (vaultIcon != null) {
      previewWidget = Center(
        child: Icon(vaultIcon, size: iconSize, color: vaultColor),
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
            archiveContext: widget.archiveContext,
            archiveRootPath: widget.archiveRootPath,
          ),
        ),
      );
    } else if (isVid && widget.archiveContext == null) {
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
    } else if (isApk && widget.archiveContext == null) {
      previewWidget = Center(
        child: SizedBox(
          width: iconSize,
          height: iconSize,
          child: _ApkIconGridThumb(
            container: widget.container,
            filePath: fullPath,
            cacheMode: widget.thumbnailCacheMode,
            quality: widget.thumbnailQuality,
            fallbackIcon: iconForFile(cleanName),
            fallbackColor: colorForFile(cleanName),
            fallbackIconSize: iconSize,
          ),
        ),
      );
    } else {
      previewWidget = Center(
        child: Icon(
          iconForFile(cleanName),
          size: iconSize,
          color: colorForFile(cleanName),
        ),
      );
    }

    return GridCardShell(
      cardColor: GridCardUtils.folderCardColor(cs, isMounted: false),
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      showFileName: widget.showFileNames || !hasRealThumbnail,
      longFileNameMode: widget.longFileNameMode,
      isPinned: widget.isPinned?.call(entry) ?? false,
      isBookmark: widget.isBookmark?.call(entry) ?? false,
      isPlaceholder: entry.isPlaceholder,
      onTap: entry.isPlaceholder ? () {} : () => widget.onFileTap(entry),
      onLongPress: entry.isPlaceholder
          ? () {}
          : () => widget.onItemLongPress(entry),
      onMoreTap: (widget.isSelectionMode || entry.isPlaceholder)
          ? null
          : () => widget.onFileLongMenu?.call(entry),
      preview: previewWidget,
      label: displayName,
      searchQuery: widget.searchQuery,
    );
  }
}

class _EncryptedImageGridThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;

  const _EncryptedImageGridThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    this.archiveContext,
    this.archiveRootPath,
  });

  static Future<Uint8List> _fetch(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
    ArchiveContext? archiveContext,
    String? archiveRootPath,
  ) async {
    if (archiveContext != null && archiveRootPath != null) {
      final bytes = await fetchArchiveEntryForThumbnail(
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
        fullPath: path,
      );
      thumbnailCache.cacheInMemory(container, path, bytes, quality);
      return bytes;
    }
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await thumbnailCache.fetch(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }
    Uint8List? thumbBytes = await fileIoApi.getImageThumbnail(
      container,
      path,
      targetSize: quality.scaledSize(180),
      quality: quality.jpegQuality,
    );
    if (thumbBytes == null || thumbBytes.isEmpty) {
      final size = await fileIoApi.getFileSize(container, path);
      if (size <= 0) throw Exception('Empty file (size <= 0)');
      final raw = await fileIoApi.readFileChunk(container, path, 0, size);
      if (raw == null || raw.isEmpty) throw Exception('File chunk read failed');
      if (raw.length < 200 * 1024) {
        thumbnailCache.cacheInMemory(container, path, raw, quality);
      }
      return raw;
    }
    thumbnailCache.cacheInMemory(container, path, thumbBytes, quality);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        thumbnailCache.store(
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
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final cs = Theme.of(context).colorScheme;

    return AsyncThumbnail(
      key: ValueKey('img:$filePath'),
      container: container,
      filePath: filePath,
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: ThumbnailConcurrency.imageLimiter,
      quality: quality,
      fetchFn: (c, p) => _fetch(
        thumbnailCache,
        fileIoApi,
        c,
        p,
        cacheMode,
        quality,
        archiveContext,
        archiveRootPath,
      ),
      debounce: const Duration(milliseconds: 100),
      syncLookup: () => thumbnailCache.peekMemory(container, filePath, quality),
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
          child: Icon(
            Icons.broken_image_rounded,
            size: AppIconSize.feature,
            color: cs.outline,
          ),
        ),
      );
}

class _VideoThumb extends ConsumerWidget {
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
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
  ) =>
      VideoThumbnailFetcher.fetch(
        thumbnailCache,
        fileIoApi,
        container,
        path,
        mode: mode,
        quality: quality,
        targetSize: quality.scaledSize(180),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final cs = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        AsyncThumbnail(
          key: ValueKey('vid:$filePath'),
          container: container,
          filePath: filePath,
          quality: quality,
          cache: ThumbnailConcurrency.inFlightThumbnails,
          limiter: ThumbnailConcurrency.videoLimiter,
          fetchFn: (c, p) =>
              _fetch(thumbnailCache, fileIoApi, c, p, cacheMode, quality),
          debounce: const Duration(milliseconds: 150),
          syncLookup: () =>
              thumbnailCache.peekMemory(container, filePath, quality),
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
          child: Icon(
            Icons.broken_image_rounded,
            size: AppIconSize.feature,
            color: cs.outline,
          ),
        ),
      );
}

class _ApkIconGridThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;

  final IconData fallbackIcon;
  final Color fallbackColor;
  final double fallbackIconSize;

  const _ApkIconGridThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.fallbackIconSize,
  });

  static Future<Uint8List> _fetch(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await thumbnailCache.fetch(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }
    final bytes = await fetchApkIconForThumbnail(
      container: container,
      filePath: path,
      fileIoApi: fileIoApi,
    );
    thumbnailCache.cacheInMemory(container, path, bytes, quality);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        thumbnailCache.store(
          container: container,
          filePath: path,
          data: bytes,
          mode: mode,
          quality: quality,
        ),
      );
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);

    return AsyncThumbnail(
      key: ValueKey('apk:$filePath'),
      container: container,
      filePath: filePath,
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: ThumbnailConcurrency.imageLimiter,
      quality: quality,
      fetchFn: (c, p) => _fetch(thumbnailCache, fileIoApi, c, p, cacheMode, quality),
      debounce: const Duration(milliseconds: 100),
      syncLookup: () => thumbnailCache.peekMemory(container, filePath, quality),
      cacheHeight: quality.scaledSize(180),
      imageBuilder: (context, bytes, cacheHeight) => Image.memory(
        bytes,
        fit: BoxFit.contain,
        cacheHeight: cacheHeight,
        errorBuilder: (_, _, _) => _fallbackWidget(),
      ),
      loadingBuilder: (context) => Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
      ),
      errorBuilder: (context) => _fallbackWidget(),
    );
  }

  Widget _fallbackWidget() => Center(
        child: Icon(
          fallbackIcon,
          size: fallbackIconSize,
          color: fallbackColor,
        ),
      );
}