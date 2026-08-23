import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_sheet.dart';

class MediaViewerTopBar extends StatelessWidget {
  final MountedContainer container;
  final PlaylistController playlistController;
  final String currentFileName;
  final int totalCount;
  final PlaylistTransitionEffect currentTransitionEffect;
  final ValueChanged<PlaylistTransitionEffect> onTransitionEffectChanged;
  final PlaylistScrollMode currentScrollMode;
  final ValueChanged<PlaylistScrollMode> onScrollModeChanged;
  final VoidCallback onBackPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback onRenamePressed;
  final VoidCallback? onInfoPressed;
  final bool isBookmark;
  final VoidCallback onBookmarkPressed;
  final VoidCallback onPlaylistChanged;
  final VoidCallback? onMenuOpened;
  final VoidCallback? onMenuClosed;

  const MediaViewerTopBar({
    super.key,
    required this.container,
    required this.playlistController,
    required this.currentFileName,
    required this.totalCount,
    required this.currentTransitionEffect,
    required this.onTransitionEffectChanged,
    this.currentScrollMode = PlaylistScrollMode.horizontal,
    required this.onScrollModeChanged,
    required this.onBackPressed,
    required this.onDeletePressed,
    required this.onRenamePressed,
    this.onInfoPressed,
    required this.isBookmark,
    required this.onBookmarkPressed,
    required this.onPlaylistChanged,
    this.onMenuOpened,
    this.onMenuClosed,
  });

