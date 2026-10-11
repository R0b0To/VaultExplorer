import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/audio_metadata_parser.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_sheet.dart'
    show MetadataParser;

Uint8List _be32(int v) =>
    Uint8List.fromList([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);

Uint8List _le32(int v) =>
    Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

Uint8List _syncsafe(int v) => Uint8List.fromList([
  (v >> 21) & 0x7F,
  (v >> 14) & 0x7F,
  (v >> 7) & 0x7F,
  v & 0x7F,
]);

Uint8List _id3v23(Map<String, String> frames) {
  final body = BytesBuilder();
  frames.forEach((id, text) {
    final data = [0, ...ascii.encode(text)]; // encoding 0 = ISO-8859-1
    body
      ..add(ascii.encode(id))
      ..add(_be32(data.length))
      ..add([0, 0])
      ..add(data);
  });
  final payload = body.toBytes();
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    3,
    0,
    0,
    ..._syncsafe(payload.length),
    ...payload,
  ]);
}

Uint8List _flac({required int bitsPerSample, required List<String> comments}) {
  final streamInfo = Uint8List(34);
  final v = bitsPerSample - 1;
  streamInfo[12] = (v >> 4) & 0x01;
  streamInfo[13] = (v & 0x0F) << 4;

  final vorbis = BytesBuilder()
    ..add(_le32(1))
    ..add(ascii.encode('x'))
    ..add(_le32(comments.length));
  for (final c in comments) {
    final bytes = utf8.encode(c);
    vorbis
      ..add(_le32(bytes.length))
      ..add(bytes);
  }
  final vorbisBytes = vorbis.toBytes();

  return Uint8List.fromList([
    ...ascii.encode('fLaC'),
    0x00, 0, 0, 34, ...streamInfo, // STREAMINFO, not last
    0x84, // VORBIS_COMMENT, last
    (vorbisBytes.length >> 16) & 0xFF,
    (vorbisBytes.length >> 8) & 0xFF,
    vorbisBytes.length & 0xFF,
    ...vorbisBytes,
  ]);
}

Uint8List _wav({required int bits}) => Uint8List.fromList([
  ...ascii.encode('RIFF'),
  ..._le32(36),
  ...ascii.encode('WAVE'),
  ...ascii.encode('fmt '),
  ..._le32(16),
  1, 0, // PCM
  2, 0, // channels
  ..._le32(44100),
  ..._le32(44100 * 2 * (bits ~/ 8)),
  4, 0, // block align
  bits & 0xFF, (bits >> 8) & 0xFF,
]);

Uint8List _png({required int colorType, bool animated = false}) {
  final ihdr = [
    ..._be32(4), // width
    ..._be32(3), // height
    8, // bit depth
    colorType,
    0, 0, 0,
  ];
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ..._be32(13), ...ascii.encode('IHDR'), ...ihdr, 0, 0, 0, 0,
    if (animated) ...[
      ..._be32(8), ...ascii.encode('acTL'), ..._be32(2), ..._be32(0), 0, 0, 0, 0,
    ],
    ..._be32(0), ...ascii.encode('IDAT'),
  ]);
}

Uint8List _gif({required int frames}) {
  final out = <int>[
    ...ascii.encode('GIF89a'),
    2, 0, 2, 0, // 2x2
    0x00, 0, 0, // no global palette
  ];
  for (var i = 0; i < frames; i++) {
    out.addAll([0x2C, 0, 0, 0, 0, 2, 0, 2, 0, 0x00]); // image descriptor
    out.addAll([2, 1, 0x00, 0]); // LZW min size, one sub-block, terminator
  }
  out.add(0x3B);
  return Uint8List.fromList(out);
}

Uint8List _webpLossless({required int w, required int h, required bool alpha}) {
  final bits = (w - 1) | ((h - 1) << 14) | ((alpha ? 1 : 0) << 28);
  return Uint8List.fromList([
    ...ascii.encode('RIFF'),
    ..._le32(40),
    ...ascii.encode('WEBP'),
    ...ascii.encode('VP8L'),
    ..._le32(10),
    0x2F,
    ..._le32(bits),
    ...List.filled(12, 0),
  ]);
}

