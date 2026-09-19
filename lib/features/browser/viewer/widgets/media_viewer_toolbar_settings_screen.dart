import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/inputs/option_picker_tile.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/scrub_preview_style.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

class MediaViewerToolbarSettingsScreen extends ConsumerWidget {
  const MediaViewerToolbarSettingsScreen({super.key});

  void _reorderSection(
    WidgetRef ref, {
    required String sectionName,
    required int oldIndex,
    required int newIndex,
  }) {
    final state = ref.read(fileManagerToolbarSettingsProvider(null));
    final mediaConfig = state.config.mediaViewerToolbarConfig;
    final controller =
        ref.read(fileManagerToolbarSettingsProvider(null).notifier);

    // Standard Flutter ReorderableListView index offset adjustment
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final top = List<MediaViewerAction>.from(mediaConfig.topBarActions);
    final bottom = List<MediaViewerAction>.from(mediaConfig.bottomBarActions);
    final more = List<MediaViewerAction>.from(mediaConfig.moreMenuActions);
    final advanced =
        List<MediaViewerAction>.from(mediaConfig.advancedSettingsActions);

    switch (sectionName) {
      case 'top':
        final item = top.removeAt(oldIndex);
        top.insert(newIndex, item);
        break;
      case 'bottom':
        final item = bottom.removeAt(oldIndex);
        bottom.insert(newIndex, item);
        break;
      case 'more':
        final item = more.removeAt(oldIndex);
        more.insert(newIndex, item);
        break;
      case 'advanced':
        final item = advanced.removeAt(oldIndex);
        advanced.insert(newIndex, item);
        break;
    }

    final updated = mediaConfig.copyWith(
      topBarActions: top,
      bottomBarActions: bottom,
      moreMenuActions: more,
      advancedSettingsActions: advanced,
    );
    controller.updateMediaViewerConfig(updated);
    HapticFeedback.mediumImpact();
  }

