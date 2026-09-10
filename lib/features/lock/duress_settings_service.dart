// Master Lock Screen Duress Unlock storage (architecture plan Component 4,
// "6.1 Storage Keys in AppSecureStorage"). Deliberately kept entirely out of
// the plaintext AppSettings JSON blob (see AppSettingsService) and out of
// ContainerRepository's per-container records -- both of those are things
// SettingsBackupService can export to a plain file on request, and the
// entire point of a duress credential is that its existence never shows up
// anywhere the real master credential's existence doesn't already show up.
// Everything here lives in AppSecureStorage instead, the same store
// AppSettingsService itself uses under the hood for the real master
// password/pattern/PIN hashes (see its `_kMasterHash` etc. constants) --
// this is just a second, independent set of keys in the same Keystore-backed
// store, not a new storage mechanism.
//
// "Configured" == a duress PIN hash is present; there's deliberately no
// separate enabled/disabled flag to drift out of sync with it, mirroring how
// AppSettings.masterPinHash's nullness alone gates the master PIN
// quick-unlock path in LockGateScreen.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart'
    show hashPin, verifyPin;

part 'duress_settings_service.g.dart';

@Riverpod(keepAlive: true)
DuressSettingsService duressSettingsService(Ref ref) => DuressSettingsService(
  ref.watch(appSecureStorageProvider),
  ref.watch(vaultCryptoApiProvider),
);

/// What happens when the duress credential is entered on the master lock
/// screen instead of the real one. See [DuressSettingsService]'s own doc
/// comment for how each is actually carried out, and LockGateController's
/// `_handleDuressDecoy`/`_handleDuressPurge` for the runtime behavior.
enum DuressActionMode {
  /// Silently unlock a real, separate, low-stakes container and land
  /// straight in its FileBrowserScreen -- the vault the person is actually
  /// protecting is never touched, referenced, or revealed to exist.
  decoy('decoy'),

  /// Runs a Tier 2 credential purge in the background (see PanicTier /
  /// VaultPanicApi.triggerPanic) while the screen shows an ordinary-looking
  /// "wrong password" error -- there is no vault left to show *or* hide by
  /// the time anyone sees that error.
  purge('purge');

  final String wire;
  const DuressActionMode(this.wire);

  static DuressActionMode fromWire(String? wire) => values.firstWhere(
    (m) => m.wire == wire,
    // Purge is the safer default if this is ever missing/corrupt -- decoy
    // mode requires a correctly-configured target container, and silently
    // falling back to *showing something* on a misconfigured decoy would
    // be worse than falling back to the wipe the person explicitly set a
    // duress PIN up for in the first place.
    orElse: () => DuressActionMode.purge,
  );
}

/// Non-secret snapshot for the settings screen -- everything except the PIN
/// hash and decoy vault password themselves, neither of which any caller
/// needs back out of this service once written (only
/// [DuressSettingsService.verify] and [DuressSettingsService.decoyPassword]
/// ever touch them again, both exclusively from LockGateController).
typedef DuressConfig = ({
  bool configured,
  DuressActionMode actionMode,
  String? decoyVaultUri,
  String? decoyVaultDisplayName,
  String? decoyVaultFormat,
});

class DuressSettingsService {
  final AppSecureStorage _secure;
  final VaultCryptoApi _cryptoApi;
  const DuressSettingsService(this._secure, this._cryptoApi);

  static const _kPinHash = 'duress_pin_hash';
  static const _kActionMode = 'duress_action_mode';
  static const _kDecoyVaultUri = 'duress_decoy_vault_uri';
  static const _kDecoyVaultFormat = 'duress_decoy_vault_format';
  static const _kDecoyVaultName = 'duress_decoy_vault_name';
  static const _kDecoyPassword = 'duress_decoy_password';

  Future<DuressConfig> getConfig() async {
    final hash = await _secure.read(key: _kPinHash);
    final mode = await _secure.read(key: _kActionMode);
    final uri = await _secure.read(key: _kDecoyVaultUri);
    final name = await _secure.read(key: _kDecoyVaultName);
    final format = await _secure.read(key: _kDecoyVaultFormat);
    return (
      configured: hash != null,
      actionMode: DuressActionMode.fromWire(mode),
      decoyVaultUri: uri,
      decoyVaultDisplayName: name,
      decoyVaultFormat: format,
    );
  }

  /// Sets/replaces the duress PIN. Does not itself touch [DuressActionMode]
  /// or the decoy target -- call [setActionMode]/[setDecoyVault]
  /// separately, the same "each field its own write" shape
  /// AppSettingsService.saveMasterPassword has to its unlock-method
  /// setters.
  Future<void> setDuressPin(String pin) async {
    final hash = await hashPin(_cryptoApi, pin);
    await _secure.write(key: _kPinHash, value: hash);
  }

  /// Turns duress unlock off entirely. Deliberately clears the decoy
  /// vault's stored *password* along with the PIN hash -- an armed
  /// duress config is exactly the kind of stale secret that shouldn't keep
  /// sitting in Keystore once the feature is off. The (non-secret) vault
  /// URI/format/label are left alone so re-enabling later doesn't force
  /// picking the container again.
  Future<void> disable() async {
    await _secure.delete(key: _kPinHash);
    await _secure.delete(key: _kDecoyPassword);
  }

  /// True if [candidate] matches the stored duress PIN. Cheap (a single
  /// secure-storage read, no hashing) when duress isn't configured at all,
  /// since [hash] is checked for null before ever calling into
  /// [verifyPin] -- safe to call unconditionally on every master-lock
  /// attempt without worrying about the cost for the common case where no
  /// duress PIN has ever been set.
  Future<bool> verify(String candidate) async {
    final hash = await _secure.read(key: _kPinHash);
    if (hash == null) return false;
    return verifyPin(_cryptoApi, candidate, hash);
  }

  Future<void> setActionMode(DuressActionMode mode) async {
    await _secure.write(key: _kActionMode, value: mode.wire);
  }

  Future<void> setDecoyVault({
    required String uri,
    required String format,
    required String displayName,
    required String password,
  }) async {
    await _secure.write(key: _kDecoyVaultUri, value: uri);
    await _secure.write(key: _kDecoyVaultFormat, value: format);
    await _secure.write(key: _kDecoyVaultName, value: displayName);
    await _secure.write(key: _kDecoyPassword, value: password);
  }

  Future<void> clearDecoyVault() async {
    await _secure.delete(key: _kDecoyVaultUri);
    await _secure.delete(key: _kDecoyVaultFormat);
    await _secure.delete(key: _kDecoyVaultName);
    await _secure.delete(key: _kDecoyPassword);
  }

  /// Only ever read by LockGateController at the moment a correct duress
  /// PIN is actually entered -- never exposed through [getConfig] or shown
  /// back in Settings once saved, the same write-only-from-the-UI's-
  /// perspective shape ContainerRepository.getPassword's callers already
  /// have (always unlock-time, never a settings display).
  Future<String?> decoyPassword() => _secure.read(key: _kDecoyPassword);
}
