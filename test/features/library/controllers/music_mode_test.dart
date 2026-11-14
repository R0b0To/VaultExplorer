import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
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
      // Music mode never reopens as the file listing with only the toolbar:
      // a saved enabled mode opens on the library.
      expect(second.category, MusicCategory.albums);
      expect(second.libraryVisible, isTrue);
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

    test('a hint that music mode is on opens on the library before the load', () {
      final e = MusicModeEntry(_vault('/a'), store);
      expect(e.pendingView, isTrue);
      expect(e.expectedEnabled, isFalse);

      e.applyHint(true);

      expect(e.hint, isTrue);
      expect(e.expectedEnabled, isTrue);
      expect(e.category, MusicCategory.albums);
      expect(e.pendingView, isTrue); // the view waits for the real setting
      e.dispose();
    });

    test('a hint that music mode is off settles the view at once', () {
      final e = MusicModeEntry(_vault('/a'), store);
      e.applyHint(false);

      expect(e.pendingView, isFalse);
      expect(e.expectedEnabled, isFalse);
      expect(e.category, MusicCategory.files);
      e.dispose();
    });

    test('the saved setting replaces a wrong hint once it is read', () async {
      final e = MusicModeEntry(_vault('/a'), store);
      e.applyHint(true); // this device thinks it is on; the vault says off
      await e.load();

      expect(e.config.enabled, isFalse);
      expect(e.expectedEnabled, isFalse);
      expect(e.hint, isNull);
      expect(e.category, MusicCategory.files);
      expect(e.pendingView, isFalse);

      e.applyHint(true); // too late: ignored
      expect(e.expectedEnabled, isFalse);
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
    const tabA = TabId(1);
    const tabB = TabId(2);

    test('one entry per tab, shared by everything showing that tab', () {
      final r = MusicModeRegistry(store);
      expect(
        identical(r.entryFor(_vault('/a'), tabA), r.entryFor(_vault('/a'), tabA)),
        isTrue,
      );
      expect(
        identical(r.entryFor(_vault('/a'), tabA), r.entryFor(_vault('/b'), tabB)),
        isFalse,
      );
    });

    test('two tabs on one container get their own entries and one scope', () {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      final first = r.entryFor(c, tabA);
      final second = r.entryFor(c, tabB);
      expect(identical(first, second), isFalse);
      expect(r.entryCount, 2);
      expect(r.scopeCount, 1);
    });

    test('an entry lives until its last holder releases it', () {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      final first = r.acquire(c, tabA);
      final second = r.acquire(c, tabA); // e.g. the host rebuilt in a new pane
      expect(identical(first, second), isTrue);

      r.release(c, tabA);
      expect(r.entryCount, 1);
      r.release(c, tabA);
      expect(r.entryCount, 0);
      expect(r.scopeCount, 0);
    });

    test('the container scope outlives a tab while another tab holds it', () {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      r.acquire(c, tabA);
      r.acquire(c, tabB);
      r.release(c, tabA);
      expect(r.entryCount, 1);
      expect(r.scopeCount, 1);
      r.release(c, tabB);
      expect(r.scopeCount, 0);
    });

    test('after everything lets go, a new entry reloads the saved setting', () async {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      final e = r.acquire(c, tabA);
      await e.load();
      await e.enable(folders: ['Music']);
      r.release(c, tabA);

      final back = r.acquire(c, tabA);
      expect(identical(back, e), isFalse);
      await back.load();
      expect(back.config.enabled, isTrue);
      expect(back.config.folders, ['Music']);
      r.release(c, tabA);
    });

    test('releasing something never acquired is harmless', () {
      final r = MusicModeRegistry(store);
      r.release(_vault('/zzz'), tabA);
      expect(r.entryCount, 0);
      expect(r.scopeCount, 0);
    });
  });

  group('modes are per tab on the same container', () {
    const tabA = TabId(1);
    const tabB = TabId(2);
    const tabC = TabId(3);

    test('enabling in one tab leaves the other tab on the file listing', () async {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      final a = r.acquire(c, tabA);
      final b = r.acquire(c, tabB);
      await a.load();
      await b.load();

      await a.enable(folders: ['Music']);

      expect(a.config.enabled, isTrue);
      expect(a.libraryVisible, isTrue);
      expect(b.config.enabled, isFalse);
      expect(b.libraryVisible, isFalse);
      expect(b.category, MusicCategory.files);
      r.release(c, tabA);
      r.release(c, tabB);
    });

    test('disabling in one tab leaves the other tab in music mode', () async {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      final a = r.acquire(c, tabA);
      final b = r.acquire(c, tabB);
      await a.load();
      await a.enable();
      await b.enable();

      await a.disable();

      expect(a.config.enabled, isFalse);
      expect(b.config.enabled, isTrue);
      expect(b.libraryVisible, isTrue);
      r.release(c, tabA);
      r.release(c, tabB);
    });

    test('the library view is chosen per tab', () async {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      final a = r.acquire(c, tabA);
      final b = r.acquire(c, tabB);
      await a.enable();
      await b.enable();

      a.setCategory(MusicCategory.tracks);

      expect(a.category, MusicCategory.tracks);
      expect(b.category, MusicCategory.albums);
      r.release(c, tabA);
      r.release(c, tabB);
    });

    test('the covered folders are shared by every tab on the container', () async {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      final a = r.acquire(c, tabA);
      final b = r.acquire(c, tabB);
      await a.load();
      var bNotified = 0;
      b.addListener(() => bNotified++);

      await a.enable(folders: ['Music']);
      expect(b.config.folders, ['Music']);
      expect(b.config.enabled, isFalse);

      await b.setFolders(['Podcasts']);
      expect(a.config.folders, ['Podcasts']);
      expect(bNotified, greaterThan(0));
      r.release(c, tabA);
      r.release(c, tabB);
    });

    test('a tab opened later starts in the latest saved choice', () async {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      final a = r.acquire(c, tabA);
      await a.load();
      await a.enable(folders: ['Music']);

      final later = r.acquire(c, tabC);
      expect(later.loaded, isTrue);
      expect(later.config.enabled, isTrue);
      expect(later.category, MusicCategory.albums);

      // Turning it off in the new tab changes what the NEXT tab opens in, not
      // the tab that is still in music mode.
      await later.disable();
      expect(a.config.enabled, isTrue);
      expect(a.libraryVisible, isTrue);
      expect(a.savedDefaultEnabled, isFalse);
      final next = r.acquire(c, const TabId(4));
      expect(next.config.enabled, isFalse);
      r.release(c, tabA);
      r.release(c, tabC);
      r.release(c, const TabId(4));
    });

    test('setDefaultForNewTabs never changes tabs that are already open', () async {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      final a = r.acquire(c, tabA);
      await a.load();
      await a.enable();

      await a.setDefaultForNewTabs(false);

      expect(a.config.enabled, isTrue);
      expect(a.savedDefaultEnabled, isFalse);
      r.release(c, tabA);
    });

    test('a tab that chose a mode before the load finished keeps it', () async {
      final r = MusicModeRegistry(store);
      final c = _vault('/a');
      // The vault was saved with music mode on.
      final seed = MusicModeEntry(c, store);
      await seed.load();
      await seed.enable(folders: ['Music']);
      seed.dispose();

      final a = r.acquire(c, tabA);
      await a.disable(); // chosen before the saved setting was adopted
      await a.load();

      expect(a.config.enabled, isFalse);
      // ...and it was saved on top of the saved folders, not over them.
      expect(a.savedDefaultEnabled, isFalse);
      expect(a.config.folders, ['Music']);
      r.release(c, tabA);
    });
  });
}
