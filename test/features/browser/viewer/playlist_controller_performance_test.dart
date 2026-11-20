import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';

class _FakeVaultFileIoApi implements VaultFileIoApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PlaylistController scale and filtering performance', () {
    final dummyContainer = MountedContainer(
      volId: 1,
      displayName: 'test_vault',
      uri: 'content://test',
      rootFiles: const [],
      mountedAt: DateTime.now(),
      totalSpace: 1024,
      freeSpace: 512,
    );

    test('initializes 40,000 items in same folder instantly with Current Folder Only', () {
      final items = List<String>.generate(
        40000,
        (i) => 'photos/image_${i.toString().padLeft(5, '0')}.jpg',
        growable: false,
      );

      final sw = Stopwatch()..start();
      final controller = PlaylistController(
        container: dummyContainer,
        fileIoApi: _FakeVaultFileIoApi(),
        initialMediaFiles: items,
        initialIndex: 500,
        startingFolder: 'photos',
      );
      sw.stop();

      expect(controller.selectedFolder, 'Current Folder Only');
      expect(controller.allFilesScanned, isFalse);
      expect(controller.playlist.length, 40000);
      expect(controller.currentIndex, 500);
      expect(controller.currentFile, 'photos/image_00500.jpg');
      // Sub-100ms even on slow CI environments for 40,000 items
      expect(sw.elapsedMilliseconds, lessThan(100));
    });

    test('detects subfolder items in 40,000 items list and switches to All', () {
      final items = List<String>.generate(
        40000,
        (i) => i == 39999
            ? 'photos/subfolder/last.jpg'
            : 'photos/image_${i.toString().padLeft(5, '0')}.jpg',
        growable: false,
      );

      final controller = PlaylistController(
        container: dummyContainer,
        fileIoApi: _FakeVaultFileIoApi(),
        initialMediaFiles: items,
        initialIndex: 0,
        startingFolder: 'photos',
      );

      expect(controller.selectedFolder, 'All');
      expect(controller.allFilesScanned, isTrue);
      expect(controller.playlist.length, 40000);
    });

    test('folder filtering retains only direct children of base directory', () {
      final items = [
        'root_file.jpg',
        'folder/img1.jpg',
        'folder/img2.jpg',
        'folder/sub/nested.jpg',
        'other/file.jpg',
      ];

      final controller = PlaylistController(
        container: dummyContainer,
        fileIoApi: _FakeVaultFileIoApi(),
        initialMediaFiles: items,
        initialIndex: 1,
        startingFolder: 'folder',
      );

      expect(controller.selectedFolder, 'All');
      expect(controller.playlist.length, 5);

      // Disable/enable filtering
      controller.enablePlaylist('Current Folder Only');
      expect(controller.playlist, ['folder/img1.jpg', 'folder/img2.jpg']);
      expect(controller.currentIndex, 0);

      controller.enablePlaylist('All');
      expect(controller.playlist, items);
      expect(controller.currentIndex, 1);
    });
  });
}
