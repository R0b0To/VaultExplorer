import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/thumbnail_concurrency.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/widgets/archive_thumbnail_support.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_thumbnail_preview.dart';

class FileItemActionsSheet extends ConsumerWidget {
  final RawEntry entry;
  final MountedContainer container;
  final String currentDirPath;
  final bool isReadOnly;
  final bool isPinned;
  final bool isBookmark;
  final bool isDocumentProviderMounted;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;
  final Widget? customLeading;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleBookmark;
  final VoidCallback onInfo;
  final VoidCallback? onOpenWith;
  final VoidCallback? onShare;
  final VoidCallback? onEditImage;
  final VoidCallback? onToggleDocProvider;

  const FileItemActionsSheet({
    super.key,
    required this.entry,
    required this.container,
    required this.currentDirPath,
    required this.isReadOnly,
    required this.isPinned,
    required this.isBookmark,
    this.isDocumentProviderMounted = false,
    this.thumbnailCacheMode = ThumbnailCacheMode.appCache,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    this.archiveContext,
    this.archiveRootPath,
    this.customLeading,
    required this.onRename,
    required this.onDelete,
    required this.onCopy,
    required this.onCut,
    required this.onTogglePin,
    required this.onToggleBookmark,
    required this.onInfo,
    this.onOpenWith,
    this.onShare,
    this.onEditImage,
    this.onToggleDocProvider,
  });

  static Future<void> show(
    BuildContext context, {
    required RawEntry entry,
    required MountedContainer container,
    required String currentDirPath,
    required bool isReadOnly,
    required bool isPinned,
    required bool isBookmark,
    bool isDocumentProviderMounted = false,
    ThumbnailCacheMode thumbnailCacheMode = ThumbnailCacheMode.appCache,
    ThumbnailQuality thumbnailQuality = ThumbnailQuality.defaultQuality,
    ArchiveContext? archiveContext,
    String? archiveRootPath,
    Widget? customLeading,
    required VoidCallback onRename,
    required VoidCallback onDelete,
    required VoidCallback onCopy,
    required VoidCallback onCut,
    required VoidCallback onTogglePin,
    required VoidCallback onToggleBookmark,
    required VoidCallback onInfo,
    VoidCallback? onOpenWith,
    VoidCallback? onShare,
    VoidCallback? onEditImage,
    VoidCallback? onToggleDocProvider,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => FileItemActionsSheet(
        entry: entry,
        container: container,
        currentDirPath: currentDirPath,
        isReadOnly: isReadOnly,
        isPinned: isPinned,
        isBookmark: isBookmark,
        isDocumentProviderMounted: isDocumentProviderMounted,
        thumbnailCacheMode: thumbnailCacheMode,
        thumbnailQuality: thumbnailQuality,
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
        customLeading: customLeading,
        onRename: onRename,
        onDelete: onDelete,
        onCopy: onCopy,
        onCut: onCut,
        onTogglePin: onTogglePin,
        onToggleBookmark: onToggleBookmark,
        onInfo: onInfo,
        onOpenWith: onOpenWith,
        onShare: onShare,
        onEditImage: onEditImage,
        onToggleDocProvider: onToggleDocProvider,
      ),
    );
  }

