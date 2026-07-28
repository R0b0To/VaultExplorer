import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/widgets/highlighted_text.dart';
import 'dart:ui' as ui;

class FileMasonryView extends StatefulWidget {
  final MountedContainer container;
  final List<RawEntry> dirs;
  final List<RawEntry> files;
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
  final String? searchQuery;
  final Set<String> mountedFolderPaths;
  final bool Function(RawEntry entry)? isPinned;

  const FileMasonryView({
    super.key,
    required this.container,
    required this.dirs,
    required this.files,
    required this.isSelectionMode,
    required this.selectedItems,
    required this.currentDirPath,
    required this.thumbnailCacheMode,
    required this.thumbnailQuality,
    this.showFileNames = true,
    this.initialColumns = 2,
    this.onColumnCountChanged,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    this.onFileLongMenu,
    this.searchQuery,
    this.mountedFolderPaths = const {},
    this.isPinned,
  });

  @override
  State<FileMasonryView> createState() => _FileMasonryViewState();
}

class _FileMasonryViewState extends State<FileMasonryView> {
  Orientation? _lastOrientation;
  late int _columnCount;
  double _baselineScale = 1.0;

  @override
  void initState() {
    super.initState();
    _columnCount = widget.initialColumns;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != orientation) {
      _lastOrientation = orientation;
      _columnCount = widget.initialColumns.clamp(_minColumns, _maxColumns);
    }
  }

  @override
  void didUpdateWidget(covariant FileMasonryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialColumns != widget.initialColumns) {
      _columnCount = widget.initialColumns.clamp(_minColumns, _maxColumns);
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

  double _aspectRatioFor(RawEntry entry, String fullPath,
      {required bool hasVisualPreview}) {
    if (!hasVisualPreview) return _iconRatio;
    final decoded = MediaAspectRatioCache.get(widget.container, fullPath);
    if (decoded == null) return _iconRatio;
    return decoded.clamp(_minRatio, _maxRatio).toDouble();
  }

  void _onSizeKnown(String fullPath, int width, int height) {
    if (width <= 0 || height <= 0) return;
    final before = MediaAspectRatioCache.get(widget.container, fullPath);
    final ratio = width / height;
    if (before == ratio) return;
    MediaAspectRatioCache.put(widget.container, fullPath, width, height);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
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
    final dirEntries = widget.dirs;
    final fileEntries = widget.files;
    final total = dirEntries.length + fileEntries.length;
    if (total == 0) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: MasonryGridView.count(
          crossAxisCount: _columnCount,
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
            final isDir = i < dirEntries.length;
            final entry =
                isDir ? dirEntries[i] : fileEntries[i - dirEntries.length];
            final fullPath = widget.currentDirPath.isEmpty
                ? entry.name
                : '${widget.currentDirPath}/${entry.name}';
            final hasVisualPreview = !isDir && _hasVisualPreview(entry.name);
            final ratio = _aspectRatioFor(entry, fullPath,
                hasVisualPreview: hasVisualPreview);
            return AspectRatio(
              key: ValueKey(
                  '${isDir ? 'dir' : 'file'}:${widget.currentDirPath}/${entry.name}'),
              aspectRatio: ratio,
              child: isDir
                  ? _buildDirCell(context, entry, fullPath)
                  : _buildFileCell(context, entry, fullPath),
            );
          },
        ),
      ),
    );
  }

  bool _hasVisualPreview(String fileName) {
    final ext = fileName.split('.').last;
    if (vaultIconForExt(ext) != null) return false;
    return MediaViewerConstants.isImage(fileName) ||
        MediaViewerConstants.isVideo(fileName);
  }

  Widget _buildDirCell(BuildContext context, RawEntry entry, String fullPath) {
    final isSelected = widget.selectedItems.contains(entry);
    final isPinned = widget.isPinned?.call(entry) ?? false;
    final cs = Theme.of(context).colorScheme;
    final isMounted = widget.mountedFolderPaths.contains(fullPath);
    return _MasonryCell(
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      showFileName: widget.showFileNames,
      isPinned: isPinned,
      onTap: () => widget.onDirTap(entry),
      onLongPress: () => widget.onItemLongPress(entry),
      preview: Center(
        child: Icon(
          isMounted ? Icons.folder_shared_rounded : Icons.folder_rounded,
          size: AppIconSize.hero,
          color: isSelected ? cs.primary : (isMounted ? cs.tertiary : cs.secondary),
        ),
      ),
      label: entry.name,
      searchQuery: widget.searchQuery,
    );
  }

  Widget _buildFileCell(BuildContext context, RawEntry entry, String fullPath) {
    final cleanName = entry.name;
    final isSelected = widget.selectedItems.contains(entry);
    final isPinned = widget.isPinned?.call(entry) ?? false;
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
    final isImg = MediaViewerConstants.isImage(cleanName);
    final isVid = MediaViewerConstants.isVideo(cleanName);
    Widget previewWidget;
    if (vaultIcon != null) {
      previewWidget = Center(
        child: Icon(vaultIcon, size: AppIconSize.feature, color: vaultColor),
      );
    } else if (isImg) {
      previewWidget = _EncryptedImageMasonryThumb(
        container: widget.container,
        filePath: fullPath,
        cacheMode: widget.thumbnailCacheMode,
        quality: widget.thumbnailQuality,
        onSizeKnown: (w, h) => _onSizeKnown(fullPath, w, h),
      );
    } else if (isVid) {
      previewWidget = _VideoMasonryThumb(
        container: widget.container,
        filePath: fullPath,
        cacheMode: widget.thumbnailCacheMode,
        quality: widget.thumbnailQuality,
        onSizeKnown: (w, h) => _onSizeKnown(fullPath, w, h),
      );
    } else {
      previewWidget = Center(
        child: Icon(
          iconForFile(cleanName),
          size: AppIconSize.feature,
          color: colorForFile(cleanName),
        ),
      );
    }
    return _MasonryCell(
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      showFileName: widget.showFileNames,
      isPinned: isPinned,
      onTap: () => widget.onFileTap(entry),
      onLongPress: () => widget.onItemLongPress(entry),
      onMoreTap:
          widget.isSelectionMode ? null : () => widget.onFileLongMenu?.call(entry),
      preview: previewWidget,
      label: displayName,
      searchQuery: widget.searchQuery,
    );
  }
}

