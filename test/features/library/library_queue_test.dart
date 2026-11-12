import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';
import 'package:vaultexplorer/features/library/widgets/library_widgets.dart';

/// A library queue must reach the viewer exactly as the library built it.
///
/// The library keeps it that way by passing [libraryQueueFolder] as the
/// viewer's `startingFolder` (see its doc comment). This test pins that
/// contract to the real `PlaylistController`, so a future change to how the
/// controller scopes folders fails here instead of silently letting the
/// viewer's folder toggle replace an album with its folder's contents.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/library-queue-file-io');
  const fileIoApi = VaultFileIoApi(channel);
  var channelCalls = 0;

  setUp(() {
    channelCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      channelCalls++;
      return <Object?>[];
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final container = MountedContainer(
    volId: 1,
    displayName: 'vault',
    uri: 'content://test',
    rootFiles: const [],
    mountedAt: DateTime(2026),
    totalSpace: 1024,
    freeSpace: 512,
  );

  // All in ONE folder: the case the viewer's folder toggle used to break.
  final albumFiles = [
    'Music/Album/01.mp3',
    'Music/Album/02.mp3',
    'Music/Album/03.mp3',
  ];

  PlaylistController build({required String startingFolder}) => PlaylistController(
        container: container,
        fileIoApi: fileIoApi,
        initialMediaFiles: albumFiles,
        initialIndex: 0,
        startingFolder: startingFolder,
        mediaFilter: 'audio',
      );

  test('a library queue starts on "All" with nothing left to scan', () {
    final c = build(startingFolder: libraryQueueFolder);
    expect(c.selectedFolder, 'All');
    expect(c.allFilesScanned, isTrue);
    expect(c.playlist, albumFiles);
  });

  test('widening to "All" does not rescan or replace the queue', () async {
    final c = build(startingFolder: libraryQueueFolder);
    await c.enablePlaylist('All');
    expect(channelCalls, 0);
    expect(c.playlist, albumFiles);
  });

  test('toggling the folder scope back and forth keeps the queue', () async {
    final c = build(startingFolder: libraryQueueFolder);
    await c.enablePlaylist('Current Folder Only');
    expect(c.playlist, albumFiles);
    await c.enablePlaylist('All');
    expect(c.playlist, albumFiles);
    expect(channelCalls, 0);
  });

  test('shuffle on and off returns to the library order', () {
    final c = build(startingFolder: libraryQueueFolder);
    c.toggleShuffle();
    expect(c.isShuffled, isTrue);
    c.toggleShuffle();
    expect(c.playlist, albumFiles);
  });

  test('control: without the library folder the same queue does rescan on "All"', () async {
    final c = build(startingFolder: 'Music/Album');
    expect(c.selectedFolder, 'Current Folder Only');
    expect(c.allFilesScanned, isFalse);
    await c.enablePlaylist('All');
    expect(channelCalls, greaterThan(0));
  });
}
