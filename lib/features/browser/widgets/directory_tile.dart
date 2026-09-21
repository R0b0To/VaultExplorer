import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
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

  /// Tapping the leading icon toggles this entry's selection instead of
  /// opening it. See `FileRowShell.onIconTap`.
  final VoidCallback? onIconTap;
  final ValueChanged<RawEntry>? onMoreTap;
  final bool showItemActionsMenu;
  final bool isCompact;

  /// Two-row layout -- see `FileListView.isDetailed`.
  final bool isDetailed;
  final double zoomLevel;
  final List<FileDetailColumn> detailColumns;
  final LongFileNameDisplayMode longFileNameMode;
  final bool isDocumentProviderMounted;
  final bool isPinned;
  final bool isBookmark;
  final bool isSynced;

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
    this.onIconTap,
    this.onMoreTap,
    this.showItemActionsMenu = true,
    this.isCompact = false,
    this.isDetailed = false,
    this.zoomLevel = 1.0,
    this.detailColumns = const [FileDetailColumn.date, FileDetailColumn.size],
    this.longFileNameMode = LongFileNameDisplayMode.ellipsizeEnd,
    this.isDocumentProviderMounted = false,
    this.isPinned = false,
    this.isBookmark = false,
    this.isSynced = false,
    this.container,
    this.currentDirPath = '',
    this.cacheMode = ThumbnailCacheMode.appCache,
    this.quality = ThumbnailQuality.defaultQuality,
    this.showThumbnailPreview = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = cs.secondary;
    final iconBackground = cs.secondaryContainer.withValues(alpha: 0.4);

    final folderIconSize = (AppIconSize.action + 4) * zoomLevel;

    Widget? badge;
    if ((isPinned || isBookmark || isDocumentProviderMounted || isSynced) && !isSelected) {
      badge = Container(
        padding: EdgeInsets.symmetric(horizontal: 3 * zoomLevel, vertical: 1.5 * zoomLevel),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPinned)
              Icon(
                Icons.push_pin_rounded,
                size: 10 * zoomLevel,
                color: cs.primary,
              ),
            if (isBookmark) ...[
              if (isPinned) SizedBox(width: 2 * zoomLevel),
              Icon(
                Icons.star_rounded,
                size: 10 * zoomLevel,
                color: context.semanticColors.bookmark,
              ),
            ],
            if (isDocumentProviderMounted) ...[
              if (isPinned || isBookmark) SizedBox(width: 2 * zoomLevel),
              Icon(
                Icons.folder_shared_rounded,
                size: 10 * zoomLevel,
                color: cs.tertiary,
              ),
            ],
            if (isSynced) ...[
              if (isPinned || isBookmark || isDocumentProviderMounted) SizedBox(width: 2 * zoomLevel),
              Icon(
                Icons.sync_rounded,
                size: 10 * zoomLevel,
                color: cs.primary,
              ),
            ],
          ],
        ),
      );
    }

     final showPreview = container != null &&
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
          Icons.folder_rounded,
          size: folderIconSize,
          color: iconColor,
        ),
      );
    }

    Widget? trailingWidget;
    if (!isSelectionMode && showItemActionsMenu && !entry.isPlaceholder) {
      trailingWidget = SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 20,
          color: cs.onSurfaceVariant,
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: onMoreTap == null ? null : () => onMoreTap!(entry),
        ),
      );
    }

    return FileRowShell(
      icon: Icons.folder_rounded,
      iconColor: iconColor,
      unselectedIconBackground: iconBackground,
      customLeading: customLeading,
      displayName: entry.name,
      searchQuery: searchQuery,
      entry: entry,
      detailColumns: detailColumns,
      longFileNameMode: longFileNameMode,
      trailing: trailingWidget,
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress,
      onIconTap: onIconTap,
      isCompact: isCompact,
      isDetailed: isDetailed,
      zoomLevel: zoomLevel,
      iconBadge: badge,
    );
  }
}