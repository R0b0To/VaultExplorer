// Extracted from lib/data/services/vault_engine/vault_explorer_api_crypto.dart
// (the old `mixin _CryptoOps` on the VaultExplorerApi singleton) as part of
// the Riverpod migration, Phase 2. See lib/core/providers/vault_engine_providers.dart
// for the generated `vaultCryptoApiProvider`.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

/// Hash functions [VaultCryptoApi.pbkdf2] can run.
enum Pbkdf2Hash { sha1, sha256 }

/// Hash functions [VaultCryptoApi.hmac] can run.
enum HmacHash { sha1, sha256, sha512 }

/// What the platform layer found when it checked a biometric sentinel key (see
/// [VaultCryptoApi.biometricKeyStatus]).
enum BiometricKeyStatus {
  /// The key exists and the device's biometrics have not changed since it was
  /// created.
  valid,

  /// Android invalidated the key: a biometric was enrolled (or the last one
  /// removed, or the secure lock screen disabled) after it was created.
  invalidated,

  /// There is no key: biometrics were never set up on this device for that
  /// purpose, its Keystore entries were cleared, or the setting was restored
  /// from a backup made elsewhere.
  missing,

  /// The Keystore could not answer. Not evidence of a change, so callers
  /// refuse the current attempt without switching anything off.
  error;

  static BiometricKeyStatus fromWire(String? value) => switch (value) {
    'valid' => BiometricKeyStatus.valid,
    'invalidated' => BiometricKeyStatus.invalidated,
    'missing' => BiometricKeyStatus.missing,
    _ => BiometricKeyStatus.error,
  };

  /// True when biometric unlock must be switched off for good: the key was
  /// invalidated or never existed here. [error] is deliberately excluded.
  bool get requiresRevert =>
      this == BiometricKeyStatus.invalidated ||
      this == BiometricKeyStatus.missing;
}

/// Password hashing and derived-key storage: PBKDF2 hashing used by the
/// unlock/create flows, plus the Keystore-backed derived-key cache, plus
/// AES-GCM and AVIF decode primitives that also live in the native crypto
/// layer.
class VaultCryptoApi {
  final MethodChannel _channel;
  const VaultCryptoApi(this._channel);

