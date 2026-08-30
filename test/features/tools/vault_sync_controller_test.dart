import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_controller.dart';

MountedContainer _testContainer({
  required int volId,
  required String uri,
  required String name,
  bool readOnly = false,
}) =>
    MountedContainer(
      volId: volId,
      uri: uri,
      displayName: name,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      readOnly: readOnly,
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

  group('VaultSyncController Tests', () {
    test('initDefaultSides populates left and right from container list', () {
      final vault1 = _testContainer(volId: 1, uri: 'file:///v1.hc', name: 'Vault 1');
      final vault2 = _testContainer(volId: 2, uri: 'file:///v2.hc', name: 'Vault 2');

      final controller = container.read(vaultSyncProvider.notifier);
      controller.initDefaultSides([vault1, vault2]);

      final state = container.read(vaultSyncProvider);
      expect(state.left?.container.volId, 1);
      expect(state.right?.container.volId, 2);
      expect(state.canCompare, isTrue);
    });

    test('swapSides exchanges left and right targets', () {
      final vault1 = _testContainer(volId: 1, uri: 'file:///v1.hc', name: 'Vault 1');
      final vault2 = _testContainer(volId: 2, uri: 'file:///v2.hc', name: 'Vault 2');

      final controller = container.read(vaultSyncProvider.notifier);
      controller.initDefaultSides([vault1, vault2]);
      controller.swapSides();

      final state = container.read(vaultSyncProvider);
      expect(state.left?.container.volId, 2);
      expect(state.right?.container.volId, 1);
    });

    test('setDirection updates sync direction and clears overrides', () {
      final controller = container.read(vaultSyncProvider.notifier);

      controller.setOverride('test.txt', EntryAction.copyToLeft);
      expect(container.read(vaultSyncProvider).overrides, isNotEmpty);

      controller.setDirection(SyncDirection.leftToRight);
      final state = container.read(vaultSyncProvider);
      expect(state.direction, SyncDirection.leftToRight);
      expect(state.overrides, isEmpty);
    });

    test('actionFor respects read-only destination constraints', () {
      final readOnlyVault = _testContainer(volId: 2, uri: 'file:///v2.hc', name: 'Vault 2 (RO)', readOnly: true);
      final normalVault = _testContainer(volId: 1, uri: 'file:///v1.hc', name: 'Vault 1');

      final controller = container.read(vaultSyncProvider.notifier);
      controller.initDefaultSides([normalVault, readOnlyVault]);

      const diffEntry = VaultDiffEntry(
        name: 'test.txt',
        relativePath: 'test.txt',
        status: VaultDiffStatus.onlyLeft,
        isDir: false,
        leftSizeBytes: 100,
        leftModifiedSecs: 1000,
      );

      final action = controller.actionFor(diffEntry);
      expect(action, equals(EntryAction.skip));
    });
  });
}