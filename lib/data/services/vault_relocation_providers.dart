import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_storage_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/services/biometric_enrollment_guard.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/vault_relocation_gateway.dart';
import 'package:vaultexplorer/data/services/vault_relocation_record_store.dart';
import 'package:vaultexplorer/data/services/vault_relocation_service.dart';
import 'package:vaultexplorer/features/unlock/unlock_lockout_throttle.dart';

// Hand-written (not code-generated) providers: nothing here needs a generated part file.

/// Vaults that live in the app's private storage (Android), and moving a vault in or out of it.
final vaultStorageApiProvider = Provider<VaultStorageApi>(
  (ref) => VaultStorageApi(ref.watch(vaultEngineChannelProvider)),
);

/// Moves a vault between where the user keeps it and app storage. One instance for the app, so "only
/// one move at a time" holds across screens.
final vaultRelocationServiceProvider = Provider<VaultRelocationService>((ref) {
  final events = ref.watch(vaultEngineEventsProvider);
  final splitJoin = ref.watch(vaultSplitJoinApiProvider);
  final guard = ref.watch(biometricEnrollmentGuardProvider);

  return VaultRelocationService(
    gateway: VaultRelocationGateway(
      storage: ref.watch(vaultStorageApiProvider),
      // Relocation reports through the Split/Join progress channel, on an opId range of its own.
      subscribeProgress: (listener) {
        void forward(SplitJoinProgress p) => listener(p.opId, p.bytesDone, p.bytesTotal);
        events.addSplitJoinProgressListener(forward);
        return () => events.removeSplitJoinProgressListener(forward);
      },
      cancelOperation: splitJoin.cancelSplitJoin,
    ),
    records: RepositoryRelocationRecordStore(
      repository: ref.watch(containerRepositoryProvider),
      isBiometricTrusted: (uri) async =>
          await guard.checkVault(uri) == BiometricGuardResult.ok,
      armBiometrics: guard.enableVault,
      carryLockouts: ({required fromUri, required toUri}) async {
        await PatternUnlockThrottle.carryOver(fromUri: fromUri, toUri: toUri);
        await PinUnlockThrottle.carryOver(fromUri: fromUri, toUri: toUri);
      },
    ),
  );
});
