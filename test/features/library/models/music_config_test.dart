import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/library/models/music_config.dart';

void main() {
  test('off by default and scans the whole container', () {
    expect(MusicConfig.off.enabled, isFalse);
    expect(MusicConfig.off.wholeContainer, isTrue);
    expect(MusicConfig.off.scanRoots, ['']);
  });

  test('chosen folders become the scan roots', () {
    const c = MusicConfig(enabled: true, folders: ['Music', 'Podcasts/Audio']);
    expect(c.wholeContainer, isFalse);
    expect(c.scanRoots, ['Music', 'Podcasts/Audio']);
  });

  group('normalizeFolders', () {
    test('trims slashes, drops blanks and duplicates, and sorts', () {
      expect(
        MusicConfig.normalizeFolders(['/Music/', 'Music', '', '  ', 'A//B', 'a']),
        ['A/B', 'Music', 'a'],
      );
    });

    test('a folder inside another chosen folder is dropped', () {
      expect(
        MusicConfig.normalizeFolders(['Music/Rock', 'Music', 'Music/Jazz/Live', 'Musical']),
        ['Music', 'Musical'],
      );
    });

    test('backslashes are treated as separators', () {
      expect(MusicConfig.normalizeFolders([r'Music\Rock']), ['Music/Rock']);
    });

    test('the root (empty) is never an entry', () {
      expect(MusicConfig.normalizeFolders(['/', '']), isEmpty);
    });
  });

  test('copyWith normalizes folders', () {
    final c = MusicConfig.off.copyWith(enabled: true, folders: ['/X/', 'X/Y']);
    expect(c.enabled, isTrue);
    expect(c.folders, ['X']);
  });

  test('JSON round trip', () {
    const c = MusicConfig(enabled: true, folders: ['A', 'B/C']);
    expect(MusicConfig.fromJson(c.toJson()), c);
  });

  test('bad JSON is rejected', () {
    for (final bad in <Object?>[
      null,
      'x',
      [1],
      {'enabled': 'yes', 'folders': []},
      {'enabled': true, 'folders': 'A'},
      {'enabled': true, 'folders': [1, 2]},
      {'folders': []},
    ]) {
      var threw = false;
      try {
        MusicConfig.fromJson(bad);
      } on FormatException {
        threw = true;
      }
      expect(threw, isTrue, reason: '$bad');
    }
  });

  test('equality and hashing', () {
    const a = MusicConfig(enabled: true, folders: ['A']);
    const b = MusicConfig(enabled: true, folders: ['A']);
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);
    expect(a == const MusicConfig(enabled: false, folders: ['A']), isFalse);
  });
}