  /// PBKDF2-SHA512 via the C++ mbedTLS layer.
  ///
  /// Returns 64 raw bytes of derived key, or null on failure.
  /// [salt] must be non-empty (16 bytes recommended).
  Future<Uint8List?> hashPassword({
    required String password,
    required Uint8List salt,
    int iterations = 200000,
  }) async {
    assert(salt.isNotEmpty, 'salt must not be empty');
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.hashPassword,
      {'password': password, 'salt': salt, 'iterations': iterations},
    );
    return result;
  }

  /// PBKDF2-SHA256 via the C++ mbedTLS layer.
  Future<Uint8List?> hashPasswordSha256({
    required String password,
    required Uint8List salt,
    int iterations = 50000,
    int outputLen = 32,
  }) async {
    assert(salt.isNotEmpty, 'salt must not be empty');
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.hashPasswordSha256,
      {
        'password': password,
        'salt': salt,
        'iterations': iterations,
        'outputLen': outputLen,
      },
    );
    return result;
  }

  /// AES-GCM encryption via the C++ mbedTLS layer.
  Future<Uint8List?> aesGcmEncrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.aesGcmEncrypt,
      {'key': key, 'iv': iv, 'plaintext': plaintext},
    );
    return result;
  }

  /// AES-GCM decryption via the C++ mbedTLS layer.
  Future<Uint8List?> aesGcmDecrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List ciphertextAndTag,
    Uint8List? aad,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.aesGcmDecrypt,
      {
        'key': key,
        'iv': iv,
        'ciphertextAndTag': ciphertextAndTag,
        if (aad != null) 'aad': aad,
      },
    );
    return result;
  }

  /// AES-256-CBC decryption with PKCS5/PKCS7 unpadding via the native engine.
  Future<Uint8List?> aesCbcDecrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List ciphertext,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.aesCbcDecrypt,
      {'key': key, 'iv': iv, 'ciphertext': ciphertext},
    );
    return result;
  }

  /// PBKDF2-HMAC over raw password bytes, via the native engine.
  ///
  /// Unlike [hashPassword]/[hashPasswordSha256] this takes the password as
  /// bytes (encode the string as UTF-8 first): the String-taking variants go
  /// through JNI's *modified* UTF-8, which differs from standard UTF-8 for
  /// emoji and other supplementary characters. Used to open other
  /// authenticator apps' encrypted backups (andOTP: SHA-1, 2FAS: SHA-256).
  ///
  /// Returns null if the derivation failed.
  Future<Uint8List?> pbkdf2({
    required Uint8List password,
    required Uint8List salt,
    required int iterations,
    required int outputLen,
    required Pbkdf2Hash hash,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.pbkdf2,
      {
        'password': password,
        'salt': salt,
        'iterations': iterations,
        'outputLen': outputLen,
        'hash': hash.name,
      },
    );
    return result;
  }

  /// One-shot HMAC of [data] under [key], via the platform's `javax.crypto.Mac`
  /// (see `HmacUtil.kt`). Used for the built-in authenticator's TOTP/HOTP codes
  /// and the Bitwarden import's HKDF / MAC check.
  ///
  /// [key] must be non-empty (the native side rejects an empty one). Returns
  /// the raw MAC, or null if the platform produced nothing.
  Future<Uint8List?> hmac({
    required Uint8List key,
    required Uint8List data,
    required HmacHash hash,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.hmac,
      {'key': key, 'data': data, 'hash': hash.name},
    );
    return result;
  }

  /// scrypt over raw password bytes, via the native engine. Used to open
  /// Aegis's password-protected vault exports. The native side rejects
  /// parameters that would need more than 256 MiB.
  Future<Uint8List?> scrypt({
    required Uint8List password,
    required Uint8List salt,
    required int n,
    required int r,
    required int p,
    required int dkLen,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.scrypt,
      {'password': password, 'salt': salt, 'n': n, 'r': r, 'p': p, 'dkLen': dkLen},
    );
    return result;
  }

  /// Argon2id via the native engine.
  Future<Uint8List?> argon2id({
    required Uint8List password,
    required Uint8List salt,
    required int memoryKiB,
    required int iterations,
    required int parallelism,
    required int outputLen,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.argon2id,
      {
        'password': password,
        'salt': salt,
        'memoryKiB': memoryKiB,
        'iterations': iterations,
        'parallelism': parallelism,
        'outputLen': outputLen,
      },
    );
    return result;
  }

  /// XChaCha20-Poly1305 AEAD decryption via the native engine.
  Future<Uint8List?> xchacha20Poly1305Open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertextAndTag,
    Uint8List? aad,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.xchacha20Poly1305Open,
      {
        'key': key,
        'nonce': nonce,
        'ciphertextAndTag': ciphertextAndTag,
        if (aad != null) 'aad': aad,
      },
    );
    return result;
  }

  Future<({int width, int height, int frameCount, int totalDurationMs})?>
  getAvifInfo(Uint8List avifBytes) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.getAvifInfo,
      {'avifBytes': avifBytes},
    );
    if (result == null || result.length < 4) return null;
    return (
      width: (result[0] as num).toInt(),
      height: (result[1] as num).toInt(),
      frameCount: (result[2] as num).toInt(),
      totalDurationMs: (result[3] as num).toInt(),
    );
  }

  Future<({
    int width,
    int height,
    int totalDurationMs,
    List<({Uint8List rgbaBytes, int durationMs})> frames,
  })?>
  decodeAvif(Uint8List avifBytes) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      ChannelMethods.decodeAvif,
      {'avifBytes': avifBytes},
    );
    if (result == null) return null;

    final rawFrames = result['frames'] as List<dynamic>? ?? [];
    final frames = <({Uint8List rgbaBytes, int durationMs})>[];
    for (final f in rawFrames) {
      if (f is Map) {
        frames.add((
          rgbaBytes: f['rgbaBytes'] as Uint8List,
          durationMs: (f['durationMs'] as num?)?.toInt() ?? 100,
        ));
      }
    }

    return (
      width: (result['width'] as num).toInt(),
      height: (result['height'] as num).toInt(),
      totalDurationMs: (result['totalDurationMs'] as num).toInt(),
      frames: frames,
    );
  }

  Future<({Uint8List rgbaBytes, int durationMs})?> decodeAvifFrame(
    Uint8List avifBytes,
    int frameIndex,
  ) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      ChannelMethods.decodeAvifFrame,
      {'avifBytes': avifBytes, 'frameIndex': frameIndex},
    );
    if (result == null) return null;
    return (
      rgbaBytes: result['rgbaBytes'] as Uint8List,
      durationMs: (result['durationMs'] as num?)?.toInt() ?? 100,
    );
  }

  Future<Uint8List?> deriveDerivedKey({
    required String filePath,
    required String password,
    required int pim,
    int? cipherId,
    int? hashId,
    List<String>? keyfilePaths,
  }) async {
    final result = await _channel.invokeMethod<String>(
      ChannelMethods.deriveDerivedKey,
      {
        'filePath': filePath,
        'password': password,
        'pim': pim,
        'cipherId': cipherId ?? 255,
        'hashId': hashId ?? 255,
        if (keyfilePaths != null && keyfilePaths.isNotEmpty)
          'keyfilePaths': keyfilePaths,
      },
    );
    if (result == null || result.isEmpty) return null;
    return base64Decode(result);
  }

  Future<bool> storeDerivedKey(String filePath, Uint8List derivedKey) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.storeDerivedKey,
      {'filePath': filePath, 'derivedKey': base64Encode(derivedKey)},
    );
    return result ?? false;
  }

  Future<Uint8List?> loadDerivedKey(String filePath) async {
    final result = await _channel.invokeMethod<String>(
      ChannelMethods.loadDerivedKey,
      {'filePath': filePath},
    );
    if (result == null || result.isEmpty) return null;
    return base64Decode(result);
  }

  /// Drops the cached derived key for [filePath].
  ///
  /// A configured expiry (see [setDerivedKeyExpiry]) is kept by default, since
  /// this is also the "cached key turned out to be stale" path and that must
  /// not quietly lift a vault's lifetime. Pass [removeExpiry] when the vault is
  /// being removed or key caching switched off: it then also deletes the
  /// Keystore entry and forgets the expiry.
  Future<bool> clearDerivedKey(
    String filePath, {
    bool removeExpiry = false,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.clearDerivedKey,
      {'filePath': filePath, if (removeExpiry) 'removeExpiry': true},
    );
    return result ?? false;
  }

  /// Sets the moment at which [filePath]'s cached derived key is removed, or
  /// clears it when [expiresAt] is null. The platform enforces it: the key is
  /// refused (and deleted) once [expiresAt] has passed, and swept on launch
  /// by [purgeExpiredDerivedKeys].
  Future<bool> setDerivedKeyExpiry(String filePath, DateTime? expiresAt) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.setDerivedKeyExpiry,
      {
        'filePath': filePath,
        if (expiresAt != null) 'expiresAtMs': expiresAt.millisecondsSinceEpoch,
      },
    );
    return result ?? false;
  }

  /// The expiry currently configured for [filePath], or null for none.
  Future<DateTime?> getDerivedKeyExpiry(String filePath) async {
    final ms = await _channel.invokeMethod<int>(
      ChannelMethods.getDerivedKeyExpiry,
      {'filePath': filePath},
    );
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Removes every cached derived key whose expiry has passed. Returns the
  /// file paths (the same strings used with [loadDerivedKey]) of every vault
  /// purged since this was last called, so key caching can be switched off
  /// for them.
  Future<List<String>> purgeExpiredDerivedKeys() async {
    final result = await _channel.invokeListMethod<String>(
      ChannelMethods.purgeExpiredDerivedKeys,
    );
    return result ?? const [];
  }

  /// Creates (replacing any existing) the biometric sentinel key for [id] --
  /// an Android Keystore key that Android permanently invalidates when a new
  /// biometric is enrolled. It trusts the biometrics enrolled *now*.
  ///
  /// Returns false when the key could not be created, usually because no
  /// biometric is enrolled or there is no secure lock screen; biometric unlock
  /// must then not be turned on. Biometric unlock is only a prompt in front of
  /// the saved credentials, so this key is what makes a later enrollment
  /// detectable.
  Future<bool> createBiometricKey(String id) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.biometricKeyCreate,
      {'id': id},
    );
    return result ?? false;
  }

  /// Whether the biometric sentinel key for [id] still trusts the device's
  /// current biometrics. A platform failure is reported as
  /// [BiometricKeyStatus.error], never thrown, so callers fail closed.
  Future<BiometricKeyStatus> biometricKeyStatus(String id) async {
    try {
      final result = await _channel.invokeMethod<String>(
        ChannelMethods.biometricKeyStatus,
        {'id': id},
      );
      return BiometricKeyStatus.fromWire(result);
    } on PlatformException {
      return BiometricKeyStatus.error;
    }
  }

  /// Deletes the biometric sentinel key for [id]. Idempotent.
  Future<bool> deleteBiometricKey(String id) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.biometricKeyDelete,
      {'id': id},
    );
    return result ?? false;
  }
}
