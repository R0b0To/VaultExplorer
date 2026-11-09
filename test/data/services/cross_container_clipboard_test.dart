import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('CrossContainerClipboard.removeDeletedPaths', () {
    test('removes matching deleted files from the clipboard', () {
      final notifier = container.read(crossContainerClipboardProvider.notifier);
      notifier.set(
        volId: 1,
        displayName: 'Vault 1',
        cut: false,
        clipItems: const [
          ClipboardItem(path: 'dirA/file1.txt', isDir: false),
          ClipboardItem(path: 'dirA/file2.txt', isDir: false),
        ],
      );

      notifier.removeDeletedPaths(1, ['dirA/file1.txt']);

      final state = container.read(crossContainerClipboardProvider);
      expect(state.hasItems, isTrue);
      expect(state.items.length, 1);
      expect(state.items.first.path, 'dirA/file2.txt');
    });

    test('removes child items when their parent folder is deleted', () {
      final notifier = container.read(crossContainerClipboardProvider.notifier);
      notifier.set(
        volId: 1,
        displayName: 'Vault 1',
        cut: false,
        clipItems: const [
          ClipboardItem(path: 'folder/file1.txt', isDir: false),
          ClipboardItem(path: 'folder/sub/file2.txt', isDir: false),
          ClipboardItem(path: 'other/file3.txt', isDir: false),
        ],
      );

      notifier.removeDeletedPaths(1, ['folder']);

      final state = container.read(crossContainerClipboardProvider);
      expect(state.hasItems, isTrue);
      expect(state.items.length, 1);
      expect(state.items.first.path, 'other/file3.txt');
    });

    test('clears clipboard when all items are deleted', () {
      final notifier = container.read(crossContainerClipboardProvider.notifier);
      notifier.set(
        volId: 1,
        displayName: 'Vault 1',
        cut: true,
        clipItems: const [
          ClipboardItem(path: 'dirA/file1.txt', isDir: false),
        ],
      );

      notifier.removeDeletedPaths(1, ['dirA/file1.txt']);

      final state = container.read(crossContainerClipboardProvider);
      expect(state.hasItems, isFalse);
      expect(state.items, isEmpty);
      expect(state.sourceVolId, isNull);
    });

    test('ignores deletions on different volumes', () {
      final notifier = container.read(crossContainerClipboardProvider.notifier);
      notifier.set(
        volId: 1,
        displayName: 'Vault 1',
        cut: false,
        clipItems: const [
          ClipboardItem(path: 'dirA/file1.txt', isDir: false),
        ],
      );

      notifier.removeDeletedPaths(2, ['dirA/file1.txt']);

      final state = container.read(crossContainerClipboardProvider);
      expect(state.hasItems, isTrue);
      expect(state.items.length, 1);
      expect(state.items.first.path, 'dirA/file1.txt');
    });
  });
}
