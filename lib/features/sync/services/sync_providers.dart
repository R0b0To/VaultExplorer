import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/sync/data/config/sync_config_store.dart';
import 'package:vaultexplorer/features/sync/services/live_watch_service.dart';
import 'package:vaultexplorer/features/sync/services/sync_coordinator_service.dart';
import 'package:vaultexplorer/features/sync/services/sync_lock_barrier.dart';
import 'package:vaultexplorer/features/sync/services/sync_notification_bridge.dart';
import 'package:vaultexplorer/features/sync/services/sync_status.dart';

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

/// The single coordinator that runs sync for every unlocked vault.
final syncCoordinatorServiceProvider = Provider<SyncCoordinatorService>((ref) {
  final fileOps = ref.watch(fileOperationServiceProvider);
  final service = SyncCoordinatorService(
    fileIo: ref.watch(vaultFileIoApiProvider),
    hashApi: ref.watch(vaultHashApiProvider),
    events: ref.watch(vaultEngineEventsProvider),
    barrier: ref.watch(syncLockBarrierProvider),
    bindings: ref.watch(syncTargetBindingStoreProvider),
    liveWatch: LiveWatchService(fileOps: fileOps),
    notifier: SyncNotificationBridge(
      lifecycle: ref.watch(vaultLifecycleApiProvider),
      fileOps: fileOps,
      settings: ref.watch(appSettingsServiceProvider),
    ),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Live sync status for the dashboard banner. Rebuilds only when the status
/// actually changes.
final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(
  SyncStatusNotifier.new,
);

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() {
    final notifier = ref.watch(syncCoordinatorServiceProvider).status;
    void onChange() => state = notifier.value;
    notifier.addListener(onChange);
    ref.onDispose(() => notifier.removeListener(onChange));
    return notifier.value;
  }
}
