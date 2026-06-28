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
///
/// Tier 1 — static in-memory [LruCache] ([_memoryCache])
///   Synchronous O(1).  Survives widget dispose/recreate within a session.
///   120 entries × ~20 KB ≈ 2.4 MB maximum footprint.
///   Checked first, before any async work is scheduled.
///
/// Tier 2 — encrypted disk file (appCache) or container file (inContainer)
///   Async; AES-GCM runs *inline* (no Isolate spawn).
///   App-cache directory path cached statically after first resolution.
///   File read via try/catch — no redundant exists() syscall on every miss.
///
/// Tier 3 — full container read (handled by callers on a complete miss)
///   Returns raw or native-thumbnail bytes; callers write the result back
///   into Tier 1 and schedule a Tier 2 write so the next access is faster.
class ThumbnailCacheService {
  ThumbnailCacheService._();

  // ── Constants ──────────────────────────────────────────────────────────────
  static const inContainerDir = '.thumbcache';
  static const _gcmNonceSize  = 12;
  static const _gcmTagSize    = 16; // AES-GCM authentication tag

  // ── Tier 1: static in-memory LRU ──────────────────────────────────────────
  // Static so the cache survives widget disposal and scroll recycling.
  static final _memoryCache = LruCache<String, Uint8List>(120);

  // ── AES key — read from Keystore exactly once per app session ─────────────
  static enc.Key? _cachedKey;

  /// Returns the persistent AES-256 key.  Safe to call from any async context.
  static Future<enc.Key> getOrFetchKey() async =>
      _cachedKey ??= await AppCacheEncryption.getEncryptionKey();

  // ── App-cache directory — resolved once, never re-queried ─────────────────
  //
  // BUG FIXED: the old code called getApplicationCacheDirectory() on *every*
  // single cache read, paying a platform-channel round-trip every time.
  // The path never changes at runtime; cache it statically.
  static String? _appCacheRoot;

  static Future<String> _thumbDir(int volId) async {
    _appCacheRoot ??= (await getApplicationCacheDirectory()).path;
    return '$_appCacheRoot/thumbs/$volId';
  }

  // ── Filename encoding ──────────────────────────────────────────────────────
  static String _encodeKey(String filePath) {
    final encoded = base64Url.encode(utf8.encode(filePath));
    return encoded.length > 180 ? encoded.substring(0, 180) : encoded;
  }

  // ── AES-GCM — inline, no Isolate ──────────────────────────────────────────
  //
  // BUG FIXED: the old code used Isolate.run() for every encrypt/decrypt.
  // Spawning a fresh Isolate costs ~5–10 ms.
  // AES-GCM on a 20 KB thumbnail costs ~0.3 ms.
  // The isolate overhead was 20–30× the actual work, making every disk cache
  // hit *slower* than reading directly from the container.
  //
  // Running AES-GCM inline is safe here: the concurrency limiter upstream
  // ensures at most 2 image loads run simultaneously, so the worst-case
  // synchronous CPU cost per frame is ~0.6 ms — well inside a 16 ms budget.
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
  ///
  /// Call this from widget [initState] / [build] so that already-loaded
  /// thumbnails are displayed immediately without entering the async pipeline.
  static Uint8List? getFromMemory(MountedContainer container, String filePath) =>
      _memoryCache[_memKey(container, filePath)];

  /// Writes directly to the in-memory tier.  Safe to call from any async context.
  static void putInMemory(
      MountedContainer container, String filePath, Uint8List data) =>
      _memoryCache[_memKey(container, filePath)] = data;

  // ── Public: read ──────────────────────────────────────────────────────────

  /// Returns cached thumbnail bytes, or null on a miss.
  ///
  /// Read order: Tier 1 (memory, synchronous) → Tier 2 (disk / container).
  /// On a Tier-2 hit the result is promoted to Tier 1 automatically.
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
    try {
      if (mode == ThumbnailCacheMode.appCache) {
        final dir  = await _thumbDir(container.volId);
        final file = File('$dir/${_encodeKey(filePath)}');

        // BUG FIXED: old code called file.exists() before file.readAsBytes().
        // That's two syscalls for every miss.  Using try/catch on readAsBytes()
        // handles the ENOENT case in a single syscall.
        final Uint8List raw;
        try {
          raw = await file.readAsBytes();
        } on PathNotFoundException {
          return null; // Clean miss — no bytes written yet.
        } catch (_) {
          return null;
        }

        if (raw.length <= _gcmNonceSize + _gcmTagSize) return null;

        final key       = await getOrFetchKey();
        final decrypted = _decrypt(raw, key); // Inline — fast for thumbnail data.
        if (decrypted == null || decrypted.isEmpty) return null;

        // Promote to Tier 1 so the next access is instant.
        putInMemory(container, filePath, decrypted);
        return decrypted;
      } else {
        // inContainer: stored unencrypted inside the FAT filesystem.
        final cachePath = '$inContainerDir/${_encodeKey(filePath)}';
        final size = await vaultExplorerApi.getFileSize(container, cachePath);
        if (size <= 0) return null;
        final bytes =
            await vaultExplorerApi.readFileChunk(container, cachePath, 0, size);
        if (bytes != null && bytes.isNotEmpty) {
          putInMemory(container, filePath, bytes);
        }
        return bytes;
      }
    } catch (e) {
      debugPrint('ThumbnailCacheService.get: $e');
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
        final dirPath = await _thumbDir(container.volId);
        final dir     = Directory(dirPath);
        if (!await dir.exists()) await dir.create(recursive: true);

        final file      = File('$dirPath/${_encodeKey(filePath)}');
        final key       = await getOrFetchKey();
        final encrypted = _encrypt(data, key); // Inline — fast for small data.

        // Atomic write: write to a temp file then rename to prevent partial reads.
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsBytes(encrypted, flush: true);
        await tmp.rename(file.path);
      } else {
        // inContainer
        final cachePath = '$inContainerDir/${_encodeKey(filePath)}';
        final tmpPath   = '$cachePath.tmp';
        await vaultExplorerApi.createDirectory(container, inContainerDir);
        await vaultExplorerApi.deleteFile(container, tmpPath);
        final ok =
            await vaultExplorerApi.writeFileChunk(container, tmpPath, 0, data);
        if (ok) {
          await vaultExplorerApi.deleteFile(container, cachePath);
          await vaultExplorerApi.renameFile(container, tmpPath, cachePath);
        } else {
          await vaultExplorerApi.deleteFile(container, tmpPath);
          debugPrint('ThumbnailCacheService.put: inContainer write failed for $filePath');
        }
      }
    } catch (e) {
      debugPrint('ThumbnailCacheService.put: $e');
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
    // LruCache has no prefix-delete API, so flush the whole memory cache
    // conservatively.  It will refill quickly on the next scroll.
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