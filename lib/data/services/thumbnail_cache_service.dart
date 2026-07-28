import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/services.dart';

import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/core/utils/byte_budget_cache.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/services/app_cache_encryption.dart';

/// Three-tier thumbnail cache.
///
/// Tier 1 — static in-memory [ByteBudgetCache] ([_memoryCache])
///   Synchronous O(1). Survives widget dispose/recreate within a session.
///   payload whose size is a user-adjustable setting (see
///   `ThumbnailQuality`) shouldn't be able to swing effective memory use by
///   an order of magnitude the way a fixed entry cap did. See
///   [_memoryMaxBytes] for the current budget.
///
/// Tier 2 — encrypted disk file (appCache) or container file (inContainer).
///   AES-GCM runs inline for small thumbnails (< [_computeThresholdBytes])
///   and is offloaded to a background isolate via [compute()] for larger data.
///
/// Tier 3 — full container read (handled by callers on a complete miss).
///
/// ### Cache isolation across container lock/unlock cycles
///
/// Memory keys include [MountedContainer.mountedAt] so that a different
/// container mounted into the same volume slot always gets a fresh key —
/// stale entries from the previous session are never served and are evicted
/// naturally by LRU.
///
/// Disk cache directories are keyed by the container's URI (base64-encoded)
/// rather than by volId, so two different container files that happen to share
/// a slot at different times never collide on disk.
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
  static const int _memoryMaxBytes = 24 * 1024 * 1024;
  static final _memoryCache = ByteBudgetCache(_memoryMaxBytes);

  static void resizeMemoryBudget(int newMaxBytes) =>
      _memoryCache.resize(newMaxBytes);

  static void trimMemoryToFraction(double fraction) =>
      _memoryCache.trimToFraction(fraction);

  // ── AES key ────────────────────────────────────────────────────────────────
  static Future<enc.Key>? _keyFuture;
  static Future<enc.Key> getOrFetchKey() =>
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
    return '$root/thumbs/${_encodeKey(container.uri)}';
  }

  // ── Filename / key encoding ────────────────────────────────────────────────
  static String _encodeKey(String value) {
    const int fnvPrime = 1099511628211;
    const int offsetBasis = -2875151525287752661; // 0xcbf29ce484222325 as signed 64-bit int
    const int mask64 = 0xFFFFFFFFFFFFFFFF;

    int hash = offsetBasis;
    final bytes = utf8.encode(value);
    for (final byte in bytes) {
      hash = (hash ^ byte) & mask64;
      hash = (hash * fnvPrime) & mask64;
    }
    // Returns an extremely safe, unique 16-character hex filename
    return hash.toRadixString(16);
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

  // ── Optional size envelope ─────────────────────────────────────────────────
  //
  // The cache's payload is normally just the thumbnail JPEG. Callers that
  // know the source frame's true width/height (from the platform's
  // `...WithSize` channel methods — see ThumbnailWithSize) can additionally
  // persist it here, so a later cache *hit* — including across app restarts,
  // where MediaAspectRatioCache's in-memory entries are gone — still gives
  // masonry-style layouts the real aspect ratio without falling back to
  // decoding the JPEG bytes on the Dart side.
  //
  // Format: a 5-byte header (0x01 marker, then width/height as big-endian
  // u16 each) prepended to the JPEG bytes, all of it encrypted/stored as one
  // blob — no change to the encryption or storage path itself. u16 is ample
  // (thumbnails are capped at 1000px, see ThumbnailQuality). 0x01 as the
  // marker is safe against collision with un-enveloped legacy entries: every
  // JPEG starts with the SOI marker 0xFF 0xD8, never 0x01, so [_unpackSize]
  // can tell the two apart by that first byte alone and never misreads a
  // plain thumbnail's leading bytes as a header.
  static const _sizeEnvelopeMarker = 0x01;
  static const _sizeEnvelopeLength = 5; // 1 marker byte + 2×u16

  static Uint8List _packSize(Uint8List jpegBytes, int? width, int? height) {
    if (width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        width > 0xFFFF ||
        height > 0xFFFF) {
      return jpegBytes;
    }
    final out = Uint8List(_sizeEnvelopeLength + jpegBytes.length);
    out[0] = _sizeEnvelopeMarker;
    out[1] = (width >> 8) & 0xFF;
    out[2] = width & 0xFF;
    out[3] = (height >> 8) & 0xFF;
    out[4] = height & 0xFF;
    out.setRange(_sizeEnvelopeLength, out.length, jpegBytes);
    return out;
  }

  /// Splits a stored payload back into its JPEG bytes and, if present, the
  /// width/height that were packed alongside it. Payloads written before
  /// this envelope existed have no marker byte and are returned unchanged
  /// with a null size — never misinterpreted as having one.
  static (Uint8List bytes, int? width, int? height) _unpackSize(
    Uint8List stored,
  ) {
    if (stored.length <= _sizeEnvelopeLength || stored[0] != _sizeEnvelopeMarker) {
      return (stored, null, null);
    }
    final width = (stored[1] << 8) | stored[2];
    final height = (stored[3] << 8) | stored[4];
    return (stored.sublist(_sizeEnvelopeLength), width, height);
  }

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

  static Uint8List? _decryptInline(Uint8List raw, enc.Key key) {
    if (raw.length <= _gcmNonceSize + _gcmTagSize) return null;
    try {
      final iv = enc.IV(raw.sublist(0, _gcmNonceSize));
      final ciphertext = enc.Encrypted(raw.sublist(_gcmNonceSize));
      return Uint8List.fromList(
        enc.Encrypter(
          enc.AES(key, mode: enc.AESMode.gcm),
        ).decryptBytes(ciphertext, iv: iv),
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List _encryptInline(Uint8List data, enc.Key key) {
    final iv = enc.IV.fromSecureRandom(_gcmNonceSize);
    final encrypted = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.gcm),
    ).encryptBytes(data, iv: iv);
    final out = Uint8List(_gcmNonceSize + encrypted.bytes.length);
    out.setRange(0, _gcmNonceSize, iv.bytes);
    out.setRange(_gcmNonceSize, out.length, encrypted.bytes);
    return out;
  }

  // ── Top-level functions for compute() ─────────────────────────────────────

  static Uint8List? _decryptIsolate(_DecryptArgs args) {
    if (args.raw.length <= _gcmNonceSize + _gcmTagSize) return null;
    try {
      final key = enc.Key(args.keyBytes);
      final iv = enc.IV(args.raw.sublist(0, _gcmNonceSize));
      final ciphertext = enc.Encrypted(args.raw.sublist(_gcmNonceSize));
      return Uint8List.fromList(
        enc.Encrypter(
          enc.AES(key, mode: enc.AESMode.gcm),
        ).decryptBytes(ciphertext, iv: iv),
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List _encryptIsolate(_EncryptArgs args) {
    final key = enc.Key(args.keyBytes);
    final iv = enc.IV.fromSecureRandom(_gcmNonceSize);
    final encrypted = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.gcm),
    ).encryptBytes(args.data, iv: iv);
    final out = Uint8List(_gcmNonceSize + encrypted.bytes.length);
    out.setRange(0, _gcmNonceSize, iv.bytes);
    out.setRange(_gcmNonceSize, out.length, encrypted.bytes);
    return out;
  }

  // ── Dispatch helpers ───────────────────────────────────────────────────────

  static Future<Uint8List?> _decrypt(Uint8List raw, enc.Key key) async {
    if (raw.length < _computeThresholdBytes) {
      return _decryptInline(raw, key);
    }
    return compute(
      _decryptIsolate,
      _DecryptArgs(raw: raw, keyBytes: key.bytes),
    );
  }

  static Future<Uint8List> _encrypt(Uint8List data, enc.Key key) async {
    if (data.length < _computeThresholdBytes) {
      return _encryptInline(data, key);
    }
    return compute(
      _encryptIsolate,
      _EncryptArgs(data: data, keyBytes: key.bytes),
    );
  }

  // ── Memory-tier public helpers ─────────────────────────────────────────────

  /// Synchronous O(1) lookup into the in-memory tier. Returns the plain
  /// JPEG bytes — any packed size envelope (see [_packSize]) is stripped
  /// transparently. Use [getSizeFromMemory] if you also need the size.
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
    final stored = _memoryCache[_memKey(container, filePath, quality)];
    if (stored == null) return null;
    return _unpackSize(stored).$1;
  }

  /// Same lookup as [getFromMemory], but also returns the width/height that
  /// were packed alongside the bytes, if any (null, null if this entry
  /// predates the envelope or was stored without a known size).
  static (Uint8List bytes, int? width, int? height)? getWithSizeFromMemory(
    MountedContainer container,
    String filePath, [
    ThumbnailQuality quality = ThumbnailQuality.defaultQuality,
  ]) {
    final stored = _memoryCache[_memKey(container, filePath, quality)];
    if (stored == null) return null;
    return _unpackSize(stored);
  }

  /// Writes directly to the in-memory tier. See [getFromMemory] re:
  /// [quality]. Pass [width]/[height] when known so a later
  /// [getWithSizeFromMemory] call can read them back without redecoding.
  static void putInMemory(
    MountedContainer container,
    String filePath,
    Uint8List data, [
    ThumbnailQuality quality = ThumbnailQuality.defaultQuality,
    int? width,
    int? height,
  ]) =>
      _memoryCache[_memKey(container, filePath, quality)] =
          _packSize(data, width, height);

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

  /// Same lookup as [get], but also returns the width/height packed
  /// alongside the bytes (see [_packSize]), if any — null, null for entries
  /// written before the envelope existed, or written without a known size.
  /// Every read path (memory, disk, in-container) unwraps the envelope
  /// transparently, so callers that only want bytes can keep calling [get].
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
        final file = File('$dir/${_encodeKey(_qualifiedPath(filePath, quality))}');

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

        final (bytes, width, height) = _unpackSize(decrypted);
        putInMemory(container, filePath, bytes, quality, width, height);
        return (bytes, width, height);
      } else {
        final cachePath =
            '$inContainerDir/${_encodeKey(_qualifiedPath(filePath, quality))}';
        // Single round trip instead of getFileSize() + readFileChunk(): a
        // miss (file doesn't exist) comes back null/empty either way, and a
        // hit is always far smaller than _inContainerReadCap.
        final stored = await vaultExplorerApi.readFileChunk(
          container,
          cachePath,
          0,
          _inContainerReadCap,
        );
        if (stored == null || stored.isEmpty) return null;
        final (bytes, width, height) = _unpackSize(stored);
        putInMemory(container, filePath, bytes, quality, width, height);
        return (bytes, width, height);
      }
    } catch (e) {
      debugPrint('ThumbnailCacheService.get: $e');
      return null;
    }
  }

  /// Clears on-disk local app cache directories using only the container URI.
  static Future<void> clearAppCacheByUri(String uri) async {
    _ensuredThumbDirs.remove(uri);
    try {
      final root = await _getAppCacheRoot();
      final dirPath = '$root/thumbs/${_encodeKey(uri)}';
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

static Future<void> put({
  required MountedContainer container,
  required String filePath,
  required Uint8List data,
  required ThumbnailCacheMode mode,
  required ThumbnailQuality quality,
  int? width,
  int? height,
}) async {
  if (mode == ThumbnailCacheMode.disabled || data.isEmpty) return;

  putInMemory(container, filePath, data, quality, width, height);
  final payload = _packSize(data, width, height);

  try {
    if (mode == ThumbnailCacheMode.appCache) {
      final dirPath = await _thumbDir(container);
      
      if (!_ensuredThumbDirs.containsKey(dirPath)) {
        _ensuredThumbDirs[dirPath] = Directory(dirPath).create(recursive: true).then((_) {});
      }
      await _ensuredThumbDirs[dirPath];

      final file = File('$dirPath/${_encodeKey(_qualifiedPath(filePath, quality))}');
      final key = await getOrFetchKey();
      final encrypted = await _encrypt(payload, key);

      // Create a UNIQUE temp file to prevent concurrent write collisions
      final uniqueId = DateTime.now().microsecondsSinceEpoch;
      final tmp = File('${file.path}.$uniqueId.tmp');
      
      await tmp.writeAsBytes(encrypted, flush: true);

      await tmp.rename(file.path);
      if (++_putWriteCount % 25 == 0) {
        unawaited(enforceDiskBudget());
      }
    } else {
      final cachePath =
          '$inContainerDir/${_encodeKey(_qualifiedPath(filePath, quality))}';
      
      // Unique temp path for the vault to prevent write conflicts
      final uniqueId = DateTime.now().microsecondsSinceEpoch;
      final tmpPath = '$cachePath.$uniqueId.tmp';
      
      final uriStr = container.uri.toString();

      if (!_ensuredThumbDirs.containsKey(uriStr)) {
        _ensuredThumbDirs[uriStr] = vaultExplorerApi.createDirectory(container, inContainerDir);
      }
      await _ensuredThumbDirs[uriStr];
      
      final ok = await vaultExplorerApi.writeFileChunk(container, tmpPath, 0, payload);
      // finishWriteIfCryptomator() is a documented no-op for every format
      // except Cryptomator (which needs it to flush the buffered final
      // chunk) — skip the round trip for gocryptfs/VeraCrypt/LUKS, which is
      // the common case, instead of paying for a call that just no-ops.
      if (container.containerFormat == 'cryptomator') {
        await vaultExplorerApi.finishWriteIfCryptomator(container, tmpPath);
      }

      if (ok) {
        // You may still need to delete the target file here depending on whether 
        // vaultExplorerApi.renameFile supports overwriting existing files.
        await vaultExplorerApi.deleteFile(container, cachePath);
        await vaultExplorerApi.renameFile(container, tmpPath, cachePath);
      } else {
        await vaultExplorerApi.deleteFile(container, tmpPath);
        debugPrint(
          'ThumbnailCacheService.put: inContainer write failed',
        );
      }
    }
  } catch (e, stackTrace) {
    debugPrint('ThumbnailCacheService.put: $e\n$stackTrace');
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

  static Future<void> clearAppCacheFor(MountedContainer container) async {
    _ensuredThumbDirs.remove(container.uri.toString());
    try {
      final dirPath = await _thumbDir(container);
      _ensuredThumbDirs.remove(dirPath);
      final dir = Directory(dirPath);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    // Scoped to this container's volId prefix (see _memKey) rather than a
    // blanket clear — this now runs on every lock (F-16), and other
    // containers may still be mounted with warm, still-valid entries of
    // their own.
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

  static const int defaultMaxAppCacheBytes = 100 * 1024 * 1024;
  static int _putWriteCount = 0;

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
      debugPrint('ThumbnailCacheService.enforceDiskBudget: $e');
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
      final activeKeys = activeContainerUris.map(_encodeKey).toSet();
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

// ── compute() argument records ─────────────────────────────────────────────

class _DecryptArgs {
  final Uint8List raw;
  final Uint8List keyBytes;
  const _DecryptArgs({required this.raw, required this.keyBytes});
}

class _EncryptArgs {
  final Uint8List data;
  final Uint8List keyBytes;
  const _EncryptArgs({required this.data, required this.keyBytes});
}