import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';

class MediaViewerTopBar extends StatelessWidget {
  final MountedContainer container;
  final PlaylistController playlistController;
  final String currentFileName;
  final int totalCount;
  final VoidCallback onBackPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback onPlaylistChanged;

  const MediaViewerTopBar({
    super.key,
    required this.container,
    required this.playlistController,
    required this.currentFileName,
    required this.totalCount,
    required this.onBackPressed,
    required this.onDeletePressed,
    required this.onPlaylistChanged,
  });

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
          // M3 Tactile Back Button
          _TopBarCircleButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed: onBackPressed,
          ),
          const SizedBox(width: 12),
          // Title & Subtitle Info
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
                        ? '${playlistController.currentIndex + 1} of $totalCount${playlistController.isScanningSubfolders ? '  ·  scanning…' : ''}'
                        : 'Scanning…',
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
      builder: (ctx, controller, child) => _TopBarCircleButton(
        icon: isPlaylist ? Icons.playlist_play_rounded : Icons.playlist_add_rounded,
        iconColor: isPlaylist ? cs.primary : Colors.white,
        tooltip: isPlaylist ? 'Playlist Options' : 'Enable Playlist',
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
          child: const Text('This Folder'),
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
          child: const Text('All (Incl. Subfolders)'),
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
                  ? 'Disable Shuffle'
                  : 'Shuffle Playlist',
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
      builder: (ctx, controller, child) => _TopBarCircleButton(
        icon: Icons.more_vert_rounded,
        tooltip: 'More Actions',
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
                    content: Text('Failed to open in external app: $e'),
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
          child: const Text('Open with App'),
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
              child: const Text('Force Portrait'),
            ),
            MenuItemButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]);
              },
              child: const Text('Force Landscape'),
            ),
            MenuItemButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                SystemChrome.setPreferredOrientations(DeviceOrientation.values);
              },
              child: const Text('Auto-Rotate (Sensor)'),
            ),
          ],
          child: const Text('Screen Orientation'),
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
          child: const Text('Delete File'),
        ),
      ],
    );
  }
}

// ── Translucent M3 Top-Bar Action Button ─────────────────────────────────────

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
