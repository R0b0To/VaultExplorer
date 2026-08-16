import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/core/utils/byte_budget_cache.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/services/app_cache_encryption.dart';

import 'media_aspect_ratio_cache.dart';

/// Three-tier thumbnail cache.
class ThumbnailCacheService {
  ThumbnailCacheService._();

  static const _channel = MethodChannel('com.aeidolon.vaultexplorer/engine');

  // ── Constants ──────────────────────────────────────────────────────────────
  static const inContainerDir = '.thumbcache';
  static const _gcmNonceSize = 12;
  static const _gcmTagSize = 16;

  /// Data above this size is encrypted/decrypted in a background isolate via
  /// [compute()] to avoid blocking the UI thread.
  static const _computeThresholdBytes = 500 * 1024; // 500 KB

  /// Read length used for in-container cache lookups. Thumbnails are always
  /// small JPEGs (a few KB to a few hundred KB), so this is deliberately
  /// generous headroom, not an expected size — native clamps to however many
  /// bytes the file actually contains (or returns null/empty on a miss), so
  /// this lets [get] skip a separate getFileSize() round trip entirely
  /// without risking a truncated read.
  static const _inContainerReadCap = 8 * 1024 * 1024; // 8 MB

  // ── Tier 1: static in-memory, byte-budgeted LRU (Finding F-01) ─────────────
  //
  // 24 MB comfortably covers the documented worst case (~150 KB per
  // thumbnail at max ThumbnailQuality × a few hundred resident entries)
  // without capping raw entry count the way the old 120-entry LruCache did
  // — a user on the lowest quality setting can now hold far more thumbnails
  // resident than one on the highest, which is the point: memory scales
  // with actual bytes held, not an arbitrary count that meant wildly
  // different things depending on a setting this cache doesn't control.
  static const int _memoryMaxBytes = 24 * 1024 * 1024;
  static final _memoryCache = ByteBudgetCache(_memoryMaxBytes);

  static void resizeMemoryBudget(int newMaxBytes) =>
      _memoryCache.resize(newMaxBytes);

  static void trimMemoryToFraction(double fraction) =>
      _memoryCache.trimToFraction(fraction);

  // ── AES key ────────────────────────────────────────────────────────────────
  static Future<Uint8List>? _keyFuture;
  static Future<Uint8List> getOrFetchKey() =>
      _keyFuture ??= AppCacheEncryption.getEncryptionKey();

  // ── App-cache directory — resolved once ───────────────────────────────────
  //
  // Keyed by the container's URI (MD5 hashed)
  // rather than by volId. Two different container files that happen to occupy
  // the same volume slot at different times therefore never share a disk
  // directory, eliminating stale thumbnail cross-contamination.
  static Future<String>? _appCacheRootFuture;

  static Future<String> _getAppCacheRoot() {
    return _appCacheRootFuture ??= getApplicationCacheDirectory().then((d) => d.path);
  }

  static Future<String> _thumbDir(MountedContainer container) async {
    final root = await _getAppCacheRoot();
    final key = await _encodeKey(container.uri);
    return '$root/thumbs/$key';
  }

  // ── Filename / key encoding ────────────────────────────────────────────────
  //
  // Hashed natively via VaultExplorerApi.hashBytesMd5 (java.security.
  // MessageDigest on the Kotlin side) rather than a Dart hashing package --
  // MD5 here is purely a cache-key derivation, not a security boundary, so
  // it deliberately stays MD5 rather than switching to SHA-256 (that would
  // change every existing key and orphan the cache on upgrade).
  static Future<String> _encodeKey(String value) {
    return vaultExplorerApi.hashBytesMd5(Uint8List.fromList(utf8.encode(value)));
  }

  // ── Quality-qualified path key ─────────────────────────────────────────────
  //
  // Folds size+quality into the string that gets hashed/stored, so a settings
  // change (app default or per-container override) naturally produces a new
  // cache key instead of silently serving a stale thumbnail rendered at the
  // old size/quality. Old entries just become unreachable orphans, cleaned up
  // the same way any other stale cache entry is (manual clear / prune).
  static String _qualifiedPath(String filePath, ThumbnailQuality quality) =>
      '$filePath|${quality.size}|${quality.quality}';