class _MasonryCell extends StatelessWidget {
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

  const _MasonryCell({
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
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
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
            if (isPinned && !isSelected)
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: 14,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
            if (isSelected)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _CheckBadge(color: cs.primary, onColor: cs.onPrimary),
                ),
              ),
            if (showFileName)
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.65),
                      ],
                    ),
                  ),
                  child: HighlightedText(
                    text: label,
                    query: searchQuery,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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

class _EncryptedImageMasonryThumb extends StatelessWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final void Function(int width, int height) onSizeKnown;
  const _EncryptedImageMasonryThumb({
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
    if (MediaAspectRatioCache.get(container, path) == null) {
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        onSizeKnown(frame.image.width, frame.image.height);
        frame.image.dispose();
        codec.dispose();
      } catch (_) {}
    }
  }

  static Future<Uint8List> _fetch(
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
    void Function(int width, int height) onSizeKnown,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await ThumbnailCacheService.getWithSize(
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
          await _checkAndReportSizeFromBytes(container, path, bytes, onSizeKnown);
        }
        return bytes;
      }
    }
    final thumb = await vaultExplorerApi.getImageThumbnailWithSize(
      container,
      path,
      targetSize: quality.scaledSize(180),
      quality: quality.jpegQuality,
    );
    final thumbBytes = thumb?.bytes;
    if (thumbBytes == null || thumbBytes.isEmpty) {
      final size = await vaultExplorerApi.getFileSize(container, path);
      if (size <= 0) throw Exception('Empty file: $path');
      final raw = await vaultExplorerApi.readFileChunk(
        container,
        path,
        0,
        size,
      );
      if (raw == null || raw.isEmpty) throw Exception('Read failed: $path');
      if (raw.length < 200 * 1024) {
        ThumbnailCacheService.putInMemory(container, path, raw, quality);
        await _checkAndReportSizeFromBytes(container, path, raw, onSizeKnown);
      }
      return raw;
    }
    onSizeKnown(thumb!.width, thumb.height);
    ThumbnailCacheService.putInMemory(
      container, path, thumbBytes, quality, thumb.width, thumb.height,
    );
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        ThumbnailCacheService.put(
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final syncEntry = ThumbnailCacheService.getWithSizeFromMemory(container, filePath, quality);
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
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: ThumbnailConcurrency.imageLimiter,
      fetchFn: (c, p) => _fetch(c, p, cacheMode, quality, onSizeKnown),
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

class _VideoMasonryThumb extends StatelessWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final void Function(int width, int height) onSizeKnown;
  const _VideoMasonryThumb({
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
    if (MediaAspectRatioCache.get(container, path) == null) {
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        onSizeKnown(frame.image.width, frame.image.height);
        frame.image.dispose();
        codec.dispose();
      } catch (_) {}
    }
  }

  static Future<Uint8List> _fetch(
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
    void Function(int width, int height) onSizeKnown,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await ThumbnailCacheService.getWithSize(
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
          await _checkAndReportSizeFromBytes(container, path, bytes, onSizeKnown);
        }
        return bytes;
      }
    }
    final thumb = await vaultExplorerApi.getVideoThumbnailWithSize(
      container,
      path,
      quality: quality.jpegQuality,
      targetSize: quality.scaledSize(180),
    );
    final data = thumb?.bytes;
    if (data == null || data.isEmpty) return Uint8List(0);
    onSizeKnown(thumb!.width, thumb.height);
    ThumbnailCacheService.putInMemory(
      container, path, data, quality, thumb.width, thumb.height,
    );
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        ThumbnailCacheService.put(
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final syncEntry = ThumbnailCacheService.getWithSizeFromMemory(container, filePath, quality);
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
          cache: ThumbnailConcurrency.inFlightThumbnails,
          limiter: ThumbnailConcurrency.videoLimiter,
          fetchFn: (c, p) => _fetch(c, p, cacheMode, quality, onSizeKnown),
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
          alignment: Alignment.topRight,
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