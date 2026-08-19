import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/viewer/playlist_controller.dart';

void main() {
  group('compareEntriesWithPinned', () {
    final entryA = RawEntry(name: 'a_file.mp4', isDir: false, sizeBytes: 100, modifiedSecs: 1000);
    final entryB = RawEntry(name: 'b_file.mp4', isDir: false, sizeBytes: 500, modifiedSecs: 2000);
    final entryZ = RawEntry(name: 'z_file.mp4', isDir: false, sizeBytes: 50, modifiedSecs: 500);

    test('pinned item comes before unpinned item regardless of alphabetical sort', () {
      final pinned = {'z_file.mp4'};
      final list = [entryA, entryB, entryZ];
      list.sort((a, b) => compareEntriesWithPinned(
        a,
        b,
        sortBy: SortBy.name,
        sortAscending: true,
        pinnedPaths: pinned,
      ));

      expect(list.map((e) => e.name).toList(), ['z_file.mp4', 'a_file.mp4', 'b_file.mp4']);
    });

    test('multiple pinned items are sorted among themselves by the active sort criteria', () {
      final pinned = {'z_file.mp4', 'b_file.mp4'};
      final list = [entryA, entryB, entryZ];
      list.sort((a, b) => compareEntriesWithPinned(
        a,
        b,
        sortBy: SortBy.name,
        sortAscending: true,
        pinnedPaths: pinned,
      ));

      expect(list.map((e) => e.name).toList(), ['b_file.mp4', 'z_file.mp4', 'a_file.mp4']);
    });

    test('pinned items respect parentPath prefix', () {
      final pinned = {'folder/z_file.mp4'};
      final list = [entryA, entryB, entryZ];
      list.sort((a, b) => compareEntriesWithPinned(
        a,
        b,
        sortBy: SortBy.name,
        sortAscending: true,
        pinnedPaths: pinned,
        parentPath: 'folder',
      ));

      expect(list.map((e) => e.name).toList(), ['z_file.mp4', 'a_file.mp4', 'b_file.mp4']);
    });

    test('pinned items come first when sorting descending by size', () {
      final pinned = {'z_file.mp4'}; // size 50 (smallest)
      final list = [entryA, entryB, entryZ]; // sizes: 100, 500, 50
      list.sort((a, b) => compareEntriesWithPinned(
        a,
        b,
        sortBy: SortBy.size,
        sortAscending: false,
        pinnedPaths: pinned,
      ));

      // z_file is pinned so it comes first, then remaining sorted by size desc: b (500), a (100)
      expect(list.map((e) => e.name).toList(), ['z_file.mp4', 'b_file.mp4', 'a_file.mp4']);
    });

    test('directoriesFirst prioritizes pinned directory, then unpinned directory, then pinned files, then unpinned files', () {
      final dir1 = RawEntry(name: 'unpinned_dir', isDir: true, sizeBytes: 0, modifiedSecs: 100);
      final dir2 = RawEntry(name: 'pinned_dir', isDir: true, sizeBytes: 0, modifiedSecs: 100);
      final file1 = RawEntry(name: 'unpinned_file.txt', isDir: false, sizeBytes: 10, modifiedSecs: 100);
      final file2 = RawEntry(name: 'pinned_file.txt', isDir: false, sizeBytes: 10, modifiedSecs: 100);

      final pinned = {'pinned_dir', 'pinned_file.txt'};
      final list = [file1, dir1, file2, dir2];
      list.sort((a, b) => compareEntriesWithPinned(
        a,
        b,
        sortBy: SortBy.name,
        sortAscending: true,
        pinnedPaths: pinned,
        directoriesFirst: true,
      ));

      expect(
        list.map((e) => e.name).toList(),
        ['pinned_dir', 'pinned_file.txt', 'unpinned_dir', 'unpinned_file.txt'],
      );
    });
  });

  group('PlaylistController pinned paths handling', () {
    final dummyContainer = MountedContainer(
      volId: 1,
      displayName: 'test_vault',
      uri: 'content://test',
      rootFiles: const [],
      mountedAt: DateTime.now(),
      totalSpace: 1024,
      freeSpace: 512,
    );

    test('initializes with pinnedPaths and maintains order', () {
      final files = ['pinned_z.mp4', 'a.mp4', 'b.mp4'];
      final controller = PlaylistController(
        container: dummyContainer,
        initialMediaFiles: files,
        initialIndex: 0,
        pinnedPaths: {'pinned_z.mp4'},
      );

      expect(controller.playlist, ['pinned_z.mp4', 'a.mp4', 'b.mp4']);
      expect(controller.currentFile, 'pinned_z.mp4');
      expect(controller.pinnedPaths, contains('pinned_z.mp4'));
    });

    test('updatePinnedPaths updates internal pinned paths', () {
      final files = ['a.mp4', 'b.mp4'];
      final controller = PlaylistController(
        container: dummyContainer,
        initialMediaFiles: files,
        initialIndex: 0,
      );

      expect(controller.pinnedPaths, isEmpty);
      controller.updatePinnedPaths({'b.mp4'});
      expect(controller.pinnedPaths, contains('b.mp4'));
    });

    test('toggleShuffle on and off preserves original pinned order', () {
      final files = ['pinned_z.mp4', 'a.mp4', 'b.mp4'];
      final controller = PlaylistController(
        container: dummyContainer,
        initialMediaFiles: files,
        initialIndex: 0,
        pinnedPaths: {'pinned_z.mp4'},
      );

      controller.toggleShuffle();
      expect(controller.isShuffled, isTrue);

      controller.toggleShuffle();
      expect(controller.isShuffled, isFalse);
      expect(controller.playlist, ['pinned_z.mp4', 'a.mp4', 'b.mp4']);
      expect(controller.currentIndex, 0);
    });
  });
}
