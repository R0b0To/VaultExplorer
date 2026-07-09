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
            Colors.black.withOpacity(0.85),
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
                Text(
                  '${playlistController.currentIndex + 1} of $totalCount${playlistController.isScanningSubfolders ? '  ·  scanning…' : ''}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: cs.error),
            tooltip: 'Delete File',
            onPressed: onDeletePressed,
            iconSize: 24,
          ),
          _buildMoreMenu(context, cs),
        ],
      ),
    );
  }

  Widget _buildMoreMenu(BuildContext context, ColorScheme cs) {
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(
          Colors.black.withValues(alpha: 0.9),
        ),
        elevation: WidgetStateProperty.all(12),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
        ),
      ),
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
          style: MenuItemButton.styleFrom(foregroundColor: Colors.white),
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
          leadingIcon: const Icon(
            Icons.open_in_new_rounded,
            size: 18,
            color: Colors.white70,
          ),
          child: const Text('Open with App'),
        ),
        SubmenuButton(
          style: SubmenuButton.styleFrom(foregroundColor: Colors.white),
          menuStyle: MenuStyle(
            backgroundColor: WidgetStateProperty.all(
              Colors.black.withValues(alpha: 0.9),
            ),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
          ),
          leadingIcon: const Icon(
            Icons.screen_rotation_rounded,
            size: 18,
            color: Colors.white70,
          ),
          menuChildren: [
            MenuItemButton(
              style: MenuItemButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () {
                HapticFeedback.lightImpact();
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.portraitUp,
                ]);
              },
              child: const Text('Force Portrait'),
            ),
            MenuItemButton(
              style: MenuItemButton.styleFrom(foregroundColor: Colors.white),
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
              style: MenuItemButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () {
                HapticFeedback.lightImpact();
                SystemChrome.setPreferredOrientations(DeviceOrientation.values);
              },
              child: const Text('Auto-Rotate (Sensor)'),
            ),
          ],
          child: const Text('Screen Orientation'),
        ),
        MenuItemButton(
          style: MenuItemButton.styleFrom(foregroundColor: Colors.white),
          onPressed: () {
            playlistController.toggleShuffle();
            onPlaylistChanged();
          },
          leadingIcon: Icon(
            Icons.shuffle_rounded,
            size: 18,
            color: playlistController.isShuffled ? cs.primary : Colors.white70,
          ),
          child: Text(
            playlistController.isShuffled
                ? 'Disable Shuffle'
                : 'Shuffle Playlist',
          ),
        ),
        const PopupMenuDivider(color: Colors.white10),
        SubmenuButton(
          style: SubmenuButton.styleFrom(foregroundColor: Colors.white),
          menuStyle: MenuStyle(
            backgroundColor: WidgetStateProperty.all(
              Colors.black.withValues(alpha: 0.9),
            ),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
          ),
          menuChildren: [
            MenuItemButton(
              style: MenuItemButton.styleFrom(
                foregroundColor:
                    playlistController.selectedFolder == 'Current Folder Only'
                        ? cs.primary
                        : Colors.white,
              ),
              onPressed: () async {
                await playlistController.filterByFolder('Current Folder Only');
                onPlaylistChanged();
              },
              leadingIcon:
                  playlistController.selectedFolder == 'Current Folder Only'
                      ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
                      : const SizedBox(width: 16),
              child: const Text('Current Folder Only'),
            ),
            MenuItemButton(
              style: MenuItemButton.styleFrom(
                foregroundColor: playlistController.selectedFolder == 'All'
                    ? cs.primary
                    : Colors.white,
              ),
              onPressed: () async {
                await playlistController.filterByFolder('All');
                onPlaylistChanged();
              },
              leadingIcon: playlistController.selectedFolder == 'All'
                  ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
                  : const SizedBox(width: 16),
              child: const Text('All (Incl. Subfolders)'),
            ),
          ],
          child: const Text('Folder Filter'),
        ),
      ],
    );
  }
}