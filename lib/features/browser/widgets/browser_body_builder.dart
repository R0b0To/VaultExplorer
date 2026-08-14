import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_empty_state.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/widgets/file_grid_view.dart';
import 'package:vaultexplorer/features/browser/widgets/file_list_view.dart';
import 'package:vaultexplorer/features/browser/widgets/file_masonry_view.dart';
import 'package:vaultexplorer/features/browser/widgets/truncated_banner.dart';

Widget buildBrowserBody(
  BuildContext context,
  List<RawEntry> items, {
  required bool isLoading,
  required List<RawEntry> currentItems,
  required bool atRoot,
  required VoidCallback? onNavigateUp,
  required String searchQuery,
  required BrowserLayoutMode layoutMode,
  required MountedContainer container,
  required String currentDirPath,
  required ThumbnailCacheMode thumbnailCacheMode,
  required ThumbnailQuality thumbnailQuality,
  required FileManagerToolbarConfig toolbarConfig,
  required bool isSelectionMode,
  required Set<RawEntry> selectedItems,
  required bool searchActive,
  required Set<String> mountedDocProviderFolders,
  required bool Function(RawEntry entry) isFolderMounted,
  required bool Function(RawEntry entry) isPinned,
  required bool Function(RawEntry entry) isFavourite,
  required void Function(RawEntry entry) onDirTap,
  required void Function(RawEntry entry) onFileTap,
  required void Function(RawEntry entry) onItemLongPress,
  required void Function(int count) onGridColumnCountChanged,
  required void Function(int count) onMasonryColumnCountChanged,
  required void Function(double newZoom) onListZoomLevelChanged,
  required Future<void> Function() onRefresh,
  required bool isListingTruncated,
}) {
  if (isLoading && currentItems.isEmpty) {
    return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
  }
  if (currentItems.isEmpty) {
    return AppEmptyState(
      icon: Icons.folder_open_rounded,
      title: context.l10n.emptyFolderTitle,
      message: context.l10n.emptyFolderMessage,
      actionLabel: atRoot ? null : context.l10n.goBack,
      actionIcon: Icons.arrow_upward_rounded,
      onAction: onNavigateUp,
    );
  }
  if (searchQuery.trim().isNotEmpty && items.isEmpty) {
    return AppEmptyState(
      icon: Icons.search_off_rounded,
      title: context.l10n.noResultsTitle,
      message: context.l10n.noResultsForQueryMessage(searchQuery.trim()),
    );
  }
  final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
  final content = switch (layoutMode) {
    BrowserLayoutMode.grid => FileGridView(
        container: container,
        items: items,
        isSelectionMode: isSelectionMode,
        selectedItems: selectedItems,
        currentDirPath: currentDirPath,
        thumbnailCacheMode: thumbnailCacheMode,
        thumbnailQuality: thumbnailQuality,
        showFileNames: toolbarConfig.showGridFileNames,
        initialColumns: isLandscape
            ? toolbarConfig.gridColumnsLandscape
            : toolbarConfig.gridColumnsPortrait,
        onColumnCountChanged: onGridColumnCountChanged,
        onDirTap: onDirTap,
        onFileTap: onFileTap,
        onItemLongPress: onItemLongPress,
        searchQuery: searchActive ? searchQuery.trim().toLowerCase() : null,
        mountedFolderPaths: mountedDocProviderFolders,
        isPinned: isPinned,
        isFavourite: isFavourite,
      ),
    BrowserLayoutMode.masonry => FileMasonryView(
        container: container,
        items: items,
        isSelectionMode: isSelectionMode,
        selectedItems: selectedItems,
        currentDirPath: currentDirPath,
        thumbnailCacheMode: thumbnailCacheMode,
        thumbnailQuality: thumbnailQuality,
        showFileNames: toolbarConfig.showGridFileNames,
        initialColumns: isLandscape
            ? toolbarConfig.masonryColumnsLandscape
            : toolbarConfig.masonryColumnsPortrait,
        onColumnCountChanged: onMasonryColumnCountChanged,
        onDirTap: onDirTap,
        onFileTap: onFileTap,
        onItemLongPress: onItemLongPress,
        searchQuery: searchActive ? searchQuery.trim().toLowerCase() : null,
        mountedFolderPaths: mountedDocProviderFolders,
        isPinned: isPinned,
        isFavourite: isFavourite,
      ),
    BrowserLayoutMode.list ||
    BrowserLayoutMode.compact =>
      FileListView(
        container: container,
        currentDirPath: currentDirPath,
        thumbnailCacheMode: thumbnailCacheMode,
        thumbnailQuality: thumbnailQuality,
        showThumbnails: toolbarConfig.showListThumbnails,
        initialZoomLevel: toolbarConfig.listZoomLevel,
        onZoomLevelChanged: onListZoomLevelChanged,
        items: items,
        isSelectionMode: isSelectionMode,
        isCompact: layoutMode == BrowserLayoutMode.compact,
        selectedItems: selectedItems,
        detailColumns: toolbarConfig.visibleDetailColumns,
        onDirTap: onDirTap,
        onFileTap: onFileTap,
        onItemLongPress: onItemLongPress,
        searchQuery: searchActive ? searchQuery.trim().toLowerCase() : null,
        isFolderMounted: isFolderMounted,
        isPinned: isPinned,
        isFavourite: isFavourite,
      ),
  };
  final refreshable = RefreshIndicator(
    onRefresh: onRefresh,
    child: content,
  );
  if (!isListingTruncated) return refreshable;
  return Column(
    children: [
      const TruncatedBanner(),
      Expanded(child: refreshable),
    ],
  );
}