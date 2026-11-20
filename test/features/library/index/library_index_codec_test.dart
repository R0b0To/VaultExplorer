import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/library/index/library_index_codec.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';

LibraryTrack _t(int i) => LibraryTrack(
      path: 'Music/Album $i/track $i.mp3',
      size: 1000 + i,
      modifiedSecs: 1700000000 + i,
      title: 'Title $i ✓ Ünï',
      artists: ['Artist ${i % 7}', 'Other'],
      album: 'Album $i',
      albumArtists: i.isEven ? ['AA'] : const [],
      genres: ['Rock'],
      year: 1990 + i % 30,
      trackNo: i % 12,
      discNo: i % 3,
      durationMs: 180000 + i,
      hasCover: i.isOdd,
      format: 'mp3',
    );

Uint8List _gz(Object json) =>
    Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(json))));

void main() {
  test('round trip preserves every field', () {
    final src = [for (var i = 0; i < 50; i++) _t(i)];
    final back = LibraryIndexCodec.decode(LibraryIndexCodec.encode(src));
    expect(back.length, 50);
    for (var i = 0; i < 50; i++) {
      final a = src[i], b = back[i];
      expect(b.path, a.path);
      expect(b.size, a.size);
      expect(b.modifiedSecs, a.modifiedSecs);
      expect(b.title, a.title);
      expect(b.artists, a.artists);
      expect(b.album, a.album);
      expect(b.albumArtists, a.albumArtists);
      expect(b.genres, a.genres);
      expect(b.year, a.year);
      expect(b.trackNo, a.trackNo);
      expect(b.discNo, a.discNo);
      expect(b.durationMs, a.durationMs);
      expect(b.hasCover, a.hasCover);
      expect(b.format, a.format);
    }
  });

  test('an empty index round-trips', () {
    expect(LibraryIndexCodec.decode(LibraryIndexCodec.encode(const [])), isEmpty);
  });

  test('the blob is much smaller than the raw rows', () {
    final src = [for (var i = 0; i < 5000; i++) _t(i)];
    final blob = LibraryIndexCodec.encode(src);
    final raw = utf8.encode(jsonEncode([for (final t in src) t.toJson()]));
    expect(blob.length, lessThan(raw.length ~/ 3));
  });

  void expectRejected(Uint8List blob) {
    var threw = false;
    try {
      LibraryIndexCodec.decode(blob);
    } on FormatException {
      threw = true;
    }
    expect(threw, isTrue);
  }

  test('garbage, truncation and bad gzip are rejected as FormatException', () {
    expectRejected(Uint8List.fromList([1, 2, 3, 4]));
    expectRejected(Uint8List(0));
    final good = LibraryIndexCodec.encode([_t(1), _t(2)]);
    expectRejected(Uint8List.sublistView(good, 0, good.length ~/ 2));
  });

  test('wrong version, count mismatch and bad rows are rejected', () {
    final row = _t(1).toJson();
    expectRejected(_gz({'v': 99, 'n': 1, 't': [row]}));
    expectRejected(_gz({'v': LibraryIndexCodec.version, 'n': 2, 't': [row]}));
    expectRejected(_gz({'v': LibraryIndexCodec.version, 'n': 1, 't': [[1, 2, 3]]}));
    final badType = List<Object>.of(row)..[1] = 'not a number';
    expectRejected(_gz({'v': LibraryIndexCodec.version, 'n': 1, 't': [badType]}));
    final badList = List<Object>.of(row)..[4] = [1, 2];
    expectRejected(_gz({'v': LibraryIndexCodec.version, 'n': 1, 't': [badList]}));
    expectRejected(_gz([1, 2, 3]));
  });
}
