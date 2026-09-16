import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/widgets/archive_thumbnail_support.dart';
import 'package:vaultexplorer/features/browser/widgets/fast_scrollbar.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_thumbnail_preview.dart';
import 'package:vaultexplorer/features/browser/widgets/grid_card_shell.dart';
import 'package:vaultexplorer/features/browser/widgets/hold_range_select_container.dart';

class FileMasonryView extends ConsumerStatefulWidget {
  final MountedContainer container;
  final List<RawEntry> items;
  final bool isSelectionMode;
  final Set<RawEntry> selectedItems;
  final String currentDirPath;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;
  final bool showFileNames;
  final LongFileNameDisplayMode longFileNameMode;
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

  final ArchiveContext? archiveContext;
  final String? archiveRootPath;
  final SortBy? sortBy;

  const FileMasonryView({
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
    this.initialColumns = 2,
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
    this.archiveContext,
    this.archiveRootPath,
    this.sortBy,
  });

  @override
  ConsumerState<FileMasonryView> createState() => _FileMasonryViewState();
}

class _FileMasonryViewState extends ConsumerState<FileMasonryView> {
  Orientation? _lastOrientation;
  late int _columnCount;
  double _baselineScale = 1.0;
  late final ThumbnailCacheService _thumbnailCache;

  final Map<String, double> _renderedRatios = {};
  bool _hasPendingRebuild = false;

