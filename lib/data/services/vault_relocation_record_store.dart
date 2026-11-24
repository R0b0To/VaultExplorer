import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/vault_relocation_service.dart';

const _kLogTag = 'VaultRelocation';

/// Whether [uri]'s biometric sentinel key is still valid, i.e. nothing was enrolled since it was
/// created (see `BiometricEnrollmentGuard.checkVault`). False also when that could not be established.
typedef BiometricTrustCheck = Future<bool> Function(String uri);

/// Creates the biometric sentinel key for [uri]. It trusts the biometrics enrolled *now*, so it must
/// only follow a [BiometricTrustCheck] that passed. False if Android refused.
typedef BiometricArm = Future<bool> Function(String uri);

/// Moves a vault's lockout state (failed pattern/PIN attempts) from one URI to another.
typedef LockoutCarryOver = Future<void> Function({required String fromUri, required String toUri});

/// [RelocationRecordStore] over [ContainerRepository]: re-keys the vault's record and credentials
/// ([ContainerRepository.relocate]) and applies the two policies a bare re-key must not decide alone.
///
///  * **Biometrics.** The sentinel key behind biometric unlock detects a fingerprint enrolled after
///    setup. Creating a new one for the new location would trust whatever is enrolled now, silently
///    forgiving such an enrollment. So the old sentinel is checked first, and the new one is created
///    only if that check passed. Otherwise (or if Android refuses the new key) the vault falls back to its
///    manual password, exactly as it would have at the next unlock.
///  * **Lockout.** Failed pattern/PIN attempts and any running lockout belong to the vault, so they move with
///    it. Moving a vault must not be a way to start with a clean slate.
class RepositoryRelocationRecordStore implements RelocationRecordStore {
  RepositoryRelocationRecordStore({
    required ContainerRepository repository,
    required BiometricTrustCheck isBiometricTrusted,
    required BiometricArm armBiometrics,
    required LockoutCarryOver carryLockouts,
  }) : _repository = repository,
       _isBiometricTrusted = isBiometricTrusted,
       _armBiometrics = armBiometrics,
       _carryLockouts = carryLockouts;

  final ContainerRepository _repository;
  final BiometricTrustCheck _isBiometricTrusted;
  final BiometricArm _armBiometrics;
  final LockoutCarryOver _carryLockouts;

  @override
  Future<RecordMove> moveRecord({
    required String oldUri,
    required String newUri,
  }) async {
    final record = (await _repository.loadAll())[oldUri];
    if (record == null) {
      throw StateError('No vault is registered at $oldUri');
    }

    var biometricsDropped = false;
    if (record.unlockMethod == ContainerUnlockMethod.biometrics) {
      var trusted = false;
      try {
        trusted = await _isBiometricTrusted(oldUri);
      } catch (e) {
        VeLog.w(_kLogTag, 'biometric check failed; falling back to the password: $e', e);
      }
      if (!trusted) {
        // Not trusted, or could not be told: do not carry biometrics over.
        await _repository.revertBiometricsToPassword(oldUri);
        biometricsDropped = true;
      }
    }

    final moved = await _repository.relocate(oldUri: oldUri, newUri: newUri);

    if (moved.unlockMethod == ContainerUnlockMethod.biometrics) {
      var armed = false;
      try {
        armed = await _armBiometrics(newUri);
      } catch (e) {
        VeLog.w(_kLogTag, 'could not create the biometric key for the new location: $e', e);
      }
      if (!armed) {
        await _repository.revertBiometricsToPassword(newUri);
        biometricsDropped = true;
      }
    }

    try {
      await _carryLockouts(fromUri: oldUri, toUri: newUri);
    } catch (e) {
      // The move itself is done; the lockout helper is best-effort by design.
      VeLog.w(_kLogTag, 'could not carry the unlock lockout over: $e', e);
    }
    return RecordMove(biometricsDropped: biometricsDropped);
  }
}
