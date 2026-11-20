import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/controllers/library_controller.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';
import 'package:vaultexplorer/features/library/index/library_scanner.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/audio_tags/$name').readAsBytesSync();

class _Tree {
  final Map<String, Uint8List> files = {};
  final Map<String, int> mtimes = {};
  final Set<String> failingDirs = {};
  int readCalls = 0;
  Future<void> Function()? onRead;

  void add(String path, Uint8List bytes, {int mtime = 1}) {
    files[path] = bytes;
    mtimes[path] = mtime;
  }

  LibraryFileAccess get access => LibraryFileAccess(
        list: (dir) async {
          if (failingDirs.contains(dir)) return null;
          final prefix = dir.isEmpty ? '' : '$dir/';
          final out = <String, LibraryFsEntry>{};
          for (final e in files.entries) {
            if (!e.key.startsWith(prefix)) continue;
            final rest = e.key.substring(prefix.length);
            final slash = rest.indexOf('/');
            if (slash < 0) {
              out[rest] = LibraryFsEntry(
                name: rest,
                isDir: false,
                sizeBytes: e.value.length,
                modifiedSecs: mtimes[e.key]!,
              );
            } else {
              out[rest.substring(0, slash)] =
                  LibraryFsEntry(name: rest.substring(0, slash), isDir: true);
            }
          }
          return out.values.toList();
        },
        read: (path, offset, length) async {
          readCalls++;
          await onRead?.call();
          final b = files[path];
          if (b == null) return null;
          if (offset >= b.length) return Uint8List(0);
          final end = offset + length > b.length ? b.length : offset + length;
          return Uint8List.sublistView(b, offset, end);
        },
      );
}

/// Identity "encryption" and in-memory files: enough to test the controller's
/// use of the store.
class _Platform implements LibraryStorePlatform {
  final Map<String, Uint8List> app = {};
  final Map<String, Uint8List> vault = {};
  int indexWrites = 0;

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
  Future<String> digest(String v) async => v.replaceAll('/', '_');
  @override
  Future<Uint8List?> readAppFile(String path) async => app[path];
  @override
  Future<bool> writeAppFile(String path, Uint8List bytes) async {
    if (path.endsWith('.idx')) indexWrites++;
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
    if (path.endsWith('music-index.bin')) indexWrites++;
    vault[_k(c, path)] = b;
    return true;
  }

  @override
  Future<void> deleteContainerFile(MountedContainer c, String path) async =>
      vault.remove(_k(c, path));
}

MountedContainer _vault(String uri, {bool readOnly = false}) => MountedContainer(
      uri: uri,
      displayName: uri,
      volId: 0,
      rootFiles: const [],
      mountedAt: DateTime(2026),
      totalSpace: 0,
      freeSpace: 0,
      readOnly: readOnly,
    );

MountedContainer _phone() =>
    buildLocalStorageContainer(rootPath: '/sdcard/Music', displayName: 'Phone');

bool _audio(String n) => n.endsWith('.mp3') || n.endsWith('.flac') || n.endsWith('.ogg');

_Tree _library() {
  final t = _Tree();
  t.add('Rock/a.mp3', _fixture('mp3_v23_cover.mp3'));
  t.add('Rock/b.flac', _fixture('flac_cover.flac'));
  t.add('Jazz/c.ogg', _fixture('ogg_vorbis.ogg'));
  return t;
}

LibraryController _controller(
  _Tree tree,
  _Platform platform, {
  Map<String, _Tree>? trees,
  int checkpointTracks = 1500,
  int minApplyGapMs = 1500,
}) =>
    LibraryController(
      access: (c) => (trees?[c.uri] ?? tree).access,
      store: LibraryIndexStore(platform),
      isAudioFile: _audio,
      checkpointTracks: checkpointTracks,
      minApplyGapMs: minApplyGapMs,
    );

