import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

class FileManagerToolbarSettingsScreen extends ConsumerWidget {
  final String? containerUri;
  const FileManagerToolbarSettingsScreen({super.key, this.containerUri});

  static bool _isFolder(String path) {
    final leaf = path.split('/').last;
    return !leaf.contains('.') || path.endsWith('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileManagerToolbarSettingsProvider(containerUri));
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.fileManagerSettingsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: context.l10n.resetToDefaultsTooltip,
            onPressed: () => ref
                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                .resetToDefaults(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    children: [
                      // ==========================================
                      // 1. GENERAL BROWSER LAYOUT & BARS
                      // ==========================================
                      SectionHeader(context.l10n.browserLayoutSectionHeader),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.rememberPerFolderLayout,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setRememberPerFolderLayout(v),
                            title: Text(
                              context.l10n.rememberPerFolderLayoutLabel,
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.rememberPerFolderLayoutDesc,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(
                              Icons.folder_special_outlined,
                              color: cs.primary,
                            ),
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showHiddenFiles,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowHiddenFiles(v),
                            title: Text(
                              context.l10n.showHiddenFilesLabel,
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showHiddenFilesDesc,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(
                              Icons.visibility_outlined,
                              color: cs.primary,
                            ),
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showBreadcrumbBar,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowBreadcrumbBar(v),
                            title: Text(
                              context.l10n.showBreadcrumbBarLabel,
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showBreadcrumbBarDesc,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(
                              Icons.linear_scale_rounded,
                              color: cs.primary,
                            ),
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showStatsBar,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowStatsBar(v),
                            title: Text(
                              context.l10n.showStatsBarLabel,
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showStatsBarDesc,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(
                              Icons.analytics_outlined,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ==========================================
                      // 2. TOOLBAR ACTIONS
                      // ==========================================
                      SectionHeader(context.l10n.toolbarLayoutSectionHeader),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: state.config.order.length,
                        onReorder: (oldIndex, newIndex) => ref
                            .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                            .reorderActions(oldIndex, newIndex),
                        itemBuilder: (context, i) {
                          final action = state.config.order[i];
                          final visible = !state.config.hidden.contains(action);
                          return Padding(
                            key: ValueKey(action),
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Material(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(i == 0 ? 20 : 4),
                                bottom: Radius.circular(
                                    i == state.config.order.length - 1 ? 20 : 4),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 2,
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: visible
                                        ? cs.primaryContainer.withValues(alpha: 0.5)
                                        : cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    action.icon,
                                    size: 20,
                                    color: visible
                                        ? cs.primary
                                        : cs.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                  ),
                                ),
                                title: Text(
                                  action.getLocalizedLabel(context.l10n),
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: visible
                                        ? cs.onSurface
                                        : cs.onSurfaceVariant
                                            .withValues(alpha: 0.6),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: visible,
                                      onChanged: (v) => ref
                                          .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                          .toggleActionVisible(action, v),
                                    ),
                                    const SizedBox(width: 4),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest
                                              .withValues(alpha: 0.5),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.drag_handle_rounded,
                                          color: cs.onSurfaceVariant,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // ==========================================
                      // 3. BOOKMARKS
                      // ==========================================
                      SectionHeader(context.l10n.bookmarkBarSectionHeader),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showBookmarkBar,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowBookmarkBar(v),
                            title: Text(
                              context.l10n.showBookmarkBarLabel,
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showBookmarkBarDesc,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(
                              Icons.star_rounded,
                              color: cs.secondary,
                            ),
                          ),
                        ],
                      ),
                      if (state.record != null) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.reorderBookmarksTitle,
                                style: textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.l10n.reorderBookmarksDesc,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        if (state.record!.bookmarkPaths.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 8,
                              bottom: 24,
                              left: 4,
                            ),
                            child: Text(
                              context.l10n.noBookmarksYet,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: state.record!.bookmarkPaths.length,
                            onReorder: (oldIndex, newIndex) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .reorderBookmarks(oldIndex, newIndex),
                            itemBuilder: (context, i) {
                              final path = state.record!.bookmarkPaths[i];
                              final name = path.split('/').last;
                              final isDir = _isFolder(path);
                              final ext =
                                  name.contains('.') ? name.split('.').last : '';
                              final icon = isDir
                                  ? Icons.folder_rounded
                                  : (vaultIconForExt(ext) ?? iconForFile(name));
                              final iconColor = isDir
                                  ? cs.secondary
                                  : (vaultColorForExt(ext) ??
                                      colorForFile(name));
                              return Padding(
                                key: ValueKey(path),
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Material(
                                  color: cs.surfaceContainerHigh,
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(i == 0 ? 20 : 4),
                                    bottom: Radius.circular(
                                      i == state.record!.bookmarkPaths.length - 1
                                          ? 20
                                          : 4,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 2,
                                    ),
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: cs.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child:
                                          Icon(icon, size: 20, color: iconColor),
                                    ),
                                    title: Text(
                                      name,
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.close_rounded,
                                            size: 20,
                                            color: cs.error,
                                          ),
                                          onPressed: () => ref
                                              .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                              .removeBookmark(path),
                                          tooltip: context.l10n.unbookmarkAction,
                                        ),
                                        const SizedBox(width: 4),
                                        ReorderableDragStartListener(
                                          index: i,
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: cs.surfaceContainerHighest
                                                  .withValues(alpha: 0.5),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              Icons.drag_handle_rounded,
                                              color: cs.onSurfaceVariant,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                      const SizedBox(height: 16),

                      // ==========================================
                      // 4. VIEW MODES & CONTENT PRESENTATION
                      // ==========================================
                      // 4a. List View
                      SectionHeader(context.l10n.listViewOptionsSectionHeader),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showListThumbnails,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowListThumbnails(v),
                            title: Text(
                              context.l10n.showMediaThumbnailsLabel,
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showMediaThumbnailsDesc,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(
                              Icons.image_outlined,
                              color: cs.primary,
                            ),
                          ),
                          OptionPickerTile<ThumbnailCacheMode>(
                            label: context.l10n.thumbnailCachingDefaultLabel,
                            value: state.config.defaultThumbnailCacheMode,
                            options: ThumbnailCacheMode.values.map((mode) {
                              return SelectOption(
                                value: mode,
                                label: mode.getLocalizedLabel(context.l10n),
                                subtitle: mode.getLocalizedDescription(
                                  context.l10n,
                                ),
                              );
                            }).toList(),
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setDefaultThumbnailCacheMode(v),
                          ),
                          ThumbnailQualityTile(
                            label: context.l10n.thumbnailQualityDefaultLabel,
                            value: state.config.defaultThumbnailQuality,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setDefaultThumbnailQuality(v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 4b. Detailed List View Columns
                      SectionHeader(
                          context.l10n.detailedListViewColumnsSectionHeader),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: state.config.detailColumnsOrder.length,
                        onReorder: (oldIndex, newIndex) => ref
                            .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                            .reorderDetailColumns(oldIndex, newIndex),
                        itemBuilder: (context, i) {
                          final col = state.config.detailColumnsOrder[i];
                          final visible =
                              !state.config.hiddenDetailColumns.contains(col);
                          return Padding(
                            key: ValueKey(col),
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Material(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(i == 0 ? 20 : 4),
                                bottom: Radius.circular(
                                    i == state.config.detailColumnsOrder.length - 1
                                        ? 20
                                        : 4),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 2,
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: visible
                                        ? cs.primaryContainer.withValues(alpha: 0.5)
                                        : cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    col.icon,
                                    size: 20,
                                    color: visible
                                        ? cs.primary
                                        : cs.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                  ),
                                ),
                                title: Text(
                                  col.getLocalizedLabel(context.l10n),
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: visible
                                        ? cs.onSurface
                                        : cs.onSurfaceVariant
                                            .withValues(alpha: 0.6),
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: visible,
                                      onChanged: (v) => ref
                                          .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                          .toggleDetailColumnVisible(col, v),
                                    ),
                                    const SizedBox(width: 4),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest
                                              .withValues(alpha: 0.5),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.drag_handle_rounded,
                                          color: cs.onSurfaceVariant,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // 4c. Gallery / Grid View
                      SectionHeader(context.l10n.galleryGridViewSectionHeader),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showGridFileNames,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowGridFileNames(v),
                            title: Text(
                              context.l10n.showFileNamesLabel,
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showFileNamesDesc,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(
                              Icons.label_outlined,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ==========================================
                      // 5. MEDIA VIEWER & PLAYLIST
                      // ==========================================
                      SectionHeader(context.l10n.mediaViewerSectionHeader),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.autoStartPlaylistMode,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setAutoStartPlaylistMode(v),
                            title: Text(
                              context.l10n.autoStartPlaylistModeLabel,
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.autoStartPlaylistModeDesc,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(
                              Icons.playlist_play_rounded,
                              color: cs.primary,
                            ),
                          ),
                          SwitchListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showMediaCarousel,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowMediaCarousel(v),
                            title: Text(
                              context.l10n.showPlaylistCarouselLabel,
                              style: textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showPlaylistCarouselDesc,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(
                              Icons.view_carousel_rounded,
                              color: cs.primary,
                            ),
                          ),
                          OptionPickerTile<PlaylistTransitionEffect>(
                            label: context.l10n.playlistTransitionAnimationLabel,
                            value: state.config.playlistTransitionEffect,
                            options:
                                PlaylistTransitionEffect.values.map((effect) {
                              return SelectOption(
                                value: effect,
                                label: effect.getLocalizedLabel(context.l10n),
                              );
                            }).toList(),
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setPlaylistTransitionEffect(v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}