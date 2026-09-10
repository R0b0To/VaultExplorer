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

typedef DuressConfig = ({
  bool configured,
  bool hasPassword,
  bool hasPin,
  bool hasPattern,
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

  Future<String?> getPinHash() => _secure.read(key: _kPinHash);
  Future<String?> getPatternHash() => _secure.read(key: _kPatternHash);

  Future<DuressConfig> getConfig() async {
    final pwHash = await _secure.read(key: _kPasswordHash);
    final pinHash = await _secure.read(key: _kPinHash);
    final patternHash = await _secure.read(key: _kPatternHash);

    final isConfigured = pwHash != null || pinHash != null || patternHash != null;

    return (
      configured: isConfigured,
      hasPassword: pwHash != null,
      hasPin: pinHash != null,
      hasPattern: patternHash != null,
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

  Future<void> disable() async {
    await clearDuressPassword();
    await clearDuressPin();
    await clearDuressPattern();
  }
}