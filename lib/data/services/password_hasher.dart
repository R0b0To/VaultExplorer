import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

part 'password_hasher.g.dart';

@Riverpod(keepAlive: true)
PasswordHasher passwordHasher(Ref ref) =>
    PasswordHasher(ref.watch(vaultCryptoApiProvider));

/// Pure PBKDF2-SHA512 logic, extracted from the former AppSettings god class.
///
/// The PBKDF2 primitive is supplied by [VaultCryptoApi], keeping this service
/// independent of the legacy process-wide engine singleton. It can therefore
/// be unit-tested with a local crypto fake and overridden through Riverpod.
///
/// [AppSettingsService] is responsible for persisting the hash and salt;
/// this class only derives and verifies them.
class PasswordHasher {
  final VaultCryptoApi _cryptoApi;

  const PasswordHasher(this._cryptoApi);

  static const int _saltBytes = 16;
  static const int _iterations = 200000;

  /// Derives a PBKDF2-SHA512 hash from [plaintext].
  ///
  /// Returns a `(hash, salt)` record where both values are base64-encoded
  /// strings suitable for storage in Android Keystore via
  /// [AppSettingsService.saveMasterPassword].
  ///
  /// Throws [StateError] if the underlying PBKDF2 call fails.
  Future<({String hash, String salt})> deriveHash(String plaintext) async {
    final saltBytes = Uint8List(_saltBytes);
    final rng = Random.secure();
    for (int i = 0; i < _saltBytes; i++) {
      saltBytes[i] = rng.nextInt(256);
    }

    final hashBytes = await _cryptoApi.hashPassword(
      password: plaintext,
      salt: saltBytes,
      iterations: _iterations,
    );
    if (hashBytes == null || hashBytes.isEmpty) {
      throw StateError('PBKDF2 derivation failed');
    }
    return (hash: base64Encode(hashBytes), salt: base64Encode(saltBytes));
  }

  /// Returns true if [candidate] matches the stored [hash] / [salt] pair.
  ///
  /// Uses constant-time comparison to prevent timing-based side-channel
  /// attacks.  Returns false immediately if either [hash] or [salt] is null
  /// or empty.
  Future<bool> verify({
    required String candidate,
    required String? hash,
    required String? salt,
  }) async {
    if (hash == null || salt == null || salt.isEmpty) return false;

    final saltBytes = base64Decode(salt);
    final hashBytes = await _cryptoApi.hashPassword(
      password: candidate,
      salt: saltBytes,
      iterations: _iterations,
    );
    if (hashBytes == null) return false;

    final storedHash = base64Decode(hash);
    return _secureEqual(hashBytes, storedHash);
  }

  /// Constant-time byte comparison.
  ///
  /// Iterates the full length of both arrays regardless of where they first
  /// differ, preventing early-exit timing leaks.
  static bool _secureEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
