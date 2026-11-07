import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/library/tags/audio_tag_reader.dart';
import 'package:vaultexplorer/features/library/tags/byte_source.dart';

/// Fixtures are 2 second clips written by ffmpeg (mp3 ID3v2.3/2.4, flac, ogg,
/// opus, m4a, wav) and mutagen (ID3v1-only, multi-value UTF-8, UTF-16, Ogg
/// cover). The tag values mirror what was written into them.
Uint8List _fixture(String name) =>
    File('test/fixtures/audio_tags/$name').readAsBytesSync();

/// Counts how much a reader actually pulls from the file.
class _CountingSource implements ByteSource {
  final Uint8List bytes;
  int reads = 0;
  int fetched = 0;

  _CountingSource(this.bytes);

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List?> read(int offset, int count) async {
    reads++;
    if (offset >= bytes.length) return Uint8List(0);
    final end = offset + count > bytes.length ? bytes.length : offset + count;
    fetched += end - offset;
    return Uint8List.sublistView(bytes, offset, end);
  }
}

class _ThrowingSource implements ByteSource {
  final int okReads;
  final Uint8List bytes;
  int calls = 0;

  _ThrowingSource(this.bytes, {this.okReads = 0});

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List?> read(int offset, int count) async {
    if (calls++ >= okReads) throw StateError('platform channel failed');
    final end = offset + count > bytes.length ? bytes.length : offset + count;
    return Uint8List.sublistView(bytes, offset, end);
  }
}

Future<void> _expectStandardTags(String file, {bool disc = true}) async {
  final t = await AudioTagReader.read(
    MemoryByteSource(_fixture(file)),
    fileName: file,
  );
  expect(t.title, 'Test_Title', reason: file);
  expect(t.artists, ['Artist_One'], reason: file);
  expect(t.album, 'Album_X', reason: file);
  expect(t.genres, ['Rock'], reason: file);
  expect(t.year, 2004, reason: file);
  expect(t.trackNo, 3, reason: file);
  if (disc) {
    expect(t.albumArtists, ['Various_Artists'], reason: file);
    expect(t.trackTotal, 12, reason: file);
    expect(t.discNo, 1, reason: file);
    expect(t.discTotal, 2, reason: file);
  }
}