  // ── Size sidecar ────────────────────────────────────────────────────────────
  //
  // The cache's payload is always just the thumbnail JPEG. Dimensions (known
  // from the platform's `...WithSize` channel methods — see
  // ThumbnailWithSize) are tracked separately: in-memory via [_sizeCache],
  // and on disk/in-container via the `.meta` sidecar file written alongside
  // each cached thumbnail. This keeps the cached bytes themselves untouched
  // and lets any reader treat them as plain JPEG data with no unpacking step.

  /// Sidecar map for caching thumbnail dimensions without altering JPEG bytes
  static final Map<String, (int width, int height)> _sizeCache = {};

  // ── Memory-tier key ───────────────────────────────────────────────────────
  //
  // Includes mountedAt so that a new session for the same volId always
  // generates a distinct key, preventing stale bytes from a previous container
  // from being served without a disk/API round-trip. Also includes the
  // requested quality/size so switching the setting doesn't return a
  // wrong-resolution thumbnail from the in-memory tier.
  static String _memKey(
    MountedContainer container,
    String filePath,
    ThumbnailQuality quality,
  ) =>
      '${container.volId}:${container.mountedAt.millisecondsSinceEpoch}:'
      '${_qualifiedPath(filePath, quality)}';

  // ── AES-GCM helpers ────────────────────────────────────────────────────────

