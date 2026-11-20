import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/features/library/index/library_scanner.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/audio_tags/$name').readAsBytesSync();

class _FakeFile {
  Uint8List bytes;
  int mtime;
  _FakeFile(this.bytes, {this.mtime = 100});
}

/// A fake container: path -> file, with listing and chunk reads derived from it.
class _FakeTree {
  final Map<String, _FakeFile> files = {};
  final Set<String> failingDirs = {};
  final Set<String> unreadable = {};
  int listCalls = 0;
  int readCalls = 0;
  int running = 0;
  int maxRunning = 0;
  Future<void> Function()? onRead;

  void add(String path, Uint8List bytes, {int mtime = 100}) =>
      files[path] = _FakeFile(bytes, mtime: mtime);

  Future<List<LibraryFsEntry>?> list(String dir) async {
    listCalls++;
    if (failingDirs.contains(dir)) return null;
    final prefix = dir.isEmpty ? '' : '$dir/';
    final entries = <String, LibraryFsEntry>{};
    for (final e in files.entries) {
      if (!e.key.startsWith(prefix)) continue;
      final rest = e.key.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        entries[rest] = LibraryFsEntry(
          name: rest,
          isDir: false,
          sizeBytes: e.value.bytes.length,
          modifiedSecs: e.value.mtime,
        );
      } else {
        final d = rest.substring(0, slash);
        entries[d] = LibraryFsEntry(name: d, isDir: true);
      }
    }
    return entries.values.toList();
  }

  Future<Uint8List?> read(String path, int offset, int length) async {
    readCalls++;
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      await onRead?.call();
      await Future<void>.delayed(Duration.zero);
      if (unreadable.contains(path)) throw StateError('io error');
      final b = files[path]!.bytes;
      if (offset >= b.length) return Uint8List(0);
      final end = offset + length > b.length ? b.length : offset + length;
      return Uint8List.sublistView(b, offset, end);
    } finally {
      running--;
    }
  }
}

bool _isAudio(String n) {
  final l = n.toLowerCase();
  return l.endsWith('.mp3') || l.endsWith('.flac') || l.endsWith('.m4a') || l.endsWith('.ogg');
}

LibraryScanner _scanner(_FakeTree tree, {int readConcurrency = 4}) => LibraryScanner(
      listDirectory: tree.list,
      readChunk: tree.read,
      isAudioFile: _isAudio,
      readConcurrency: readConcurrency,
      batchSize: 2,
    );

_FakeTree _library() {
  final tree = _FakeTree();
  tree.add('Music/Rock/song1.mp3', _fixture('mp3_v23_cover.mp3'));
  tree.add('Music/Rock/song2.flac', _fixture('flac_cover.flac'));
  tree.add('Music/Jazz/deep/song3.m4a', _fixture('m4a_moov_end.m4a'));
  tree.add('Music/Jazz/song4.ogg', _fixture('ogg_vorbis.ogg'));
  tree.add('Music/notes.txt', Uint8List.fromList([1, 2, 3]));
  tree.add('Music/.hidden/secret.mp3', _fixture('mp3_v24_cbr.mp3'));
  tree.add('Music/Rock/.DS_Store.mp3', _fixture('mp3_v24_cbr.mp3'));
  tree.add('top.mp3', _fixture('mp3_untagged.mp3'));
  return tree;
}

Future<({LibraryScanResult result, List<LibraryTrack> tracks})> _run(
  LibraryScanner s, {
  Map<String, LibraryTrack> existing = const {},
  CancellationToken? token,
  List<String> starts = const [''],
}) async {
  final tracks = <LibraryTrack>[];
  final result = await s.scan(
    startPaths: starts,
    existing: existing,
    token: token ?? CancellationToken(),
    onTracks: tracks.addAll,
  );
  return (result: result, tracks: tracks);
}

