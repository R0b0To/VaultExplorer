import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';
import 'package:vaultexplorer/features/library/widgets/library_widgets.dart'
    show albumCoverKey;

/// What the mini bar and the player show for the track that is playing: tags
/// and cover from the library when the file is in it, the file name otherwise.
class NowPlayingInfo {
  final String path;
  final LibraryTrack? track;
  final String title;
  final String artist;
  final String album;

  /// The track whose picture to draw: the album's, so every track of an album
  /// shares one cached read.
  final LibraryTrack? coverTrack;

  /// Key of a cover chosen by hand for the album, if the track has one.
  final String? coverKey;

  const NowPlayingInfo({
    required this.path,
    required this.track,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverTrack,
    required this.coverKey,
  });

  factory NowPlayingInfo.resolve(
    MusicHub hub,
    BackgroundPlaybackSession session,
    String path,
  ) {
    final track = hub.index.trackForKey('${session.container.uri}\u0000$path');
    final fileName = path.contains('/')
        ? path.substring(path.lastIndexOf('/') + 1)
        : path;
    final album = track == null ? null : hub.index.albumOf(track);
    return NowPlayingInfo(
      path: path,
      track: track,
      title: track?.title ?? LibraryTrack.titleFromFileName(fileName),
      artist: track == null || track.artists.isEmpty
          ? ''
          : track.artists.join(', '),
      album: track?.album ?? '',
      coverTrack: album?.coverTrack ?? track,
      coverKey: album == null ? null : albumCoverKey(album),
    );
  }
}
