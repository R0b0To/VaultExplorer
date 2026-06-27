import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as enc; // Added

import '../models/mounted_container.dart';
import '../models/thumbnail_cache_mode.dart';
import 'vaultexplorer_api.dart';
import 'app_cache_encryption.dart'; // Added helper class above

class ThumbnailCacheService {
  ThumbnailCacheService._();

  static const inContainerDir = '.thumbcache';

  // ── Key encoding ──────────────────────────────────────────────────────────

  static String _encodeKey(String filePath) {
    final encoded = base64Url.encode(utf8.encode(filePath));
    return encoded.length > 180 ? encoded.substring(0, 180) : encoded;
  }

  // ── App-cache helpers ─────────────────────────────────────────────────────

  static Future<Directory> _appDir(MountedContainer container) async {
    final root = await getApplicationCacheDirectory();
    final dir = Directory('${root.path}/thumbs/${container.volId}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _appFile(
      MountedContainer container, String filePath) async {
    final dir = await _appDir(container);
    return File('${dir.path}/${_encodeKey(filePath)}');
  }

  // ── In-container path ─────────────────────────────────────────────────────

  static String _inContainerPath(String filePath) =>
      '$inContainerDir/${_encodeKey(filePath)}';

  // ── Public read/write ─────────────────────────────────────────────────────

  /// Returns cached thumbnail bytes for [filePath], or null on a miss.
  static Future<Uint8List?> get({
    required MountedContainer container,
    required String filePath,
    required ThumbnailCacheMode mode,
  }) async {
    if (mode == ThumbnailCacheMode.disabled) return null;
    try {
      if (mode == ThumbnailCacheMode.appCache) {
        final file = await _appFile(container, filePath);
        if (await file.exists()) {
          final rawBytes = await file.readAsBytes();
          if (rawBytes.length <= 16) return null; // Must contain at least IV + 1 byte payload

          // 1. Recover the symmetric key
          final key = await AppCacheEncryption.getEncryptionKey();
          
          // 2. Extract the prepended 16-byte random IV
          final ivBytes = rawBytes.sublist(0, 16);
          final iv = enc.IV(ivBytes);

          // 3. Extract the encrypted ciphertext
          final encryptedBytes = rawBytes.sublist(16);
          final encrypted = enc.Encrypted(encryptedBytes);

          // 4. Decrypt on-the-fly
          final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
          final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
          
          return Uint8List.fromList(decrypted);
        }
      } else {
        // In-container lookup.
        final cachePath = _inContainerPath(filePath);
        final size = await vaultExplorerApi.getFileSize(container, cachePath);
        if (size > 0) {
          return await vaultExplorerApi.readFileChunk(
              container, cachePath, 0, size);
        }
      }
    } catch (_) {
      // Non-fatal: treat as a cache miss.
    }
    return null;
  }

  /// Stores [data] as the cached thumbnail for [filePath].
  static Future<void> put({
    required MountedContainer container,
    required String filePath,
    required Uint8List data,
    required ThumbnailCacheMode mode,
  }) async {
    if (mode == ThumbnailCacheMode.disabled || data.isEmpty) return;
    try {
      if (mode == ThumbnailCacheMode.appCache) {
        final file = await _appFile(container, filePath);

        // 1. Recover the symmetric key
        final key = await AppCacheEncryption.getEncryptionKey();
        
        // 2. Generate a random unique IV for this specific write operation
        final iv = enc.IV.fromSecureRandom(16);

        // 3. Encrypt the clear-text thumbnail bytes
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
        final encrypted = encrypter.encryptBytes(data, iv: iv);

        // 4. Combine the IV + Ciphertext into a single array and write to disk
        final outputBytes = BytesBuilder(copy: false)
          ..add(iv.bytes)
          ..add(encrypted.bytes);

        await file.writeAsBytes(outputBytes.takeBytes(), flush: true);
      } else {
        // Write bytes directly to the container via the JNI C++ block-writing API (offset 0).
        final cachePath = _inContainerPath(filePath);
        await vaultExplorerApi.createDirectory(container, inContainerDir);
        await vaultExplorerApi.deleteFile(container, cachePath); 
        await vaultExplorerApi.writeFileChunk(container, cachePath, 0, data);
      }
    } catch (_) {
      // Non-fatal.
    }
  }

  // ── Cache introspection & management ──────────────────────────────────────

  static Future<int> appCacheBytesFor(MountedContainer container) async {
    try {
      final dir = await _appDir(container);
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> totalAppCacheBytes() async {
    try {
      final root = await getApplicationCacheDirectory();
      final dir = Directory('${root.path}/thumbs');
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearAppCacheFor(MountedContainer container) async {
    try {
      final dir = await _appDir(container);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  static Future<void> clearAllAppCache() async {
    try {
      final root = await getApplicationCacheDirectory();
      final dir = Directory('${root.path}/thumbs');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  static Future<void> pruneStaleAppCache(Set<int> activeVolIds) async {
    try {
      final root = await getApplicationCacheDirectory();
      final thumbs = Directory('${root.path}/thumbs');
      if (!await thumbs.exists()) return;
      await for (final entity in thumbs.list()) {
        if (entity is! Directory) continue;
        final volId = int.tryParse(entity.path.split('/').last);
        if (volId != null && !activeVolIds.contains(volId)) {
          await entity.delete(recursive: true);
        }
      }
    } catch (_) {}
  }
}