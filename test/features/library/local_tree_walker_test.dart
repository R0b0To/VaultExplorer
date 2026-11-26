import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/features/library/index/local_tree_walker.dart';

bool _isAudio(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.mp3') || lower.endsWith('.flac');
}

void main() {
  late Directory root;

  void file(String relative, {int bytes = 4}) {
    final f = File('${root.path}/$relative')..createSync(recursive: true);
    f.writeAsBytesSync(List<int>.filled(bytes, 1));
  }

  setUp(() => root = Directory.systemTemp.createTempSync('ve_walk_'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<List<String>> walk(List<String> starts) async {
    final result = await walkLocalAudioTree(
      rootPath: root.path,
      startPaths: starts,
      isAudioFile: _isAudio,
      token: CancellationToken(),
      onProgress: (folders, audio) {},
    );
    expect(result, isNotNull);
    return [for (final f in result!.files) f.path]..sort();
  }

  test('finds audio files at any depth, with size and time', () async {
    file('a.mp3', bytes: 10);
    file('Albums/One/b.FLAC');
    file('Albums/notes.txt');
    final result = await walkLocalAudioTree(
      rootPath: root.path,
      startPaths: const [''],
      isAudioFile: _isAudio,
      token: CancellationToken(),
      onProgress: (folders, audio) {},
    );
    final byPath = {for (final f in result!.files) f.path: f};
    expect(byPath.keys.toSet(), {'a.mp3', 'Albums/One/b.FLAC'});
    expect(byPath['a.mp3']!.sizeBytes, 10);
    expect(byPath['a.mp3']!.modifiedSecs, greaterThan(0));
    expect(result.foldersChecked, 3);
    expect(result.listFailures, 0);
    expect(result.limitReached, isFalse);
  });

  test('skips hidden entries and folders that never hold a library', () async {
    file('.hidden/x.mp3');
    file('.y.mp3');
    file('node_modules/pkg/z.mp3');
    file('AppData/Local/song.mp3');
    file('Music/AppData/keep.mp3');
    file('Music/keep2.mp3');
    expect(await walk(const ['']), ['Music/AppData/keep.mp3', 'Music/keep2.mp3']);
  });

  test('an explicitly chosen folder is walked even under a skipped name', () async {
    file('AppData/Roaming/Music/song.mp3');
    expect(
      await walk(const ['AppData/Roaming/Music']),
      ['AppData/Roaming/Music/song.mp3'],
    );
  });

  test('overlapping start paths report a file once', () async {
    file('Music/a.mp3');
    expect(await walk(const ['', 'Music']), ['Music/a.mp3']);
  });

  test('a cancelled walk reports nothing', () async {
    file('a.mp3');
    final token = CancellationToken()..cancel();
    final result = await walkLocalAudioTree(
      rootPath: root.path,
      startPaths: const [''],
      isAudioFile: _isAudio,
      token: token,
      onProgress: (folders, audio) {},
    );
    expect(result, isNull);
  });
}
