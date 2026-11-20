import 'dart:convert';
import 'dart:typed_data';

import 'package:vaultexplorer/features/library/tags/byte_source.dart';
import 'package:vaultexplorer/features/library/tags/flac_reader.dart';
import 'package:vaultexplorer/features/library/tags/tag_models.dart';
import 'package:vaultexplorer/features/library/tags/tag_text.dart';
import 'package:vaultexplorer/features/library/tags/vorbis_comments.dart';

enum _Kind { unknown, vorbis, opus }

class _OggHeaders {
  final _Kind kind;
  final int sampleRate;
  final int preSkip;

  /// The comment packet after its 7/8 byte marker, possibly cut at the cap.
  final Uint8List comments;

  const _OggHeaders(this.kind, this.sampleRate, this.preSkip, this.comments);
}

/// Reads Ogg Vorbis and Ogg Opus: the identification header (sample rate), the
/// comment header (tags), and the last page's granule position (duration).
class OggReader {
  OggReader._();

  /// Cap on the comment packet assembled for tags. A cover embedded as a
  /// base64 METADATA_BLOCK_PICTURE can run to megabytes; tags before it still
  /// parse, and the picture is noted by its key.
  static const int _tagPacketCap = 256 * 1024;
  static const int _coverPacketCap = 16 * 1024 * 1024;

  /// Largest legal Ogg page (27 + 255 + 255 * 255).
  static const int _maxPageSize = 65307;

  static const _oggS = [0x4F, 0x67, 0x67, 0x53];

  static Future<bool> matches(BufferedReader r, int offset) async {
    final m = await r.bytes(offset, 4);
    return m != null && Bytes.startsWith(m, 0, _oggS);
  }

  static Future<void> read(BufferedReader r, AudioTagsBuilder b) async {
    final h = await _readHeaders(r, _tagPacketCap);
    if (h == null) return;
    b.format = h.kind == _Kind.opus ? 'opus' : 'ogg';
    VorbisComments.parse(h.comments, 0, h.comments.length, b);
    await _readDuration(r, b, h);
  }

  /// The embedded picture (a base64 FLAC PICTURE block in a
  /// METADATA_BLOCK_PICTURE comment), or null.
  static Future<CoverArt?> readCover(BufferedReader r) async {
    final h = await _readHeaders(r, _coverPacketCap);
    if (h == null) return null;
    final d = h.comments;
    var p = 0;
    if (p + 4 > d.length) return null;
    p += 4 + Bytes.u32le(d, p);
    if (p + 4 > d.length) return null;
    final count = Bytes.u32le(d, p);
    p += 4;

    CoverArt? fallback;
    const key = 'METADATA_BLOCK_PICTURE=';
    for (var i = 0; i < count; i++) {
      if (p + 4 > d.length) break;
      final len = Bytes.u32le(d, p);
      p += 4;
      if (len > d.length - p) break;
      if (len > key.length &&
          TagText.latin1(d, p, p + key.length).toUpperCase() == key) {
        try {
          final b64 = TagText.latin1(d, p + key.length, p + len);
          final pic = FlacReader.parsePictureBlock(base64.decode(b64));
          if (pic != null) {
            if (pic.$1 == 3) return pic.$2;
            fallback ??= pic.$2;
          }
        } catch (_) {
          // A malformed picture comment is skipped; other comments still count.
        }
      }
      p += len;
    }
    return fallback;
  }

  /// Walks the first pages, returning the stream kind, rate and comment packet.
  static Future<_OggHeaders?> _readHeaders(BufferedReader r, int cap) async {
    var pos = 0;
    var packetIndex = 0;
    var kind = _Kind.unknown;
    var sampleRate = 0;
    var preSkip = 0;

    final current = BytesBuilder(copy: false);
    var currentLen = 0;
    var truncated = false;

    Uint8List finish() {
      final data = current.takeBytes();
      current.clear();
      currentLen = 0;
      truncated = false;
      return data;
    }

    for (var page = 0; page < 600 && packetIndex < 2; page++) {
      final ph = await r.bytes(pos, 27);
      if (ph == null || !Bytes.startsWith(ph, 0, _oggS)) return null;
      final segCount = ph[26];
      final segs = await r.bytes(pos + 27, segCount);
      if (segs == null) return null;
      var bodyLen = 0;
      for (final s in segs) {
        bodyLen += s;
      }
      final bodyStart = pos + 27 + segCount;
      final body = await r.bytes(bodyStart, bodyLen);
      if (body == null) return null;

      var segOffset = 0;
      for (var i = 0; i < segCount && packetIndex < 2; i++) {
        final segLen = segs[i];
        if (!truncated) {
          final room = cap - currentLen;
          final take = segLen < room ? segLen : room;
          if (take > 0) {
            current.add(Uint8List.sublistView(body, segOffset, segOffset + take));
            currentLen += take;
          }
          if (take < segLen) truncated = true;
        }
        segOffset += segLen;

        final packetEnds = segLen < 255;
        if (packetEnds || (truncated && packetIndex == 1)) {
          final data = finish();
          if (packetIndex == 0) {
            final id = _identify(data);
            if (id.kind == _Kind.unknown) return null;
            kind = id.kind;
            sampleRate = id.sampleRate;
            preSkip = id.preSkip;
          } else {
            final headerLen = kind == _Kind.opus ? 8 : 7;
            final comments = data.length > headerLen
                ? Uint8List.sublistView(data, headerLen)
                : Uint8List(0);
            return _OggHeaders(kind, sampleRate, preSkip, comments);
          }
          packetIndex++;
          if (!packetEnds) break;
        }
      }
      pos = bodyStart + bodyLen;
    }
    return null;
  }

  static Future<void> _readDuration(
    BufferedReader r,
    AudioTagsBuilder b,
    _OggHeaders h,
  ) async {
    if (h.sampleRate <= 0) return;
    final tail = await r.tail(_maxPageSize);
    if (tail == null) return;
    for (var i = tail.length - 27; i >= 0; i--) {
      if (tail[i] != 0x4F || !Bytes.startsWith(tail, i, _oggS)) continue;
      final granule = Bytes.u64le(tail, i + 6);
      // 0xFFFFFFFFFFFFFFFF ("no packet finishes on this page") reads as -1.
      if (granule <= 0) continue;
      final samples = h.kind == _Kind.opus ? granule - h.preSkip : granule;
      if (samples <= 0) return;
      b.durationMs = (samples * 1000) ~/ h.sampleRate;
      return;
    }
  }

  static ({_Kind kind, int sampleRate, int preSkip}) _identify(Uint8List d) {
    if (d.length >= 30 && d[0] == 0x01 && Bytes.ascii(d, 1, 7) == 'vorbis') {
      return (kind: _Kind.vorbis, sampleRate: Bytes.u32le(d, 12), preSkip: 0);
    }
    if (d.length >= 19 && Bytes.ascii(d, 0, 8) == 'OpusHead') {
      // Opus always decodes at 48 kHz; the header's rate is the input rate.
      return (kind: _Kind.opus, sampleRate: 48000, preSkip: Bytes.u16le(d, 10));
    }
    return (kind: _Kind.unknown, sampleRate: 0, preSkip: 0);
  }
}
