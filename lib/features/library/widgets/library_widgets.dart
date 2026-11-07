import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_screen.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/index/library_index.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';
import 'package:vaultexplorer/features/library/widgets/library_cover.dart';
import 'package:vaultexplorer/features/library/widgets/music_covers.dart';

// ── Cover keys ──────────────────────────────────────────────────────────────

/// The key a hand-chosen cover for an album is saved under. Album keys come from
/// the tags, so the same album gets the same key in every container.
String albumCoverKey(AlbumGroup album) => 'album|${album.key}';

String artistCoverKey(ArtistGroup artist) => 'artist|${artist.key}';

// ── Labels ──────────────────────────────────────────────────────────────────

String libraryAlbumTitle(BuildContext context, AlbumGroup album) =>
    album.title.isEmpty ? context.l10n.libraryUnknownAlbum : album.title;

String libraryArtistLabel(BuildContext context, String name) =>
    name.isEmpty ? context.l10n.libraryUnknownArtist : name;

String libraryGenreLabel(BuildContext context, String name) =>
    name.isEmpty ? context.l10n.libraryUnknownGenre : name;

/// "Artist · 2004", "Various artists", or "Unknown artist".
String libraryAlbumSubtitle(BuildContext context, AlbumGroup album) {
  final artist = album.variousArtists
      ? context.l10n.libraryVariousArtists
      : libraryArtistLabel(context, album.artist);
  return album.year == 0 ? artist : '$artist · ${album.year}';
}

/// "03:07" or "" when the length is unknown.
String libraryDurationLabel(int durationMs) =>
    durationMs <= 0 ? '' : formatClockDuration(Duration(milliseconds: durationMs));

/// "Artist — Album" for a track row; whichever part exists when one is missing.
String libraryTrackSubtitle(BuildContext context, LibraryTrack t) {
  final artist = t.artists.isEmpty ? '' : t.artists.join(', ');
  final album = t.album;
  if (artist.isNotEmpty && album.isNotEmpty) return '$artist — $album';
  if (artist.isNotEmpty) return artist;
  if (album.isNotEmpty) return album;
  return context.l10n.libraryUnknownArtist;
}

// ── Playback ────────────────────────────────────────────────────────────────

/// The `startingFolder` given to the viewer for every library queue.
///
/// The viewer scopes a playlist to the folder of its first file and, for a
/// queue that all sits in that one folder, lets the user widen it to "All",
/// which rescans the folder and would replace a library queue (an album, an
/// artist, search results) with whatever else lives there. Naming a folder that
/// holds none of the queue's files makes the viewer treat the queue as already
/// spanning folders: it starts on "All" with nothing left to scan, so the queue
/// stays exactly as the library built it. The name starts with a dot, so the
/// library never indexes it and no real folder is expected to use it.
/// `library_queue_test.dart` pins this behavior to `PlaylistController`.
const String libraryQueueFolder = '.library-queue';

/// Starts [tracks] in the mini player at [startIndex], or in a random order with
/// [shuffle].
///
/// The viewer plays from one container at a time, so when the list mixes
/// containers (a merged library) it plays the tracks that live in the starting
/// track's container, in list order, and says so. For a shuffle the starting
/// container is that of a randomly chosen track, so containers come up in
/// proportion to how many tracks they hold. A hidden viewer bootstrap reuses
/// the normal player initialization and hands playback to the mini player.
void playLibraryTracks(
  BuildContext context, {
  required MusicHub hub,
  required List<LibraryTrack> tracks,
  int startIndex = 0,
  bool shuffle = false,
}) {
  if (tracks.isEmpty) return;
  final first = shuffle
      ? tracks[math.Random().nextInt(tracks.length)]
      : tracks[startIndex.clamp(0, tracks.length - 1)];
  final container = hub.containerOf(first.source);
  if (container == null) return;

  final queue = [
    for (final t in tracks)
      if (t.source == first.source) t,
  ];
  final paths = [for (final t in queue) t.path];
  var index = shuffle ? 0 : queue.indexWhere((t) => identical(t, first));
  if (index < 0) index = 0;
  if (shuffle) paths.shuffle();

  if (queue.length < tracks.length) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(context.l10n.musicPlayPartialNote(queue.length, container.displayName)),
      ),
    );
  }

  if (BackgroundPlaybackHost.instance.playLibrarySelection(
    container: container,
    paths: paths,
    index: index,
  )) {
    return;
  }

  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => MediaViewerScreen(
        container: container,
        mediaFiles: paths,
        initialIndex: index,
        startingFolder: libraryQueueFolder,
        thumbnailCacheMode: ThumbnailCacheMode.appCache,
        mediaFilter: 'audio',
        keepAudioPlayingOnClose: true,
        startInMiniPlayer: true,
        isLibraryPlayback: true,
      ),
      transitionsBuilder: (_, _, _, child) => child,
    ),
  );
}

