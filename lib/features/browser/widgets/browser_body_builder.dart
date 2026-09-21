import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_empty_state.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
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
  required bool Function(RawEntry entry) isBookmark,
  bool Function(RawEntry entry)? isFolderSynced,
  required void Function(RawEntry entry) onDirTap,
  required void Function(RawEntry entry) onFileTap,
  required void Function(RawEntry entry) onItemLongPress,
  void Function(RawEntry entry)? onIconTap,
  void Function(RawEntry entry)? onItemMoreTap,
  required void Function(int count) onGridColumnCountChanged,
  required void Function(int count) onMasonryColumnCountChanged,
  required void Function(double newZoom) onListZoomLevelChanged,
  required Future<void> Function() onRefresh,
  required bool isListingTruncated,
  ValueChanged<Set<RawEntry>>? onSelectionChanged,
  ScrollController? scrollController,
  ArchiveContext? archiveContext,
  String? archiveRootPath,
  SortBy? sortBy,
}) {
  if (isLoading && currentItems.isEmpty) {
    return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
  }
  if (items.isEmpty) {
    if (searchQuery.trim().isNotEmpty) {
      return _refreshableEmptyState(
        onRefresh: onRefresh,
        child: AppEmptyState(
          icon: Icons.search_off_rounded,
          title: context.l10n.noResultsTitle,
          message: context.l10n.noResultsForQueryMessage(searchQuery.trim()),
        ),
      );
    }
    return _refreshableEmptyState(
      onRefresh: onRefresh,
      child: AppEmptyState(
        icon: Icons.folder_open_rounded,
        title: context.l10n.emptyFolderTitle,
        message: context.l10n.emptyFolderMessage,
        actionLabel: atRoot ? null : context.l10n.goBack,
        actionIcon: Icons.arrow_upward_rounded,
        onAction: onNavigateUp,
      ),
    );
  }
  if (searchQuery.trim().isNotEmpty && items.isEmpty) {
    return _refreshableEmptyState(
      onRefresh: onRefresh,
      child: AppEmptyState(
        icon: Icons.search_off_rounded,
        title: context.l10n.noResultsTitle,
        message: context.l10n.noResultsForQueryMessage(searchQuery.trim()),
      ),
    );
  }
  final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
  final content = switch (layoutMode) {
    BrowserLayoutMode.grid => FileGridView(
        scrollController: scrollController,
        container: container,
        items: items,
        isSelectionMode: isSelectionMode,
        selectedItems: selectedItems,
        currentDirPath: currentDirPath,
        thumbnailCacheMode: thumbnailCacheMode,
        thumbnailQuality: thumbnailQuality,
        showFileNames: toolbarConfig.showGridFileNames,
        longFileNameMode: toolbarConfig.longFileNameDisplayMode,
        gridAspectRatio: toolbarConfig.getGridAspectRatioForFolder(
          container.uri,
          currentDirPath,
        ),
        initialColumns: isLandscape
            ? toolbarConfig.gridColumnsLandscape
            : toolbarConfig.gridColumnsPortrait,
        onColumnCountChanged: onGridColumnCountChanged,
        onDirTap: onDirTap,
        onFileTap: onFileTap,
        onItemLongPress: onItemLongPress,
        onSelectionChanged: onSelectionChanged,
        searchQuery: searchActive ? searchQuery.trim().toLowerCase() : null,
        mountedFolderPaths: mountedDocProviderFolders,
        isPinned: isPinned,
        isBookmark: isBookmark,
        isFolderSynced: isFolderSynced,
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
        sortBy: sortBy,
      ),
    BrowserLayoutMode.masonry => FileMasonryView(
        scrollController: scrollController,
        container: container,
        items: items,
        isSelectionMode: isSelectionMode,
        selectedItems: selectedItems,
        currentDirPath: currentDirPath,
        thumbnailCacheMode: thumbnailCacheMode,
        thumbnailQuality: thumbnailQuality,
        showFileNames: toolbarConfig.showGridFileNames,
        longFileNameMode: toolbarConfig.longFileNameDisplayMode,
        initialColumns: isLandscape
            ? toolbarConfig.masonryColumnsLandscape
            : toolbarConfig.masonryColumnsPortrait,
        onColumnCountChanged: onMasonryColumnCountChanged,
        onDirTap: onDirTap,
        onFileTap: onFileTap,
        onItemLongPress: onItemLongPress,
        onSelectionChanged: onSelectionChanged,
        searchQuery: searchActive ? searchQuery.trim().toLowerCase() : null,
        mountedFolderPaths: mountedDocProviderFolders,
        isPinned: isPinned,
        isBookmark: isBookmark,
        isFolderSynced: isFolderSynced,
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
        sortBy: sortBy,
      ),
    BrowserLayoutMode.list ||
    BrowserLayoutMode.detailed ||
    BrowserLayoutMode.compact =>
      FileListView(
        scrollController: scrollController,
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
        isDetailed: layoutMode == BrowserLayoutMode.detailed,
        selectedItems: selectedItems,
        detailColumns: toolbarConfig.visibleDetailColumns,
        longFileNameMode: toolbarConfig.longFileNameDisplayMode,
        showItemActionsMenu: toolbarConfig.showItemActionsMenu,
        onDirTap: onDirTap,
        onFileTap: onFileTap,
        onItemLongPress: onItemLongPress,
        onFileLongMenu: onItemMoreTap,
        onIconTap: onIconTap,
        onSelectionChanged: onSelectionChanged,
        searchQuery: searchActive ? searchQuery.trim().toLowerCase() : null,
        isFolderMounted: isFolderMounted,
        isPinned: isPinned,
        isBookmark: isBookmark,
        isFolderSynced: isFolderSynced,
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
        sortBy: sortBy,
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

Widget _refreshableEmptyState({
  required Widget child,
  required Future<void> Function() onRefresh,
}) {
  return RefreshIndicator(
    onRefresh: onRefresh,
    child: LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: child,
            ),
          ],
        );
      },
    ),
  );
}