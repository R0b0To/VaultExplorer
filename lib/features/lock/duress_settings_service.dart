import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart'
    as pattern_lock show verifyPattern;
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart'
    as pin_lock show hashPin, verifyPin;

part 'duress_settings_service.g.dart';

@Riverpod(keepAlive: true)
DuressSettingsService duressSettingsService(Ref ref) => DuressSettingsService(
  ref.watch(appSecureStorageProvider),
  ref.watch(vaultCryptoApiProvider),
  ref.watch(passwordHasherProvider),
);

enum DuressActionMode {
  decoy('decoy'),
  purge('purge');

  final String wire;
  const DuressActionMode(this.wire);

  static DuressActionMode fromWire(String? wire) => values.firstWhere(
    (m) => m.wire == wire,
    orElse: () => DuressActionMode.purge,
  );
}

typedef DuressConfig = ({
  bool configured,
  bool hasPassword,
  bool hasPin,
  bool hasPattern,
  DuressActionMode actionMode,
  String? decoyVaultUri,
  String? decoyVaultDisplayName,
  String? decoyVaultFormat,
});

class DuressSettingsService {
  final AppSecureStorage _secure;
  final VaultCryptoApi _cryptoApi;
  final PasswordHasher _passwordHasher;

  const DuressSettingsService(
    this._secure,
    this._cryptoApi,
    this._passwordHasher,
  );

  static const _kPasswordHash = 'duress_password_hash';
  static const _kPasswordSalt = 'duress_password_salt';
  static const _kPinHash = 'duress_pin_hash';
  static const _kPatternHash = 'duress_pattern_hash';
  static const _kActionMode = 'duress_action_mode';
  static const _kDecoyVaultUri = 'duress_decoy_vault_uri';
  static const _kDecoyVaultFormat = 'duress_decoy_vault_format';
  static const _kDecoyVaultName = 'duress_decoy_vault_name';
  static const _kDecoyPassword = 'duress_decoy_password';

  Future<DuressConfig> getConfig() async {
    final pwHash = await _secure.read(key: _kPasswordHash);
    final pinHash = await _secure.read(key: _kPinHash);
    final patternHash = await _secure.read(key: _kPatternHash);
    final mode = await _secure.read(key: _kActionMode);
    final uri = await _secure.read(key: _kDecoyVaultUri);
    final name = await _secure.read(key: _kDecoyVaultName);
    final format = await _secure.read(key: _kDecoyVaultFormat);

    final isConfigured = pwHash != null || pinHash != null || patternHash != null;

    return (
      configured: isConfigured,
      hasPassword: pwHash != null,
      hasPin: pinHash != null,
      hasPattern: patternHash != null,
      actionMode: DuressActionMode.fromWire(mode),
      decoyVaultUri: uri,
      decoyVaultDisplayName: name,
      decoyVaultFormat: format,
    );
  }

  // ── Password Duress ────────────────────────────────────────────────────────

  Future<void> setDuressPassword(String password) async {
    final (:hash, :salt) = await _passwordHasher.deriveHash(password);
    await _secure.write(key: _kPasswordHash, value: hash);
    await _secure.write(key: _kPasswordSalt, value: salt);
  }

  Future<void> clearDuressPassword() async {
    await _secure.delete(key: _kPasswordHash);
    await _secure.delete(key: _kPasswordSalt);
  }

  Future<bool> verifyPassword(String candidate) async {
    final hash = await _secure.read(key: _kPasswordHash);
    final salt = await _secure.read(key: _kPasswordSalt);
    if (hash == null || salt == null) return false;
    return _passwordHasher.verify(
      candidate: candidate,
      hash: hash,
      salt: salt,
    );
  }

  // ── PIN Duress ─────────────────────────────────────────────────────────────

  Future<void> setDuressPin(String pin) async {
    final hash = await pin_lock.hashPin(_cryptoApi, pin);
    await _secure.write(key: _kPinHash, value: hash);
  }

  Future<void> setDuressPinHash(String hash) async {
    await _secure.write(key: _kPinHash, value: hash);
  }

  Future<void> clearDuressPin() async {
    await _secure.delete(key: _kPinHash);
  }

  Future<bool> verifyPin(String candidate) async {
    final hash = await _secure.read(key: _kPinHash);
    if (hash == null) return false;
    return pin_lock.verifyPin(_cryptoApi, candidate, hash);
  }

  // ── Pattern Duress ─────────────────────────────────────────────────────────

  Future<void> setDuressPattern(String hash) async {
    await _secure.write(key: _kPatternHash, value: hash);
  }

  Future<void> clearDuressPattern() async {
    await _secure.delete(key: _kPatternHash);
  }

  Future<bool> verifyPattern(List<int> candidate) async {
    final hash = await _secure.read(key: _kPatternHash);
    if (hash == null) return false;
    return pattern_lock.verifyPattern(_cryptoApi, candidate, hash);
  }

  // ── Action and Decoy Vault ─────────────────────────────────────────────────

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

  Future<String?> decoyPassword() => _secure.read(key: _kDecoyPassword);

  Future<void> disable() async {
    await clearDuressPassword();
    await clearDuressPin();
    await clearDuressPattern();
    await _secure.delete(key: _kDecoyPassword);
  }
}