import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/grid_aspect_ratio.dart';
import 'package:vaultexplorer/data/models/grid_corner_style.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/core/widgets/inputs/slider_setting_tile.dart';
import 'package:vaultexplorer/core/widgets/inputs/thumbnail_settings_tiles.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_toolbar_settings_screen.dart';
import 'package:vaultexplorer/features/settings/file_manager_skin_screen.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';

class FileManagerToolbarSettingsScreen extends ConsumerWidget {
  final String? containerUri;

  /// Holds no vault-related options (the app-wide vault thumbnail default and
  /// its "reset all vaults" action live in App settings), so the decoy file
  /// manager can open this same screen without exposing anything about vaults.
  const FileManagerToolbarSettingsScreen({
    super.key,
    this.containerUri,
  });

  static String _layoutModeLabel(BrowserLayoutMode mode, AppLocalizations l10n) {
    switch (mode) {
      case BrowserLayoutMode.list:
        return l10n.layoutModeColumnedList;
      case BrowserLayoutMode.detailed:
        return l10n.layoutModeDetailedList;
      case BrowserLayoutMode.compact:
        return l10n.layoutModeCompactList;
      case BrowserLayoutMode.grid:
        return l10n.layoutModeGalleryGrid;
      case BrowserLayoutMode.masonry:
        return l10n.layoutModeMasonry;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileManagerToolbarSettingsProvider(containerUri));
    final defaultLayoutMode = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.defaultLayoutMode),
    );
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: [
                      // ==========================================
                      // 1. GENERAL BROWSER LAYOUT & BARS
                      // ==========================================
                      SectionHeader(context.l10n.browserLayoutSectionHeader),
                      SectionCard(
                        children: [
                             OptionPickerTile<BrowserLayoutMode>(
                            label: context.l10n.defaultFolderLayoutLabel,
                            value: defaultLayoutMode,
                            options: BrowserLayoutMode.values.map((mode) {
                              return SelectOption(
                                value: mode,
                                label: _layoutModeLabel(mode, context.l10n),
                              );
                            }).toList(),
                            onChanged: (v) => ref
                                .read(appSettingsControllerProvider.notifier)
                                .setDefaultLayoutMode(v),
                          ),
                          OptionPickerTile<LongFileNameDisplayMode>(
                            label: context.l10n.longFileNameDisplayLabel,
                            value: state.config.longFileNameDisplayMode,
                            options: LongFileNameDisplayMode.values.map((mode) {
                              return SelectOption(
                                value: mode,
                                label: mode.getLocalizedLabel(context.l10n),
                                subtitle: mode.getLocalizedDescription(context.l10n),
                              );
                            }).toList(),
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setLongFileNameDisplayMode(v),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.rememberPerFolderLayout,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setRememberPerFolderLayout(v),
                            title: Text(
                              context.l10n.rememberPerFolderLayoutLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.rememberPerFolderLayoutDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.folder_special_outlined, color: cs.primary),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.resetSizeOnLayoutChange,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setResetSizeOnLayoutChange(v),
                            title: Text(
                              context.l10n.resetSizeOnLayoutChangeLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.resetSizeOnLayoutChangeDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.zoom_out_map_rounded, color: cs.primary),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showHiddenFiles,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowHiddenFiles(v),
                            title: Text(
                              context.l10n.showHiddenFilesLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showHiddenFilesDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.visibility_outlined, color: cs.primary),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showBreadcrumbBar,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowBreadcrumbBar(v),
                            title: Text(
                              context.l10n.showBreadcrumbBarLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showBreadcrumbBarDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.linear_scale_rounded, color: cs.primary),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showStatsBar,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowStatsBar(v),
                            title: Text(
                              context.l10n.showStatsBarLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showStatsBarDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.analytics_outlined, color: cs.primary),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.autoHideAppBar,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setAutoHideAppBar(v),
                            title: Text(
                              context.l10n.autoHideAppBarLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.autoHideAppBarDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.vertical_align_top_rounded, color: cs.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ==========================================
                      // 2. TOOLBAR & SHORTCUTS
                      // ==========================================
                      SectionHeader(context.l10n.toolbarLayoutSectionHeader),
                      SectionCard(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Icon(Icons.tune_rounded, color: cs.primary),
                            title: Text(
                              context.l10n.toolbarLayoutSectionHeader,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${state.config.order.length - state.config.hidden.length} / ${state.config.order.length}',
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SkinAreaScope(
                                  area: SkinArea.settings,
                                  child: FileManagerToolbarActionsScreen(containerUri: containerUri),
                                ),
                              ),
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.useFabForToolbar,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setUseFabForToolbar(v),
                            title: Text(
                              context.l10n.useFabForToolbarLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.useFabForToolbarDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.smart_button_rounded, color: cs.primary),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.bottomSelectionBar,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setBottomSelectionBar(v),
                            title: Text(
                              context.l10n.bottomSelectionBarLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.bottomSelectionBarDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.vertical_align_bottom_rounded, color: cs.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ==========================================
                      // 3. BOOKMARKS
                      // ==========================================
                      SectionHeader(context.l10n.bookmarkBarSectionHeader),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showBookmarkBar,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowBookmarkBar(v),
                            title: Text(
                              context.l10n.showBookmarkBarLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showBookmarkBarDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.star_rounded, color: cs.secondary),
                          ),
                          if (state.record != null)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: Icon(Icons.bookmarks_outlined, color: cs.secondary),
                              title: Text(
                                context.l10n.reorderBookmarksTitle,
                                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${state.record!.bookmarkPaths.length}',
                                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SkinAreaScope(
                                    area: SkinArea.settings,
                                    child: FileManagerBookmarksScreen(containerUri: containerUri),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ==========================================
                      // 4. THUMBNAILS & CACHE (LOCAL STORAGE)
                      // ==========================================
                      // The one slot shared by Local Storage and the decoy file
                      // manager. The vault default is edited in App settings.
                      SectionHeader(context.l10n.localStorageCardTitle),
                      SectionCard(
                        children: [
                          ThumbnailSettingsTiles(
                            cacheMode: state.config.localStorageThumbnailCacheMode,
                            quality: state.config.localStorageThumbnailQuality,
                            cacheModeLabel: context.l10n.cacheModeLabel,
                            qualityLabel: context.l10n.thumbnailQualityLabel,
                            isLocalStorage: true,
                            onCacheModeChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setLocalStorageThumbnailCacheMode(v),
                            onQualityChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setLocalStorageThumbnailQuality(v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ==========================================
                      // 5. VIEW MODES & PRESENTATION
                      // ==========================================
                      // 5a. List View
                      SectionHeader(context.l10n.listViewOptionsSectionHeader),
                      SectionCard(
                        children: [
                         SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showListThumbnails,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowListThumbnails(v),
                            title: Text(
                              context.l10n.showMediaThumbnailsLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showMediaThumbnailsDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.image_outlined, color: cs.primary),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showItemActionsMenu,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowItemActionsMenu(v),
                            title: Text(
                              context.l10n.showItemActionsMenuLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showItemActionsMenuDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.more_vert_rounded, color: cs.primary),
                          ),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Icon(Icons.view_column_rounded, color: cs.primary),
                            title: Text(
                              context.l10n.detailedListViewColumnsSectionHeader,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${state.config.detailColumnsOrder.length - state.config.hiddenDetailColumns.length} / ${state.config.detailColumnsOrder.length}',
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SkinAreaScope(
                                  area: SkinArea.settings,
                                  child: FileManagerDetailColumnsScreen(containerUri: containerUri),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 4b. Gallery / Grid View
                      SectionHeader(context.l10n.galleryGridViewSectionHeader),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.showGridFileNames,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setShowGridFileNames(v),
                            title: Text(
                              context.l10n.showFileNamesLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.showFileNamesDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.label_outlined, color: cs.primary),
                          ),
                          OptionPickerTile<GridAspectRatio>(
                            label: context.l10n.gridAspectRatioLabel,
                            value: state.config.gridAspectRatio,
                            options: GridAspectRatio.values.map((ratio) {
                              return SelectOption(
                                value: ratio,
                                label: ratio.getLocalizedLabel(context.l10n),
                              );
                            }).toList(),
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setGridAspectRatio(v),
                          ),
                          OptionPickerTile<GridCornerStyle>(
                            label: context.l10n.gridCornerStyleLabel,
                            value: state.config.gridCornerStyle,
                            options: GridCornerStyle.values.map((style) {
                              return SelectOption(
                                value: style,
                                label: style.getLocalizedLabel(context.l10n),
                              );
                            }).toList(),
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setGridCornerStyle(v),
                          ),
                          SliderSettingTile(
                            label: context.l10n.gridSpacingLabel,
                            prefixIcon: Icons.space_bar_rounded,
                            value: state.config.gridSpacing,
                            min: FileManagerToolbarConfig.minGridSpacing,
                            max: FileManagerToolbarConfig.maxGridSpacing,
                            divisions: (FileManagerToolbarConfig.maxGridSpacing -
                                    FileManagerToolbarConfig.minGridSpacing) ~/
                                2,
                            valueLabel: (v) => v == 0
                                ? context.l10n.gridSpacingNone
                                : context.l10n.gridSpacingValue(v),
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setGridSpacing(v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ==========================================
                      // 5. APPEARANCE & MEDIA
                      // ==========================================
                      SectionHeader(context.l10n.fileSkinSectionHeader),
                      SectionCard(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            leading: Icon(Icons.palette_outlined, color: cs.primary),
                            title: Text(
                              context.l10n.fileSkinEntryTitle,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              state.config.skin.matchingPreset?.getLocalizedLabel(context.l10n) ??
                                  context.l10n.fileSkinPresetCustom,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SkinAreaScope(
                                  area: SkinArea.settings,
                                  child: FileManagerSkinScreen(containerUri: containerUri),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      SectionHeader(context.l10n.mediaViewerSectionHeader),
                      SectionCard(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            leading: Icon(Icons.tune_rounded, color: cs.primary),
                            title: Text(
                              context.l10n.mediaPlayerControlsTitle,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${context.l10n.playbackSettingsTitle}, ${context.l10n.toolbarLayoutSectionHeader}, ${context.l10n.advancedOptionsTitle}',
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SkinAreaScope(
                                    area: SkinArea.settings,
                                    child: const MediaViewerToolbarSettingsScreen(),
                                  ),
                                ),
                              );
                            },
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            value: state.config.autoStartPlaylistMode,
                            onChanged: (v) => ref
                                .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                                .setAutoStartPlaylistMode(v),
                            title: Text(
                              context.l10n.autoStartPlaylistModeLabel,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              context.l10n.autoStartPlaylistModeDesc,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            secondary: Icon(Icons.playlist_play_rounded, color: cs.primary),
                          ),
                          OptionPickerTile<PlaylistTransitionEffect>(
                            label: context.l10n.playlistTransitionAnimationLabel,
                            value: state.config.playlistTransitionEffect,
                            options: PlaylistTransitionEffect.values.map((effect) {
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

// ─────────────────────────────────────────────────────────────────────────────
// SUB-SCREEN 1: TOOLBAR ACTIONS REORDER & VISIBILITY
// ─────────────────────────────────────────────────────────────────────────────

class FileManagerToolbarActionsScreen extends ConsumerWidget {
  final String? containerUri;
  const FileManagerToolbarActionsScreen({super.key, this.containerUri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileManagerToolbarSettingsProvider(containerUri));
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.toolbarLayoutSectionHeader,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              buildDefaultDragHandles: false,
              itemCount: state.config.order.length,
              onReorderItem: (oldIndex, newIndex) => ref
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
                      bottom: Radius.circular(i == state.config.order.length - 1 ? 20 : 4),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: visible ? cs.primaryContainer.withValues(alpha: 0.5) : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          action.icon,
                          size: 20,
                          color: visible ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      title: Text(
                        action.getLocalizedLabel(context.l10n),
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: visible ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.6),
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
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.drag_handle_rounded, color: cs.onSurfaceVariant, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUB-SCREEN 2: DETAILED LIST COLUMNS REORDER & VISIBILITY
// ─────────────────────────────────────────────────────────────────────────────

class FileManagerDetailColumnsScreen extends ConsumerWidget {
  final String? containerUri;
  const FileManagerDetailColumnsScreen({super.key, this.containerUri});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileManagerToolbarSettingsProvider(containerUri));
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.detailedListViewColumnsSectionHeader,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              buildDefaultDragHandles: false,
              itemCount: state.config.detailColumnsOrder.length,
              onReorderItem: (oldIndex, newIndex) => ref
                  .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                  .reorderDetailColumns(oldIndex, newIndex),
              itemBuilder: (context, i) {
                final col = state.config.detailColumnsOrder[i];
                final visible = !state.config.hiddenDetailColumns.contains(col);
                return Padding(
                  key: ValueKey(col),
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(i == 0 ? 20 : 4),
                      bottom: Radius.circular(i == state.config.detailColumnsOrder.length - 1 ? 20 : 4),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: visible ? cs.primaryContainer.withValues(alpha: 0.5) : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          col.icon,
                          size: 20,
                          color: visible ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      title: Text(
                        col.getLocalizedLabel(context.l10n),
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: visible ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.6),
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
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.drag_handle_rounded, color: cs.onSurfaceVariant, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUB-SCREEN 3: BOOKMARKS REORDER & REMOVAL
// ─────────────────────────────────────────────────────────────────────────────

class FileManagerBookmarksScreen extends ConsumerWidget {
  final String? containerUri;
  const FileManagerBookmarksScreen({super.key, this.containerUri});

  static bool _isFolder(String path) {
    final leaf = path.split('/').last;
    return !leaf.contains('.') || path.endsWith('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileManagerToolbarSettingsProvider(containerUri));
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bookmarks = state.record?.bookmarkPaths ?? const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.reorderBookmarksTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: bookmarks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.l10n.noBookmarksYet,
                        style: textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    buildDefaultDragHandles: false,
                    itemCount: bookmarks.length,
                    onReorderItem: (oldIndex, newIndex) => ref
                        .read(fileManagerToolbarSettingsProvider(containerUri).notifier)
                        .reorderBookmarks(oldIndex, newIndex),
                    itemBuilder: (context, i) {
                      final path = bookmarks[i];
                      final name = path.split('/').last;
                      final isDir = _isFolder(path);
                      final ext = name.contains('.') ? name.split('.').last : '';
                      final icon = isDir ? Icons.folder_rounded : (vaultIconForExt(ext) ?? iconForFile(name));
                      final iconColor = isDir ? cs.secondary : (vaultColorForExt(ext) ?? colorForFile(name));

                      return Padding(
                        key: ValueKey(path),
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Material(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(i == 0 ? 20 : 4),
                            bottom: Radius.circular(i == bookmarks.length - 1 ? 20 : 4),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(icon, size: 20, color: iconColor),
                            ),
                            title: Text(
                              name,
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.close_rounded, size: 20, color: cs.error),
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
                                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.drag_handle_rounded, color: cs.onSurfaceVariant, size: 20),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}