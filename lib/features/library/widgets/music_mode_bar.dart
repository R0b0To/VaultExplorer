import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/controllers/music_mode.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';

enum _BarMenu { rescan, rebuild, folders, deleteSaved }

/// The dedicated music mode strip, shown at the bottom of the file manager
/// while the mode is on: switches between library views, toggles the mode off,
/// shows when a scan is running, and holds the mode's actions.
class MusicModeBar extends StatelessWidget {
  final MusicModeEntry entry;
  final MusicHub hub;

  final VoidCallback onToggleMode;
  final VoidCallback onEditFolders;

  /// Called when a view is picked. Null just switches the view; the copy of the
  /// bar inside a folder / album / artist / genre screen passes one that first
  /// returns to the library.
  final ValueChanged<MusicCategory>? onSelectCategory;

  const MusicModeBar({
    super.key,
    required this.entry,
    required this.hub,
    required this.onToggleMode,
    required this.onEditFolders,
    this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SafeArea(
      top: false,
      child: Material(
        color: cs.surfaceContainer,
        elevation: 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
          child: ListenableBuilder(
            listenable: Listenable.merge([entry, hub]),
            builder: (context, _) => SizedBox(
              height: 72,
              child: Row(
                children: [
                  for (final category in const [
                    MusicCategory.tracks,
                    MusicCategory.albums,
                    MusicCategory.artists,
                    MusicCategory.genres,
                    MusicCategory.folders,
                  ])
                    _buildDestination(context, category),
                  IconButton(
                    icon: const Icon(Icons.library_music_rounded),
                    color: Theme.of(context).colorScheme.primary,
                    tooltip: context.l10n.musicModeAction,
                    onPressed: onToggleMode,
                  ),
                  _buildMenu(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDestination(BuildContext context, MusicCategory category) {
    final selected = entry.category == category;
    final cs = Theme.of(context).colorScheme;
    final textStyle = context.typography.labelSmall?.copyWith(
      color: selected ? cs.onSurface : cs.onSurfaceVariant,
    );
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => (onSelectCategory ?? entry.setCategory)(category),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 52,
                height: 30,
                decoration: BoxDecoration(
                  color: selected ? cs.secondaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _icon(category),
                  size: 20,
                  color: selected
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _label(context, category),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _icon(MusicCategory category) => switch (category) {
    MusicCategory.files => Icons.folder_outlined,
    MusicCategory.tracks => Icons.queue_music_rounded,
    MusicCategory.albums => Icons.album_rounded,
    MusicCategory.artists => Icons.people_alt_rounded,
    MusicCategory.genres => Icons.category_rounded,
    MusicCategory.folders => Icons.folder_copy_outlined,
  };

  String _label(BuildContext context, MusicCategory c) {
    final l10n = context.l10n;
    return switch (c) {
      MusicCategory.files => l10n.musicModeFiles,
      MusicCategory.albums => l10n.libraryTabAlbums,
      MusicCategory.artists => l10n.libraryTabArtists,
      MusicCategory.genres => l10n.libraryTabGenres,
      MusicCategory.tracks => l10n.libraryTabTracks,
      MusicCategory.folders => l10n.libraryTabFolders,
    };
  }

  String? _storageNote(BuildContext context) {
    final location = hub.controllerOf(entry.container.uri)?.location;
    if (location == null) return null;
    final l10n = context.l10n;
    return switch (location) {
      LibraryLocation.inVault => l10n.libraryStorageInVault,
      LibraryLocation.thisDevice => l10n.libraryStorageThisDevice,
    };
  }

  Widget _buildMenu(BuildContext context) {
    final l10n = context.l10n;
    final note = _storageNote(context);
    return PopupMenuButton<_BarMenu>(
      onSelected: (item) async {
        switch (item) {
          case _BarMenu.rescan:
            await hub.rescanAll();
          case _BarMenu.rebuild:
            await hub.rescanAll(rebuild: true);
          case _BarMenu.folders:
            onEditFolders();
          case _BarMenu.deleteSaved:
            await hub.clearSavedIndex(entry.container);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.libraryMenuDeleteSavedDone)),
              );
            }
        }
      },
      itemBuilder: (context) => [
        if (note != null) ...[
          PopupMenuItem<_BarMenu>(enabled: false, child: Text(note)),
          const PopupMenuDivider(),
        ],
        PopupMenuItem<_BarMenu>(
          value: _BarMenu.rescan,
          child: Text(l10n.libraryMenuRescan),
        ),
        PopupMenuItem<_BarMenu>(
          value: _BarMenu.rebuild,
          child: Text(l10n.libraryMenuRebuild),
        ),
        PopupMenuItem<_BarMenu>(
          value: _BarMenu.folders,
          child: Text(l10n.musicModeMenuFolders),
        ),
        PopupMenuItem<_BarMenu>(
          value: _BarMenu.deleteSaved,
          child: Text(l10n.libraryMenuDeleteSaved),
        ),
      ],
    );
  }
}