  Future<void> _showFileInfo(BuildContext context) async {
    onMenuOpened?.call();
    final file = playlistController.currentFile;
    final lastSlash = file.lastIndexOf('/');
    final dirPath = lastSlash == -1 ? '' : file.substring(0, lastSlash);
    final baseName = lastSlash == -1 ? file : file.substring(lastSlash + 1);
    var existingEntries = <RawEntry>[];
    try {
      final raw = await vaultExplorerApi.listDirectory(container, dirPath);
      if (raw != null) {
        existingEntries = RawEntry.parseAll(raw);
      }
    } catch (_) {}
    final currentEntry = existingEntries.firstWhere(
      (e) => e.name == baseName,
      orElse: () => RawEntry(
        name: baseName,
        isDir: false,
        sizeBytes: 0,
        modifiedSecs: 0,
      ),
    );
    if (context.mounted) {
      await FileInfoSheet.show(
        context,
        container: container,
        entry: currentEntry,
        currentDirPath: dirPath,
      );
    }
    onMenuClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 8,
        bottom: 24,
        left: 12,
        right: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          _TopBarCircleButton(
            icon: Icons.arrow_back_rounded,
            tooltip: context.l10n.backTooltip,
            onPressed: onBackPressed,
          ),
          const SizedBox(width: 12),
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
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (playlistController.isPlaylistMode || playlistController.isScanningSubfolders)
                  Text(
                    playlistController.isPlaylistMode
                        ? (playlistController.isScanningSubfolders
                            ? context.l10n.mediaViewerPlaylistPositionScanningLabel(
                                playlistController.currentIndex + 1, totalCount)
                            : context.l10n.mediaViewerPlaylistPositionLabel(
                                playlistController.currentIndex + 1, totalCount))
                        : context.l10n.mediaViewerScanningLabel,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildPlaylistMenu(context, cs),
          const SizedBox(width: 8),
          _buildMoreMenu(context, cs),
        ],
      ),
    );
  }

  Widget _buildPlaylistMenu(BuildContext context, ColorScheme cs) {
    final isPlaylist = playlistController.isPlaylistMode;
    final folderScope = playlistController.selectedFolder;
    final isThisFolderSelected = isPlaylist && folderScope == 'Current Folder Only';
    final isAllSelected = isPlaylist && folderScope == 'All';
    final menuStyle = MenuStyle(
      elevation: const WidgetStatePropertyAll(4),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 8),
      ),
    );
    return MenuAnchor(
      style: menuStyle,
      onOpen: onMenuOpened,
      onClose: onMenuClosed,
      builder: (ctx, controller, child) => _TopBarCircleButton(
        icon: isPlaylist ? Icons.playlist_play_rounded : Icons.playlist_add_rounded,
        iconColor: isPlaylist ? cs.primary : Colors.white,
        tooltip: isPlaylist ? context.l10n.playlistOptionsTooltip : context.l10n.enablePlaylistTooltip,
        onPressed: () {
          HapticFeedback.lightImpact();
          controller.isOpen ? controller.close() : controller.open();
        },
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
            if (newIndex != -1) {
              playlistController.updateIndex(newIndex);
            }
            onPlaylistChanged();
          },
          leadingIcon: isThisFolderSelected
              ? Icon(Icons.check_rounded, size: 18, color: cs.primary)
              : const SizedBox(width: 18),
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
            if (newIndex != -1) {
              playlistController.updateIndex(newIndex);
            }
            onPlaylistChanged();
          },
          leadingIcon: isAllSelected
              ? Icon(Icons.check_rounded, size: 18, color: cs.primary)
              : const SizedBox(width: 18),
          child: Text(context.l10n.allInclSubfoldersMenu),
        ),
        if (playlistController.isPlaylistMode) ...[
          const PopupMenuDivider(),
          MenuItemButton(
            style: MenuItemButton.styleFrom(
              foregroundColor: playlistController.isShuffled ? cs.primary : null,
            ),
            onPressed: () {
              final targetFile = playlistController.currentFile;
              playlistController.toggleShuffle();
              final newIndex = playlistController.playlist.indexOf(targetFile);
              if (newIndex != -1) {
                playlistController.updateIndex(newIndex);
              }
              onPlaylistChanged();
            },
            leadingIcon: Icon(
              Icons.shuffle_rounded,
              size: 18,
              color: playlistController.isShuffled ? cs.primary : cs.onSurfaceVariant,
            ),
            child: Text(
              playlistController.isShuffled
                  ? context.l10n.disableShuffleMenu
                  : context.l10n.shufflePlaylistMenu,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMoreMenu(BuildContext context, ColorScheme cs) {
    final menuStyle = MenuStyle(
      elevation: const WidgetStatePropertyAll(4),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 8),
      ),
    );
    return MenuAnchor(
      style: menuStyle,
      onOpen: onMenuOpened,
      onClose: onMenuClosed,
      builder: (ctx, controller, child) => _TopBarCircleButton(
        icon: Icons.more_vert_rounded,
        tooltip: context.l10n.moreActionsTooltip,
        onPressed: () {
          HapticFeedback.lightImpact();
          controller.isOpen ? controller.close() : controller.open();
        },
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: () async {
            try {
              await vaultExplorerApi.openWithApp(
                container,
                playlistController.currentFile,
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.failedToOpenExternalApp('$e')),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            }
          },
          leadingIcon: Icon(
            Icons.open_in_new_rounded,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          child: Text(context.l10n.openWithAppAction),
        ),
        MenuItemButton(
          onPressed: () {
            if (onInfoPressed != null) {
              onInfoPressed!();
            } else {
              _showFileInfo(context);
            }
          },
          leadingIcon: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          child: Text(context.l10n.fileInfoAction),
        ),
        MenuItemButton(
          onPressed: onRenamePressed,
          leadingIcon: Icon(
            Icons.drive_file_rename_outline_rounded,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          child: Text(context.l10n.renameFileMenu),
        ),
        MenuItemButton(
          onPressed: onBookmarkPressed,
          leadingIcon: Icon(
            isBookmark ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 18,
            color: isBookmark ? context.semanticColors.bookmark : cs.onSurfaceVariant,
          ),
          child: Text(
            isBookmark ? context.l10n.removeFromBookmarks : context.l10n.addToBookmarks,
          ),
        ),
        SubmenuButton(
          leadingIcon: Icon(
            currentScrollMode.icon,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          menuChildren: PlaylistScrollMode.values.map((mode) {
            final isSelected = mode == currentScrollMode;
            return MenuItemButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                onScrollModeChanged(mode);
              },
              leadingIcon: isSelected
                  ? Icon(Icons.check_rounded, size: 18, color: cs.primary)
                  : SizedBox(
                      width: 18,
                      child: Icon(
                        mode.icon,
                        size: 16,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
              child: Text(mode.getLocalizedLabel(context.l10n)),
            );
          }).toList(),
          child: Text(context.l10n.playlistScrollModeMenu),
        ),
        SubmenuButton(
          leadingIcon: Icon(
            Icons.screen_rotation_rounded,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          menuChildren: [
            MenuItemButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.portraitUp,
                ]);
              },
              child: Text(context.l10n.forcePortraitMenu),
            ),
            MenuItemButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]);
              },
              child: Text(context.l10n.forceLandscapeMenu),
            ),
            MenuItemButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                SystemChrome.setPreferredOrientations(DeviceOrientation.values);
              },
              child: Text(context.l10n.autoRotateSensorMenu),
            ),
          ],
          child: Text(context.l10n.screenOrientationMenu),
        ),
        SubmenuButton(
          leadingIcon: Icon(
            currentTransitionEffect.icon,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          menuChildren: PlaylistTransitionEffect.values.map((effect) {
            final isSelected = effect == currentTransitionEffect;
            return MenuItemButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                onTransitionEffectChanged(effect);
              },
              leadingIcon: isSelected
                  ? Icon(Icons.check_rounded, size: 18, color: cs.primary)
                  : SizedBox(
                      width: 18,
                      child: Icon(
                        effect.icon,
                        size: 16,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
              child: Text(effect.getLocalizedLabel(context.l10n)),
            );
          }).toList(),
          child: Text(context.l10n.playlistTransitionMenu),
        ),
        const PopupMenuDivider(),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            foregroundColor: cs.error,
          ),
          onPressed: onDeletePressed,
          leadingIcon: Icon(
            Icons.delete_outline_rounded,
            size: 18,
            color: cs.error,
          ),
          child: Text(context.l10n.deleteFileMenu),
        ),
      ],
    );
  }
}

class _TopBarCircleButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String tooltip;
  final VoidCallback onPressed;
  const _TopBarCircleButton({
    required this.icon,
    this.iconColor,
    required this.tooltip,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              size: 20,
              color: iconColor ?? Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}