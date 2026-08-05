import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:vaultexplorer/data/services/app_secure_storage.dart';

class AppCacheEncryption {
  static const _secure = AppSecureStorage.instance;
  static const _kCacheKey = 'app_cache_aes_key';

  static Uint8List? _cachedKey;

  /// Retrieves the persistent symmetric key, creating it if it doesn't exist.
  static Future<Uint8List> getEncryptionKey() async {
    if (_cachedKey != null) return _cachedKey!;

    final base64Key = await _secure.read(key: _kCacheKey);
    if (base64Key != null) {
      _cachedKey = base64Decode(base64Key);
      return _cachedKey!;
    }

    // Generate a fresh cryptographically secure 256-bit key (32 bytes)
    final rng = Random.secure();
    final freshKeyBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      freshKeyBytes[i] = rng.nextInt(256);
    }
    await _secure.write(key: _kCacheKey, value: base64Encode(freshKeyBytes));
    _cachedKey = freshKeyBytes;
    return _cachedKey!;
  }
}
