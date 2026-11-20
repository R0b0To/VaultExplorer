import 'dart:typed_data';

/// What the tag readers found in one audio file.
///
/// Multi-valued fields keep every value the file carried (ID3v2.4 null
/// separated strings, repeated Vorbis comments, repeated MP4 `data` atoms).
/// Splitting a single "A; B" string into several names is the index's job,
/// not the reader's.
class AudioTags {
  final String? title;
  final List<String> artists;
  final String? album;
  final List<String> albumArtists;
  final List<String> genres;

  /// 0 when unknown.
  final int year;
  final int trackNo;
  final int trackTotal;
  final int discNo;
  final int discTotal;

  /// 0 when unknown.
  final int durationMs;

  /// Whether the file carries an embedded picture.
  final bool hasCover;

  /// Short lowercase codec/container name, '' when unrecognised.
  final String format;

  const AudioTags({
    this.title,
    this.artists = const [],
    this.album,
    this.albumArtists = const [],
    this.genres = const [],
    this.year = 0,
    this.trackNo = 0,
    this.trackTotal = 0,
    this.discNo = 0,
    this.discTotal = 0,
    this.durationMs = 0,
    this.hasCover = false,
    this.format = '',
  });

  static const AudioTags empty = AudioTags();

  bool get hasAnyTag =>
      title != null ||
      artists.isNotEmpty ||
      album != null ||
      albumArtists.isNotEmpty ||
      genres.isNotEmpty ||
      year != 0 ||
      trackNo != 0;
}

/// Mutable collector the format readers fill in, then freeze with [build].
class AudioTagsBuilder {
  String? title;
  final List<String> artists = [];
  String? album;
  final List<String> albumArtists = [];
  final List<String> genres = [];
  int year = 0;
  int trackNo = 0;
  int trackTotal = 0;
  int discNo = 0;
  int discTotal = 0;
  int durationMs = 0;
  bool hasCover = false;
  String format = '';

  /// Adds [value] to [list] unless it is blank or already present.
  static void addUnique(List<String> list, String? value) {
    if (value == null) return;
    final v = value.trim();
    if (v.isEmpty) return;
    if (!list.contains(v)) list.add(v);
  }

  AudioTags build() => AudioTags(
        title: title,
        artists: List.unmodifiable(artists),
        album: album,
        albumArtists: List.unmodifiable(albumArtists),
        genres: List.unmodifiable(genres),
        year: year,
        trackNo: trackNo,
        trackTotal: trackTotal,
        discNo: discNo,
        discTotal: discTotal,
        durationMs: durationMs,
        hasCover: hasCover,
        format: format,
      );
}

/// An embedded picture pulled out of a file.
class CoverArt {
  final Uint8List bytes;

  /// `image/jpeg`, `image/png`, ... sniffed from the bytes when the tag's own
  /// type is missing or wrong.
  final String mime;

  const CoverArt(this.bytes, this.mime);
}

/// Guesses an image mime type from magic bytes, falling back to [declared].
String sniffImageMime(Uint8List b, [String declared = '']) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'image/webp';
  }
  if (b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return 'image/gif';
  }
  return declared.isEmpty ? 'application/octet-stream' : declared;
}
