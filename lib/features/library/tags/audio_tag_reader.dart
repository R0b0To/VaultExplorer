import 'dart:typed_data';

import 'package:vaultexplorer/features/library/tags/byte_source.dart';
import 'package:vaultexplorer/features/library/tags/flac_reader.dart';
import 'package:vaultexplorer/features/library/tags/id3_reader.dart';
import 'package:vaultexplorer/features/library/tags/mp3_reader.dart';
import 'package:vaultexplorer/features/library/tags/mp4_reader.dart';
import 'package:vaultexplorer/features/library/tags/ogg_reader.dart';
import 'package:vaultexplorer/features/library/tags/tag_models.dart';
import 'package:vaultexplorer/features/library/tags/tag_text.dart';

/// Thrown when a file's bytes could not be read at all, as opposed to a file
/// that was read fine and simply carries no tags.
class TagSourceException implements Exception {
  const TagSourceException();

  @override
  String toString() => 'TagSourceException: the file could not be read';
}

/// Reads tags, duration and cover art from an audio file through a
/// [ByteSource].
///
/// Supports MP3 (ID3v2.2/2.3/2.4, ID3v1, Xing/VBRI), FLAC, Ogg Vorbis, Ogg
/// Opus, MP4/M4A/M4B and WAV. Other formats come back with no tags (the
/// library falls back to the file name) and the extension as their format.
///
/// Every method walks the file's structure and fetches only what it needs, so
/// the cost per file is a few kilobytes of decrypted reads, not a megabyte.
class AudioTagReader {
  AudioTagReader._();

  /// Tags and duration for one file.
  ///
  /// Malformed data ends the walk and returns what was found so far. Throws
  /// [TagSourceException] only when the source failed before yielding a byte.
  static Future<AudioTags> read(
    ByteSource source, {
    String fileName = '',
  }) async {
    final r = BufferedReader(source);
    final b = AudioTagsBuilder();
    try {
      await _read(r, b, fileName);
    } on RangeError {
      // Truncated or corrupt structure: keep what was parsed.
    } on FormatException {
      // Same.
    }
    if (r.readFailed && r.bytesFetched == 0) throw const TagSourceException();
    if (b.format.isEmpty) b.format = _extension(fileName);
    return b.build();
  }

  /// The embedded cover picture, or null when there is none.
  static Future<CoverArt?> readCover(
    ByteSource source, {
    String fileName = '',
  }) async {
    final r = BufferedReader(source, chunkSize: 128 * 1024, maxReads: 2000);
    try {
      final id3Len = await Id3Reader.skipLength(r);
      if (id3Len > 0) {
        final art = await Id3Reader.readCover(r);
        if (art != null) return art;
      }
      if (await FlacReader.matches(r, id3Len)) {
        return await FlacReader.readCover(r, id3Len);
      }
      if (id3Len == 0 && await Mp4Reader.matches(r)) {
        return await Mp4Reader.readCover(r);
      }
      if (id3Len == 0 && await OggReader.matches(r, 0)) {
        return await OggReader.readCover(r);
      }
    } on RangeError {
      return null;
    } on FormatException {
      return null;
    }
    return null;
  }

  static Future<void> _read(
    BufferedReader r,
    AudioTagsBuilder b,
    String fileName,
  ) async {
    if (r.length < 4) return;

    final id3 = await Id3Reader.read(r, b);
    final start = id3.audioStart;

    if (await FlacReader.matches(r, start)) {
      await FlacReader.read(r, start, b);
      return;
    }
    if (!id3.found) {
      if (await Mp4Reader.matches(r)) {
        await Mp4Reader.read(r, b);
        return;
      }
      if (await OggReader.matches(r, 0)) {
        await OggReader.read(r, b);
        return;
      }
      if (await _isWave(r)) {
        await _readWave(r, b);
        return;
      }
    }

    // MPEG audio (MP3/MP2), possibly with ID3v1 at the end. The frame header
    // comes first because it is still in the read window; the trailing ID3v1
    // block lives at the far end of the file and costs a separate read, so it
    // is only fetched when it is needed: always when there is no ID3v2 tag (it
    // is then the only tag), otherwise only to refine a bitrate estimate.
    final info = await Mp3Reader.read(r, start);
    var v1 = false;
    if (!id3.found) v1 = await Id3Reader.readV1(r, b);
    if (info.foundFrame || _extension(fileName) == 'mp3') b.format = 'mp3';

    if (info.exact) {
      b.durationMs = info.durationMs;
    } else if (id3.declaredDurationMs > 0) {
      b.durationMs = id3.declaredDurationMs;
    } else if (info.foundFrame) {
      if (id3.found) v1 = await Id3Reader.readV1(r, AudioTagsBuilder());
      b.durationMs = info.estimateMs(r.length - (v1 ? 128 : 0));
    }
  }

  // ── WAV ────────────────────────────────────────────────────────────────────

  static Future<bool> _isWave(BufferedReader r) async {
    final h = await r.bytes(0, 12);
    return h != null &&
        Bytes.ascii(h, 0, 4) == 'RIFF' &&
        Bytes.ascii(h, 8, 12) == 'WAVE';
  }

  /// Walks RIFF chunks: `fmt ` (byte rate), `data` (size), `LIST`/`INFO`.
  static Future<void> _readWave(BufferedReader r, AudioTagsBuilder b) async {
    b.format = 'wav';
    var pos = 12;
    var byteRate = 0;
    var dataSize = 0;
    for (var guard = 0; guard < 64; guard++) {
      final h = await r.bytes(pos, 8);
      if (h == null) break;
      final id = Bytes.ascii(h, 0, 4);
      final size = Bytes.u32le(h, 4);
      final body = pos + 8;
      if (id == 'fmt ' && size >= 16) {
        final f = await r.bytes(body, 16);
        if (f != null) byteRate = Bytes.u32le(f, 8);
      } else if (id == 'data') {
        dataSize = (body + size > r.length) ? r.length - body : size;
      } else if (id == 'LIST' && size >= 4 && size <= 64 * 1024) {
        final l = await r.bytes(body, size);
        if (l != null && Bytes.ascii(l, 0, 4) == 'INFO') _readWaveInfo(l, b);
      }
      pos = body + size + (size & 1);
      if (pos + 8 > r.length) break;
    }
    if (byteRate > 0 && dataSize > 0) {
      b.durationMs = (dataSize * 1000) ~/ byteRate;
    }
  }

  static void _readWaveInfo(Uint8List l, AudioTagsBuilder b) {
    var p = 4;
    while (p + 8 <= l.length) {
      final id = Bytes.ascii(l, p, p + 4);
      final size = Bytes.u32le(l, p + 4);
      final s = p + 8;
      if (s + size > l.length) break;
      final text = TagText.clean(TagText.latin1(l, s, s + size));
      if (text != null) {
        switch (id) {
          case 'INAM':
            b.title ??= text;
          case 'IART':
            AudioTagsBuilder.addUnique(b.artists, text);
          case 'IPRD':
            b.album ??= text;
          case 'IGNR':
            AudioTagsBuilder.addUnique(b.genres, TagText.genre(text));
          case 'ICRD':
            if (b.year == 0) b.year = TagText.year(text);
          case 'ITRK':
            if (b.trackNo == 0) b.trackNo = TagText.leadingInt(text);
        }
      }
      p = s + size + (size & 1);
    }
  }

  static String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}
