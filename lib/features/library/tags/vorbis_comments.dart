import 'dart:typed_data';

import 'package:vaultexplorer/features/library/tags/byte_source.dart';
import 'package:vaultexplorer/features/library/tags/tag_models.dart';
import 'package:vaultexplorer/features/library/tags/tag_text.dart';

/// Parser for the Vorbis comment structure used by FLAC, Ogg Vorbis and Opus:
/// `u32 vendorLen, vendor, u32 count, (u32 len, "KEY=value") * count`, all
/// little-endian.
class VorbisComments {
  VorbisComments._();

  /// Fills [b] from the comments in `data[start, end)`.
  ///
  /// Tolerates truncation: a comment that runs past [end] (a huge embedded
  /// picture cut off by the caller's read cap) ends the walk, and a
  /// `METADATA_BLOCK_PICTURE` key seen at the cut still counts as a cover.
  static void parse(Uint8List data, int start, int end, AudioTagsBuilder b) {
    var p = start;
    if (p + 4 > end) return;
    final vendorLen = Bytes.u32le(data, p);
    p += 4 + vendorLen;
    if (p + 4 > end) return;
    final count = Bytes.u32le(data, p);
    p += 4;

    for (var i = 0; i < count; i++) {
      if (p + 4 > end) return;
      final len = Bytes.u32le(data, p);
      p += 4;
      final available = end - p;
      if (len > available) {
        _noteTruncated(data, p, end, b);
        return;
      }
      _apply(data, p, p + len, b);
      p += len;
    }
  }

  static void _noteTruncated(
    Uint8List data,
    int start,
    int end,
    AudioTagsBuilder b,
  ) {
    final probe = TagText.latin1(data, start, (start + 24).clamp(start, end));
    if (probe.toUpperCase().startsWith('METADATA_BLOCK_PICTURE=')) {
      b.hasCover = true;
    }
  }

  static void _apply(Uint8List data, int start, int end, AudioTagsBuilder b) {
    var eq = -1;
    for (var i = start; i < end; i++) {
      if (data[i] == 0x3D) {
        eq = i;
        break;
      }
    }
    if (eq <= start) return;
    final key = TagText.latin1(data, start, eq).toUpperCase();
    if (key == 'METADATA_BLOCK_PICTURE') {
      b.hasCover = true;
      return;
    }
    final value = TagText.clean(TagText.utf8Lenient(data, eq + 1, end));
    if (value == null) return;

    switch (key) {
      case 'TITLE':
        b.title ??= value;
      case 'ARTIST':
        AudioTagsBuilder.addUnique(b.artists, value);
      case 'ALBUM':
        b.album ??= value;
      case 'ALBUMARTIST':
      case 'ALBUM ARTIST':
      case 'ALBUM_ARTIST':
        AudioTagsBuilder.addUnique(b.albumArtists, value);
      case 'GENRE':
        AudioTagsBuilder.addUnique(b.genres, TagText.genre(value));
      case 'DATE':
      case 'YEAR':
      case 'ORIGINALDATE':
        if (b.year == 0) b.year = TagText.year(value);
      case 'TRACKNUMBER':
      case 'TRACK':
        final (n, total) = TagText.numberPair(value);
        if (b.trackNo == 0) b.trackNo = n;
        if (b.trackTotal == 0) b.trackTotal = total;
      case 'TRACKTOTAL':
      case 'TOTALTRACKS':
        if (b.trackTotal == 0) b.trackTotal = TagText.leadingInt(value);
      case 'DISCNUMBER':
      case 'DISC':
        final (n, total) = TagText.numberPair(value);
        if (b.discNo == 0) b.discNo = n;
        if (b.discTotal == 0) b.discTotal = total;
      case 'DISCTOTAL':
      case 'TOTALDISCS':
        if (b.discTotal == 0) b.discTotal = TagText.leadingInt(value);
    }
  }
}
