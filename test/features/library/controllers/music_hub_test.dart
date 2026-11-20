import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/controllers/library_controller.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';
import 'package:vaultexplorer/features/library/index/library_scanner.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/audio_tags/$name').readAsBytesSync();

class _Tree {
  final Map<String, Uint8List> files = {};
  int readCalls = 0;

  LibraryFileAccess get access => LibraryFileAccess(
        list: (dir) async {
          final prefix = dir.isEmpty ? '' : '$dir/';
          final out = <String, LibraryFsEntry>{};
          for (final e in files.entries) {
            if (!e.key.startsWith(prefix)) continue;
            final rest = e.key.substring(prefix.length);
            final slash = rest.indexOf('/');
            if (slash < 0) {
              out[rest] = LibraryFsEntry(name: rest, isDir: false, sizeBytes: e.value.length, modifiedSecs: 1);
            } else {
              out[rest.substring(0, slash)] = LibraryFsEntry(name: rest.substring(0, slash), isDir: true);
            }
          }
          return out.values.toList();
        },
        read: (path, offset, length) async {
          readCalls++;
          final b = files[path];
          if (b == null) return null;
          if (offset >= b.length) return Uint8List(0);
          final end = offset + length > b.length ? b.length : offset + length;
          return Uint8List.sublistView(b, offset, end);
        },
      );
}

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
  Future<String> digest(String v) async => v.replaceAll('/', '_');
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
  Future<bool> containerFileExists(MountedContainer c, String path) async => vault.containsKey(_k(c, path));
  @override
  Future<Uint8List?> readContainerFile(MountedContainer c, String path) async => vault[_k(c, path)];
  @override
  Future<bool> writeContainerFile(MountedContainer c, String path, Uint8List b) async {
    vault[_k(c, path)] = b;
    return true;
  }

  @override
  Future<void> deleteContainerFile(MountedContainer c, String path) async => vault.remove(_k(c, path));
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

bool _audio(String n) => n.endsWith('.mp3') || n.endsWith('.flac') || n.endsWith('.ogg');

/// Lets scans started by `attach` (which are not awaited) finish.
Future<void> _settle(MusicHub hub) async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (!hub.isScanning && !hub.isLoading && hub.sourceCount > 0) {
      // One more tick so a controller that has not yet started is not missed.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (!hub.isScanning && !hub.isLoading) return;
    }
  }
}

