import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/index/library_index.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';
import 'package:vaultexplorer/features/library/widgets/library_cover.dart';
import 'package:vaultexplorer/features/library/widgets/library_widgets.dart';
import 'package:vaultexplorer/features/library/widgets/music_covers.dart';
import 'package:vaultexplorer/features/library/widgets/music_mini_player.dart';

enum _DetailMenu { chooseCover, removeCover }

/// One album, artist or genre: a header with Play and Shuffle, then its tracks.
///
/// An artist can also show a strip of its albums; [onOpenAlbum] opens one. When
/// [coverKey] is given the cover can be chosen by hand (an image from the
/// location's own files), since the app has no internet to fetch one.
/// The route a library detail screen (album, artist, genre, folder) is shown
/// on. The bar inside those screens uses it to find its way back to the library.
class LibraryDetailRoute<T> extends MaterialPageRoute<T> {
  LibraryDetailRoute({required super.builder});
}

class LibraryDetailScreen extends StatelessWidget {
  final MusicHub hub;
  final MusicCovers covers;
  final String title;
  final String subtitle;
  final LibraryTrack? coverTrack;
  final List<LibraryTrack> tracks;

  /// Albums to show in a horizontal strip above the tracks (artist view).
  final List<AlbumGroup> albums;
  final void Function(AlbumGroup album)? onOpenAlbum;

  /// Picks the track whose picture a row shows; pass one that returns the
  /// album's cover track so all of an album's rows share a single cached read.
  final LibraryTrack? Function(LibraryTrack track)? coverOf;

  /// Album view: rows show the track number instead of a cover.
  final bool numbered;
  final IconData placeholderIcon;

  /// Key a hand-chosen cover is saved under (album or artist), or null when this
  /// view has no cover of its own to choose.
  final String? coverKey;

  /// Opens the image picker and saves the result; null hides the menu.
  final Future<void> Function()? onChooseCover;

  /// The music mode bar, kept at the bottom so the library's views stay one tap
  /// away while a folder, album, artist or genre is open.
  final Widget? modeBar;

  const LibraryDetailScreen({
    super.key,
    required this.hub,
    required this.covers,
    required this.title,
    required this.subtitle,
    required this.coverTrack,
    required this.tracks,
    this.albums = const [],
    this.onOpenAlbum,
    this.coverOf,
    this.numbered = false,
    this.placeholderIcon = Icons.music_note_rounded,
    this.coverKey,
    this.onChooseCover,
    this.modeBar,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    final text = context.typography;
    final totalMs = tracks.fold<int>(0, (sum, t) => sum + t.durationMs);
    final countLine = [
      l10n.libraryTrackCount(tracks.length),
      if (totalMs > 0) formatDuration(Duration(milliseconds: totalMs)),
    ].join(' · ');
    final showSource = hub.sourceCount > 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (coverKey != null && onChooseCover != null)
            ValueListenableBuilder<int>(
              valueListenable: covers.revision,
              builder: (context, _, _) => PopupMenuButton<_DetailMenu>(
                onSelected: (item) async {
                  switch (item) {
                    case _DetailMenu.chooseCover:
                      await onChooseCover!();
                    case _DetailMenu.removeCover:
                      await covers.removeCustom(coverKey!);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<_DetailMenu>(
                    value: _DetailMenu.chooseCover,
                    child: Text(l10n.musicCoverChoose),
                  ),
                  if (covers.hasCustom(coverKey!))
                    PopupMenuItem<_DetailMenu>(
                      value: _DetailMenu.removeCover,
                      child: Text(l10n.musicCoverRemove),
                    ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MusicMiniPlayer(hub: hub, covers: covers),
          if (modeBar != null) modeBar!,
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LibraryCover(
                        covers: covers,
                        track: coverTrack,
                        groupKey: coverKey,
                        size: 120,
                        borderRadius: 12,
                        placeholderIcon: placeholderIcon,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleLarge,
                            ),
                            if (subtitle.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                countLine,
                                style: text.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: tracks.isEmpty
                              ? null
                              : () => playLibraryTracks(
                                  context,
                                  hub: hub,
                                  tracks: tracks,
                                ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(l10n.libraryPlayAll),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: tracks.isEmpty
                              ? null
                              : () => playLibraryTracks(
                                  context,
                                  hub: hub,
                                  tracks: tracks,
                                  shuffle: true,
                                ),
                          icon: const Icon(Icons.shuffle_rounded),
                          label: Text(l10n.libraryShuffleAll),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (albums.isNotEmpty && onOpenAlbum != null) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Text(
                  l10n.libraryArtistAlbumsHeader,
                  style: text.titleMedium,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  itemCount: albums.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (context, i) => SizedBox(
                    width: 140,
                    child: LibraryAlbumTile(
                      album: albums[i],
                      covers: covers,
                      onTap: () => onOpenAlbum!(albums[i]),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: Text(
                  l10n.libraryArtistTracksHeader,
                  style: text.titleMedium,
                ),
              ),
            ),
          ],
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) {
              final t = tracks[i];
              return LibraryTrackTile(
                track: t,
                covers: covers,
                coverTrack: coverOf?.call(t),
                leadingLabel: numbered
                    ? (t.trackNo > 0 ? '${t.trackNo}' : '–')
                    : null,
                // In an album the album is a given; only show who performs it.
                subtitle: numbered ? t.artists.join(', ') : null,
                sourceLabel: showSource
                    ? hub.containerOf(t.source)?.displayName
                    : null,
                onTap: () => playLibraryTracks(
                  context,
                  hub: hub,
                  tracks: tracks,
                  startIndex: i,
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        ],
      ),
    );
  }
}
