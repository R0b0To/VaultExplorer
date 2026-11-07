import 'dart:typed_data';

import 'package:vaultexplorer/features/library/tags/byte_source.dart';

/// Duration facts about an MPEG audio stream.
class Mp3Info {
  /// Duration from a frame count (Xing/Info/VBRI header), 0 when there is none.
  final int durationMs;

  /// True when [durationMs] comes from a frame count.
  final bool exact;

  /// Where the first audio frame starts, and its bitrate in bits per second;
  /// 0 when no frame was found. With these a constant-bitrate duration can be
  /// estimated later, once the end of the audio is known ([estimateMs]).
  final int firstFrameOffset;
  final int bitrate;

  const Mp3Info(
    this.durationMs, {
    required this.exact,
    this.firstFrameOffset = 0,
    this.bitrate = 0,
  });

  static const Mp3Info unknown = Mp3Info(0, exact: false);

  /// Whether a valid MPEG frame was found.
  bool get foundFrame => bitrate > 0;

  /// Constant-bitrate estimate for audio that ends at [audioEnd] (the file
  /// length, minus a trailing ID3v1 block if there is one).
  int estimateMs(int audioEnd) {
    if (bitrate <= 0 || audioEnd <= firstFrameOffset) return 0;
    return ((audioEnd - firstFrameOffset) * 8 * 1000) ~/ bitrate;
  }
}

class _FrameHeader {
  final int version; // 1 = MPEG-1, 2 = MPEG-2, 25 = MPEG-2.5
  final int layer; // 1..3
  final int bitrate; // bits per second
  final int sampleRate;
  final int padding;
  final bool protectedByCrc;
  final bool mono;

  const _FrameHeader({
    required this.version,
    required this.layer,
    required this.bitrate,
    required this.sampleRate,
    required this.padding,
    required this.protectedByCrc,
    required this.mono,
  });

  int get samplesPerFrame {
    if (layer == 1) return 384;
    if (layer == 2) return 1152;
    return version == 1 ? 1152 : 576;
  }

  int get frameLength {
    if (layer == 1) return ((12 * bitrate ~/ sampleRate) + padding) * 4;
    final coef = (layer == 3 && version != 1) ? 72 : 144;
    return (coef * bitrate ~/ sampleRate) + padding;
  }

  int get sideInfoLength {
    if (version == 1) return mono ? 17 : 32;
    return mono ? 9 : 17;
  }
}

/// Finds the first MPEG audio frame and derives the stream duration.
class Mp3Reader {
  Mp3Reader._();

  static const _bitratesV1L1 = [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448];
  static const _bitratesV1L2 = [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384];
  static const _bitratesV1L3 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
  static const _bitratesV2L1 = [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256];
  static const _bitratesV2L23 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];

  static const _sampleRatesV1 = [44100, 48000, 32000];
  static const _sampleRatesV2 = [22050, 24000, 16000];
  static const _sampleRatesV25 = [11025, 12000, 8000];

  /// How far past [audioStart] to look for the first frame (junk, padding).
  static const int _syncSearchWindow = 16 * 1024;

  /// Whether the bytes at [offset] look like an MPEG audio frame header.
  static bool looksLikeFrame(Uint8List b, int offset) =>
      _parseHeader(b, offset) != null;

  static _FrameHeader? _parseHeader(Uint8List b, int o) {
    if (o + 4 > b.length) return null;
    if (b[o] != 0xFF || (b[o + 1] & 0xE0) != 0xE0) return null;
    final versionBits = (b[o + 1] >> 3) & 3;
    final layerBits = (b[o + 1] >> 1) & 3;
    if (versionBits == 1 || layerBits == 0) return null;
    final bitrateIdx = b[o + 2] >> 4;
    final srIdx = (b[o + 2] >> 2) & 3;
    if (bitrateIdx == 0 || bitrateIdx == 15 || srIdx == 3) return null;

    final version = versionBits == 3 ? 1 : (versionBits == 2 ? 2 : 25);
    final layer = 4 - layerBits;
    final List<int> table;
    if (version == 1) {
      table = layer == 1
          ? _bitratesV1L1
          : (layer == 2 ? _bitratesV1L2 : _bitratesV1L3);
    } else {
      table = layer == 1 ? _bitratesV2L1 : _bitratesV2L23;
    }
    final sr = version == 1
        ? _sampleRatesV1[srIdx]
        : (version == 2 ? _sampleRatesV2[srIdx] : _sampleRatesV25[srIdx]);
    return _FrameHeader(
      version: version,
      layer: layer,
      bitrate: table[bitrateIdx] * 1000,
      sampleRate: sr,
      padding: (b[o + 2] >> 1) & 1,
      protectedByCrc: (b[o + 1] & 1) == 0,
      mono: ((b[o + 3] >> 6) & 3) == 3,
    );
  }

  /// Finds the first MPEG frame at or after [audioStart] and reads its
  /// Xing/Info/VBRI header if it has one.
  ///
  /// This reads only from the window near [audioStart]; it never needs the end
  /// of the file, so a caller can skip looking for a trailing ID3v1 block when
  /// the duration comes out exact.
  static Future<Mp3Info> read(BufferedReader r, int audioStart) async {
    if (audioStart >= r.length) return Mp3Info.unknown;
    final window = (r.length - audioStart).clamp(0, _syncSearchWindow);
    final buf = await r.bytes(audioStart, window);
    if (buf == null) return Mp3Info.unknown;

    for (var i = 0; i + 4 <= buf.length; i++) {
      if (buf[i] != 0xFF) continue;
      final h = _parseHeader(buf, i);
      if (h == null) continue;
      // A real frame is followed by another one; this rules out stray 0xFFE.
      final next = i + h.frameLength;
      if (next + 4 <= buf.length && _parseHeader(buf, next) == null) continue;

      final firstFrameAt = audioStart + i;
      final frames = _framesFromVbrHeader(buf, i, h);
      final exactMs =
          frames > 0 ? (frames * h.samplesPerFrame * 1000) ~/ h.sampleRate : 0;
      return Mp3Info(
        exactMs,
        exact: exactMs > 0,
        firstFrameOffset: firstFrameAt,
        bitrate: h.bitrate,
      );
    }
    return Mp3Info.unknown;
  }

  /// Frame count from a Xing/Info or VBRI header in the first frame, else 0.
  static int _framesFromVbrHeader(Uint8List b, int frameAt, _FrameHeader h) {
    final xing = frameAt + 4 + (h.protectedByCrc ? 2 : 0) + h.sideInfoLength;
    if (xing + 12 <= b.length) {
      final tag = Bytes.ascii(b, xing, xing + 4);
      if (tag == 'Xing' || tag == 'Info') {
        final flags = Bytes.u32be(b, xing + 4);
        if (flags & 1 != 0) return Bytes.u32be(b, xing + 8);
      }
    }
    final vbri = frameAt + 4 + 32;
    if (vbri + 18 <= b.length && Bytes.ascii(b, vbri, vbri + 4) == 'VBRI') {
      return Bytes.u32be(b, vbri + 14);
    }
    return 0;
  }
}
