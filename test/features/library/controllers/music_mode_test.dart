import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/controllers/music_mode.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';
import 'package:vaultexplorer/features/library/models/music_config.dart';

class _Platform implements LibraryStorePlatform {
  final Map<String, Uint8List> app = {};
  final Map<String, Uint8List> vault = {};

  @override
  String get metaDir => '.vaultexplorer';
  @override
  Future<String> appRoot() async => '/app';
  @override
  Future<Uint8List> cacheKey() async => Uint8List(32);
  @override
  Future<Uint8List?> aesGcmEncrypt(Uint8List k, Uint8List iv, Uint8List p) async =>
      Uint8List.fromList([...p, ...List.filled(16, 0)]);
  @override
  Future<Uint8List?> aesGcmDecrypt(Uint8List k, Uint8List iv, Uint8List c) async =>
      Uint8List.sublistView(c, 0, c.length - 16);
  @override
  Future<String> digest(String v) async => base64Url.encode(utf8.encode(v));
  @override
  Future<Uint8List?> readAppFile(String path) async => app[path];
  @override
  Future<bool> writeAppFile(String path, Uint8List bytes) async {
    app[path] = bytes;
    return true;
  }

  @override
  Future<void> deleteAppFile(String path) async => app.remove(path);
  String _k(MountedContainer c, String p) => '${c.uri}|$p';
  @override
  Future<bool> containerFileExists(MountedContainer c, String path) async =>
      vault.containsKey(_k(c, path));
  @override
  Future<Uint8List?> readContainerFile(MountedContainer c, String path) async =>
      vault[_k(c, path)];
  @override
  Future<bool> writeContainerFile(MountedContainer c, String path, Uint8List b) async {
    vault[_k(c, path)] = b;
    return true;
  }

  @override
  Future<void> deleteContainerFile(MountedContainer c, String path) async =>
      vault.remove(_k(c, path));
}

MountedContainer _vault(String uri) => MountedContainer(
      uri: uri,
      displayName: uri,
      volId: 0,
      rootFiles: const [],
      mountedAt: DateTime(2026),
      totalSpace: 0,
      freeSpace: 0,
    );

MountedContainer _phone() =>
    buildLocalStorageContainer(rootPath: '/sdcard/Music', displayName: 'Phone');

