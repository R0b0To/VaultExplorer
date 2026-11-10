import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/controllers/music_mode.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';

enum _BarMenu { rescan, rebuild, folders, deleteSaved }

/// A persistent mode switch action with the same icon-only hit target as the
/// file manager toolbar. Like the gallery mode button it keeps one icon in
/// both states: outlined when the mode is off, filled and tinted when on.
class MusicModeSwitchButton extends StatelessWidget {
  final bool musicMode;
  final VoidCallback onPressed;

  const MusicModeSwitchButton({
    super.key,
    required this.musicMode,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: musicMode
          ? context.l10n.musicModeMenuTurnOff
          : context.l10n.musicModeAction,
      icon: Icon(
        musicMode ? Icons.library_music_rounded : Icons.library_music_outlined,
        size: 24,
      ),
      color: musicMode ? cs.primary : cs.onSurfaceVariant,
      onPressed: onPressed,
    );
  }
}

/// Music-library actions, shown beside search in the library header or in the
/// compact navigation bar on library detail pages.
class MusicModeMenuButton extends StatelessWidget {
  final MusicModeEntry entry;
  final MusicHub hub;
  final VoidCallback onEditFolders;
  final bool compact;

  const MusicModeMenuButton({
    super.key,
    required this.entry,
    required this.hub,
    required this.onEditFolders,
    this.compact = false,
  });

  String? _storageNote(BuildContext context) {
    final location = hub.controllerOf(entry.container.uri)?.location;
    if (location == null) return null;
    final l10n = context.l10n;
    return switch (location) {
      LibraryLocation.inVault => l10n.libraryStorageInVault,
      LibraryLocation.thisDevice => l10n.libraryStorageThisDevice,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final note = _storageNote(context);
    return PopupMenuButton<_BarMenu>(
      tooltip: l10n.optionsAction,
      icon: compact ? null : const Icon(Icons.more_vert_rounded),
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
      constraints: null,
      child: compact
          ? const SizedBox(
              width: 48,
              height: 44,
              child: Center(child: Icon(Icons.more_vert_rounded, size: 20)),
            )
          : null,
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
          PopupMenuItem<_BarMenu>(
            enabled: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 200),
              child: Text(note),
            ),
          ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem<_BarMenu>(
          value: _BarMenu.rescan,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: Text(l10n.libraryMenuRescan),
          ),
        ),
        PopupMenuItem<_BarMenu>(
          value: _BarMenu.rebuild,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: Text(l10n.libraryMenuRebuild),
          ),
        ),
        PopupMenuItem<_BarMenu>(
          value: _BarMenu.folders,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: Text(l10n.musicModeMenuFolders),
          ),
        ),
        PopupMenuItem<_BarMenu>(
          value: _BarMenu.deleteSaved,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: Text(l10n.libraryMenuDeleteSaved),
          ),
        ),
      ],
    );
  }
}

/// The dedicated music mode strip, shown at the bottom of the file manager
/// while the mode is on: switches between library views, toggles the mode off,
/// shows when a scan is running, and holds the mode's actions.
class MusicModeBar extends StatelessWidget {
  final MusicModeEntry entry;
  final MusicHub hub;

  final VoidCallback onToggleMode;
  final VoidCallback onEditFolders;
  final bool showMenu;

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
    this.showMenu = true,
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
              height: 64,
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
                  MusicModeSwitchButton(
                    musicMode: true,
                    onPressed: onToggleMode,
                  ),
                  if (showMenu)
                    MusicModeMenuButton(
                      entry: entry,
                      hub: hub,
                      onEditFolders: onEditFolders,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One view of the library. Only the view in use shows its name (under a
  /// pill that animates in); the others are icon-only
  ///The name stays available as a tooltip and to screen readers.
  Widget _buildDestination(BuildContext context, MusicCategory category) {
    final selected = entry.category == category;
    final cs = Theme.of(context).colorScheme;
    final label = _label(context, category);
    final pill = Color.alphaBlend(
      cs.primary.withValues(alpha: 0.08),
      cs.secondaryContainer,
    );
    const animation = Duration(milliseconds: 220);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => (onSelectCategory ?? entry.setCategory)(category),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: animation,
                  curve: Curves.easeOutCubic,
                  width: 52,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected ? pill : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _icon(category),
                    size: 22,
                    color: selected
                        ? cs.onSecondaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: selected ? 1 : 0),
                  duration: animation,
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: t,
                      child: Opacity(opacity: t, child: child),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.labelSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
}