void main() {
  group('tags per format', () {
    test('MP3 ID3v2.3 with cover', () => _expectStandardTags('mp3_v23_cover.mp3'));
    test('MP3 ID3v2.4', () => _expectStandardTags('mp3_v24_cbr.mp3'));
    test('FLAC', () => _expectStandardTags('flac_cover.flac'));
    test('Ogg Vorbis', () => _expectStandardTags('ogg_vorbis.ogg'));
    test('Opus', () => _expectStandardTags('opus.opus'));
    test('M4A, moov at end', () => _expectStandardTags('m4a_moov_end.m4a'));
    test('M4A, moov first', () => _expectStandardTags('m4a_faststart.m4a'));
    test('WAV INFO', () async {
      final t = await AudioTagReader.read(
        MemoryByteSource(_fixture('wav_info.wav')),
        fileName: 'wav_info.wav',
      );
      expect(t.title, 'Test_Title');
      expect(t.artists, ['Artist_One']);
      expect(t.album, 'Album_X');
      expect(t.year, 2004);
      expect(t.format, 'wav');
    });

    test('formats are reported', () async {
      Future<String> fmt(String f) async => (await AudioTagReader.read(
            MemoryByteSource(_fixture(f)),
            fileName: f,
          ))
              .format;
      expect(await fmt('mp3_v23_cover.mp3'), 'mp3');
      expect(await fmt('flac_cover.flac'), 'flac');
      expect(await fmt('ogg_vorbis.ogg'), 'ogg');
      expect(await fmt('opus.opus'), 'opus');
      expect(await fmt('m4a_moov_end.m4a'), 'm4a');
    });
  });

  group('duration', () {
    Future<int> dur(String f) async => (await AudioTagReader.read(
          MemoryByteSource(_fixture(f)),
          fileName: f,
        ))
            .durationMs;

    test('exact formats land on the 2 second clip', () async {
      for (final f in [
        'flac_cover.flac',
        'ogg_vorbis.ogg',
        'opus.opus',
        'm4a_moov_end.m4a',
        'm4a_faststart.m4a',
        'wav_info.wav',
      ]) {
        expect((await dur(f) - 2000).abs() < 30, isTrue, reason: '$f -> ${await dur(f)}');
      }
    });

    test('MP3 with a Xing header', () async {
      expect((await dur('mp3_v23_cover.mp3') - 2037).abs() < 40, isTrue);
    });

    test('MP3 without a Xing header falls back to the bitrate estimate', () async {
      expect((await dur('mp3_v24_cbr.mp3') - 2037).abs() < 60, isTrue);
    });
  });

  group('ID3 details', () {
    test('ID3v1-only file', () async {
      final t = await AudioTagReader.read(
        MemoryByteSource(_fixture('mp3_v1_only.mp3')),
        fileName: 'mp3_v1_only.mp3',
      );
      expect(t.title, 'V1 Title');
      expect(t.artists, ['V1 Artist']);
      expect(t.album, 'V1 Album');
      expect(t.genres, ['Rock']);
      expect(t.year, 1999);
      expect(t.trackNo, 7);
      // The 128-byte footer must not be counted as audio.
      expect((t.durationMs - 2037).abs() < 60, isTrue);
    });

    test('untagged MP3 has no tags but a duration and format', () async {
      final t = await AudioTagReader.read(
        MemoryByteSource(_fixture('mp3_untagged.mp3')),
        fileName: 'mp3_untagged.mp3',
      );
      expect(t.hasAnyTag, isFalse);
      expect(t.format, 'mp3');
      expect(t.durationMs, greaterThan(1900));
    });

    test('ID3v2.4 UTF-8, multiple values and a numeric genre reference', () async {
      final t = await AudioTagReader.read(
        MemoryByteSource(_fixture('mp3_v24_multi_unicode.mp3')),
        fileName: 'x.mp3',
      );
      expect(t.title, 'Ünïcode Tïtle ✓');
      expect(t.artists, ['Björk', 'Sigur Rós']);
      expect(t.album, 'Альбом');
      expect(t.genres, ['Rock', 'Electronic']);
      expect(t.year, 2010);
    });

    test('ID3v2.3 UTF-16', () async {
      final t = await AudioTagReader.read(
        MemoryByteSource(_fixture('mp3_v23_utf16.mp3')),
        fileName: 'x.mp3',
      );
      expect(t.title, '日本語タイトル');
      expect(t.artists, ['アーティスト']);
      expect(t.album, 'アルバム');
    });
  });

  group('cover art', () {
    Future<void> expectCover(String f) async {
      final art = await AudioTagReader.readCover(
        MemoryByteSource(_fixture(f)),
        fileName: f,
      );
      expect(art, isNotNull, reason: f);
      expect(art!.mime, 'image/jpeg', reason: f);
      expect(art.bytes.length, 272, reason: f);
      expect(art.bytes[0], 0xFF, reason: f);
      expect(art.bytes[1], 0xD8, reason: f);
      final t = await AudioTagReader.read(
        MemoryByteSource(_fixture(f)),
        fileName: f,
      );
      expect(t.hasCover, isTrue, reason: f);
    }

    test('MP3 APIC', () => expectCover('mp3_v23_cover.mp3'));
    test('FLAC PICTURE', () => expectCover('flac_cover.flac'));
    test('M4A covr', () => expectCover('m4a_moov_end.m4a'));
    test('M4A covr, moov first', () => expectCover('m4a_faststart.m4a'));
    test('Ogg METADATA_BLOCK_PICTURE', () => expectCover('ogg_vorbis_cover.ogg'));

    test('files without a picture report none', () async {
      for (final f in [
        'mp3_v24_cbr.mp3',
        'mp3_untagged.mp3',
        'ogg_vorbis.ogg',
        'opus.opus',
        'wav_info.wav',
      ]) {
        final t = await AudioTagReader.read(MemoryByteSource(_fixture(f)), fileName: f);
        expect(t.hasCover, isFalse, reason: f);
        expect(
          await AudioTagReader.readCover(MemoryByteSource(_fixture(f)), fileName: f),
          isNull,
          reason: f,
        );
      }
    });
  });

  group('read cost with large embedded pictures', () {
    // The point of the header-driven readers: tag size must not drive cost.
    const bigCover = 3 * 1024 * 1024;

    test('MP3: tags placed after a 3 MB APIC frame are still read, picture skipped', () async {
      final audio = _fixture('mp3_untagged.mp3');
      final tag = _buildId3v23([
        _textFrame('TIT2', 'Before Cover'),
        _frame('APIC', Uint8List(bigCover)),
        _textFrame('TALB', 'After Cover'),
      ]);
      final file = Uint8List.fromList([...tag, ...audio]);
      final src = _CountingSource(file);
      final t = await AudioTagReader.read(src, fileName: 'big.mp3');
      expect(t.title, 'Before Cover');
      expect(t.album, 'After Cover');
      expect(t.hasCover, isTrue);
      expect(src.fetched, lessThan(200 * 1024), reason: 'fetched ${src.fetched} of ${file.length}');
    });

    test('FLAC: a 3 MB picture block is not read', () async {
      final src = _CountingSource(_flacWithBigPicture(_fixture('flac_cover.flac'), bigCover));
      final t = await AudioTagReader.read(src, fileName: 'big.flac');
      expect(t.title, 'Test_Title');
      expect(t.durationMs, 2000);
      expect(t.hasCover, isTrue);
      expect(src.fetched, lessThan(200 * 1024), reason: 'fetched ${src.fetched}');
    });

    test('M4A: moov after 3 MB of mdat is found without reading the mdat', () async {
      final src = _CountingSource(_m4aWithBigMdat(_fixture('m4a_moov_end.m4a'), bigCover));
      final t = await AudioTagReader.read(src, fileName: 'big.m4a');
      expect(t.title, 'Test_Title');
      expect(t.durationMs, 2000);
      expect(src.fetched, lessThan(200 * 1024), reason: 'fetched ${src.fetched}');
    });
  });

  group('reads per MP3', () {
    // Each source read is a platform-channel call plus a decrypt, so the number
    // of calls per file matters as much as the bytes. Padding after the audio
    // makes the file far larger than one read window, like a real track.
    Uint8List padded(String name) => Uint8List.fromList([
          ..._fixture(name),
          ...Uint8List(2 * 1024 * 1024),
        ]);

    test('an ID3v2 + Xing file is read with a single call', () async {
      final src = _CountingSource(padded('mp3_v23_cover.mp3'));
      final t = await AudioTagReader.read(src, fileName: 'a.mp3');
      expect(t.title, 'Test_Title');
      expect((t.durationMs - 2037).abs() < 40, isTrue);
      expect(src.reads, 1);
    });

    test('without a frame count the bitrate estimate costs one extra call for the file end', () async {
      final src = _CountingSource(padded('mp3_v24_cbr.mp3'));
      final t = await AudioTagReader.read(src, fileName: 'a.mp3');
      expect(t.title, 'Test_Title');
      expect(src.reads, 2);
    });

    test('a file with no ID3v2 tag also checks the end for ID3v1', () async {
      final src = _CountingSource(padded('mp3_untagged.mp3'));
      await AudioTagReader.read(src, fileName: 'a.mp3');
      expect(src.reads, 2);
    });
  });

  group('robustness', () {
    test('empty, tiny and garbage inputs yield empty tags', () async {
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList(List.generate(5000, (i) => (i * 37 + 11) & 0xFF)),
        Uint8List(5000),
      ]) {
        final t = await AudioTagReader.read(MemoryByteSource(bytes), fileName: 'x.mp3');
        expect(t.hasAnyTag, isFalse);
      }
    });

    test('every fixture truncated at half its size never throws', () async {
      final dir = Directory('test/fixtures/audio_tags');
      for (final f in dir.listSync().whereType<File>()) {
        final name = f.path.split('/').last;
        if (name.endsWith('.jpg') || name.endsWith('.png')) continue;
        final full = f.readAsBytesSync();
        for (final cut in [full.length ~/ 2, full.length ~/ 10, 40]) {
          final part = Uint8List.sublistView(full, 0, cut);
          await AudioTagReader.read(MemoryByteSource(part), fileName: name);
          await AudioTagReader.readCover(MemoryByteSource(part), fileName: name);
        }
      }
    });

    test('a source that fails on the first read is reported, not hidden', () async {
      final src = _ThrowingSource(_fixture('mp3_v23_cover.mp3'));
      var threw = false;
      try {
        await AudioTagReader.read(src, fileName: 'a.mp3');
      } on TagSourceException {
        threw = true;
      }
      expect(threw, isTrue);
    });

    test('a source that fails after the first window keeps what was read', () async {
      final src = _ThrowingSource(_fixture('mp3_v23_cover.mp3'), okReads: 1);
      final t = await AudioTagReader.read(src, fileName: 'a.mp3');
      expect(t.title, 'Test_Title');
    });
  });
}

