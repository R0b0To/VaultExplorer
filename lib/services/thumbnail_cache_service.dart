import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as enc;

import '../models/mounted_container.dart';
import '../models/thumbnail_cache_mode.dart';
import '../utils/lru_cache.dart';
import 'vaultexplorer_api.dart';
import 'app_cache_encryption.dart';

/// Three-tier thumbnail cache.

class ThumbnailCacheService {
  ThumbnailCacheService._();

  // ── Constants ──────────────────────────────────────────────────────────────
  static const inContainerDir = '.thumbcache';
  static const _gcmNonceSize  = 12;
  static const _gcmTagSize    = 16; // AES-GCM authentication tag

  // ── Tier 1: static in-memory LRU ──────────────────────────────────────────
  // Static so the cache survives widget disposal and scroll recycling.
  static final _memoryCache = LruCache<String, Uint8List>(120);

  // ── AES key — read from Keystore exactly once per session ─────────────────
  static enc.Key? _cachedKey;

  static Future<enc.Key> _getOrFetchKey() async =>
      _cachedKey ??= await AppCacheEncryption.getEncryptionKey();

  // ── App-cache directory — resolved once, never re-queried ─────────────────
  // BUG FIXED: the old code called getApplicationCacheDirectory() on every
  // single cache read, paying a platform-channel round-trip every time.
  static String? _appCacheRoot;

  static Future<String> _thumbDir(int volId) async {
    // FIX: Wrap in try/catch so a temporarily-unavailable cache dir doesn't
    // throw an unhandled exception. Fall back to a temp directory if needed.
    try {
      _appCacheRoot ??= (await getApplicationCacheDirectory()).path;
    } catch (e) {
      debugPrint('ThumbnailCacheService._thumbDir: cache directory unavailable: $e');
      _appCacheRoot ??= (await getTemporaryDirectory()).path;
    }
    return '$_appCacheRoot/thumbs/$volId';
  }

  // ── Filename encoding ──────────────────────────────────────────────────────
  static String _encodeKey(String filePath) {
    final encoded = base64Url.encode(utf8.encode(filePath));
    return encoded.length > 180 ? encoded.substring(0, 180) : encoded;
  }