  static Future<Uint8List?> _decrypt(Uint8List raw, Uint8List key) async {
    if (raw.length <= _gcmNonceSize + _gcmTagSize) return null;
    try {
      final iv = raw.sublist(0, _gcmNonceSize);
      final ciphertextAndTag = raw.sublist(_gcmNonceSize);
      return await vaultExplorerApi.aesGcmDecrypt(
        key: key,
        iv: iv,
        ciphertextAndTag: ciphertextAndTag,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> _encrypt(Uint8List data, Uint8List key) async {
    final rng = Random.secure();
    final iv = Uint8List(_gcmNonceSize);
    for (int i = 0; i < _gcmNonceSize; i++) {
      iv[i] = rng.nextInt(256);
    }
    final encryptedAndTag = await vaultExplorerApi.aesGcmEncrypt(
      key: key,
      iv: iv,
      plaintext: data,
    );
    if (encryptedAndTag == null) {
      throw Exception('AES-GCM encryption failed');
    }
    final out = Uint8List(_gcmNonceSize + encryptedAndTag.length);
    out.setRange(0, _gcmNonceSize, iv);
    out.setRange(_gcmNonceSize, out.length, encryptedAndTag);
    return out;
  }

  // ── Memory-tier public helpers ─────────────────────────────────────────────

  /// Synchronous O(1) lookup into the in-memory tier. Returns the plain
  /// JPEG bytes. Use [getWithSizeFromMemory] if you also need the size.
  ///
  /// Validated the same way a disk read is (see [_looksLikeValidJpeg]):
  /// an entry that doesn't look like a real JPEG is evicted and treated as
  /// a miss rather than handed back to the caller. [putInMemory] already
  /// rejects malformed bytes before they're stored, so in the normal case
  /// this never trips -- it exists as the same belt-and-suspenders the disk
  /// tier has always had, so a bad entry (e.g. one written by a future code
  /// path that bypasses [putInMemory]) can never reach a consumer like
  /// [MediaPlayerWidget]'s poster `Image.memory` call -- where a corrupt
  /// blob doesn't fail loudly, it just fails to decode and lets whatever's
  /// behind it (typically a plain black `Container`) show through as a
  /// flash of black.
  ///
  /// [quality] defaults to [ThumbnailQuality.defaultQuality] for callers that
  /// only want an optimistic "whatever's cached" placeholder (e.g. showing
  /// something instantly before a full-res load) and don't have the current
  /// quality setting in scope. Callers that fetch/store real thumbnails at a
  /// specific quality should always pass it explicitly so they read back
  /// exactly what they wrote.
static Uint8List? getFromMemory(
    MountedContainer container,
    String filePath, [
    ThumbnailQuality quality = ThumbnailQuality.defaultQuality,
  ]) {
    final key = _memKey(container, filePath, quality);
    final stored = _memoryCache[key];
    if (stored != null) {
      if (_looksLikeValidJpeg(stored)) return stored;
      _memoryCache.remove(key);
    }

    // Prefix search: Find ANY resident thumbnail in RAM for this file,
    // regardless of what quality key Masonry view stored it under.
    final prefix = '${container.volId}:${container.mountedAt.millisecondsSinceEpoch}:$filePath|';
    final matchedKey = _memoryCache.keys.firstWhere(
      (k) => k.startsWith(prefix),
      orElse: () => '',
    );
    if (matchedKey.isNotEmpty) {
      final alt = _memoryCache[matchedKey];
      if (alt != null) {
        if (_looksLikeValidJpeg(alt)) return alt;
        _memoryCache.remove(matchedKey);
      }
    }
    return null;
  }

  /// Same lookup as [getFromMemory], but also returns the width/height that
  /// were cached alongside the bytes in [_sizeCache], if any (null, null if
  /// this entry was stored without a known size). Validated and self-evicting
  /// the same way [getFromMemory] is -- see its doc.
  ///
  /// Mirrors [getFromMemory]'s prefix-search fallback: if nothing is resident
  /// under the exact (filePath, quality) key, this also checks for ANY
  /// resident entry for this file under a different quality key. Without
  /// this, a masonry view landing on a file for the first time this session
  /// (nothing generated yet at *its* quality, even though a same-file entry
  /// exists in RAM at another quality) would synchronously report a miss and
  /// fall back to the icon aspect ratio, only self-correcting once the async
  /// fetch completes and triggers a rebuild -- and in practice never getting
  /// that rebuild to reflow cleanly until the next full grid rebuild (e.g.
  /// navigating away and back, or pull-to-refresh).
  static (Uint8List bytes, int? width, int? height)? getWithSizeFromMemory(
    MountedContainer container,
    String filePath, [
    ThumbnailQuality quality = ThumbnailQuality.defaultQuality,
  ]) {
    final key = _memKey(container, filePath, quality);
    final stored = _memoryCache[key];
    if (stored != null) {
      if (_looksLikeValidJpeg(stored)) {
        final size = _sizeCache[key];
        return (stored, size?.$1, size?.$2);
      }
      _memoryCache.remove(key);
    }

    // Prefix search: find ANY resident thumbnail in RAM for this file,
    // regardless of what quality key it was stored under (see [getFromMemory]).
    final prefix = '${container.volId}:${container.mountedAt.millisecondsSinceEpoch}:$filePath|';
    final matchedKey = _memoryCache.keys.firstWhere(
      (k) => k.startsWith(prefix),
      orElse: () => '',
    );
    if (matchedKey.isNotEmpty) {
      final alt = _memoryCache[matchedKey];
      if (alt != null) {
        if (_looksLikeValidJpeg(alt)) {
          final size = _sizeCache[matchedKey];
          return (alt, size?.$1, size?.$2);
        }
        _memoryCache.remove(matchedKey);
      }
    }
    return null;
  }

  /// Writes directly to the in-memory tier. See [getFromMemory] re:
  /// [quality]. Pass [width]/[height] when known so a later
  /// [getWithSizeFromMemory] call can read them back without redecoding.
  ///
  /// Rejects [data] that doesn't look like a real JPEG (see
  /// [_looksLikeValidJpeg]) before packing/storing it -- the same guard
  /// [put] has always applied to the *disk* tier, now applied here too so
  /// the two tiers can't disagree about whether a given entry is trustworthy.
  /// This is the single choke point every writer (this method directly, and
  /// [put], which calls it) goes through, so fixing it here closes the gap
  /// for all of them at once rather than needing each call site to remember.
  static void putInMemory(
    MountedContainer container,
    String filePath,
    Uint8List data, [
    ThumbnailQuality quality = ThumbnailQuality.defaultQuality,
    int? width,
    int? height,
  ]) {
    if (!_looksLikeValidJpeg(data)) {
      return;
    }
    final key = _memKey(container, filePath, quality);
    _memoryCache[key] = data;

    if (width != null && height != null && width > 0 && height > 0) {
      _sizeCache[key] = (width, height);
      MediaAspectRatioCache.put(container, filePath, width, height);
    }
  }

  // ── Public: read ──────────────────────────────────────────────────────────

  static Future<Uint8List?> get({
    required MountedContainer container,
    required String filePath,
    required ThumbnailCacheMode mode,
    required ThumbnailQuality quality,
  }) async {
    final result = await getWithSize(
      container: container,
      filePath: filePath,
      mode: mode,
      quality: quality,
    );
    return result?.$1;
  }

  /// Same lookup as [get], but also returns the width/height recorded for
  /// this entry (from the `.meta` sidecar / [_sizeCache]), if any — null,
  /// null for entries written without a known size. Callers that only want
  /// bytes can keep calling [get].
  static Future<(Uint8List bytes, int? width, int? height)?> getWithSize({
    required MountedContainer container,
    required String filePath,
    required ThumbnailCacheMode mode,
    required ThumbnailQuality quality,
  }) async {
    if (mode == ThumbnailCacheMode.disabled) return null;

    // Tier 1: memory.
    final mem = getWithSizeFromMemory(container, filePath, quality);
    if (mem != null) return mem;

    // Tier 2: disk / in-container.
    try {
      if (mode == ThumbnailCacheMode.appCache) {
        final dir = await _thumbDir(container);
        final cacheKey = await _encodeKey(_qualifiedPath(filePath, quality));
        var file = File('$dir/$cacheKey');

        // Fallback: If exact quality key misses on disk, check base filePath key
        if (!await file.exists()) {
          final baseKey = await _encodeKey(filePath);
          file = File('$dir/$baseKey');
        }

        final Uint8List raw;
        try {
          raw = await file.readAsBytes();
        } on PathNotFoundException {
          return null;
        } catch (_) {
          return null;
        }

        if (raw.length <= _gcmNonceSize + _gcmTagSize) return null;

        final key = await getOrFetchKey();
        final decrypted = await _decrypt(raw, key);
        if (decrypted == null || decrypted.isEmpty) return null;

        final bytes = decrypted;
        if (!_looksLikeValidJpeg(bytes)) {
          return null;
        }

        int? width;
        int? height;

        // Restore dimensions from sidecar .meta file if present
        final metaFile = File('${file.path}.meta');
        if (await metaFile.exists()) {
          try {
            final rawMeta = await metaFile.readAsBytes();
            final decMeta = await _decrypt(rawMeta, key);
            if (decMeta != null && decMeta.length >= 4) {
              width = (decMeta[0] << 8) | decMeta[1];
              height = (decMeta[2] << 8) | decMeta[3];
            }
          } catch (_) {}
        }

        putInMemory(container, filePath, bytes, quality, width, height);
        return (bytes, width, height);
      } else {
        final key = await _encodeKey(_qualifiedPath(filePath, quality));
        final cachePath = '$inContainerDir/$key';
        final stored = await vaultExplorerApi.readFileChunk(
          container,
          cachePath,
          0,
          _inContainerReadCap,
        );
        if (stored == null || stored.isEmpty) return null;

        final bytes = stored;
        if (!_looksLikeValidJpeg(bytes)) {
          return null;
        }

        int? width;
        int? height;

        // Restore dimensions from in-container sidecar .meta file
        {
          try {
            final metaBytes = await vaultExplorerApi.readFileChunk(
              container,
              '$cachePath.meta',
              0,
              16,
            );
            if (metaBytes != null && metaBytes.length >= 4) {
              width = (metaBytes[0] << 8) | metaBytes[1];
              height = (metaBytes[2] << 8) | metaBytes[3];
            }
          } catch (_) {}
        }

        putInMemory(container, filePath, bytes, quality, width, height);
        return (bytes, width, height);
      }
    } catch (e) {
      return null;
    }
  }

  /// Clears on-disk local app cache directories using only the container URI.
  static Future<void> clearAppCacheByUri(String uri) async {
    _ensuredThumbDirs.remove(uri);
    try {
      final root = await _getAppCacheRoot();
      final key = await _encodeKey(uri);
      final dirPath = '$root/thumbs/$key';
      _ensuredThumbDirs.remove(dirPath);
      
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
    _memoryCache.clear();
  }

  /// Clears the .thumbcache directory inside the mounted volume by direct channel invocations.
  /// Throws PlatformException if the container is locked (not mounted).
  static Future<void> clearInContainerCacheByUri(String uri) async {
    _ensuredThumbDirs.remove(uri);
    try {
      final entries = await _channel.invokeMethod<List<Object?>>(
        'listDirectory',
        {'filePath': uri, 'dirPath': inContainerDir},
      );
      if (entries != null) {
        final casted = entries.cast<String>();
        for (final raw in casted) {
          if (raw.startsWith('System:')) continue;
          final name = RawEntry.parse(raw).name;
          await _channel.invokeMethod<bool>(
            'deleteFile',
            {'filePath': uri, 'fileName': '$inContainerDir/$name'},
          );
        }
      }
      await _channel.invokeMethod<bool>(
        'deleteFile',
        {'filePath': uri, 'fileName': inContainerDir},
      );
    } catch (_) {
      rethrow;
    }
  }

// Use a Map of Futures to prevent race conditions during directory creation
static final Map<String, Future<void>> _ensuredThumbDirs = {};

/// Coalesces concurrent [put] calls for the identical (container, file,
/// quality, mode) target into a single write. Without this, two
/// independent code paths generating a thumbnail for the same upcoming
/// file around the same time — e.g. the playlist carousel and the main
/// viewer's own surrounding-item prefetch, which have no cross-component
/// awareness of each other — could each issue their own write to the
/// same cache path concurrently. The appCache branch's unique temp file
/// makes that survivable there (worst case, one writer's rename loses,
/// the other's complete file wins); the in-container branch's shared
/// `<fileName>.tmp` staging path (see [VaultExplorerApi.writeWholeFile])
/// does not have that safety margin — two concurrent stagers writing to
/// the same tmp path can genuinely interleave. Keyed on the same
/// components as the on-disk cache key so it doesn't cross-block
/// unrelated targets.
static final Map<String, Future<void>> _inFlightPuts = {};

/// True if [jpegBytes] has a plausible JPEG structure: the SOI marker
/// (0xFFD8) at the start and the EOI marker (0xFFD9) at the end. Not a
/// full decode — just cheap enough to run on every write and catch a
/// truncated/torn result before it's ever trusted as a cache hit,
/// without needing a real image codec here.
static bool _looksLikeValidJpeg(Uint8List jpegBytes) {
  if (jpegBytes.length < 4) return false;
  if (jpegBytes[0] != 0xFF || jpegBytes[1] != 0xD8) return false;
  final len = jpegBytes.length;
  return jpegBytes[len - 2] == 0xFF && jpegBytes[len - 1] == 0xD9;
}

static Future<void> put({
  required MountedContainer container,
  required String filePath,
  required Uint8List data,
  required ThumbnailCacheMode mode,
  required ThumbnailQuality quality,
  int? width,
  int? height,
}) {
  if (mode == ThumbnailCacheMode.disabled || data.isEmpty) return Future.value();

  putInMemory(container, filePath, data, quality, width, height);

  if (!_looksLikeValidJpeg(data)) {
    return Future.value();
  }

  final dedupKey = '${mode.name}:${container.volId}:'
      '${container.mountedAt.millisecondsSinceEpoch}:'
      '${_qualifiedPath(filePath, quality)}';
  final existing = _inFlightPuts[dedupKey];
  if (existing != null) return existing;

  final future = _putInternal(
    container: container,
    filePath: filePath,
    data: data,
    mode: mode,
    quality: quality,
    width: width,
    height: height,
  );
  _inFlightPuts[dedupKey] = future;
  return future.whenComplete(() {
    if (identical(_inFlightPuts[dedupKey], future)) {
      _inFlightPuts.remove(dedupKey);
    }
  });
}

static Future<void> _putInternal({
  required MountedContainer container,
  required String filePath,
  required Uint8List data,
  required ThumbnailCacheMode mode,
  required ThumbnailQuality quality,
  int? width,
  int? height,
}) async {
  final cleanData = data;

  try {
    if (mode == ThumbnailCacheMode.appCache) {
      final dirPath = await _thumbDir(container);
      
      if (!_ensuredThumbDirs.containsKey(dirPath)) {
        _ensuredThumbDirs[dirPath] = Directory(dirPath).create(recursive: true).then((_) {});
      }
      await _ensuredThumbDirs[dirPath];

      final cacheKey = await _encodeKey(_qualifiedPath(filePath, quality));
      final baseKey = await _encodeKey(filePath);
      final file = File('$dirPath/$cacheKey');
      final baseFile = File('$dirPath/$baseKey');
      final key = await getOrFetchKey();
      
      // 1. Write pure JPEG payload encrypted to disk
      final encrypted = await _encrypt(cleanData, key);
      final uniqueId = DateTime.now().microsecondsSinceEpoch;
      final tmp = File('${file.path}.$uniqueId.tmp');
      await tmp.writeAsBytes(encrypted, flush: true);
      await tmp.rename(file.path);

      // Also copy/link to baseKey so any thumbnail request for this filePath hits
      try {
        await file.copy(baseFile.path);
      } catch (_) {}

      // 2. Persist sidecar metadata file for dimensions if provided
      if (width != null && height != null && width > 0 && height > 0) {
        final metaBytes = Uint8List(4)
          ..[0] = (width >> 8) & 0xFF
          ..[1] = width & 0xFF
          ..[2] = (height >> 8) & 0xFF
          ..[3] = height & 0xFF;
        final metaEncrypted = await _encrypt(metaBytes, key);
        final metaFile = File('${file.path}.meta');
        final metaTmp = File('${metaFile.path}.$uniqueId.tmp');
        await metaTmp.writeAsBytes(metaEncrypted, flush: true);
        await metaTmp.rename(metaFile.path);
      }

      if (++_putWriteCount % 25 == 0) {
        unawaited(enforceDiskBudget());
      }
    } else {
      final keyHex = await _encodeKey(_qualifiedPath(filePath, quality));
      final cachePath = '$inContainerDir/$keyHex';
      final uriStr = container.uri.toString();

      if (!_ensuredThumbDirs.containsKey(uriStr)) {
        _ensuredThumbDirs[uriStr] = vaultExplorerApi.createDirectory(container, inContainerDir);
      }
      await _ensuredThumbDirs[uriStr];

      // 1. Write pure JPEG payload to in-container storage
      final ok = await vaultExplorerApi.writeWholeFile(container, cachePath, cleanData);
      
      // 2. Persist sidecar metadata for dimensions in container
      if (ok && width != null && height != null && width > 0 && height > 0) {
        final metaBytes = Uint8List(4)
          ..[0] = (width >> 8) & 0xFF
          ..[1] = width & 0xFF
          ..[2] = (height >> 8) & 0xFF
          ..[3] = height & 0xFF;
        await vaultExplorerApi.writeWholeFile(container, '$cachePath.meta', metaBytes);
      }

      if (ok && ++_inContainerPutWriteCount % 25 == 0) {
        unawaited(enforceInContainerDiskBudget(container));
      }
    }
  } catch (_) {
    // Caching the thumbnail failed; the caller doesn't need to know since
    // the thumbnail will simply be regenerated on next access.
  }
}
  // ── Cache management ───────────────────────────────────────────────────────

  static Future<int> appCacheBytesFor(MountedContainer container) async {
    try {
      final dir = Directory(await _thumbDir(container));
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
      final root = await _getAppCacheRoot();
      final dir = Directory('$root/thumbs');
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

  /// Called on every container lock (F-16). Only clears the in-memory tier:
  /// those bytes are decrypted and resident in RAM for as long as the
  /// process lives, so they must not outlive the lock. The on-disk appCache
  /// tier is intentionally left alone — it's encrypted at rest under a
  /// persistent key (see [AppCacheEncryption]) specifically so it *can*
  /// survive lock/unlock without re-generating every thumbnail; wiping it
  /// here would defeat the entire point of [ThumbnailCacheMode.appCache].
  /// Use [clearAppCacheByUri] / [clearAllAppCache] for an explicit,
  /// user-initiated disk clear.
  static Future<void> clearAppCacheFor(MountedContainer container) async {
    // Scoped to this container's volId prefix (see _memKey) rather than a
    // blanket clear — other containers may still be mounted with warm,
    // still-valid entries of their own.
    _memoryCache.removeWhere((key) => key.startsWith('${container.volId}:'));
  }

  static Future<void> clearAllAppCache() async {
    _ensuredThumbDirs.clear();
    try {
      final root = await _getAppCacheRoot();
      final dir = Directory('$root/thumbs');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    _memoryCache.clear();
  }

  // Default maximum on-disk app cache budget (100 MB) — ADR-014, Finding F-08
  static const int defaultMaxAppCacheBytes = 100 * 1024 * 1024;
  static int _putWriteCount = 0;

  /// Enforces L2 disk cache byte budget (ADR-014, Finding F-08).
  ///
  /// Scans all thumbnail files under the app cache directory, and if total
  /// usage exceeds [maxBytes], evicts the oldest files by modification time
  /// (`stat.modified`) until usage drops down to 80% of [maxBytes].
  static Future<void> enforceDiskBudget([
    int maxBytes = defaultMaxAppCacheBytes,
  ]) async {
    try {
      final rootPath = await _getAppCacheRoot();
      final root = Directory('$rootPath/thumbs');
      if (!await root.exists()) return;

      final files = <({File file, int size, DateTime modified})>[];
      var totalBytes = 0;

      await for (final entity in root.list(recursive: true)) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.tmp')) continue;
        try {
          final stat = await entity.stat();
          files.add((file: entity, size: stat.size, modified: stat.modified));
          totalBytes += stat.size;
        } catch (_) {}
      }

      if (totalBytes <= maxBytes) return;

      final targetBytes = (maxBytes * 0.8).toInt();
      files.sort((a, b) => a.modified.compareTo(b.modified));

      for (final entry in files) {
        if (totalBytes <= targetBytes) break;
        try {
          await entry.file.delete();
          totalBytes -= entry.size;
        } catch (_) {}
      }
    } catch (e) {

    }
  }


  static const int defaultMaxInContainerCacheBytes = 50 * 1024 * 1024;
  static int _inContainerPutWriteCount = 0;


  static Future<void> enforceInContainerDiskBudget(
    MountedContainer container, [
    int maxBytes = defaultMaxInContainerCacheBytes,
  ]) async {
    try {
      final totalBytes = await vaultExplorerApi.getFolderSize(
        container,
        inContainerDir,
      );
      if (totalBytes <= maxBytes) return;

      final rawEntries = await vaultExplorerApi.listDirectory(
        container,
        inContainerDir,
      );
      if (rawEntries == null || rawEntries.isEmpty) return;

      final entries = rawEntries
          .where((raw) => !raw.startsWith('System:'))
          .map(RawEntry.parse)
          .where((e) => !e.isDir && !e.name.endsWith('.tmp'))
          .toList()
        ..sort((a, b) => a.modifiedSecs.compareTo(b.modifiedSecs));

      final targetBytes = (maxBytes * 0.8).toInt();
      var runningBytes = totalBytes;

      for (final entry in entries) {
        if (runningBytes <= targetBytes) break;
        final deleted = await vaultExplorerApi.deleteFile(
          container,
          '$inContainerDir/${entry.name}',
        );
        if (deleted) runningBytes -= entry.sizeBytes;
      }
    } catch (e) {

    }
  }

  /// Deletes on-disk thumbnail directories for containers whose URIs are not
  /// in [activeContainerUris]. Call this on app start or after a bulk lock.
  ///
  /// Signature changed from `Set<int> activeVolIds` to `Set<String> activeContainerUris`
  /// because disk directories are now keyed by encoded URI, not volId.
  static Future<void> pruneStaleAppCache(
    Set<String> activeContainerUris,
  ) async {
    try {
      final rootPath = await _getAppCacheRoot();
      final root = Directory('$rootPath/thumbs');
      if (!await root.exists()) return;
      final activeKeys = <String>{};
      for (final uri in activeContainerUris) {
        activeKeys.add(await _encodeKey(uri));
      }
      await for (final e in root.list()) {
        if (e is! Directory) continue;
        final dirName = e.path.split('/').last;
        if (!activeKeys.contains(dirName)) {
          // Forget from memory state map so it doesn't fail if revisited later
          _ensuredThumbDirs.removeWhere((key, _) => key.contains(dirName));
          await e.delete(recursive: true);
        }
      }
    } catch (_) {}
  }
}