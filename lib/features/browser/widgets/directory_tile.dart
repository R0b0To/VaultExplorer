import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_thumbnail_preview.dart';
import 'package:vaultexplorer/features/browser/widgets/tile_selection_style.dart';

class DirectoryTile extends StatelessWidget {
  final RawEntry entry;
  final bool isSelectionMode;
  final bool isSelected;
  final String? searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isCompact;
  final double zoomLevel;
  final List<FileDetailColumn> detailColumns;
  final bool isDocumentProviderMounted;
  final bool isPinned;
  final bool isBookmark;

  /// When provided (together with [container]), the folder icon shows a
  /// collage of already-cached thumbnails from this folder's contents
  /// instead of the plain folder icon -- see [FolderThumbnailPreview].
  final MountedContainer? container;
  final String currentDirPath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;

  /// Mirrors whichever "show thumbnails" toggle the surrounding view (list/
  /// grid/masonry) already exposes for file thumbnails, so turning that off
  /// also turns off folder collages -- both are the same underlying
  /// preference from the person's point of view.
  final bool showThumbnailPreview;

  const DirectoryTile({
    super.key,
    required this.entry,
    required this.isSelectionMode,
    required this.isSelected,
    this.searchQuery,
    required this.onTap,
    required this.onLongPress,
    this.isCompact = false,
    this.zoomLevel = 1.0,
    this.detailColumns = const [FileDetailColumn.date, FileDetailColumn.size],
    this.isDocumentProviderMounted = false,
    this.isPinned = false,
    this.isBookmark = false,
    this.container,
    this.currentDirPath = '',
    this.cacheMode = ThumbnailCacheMode.appCache,
    this.quality = ThumbnailQuality.defaultQuality,
    this.showThumbnailPreview = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = isDocumentProviderMounted ? cs.tertiary : cs.secondary;
    final iconBackground = isDocumentProviderMounted
        ? cs.tertiaryContainer.withValues(alpha: 0.4)
        : cs.secondaryContainer.withValues(alpha: 0.4);


    final folderIconSize = (AppIconSize.action + 4) * zoomLevel;

    Widget? badge;
    if ((isPinned || isBookmark) && !isSelected) {
      badge = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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

     final showPreview = container != null &&
        !isSelected &&
        !entry.isPlaceholder &&
        showThumbnailPreview;

    Widget? customLeading;
    if (showPreview) {
      final folderPath =
          currentDirPath.isEmpty ? entry.name : '$currentDirPath/${entry.name}';
      customLeading = FolderThumbnailPreview(
        key: ValueKey('folder_preview:${container!.uri}:$folderPath'),
        container: container!,
        folderPath: folderPath,
        cacheMode: cacheMode,
        quality: quality,
        iconSize: folderIconSize,
        child: Icon(
          isDocumentProviderMounted
              ? Icons.folder_shared_rounded
              : Icons.folder_rounded,
          size: folderIconSize,
          color: iconColor,
        ),
      );
    }

    return FileRowShell(
      icon: isDocumentProviderMounted
          ? Icons.folder_shared_rounded
          : Icons.folder_rounded,
      iconColor: iconColor,
      unselectedIconBackground: iconBackground,
      customLeading: customLeading,
      displayName: entry.name,
      searchQuery: searchQuery,
      entry: entry,
      detailColumns: detailColumns,
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
      isCompact: isCompact,
      zoomLevel: zoomLevel,
      iconBadge: badge,
    );
  }
}