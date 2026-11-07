import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';
import 'package:vaultexplorer/features/library/models/music_config.dart';

/// In-memory platform. "Encryption" is a keyed XOR plus a checksum so that a
/// flipped byte fails to decrypt, like a real GCM tag.
class _FakePlatform implements LibraryStorePlatform {
  final Map<String, Uint8List> appFiles = {};
  final Map<String, Uint8List> containerFiles = {}; // "<uri>|<path>"
  int encryptCalls = 0;
  int existsCalls = 0;

  @override
  String get metaDir => '.vaultexplorer';

  @override
  Future<String> appRoot() async => '/app';

  @override
  Future<Uint8List> cacheKey() async => Uint8List.fromList(List.filled(32, 0x5A));

  @override
  Future<Uint8List?> aesGcmEncrypt(Uint8List key, Uint8List iv, Uint8List p) async {
    encryptCalls++;
    final out = Uint8List(p.length + 16);
    var sum = 0;
    for (var i = 0; i < p.length; i++) {
      out[i] = p[i] ^ key[i % key.length] ^ iv[i % iv.length];
      sum = (sum + p[i]) & 0xFF;
    }
    for (var i = 0; i < 16; i++) {
      out[p.length + i] = sum;
    }
    return out;
  }

  @override
  Future<Uint8List?> aesGcmDecrypt(Uint8List key, Uint8List iv, Uint8List c) async {
    final n = c.length - 16;
    final out = Uint8List(n);
    var sum = 0;
    for (var i = 0; i < n; i++) {
      out[i] = c[i] ^ key[i % key.length] ^ iv[i % iv.length];
      sum = (sum + out[i]) & 0xFF;
    }
    for (var i = 0; i < 16; i++) {
      if (c[n + i] != sum) return null;
    }
    return out;
  }

  @override
  Future<String> digest(String value) async => base64Url.encode(utf8.encode(value));

  @override
  Future<Uint8List?> readAppFile(String path) async => appFiles[path];

  @override
  Future<bool> writeAppFile(String path, Uint8List bytes) async {
    appFiles[path] = bytes;
    return true;
  }

  @override
  Future<void> deleteAppFile(String path) async => appFiles.remove(path);

  String _k(MountedContainer c, String p) => '${c.uri}|$p';

  @override
  Future<bool> containerFileExists(MountedContainer c, String path) async {
    existsCalls++;
    return containerFiles.containsKey(_k(c, path));
  }

  @override
  Future<Uint8List?> readContainerFile(MountedContainer c, String path) async =>
      containerFiles[_k(c, path)];

  @override
  Future<bool> writeContainerFile(MountedContainer c, String path, Uint8List bytes) async {
    containerFiles[_k(c, path)] = bytes;
    return true;
  }

  @override
  Future<void> deleteContainerFile(MountedContainer c, String path) async =>
      containerFiles.remove(_k(c, path));
}

MountedContainer _vault({bool readOnly = false, String uri = '/vaults/a.vc'}) =>
    MountedContainer(
      uri: uri,
      displayName: 'a',
      volId: 0,
      rootFiles: const [],
      mountedAt: DateTime(2026),
      totalSpace: 0,
      freeSpace: 0,
      readOnly: readOnly,
    );

MountedContainer _local() =>
    buildLocalStorageContainer(rootPath: '/sdcard/Music', displayName: 'Phone');

List<LibraryTrack> _tracks() => [
      for (var i = 0; i < 20; i++)
        LibraryTrack(
          path: 'Secret Folder/track $i.mp3',
          size: 10 + i,
          modifiedSecs: 5,
          title: 'Private Title $i',
          artists: const ['Private Artist'],
          album: 'Private Album',
        ),
    ];

