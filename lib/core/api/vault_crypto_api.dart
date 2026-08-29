// Extracted from lib/data/services/vault_engine/vault_explorer_api_crypto.dart
// (the old `mixin _CryptoOps` on the VaultExplorerApi singleton) as part of
// the Riverpod migration, Phase 2. See lib/core/providers/vault_engine_providers.dart
// for the generated `vaultCryptoApiProvider`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

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
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.aesGcmDecrypt,
      {'key': key, 'iv': iv, 'ciphertextAndTag': ciphertextAndTag},
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

  Future<bool> clearDerivedKey(String filePath) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.clearDerivedKey,
      {'filePath': filePath},
    );
    return result ?? false;
  }
}