void main() {
  late _Platform platform;
  late LibraryIndexStore store;

  setUp(() {
    platform = _Platform();
    store = LibraryIndexStore(platform);
  });

  group('MusicModeEntry', () {
    test('starts off on the file listing and reads nothing it should not', () async {
      final e = MusicModeEntry(_vault('/a'), store);
      expect(e.config, MusicConfig.off);
      expect(e.category, MusicCategory.files);
      expect(e.loaded, isFalse);
      await e.load();
      expect(e.loaded, isTrue);
      expect(e.config.enabled, isFalse);
      expect(e.libraryVisible, isFalse);
      e.dispose();
    });

    test('enable saves the scope, switches to Albums and shows the library', () async {
      final e = MusicModeEntry(_vault('/a'), store);
      await e.load();
      var notified = 0;
      e.addListener(() => notified++);

      await e.enable(folders: ['Music', 'Music/Rock']);

      expect(e.config.enabled, isTrue);
      expect(e.config.folders, ['Music']); // nested folder collapsed
      expect(e.category, MusicCategory.albums);
      expect(e.libraryVisible, isTrue);
      expect(notified, greaterThan(0));
      expect(platform.vault.keys.single, '/a|.vaultexplorer/music.json');
      e.dispose();
    });

    test('a new session finds music mode still on, with its folders', () async {
      final first = MusicModeEntry(_vault('/a'), store);
      await first.load();
      await first.enable(folders: ['Music']);
      first.dispose();

      final second = MusicModeEntry(_vault('/a'), store);
      await second.load();
      expect(second.config.enabled, isTrue);
      expect(second.config.folders, ['Music']);
      // The visible view is per session: it opens on the files.
      expect(second.category, MusicCategory.files);
      expect(second.libraryVisible, isFalse);
      second.dispose();
    });

    test('disable returns to files, remembers the folders, and persists', () async {
      final e = MusicModeEntry(_vault('/a'), store);
      await e.load();
      await e.enable(folders: ['Music']);
      await e.disable();
      expect(e.config.enabled, isFalse);
      expect(e.config.folders, ['Music']);
      expect(e.category, MusicCategory.files);

      final again = MusicModeEntry(_vault('/a'), store);
      await again.load();
      expect(again.config.enabled, isFalse);
      expect(again.config.folders, ['Music']);
      e.dispose();
      again.dispose();
    });

    test('setFolders normalizes, persists, and ignores a no-op', () async {
      final e = MusicModeEntry(_vault('/a'), store);
      await e.load();
      await e.enable();
      var notified = 0;
      e.addListener(() => notified++);

      await e.setFolders(['/B/', 'A']);
      expect(e.config.folders, ['A', 'B']);
      expect(notified, 1);

      await e.setFolders(['A', 'B']);
      expect(notified, 1);
      e.dispose();
    });

    test('switching category notifies only when it changes', () async {
      final e = MusicModeEntry(_vault('/a'), store);
      await e.load();
      await e.enable();
      var notified = 0;
      e.addListener(() => notified++);
      e.setCategory(MusicCategory.tracks);
      e.setCategory(MusicCategory.tracks);
      e.setCategory(MusicCategory.files);
      expect(notified, 2);
      expect(e.libraryVisible, isFalse);
      e.dispose();
    });

    test('the library is never visible while music mode is off', () async {
      final e = MusicModeEntry(_vault('/a'), store);
      await e.load();
      e.setCategory(MusicCategory.albums);
      expect(e.libraryVisible, isFalse);
      e.dispose();
    });

    test('a load that finishes after dispose does nothing', () async {
      final e = MusicModeEntry(_vault('/a'), store);
      final loading = e.load();
      e.dispose();
      await loading;
      expect(e.loaded, isFalse);
    });
  });

  group('per container', () {
    test('settings do not leak between containers or into local storage', () async {
      final a = MusicModeEntry(_vault('/a'), store);
      await a.enable(folders: ['Music']);
      final b = MusicModeEntry(_vault('/b'), store);
      final phone = MusicModeEntry(_phone(), store);
      await b.load();
      await phone.load();
      expect(b.config.enabled, isFalse);
      expect(phone.config.enabled, isFalse);
      a.dispose();
      b.dispose();
      phone.dispose();
    });

    test('phone storage keeps its setting in app storage, encrypted, not in the folder', () async {
      final phone = MusicModeEntry(_phone(), store);
      await phone.enable(folders: ['Secret Albums']);
      expect(platform.vault, isEmpty);
      expect(platform.app.length, 1);
      final plain = utf8.decode(platform.app.values.single, allowMalformed: true);
      // (The fake "encryption" leaves JSON readable; the point is the location.)
      expect(plain.contains('Secret Albums'), isTrue);
      final again = MusicModeEntry(_phone(), store);
      await again.load();
      expect(again.config.folders, ['Secret Albums']);
      phone.dispose();
      again.dispose();
    });
  });

  group('MusicModeRegistry', () {
    test('one entry per container, shared', () {
      final r = MusicModeRegistry(store);
      expect(identical(r.entryFor(_vault('/a')), r.entryFor(_vault('/a'))), isTrue);
      expect(identical(r.entryFor(_vault('/a')), r.entryFor(_vault('/b'))), isFalse);
    });

    test('an entry lives until its last holder releases it', () {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      final first = r.acquire(c);
      final second = r.acquire(c); // e.g. the same vault in a second pane
      expect(identical(first, second), isTrue);

      r.release(c);
      expect(r.entryCount, 1);
      r.release(c);
      expect(r.entryCount, 0);
    });

    test('after everything lets go, a new entry reloads the saved setting', () async {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      final e = r.acquire(c);
      await e.load();
      await e.enable(folders: ['Music']);
      r.release(c);

      final back = r.acquire(c);
      expect(identical(back, e), isFalse);
      await back.load();
      expect(back.config.enabled, isTrue);
      expect(back.config.folders, ['Music']);
      r.release(c);
    });

    test('releasing something never acquired is harmless', () {
      final r = MusicModeRegistry(store);
      r.release(_vault('/zzz'));
      expect(r.entryCount, 0);
    });
  });
}
