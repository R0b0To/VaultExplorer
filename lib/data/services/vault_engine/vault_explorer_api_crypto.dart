part of 'vault_explorer_api.dart';

/// Password hashing and derived-key storage: PBKDF2 hashing used by the
/// unlock/create flows, plus the Keystore-backed derived-key cache (see
/// [VaultExplorerApi.hashPassword], [deriveDerivedKey], [storeDerivedKey],
/// [loadDerivedKey], [clearDerivedKey]).
mixin _CryptoOps {
  // ── Crypto ─────────────────────────────────────────────────────────────────

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
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.aesGcmDecrypt,
      {'key': key, 'iv': iv, 'ciphertextAndTag': ciphertextAndTag},
    );
    return result;
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

  Future<bool> clearDerivedKey(String filePath) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.clearDerivedKey,
      {'filePath': filePath},
    );
    return result ?? false;
  }
}
