import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/sync/data/config/sync_config_store.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/services/sync_providers.dart';

MountedContainer _testVault() => MountedContainer(
  uri: 'file:///vault.hc',
  displayName: 'Vault',
  volId: 1,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000,
  freeSpace: 500,
  containerFormat: 'veracrypt',
);

class FakeSyncConfigStore extends SyncConfigStore {
  SyncConfig? config;

  FakeSyncConfigStore(this.config) : super(_FakeFileIo());

  @override
  Future<SyncConfig?> load(MountedContainer vault) async => config;
}

class _FakeFileIo implements VaultFileIoApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('vaultSyncedFolderPathsProvider includes only active rules (onUnlock or liveWatch)', () async {
    final config = SyncConfig(
      vaultSyncId: 'vault-1',
      rules: const [
        SyncRule(
          id: 'rule-1',
          vaultInternalPath: 'Notes',
          targetEndpointUri: '/sdcard/Notes',
          autoSyncOnUnlock: true,
          liveWatch: false,
        ),
        SyncRule(
          id: 'rule-2',
          vaultInternalPath: 'Photos',
          targetEndpointUri: '/sdcard/Photos',
          autoSyncOnUnlock: false,
          liveWatch: false, // Disabled!
        ),
        SyncRule(
          id: 'rule-3',
          vaultInternalPath: 'Documents/Work',
          targetEndpointUri: '/sdcard/Work',
          autoSyncOnUnlock: false,
          liveWatch: true,
        ),
      ],
    );

    final fakeStore = FakeSyncConfigStore(config);
    final vault = _testVault();

    final container = ProviderContainer(
      overrides: [
        syncConfigStoreProvider.overrideWithValue(fakeStore),
      ],
    );
    addTearDown(container.dispose);

    // Initial read
    final notifier = container.read(vaultSyncedFolderPathsProvider(vault).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final paths = container.read(vaultSyncedFolderPathsProvider(vault));
    expect(paths, contains('Notes'));
    expect(paths, contains('Documents/Work'));
    expect(paths, isNot(contains('Photos')));

    // Synchronous immediate update (e.g. when rule editor saves or removes)
    notifier.update({'Notes', 'NewFolder'});
    expect(container.read(vaultSyncedFolderPathsProvider(vault)), {'Notes', 'NewFolder'});
  });
}