void main() {
  test('finds audio recursively, skips hidden entries and non-audio files', () async {
    final tree = _library();
    final r = await _run(_scanner(tree));
    expect(r.result.seenPaths, {
      'Music/Rock/song1.mp3',
      'Music/Rock/song2.flac',
      'Music/Jazz/deep/song3.m4a',
      'Music/Jazz/song4.ogg',
      'top.mp3',
    });
    expect(r.tracks.length, 5);
    expect(r.result.walkComplete, isTrue);
    expect(r.result.readFailures, 0);
  });

  test('reads real tags and keeps listing size and mtime', () async {
    final tree = _library();
    final r = await _run(_scanner(tree));
    final byPath = {for (final t in r.tracks) t.path: t};
    final rock = byPath['Music/Rock/song1.mp3']!;
    expect(rock.title, 'Test_Title');
    expect(rock.artists, ['Artist_One']);
    expect(rock.album, 'Album_X');
    expect(rock.hasCover, isTrue);
    expect(rock.size, tree.files['Music/Rock/song1.mp3']!.bytes.length);
    expect(rock.modifiedSecs, 100);
    // Untagged file falls back to its file name.
    expect(byPath['top.mp3']!.title, 'top');
  });

  test('scanning a subfolder only walks that subtree', () async {
    final r = await _run(_scanner(_library()), starts: ['Music/Jazz']);
    expect(r.result.seenPaths, {'Music/Jazz/deep/song3.m4a', 'Music/Jazz/song4.ogg'});
  });

  test('several chosen folders are all scanned and nothing else is touched', () async {
    final tree = _library();
    final r = await _run(_scanner(tree), starts: ['Music/Rock', 'Music/Jazz/deep']);
    expect(r.result.seenPaths, {
      'Music/Rock/song1.mp3',
      'Music/Rock/song2.flac',
      'Music/Jazz/deep/song3.m4a',
    });
    expect(r.tracks.length, 3);
  });

  test('overlapping roots count each file once', () async {
    final r = await _run(_scanner(_library()), starts: ['Music', 'Music/Rock']);
    expect(r.result.seenPaths.length, 4);
    expect(r.tracks.length, 4);
  });

  test('a second scan against the first result reads nothing', () async {
    final tree = _library();
    final first = await _run(_scanner(tree));
    final existing = {for (final t in first.tracks) t.path: t};
    tree.readCalls = 0;

    final second = await _run(_scanner(tree), existing: existing);
    expect(second.tracks, isEmpty);
    expect(tree.readCalls, 0);
    expect(second.result.seenPaths.length, 5);
  });

  test('only files whose size or mtime changed are re-read', () async {
    final tree = _library();
    final first = await _run(_scanner(tree));
    final existing = {for (final t in first.tracks) t.path: t};

    tree.files['Music/Rock/song1.mp3']!.mtime = 999;
    tree.add('Music/Jazz/new.mp3', _fixture('mp3_v1_only.mp3'));

    final second = await _run(_scanner(tree), existing: existing);
    expect(second.tracks.map((t) => t.path).toSet(), {
      'Music/Rock/song1.mp3',
      'Music/Jazz/new.mp3',
    });
    final changed = second.tracks.firstWhere((t) => t.path == 'Music/Rock/song1.mp3');
    expect(changed.modifiedSecs, 999);
  });

  test('a deleted file is absent from seenPaths of a complete walk', () async {
    final tree = _library();
    final first = await _run(_scanner(tree));
    tree.files.remove('top.mp3');
    final second = await _run(
      _scanner(tree),
      existing: {for (final t in first.tracks) t.path: t},
    );
    expect(second.result.seenPaths.contains('top.mp3'), isFalse);
    expect(second.result.walkComplete, isTrue);
  });

  test('a folder that fails to list marks the walk incomplete but the rest still scans', () async {
    final tree = _library();
    tree.failingDirs.add('Music/Jazz');
    final r = await _run(_scanner(tree));
    expect(r.result.listFailures, 1);
    expect(r.result.walkComplete, isFalse);
    expect(r.result.seenPaths, {
      'Music/Rock/song1.mp3',
      'Music/Rock/song2.flac',
      'top.mp3',
    });
  });

  test('an unreadable file counts as a failure, stays seen, and does not stop the scan', () async {
    final tree = _library();
    tree.unreadable.add('Music/Rock/song2.flac');
    final r = await _run(_scanner(tree));
    expect(r.result.readFailures, 1);
    expect(r.result.seenPaths.contains('Music/Rock/song2.flac'), isTrue);
    expect(r.tracks.map((t) => t.path).contains('Music/Rock/song2.flac'), isFalse);
    expect(r.tracks.length, 4);
  });

  test('empty files are listed as seen but never read', () async {
    final tree = _library();
    tree.add('empty.mp3', Uint8List(0));
    final r = await _run(_scanner(tree));
    expect(r.result.seenPaths.contains('empty.mp3'), isTrue);
    expect(r.tracks.any((t) => t.path == 'empty.mp3'), isFalse);
    expect(r.result.readFailures, 0);
  });

  test('cancelling mid-read stops further reads and reports cancelled', () async {
    final tree = _library();
    // Plenty of files so there is something left to cancel.
    for (var i = 0; i < 40; i++) {
      tree.add('Many/f$i.mp3', _fixture('mp3_v24_cbr.mp3'));
    }
    final token = CancellationToken();
    var reads = 0;
    tree.onRead = () async {
      if (++reads == 6) token.cancel();
    };
    final r = await _run(_scanner(tree, readConcurrency: 2), token: token);
    expect(r.result.cancelled, isTrue);
    expect(r.result.walkComplete, isFalse);
    expect(tree.readCalls, lessThan(30));
  });

  test('cancelling before the walk finishes does no reading', () async {
    final tree = _library();
    final token = CancellationToken()..cancel();
    final r = await _run(_scanner(tree), token: token);
    expect(r.result.cancelled, isTrue);
    expect(tree.readCalls, 0);
  });

  test('tag reads never exceed the configured concurrency', () async {
    final tree = _FakeTree();
    for (var i = 0; i < 30; i++) {
      tree.add('f$i.mp3', _fixture('mp3_v23_cover.mp3'));
    }
    await _run(_scanner(tree, readConcurrency: 3));
    expect(tree.maxRunning, lessThanOrEqualTo(3));
    expect(tree.maxRunning, greaterThan(1));
  });

  test('batches arrive while the scan runs', () async {
    final tree = _FakeTree();
    for (var i = 0; i < 9; i++) {
      tree.add('f$i.mp3', _fixture('mp3_v23_cover.mp3'));
    }
    final sizes = <int>[];
    await _scanner(tree).scan(
      startPaths: const [''],
      existing: const {},
      token: CancellationToken(),
      onTracks: (b) => sizes.add(b.length),
    );
    expect(sizes.length, greaterThan(1));
    expect(sizes.fold<int>(0, (a, b) => a + b), 9);
  });
}
