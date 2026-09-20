import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/features/sync/data/config/sync_config_store.dart';
import 'package:vaultexplorer/features/sync/services/sync_coordinator_service.dart';
import 'package:vaultexplorer/features/sync/services/sync_lock_barrier.dart';

// Plain (non-generated) providers on purpose: the sync feature adds no
// `.g.dart` files, so nothing needs build_runner to be re-run for it.
// (`syncLockBarrierProvider` lives with SyncLockBarrier so that
// vault_engine_providers.dart can depend on it without an import cycle.)

final syncConfigStoreProvider = Provider<SyncConfigStore>(
  (ref) => SyncConfigStore(ref.watch(vaultFileIoApiProvider)),
);

final syncTargetBindingStoreProvider = Provider<SyncTargetBindingStore>(
  (ref) => SyncTargetBindingStore(ref.watch(appSecureStorageProvider)),
);

/// The single coordinator that runs auto-sync for every unlocked vault.
final syncCoordinatorServiceProvider = Provider<SyncCoordinatorService>((ref) {
  final service = SyncCoordinatorService(
    fileIo: ref.watch(vaultFileIoApiProvider),
    hashApi: ref.watch(vaultHashApiProvider),
    events: ref.watch(vaultEngineEventsProvider),
    barrier: ref.watch(syncLockBarrierProvider),
    bindings: ref.watch(syncTargetBindingStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