// ── Synthetic file builders ──────────────────────────────────────────────────

Uint8List _frame(String id, Uint8List payload) {
  final b = BytesBuilder();
  b.add(id.codeUnits);
  final n = payload.length;
  b.add([(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF]);
  b.add([0, 0]);
  b.add(payload);
  return b.toBytes();
}

Uint8List _textFrame(String id, String text) =>
    _frame(id, Uint8List.fromList([0, ...text.codeUnits]));

Uint8List _buildId3v23(List<Uint8List> frames) {
  final body = BytesBuilder();
  for (final f in frames) {
    body.add(f);
  }
  final n = body.length;
  final b = BytesBuilder();
  b.add([0x49, 0x44, 0x33, 3, 0, 0]);
  b.add([(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F]);
  b.add(body.toBytes());
  return b.toBytes();
}

/// Inserts [extra] zero bytes into the FLAC PICTURE block and fixes its length.
Uint8List _flacWithBigPicture(Uint8List flac, int extra) {
  var pos = 4;
  while (pos + 4 <= flac.length) {
    final isLast = (flac[pos] & 0x80) != 0;
    final type = flac[pos] & 0x7F;
    final len = (flac[pos + 1] << 16) | (flac[pos + 2] << 8) | flac[pos + 3];
    if (type == 6) {
      final newLen = len + extra;
      final out = BytesBuilder();
      out.add(flac.sublist(0, pos + 1));
      out.add([(newLen >> 16) & 0xFF, (newLen >> 8) & 0xFF, newLen & 0xFF]);
      out.add(flac.sublist(pos + 4, pos + 4 + len));
      out.add(Uint8List(extra));
      out.add(flac.sublist(pos + 4 + len));
      return out.toBytes();
    }
    if (isLast) break;
    pos += 4 + len;
  }
  throw StateError('fixture has no PICTURE block');
}

/// Grows the top-level `mdat` atom by [extra] zero bytes, pushing `moov` out.
Uint8List _m4aWithBigMdat(Uint8List m4a, int extra) {
  var pos = 0;
  while (pos + 8 <= m4a.length) {
    final size = (m4a[pos] << 24) | (m4a[pos + 1] << 16) | (m4a[pos + 2] << 8) | m4a[pos + 3];
    final type = String.fromCharCodes(m4a.sublist(pos + 4, pos + 8));
    if (type == 'mdat') {
      final newSize = size + extra;
      final out = BytesBuilder();
      out.add(m4a.sublist(0, pos));
      out.add([(newSize >> 24) & 0xFF, (newSize >> 16) & 0xFF, (newSize >> 8) & 0xFF, newSize & 0xFF]);
      out.add(m4a.sublist(pos + 4, pos + size));
      out.add(Uint8List(extra));
      out.add(m4a.sublist(pos + size));
      return out.toBytes();
    }
    pos += size;
  }
  throw StateError('fixture has no mdat');
}