  Widget _buildLeading(
    BuildContext context,
    WidgetRef ref,
    ColorScheme cs,
    IconData fallbackIcon,
    Color fallbackIconColor,
  ) {
    if (customLeading != null) return customLeading!;

    final cleanName = entry.name;
    final fullPath = currentDirPath.isEmpty ? cleanName : '$currentDirPath/$cleanName';
    final ext = cleanName.contains('.') ? cleanName.split('.').last.toLowerCase() : '';
    final vaultIcon = vaultIconForExt(ext);
    final vaultColor = vaultColorForExt(ext);

    if (entry.isDir) {
      return FolderThumbnailPreview(
        container: container,
        folderPath: fullPath,
        cacheMode: thumbnailCacheMode,
        quality: thumbnailQuality,
        iconSize: 24,
        child: Center(
          child: Icon(fallbackIcon, color: fallbackIconColor, size: 24),
        ),
      );
    }

    if (vaultIcon != null) {
      return Center(
        child: Icon(vaultIcon, color: vaultColor, size: 24),
      );
    }

    final isImg = MediaViewerConstants.isImage(cleanName) && !entry.isPlaceholder;
    final isVid = MediaViewerConstants.isVideo(cleanName) && !entry.isPlaceholder;

    if (isImg) {
      return _ItemImageThumbnail(
        container: container,
        filePath: fullPath,
        cacheMode: thumbnailCacheMode,
        quality: thumbnailQuality,
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
        fallbackIcon: fallbackIcon,
        fallbackIconColor: fallbackIconColor,
      );
    }

    if (isVid && archiveContext == null) {
      return _ItemVideoThumbnail(
        container: container,
        filePath: fullPath,
        cacheMode: thumbnailCacheMode,
        quality: thumbnailQuality,
        fallbackIcon: fallbackIcon,
        fallbackIconColor: fallbackIconColor,
      );
    }

    return Center(
      child: Icon(fallbackIcon, color: fallbackIconColor, size: 24),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final isDir = entry.isDir;
    final ext = isDir ? '' : (entry.name.contains('.') ? entry.name.split('.').last : '');
    final icon = isDir
        ? (isDocumentProviderMounted ? Icons.folder_shared_rounded : Icons.folder_rounded)
        : (vaultIconForExt(ext) ?? iconForFile(entry.name));
    final iconColor = isDir
        ? (isDocumentProviderMounted ? cs.tertiary : cs.secondary)
        : (vaultColorForExt(ext) ?? colorForFile(entry.name));

    final subtitleParts = <String>[
      if (!isDir) formatBytes(entry.sizeBytes),
      if (entry.modifiedSecs > 0) formatEntryDate(entry.modifiedSecs),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Thumbnail/Icon + Filename + Meta
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox.expand(
                      child: _buildLeading(context, ref, cs, icon, iconColor),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (subtitleParts.isNotEmpty)
                          Text(
                            subtitleParts.join('    '),
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),

            // Actions list
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Group 1: Consumption & Sharing
                    if (onOpenWith != null)
                      _ActionTile(
                        icon: Icons.open_in_new_rounded,
                        label: context.l10n.openWithAppAction,
                        onTap: () {
                          Navigator.pop(context);
                          onOpenWith!();
                        },
                      ),
                    if (onShare != null)
                      _ActionTile(
                        icon: Icons.share_rounded,
                        label: context.l10n.shareAction,
                        onTap: () {
                          Navigator.pop(context);
                          onShare!();
                        },
                      ),
                    if (onEditImage != null)
                      _ActionTile(
                        icon: Icons.edit_outlined,
                        label: context.l10n.editImageAction,
                        enabled: !isReadOnly,
                        onTap: () {
                          Navigator.pop(context);
                          onEditImage!();
                        },
                      ),
                    if (onOpenWith != null || onShare != null || onEditImage != null)
                      const SizedBox(height: 8),

                    // Group 2: Core File Operations
                    _ActionTile(
                      icon: Icons.drive_file_rename_outline_rounded,
                      label: context.l10n.renameAction,
                      enabled: !isReadOnly,
                      onTap: () {
                        Navigator.pop(context);
                        onRename();
                      },
                    ),
                    _ActionTile(
                      icon: Icons.copy_rounded,
                      label: context.l10n.copyAction,
                      onTap: () {
                        Navigator.pop(context);
                        onCopy();
                      },
                    ),
                    _ActionTile(
                      icon: Icons.cut_rounded,
                      label: context.l10n.moveAction,
                      enabled: !isReadOnly,
                      onTap: () {
                        Navigator.pop(context);
                        onCut();
                      },
                    ),
                    const SizedBox(height: 8),

                    // Group 3: Shortcuts & Integrations
                    _ActionTile(
                      icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                      label: isPinned ? context.l10n.unpinAction : context.l10n.pinAction,
                      onTap: () {
                        Navigator.pop(context);
                        onTogglePin();
                      },
                    ),
                    _ActionTile(
                      icon: isBookmark ? Icons.star_outline_rounded : Icons.star_rounded,
                      label: isBookmark ? context.l10n.unbookmarkAction : context.l10n.bookmarkAction,
                      onTap: () {
                        Navigator.pop(context);
                        onToggleBookmark();
                      },
                    ),
                    if (onToggleDocProvider != null)
                      _ActionTile(
                        icon: isDocumentProviderMounted
                            ? Icons.folder_shared_rounded
                            : Icons.folder_shared_outlined,
                        label: isDocumentProviderMounted
                            ? context.l10n.documentProviderSettingsMenu
                            : context.l10n.exposeAsDocumentProviderMenu,
                        onTap: () {
                          Navigator.pop(context);
                          onToggleDocProvider!();
                        },
                      ),
                    const SizedBox(height: 10),

                    // Group 4: Destructive Action (Safely isolated in a soft tinted container)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      child: Material(
                        color: cs.errorContainer.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: _ActionTile(
                          icon: Icons.delete_outline_rounded,
                          label: context.l10n.delete,
                          color: cs.error,
                          enabled: !isReadOnly,
                          onTap: () {
                            Navigator.pop(context);
                            onDelete();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Group 5: Properties / Info (The calm anchor at the very bottom)
                    _ActionTile(
                      icon: Icons.info_outline_rounded,
                      label: context.l10n.fileInfoAction,
                      onTap: () {
                        Navigator.pop(context);
                        onInfo();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemImageThumbnail extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;
  final IconData fallbackIcon;
  final Color fallbackIconColor;

  const _ItemImageThumbnail({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    this.archiveContext,
    this.archiveRootPath,
    required this.fallbackIcon,
    required this.fallbackIconColor,
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
    final thumbBytes = await fileIoApi.getImageThumbnail(
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
      key: ValueKey('sheet_img:$filePath'),
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
      debounce: const Duration(milliseconds: 50),
      syncLookup: () => thumbnailCache.peekMemory(container, filePath, quality),
      cacheHeight: quality.scaledSize(180),
      imageBuilder: (context, bytes, cacheHeight) => Image.memory(
        bytes,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        cacheHeight: cacheHeight,
        errorBuilder: (_, _, _) => Center(
          child: Icon(fallbackIcon, color: fallbackIconColor, size: 24),
        ),
      ),
      loadingBuilder: (context) => Container(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: cs.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
      errorBuilder: (context) => Icon(fallbackIcon, color: fallbackIconColor, size: 24),
    );
  }
}

class _ItemVideoThumbnail extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final IconData fallbackIcon;
  final Color fallbackIconColor;

  const _ItemVideoThumbnail({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.fallbackIcon,
    required this.fallbackIconColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final cs = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        AsyncThumbnail(
          key: ValueKey('sheet_vid:$filePath'),
          container: container,
          filePath: filePath,
          quality: quality,
          cache: ThumbnailConcurrency.inFlightThumbnails,
          limiter: ThumbnailConcurrency.videoLimiter,
          fetchFn: (c, p) => VideoThumbnailFetcher.fetch(
            thumbnailCache,
            fileIoApi,
            c,
            p,
            mode: cacheMode,
            quality: quality,
            targetSize: quality.scaledSize(180),
          ),
          debounce: const Duration(milliseconds: 50),
          syncLookup: () => thumbnailCache.peekMemory(container, filePath, quality),
          cacheHeight: quality.scaledSize(180),
          imageBuilder: (context, bytes, cacheHeight) => Image.memory(
            bytes,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            cacheHeight: cacheHeight,
            errorBuilder: (_, _, _) => Center(
              child: Icon(fallbackIcon, color: fallbackIconColor, size: 24),
            ),
          ),
          loadingBuilder: (context) => Container(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: cs.primary.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          errorBuilder: (context) => Icon(fallbackIcon, color: fallbackIconColor, size: 24),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(3.0),
            child: Icon(
              Icons.play_circle_outline_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool enabled;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = enabled
        ? (color ?? cs.onSurface)
        : cs.onSurfaceVariant.withValues(alpha: 0.38);

    return ListTile(
      dense: true,
      leading: Icon(icon, color: effectiveColor, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: effectiveColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}