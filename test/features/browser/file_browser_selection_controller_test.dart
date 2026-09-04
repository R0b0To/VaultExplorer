import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';

MountedContainer _testContainer(int volId) => MountedContainer(
      volId: volId,
      uri: 'file:///vault$volId.hc',
      displayName: 'Vault $volId',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      containerFormat: 'veracrypt',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;

  const file1 = RawEntry(name: 'file1.txt', isDir: false, sizeBytes: 100, modifiedSecs: 1000);
  const file2 = RawEntry(name: 'file2.jpg', isDir: false, sizeBytes: 250, modifiedSecs: 1000);
  const dir1 = RawEntry(name: 'photos', isDir: true, sizeBytes: 0, modifiedSecs: 1000);
  const dir2 = RawEntry(name: 'documents', isDir: true, sizeBytes: 0, modifiedSecs: 1000);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getFolderSize') {
        final path = (call.arguments['dirPath'] ?? call.arguments['fatPath']) as String?;
        if (path != null && path.contains('photos')) return 1024;
        if (path != null && path.contains('documents')) return 2048;
        return 512;
      }
      return null;
    });

    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('FileBrowserSelection Controller Tests', () {
    test('Initial selection state is empty', () {
      final state = container.read(fileBrowserSelectionProvider(1));
      expect(state.items, isEmpty);
      expect(state.resolvedFolderSizes, isEmpty);
      expect(state.isSelectionMode, isFalse);
      expect(state.selectedFileCount, 0);
      expect(state.selectedFolderCount, 0);
      expect(state.selectedFileBytes, 0);
      expect(state.selectedTotalBytes, 0);
      expect(state.hasPendingFolderSizes, isFalse);
    });

    test('toggleSelectItem adds and removes items', () {
      final notifier = container.read(fileBrowserSelectionProvider(1).notifier);

      notifier.toggleSelectItem(file1);
      var state = container.read(fileBrowserSelectionProvider(1));
      expect(state.items, contains(file1));
      expect(state.isSelectionMode, isTrue);
      expect(state.selectedFileCount, 1);
      expect(state.selectedFileBytes, 100);

      // Add second item
      notifier.toggleSelectItem(file2);
      state = container.read(fileBrowserSelectionProvider(1));
      expect(state.items, containsAll([file1, file2]));
      expect(state.selectedFileCount, 2);
      expect(state.selectedFileBytes, 350);

      // Toggle off first item
      notifier.toggleSelectItem(file1);
      state = container.read(fileBrowserSelectionProvider(1));
      expect(state.items.contains(file1), isFalse);
      expect(state.items, contains(file2));
      expect(state.selectedFileCount, 1);
      expect(state.selectedFileBytes, 250);
    });

    test('setSelectedItems sets bulk selection', () {
      final notifier = container.read(fileBrowserSelectionProvider(1).notifier);

      notifier.setSelectedItems({file1, dir1});
      final state = container.read(fileBrowserSelectionProvider(1));
      expect(state.items, containsAll([file1, dir1]));
      expect(state.selectedFileCount, 1);
      expect(state.selectedFolderCount, 1);
      expect(state.hasPendingFolderSizes, isTrue);
    });

    test('exitSelectionMode resets to empty state', () {
      final notifier = container.read(fileBrowserSelectionProvider(1).notifier);
      notifier.setSelectedItems({file1, dir1});
      expect(container.read(fileBrowserSelectionProvider(1)).isSelectionMode, isTrue);

      notifier.exitSelectionMode();
      final state = container.read(fileBrowserSelectionProvider(1));
      expect(state.items, isEmpty);
      expect(state.resolvedFolderSizes, isEmpty);
      expect(state.isSelectionMode, isFalse);
    });

    test('fetchFolderSizes resolves folder sizes asynchronously', () async {
      final subscription = container.listen(fileBrowserSelectionProvider(1), (_, _) {});
      final notifier = container.read(fileBrowserSelectionProvider(1).notifier);

      notifier.setSelectedItems({file1, dir1, dir2});
      var state = container.read(fileBrowserSelectionProvider(1));
      expect(state.hasPendingFolderSizes, isTrue);
      expect(state.selectedTotalBytes, 100); // Only file1 initially

      final vault = _testContainer(1);
      await notifier.fetchFolderSizes(vault, '');

      state = container.read(fileBrowserSelectionProvider(1));
      expect(state.hasPendingFolderSizes, isFalse);
      expect(state.resolvedFolderSizes['photos'], 1024);
      expect(state.resolvedFolderSizes['documents'], 2048);
      // Total = 100 (file1) + 1024 (photos) + 2048 (documents) = 3172
      expect(state.selectedTotalBytes, 3172);

      subscription.close();
    });

    test('Family keyed per volId isolates selection state', () {
      container.read(fileBrowserSelectionProvider(1).notifier).setSelectedItems({file1});
      container.read(fileBrowserSelectionProvider(2).notifier).setSelectedItems({file2});

      expect(container.read(fileBrowserSelectionProvider(1)).items, contains(file1));
      expect(container.read(fileBrowserSelectionProvider(1)).items.contains(file2), isFalse);

      expect(container.read(fileBrowserSelectionProvider(2)).items, contains(file2));
      expect(container.read(fileBrowserSelectionProvider(2)).items.contains(file1), isFalse);
    });
  });
}
