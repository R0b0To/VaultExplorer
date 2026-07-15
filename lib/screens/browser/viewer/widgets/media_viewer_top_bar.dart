import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '/../../models/mounted_container.dart';
import '/../../services/vaultexplorer_api.dart';
import '../playlist_controller.dart';

class MediaViewerTopBar extends StatelessWidget {
  final MountedContainer container;
  final PlaylistController playlistController;
  final String currentFileName;
  final int totalCount;
  final VoidCallback onBackPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback onPlaylistChanged;

  const MediaViewerTopBar({
    Key? key,
    required this.container,
    required this.playlistController,
    required this.currentFileName,
    required this.totalCount,
    required this.onBackPressed,
    required this.onDeletePressed,
    required this.onPlaylistChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 24,
        left: 8,
        right: 8,
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
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: onBackPressed,
            iconSize: 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentFileName.split('/').last,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
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
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          _buildPlaylistMenu(context, cs),
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

    return MenuAnchor(
      builder: (ctx, controller, child) => IconButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          controller.isOpen ? controller.close() : controller.open();
        },
        icon: Icon(
          playlistController.isPlaylistMode
              ? Icons.playlist_play_rounded
              : Icons.playlist_add_rounded,
          color: playlistController.isPlaylistMode ? cs.primary : Colors.white,
        ),
        tooltip: playlistController.isPlaylistMode ? 'Playlist Options' : 'Enable Playlist',
      ),
      menuChildren: [
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            foregroundColor: isThisFolderSelected ? cs.primary : null,
          ),
          onPressed: () async {
            // 1. Capture the currently viewed file before altering the playlist
            final targetFile = playlistController.currentFile;

            if (isThisFolderSelected) {
              playlistController.disablePlaylist();
            } else {
              await playlistController.enablePlaylist('Current Folder Only');
            }

            // 2. Find where the file ended up in the new playlist and update the index
            final newIndex = playlistController.playlist.indexOf(targetFile);
            if (newIndex != -1) {
              playlistController.updateIndex(newIndex);
            }

            onPlaylistChanged();
          },
          leadingIcon: isThisFolderSelected
              ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
              : const SizedBox(width: 16),
          child: const Text('This Folder'),
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(
            foregroundColor: isAllSelected ? cs.primary : null,
          ),
          onPressed: () async {
            // 1. Capture the currently viewed file before altering the playlist
            final targetFile = playlistController.currentFile;

            if (isAllSelected) {
              playlistController.disablePlaylist();
            } else {
              await playlistController.enablePlaylist('All');
            }

            // 2. Find where the file ended up in the new playlist and update the index
            final newIndex = playlistController.playlist.indexOf(targetFile);
            if (newIndex != -1) {
              playlistController.updateIndex(newIndex);
            }

            onPlaylistChanged();
          },
          leadingIcon: isAllSelected
              ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
              : const SizedBox(width: 16),
          child: const Text('All (Incl. Subfolders)'),
        ),
        if (playlistController.isPlaylistMode) ...[
          const PopupMenuDivider(),
          MenuItemButton(
            style: MenuItemButton.styleFrom(
              foregroundColor: playlistController.isShuffled ? cs.primary : null,
            ),
            onPressed: () {
              // 1. Capture current file
              final targetFile = playlistController.currentFile;
              
              playlistController.toggleShuffle();

              // 2. Restore index so we don't jump when shuffling/unshuffling
              final newIndex = playlistController.playlist.indexOf(targetFile);
              if (newIndex != -1) {
                playlistController.updateIndex(newIndex);
              }

              onPlaylistChanged();
            },
            leadingIcon: Icon(
              Icons.shuffle_rounded,
              size: 16,
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
    return MenuAnchor(
      builder: (ctx, controller, child) => IconButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          controller.isOpen ? controller.close() : controller.open();
        },
        icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
        tooltip: 'More Actions',
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