  // ── AES-GCM — inline, no Isolate ──────────────────────────────────────────
  // Running AES-GCM inline is safe: the concurrency limiter upstream ensures
  // at most 2 image loads run simultaneously, so worst-case synchronous CPU
  // cost per frame is ~0.6 ms — well inside a 16 ms budget.
  static Uint8List? _decrypt(Uint8List raw, enc.Key key) {
    if (raw.length <= _gcmNonceSize + _gcmTagSize) return null;
    try {
      final iv         = enc.IV(raw.sublist(0, _gcmNonceSize));
      final ciphertext = enc.Encrypted(raw.sublist(_gcmNonceSize));
      return Uint8List.fromList(
        enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm))
            .decryptBytes(ciphertext, iv: iv),
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List _encrypt(Uint8List data, enc.Key key) {
    final iv        = enc.IV.fromSecureRandom(_gcmNonceSize);
    final encrypted =
        enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm)).encryptBytes(data, iv: iv);
    // Layout: [12-byte nonce][ciphertext + 16-byte GCM tag]
    final out = Uint8List(_gcmNonceSize + encrypted.bytes.length);
    out.setRange(0, _gcmNonceSize, iv.bytes);
    out.setRange(_gcmNonceSize, out.length, encrypted.bytes);
    return out;
  }

  // ── Memory-tier public helpers ─────────────────────────────────────────────
  static String _memKey(MountedContainer container, String filePath) =>
      '${container.volId}:$filePath';

  /// Synchronous O(1) lookup into the in-memory tier.
  static Uint8List? getFromMemory(MountedContainer container, String filePath) =>
      _memoryCache[_memKey(container, filePath)];

  /// Writes directly to the in-memory tier. Safe to call from any async context.
  static void putInMemory(
      MountedContainer container, String filePath, Uint8List data) =>
      _memoryCache[_memKey(container, filePath)] = data;

  // ── Public: read ──────────────────────────────────────────────────────────

  /// Returns cached thumbnail bytes, or null on any miss or error.
  static Future<Uint8List?> get({
    required MountedContainer container,
    required String filePath,
    required ThumbnailCacheMode mode,
  }) async {
    if (mode == ThumbnailCacheMode.disabled) return null;

    // ── Tier 1: memory ────────────────────────────────────────────────────
    final mem = getFromMemory(container, filePath);
    if (mem != null) return mem;

    // ── Tier 2: disk / in-container ───────────────────────────────────────
    // FIX: Top-level try/catch ensures NO exception can escape from get(),
    // not even from _thumbDir() → getApplicationCacheDirectory() on first call.
    try {
      if (mode == ThumbnailCacheMode.appCache) {
        return await _getFromAppCache(container, filePath);
      } else {
        return await _getFromContainer(container, filePath);
      }
    } catch (e, stack) {
      debugPrint('ThumbnailCacheService.get: unexpected error for $filePath\n$e\n$stack');
      return null;
    }
  }

  static Future<Uint8List?> _getFromAppCache(
      MountedContainer container, String filePath) async {
    final dir  = await _thumbDir(container.volId);
    final file = File('$dir/${_encodeKey(filePath)}');
    final Uint8List raw;
    try {
      raw = await file.readAsBytes();
    } on PathNotFoundException {
      // Expected: cache entry doesn't exist yet. Not an error.
      return null;
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 2 /* ENOENT */) return null;
      debugPrint('ThumbnailCacheService._getFromAppCache: FileSystemException '
          'reading $filePath: $e');
      return null;
    } catch (e) {
      debugPrint('ThumbnailCacheService._getFromAppCache: unexpected error '
          'reading $filePath: $e');
      return null;
    }

    // Validate minimum size before attempting decryption.
    if (raw.length <= _gcmNonceSize + _gcmTagSize) {
      debugPrint('ThumbnailCacheService._getFromAppCache: cache file too small '
          '(${raw.length} bytes) for $filePath — deleting.');
      file.delete().catchError((_) {}); // Fire-and-forget cleanup
      return null;
    }

    final key       = await _getOrFetchKey();
    final decrypted = _decrypt(raw, key);

    if (decrypted == null || decrypted.isEmpty) {
      // AES-GCM authentication failure — corrupted or tampered cache file.
      // Delete it so the next access regenerates from the container.
      debugPrint('ThumbnailCacheService._getFromAppCache: AES-GCM auth failure '
          'for $filePath — deleting corrupt cache entry.');
      file.delete().catchError((_) {});
      return null;
    }

    // Promote to Tier 1 so the next access is instant.
    putInMemory(container, filePath, decrypted);
    return decrypted;
  }

  /// Reads from the in-container .thumbcache directory.
  static Future<Uint8List?> _getFromContainer(
      MountedContainer container, String filePath) async {
    try {
      final cachePath = '$inContainerDir/${_encodeKey(filePath)}';
      final size = await vaultExplorerApi.getFileSize(container, cachePath);
      if (size <= 0) return null;
      final bytes =
          await vaultExplorerApi.readFileChunk(container, cachePath, 0, size);
      if (bytes != null && bytes.isNotEmpty) {
        putInMemory(container, filePath, bytes);
      }
      return bytes;
    } catch (e) {
      debugPrint('ThumbnailCacheService._getFromContainer: $e');
      return null;
    }
  }

  // ── Public: write ─────────────────────────────────────────────────────────

  /// Stores [data] in the memory tier immediately and schedules a disk write.
  static Future<void> put({
    required MountedContainer container,
    required String filePath,
    required Uint8List data,
    required ThumbnailCacheMode mode,
  }) async {
    if (mode == ThumbnailCacheMode.disabled || data.isEmpty) return;

    // Always populate the memory tier immediately — the disk write is secondary.
    putInMemory(container, filePath, data);

    try {
      if (mode == ThumbnailCacheMode.appCache) {
        await _putToAppCache(container, filePath, data);
      } else {
        await _putToContainer(container, filePath, data);
      }
    } catch (e, stack) {
      // Last-resort safety net — should not fire in normal operation.
      debugPrint('ThumbnailCacheService.put: unexpected error for $filePath\n$e\n$stack');
    }
  }

  static Future<void> _putToAppCache(
      MountedContainer container, String filePath, Uint8List data) async {
    final dirPath = await _thumbDir(container.volId);
    final dir = Directory(dirPath);
    try {
      await dir.create(recursive: true);
    } on PathNotFoundException catch (e) {
      debugPrint('ThumbnailCacheService._putToAppCache: cannot create '
          'cache dir $dirPath: $e');
      return; // Non-fatal — thumbnail will be regenerated next access
    } on FileSystemException catch (e) {
      debugPrint('ThumbnailCacheService._putToAppCache: filesystem error '
          'creating $dirPath: $e');
      return;
    }

    final file      = File('$dirPath/${_encodeKey(filePath)}');
    final key       = await _getOrFetchKey();
    final encrypted = _encrypt(data, key);

    // Atomic write: write to a .tmp file then rename to prevent partial reads
    final tmp = File('${file.path}.tmp');
    try {
      await tmp.writeAsBytes(encrypted, flush: true);
      await tmp.rename(file.path);
    } on PathNotFoundException {
      debugPrint('ThumbnailCacheService._putToAppCache: directory vanished '
          'during write for $filePath — skipping disk cache.');
      tmp.delete().catchError((_) {});
    } on FileSystemException catch (e) {
      debugPrint('ThumbnailCacheService._putToAppCache: write failed '
          'for $filePath: $e');
      tmp.delete().catchError((_) {});
    }
  }

  static Future<void> _putToContainer(
      MountedContainer container, String filePath, Uint8List data) async {
    try {
      final cachePath = '$inContainerDir/${_encodeKey(filePath)}';
      final tmpPath   = '$cachePath.tmp';
      await vaultExplorerApi.createDirectory(container, inContainerDir);
      await vaultExplorerApi.deleteFile(container, tmpPath);
      final ok = await vaultExplorerApi.writeFileChunk(container, tmpPath, 0, data);
      if (ok) {
        await vaultExplorerApi.deleteFile(container, cachePath);
        await vaultExplorerApi.renameFile(container, tmpPath, cachePath);
      } else {
        await vaultExplorerApi.deleteFile(container, tmpPath);
        debugPrint('ThumbnailCacheService._putToContainer: '
            'write failed for $filePath');
      }
    } catch (e) {
      debugPrint('ThumbnailCacheService._putToContainer: $e');
    }
  }

  // ── Cache management ───────────────────────────────────────────────────────

  static Future<int> appCacheBytesFor(MountedContainer container) async {
    try {
      final dir = Directory(await _thumbDir(container.volId));
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final e in dir.list()) {
        if (e is File) total += await e.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> totalAppCacheBytes() async {
    try {
      _appCacheRoot ??= (await getApplicationCacheDirectory()).path;
      final dir = Directory('$_appCacheRoot/thumbs');
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final e in dir.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearAppCacheFor(MountedContainer container) async {
    try {
      final dir = Directory(await _thumbDir(container.volId));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    // LruCache has no prefix-delete, so flush the whole memory cache.
    // It refills quickly on the next scroll.
    _memoryCache.clear();
  }

  static Future<void> clearAllAppCache() async {
    try {
      _appCacheRoot ??= (await getApplicationCacheDirectory()).path;
      final dir = Directory('$_appCacheRoot/thumbs');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    _memoryCache.clear();
  }

  static Future<void> pruneStaleAppCache(Set<int> activeVolIds) async {
    try {
      _appCacheRoot ??= (await getApplicationCacheDirectory()).path;
      final root = Directory('$_appCacheRoot/thumbs');
      if (!await root.exists()) return;
      await for (final e in root.list()) {
        if (e is! Directory) continue;
        final id = int.tryParse(e.path.split('/').last);
        if (id != null && !activeVolIds.contains(id)) {
          await e.delete(recursive: true);
        }
      }
    } catch (_) {}
  }
}