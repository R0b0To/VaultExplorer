import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_viewer_action_button.dart';

class MediaViewerTopBar extends StatelessWidget {
  final PlaylistController playlistController;
  final String currentFileName;
  final int totalCount;
  final MediaViewerToolbarConfig toolbarConfig;
  final PlaylistTransitionEffect currentTransitionEffect;
  final ValueChanged<PlaylistTransitionEffect> onTransitionEffectChanged;
  final PlaylistScrollMode currentScrollMode;
  final ValueChanged<PlaylistScrollMode> onScrollModeChanged;
  final ValueChanged<MediaViewerAction> onExecuteAction;
  final VoidCallback onCustomizeControls;
  final bool isBookmark;
  final bool isMuted;
  final VoidCallback onPlaylistChanged;
  final VoidCallback? onMenuOpened;
  final VoidCallback? onMenuClosed;
  final bool isImage;
  final bool isAudio;

  const MediaViewerTopBar({
    super.key,
    required this.playlistController,
    required this.currentFileName,
    required this.totalCount,
    required this.toolbarConfig,
    required this.currentTransitionEffect,
    required this.onTransitionEffectChanged,
    this.currentScrollMode = PlaylistScrollMode.horizontal,
    required this.onScrollModeChanged,
    required this.onExecuteAction,
    required this.onCustomizeControls,
    required this.isBookmark,
    required this.isMuted,
    required this.onPlaylistChanged,
    this.onMenuOpened,
    this.onMenuClosed,
    required this.isImage,
    required this.isAudio,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final topInset = MediaQuery.paddingOf(context).top;

    final pinnedTopActions = toolbarConfig.topBarActions.where((action) {
      return action.isApplicable(
        isImage: isImage,
        isAudio: isAudio,
        isPlaylistMode: playlistController.isPlaylistMode,
      );
    }).toList();

    final moreActions = toolbarConfig.moreMenuActions.where((action) {
      return action.isApplicable(
        isImage: isImage,
        isAudio: isAudio,
        isPlaylistMode: playlistController.isPlaylistMode,
      );
    }).toList();

    return Container(
      padding: EdgeInsets.only(
        top: topInset + AppSpacing.sm,
        bottom: AppSpacing.lg,
        left: AppSpacing.md,
        right: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.45),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          MediaViewerActionButton(
            action: MediaViewerAction.playPause,
            customIcon: Icons.arrow_back_rounded,
            customTooltip: context.l10n.backTooltip,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentFileName.split('/').last,
                  style: textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (playlistController.isPlaylistMode ||
                    playlistController.isScanningSubfolders) ...[
                  const SizedBox(height: 2),
                  Text(
                    playlistController.isPlaylistMode
                        ? (playlistController.isScanningSubfolders
                            ? context.l10n
                                .mediaViewerPlaylistPositionScanningLabel(
                                    playlistController.currentIndex + 1,
                                    totalCount)
                            : context.l10n.mediaViewerPlaylistPositionLabel(
                                playlistController.currentIndex + 1,
                                totalCount))
                        : context.l10n.mediaViewerScanningLabel,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ...pinnedTopActions.map((action) {
            if (action == MediaViewerAction.playlistMenu) {
              return Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: _buildPlaylistMenu(context, cs),
              );
            }
            if (action == MediaViewerAction.screenOrientation) {
              return Padding(
                padding: const EdgeInsets.only(left: 6.0),
                child: MediaViewerActionButton(
                  action: action,
                  onTap: () => onExecuteAction(action),
                ),
              );
            }

            final isMute = action == MediaViewerAction.mute;
            return Padding(
              padding: const EdgeInsets.only(left: 6.0),
              child: MediaViewerActionButton(
                action: action,
                isHighlighted:
                    (action == MediaViewerAction.bookmark && isBookmark) ||
                    (isMute && isMuted),
                highlightColor:
                    isMute ? cs.error : context.semanticColors.bookmark,
                customIcon: isMute
                    ? (isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded)
                    : null,
                onTap: () => onExecuteAction(action),
              ),
            );
          }),
          // More MenuAnchor
          Padding(
            padding: const EdgeInsets.only(left: 6.0),
            child: _buildMoreMenu(context, cs, moreActions),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreMenu(
    BuildContext context,
    ColorScheme cs,
    List<MediaViewerAction> actions,
  ) {
    return MenuAnchor(
      onOpen: onMenuOpened,
      onClose: onMenuClosed,
      builder: (ctx, controller, child) => MediaViewerActionButton(
        action: MediaViewerAction.advancedSettings,
        customIcon: Icons.more_vert_rounded,
        customTooltip: 'More',
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        ...actions.map((action) {
          final isDelete = action == MediaViewerAction.delete;
          final isBookmarkAction = action == MediaViewerAction.bookmark;
          final isMuteAction = action == MediaViewerAction.mute;

          IconData icon = action.icon;
          Color? iconColor = isDelete ? cs.error : cs.onSurfaceVariant;

          if (isBookmarkAction && isBookmark) {
            iconColor = context.semanticColors.bookmark;
          } else if (isMuteAction) {
            icon = isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded;
            if (isMuted) iconColor = cs.error;
          }

          return MenuItemButton(
            style: isDelete || (isMuteAction && isMuted)
                ? MenuItemButton.styleFrom(foregroundColor: cs.error)
                : null,
            leadingIcon: Icon(icon, size: AppIconSize.small, color: iconColor),
            onPressed: () {
              HapticFeedback.lightImpact();
              onExecuteAction(action);
            },
            child: Text(action.getLocalizedLabel(context.l10n)),
          );
        }),
        const PopupMenuDivider(),
        MenuItemButton(
          leadingIcon: Icon(
            Icons.dashboard_customize_rounded,
            size: AppIconSize.small,
            color: cs.primary,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            onCustomizeControls();
          },
          child: Text(
            context.l10n.mediaViewerCustomizeControls,
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistMenu(BuildContext context, ColorScheme cs) {
    final isPlaylist = playlistController.isPlaylistMode;
    final folderScope = playlistController.selectedFolder;
    final isThisFolderSelected =
        isPlaylist && folderScope == 'Current Folder Only';
    final isAllSelected = isPlaylist && folderScope == 'All';

    return MenuAnchor(
      onOpen: onMenuOpened,
      onClose: onMenuClosed,
      builder: (ctx, controller, child) => MediaViewerActionButton(
        action: MediaViewerAction.playlistMenu,
        customIcon: isPlaylist
            ? Icons.playlist_play_rounded
            : Icons.playlist_add_rounded,
        isHighlighted: isPlaylist,
        highlightColor: cs.primary,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            foregroundColor: isThisFolderSelected ? cs.primary : null,
          ),
          onPressed: () async {
            final targetFile = playlistController.currentFile;
            if (isThisFolderSelected) {
              playlistController.disablePlaylist();
            } else {
              await playlistController.enablePlaylist('Current Folder Only');
            }
            final newIndex = playlistController.playlist.indexOf(targetFile);
            if (newIndex != -1) playlistController.updateIndex(newIndex);
            onPlaylistChanged();
          },
          leadingIcon: isThisFolderSelected
              ? Icon(Icons.check_rounded,
                  size: AppIconSize.small, color: cs.primary)
              : const SizedBox(width: AppIconSize.small),
          child: Text(context.l10n.thisFolderMenu),
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            foregroundColor: isAllSelected ? cs.primary : null,
          ),
          onPressed: () async {
            final targetFile = playlistController.currentFile;
            if (isAllSelected) {
              playlistController.disablePlaylist();
            } else {
              await playlistController.enablePlaylist('All');
            }
            final newIndex = playlistController.playlist.indexOf(targetFile);
            if (newIndex != -1) playlistController.updateIndex(newIndex);
            onPlaylistChanged();
          },
          leadingIcon: isAllSelected
              ? Icon(Icons.check_rounded,
                  size: AppIconSize.small, color: cs.primary)
              : const SizedBox(width: AppIconSize.small),
          child: Text(context.l10n.allInclSubfoldersMenu),
        ),
        if (playlistController.isPlaylistMode) ...[
          const PopupMenuDivider(),
          MenuItemButton(
            style: MenuItemButton.styleFrom(
              foregroundColor:
                  playlistController.isShuffled ? cs.primary : null,
            ),
            onPressed: () {
              final targetFile = playlistController.currentFile;
              playlistController.toggleShuffle();
              final newIndex = playlistController.playlist.indexOf(targetFile);
              if (newIndex != -1) playlistController.updateIndex(newIndex);
              onPlaylistChanged();
            },
            leadingIcon: Icon(
              Icons.shuffle_rounded,
              size: AppIconSize.small,
              color: playlistController.isShuffled
                  ? cs.primary
                  : cs.onSurfaceVariant,
            ),
            child: Text(
              playlistController.isShuffled
                  ? context.l10n.disableShuffleMenu
                  : context.l10n.shufflePlaylistMenu,
            ),
          ),
          SubmenuButton(
            leadingIcon: Icon(
              currentScrollMode.icon,
              size: AppIconSize.small,
              color: cs.onSurfaceVariant,
            ),
            menuChildren: PlaylistScrollMode.values.map((mode) {
              final isSelected = mode == currentScrollMode;
              return MenuItemButton(
                onPressed: () => onScrollModeChanged(mode),
                leadingIcon: isSelected
                    ? Icon(Icons.check_rounded,
                        size: AppIconSize.small, color: cs.primary)
                    : SizedBox(
                        width: AppIconSize.small,
                        child: Icon(mode.icon,
                            size: 16,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                      ),
                child: Text(mode.getLocalizedLabel(context.l10n)),
              );
            }).toList(),
            child: Text(context.l10n.playlistScrollModeMenu),
          ),
          SubmenuButton(
            leadingIcon: Icon(
              currentTransitionEffect.icon,
              size: AppIconSize.small,
              color: cs.onSurfaceVariant,
            ),
            menuChildren: PlaylistTransitionEffect.values.map((effect) {
              final isSelected = effect == currentTransitionEffect;
              return MenuItemButton(
                onPressed: () => onTransitionEffectChanged(effect),
                leadingIcon: isSelected
                    ? Icon(Icons.check_rounded,
                        size: AppIconSize.small, color: cs.primary)
                    : SizedBox(
                        width: AppIconSize.small,
                        child: Icon(effect.icon,
                            size: 16,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                      ),
                child: Text(effect.getLocalizedLabel(context.l10n)),
              );
            }).toList(),
            child: Text(context.l10n.playlistTransitionMenu),
          ),
        ],
      ],
    );
  }
}