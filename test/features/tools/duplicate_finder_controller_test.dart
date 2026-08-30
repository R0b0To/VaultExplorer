import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/duplicate_finder_models.dart';
import 'package:vaultexplorer/features/tools/widgets/duplicate_finder_controller.dart';

MountedContainer _testContainer() => MountedContainer(
      volId: 1,
      uri: 'file:///vault.hc',
      displayName: 'Vault',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      containerFormat: 'veracrypt',
    );

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('DuplicateFinderController Selection Tests', () {
    final vault = _testContainer();
    final file1 = VaultFileItem(container: vault, relativePath: 'a.jpg', name: 'a.jpg', sizeBytes: 500, modifiedSecs: 100);
    final file2 = VaultFileItem(container: vault, relativePath: 'b.jpg', name: 'b.jpg', sizeBytes: 500, modifiedSecs: 200);
    final file3 = VaultFileItem(container: vault, relativePath: 'c.jpg', name: 'c.jpg', sizeBytes: 500, modifiedSecs: 300);

    final group = DuplicateGroup(
      id: 'group_1',
      sizeBytes: 500,
      fullHash: 'hash_123',
      files: [file1, file2, file3],
    );

    test('initializes with default target as all vaults (-1) and allows target switching', () {
      final controller = container.read(duplicateFinderProvider.notifier);
      expect(container.read(duplicateFinderProvider).selectedTargetVolId, -1);
      expect(container.read(duplicateFinderProvider).isScanning, isFalse);
      expect(container.read(duplicateFinderProvider).groups, isEmpty);

      controller.setSelectedTargetVolId(10);
      expect(container.read(duplicateFinderProvider).selectedTargetVolId, 10);
    });

    test('toggleFileSelection updates individual item selection', () {
      final controller = container.read(duplicateFinderProvider.notifier);

      controller.toggleFileSelection(file1.id, true);
      expect(container.read(duplicateFinderProvider).selectedForDeletion[file1.id], isTrue);

      controller.toggleFileSelection(file1.id, false);
      expect(container.read(duplicateFinderProvider).selectedForDeletion[file1.id], isFalse);
    });

    test('selectedBytesTotal computes cumulative size of selected files', () {
      final state = DuplicateFinderState(
        groups: [group],
        selectedForDeletion: {
          file1.id: false, // kept
          file2.id: true,  // 500 B
          file3.id: true,  // 500 B
        },
      );

      expect(state.selectedCount, 2);
      expect(state.selectedBytesTotal, 1000);
    });
  });
}