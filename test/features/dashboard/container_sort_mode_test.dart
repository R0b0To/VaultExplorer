import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

void main() {
  test('unlockStatus sort mode puts mounted containers first and preserves relative order', () {
    const recordA = ContainerRecord(
      uri: 'file:///vaultA',
      label: 'Vault A',
    );
    const recordB = ContainerRecord(
      uri: 'file:///vaultB',
      label: 'Vault B',
    );

    final mountedB = MountedContainer(
      uri: 'file:///vaultB',
      displayName: 'Vault B',
      volId: 1,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 2),
      totalSpace: 1000,
      freeSpace: 500,
    );

    final items = <VaultListItem>[
      LockedVaultItem(recordA, sortDate: DateTime(2026, 1, 1)),
      MountedVaultItem(mountedB, sortDate: DateTime(2026, 1, 2)),
    ];

    items.sort((a, b) {
      if (a.isMounted == b.isMounted) return 0;
      return a.isMounted ? -1 : 1;
    });

    // Unlocked Vault B must move above locked Vault A
    expect(items[0].name, equals('Vault B'));
    expect(items[1].name, equals('Vault A'));

    // When Vault B is locked again:
    final lockedB = LockedVaultItem(recordB, sortDate: DateTime(2026, 1, 2));
    final lockedItems = <VaultListItem>[
      lockedB,
      LockedVaultItem(recordA, sortDate: DateTime(2026, 1, 1)),
    ];

    lockedItems.sort((a, b) {
      if (a.isMounted == b.isMounted) return 0;
      return a.isMounted ? -1 : 1;
    });

    // Vault B remains at position 0 (sticky position preserved)
    expect(lockedItems[0].name, equals('Vault B'));
    expect(lockedItems[1].name, equals('Vault A'));
  });
}
