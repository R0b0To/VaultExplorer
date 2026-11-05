import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_controller.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';

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


  group('VaultSyncController with device and provider storage', () {
    test('a nested folder in the same vault cannot be compared', () {
      final vault = _testContainer(volId: 1, uri: 'file:///v1.hc', name: 'Vault 1');
      final controller = container.read(vaultSyncProvider.notifier);
      controller.setSide(
        isLeft: true,
        side: VaultSyncSide(container: vault, relativePath: ''),
      );
      controller.setSide(
        isLeft: false,
        side: VaultSyncSide(container: vault, relativePath: 'backup'),
      );

      final state = container.read(vaultSyncProvider);
      expect(state.sidesOverlap, isTrue);
      expect(state.canCompare, isFalse);
    });

    test('sibling folders in the same vault can be compared', () {
      final vault = _testContainer(volId: 1, uri: 'file:///v1.hc', name: 'Vault 1');
      final controller = container.read(vaultSyncProvider.notifier);
      controller.setSide(
        isLeft: true,
        side: VaultSyncSide(container: vault, relativePath: 'photos'),
      );
      controller.setSide(
        isLeft: false,
        side: VaultSyncSide(container: vault, relativePath: 'photos-backup'),
      );

      expect(container.read(vaultSyncProvider).canCompare, isTrue);
    });

    test('a vault can be compared against device storage or a provider', () {
      final vault = _testContainer(volId: 1, uri: 'file:///v1.hc', name: 'Vault 1');
      final local = buildLocalStorageContainer(
        rootPath: '/storage/emulated/0',
        displayName: 'Local Storage',
      );
      final provider = buildExternalStorageContainer(
        rootPath: 'content://provider/tree/x',
        displayName: 'Drive',
        volId: -100,
      );
      final controller = container.read(vaultSyncProvider.notifier);
      controller.setSide(
        isLeft: true,
        side: VaultSyncSide(container: vault, relativePath: ''),
      );

      controller.setSide(
        isLeft: false,
        side: VaultSyncSide(container: local, relativePath: 'Backups'),
      );
      expect(container.read(vaultSyncProvider).canCompare, isTrue);

      controller.setSide(
        isLeft: false,
        side: VaultSyncSide(container: provider, relativePath: ''),
      );
      expect(container.read(vaultSyncProvider).canCompare, isTrue);
    });

    test('the same folder reached through two containers is not comparable', () {
      final local = buildLocalStorageContainer(
        rootPath: '/storage/emulated/0',
        displayName: 'Local Storage',
      );
      final saved = buildExternalStorageContainer(
        rootPath: '/storage/emulated/0/Documents',
        displayName: 'Documents',
        volId: -100,
      );
      final controller = container.read(vaultSyncProvider.notifier);
      controller.setSide(
        isLeft: true,
        side: VaultSyncSide(container: local, relativePath: 'Documents'),
      );
      controller.setSide(
        isLeft: false,
        side: VaultSyncSide(container: saved, relativePath: ''),
      );

      expect(container.read(vaultSyncProvider).canCompare, isFalse);
    });

    test('plaintextExportTargets is empty until there is something to sync', () {
      final vault = _testContainer(volId: 1, uri: 'file:///v1.hc', name: 'Vault 1');
      final local = buildLocalStorageContainer(
        rootPath: '/storage/emulated/0',
        displayName: 'Local Storage',
      );
      final controller = container.read(vaultSyncProvider.notifier);
      expect(controller.plaintextExportTargets(), isEmpty);

      controller.setSide(
        isLeft: true,
        side: VaultSyncSide(container: vault, relativePath: ''),
      );
      controller.setSide(
        isLeft: false,
        side: VaultSyncSide(container: local, relativePath: 'Backups'),
      );
      // Sides chosen but no comparison run yet -> no entries -> no warning.
      expect(controller.plaintextExportTargets(), isEmpty);
    });
  });

  group('VaultSyncController delete and copy rules', () {
    VaultDiffEntry entry(
      VaultDiffStatus status, {
      bool isDir = false,
      bool typeMismatch = false,
    }) => VaultDiffEntry(
      name: 'a',
      relativePath: 'a',
      status: status,
      isDir: isDir,
      typeMismatch: typeMismatch,
    );

    VaultSync setUpSides({bool rightReadOnly = false}) {
      final left = _testContainer(volId: 1, uri: 'file:///l.hc', name: 'Left');
      final right = _testContainer(
        volId: 2,
        uri: 'file:///r.hc',
        name: 'Right',
        readOnly: rightReadOnly,
      );
      final controller = container.read(vaultSyncProvider.notifier);
      controller.initDefaultSides([left, right]);
      return controller;
    }

    test('canApply only offers an action on a side that holds the entry', () {
      final c = setUpSides();
      final onlyLeft = entry(VaultDiffStatus.onlyLeft);
      expect(c.canApply(onlyLeft, EntryAction.copyToRight), isTrue);
      expect(c.canApply(onlyLeft, EntryAction.copyToLeft), isFalse);
      expect(c.canApply(onlyLeft, EntryAction.deleteLeft), isTrue);
      expect(c.canApply(onlyLeft, EntryAction.deleteRight), isFalse);
      expect(c.canApply(onlyLeft, EntryAction.skip), isTrue);

      final both = entry(VaultDiffStatus.leftNewer);
      expect(c.canApply(both, EntryAction.deleteLeft), isTrue);
      expect(c.canApply(both, EntryAction.deleteRight), isTrue);
    });

    test('a read-only side can be neither copied into nor deleted from', () {
      final c = setUpSides(rightReadOnly: true);
      final both = entry(VaultDiffStatus.leftNewer);
      expect(c.canApply(both, EntryAction.copyToRight), isFalse);
      expect(c.canApply(both, EntryAction.deleteRight), isFalse);
      expect(c.canApply(both, EntryAction.copyToLeft), isTrue);
      expect(c.canApply(both, EntryAction.deleteLeft), isTrue);
    });

    test('actionFor never plans a delete on a read-only side', () {
      final c = setUpSides(rightReadOnly: true);
      final onlyRight = entry(VaultDiffStatus.onlyRight);
      c.setOverride(onlyRight.id, EntryAction.deleteRight);
      expect(c.actionFor(onlyRight), EntryAction.skip);
    });

    test('mirroring onto a writable side plans the delete of extras', () {
      final c = setUpSides();
      c.setDirection(SyncDirection.mirrorToRight);
      expect(
        c.actionFor(entry(VaultDiffStatus.onlyRight)),
        EntryAction.deleteRight,
      );
    });

    test('items already in sync and folders on both sides are never copied',
        () {
      final c = setUpSides();
      expect(
        c.canApply(entry(VaultDiffStatus.identical), EntryAction.copyToRight),
        isFalse,
      );
      expect(
        c.canApply(
          entry(VaultDiffStatus.bothFolders, isDir: true),
          EntryAction.copyToLeft,
        ),
        isFalse,
      );
      // ...but they can still be deleted.
      expect(
        c.canApply(
          entry(VaultDiffStatus.bothFolders, isDir: true),
          EntryAction.deleteRight,
        ),
        isTrue,
      );
    });

    test('a file-versus-folder mismatch cannot be copied but can be deleted',
        () {
      final c = setUpSides();
      final mismatch = entry(VaultDiffStatus.conflicted, typeMismatch: true);
      expect(c.canApply(mismatch, EntryAction.copyToRight), isFalse);
      expect(c.canApply(mismatch, EntryAction.copyToLeft), isFalse);
      expect(c.canApply(mismatch, EntryAction.deleteLeft), isTrue);
      expect(c.canApply(mismatch, EntryAction.deleteRight), isTrue);
    });

    test('selection toggles and clears', () {
      final c = container.read(vaultSyncProvider.notifier);
      c.toggleSelected('a');
      c.toggleSelected('b');
      expect(container.read(vaultSyncProvider).selectedIds, {'a', 'b'});
      c.toggleSelected('a');
      expect(container.read(vaultSyncProvider).selectedIds, {'b'});
      c.clearSelection();
      expect(container.read(vaultSyncProvider).selectedIds, isEmpty);
    });

    test('changing the filter and sort is reflected in state', () {
      final c = container.read(vaultSyncProvider.notifier);
      c.setFilter(VaultSyncFilter.deletions);
      c.setSort(VaultSyncSort.size);
      final state = container.read(vaultSyncProvider);
      expect(state.filter, VaultSyncFilter.deletions);
      expect(state.sort, VaultSyncSort.size);
    });
  });
}