void main() {
  group('AudioMetadataParser', () {
    test('reads ID3v2.3 text frames', () {
      final tags = AudioMetadataParser.parse(
        _id3v23({
          'TIT2': 'Song',
          'TPE1': 'Band',
          'TALB': 'Record',
          'TYER': '2019',
          'TCON': '(17)Rock',
          'TRCK': '3/12',
        }),
      );
      expect(tags.title, 'Song');
      expect(tags.artist, 'Band');
      expect(tags.album, 'Record');
      expect(tags.year, '2019');
      expect(tags.genre, 'Rock');
      expect(tags.trackNumber, '3/12');
      expect(tags.hasTags, isTrue);
    });

    test('drops a bare numeric ID3 genre', () {
      final tags = AudioMetadataParser.parse(
        _id3v23({'TIT2': 'Song', 'TCON': '17'}),
      );
      expect(tags.genre, isNull);
      expect(tags.title, 'Song');
    });

    test('reads FLAC bit depth and Vorbis comments', () {
      final tags = AudioMetadataParser.parse(
        _flac(
          bitsPerSample: 24,
          comments: ['TITLE=Flac Song', 'artist=Flac Band', 'DATE=2020-01-02'],
        ),
      );
      expect(tags.bitDepth, 24);
      expect(tags.title, 'Flac Song');
      expect(tags.artist, 'Flac Band');
      expect(tags.year, '2020');
    });

    test('reads WAV bit depth', () {
      final tags = AudioMetadataParser.parse(_wav(bits: 24));
      expect(tags.bitDepth, 24);
      expect(tags.hasTags, isFalse);
    });

    test('returns empty metadata for unknown or truncated data', () {
      expect(AudioMetadataParser.parse(Uint8List(0)).hasTags, isFalse);
      expect(
        AudioMetadataParser.parse(Uint8List.fromList(List.filled(64, 7))).hasTags,
        isFalse,
      );
      final truncated = _id3v23({'TIT2': 'Song'}).sublist(0, 14);
      expect(AudioMetadataParser.parse(truncated).title, isNull);
    });
  });

  group('MetadataParser (image details)', () {
    test('PNG RGBA reports colour mode, depth and transparency', () {
      final m = MetadataParser.parse(
        fileName: 'a.png',
        isDir: false,
        headerBytes: _png(colorType: 6),
      );
      expect(m.width, 4);
      expect(m.height, 3);
      expect(m.colorMode, 'RGBA');
      expect(m.bitDepth, '8-bit');
      expect(m.hasAlpha, isTrue);
      expect(m.isAnimated, isFalse);
      expect(m.encoding, 'Non-interlaced');
    });

    test('PNG RGB has no transparency and APNG is flagged animated', () {
      final still = MetadataParser.parse(
        fileName: 'a.png',
        isDir: false,
        headerBytes: _png(colorType: 2),
      );
      expect(still.hasAlpha, isFalse);
      expect(still.isAnimated, isFalse);

      final apng = MetadataParser.parse(
        fileName: 'a.png',
        isDir: false,
        headerBytes: _png(colorType: 6, animated: true),
      );
      expect(apng.isAnimated, isTrue);
    });

    test('GIF counts frames to decide whether it is animated', () {
      final one = MetadataParser.parse(
        fileName: 'a.gif',
        isDir: false,
        headerBytes: _gif(frames: 1),
      );
      expect(one.isAnimated, isFalse);
      expect(one.encoding, 'GIF89a');

      final many = MetadataParser.parse(
        fileName: 'a.gif',
        isDir: false,
        headerBytes: _gif(frames: 3),
      );
      expect(many.isAnimated, isTrue);
    });

    test('detects the format from bytes, not the file extension', () {
      // A PNG saved as .jpg and a GIF saved as .png must still parse.
      final png = MetadataParser.parse(
        fileName: 'wrong.jpg',
        isDir: false,
        headerBytes: _png(colorType: 6),
      );
      expect(png.mimeType, 'PNG Image');
      expect(png.width, 4);

      final gif = MetadataParser.parse(
        fileName: 'wrong.png',
        isDir: false,
        headerBytes: _gif(frames: 2),
      );
      expect(gif.mimeType, 'GIF Image');
      expect(gif.isAnimated, isTrue);
    });

    test('lossless WebP now yields dimensions and alpha', () {
      final m = MetadataParser.parse(
        fileName: 'a.webp',
        isDir: false,
        headerBytes: _webpLossless(w: 321, h: 67, alpha: true),
      );
      expect(m.width, 321);
      expect(m.height, 67);
      expect(m.hasAlpha, isTrue);
      expect(m.encoding, 'Lossless');
    });
  });
}
