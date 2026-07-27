import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/widgets/tile_selection_style.dart';

class FileTile extends StatelessWidget {
  final RawEntry entry;
  final bool isSelectionMode;
  final bool isSelected;
  final String? searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<RawEntry>? onLongMenu;
  final bool isCompact;
  final double zoomLevel;
  final List<FileDetailColumn> detailColumns;
  final MountedContainer? container;
  final String currentDirPath;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;
  final bool showThumbnail;

  const FileTile({
    super.key,
    required this.entry,
    required this.isSelectionMode,
    required this.isSelected,
    this.searchQuery,
    required this.onTap,
    required this.onLongPress,
    this.onLongMenu,
    this.isCompact = false,
    this.zoomLevel = 1.0,
    this.detailColumns = const [FileDetailColumn.date, FileDetailColumn.size],
    this.container,
    this.currentDirPath = '',
    this.thumbnailCacheMode = ThumbnailCacheMode.appCache,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    this.showThumbnail = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String displayName = entry.name;
    final ext = displayName.split('.').last;
    final vaultIcon = vaultIconForExt(ext);
    final vaultColor = vaultColorForExt(ext);
    if (vaultIcon != null) {
      final parts = displayName.split('.');
      if (parts.length > 1) {
        parts.removeLast();
        displayName = parts.join('.');
      }
    }
    final displayIcon = vaultIcon ?? iconForFile(entry.name);
    final iconColor = vaultColor ?? colorForFile(entry.name);
    Widget? trailingWidget;
    if (isSelectionMode) {
      if (isSelected) {
        trailingWidget = const TileSelectionIndicator(selected: true);
      }
    } else if (onLongMenu != null) {
      trailingWidget = SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 20,
          color: cs.onSurfaceVariant,
          icon: const Icon(Icons.more_horiz_rounded),
          onPressed: () => onLongMenu!(entry),
        ),
      );
    }

    Widget? customLeading;
    final fullPath =
        currentDirPath.isEmpty ? entry.name : '$currentDirPath/${entry.name}';
    final isImg = MediaViewerConstants.isImage(entry.name);
    final isVid = MediaViewerConstants.isVideo(entry.name);

    if (showThumbnail && container != null && vaultIcon == null) {
      if (isImg) {
        customLeading = _ListImageThumb(
          container: container!,
          filePath: fullPath,
          cacheMode: thumbnailCacheMode,
          quality: thumbnailQuality,
          fallbackIcon: displayIcon,
          fallbackColor: iconColor,
          zoomLevel: zoomLevel,
        );
      } else if (isVid) {
        customLeading = _ListVideoThumb(
          container: container!,
          filePath: fullPath,
          cacheMode: thumbnailCacheMode,
          quality: thumbnailQuality,
          fallbackIcon: displayIcon,
          fallbackColor: iconColor,
          zoomLevel: zoomLevel,
        );
      }
    }

    return FileRowShell(
      icon: displayIcon,
      iconColor: iconColor,
      unselectedIconBackground: cs.surfaceContainerHighest,
      displayName: displayName,
      searchQuery: searchQuery,
      entry: entry,
      detailColumns: detailColumns,
      trailing: trailingWidget,
      isSelected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
      isCompact: isCompact,
      zoomLevel: zoomLevel,
      customLeading: customLeading,
    );
  }
}

class _ListImageThumb extends StatelessWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final double zoomLevel;

  const _ListImageThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.fallbackIcon,
    required this.fallbackColor,
    this.zoomLevel = 1.0,
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
    return AsyncThumbnail(
      key: ValueKey('list_img:$filePath'),
      container: container,
      filePath: filePath,
      cache: ThumbnailConcurrency.imageCache,
      limiter: ThumbnailConcurrency.imageLimiter,
      fetchFn: (c, p) => _fetch(c, p, cacheMode, quality),
      debounce: const Duration(milliseconds: 100),
      syncLookup: () =>
          ThumbnailCacheService.getFromMemory(container, filePath, quality),
      cacheHeight: quality.scaledSize(180),
      imageBuilder: (context, bytes, cacheHeight) => Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheHeight: cacheHeight,
        errorBuilder: (_, __, ___) => _fallbackWidget(),
      ),
      loadingBuilder: (context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: SizedBox(
            width: 14 * zoomLevel,
            height: 14 * zoomLevel,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
      errorBuilder: (context) => _fallbackWidget(),
    );
  }

  Widget _fallbackWidget() {
    return Center(
      child: Icon(
        fallbackIcon,
        size: AppIconSize.action * zoomLevel,
        color: fallbackColor,
      ),
    );
  }
}

class _ListVideoThumb extends StatelessWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final double zoomLevel;

  const _ListVideoThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.fallbackIcon,
    required this.fallbackColor,
    this.zoomLevel = 1.0,
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
    final data = await vaultExplorerApi.getVideoThumbnail(
      container,
      path,
      quality: quality.jpegQuality,
      targetSize: quality.scaledSize(180),
    );
    if (data == null || data.isEmpty) return Uint8List(0);
    ThumbnailCacheService.putInMemory(container, path, data, quality);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        ThumbnailCacheService.put(
          container: container,
          filePath: path,
          data: data,
          mode: mode,
          quality: quality,
        ),
      );
    }
    return data;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AsyncThumbnail(
          key: ValueKey('list_vid:$filePath'),
          container: container,
          filePath: filePath,
          cache: ThumbnailConcurrency.videoCache,
          limiter: ThumbnailConcurrency.videoLimiter,
          fetchFn: (c, p) => _fetch(c, p, cacheMode, quality),
          debounce: const Duration(milliseconds: 150),
          syncLookup: () =>
              ThumbnailCacheService.getFromMemory(container, filePath, quality),
          cacheHeight: quality.scaledSize(180),
          imageBuilder: (context, bytes, cacheHeight) => Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheHeight: cacheHeight,
            errorBuilder: (_, __, ___) => _fallbackWidget(),
          ),
          loadingBuilder: (context) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(
              child: SizedBox(
                width: 14 * zoomLevel,
                height: 14 * zoomLevel,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          errorBuilder: (context) => _fallbackWidget(),
        ),
        Positioned(
          right: 2,
          bottom: 2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: (12 * zoomLevel).clamp(10.0, 20.0),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallbackWidget() {
    return Center(
      child: Icon(
        fallbackIcon,
        size: AppIconSize.action * zoomLevel,
        color: fallbackColor,
      ),
    );
  }
}