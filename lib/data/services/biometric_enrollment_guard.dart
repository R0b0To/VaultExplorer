import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';

const _kLogTag = 'BiometricEnrollmentGuard';

/// Id of the biometric sentinel key that guards the master lock's biometric
/// unlock. Vaults use [vaultBiometricKeyId].
const kMasterBiometricKeyId = 'master';

/// Outcome of checking whether biometric unlock may still be used.
enum BiometricGuardResult {
  /// The device's biometrics are unchanged since biometric unlock was set up.
  /// Go ahead and prompt.
  ok,

  /// They changed (a biometric was enrolled, or all were removed), or biometric
  /// unlock was never set up on this device. Biometric unlock has just been
  /// switched off and a password, PIN or pattern is required. The caller must
  /// stop the biometric flow, show that credential's UI and say why.
  reverted,

  /// The Keystore could not say. Refuse this attempt and offer the fallback credential,
  /// but nothing was switched off: this is not evidence of a change.
  unavailable,
}

/// Makes biometric unlock safe against a newly enrolled biometric.
///
/// Biometric unlock in this app is a system prompt in front of credentials
/// kept in Keystore-backed storage (the master lock's password, a vault's saved
/// password and cached key). None of those storage keys are tied to the user's
/// biometrics, so Android never invalidates anything when someone enrolls an
/// additional fingerprint or face -- and that new biometric then passes the
/// prompt. A *sentinel* key per biometric-protected thing (see
/// `VaultCryptoApi.createBiometricKey`) closes that: Android permanently
/// invalidates it on enrollment, and this class reacts by turning biometric
/// unlock off for what it guarded.
///
///  - the master lock goes back to its password, PIN or pattern;
///  - a vault goes back to a manual password, dropping its saved credentials.
///
/// Fails closed: a sentinel that is missing counts the same as an invalidated
/// one. Installs that had biometric unlock before this existed have none, so
/// they are switched to the password once, and biometrics can be set up again
/// afterwards.
class BiometricEnrollmentGuard {
  BiometricEnrollmentGuard({
    required VaultCryptoApi cryptoApi,
    required ContainerRepository repository,
    required AppSettingsService settings,
  }) : _crypto = cryptoApi,
       _repository = repository,
       _settings = settings;

  final VaultCryptoApi _crypto;
  final ContainerRepository _repository;
  final AppSettingsService _settings;

  // -- Master lock ----------------------------------------------------------

  /// Starts trusting the biometrics enrolled right now for the master lock.
  /// False when Android refused (no biometric enrolled, no secure lock
  /// screen); biometric unlock must then not be turned on.
  Future<bool> enableMaster() => _create(kMasterBiometricKeyId);

  /// Drops the master lock's sentinel once biometrics are no longer its method.
  Future<void> forgetMaster() => _delete(kMasterBiometricKeyId);

  /// Checks the master lock's biometric unlock before it is offered or
  /// accepted. On [BiometricGuardResult.reverted] the persisted settings
  /// already use a stored credential.
  Future<BiometricGuardResult> checkMaster() async {
    final status = await _crypto.biometricKeyStatus(kMasterBiometricKeyId);
    if (status == BiometricKeyStatus.valid) return BiometricGuardResult.ok;
    if (!status.requiresRevert) return BiometricGuardResult.unavailable;
    VeLog.w(_kLogTag, 'Master biometrics changed ($status); using the fallback credential');
    await revertMaster();
    return BiometricGuardResult.reverted;
  }

  /// Switches the master lock to the credential behind biometrics (the first
  /// of password, PIN and pattern that is set) and drops its sentinel. The
  /// credentials themselves are untouched -- they are what the gate falls back
  /// to. Does nothing if biometrics are not the current method.
  Future<void> revertMaster() async {
    await _settings.updateSettings(
      (s) => s.masterUnlockMethod == MasterUnlockMethod.biometrics
          ? s.copyWith(
              masterUnlockMethod:
                  s.configuredMasterCredentials.firstOrNull ??
                  MasterUnlockMethod.password,
            )
          : s,
    );
    await _delete(kMasterBiometricKeyId);
  }

  // -- Vaults ---------------------------------------------------------------

  /// Starts trusting the biometrics enrolled right now for [uri]. False when
  /// Android refused; the vault must then not be switched to biometrics.
  Future<bool> enableVault(String uri) => _create(vaultBiometricKeyId(uri));

  /// Drops [uri]'s sentinel once biometrics are no longer its method.
  Future<void> forgetVault(String uri) => _delete(vaultBiometricKeyId(uri));

  /// Checks [uri]'s biometric unlock before it is offered or accepted. On
  /// [BiometricGuardResult.reverted] the vault is already on a manual
  /// password with its saved credentials removed.
  Future<BiometricGuardResult> checkVault(String uri) async {
    final status = await _crypto.biometricKeyStatus(vaultBiometricKeyId(uri));
    if (status == BiometricKeyStatus.valid) return BiometricGuardResult.ok;
    if (!status.requiresRevert) return BiometricGuardResult.unavailable;
    VeLog.w(
      _kLogTag,
      'Vault biometrics changed ($status) for ${VeLog.censorUri(uri)}; '
      'using the password',
    );
    await _repository.revertBiometricsToPassword(uri);
    return BiometricGuardResult.reverted;
  }

  // -- Platform -------------------------------------------------------------

  Future<bool> _create(String id) async {
    try {
      return await _crypto.createBiometricKey(id);
    } catch (e) {
      VeLog.w(_kLogTag, 'Could not create the biometric sentinel key', e);
      return false;
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _crypto.deleteBiometricKey(id);
    } catch (e) {
      VeLog.w(_kLogTag, 'Could not delete the biometric sentinel key', e);
    }
  }
}

final biometricEnrollmentGuardProvider = Provider<BiometricEnrollmentGuard>(
  (ref) => BiometricEnrollmentGuard(
    cryptoApi: ref.watch(vaultCryptoApiProvider),
    repository: ref.watch(containerRepositoryProvider),
    settings: ref.watch(appSettingsServiceProvider),
  ),
);