  @override
  void initState() {
    super.initState();
    _thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    _columnCount = widget.initialColumns;
    _prewarmMemoryCache();
    _preloadDiskAspectRatios();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != orientation) {
      _columnCount = GridCardUtils.adaptColumnsForOrientation(
        currentOrientation: orientation,
        lastOrientation: _lastOrientation,
        currentColumns: _columnCount,
        minColumns: _minColumns,
        maxColumns: _maxColumns,
      );
      _lastOrientation = orientation;
    }
  }

  @override
  void didUpdateWidget(covariant FileMasonryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialColumns != widget.initialColumns) {
      _columnCount = widget.initialColumns.clamp(_minColumns, _maxColumns);
    }
    if (oldWidget.currentDirPath != widget.currentDirPath ||
        oldWidget.items != widget.items) {
      _renderedRatios.clear();
      _prewarmMemoryCache();
      _preloadDiskAspectRatios();
    }
  }

  int get _minColumns {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 2 : 1;
  }

  int get _maxColumns {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 6 : 3;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baselineScale = 1.0;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final scale = details.scale;
    final factor = scale / _baselineScale;
    if (factor > 1.35) {
      if (_columnCount > _minColumns) {
        setState(() {
          _columnCount--;
          _baselineScale = scale;
        });
        widget.onColumnCountChanged?.call(_columnCount);
      }
    } else if (factor < 0.75) {
      if (_columnCount < _maxColumns) {
        setState(() {
          _columnCount++;
          _baselineScale = scale;
        });
        widget.onColumnCountChanged?.call(_columnCount);
      }
    }
  }

  static const _minRatio = 0.5;
  static const _maxRatio = 2.2;
  static const _iconRatio = 1.0;
  static const _videoDefaultRatio = 16.0 / 9.0;

  void _prewarmMemoryCache() {
    for (final item in widget.items) {
      if (item.isDir) continue;
      final fullPath = widget.currentDirPath.isEmpty
          ? item.name
          : '${widget.currentDirPath}/${item.name}';
      if (MediaAspectRatioCache.get(widget.container, fullPath) == null) {
        final syncEntry = _thumbnailCache.peekMemoryWithSize(
          widget.container,
          fullPath,
          widget.thumbnailQuality,
        );
        if (syncEntry != null && syncEntry.$2 != null && syncEntry.$3 != null) {
          final w = syncEntry.$2!;
          final h = syncEntry.$3!;
          if (w > 0 && h > 0) {
            MediaAspectRatioCache.put(widget.container, fullPath, w, h);
          }
        }
      }
    }
  }

  Future<void> _preloadDiskAspectRatios() async {
    if (widget.thumbnailCacheMode == ThumbnailCacheMode.disabled) return;

    final container = widget.container;
    final dirPath = widget.currentDirPath;
    final quality = widget.thumbnailQuality;
    final mode = widget.thumbnailCacheMode;

    final mediaItems = widget.items
        .where((e) => !e.isDir && _hasVisualPreview(e.name))
        .toList();
    if (mediaItems.isEmpty) return;

    for (final entry in mediaItems) {
      if (!mounted || PlaybackThrottleController.isPlaybackActive.value) {
        return;
      }
      final fullPath = dirPath.isEmpty ? entry.name : '$dirPath/${entry.name}';
      if (MediaAspectRatioCache.get(container, fullPath) != null) continue;

      try {
        final cached = await _thumbnailCache.fetchWithSize(
          container: container,
          filePath: fullPath,
          mode: mode,
          quality: quality,
        );
        if (cached != null && cached.$2 != null && cached.$3 != null) {
          _onSizeKnown(fullPath, cached.$2!, cached.$3!);
        }
      } catch (_) {}
    }
  }

  double _defaultRatioFor(String fileName) {
    if (MediaViewerConstants.isVideo(fileName)) {
      return _videoDefaultRatio.clamp(_minRatio, _maxRatio);
    }
    return _iconRatio;
  }

  double _aspectRatioFor(RawEntry entry, String fullPath,
      {required bool hasVisualPreview}) {
    if (!hasVisualPreview) {
      _renderedRatios[fullPath] = _iconRatio;
      return _iconRatio;
    }

    double? decoded = MediaAspectRatioCache.get(widget.container, fullPath);

    if (decoded == null) {
      final syncEntry = _thumbnailCache.peekMemoryWithSize(
        widget.container,
        fullPath,
        widget.thumbnailQuality,
      );
      if (syncEntry != null && syncEntry.$2 != null && syncEntry.$3 != null) {
        final w = syncEntry.$2!;
        final h = syncEntry.$3!;
        if (w > 0 && h > 0) {
          MediaAspectRatioCache.put(widget.container, fullPath, w, h);
          decoded = w / h;
        }
      }
    }

    final ratioToUse = (decoded ?? _defaultRatioFor(entry.name))
        .clamp(_minRatio, _maxRatio)
        .toDouble();

    _renderedRatios[fullPath] = ratioToUse;
    return ratioToUse;
  }

  void _onSizeKnown(String fullPath, int width, int height) {
    if (width <= 0 || height <= 0) return;

    final ratio = (width / height).clamp(_minRatio, _maxRatio).toDouble();
    MediaAspectRatioCache.put(widget.container, fullPath, width, height);

    final renderedRatio = _renderedRatios[fullPath];
    if (renderedRatio == ratio) return;

    _renderedRatios[fullPath] = ratio;
    _scheduleRebuild();
  }

  void _scheduleRebuild() {
    if (_hasPendingRebuild) return;
    _hasPendingRebuild = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _hasPendingRebuild = false;
        setState(() {});
      } else {
        _hasPendingRebuild = false;
      }
    });
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
    if (total == 0) return const SizedBox.shrink();

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
        child: widget.scrollController == null
            ? MasonryGridView.count(
                controller: widget.scrollController,
                crossAxisCount: _columnCount,
                physics: const AlwaysScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                cacheExtent: 800,
                padding: EdgeInsets.fromLTRB(
                  10,
                  12,
                  10,
                  AppSpacing.floatingStackClearance +
                      MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: total,
                itemBuilder: (context, i) {
                  final entry = widget.items[i];
                  final isDir = entry.isDir;
                  final isPinned = widget.isPinned?.call(entry) ?? false;
                  final isBookmark = widget.isBookmark?.call(entry) ?? false;
                  final fullPath = widget.currentDirPath.isEmpty
                      ? entry.name
                      : '${widget.currentDirPath}/${entry.name}';
                  final hasVisualPreview = !isDir && _hasVisualPreview(entry.name);
                  final ratio = _aspectRatioFor(entry, fullPath,
                      hasVisualPreview: hasVisualPreview);

                  final cell = isDir
                      ? _buildDirCell(context, entry, fullPath, ratio)
                      : _buildFileCell(context, entry, fullPath, ratio);

                  return HoldSelectableItem(
                    index: i,
                    entry: entry,
                    child: cell,
                  );
                },
              )
            : FastScrollbar(
                controller: widget.scrollController!,
                items: widget.items,
                sortBy: widget.sortBy,
                padding: EdgeInsets.only(
                  top: 12,
                  bottom: AppSpacing.floatingStackClearance +
                      MediaQuery.paddingOf(context).bottom,
                ),
                child: MasonryGridView.count(
                  controller: widget.scrollController,
                  crossAxisCount: _columnCount,
                  physics: const AlwaysScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  cacheExtent: 800,
                  padding: EdgeInsets.fromLTRB(
                    10,
                    12,
                    10,
                    AppSpacing.floatingStackClearance +
                        MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: total,
                  itemBuilder: (context, i) {
                    final entry = widget.items[i];
                    final isDir = entry.isDir;
                    final isPinned = widget.isPinned?.call(entry) ?? false;
                    final isBookmark = widget.isBookmark?.call(entry) ?? false;
                    final fullPath = widget.currentDirPath.isEmpty
                        ? entry.name
                        : '${widget.currentDirPath}/${entry.name}';
                    final hasVisualPreview = !isDir && _hasVisualPreview(entry.name);
                    final ratio = _aspectRatioFor(entry, fullPath,
                        hasVisualPreview: hasVisualPreview);

                    final cell = isDir
                        ? _buildDirCell(context, entry, fullPath, ratio)
                        : _buildFileCell(context, entry, fullPath, ratio);

                    return HoldSelectableItem(
                      index: i,
                      entry: entry,
                      child: cell,
                    );
                  },
                ),
              ),
      ),
    );
  }

  bool _hasVisualPreview(String fileName) {
    final ext = fileName.split('.').last;
    if (vaultIconForExt(ext) != null) return false;
    if (widget.archiveContext != null &&
        MediaViewerConstants.isVideo(fileName)) {
      return false;
    }
    return MediaViewerConstants.isImage(fileName) ||
        MediaViewerConstants.isVideo(fileName);
  }

  Widget _buildDirCell(
      BuildContext context, RawEntry entry, String fullPath, double ratio) {
    final isSelected = widget.selectedItems.contains(entry);
    final cs = Theme.of(context).colorScheme;
    final isMounted = widget.mountedFolderPaths.contains(fullPath);

    final iconSize = GridCardUtils.calculateIconSize(context, _columnCount);
    final folderIcon = Icon(
      isMounted ? Icons.folder_shared_rounded : Icons.folder_rounded,
      size: iconSize,
      color: isSelected
          ? cs.primary
          : (isMounted ? cs.tertiary : cs.secondary),
    );

    return GridCardShell(
      key: ValueKey(
          'dir:$fullPath:${widget.isPinned?.call(entry)}:${widget.isBookmark?.call(entry)}'),
      aspectRatio: ratio,
      cardColor: GridCardUtils.folderCardColor(cs, isMounted: isMounted),
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      showFileName: true,
      longFileNameMode: widget.longFileNameMode,
      isPinned: widget.isPinned?.call(entry) ?? false,
      isBookmark: widget.isBookmark?.call(entry) ?? false,
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

  Widget _buildFileCell(
      BuildContext context, RawEntry entry, String fullPath, double ratio) {
    final cs = Theme.of(context).colorScheme;
    final cleanName = entry.name;
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
    final hasRealThumbnail = MediaViewerConstants.hasRealThumbnail(
      cleanName,
      insideArchive: widget.archiveContext != null,
      isPlaceholder: entry.isPlaceholder,
    );

    Widget previewWidget;
    final iconSize = GridCardUtils.calculateIconSize(context, _columnCount);

    if (vaultIcon != null) {
      previewWidget = Center(
        child: Icon(vaultIcon, size: iconSize, color: vaultColor),
      );
    } else if (isImg) {
      previewWidget = Hero(
        tag: 'media_hero_${widget.container.volId}_$fullPath',
        child: Material(
          type: MaterialType.transparency,
          child: _EncryptedImageMasonryThumb(
            container: widget.container,
            filePath: fullPath,
            cacheMode: widget.thumbnailCacheMode,
            quality: widget.thumbnailQuality,
            onSizeKnown: (w, h) => _onSizeKnown(fullPath, w, h),
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
          child: _VideoMasonryThumb(
            container: widget.container,
            filePath: fullPath,
            cacheMode: widget.thumbnailCacheMode,
            quality: widget.thumbnailQuality,
            onSizeKnown: (w, h) => _onSizeKnown(fullPath, w, h),
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
      key: ValueKey(
          'file:$fullPath:${widget.isPinned?.call(entry)}:${widget.isBookmark?.call(entry)}'),
      aspectRatio: ratio,
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

class _EncryptedImageMasonryThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final void Function(int width, int height) onSizeKnown;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;

  const _EncryptedImageMasonryThumb({
    super.key,
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.onSizeKnown,
    this.archiveContext,
    this.archiveRootPath,
  });

  static Future<void> _checkAndReportSizeFromBytes(
    MountedContainer container,
    String path,
    Uint8List bytes,
    void Function(int width, int height) onSizeKnown,
  ) async {
    if (bytes.isEmpty) return;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      onSizeKnown(frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
    } catch (_) {}
  }

  static Future<Uint8List> _fetch(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
    void Function(int width, int height) onSizeKnown,
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
      await _checkAndReportSizeFromBytes(container, path, bytes, onSizeKnown);
      return bytes;
    }
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await thumbnailCache.fetchWithSize(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.$1.isNotEmpty) {
        final (bytes, width, height) = cached;
        if (width != null && height != null) {
          onSizeKnown(width, height);
        } else {
          await _checkAndReportSizeFromBytes(
              container, path, bytes, onSizeKnown);
        }
        return bytes;
      }
    }
    final thumb = await fileIoApi.getImageThumbnailWithSize(
      container,
      path,
      targetSize: quality.scaledSize(180),
      quality: quality.jpegQuality,
    );
    final thumbBytes = thumb?.bytes;
    if (thumbBytes == null || thumbBytes.isEmpty) {
      final size = await fileIoApi.getFileSize(container, path);
      if (size <= 0) throw Exception('Empty file (size <= 0)');
      final raw = await fileIoApi.readFileChunk(
        container,
        path,
        0,
        size,
      );
      if (raw == null || raw.isEmpty) {
        throw Exception('File chunk read failed');
      }
      if (raw.length < 200 * 1024) {
        thumbnailCache.cacheInMemory(container, path, raw, quality);
        await _checkAndReportSizeFromBytes(container, path, raw, onSizeKnown);
      }
      return raw;
    }
    onSizeKnown(thumb!.width, thumb.height);
    thumbnailCache.cacheInMemory(
      container,
      path,
      thumbBytes,
      quality,
      thumb.width,
      thumb.height,
    );
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        thumbnailCache.store(
          container: container,
          filePath: path,
          data: thumbBytes,
          mode: mode,
          quality: quality,
          width: thumb.width,
          height: thumb.height,
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

    final syncEntry =
        thumbnailCache.peekMemoryWithSize(container, filePath, quality);
    final syncBytes = syncEntry?.$1;
    if (syncEntry != null && syncEntry.$1.isNotEmpty) {
      final (bytes, width, height) = syncEntry;
      if (width != null && height != null) {
        onSizeKnown(width, height);
      } else {
        _checkAndReportSizeFromBytes(container, filePath, bytes, onSizeKnown);
      }
    }
    return AsyncThumbnail(
      key: ValueKey('img:$filePath'),
      container: container,
      filePath: filePath,
      quality: quality,
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: ThumbnailConcurrency.imageLimiter,
      fetchFn: (c, p) => _fetch(
        thumbnailCache,
        fileIoApi,
        c,
        p,
        cacheMode,
        quality,
        onSizeKnown,
        archiveContext,
        archiveRootPath,
      ),
      debounce: const Duration(milliseconds: 100),
      syncLookup: () => syncBytes,
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

class _VideoMasonryThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final void Function(int width, int height) onSizeKnown;

  const _VideoMasonryThumb({
    super.key,
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.onSizeKnown,
  });

  static Future<void> _checkAndReportSizeFromBytes(
    MountedContainer container,
    String path,
    Uint8List bytes,
    void Function(int width, int height) onSizeKnown,
  ) async {
    if (bytes.isEmpty) return;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      onSizeKnown(frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
    } catch (_) {}
  }

  static Future<Uint8List> _fetch(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
    void Function(int width, int height) onSizeKnown,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await thumbnailCache.fetchWithSize(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.$1.isNotEmpty) {
        final (bytes, width, height) = cached;
        if (width != null && height != null) {
          onSizeKnown(width, height);
        } else {
          await _checkAndReportSizeFromBytes(
              container, path, bytes, onSizeKnown);
        }
        return bytes;
      }
    }
    final thumb = await fileIoApi.getVideoThumbnailWithSize(
      container,
      path,
      quality: quality.jpegQuality,
      targetSize: quality.scaledSize(180),
    );
    final data = thumb?.bytes;
    if (data == null || data.isEmpty) {
      throw StateError('Video thumbnail unavailable');
    }
    onSizeKnown(thumb!.width, thumb.height);

    thumbnailCache.cacheInMemory(
      container,
      path,
      data,
      quality,
      thumb.width,
      thumb.height,
    );
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        thumbnailCache.store(
          container: container,
          filePath: path,
          data: data,
          mode: mode,
          quality: quality,
          width: thumb.width,
          height: thumb.height,
        ),
      );
    }
    return data;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final cs = Theme.of(context).colorScheme;

    final syncEntry =
        thumbnailCache.peekMemoryWithSize(container, filePath, quality);
    final syncBytes = syncEntry?.$1;
    if (syncEntry != null && syncEntry.$1.isNotEmpty) {
      final (bytes, width, height) = syncEntry;
      if (width != null && height != null) {
        onSizeKnown(width, height);
      } else {
        _checkAndReportSizeFromBytes(container, filePath, bytes, onSizeKnown);
      }
    }
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
          fetchFn: (c, p) => _fetch(
              thumbnailCache, fileIoApi, c, p, cacheMode, quality, onSizeKnown),
          debounce: const Duration(milliseconds: 150),
          syncLookup: () => syncBytes,
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