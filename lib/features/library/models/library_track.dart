import 'package:vaultexplorer/features/library/tags/tag_models.dart';

/// One indexed audio file.
///
/// [path] is relative to the container root, the same form the file browser
/// and the media viewer use, so a track can be handed straight to the player.
/// [size] and [modifiedSecs] are what the file looked like when its tags were
/// read; a later scan re-reads the file only when either changes.
class LibraryTrack {
  final String path;
  final int size;
  final int modifiedSecs;

  /// Which container the file lives in (its `uri`), empty for an index that
  /// holds a single container's tracks. Not saved with the index: a container's
  /// own file only ever holds its own tracks. It is set in memory so that
  /// several containers' tracks can be merged without their relative paths
  /// colliding (two vaults can both have "Music/a.mp3").
  final String source;

  final String title;
  final List<String> artists;
  final String album;
  final List<String> albumArtists;
  final List<String> genres;

  /// 0 when unknown.
  final int year;
  final int trackNo;
  final int discNo;
  final int durationMs;
  final bool hasCover;
  final String format;

  const LibraryTrack({
    required this.path,
    required this.size,
    required this.modifiedSecs,
    this.source = '',
    required this.title,
    this.artists = const [],
    this.album = '',
    this.albumArtists = const [],
    this.genres = const [],
    this.year = 0,
    this.trackNo = 0,
    this.discNo = 0,
    this.durationMs = 0,
    this.hasCover = false,
    this.format = '',
  });

  /// Builds a track from what the readers found. A file with no title tag is
  /// titled after its file name (extension and a leading track number
  /// stripped), so it still shows up sensibly.
  factory LibraryTrack.fromTags({
    required String path,
    required int size,
    required int modifiedSecs,
    required AudioTags tags,
  }) {
    final fileName = path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;
    return LibraryTrack(
      path: path,
      size: size,
      modifiedSecs: modifiedSecs,
      title: tags.title ?? titleFromFileName(fileName),
      artists: tags.artists,
      album: tags.album ?? '',
      albumArtists: tags.albumArtists,
      genres: tags.genres,
      year: tags.year,
      trackNo: tags.trackNo,
      discNo: tags.discNo,
      durationMs: tags.durationMs,
      hasCover: tags.hasCover,
      format: tags.format,
    );
  }

  /// "03 - Some Song.mp3" -> "Some Song".
  static String titleFromFileName(String fileName) {
    var s = fileName;
    final dot = s.lastIndexOf('.');
    if (dot > 0) s = s.substring(0, dot);
    s = s.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-._)]\s*'), '').trim();
    return s.isEmpty ? fileName : s;
  }

  /// Identity across containers: the path alone is only unique inside one.
  String get key => source.isEmpty ? path : '$source\u0000$path';

  String get fileName =>
      path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;

  /// This track tagged as belonging to [source].
  LibraryTrack withSource(String source) => LibraryTrack(
        path: path,
        size: size,
        modifiedSecs: modifiedSecs,
        source: source,
        title: title,
        artists: artists,
        album: album,
        albumArtists: albumArtists,
        genres: genres,
        year: year,
        trackNo: trackNo,
        discNo: discNo,
        durationMs: durationMs,
        hasCover: hasCover,
        format: format,
      );

  /// The folder holding the file, '' for the container root.
  String get folder =>
      path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

  /// True when the file still matches what was indexed.
  bool isCurrentFor({required int size, required int modifiedSecs}) =>
      this.size == size && this.modifiedSecs == modifiedSecs;

  // Positional JSON keeps a 50k-track index small; the order below is the
  // format, so changing it means bumping LibraryIndexCodec.version.
  List<Object> toJson() => [
        path,
        size,
        modifiedSecs,
        title,
        artists,
        album,
        albumArtists,
        genres,
        year,
        trackNo,
        discNo,
        durationMs,
        hasCover ? 1 : 0,
        format,
      ];

  /// Throws [FormatException] when [json] is not a track row.
  factory LibraryTrack.fromJson(Object? json) {
    if (json is! List || json.length != 14) {
      throw const FormatException('bad track row');
    }
    String str(int i) {
      final v = json[i];
      if (v is! String) throw FormatException('bad string at $i');
      return v;
    }

    int num_(int i) {
      final v = json[i];
      if (v is! int) throw FormatException('bad int at $i');
      return v;
    }

    List<String> strs(int i) {
      final v = json[i];
      if (v is! List) throw FormatException('bad list at $i');
      return List.unmodifiable(v.map((e) {
        if (e is! String) throw FormatException('bad list item at $i');
        return e;
      }));
    }

    return LibraryTrack(
      path: str(0),
      size: num_(1),
      modifiedSecs: num_(2),
      title: str(3),
      artists: strs(4),
      album: str(5),
      albumArtists: strs(6),
      genres: strs(7),
      year: num_(8),
      trackNo: num_(9),
      discNo: num_(10),
      durationMs: num_(11),
      hasCover: num_(12) != 0,
      format: str(13),
    );
  }
}