void main() {
  late _Platform platform;
  late Map<String, _Tree> trees;
  late List<String> removed;

  MusicHub makeHub() => MusicHub(
        createController: (c) => LibraryController(
          access: (cc) => (trees[cc.uri] ?? _Tree()).access,
          store: LibraryIndexStore(platform),
          isAudioFile: _audio,
        ),
        onSourceRemoved: removed.add,
      );

  setUp(() {
    platform = _Platform();
    removed = [];
    trees = {
      '/vault': _Tree()
        ..files['Music/a.mp3'] = _fixture('mp3_v23_cover.mp3')
        ..files['Music/b.flac'] = _fixture('flac_cover.flac'),
      '/other': _Tree()
        ..files['Music/a.mp3'] = _fixture('mp3_v23_cover.mp3') // same path as in /vault
        ..files['Rock/c.ogg'] = _fixture('ogg_vorbis.ogg'),
    };
  });

  test('a single container is indexed and its own index is the library', () async {
    final hub = makeHub();
    hub.attach(_vault('/vault'));
    await _settle(hub);
    expect(hub.sourceCount, 1);
    expect(hub.index.trackCount, 2);
    expect(identical(hub.index, hub.controllerOf('/vault')!.index), isTrue);
    hub.dispose();
  });

  test('two containers merge into one library, and the same path in both is two tracks', () async {
    final hub = makeHub();
    hub.attach(_vault('/vault'));
    hub.attach(_vault('/other'));
    await _settle(hub);

    expect(hub.sourceCount, 2);
    expect(hub.index.trackCount, 4);
    expect(hub.index.tracks.where((t) => t.path == 'Music/a.mp3').length, 2);
    expect(hub.index.tracks.map((t) => t.source).toSet(), {'/vault', '/other'});
    // The shared fixture's tagged album is one album with tracks from both.
    final album = hub.index.albums.firstWhere((a) => a.title == 'Album_X');
    expect(album.tracks.map((t) => t.source).toSet(), {'/vault', '/other'});
    hub.dispose();
  });

  test('the merged index is reused until a container changes', () async {
    final hub = makeHub();
    hub.attach(_vault('/vault'));
    hub.attach(_vault('/other'));
    await _settle(hub);
    final first = hub.index;
    expect(identical(hub.index, first), isTrue);

    await hub.controllerOf('/other')!.rescan(rebuild: true);
    expect(identical(hub.index, first), isFalse);
    hub.dispose();
  });

  test('two tabs on one container share a single scan and index', () async {
    final hub = makeHub();
    hub.attach(_vault('/vault'));
    final controller = hub.controllerOf('/vault');
    hub.attach(_vault('/vault'));
    await _settle(hub);
    expect(identical(hub.controllerOf('/vault'), controller), isTrue);
    expect(trees['/vault']!.readCalls, lessThan(8)); // one scan, not two
    hub.dispose();
  });

  test('a library is dropped only when its last holder lets go', () async {
    final hub = makeHub();
    final c = _vault('/vault');
    hub.attach(c);
    hub.attach(c);
    await _settle(hub);

    hub.detach(c);
    expect(hub.isAttached('/vault'), isTrue);
    expect(removed, isEmpty);

    hub.detach(c);
    expect(hub.isAttached('/vault'), isFalse);
    expect(removed, ['/vault']);
    expect(hub.index.isEmpty, isTrue);
    hub.dispose();
  });

  test('detaching one container keeps the other and shrinks the merged library', () async {
    final hub = makeHub();
    hub.attach(_vault('/vault'));
    hub.attach(_vault('/other'));
    await _settle(hub);
    hub.detach(_vault('/other'));
    expect(hub.sourceCount, 1);
    expect(hub.index.trackCount, 2);
    expect(hub.index.tracks.every((t) => t.source == '/vault'), isTrue);
    hub.dispose();
  });

  test('folder scope applies per container', () async {
    final hub = makeHub();
    hub.attach(_vault('/vault'), folders: const ['Music']);
    hub.attach(_vault('/other'), folders: const ['Rock']);
    await _settle(hub);
    expect(hub.index.tracks.map((t) => '${t.source}:${t.path}').toSet(), {
      '/vault:Music/a.mp3',
      '/vault:Music/b.flac',
      '/other:Rock/c.ogg',
    });

    await hub.setFolders(_vault('/other'), const []);
    expect(hub.index.trackCount, 4);
    hub.dispose();
  });

  test('status is aggregated across containers', () async {
    final hub = makeHub();
    expect(hub.isScanning, isFalse);
    hub.attach(_vault('/vault'));
    hub.attach(_vault('/other'));
    await _settle(hub);
    expect(hub.isScanning, isFalse);
    expect(hub.walkIncomplete, isFalse);
    expect(hub.readFailures, 0);
    hub.dispose();
  });

  test('notifies listeners as libraries load', () async {
    final hub = makeHub();
    var notified = 0;
    hub.addListener(() => notified++);
    hub.attach(_vault('/vault'));
    await _settle(hub);
    expect(notified, greaterThan(1));
    hub.dispose();
  });

  test('dispose drops every library and reports each removal', () async {
    final hub = makeHub();
    hub.attach(_vault('/vault'));
    hub.attach(_vault('/other'));
    await _settle(hub);
    hub.dispose();
    expect(removed.toSet(), {'/vault', '/other'});
  });

  test('attaching after dispose does nothing', () {
    final hub = makeHub()..dispose();
    hub.attach(_vault('/vault'));
    expect(hub.sourceCount, 0);
  });
}
