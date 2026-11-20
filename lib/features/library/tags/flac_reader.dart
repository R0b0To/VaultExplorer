import 'dart:typed_data';

import 'package:vaultexplorer/features/library/tags/byte_source.dart';
import 'package:vaultexplorer/features/library/tags/tag_models.dart';
import 'package:vaultexplorer/features/library/tags/tag_text.dart';
import 'package:vaultexplorer/features/library/tags/vorbis_comments.dart';

/// Reads FLAC metadata blocks without touching the audio frames.
///
/// Walks the block headers (4 bytes each) and reads only the blocks it needs:
/// STREAMINFO for the exact duration, VORBIS_COMMENT for the tags. A PICTURE
/// block is noted and jumped over, so a multi-megabyte cover costs nothing at
/// index time.
class FlacReader {
  FlacReader._();

  /// Cap on a single VORBIS_COMMENT block we will read whole.
  static const int _maxCommentBytes = 1024 * 1024;

  static const int _typeStreamInfo = 0;
  static const int _typeVorbisComment = 4;
  static const int _typePicture = 6;

  /// True when `fLaC` sits at [offset] (after any ID3v2 tag).
  static Future<bool> matches(BufferedReader r, int offset) async {
    final magic = await r.bytes(offset, 4);
    return magic != null && Bytes.startsWith(magic, 0, const [0x66, 0x4C, 0x61, 0x43]);
  }

  static Future<void> read(
    BufferedReader r,
    int offset,
    AudioTagsBuilder b,
  ) async {
    b.format = 'flac';
    var pos = offset + 4;
    for (var guard = 0; guard < 64; guard++) {
      final h = await r.bytes(pos, 4);
      if (h == null) return;
      final isLast = (h[0] & 0x80) != 0;
      final type = h[0] & 0x7F;
      final len = Bytes.u24be(h, 1);
      final body = pos + 4;

      if (type == _typeStreamInfo && len >= 18) {
        final si = await r.bytes(body, 18);
        if (si != null) {
          final sampleRate = (si[10] << 12) | (si[11] << 4) | (si[12] >> 4);
          final totalSamples = ((si[13] & 0x0F) * 0x100000000) +
              Bytes.u32be(si, 14);
          if (sampleRate > 0 && totalSamples > 0) {
            b.durationMs = (totalSamples * 1000) ~/ sampleRate;
          }
        }
      } else if (type == _typeVorbisComment) {
        if (len > 0 && len <= _maxCommentBytes) {
          final data = await r.bytes(body, len);
          if (data != null) VorbisComments.parse(data, 0, data.length, b);
        }
      } else if (type == _typePicture) {
        b.hasCover = true;
      }

      if (isLast) return;
      pos = body + len;
      if (pos >= r.length) return;
    }
  }

  /// The best embedded picture (front cover preferred), or null.
  static Future<CoverArt?> readCover(BufferedReader r, int offset) async {
    var pos = offset + 4;
    CoverArt? fallback;
    for (var guard = 0; guard < 64; guard++) {
      final h = await r.bytes(pos, 4);
      if (h == null) return fallback;
      final isLast = (h[0] & 0x80) != 0;
      final type = h[0] & 0x7F;
      final len = Bytes.u24be(h, 1);
      final body = pos + 4;

      if (type == _typePicture && len > 32 && len <= _maxPictureBytes) {
        final data = await r.bytes(body, len);
        final pic = data == null ? null : parsePictureBlock(data);
        if (pic != null) {
          if (pic.$1 == 3) return pic.$2;
          fallback ??= pic.$2;
        }
      }
      if (isLast) return fallback;
      pos = body + len;
      if (pos >= r.length) return fallback;
    }
    return fallback;
  }

  static const int _maxPictureBytes = 16 * 1024 * 1024;

  /// Parses a FLAC PICTURE block (also the payload of Ogg's
  /// METADATA_BLOCK_PICTURE). Returns (pictureType, art) or null.
  static (int, CoverArt)? parsePictureBlock(Uint8List d) {
    try {
      var p = 0;
      if (d.length < 32) return null;
      final picType = Bytes.u32be(d, p);
      p += 4;
      final mimeLen = Bytes.u32be(d, p);
      p += 4;
      if (p + mimeLen > d.length) return null;
      final declared = TagText.latin1(d, p, p + mimeLen);
      p += mimeLen;
      if (p + 4 > d.length) return null;
      final descLen = Bytes.u32be(d, p);
      p += 4 + descLen;
      p += 16; // width, height, depth, colours
      if (p + 4 > d.length) return null;
      final dataLen = Bytes.u32be(d, p);
      p += 4;
      if (dataLen <= 0 || p + dataLen > d.length) return null;
      final img = Uint8List.sublistView(d, p, p + dataLen);
      return (picType, CoverArt(img, sniffImageMime(img, declared)));
    } catch (_) {
      return null;
    }
  }
}