  void _moveAction(
    WidgetRef ref, {
    required MediaViewerAction action,
    required String fromSection,
    required String toSection,
  }) {
    if (fromSection == toSection) return;

    final state = ref.read(fileManagerToolbarSettingsProvider(null));
    final mediaConfig = state.config.mediaViewerToolbarConfig;
    final controller =
        ref.read(fileManagerToolbarSettingsProvider(null).notifier);

    final top = List<MediaViewerAction>.from(mediaConfig.topBarActions);
    final bottom = List<MediaViewerAction>.from(mediaConfig.bottomBarActions);
    final more = List<MediaViewerAction>.from(mediaConfig.moreMenuActions);
    final advanced =
        List<MediaViewerAction>.from(mediaConfig.advancedSettingsActions);

    // 1. Remove from source list
    switch (fromSection) {
      case 'top':
        top.remove(action);
        break;
      case 'bottom':
        bottom.remove(action);
        break;
      case 'more':
        more.remove(action);
        break;
      case 'advanced':
        advanced.remove(action);
        break;
    }

    // 2. Append to target list
    switch (toSection) {
      case 'top':
        top.add(action);
        break;
      case 'bottom':
        bottom.add(action);
        break;
      case 'more':
        more.add(action);
        break;
      case 'advanced':
        advanced.add(action);
        break;
    }

    final updated = mediaConfig.copyWith(
      topBarActions: top,
      bottomBarActions: bottom,
      moreMenuActions: more,
      advancedSettingsActions: advanced,
    );
    controller.updateMediaViewerConfig(updated);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileManagerToolbarSettingsProvider(null));
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mediaConfig = state.config.mediaViewerToolbarConfig;
    final controller =
        ref.read(fileManagerToolbarSettingsProvider(null).notifier);

    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.mediaPlayerControlsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: l10n.resetToDefaultsTooltip,
            onPressed: () {
              controller.resetMediaViewerConfigToDefaults();
              showAppSnackBar(
                context,
                message: l10n.mediaControlsResetSuccess,
                tone: AppBannerTone.success,
              );
            },
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                children: [
                  // ==========================================
                  // 1. PLAYBACK & DISPLAY
                  // ==========================================
                  SectionHeader(l10n.playbackAndDisplayHeader),
                  SectionCard(
                    children: [
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        value: mediaConfig.showProgressBar,
                        onChanged: controller.setMediaViewerShowProgressBar,
                        title: Text(
                          l10n.showProgressBarTitle,
                          style: textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          l10n.showProgressBarSubtitle,
                          style: textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        secondary: Icon(
                          Icons.linear_scale_rounded,
                          color: cs.primary,
                        ),
                      ),
                      // Only meaningful while the seekbar itself is shown, so it
                      // greys out with it rather than silently doing nothing.
                      OptionPickerTile<ScrubPreviewStyle>(
                        label: l10n.scrubPreviewStyleTitle,
                        value: mediaConfig.scrubPreviewStyle,
                        prefixIcon: mediaConfig.scrubPreviewStyle.icon,
                        enabled: mediaConfig.showProgressBar,
                        options: ScrubPreviewStyle.values.map((style) {
                          return SelectOption(
                            value: style,
                            label: style.getLocalizedLabel(l10n),
                            subtitle: style.getLocalizedDescription(l10n),
                          );
                        }).toList(),
                        onChanged: controller.setMediaViewerScrubPreviewStyle,
                      ),
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        value: mediaConfig.showCenterTransportForImages,
                        onChanged: (val) {
                          controller.updateMediaViewerConfig(
                            mediaConfig.copyWith(
                              showCenterTransportForImages: val,
                            ),
                          );
                        },
                        title: Text(
                          l10n.showTransportControlsOnPhotosTitle,
                          style: textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          l10n.showTransportControlsOnPhotosSubtitle,
                          style: textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        secondary: Icon(
                          Icons.slideshow_rounded,
                          color: cs.primary,
                        ),
                      ),
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        value: mediaConfig.showStatusBadge,
                        onChanged: controller.setMediaViewerShowStatusBadge,
                        title: Text(
                          l10n.statusBadgeTitle,
                          style: textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          l10n.statusBadgeSubtitle,
                          style: textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        secondary:
                            Icon(Icons.badge_outlined, color: cs.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ==========================================
                  // 2. TOP BAR ACTIONS
                  // ==========================================
                  SectionHeader(l10n.topBarActionsHeader),
                  _buildReorderableSection(
                    context: context,
                    ref: ref,
                    sectionName: 'top',
                    actions: mediaConfig.topBarActions,
                    emptyHint: l10n.topBarActionsEmptyHint,
                    cs: cs,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 16),

                  // ==========================================
                  // 3. BOTTOM DOCK ACTIONS
                  // ==========================================
                  SectionHeader(l10n.bottomDockActionsHeader),
                  _buildReorderableSection(
                    context: context,
                    ref: ref,
                    sectionName: 'bottom',
                    actions: mediaConfig.bottomBarActions,
                    emptyHint: l10n.bottomDockActionsEmptyHint,
                    cs: cs,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 16),

                  // ==========================================
                  // 4. MORE MENU (•••) ACTIONS
                  // ==========================================
                  SectionHeader(l10n.moreMenuActionsHeader),
                  _buildReorderableSection(
                    context: context,
                    ref: ref,
                    sectionName: 'more',
                    actions: mediaConfig.moreMenuActions,
                    emptyHint: l10n.moreMenuActionsEmptyHint,
                    cs: cs,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 16),

                  // ==========================================
                  // 5. ADVANCED SETTINGS (OVERFLOW)
                  // ==========================================
                  SectionHeader(l10n.advancedSettingsActionsHeader),
                  _buildReorderableSection(
                    context: context,
                    ref: ref,
                    sectionName: 'advanced',
                    actions: mediaConfig.advancedSettingsActions,
                    emptyHint: l10n.advancedSettingsActionsEmptyHint,
                    cs: cs,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
    );
  }

  Widget _buildReorderableSection({
    required BuildContext context,
    required WidgetRef ref,
    required String sectionName,
    required List<MediaViewerAction> actions,
    required String emptyHint,
    required ColorScheme cs,
    required TextTheme textTheme,
  }) {
    final l10n = context.l10n;

    if (actions.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Text(
            emptyHint,
            style: textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: actions.length,
      onReorder: (oldIndex, newIndex) {
        _reorderSection(
          ref,
          sectionName: sectionName,
          oldIndex: oldIndex,
          newIndex: newIndex,
        );
      },
      itemBuilder: (context, i) {
        final action = actions[i];

        return Padding(
          key: ValueKey('${sectionName}_${action.name}'),
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(i == 0 ? 20 : 4),
              bottom: Radius.circular(i == actions.length - 1 ? 20 : 4),
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
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, size: 20, color: cs.primary),
              ),
              title: Text(
                action.getLocalizedLabel(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Quick move menu to transfer between sections
                  _buildMoveMenu(
                    context: context,
                    ref: ref,
                    action: action,
                    currentSection: sectionName,
                    cs: cs,
                    l10n: l10n,
                  ),

                  // Quick 1-tap removal to Advanced Settings
                  if (sectionName != 'advanced') ...[
                    const SizedBox(width: 2),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: cs.error,
                      ),
                      tooltip: l10n.moveToAdvancedSettingsTooltip,
                      onPressed: () {
                        _moveAction(
                          ref,
                          action: action,
                          fromSection: sectionName,
                          toSection: 'advanced',
                        );
                      },
                    ),
                  ],

                  const SizedBox(width: 4),

                  // Native ReorderableDragStartListener handle (smooth 120 FPS reordering)
                  ReorderableDragStartListener(
                    index: i,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
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
    );
  }

  Widget _buildMoveMenu({
    required BuildContext context,
    required WidgetRef ref,
    required MediaViewerAction action,
    required String currentSection,
    required ColorScheme cs,
    required dynamic l10n,
  }) {
    final isAdvanced = currentSection == 'advanced';

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
      icon: Icon(
        isAdvanced
            ? Icons.add_circle_outline_rounded
            : Icons.drive_file_move_outlined,
        size: 19,
        color: isAdvanced ? cs.primary : cs.onSurfaceVariant,
      ),
      tooltip: isAdvanced ? 'Add to toolbar' : 'Move to section',
      onSelected: (targetSection) {
        _moveAction(
          ref,
          action: action,
          fromSection: currentSection,
          toSection: targetSection,
        );
      },
      itemBuilder: (context) => [
        if (currentSection != 'top')
          PopupMenuItem(
            value: 'top',
            child: Row(
              children: [
                Icon(
                  Icons.vertical_align_top_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.topBarActionsHeader,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (currentSection != 'bottom')
          PopupMenuItem(
            value: 'bottom',
            child: Row(
              children: [
                Icon(
                  Icons.vertical_align_bottom_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.bottomDockActionsHeader,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (currentSection != 'more')
          PopupMenuItem(
            value: 'more',
            child: Row(
              children: [
                Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.moreMenuActionsHeader,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (currentSection != 'advanced')
          PopupMenuItem(
            value: 'advanced',
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.advancedSettingsActionsHeader,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}