void main() {
  test('open scans an empty container, fills the index and saves it', () async {
    final tree = _library();
    final platform = _Platform();
    final c = _controller(tree, platform);
    final phases = <LibraryPhase>[];
    c.addListener(() => phases.add(c.phase));

    await c.open(_vault('/v1'));

    expect(c.phase, LibraryPhase.ready);
    expect(c.index.trackCount, 3);
    expect(c.index.albums.any((a) => a.title == 'Album_X'), isTrue);
    expect(c.loadedFromSaved, isTrue); // saved at the end of the scan
    expect(phases.first, LibraryPhase.loading);
    expect(phases.contains(LibraryPhase.scanning), isTrue);
    expect(phases.last, LibraryPhase.ready);
    c.dispose();
  });

  test('a writable vault saves its index inside the vault', () async {
    final platform = _Platform();
    final c = _controller(_library(), platform);
    await c.open(_vault('/v1'));
    expect(c.location, LibraryLocation.inVault);
    expect(platform.vault.keys.single, '/v1|.vaultexplorer/music-index.bin');
    expect(platform.app, isEmpty);
    c.dispose();
  });

  test('phone storage saves its index in the app\'s encrypted storage, never in the folder', () async {
    final platform = _Platform();
    final c = _controller(_library(), platform);
    await c.open(_phone());
    expect(c.location, LibraryLocation.thisDevice);
    expect(platform.app.length, 1);
    expect(platform.vault, isEmpty);
    expect(c.index.trackCount, 3);
    c.dispose();
  });

  for (final entry in {
    'vault': () => _vault('/v1'),
    'phone storage': _phone,
  }.entries) {
    test('${entry.key}: reopening shows the saved index at once and reads no files', () async {
      final tree = _library();
      final platform = _Platform();
      final first = _controller(tree, platform);
      await first.open(entry.value());
      first.dispose();
      tree.readCalls = 0;

      final second = _controller(tree, platform);
      var sawSavedWhileScanning = false;
      second.addListener(() {
        if (second.phase == LibraryPhase.scanning && second.index.trackCount == 3) {
          sawSavedWhileScanning = true;
        }
      });
      await second.open(entry.value());

      expect(sawSavedWhileScanning, isTrue);
      expect(second.loadedFromSaved, isTrue);
      expect(tree.readCalls, 0);
      expect(second.index.trackCount, 3);
      second.dispose();
    });
  }

  test('a rescan picks up a new file and drops a deleted one', () async {
    final tree = _library();
    final c = _controller(tree, _Platform());
    await c.open(_vault('/v1'));

    tree.files.remove('Jazz/c.ogg');
    tree.mtimes.remove('Jazz/c.ogg');
    tree.add('Rock/new.mp3', _fixture('mp3_v1_only.mp3'));
    await c.rescan();

    expect(c.index.tracks.map((t) => t.path).toSet(), {
      'Rock/a.mp3',
      'Rock/b.flac',
      'Rock/new.mp3',
    });
    c.dispose();
  });

  group('folder scope', () {
    test('only the chosen folders are indexed', () async {
      final tree = _library();
      final c = _controller(tree, _Platform());
      await c.open(_vault('/v1'), folders: ['Rock']);
      expect(c.index.tracks.map((t) => t.path).toSet(), {'Rock/a.mp3', 'Rock/b.flac'});
      expect(c.folders, ['Rock']);
      c.dispose();
    });

    test('changing the folders rescans: new ones are read, dropped ones leave the index', () async {
      final tree = _library();
      final c = _controller(tree, _Platform());
      await c.open(_vault('/v1'), folders: ['Rock']);

      tree.readCalls = 0;
      await c.setFolders(['Jazz']);
      expect(c.index.tracks.map((t) => t.path).toSet(), {'Jazz/c.ogg'});
      expect(tree.readCalls, greaterThan(0));

      // Back to everything: only what is missing is read again.
      tree.readCalls = 0;
      await c.setFolders(const []);
      expect(c.index.trackCount, 3);
      c.dispose();
    });

    test('the saved index is reused when reopening with a narrower scope', () async {
      final tree = _library();
      final platform = _Platform();
      final first = _controller(tree, platform);
      await first.open(_vault('/v1'));
      first.dispose();

      tree.readCalls = 0;
      final second = _controller(tree, platform);
      await second.open(_vault('/v1'), folders: ['Jazz']);
      expect(second.index.tracks.map((t) => t.path).toSet(), {'Jazz/c.ogg'});
      expect(tree.readCalls, 0); // nothing needed re-reading
      second.dispose();
    });
  });

  test('a folder that cannot be listed does not cause its tracks to be dropped', () async {
    final tree = _library();
    final c = _controller(tree, _Platform());
    await c.open(_vault('/v1'));
    expect(c.index.trackCount, 3);

    tree.failingDirs.add('Jazz');
    await c.rescan();
    expect(c.index.trackCount, 3);
    expect(c.walkIncomplete, isTrue);

    tree.failingDirs.clear();
    await c.rescan();
    expect(c.walkIncomplete, isFalse);
    c.dispose();
  });

  test('rebuild re-reads every file; a plain rescan does not', () async {
    final tree = _library();
    final c = _controller(tree, _Platform());
    await c.open(_vault('/v1'));

    tree.readCalls = 0;
    await c.rescan();
    expect(tree.readCalls, 0);

    await c.rescan(rebuild: true);
    expect(tree.readCalls, greaterThanOrEqualTo(3));
    expect(c.index.trackCount, 3);
    c.dispose();
  });

  group('saving a big first scan', () {
    _Tree many(int n) {
      final tree = _Tree();
      for (var i = 0; i < n; i++) {
        tree.add('Many/f$i.mp3', _fixture('mp3_v23_cover.mp3'));
      }
      return tree;
    }

    test('checkpoints are written while the scan runs, not only at the end', () async {
      final platform = _Platform();
      final c = _controller(many(80), platform, checkpointTracks: 10, minApplyGapMs: 0);
      await c.open(_vault('/v1'));
      expect(c.index.trackCount, 80);
      expect(platform.indexWrites, greaterThan(1));
      c.dispose();
    });

    test('an interrupted first scan resumes from what was saved', () async {
      final tree = many(80);
      final platform = _Platform();
      late LibraryController first;
      var reads = 0;
      tree.onRead = () async {
        // The vault locks / the app dies partway through.
        if (++reads == 120) first.dispose();
      };
      first = _controller(tree, platform, checkpointTracks: 10, minApplyGapMs: 0);
      await first.open(_vault('/v1'));
      expect(platform.indexWrites, greaterThan(0));

      tree.onRead = null;
      tree.readCalls = 0;
      final second = _controller(tree, platform);
      await second.open(_vault('/v1'));
      expect(second.index.trackCount, 80);
      // It did not start over: fewer reads than a from-scratch scan needs.
      final fromScratch = _Tree();
      for (var i = 0; i < 80; i++) {
        fromScratch.add('Many/f$i.mp3', _fixture('mp3_v23_cover.mp3'));
      }
      final control = _controller(fromScratch, _Platform());
      await control.open(_vault('/control'));
      expect(tree.readCalls, lessThan(fromScratch.readCalls));
      second.dispose();
      control.dispose();
    });
  });

  test('cancelling a scan keeps and saves what was found', () async {
    final tree = _Tree();
    for (var i = 0; i < 60; i++) {
      tree.add('Many/f$i.mp3', _fixture('mp3_v23_cover.mp3'));
    }
    final platform = _Platform();
    final c = _controller(tree, platform);
    var reads = 0;
    tree.onRead = () async {
      if (++reads == 8) c.cancelScan();
    };
    await c.open(_vault('/v1'));

    expect(c.phase, LibraryPhase.ready);
    expect(c.index.trackCount, greaterThan(0));
    expect(c.index.trackCount, lessThan(60));
    expect(platform.vault.length, 1);
    c.dispose();
  });

  test('disposing mid-scan stops cleanly with no final save', () async {
    final tree = _Tree();
    for (var i = 0; i < 40; i++) {
      tree.add('Many/f$i.mp3', _fixture('mp3_v23_cover.mp3'));
    }
    final platform = _Platform();
    late LibraryController c;
    var reads = 0;
    tree.onRead = () async {
      if (++reads == 5) c.dispose();
    };
    c = _controller(tree, platform);
    await c.open(_vault('/v1'));
    expect(c.index.trackCount, 0);
    expect(platform.vault, isEmpty);
  });

  test('opening another container supersedes a scan in progress', () async {
    final slow = _Tree();
    for (var i = 0; i < 40; i++) {
      slow.add('Many/f$i.mp3', _fixture('mp3_v23_cover.mp3'));
    }
    final fast = _library();
    final platform = _Platform();
    late LibraryController c;
    c = _controller(slow, platform, trees: {'/slow': slow, '/fast': fast});

    var reads = 0;
    Future<void>? second;
    slow.onRead = () async {
      if (++reads == 4) second = c.open(_vault('/fast'));
    };
    final first = c.open(_vault('/slow'));
    await first;
    await second;

    expect(c.container!.uri, '/fast');
    expect(c.index.trackCount, 3);
    expect(c.index.tracks.every((t) => t.path != 'Many/f1.mp3'), isTrue);
    c.dispose();
  });

  test('clearSavedIndex removes the saved copy', () async {
    final platform = _Platform();
    final c = _controller(_library(), platform);
    await c.open(_vault('/v1'));
    expect(platform.vault.length, 1);
    await c.clearSavedIndex();
    expect(platform.vault, isEmpty);
    expect(c.loadedFromSaved, isFalse);
    c.dispose();
  });

  test('close drops the index, cancels a scan and returns to idle', () async {
    final tree = _Tree();
    for (var i = 0; i < 40; i++) {
      tree.add('Many/f$i.mp3', _fixture('mp3_v23_cover.mp3'));
    }
    final platform = _Platform();
    final c = _controller(tree, platform);
    var reads = 0;
    tree.onRead = () async {
      if (++reads == 6) c.close();
    };
    await c.open(_vault('/v1'));

    expect(c.phase, LibraryPhase.idle);
    expect(c.container, isNull);
    expect(c.index.trackCount, 0);
    expect(platform.vault, isEmpty); // the abandoned scan must not save
    c.dispose();
  });
}
