import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/widgets/archive_thumbnail_support.dart';
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
  final bool isPinned;
  final bool isBookmark;

  /// Set when [entry] is being listed from inside an open archive (see
  /// `file_browser_screen.dart`'s `_archiveContext`) rather than the real
  /// container filesystem. When present, image thumbnails are sourced via
  /// on-demand archive extraction instead of the native container
  /// thumbnail API -- see `archive_thumbnail_support.dart`.
  final ArchiveContext? archiveContext;

  /// The container-relative path of the archive's own root, i.e. the
  /// [currentDirPath] value at the point the archive was opened. Required
  /// alongside [archiveContext] to resolve [entry]'s path back to a path
  /// relative to the archive root.
  final String? archiveRootPath;

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
    this.isPinned = false,
    this.isBookmark = false,
    this.archiveContext,
    this.archiveRootPath,
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
    if (!isSelectionMode && onLongMenu != null && !entry.isPlaceholder) {
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
    final fullPath = currentDirPath.isEmpty
        ? entry.name
        : '$currentDirPath/${entry.name}';
    final isImg = MediaViewerConstants.isImage(entry.name);
    final isVid = MediaViewerConstants.isVideo(entry.name);
    if (showThumbnail &&
        container != null &&
        vaultIcon == null &&
        !entry.isPlaceholder) {
      if (isImg) {
        customLeading = Hero(
          tag: 'media_hero_${container!.volId}_$fullPath',
          child: Material(
            type: MaterialType.transparency,
            child: _ListImageThumb(
              container: container!,
              filePath: fullPath,
              cacheMode: thumbnailCacheMode,
              quality: thumbnailQuality,
              fallbackIcon: displayIcon,
              fallbackColor: iconColor,
              zoomLevel: zoomLevel,
              archiveContext: archiveContext,
              archiveRootPath: archiveRootPath,
            ),
          ),
        );
      } else if (isVid && archiveContext == null) {
        // Video thumbnails inside an archive aren't supported -- unlike
        // images, generating one needs a real seekable data source for the
        // platform decoder, which an in-memory extracted entry isn't. Fall
        // through to the plain file-type icon rather than attempting (and
        // failing) a native video thumbnail against a path that was never
        // real to begin with.
        customLeading = Hero(
          tag: 'media_hero_${container!.volId}_$fullPath',
          child: Material(
            type: MaterialType.transparency,
            child: _ListVideoThumb(
              container: container!,
              filePath: fullPath,
              cacheMode: thumbnailCacheMode,
              quality: thumbnailQuality,
              fallbackIcon: displayIcon,
              fallbackColor: iconColor,
              zoomLevel: zoomLevel,
            ),
          ),
        );
      }
    }

    Widget? badge;
    if ((isPinned || isBookmark) && !isSelected) {
      badge = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: Row(
          mainAxisSize: dynamicSize(mainAxis: true),
          children: [
            if (isPinned)
              Icon(
                Icons.push_pin_rounded,
                size: 10 * zoomLevel,
                color: cs.onPrimaryContainer,
              ),
            if (isBookmark)
              Icon(
                Icons.star_rounded,
                size: 10 * zoomLevel,
                color: context.semanticColors.bookmark,
              ),
          ],
        ),
      );
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
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
      isCompact: isCompact,
      zoomLevel: zoomLevel,
      customLeading: customLeading,
      iconBadge: badge,
    );
  }

  MainAxisSize dynamicSize({required bool mainAxis}) =>
      mainAxis ? MainAxisSize.min : MainAxisSize.max;
}

class _ListImageThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final double zoomLevel;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;
  const _ListImageThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.fallbackIcon,
    required this.fallbackColor,
    this.zoomLevel = 1.0,
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
      // Sourced by extracting the entry rather than the native container
      // thumbnail API -- see archive_thumbnail_support.dart. Cached
      // in-memory only for the life of this browsing session: the archive
      // session is ephemeral, and unlike a real container path there's no
      // stable on-disk/in-container cache slot to persist these under.
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
    return AsyncThumbnail(
      key: ValueKey('list_img:$filePath'),
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
        archiveContext,
        archiveRootPath,
      ),
      debounce: const Duration(milliseconds: 100),
      syncLookup: () => thumbnailCache.peekMemory(container, filePath, quality),
      cacheHeight: quality.scaledSize(180),
      imageBuilder: (context, bytes, cacheHeight) => Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheHeight: cacheHeight,
        errorBuilder: (_, _, _) => _fallbackWidget(),
      ),
      loadingBuilder: (context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: SizedBox(
            width: 14 * zoomLevel,
            height: 14 * zoomLevel,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.6),
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

class _ListVideoThumb extends ConsumerWidget {
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
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
  ) => VideoThumbnailFetcher.fetch(
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
    return Stack(
      fit: StackFit.expand,
      children: [
        AsyncThumbnail(
          key: ValueKey('list_vid:$filePath'),
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
            width: double.infinity,
            height: double.infinity,
            cacheHeight: cacheHeight,
            errorBuilder: (_, _, _) => _fallbackWidget(),
          ),
          loadingBuilder: (context) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(
              child: SizedBox(
                width: 14 * zoomLevel,
                height: 14 * zoomLevel,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.6),
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