// ── Tiles ───────────────────────────────────────────────────────────────────

class LibraryAlbumTile extends StatelessWidget {
  final AlbumGroup album;
  final MusicCovers covers;
  final VoidCallback onTap;

  /// Starts the album playing; shown as a small button on the cover.
  final VoidCallback? onPlay;

  const LibraryAlbumTile({
    super.key,
    required this.album,
    required this.covers,
    required this.onTap,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final text = context.typography;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              LibraryCover(
                covers: covers,
                track: album.coverTrack,
                groupKey: albumCoverKey(album),
                borderRadius: 12,
                placeholderIcon: Icons.album_rounded,
              ),
              if (onPlay != null)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: IconButton.filled(
                    visualDensity: VisualDensity.compact,
                    tooltip: context.l10n.libraryPlayAll,
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: onPlay,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            libraryAlbumTitle(context, album),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            libraryAlbumSubtitle(context, album),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class LibraryTrackTile extends StatelessWidget {
  final LibraryTrack track;
  final MusicCovers covers;
  final VoidCallback onTap;

  /// The track whose file the picture is read from. Defaults to [track]; pass
  /// the album's cover track so all of an album's rows share one cached read.
  final LibraryTrack? coverTrack;

  /// An album or artist key to look for a hand-chosen cover under first.
  final String? coverGroupKey;

  /// When set, replaces the cover (album views show the track number).
  final String? leadingLabel;

  /// Overrides the default "Artist — Album" line; an empty string hides it.
  final String? subtitle;

  /// Which container the track is in; shown after the subtitle when the library
  /// merges more than one.
  final String? sourceLabel;

  const LibraryTrackTile({
    super.key,
    required this.track,
    required this.covers,
    required this.onTap,
    this.coverTrack,
    this.coverGroupKey,
    this.leadingLabel,
    this.subtitle,
    this.sourceLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackgroundPlaybackSession?>(
      valueListenable: BackgroundPlaybackHost.instance.activeSession,
      builder: (context, session, _) {
        if (session == null) return _buildTile(context, isPlaying: false);
        return ListenableBuilder(
          listenable: session.playlist,
          builder: (context, _) => _buildTile(
            context,
            isPlaying:
                session.container.uri == track.source &&
                session.playlist.currentFile == track.path,
          ),
        );
      },
    );
  }

  Widget _buildTile(BuildContext context, {required bool isPlaying}) {
    final cs = context.colors;
    final duration = libraryDurationLabel(track.durationMs);
    final base = subtitle ?? libraryTrackSubtitle(context, track);
    final line = sourceLabel == null || sourceLabel!.isEmpty
        ? base
        : (base.isEmpty ? sourceLabel! : '$base · $sourceLabel');
    return ListTile(
      onTap: onTap,
      selected: isPlaying,
      selectedTileColor: isPlaying ? cs.primary.withValues(alpha: 0.17) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      leading: leadingLabel != null
          ? SizedBox(
              width: 44,
              child: Center(
                child: Text(
                  leadingLabel!,
                  style: context.typography.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : LibraryCover(
              covers: covers,
              track: coverTrack ?? track,
              groupKey: coverGroupKey,
              size: 44,
            ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: line.isEmpty
          ? null
          : Text(line, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: duration.isEmpty
          ? null
          : Text(
              duration,
              style: context.typography.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
    );
  }
}