bool _containsBytes(Uint8List hay, String needle) {
  final n = utf8.encode(needle);
  for (var i = 0; i + n.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < n.length; j++) {
      if (hay[i + j] != n[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  group('location', () {
    test('a writable vault keeps its files inside itself', () {
      expect(LibraryIndexStore.locationFor(_vault()), LibraryLocation.inVault);
    });

    test('phone storage and read-only vaults use the app\'s private storage', () {
      expect(LibraryIndexStore.locationFor(_local()), LibraryLocation.thisDevice);
      expect(LibraryIndexStore.locationFor(_vault(readOnly: true)), LibraryLocation.thisDevice);
    });
  });

  group('writable vault: inside the vault', () {
    test('index and config land in the vault meta folder and nowhere else', () async {
      final p = _FakePlatform();
      final store = LibraryIndexStore(p);
      final c = _vault();
      expect(await store.saveIndex(c, _tracks()), isTrue);
      expect(await store.saveConfig(c, const MusicConfig(enabled: true, folders: ['Music'])), isTrue);

      expect(p.appFiles, isEmpty);
      expect(p.containerFiles.keys.toSet(), {
        '/vaults/a.vc|.vaultexplorer/music-index.bin',
        '/vaults/a.vc|.vaultexplorer/music.json',
      });
      // The vault encrypts them, so the app does not encrypt a second time.
      expect(p.encryptCalls, 0);
    });

    test('round trips', () async {
      final store = LibraryIndexStore(_FakePlatform());
      final c = _vault();
      await store.saveIndex(c, _tracks());
      await store.saveConfig(c, const MusicConfig(enabled: true, folders: ['A', 'B/C']));
      expect((await store.loadIndex(c))!.length, 20);
      final cfg = await store.loadConfig(c);
      expect(cfg.enabled, isTrue);
      expect(cfg.folders, ['A', 'B/C']);
    });

    test('nothing saved loads as null / off, asking the listing first', () async {
      final p = _FakePlatform();
      final store = LibraryIndexStore(p);
      expect(await store.loadIndex(_vault()), isNull);
      expect(await store.loadConfig(_vault()), MusicConfig.off);
      expect(p.existsCalls, 2);
    });

    test('a corrupt index or config is treated as nothing saved', () async {
      final p = _FakePlatform();
      final store = LibraryIndexStore(p);
      final c = _vault();
      await store.saveIndex(c, _tracks());
      await store.saveConfig(c, const MusicConfig(enabled: true));
      p.containerFiles.updateAll((k, v) => Uint8List.fromList([9, 9, 9]));
      expect(await store.loadIndex(c), isNull);
      expect(await store.loadConfig(c), MusicConfig.off);
    });

    test('deleteIndex removes the index but keeps the config', () async {
      final p = _FakePlatform();
      final store = LibraryIndexStore(p);
      final c = _vault();
      await store.saveIndex(c, _tracks());
      await store.saveConfig(c, const MusicConfig(enabled: true));
      await store.deleteIndex(c);
      expect(await store.loadIndex(c), isNull);
      expect((await store.loadConfig(c)).enabled, isTrue);
    });
  });

  group('phone storage and read-only vaults: encrypted app storage', () {
    for (final entry in {
      'phone storage': _local,
      'read-only vault': () => _vault(readOnly: true),
    }.entries) {
      test('${entry.key}: nothing is written into the container, nothing in the clear', () async {
        final p = _FakePlatform();
        final store = LibraryIndexStore(p);
        final c = entry.value();
        await store.saveIndex(c, _tracks());
        await store.saveConfig(c, const MusicConfig(enabled: true, folders: ['Secret Folder']));

        expect(p.containerFiles, isEmpty);
        expect(p.appFiles.length, 2);
        for (final bytes in p.appFiles.values) {
          expect(_containsBytes(bytes, 'Private'), isFalse);
          expect(_containsBytes(bytes, 'Secret'), isFalse);
        }
        expect((await store.loadIndex(c))!.length, 20);
        expect((await store.loadConfig(c)).folders, ['Secret Folder']);
      });
    }

    test('a tampered file is rejected as nothing saved', () async {
      final p = _FakePlatform();
      final store = LibraryIndexStore(p);
      final c = _local();
      await store.saveIndex(c, _tracks());
      final key = p.appFiles.keys.single;
      final bytes = Uint8List.fromList(p.appFiles[key]!);
      bytes[bytes.length ~/ 2] ^= 0xFF;
      p.appFiles[key] = bytes;
      expect(await store.loadIndex(c), isNull);
    });

    test('truncated and garbage files are rejected', () async {
      final p = _FakePlatform();
      final store = LibraryIndexStore(p);
      final c = _local();
      await store.saveIndex(c, _tracks());
      final key = p.appFiles.keys.single;
      p.appFiles[key] = Uint8List.fromList([1, 2, 3]);
      expect(await store.loadIndex(c), isNull);
      p.appFiles[key] = Uint8List.fromList(List.generate(400, (i) => i & 0xFF));
      expect(await store.loadIndex(c), isNull);
    });

    test('each container gets its own files', () async {
      final p = _FakePlatform();
      final store = LibraryIndexStore(p);
      final a = _vault(readOnly: true, uri: '/a');
      final b = _vault(readOnly: true, uri: '/b');
      await store.saveIndex(a, _tracks());
      await store.saveIndex(b, _tracks().take(3).toList());
      expect((await store.loadIndex(a))!.length, 20);
      expect((await store.loadIndex(b))!.length, 3);
      expect(await store.loadIndex(_vault(readOnly: true, uri: '/other')), isNull);
    });
  });

  group('config isolation', () {
    test('turning music mode on in one container does not turn it on in another', () async {
      final store = LibraryIndexStore(_FakePlatform());
      await store.saveConfig(_vault(uri: '/a'), const MusicConfig(enabled: true));
      expect((await store.loadConfig(_vault(uri: '/a'))).enabled, isTrue);
      expect((await store.loadConfig(_vault(uri: '/b'))).enabled, isFalse);
      expect((await store.loadConfig(_local())).enabled, isFalse);
    });
  });

  group('custom covers', () {
    Map<String, Uint8List> covers() => {
          'album|a:x|y': Uint8List.fromList(List.generate(300, (i) => i & 0xFF)),
          'artist|björk': Uint8List.fromList([1, 2, 3]),
        };

    test('a writable vault keeps them inside the vault', () async {
      final p = _FakePlatform();
      final store = LibraryIndexStore(p);
      final c = _vault();
      expect(await store.saveCovers(c, covers()), isTrue);
      expect(p.containerFiles.keys.single, '/vaults/a.vc|.vaultexplorer/music-covers.bin');
      expect(p.appFiles, isEmpty);
      final back = await store.loadCovers(c);
      expect(back.keys.toSet(), covers().keys.toSet());
      expect(back['artist|björk'], [1, 2, 3]);
    });

    test('phone storage keeps them encrypted in app storage', () async {
      final p = _FakePlatform();
      final store = LibraryIndexStore(p);
      expect(await store.saveCovers(_local(), covers()), isTrue);
      expect(p.containerFiles, isEmpty);
      expect(p.appFiles.length, 1);
      expect((await store.loadCovers(_local())).length, 2);
    });

    test('saving an empty set removes the file', () async {
      final p = _FakePlatform();
      final store = LibraryIndexStore(p);
      final c = _vault();
      await store.saveCovers(c, covers());
      await store.saveCovers(c, {});
      expect(p.containerFiles, isEmpty);
      expect(await store.loadCovers(c), isEmpty);
    });

    test('a damaged file means no custom covers, not an error', () async {
      final p = _FakePlatform();
      final store = LibraryIndexStore(p);
      final c = _vault();
      await store.saveCovers(c, covers());
      p.containerFiles.updateAll((k, v) => Uint8List.fromList([7, 7, 7, 7, 7, 7, 7, 7, 7]));
      expect(await store.loadCovers(c), isEmpty);
    });
  });
}
