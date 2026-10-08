import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_channel.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/core/utils/byte_budget_cache.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/thumbnail_generation_strategy.dart';
import 'package:vaultexplorer/data/services/app_cache_encryption.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

import 'media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart'
    show logSwallowed;

part 'thumbnail_cache_service.g.dart';

@Riverpod(keepAlive: true)
ThumbnailCacheService thumbnailCacheService(Ref ref) =>
    const ThumbnailCacheService();

/// Three-tier thumbnail cache with immutable pack-file storage for in-container mode.
class ThumbnailCacheService {
  const ThumbnailCacheService();

  static VaultFileIoApi? _fileIoApi;
  static VaultCryptoApi? _cryptoApi;
  static VaultHashApi? _hashApi;

  static void configure({
    required VaultFileIoApi fileIoApi,
    required VaultCryptoApi cryptoApi,
    required VaultHashApi hashApi,
  }) {
    _fileIoApi = fileIoApi;
    _cryptoApi = cryptoApi;
    _hashApi = hashApi;
  }

  static VaultFileIoApi get _fileIo =>
      _fileIoApi ??
      (throw StateError(
        'ThumbnailCacheService must be configured during app startup.',
      ));

  static VaultCryptoApi get _crypto =>
      _cryptoApi ??
      (throw StateError(
        'ThumbnailCacheService must be configured during app startup.',
      ));

  static VaultHashApi get _hash =>
      _hashApi ??
      (throw StateError(
        'ThumbnailCacheService must be configured during app startup.',
      ));

  // ── Instance Method Forwarders ─────────────────────────────────────────────

  Uint8List? peekMemory(
    MountedContainer container,
    String filePath, [
    ThumbnailQuality quality = ThumbnailQuality.defaultQuality,
  ]) => getFromMemory(container, filePath, quality);

  void cacheInMemory(
    MountedContainer container,
    String filePath,
    Uint8List data, [
    ThumbnailQuality quality = ThumbnailQuality.defaultQuality,
    int? width,
    int? height,
  ]) => putInMemory(container, filePath, data, quality, width, height);

  Future<Uint8List?> fetch({
    required MountedContainer container,
    required String filePath,
    required ThumbnailCacheMode mode,
    required ThumbnailQuality quality,
  }) => get(
    container: container,
    filePath: filePath,
    mode: mode,
    quality: quality,
  );

  Future<(Uint8List bytes, int? width, int? height)?> fetchWithSize({
    required MountedContainer container,
    required String filePath,
    required ThumbnailCacheMode mode,
    required ThumbnailQuality quality,
  }) => getWithSize(
    container: container,
    filePath: filePath,
    mode: mode,
    quality: quality,
  );

  (Uint8List bytes, int? width, int? height)? peekMemoryWithSize(
    MountedContainer container,
    String filePath, [
    ThumbnailQuality quality = ThumbnailQuality.defaultQuality,
  ]) => getWithSizeFromMemory(container, filePath, quality);

  Future<void> store({
    required MountedContainer container,
    required String filePath,
    required Uint8List data,
    required ThumbnailCacheMode mode,
    required ThumbnailQuality quality,
    int? width,
    int? height,
  }) => put(
    container: container,
    filePath: filePath,
    data: data,
    mode: mode,
    quality: quality,
    width: width,
    height: height,
  );

  Future<void> invalidate(
    MountedContainer container,
    String filePath, {
    List<ThumbnailQuality> qualities = const [ThumbnailQuality.defaultQuality],
  }) => invalidateFile(container, filePath, qualities: qualities);

  Future<void> clearAppCache(MountedContainer container) =>
      clearAppCacheFor(container);

  Future<void> clearAppCacheForUri(String uri) => clearAppCacheByUri(uri);

  Future<void> clearInContainerCacheForUri(String uri) =>
      clearInContainerCacheByUri(uri);

  static const _channel = kVaultEngineChannel;

  // ── Constants ──────────────────────────────────────────────────────────────
  static const inContainerDir = '.thumbcache';
  static const inContainerIndexFile = '.thumbcache/index.bin';
  static const _gcmNonceSize = 12;
  static const _gcmTagSize = 16;
  static const _inContainerReadCap = 8 * 1024 * 1024; // 8 MB

  // ── Tier 1: Static In-Memory Byte-Budgeted LRU ────────────────────────────
  static const int _memoryMaxBytes = 24 * 1024 * 1024;
  static final _memoryCache = ByteBudgetCache(_memoryMaxBytes);
  static final Map<String, String> _latestKeyByFile = {};
  static final Map<String, (int width, int height)> _sizeCache = {};

  static String _videoThumbnailVariant = 'hybrid-120';
  static final Set<String> _knownVideoThumbnailVariants = {
    for (final strategy in ThumbnailGenerationStrategy.values)
      for (var position = 50; position <= 900; position += 50)
        '${strategy.name}-$position',
    for (final strategy in ThumbnailGenerationStrategy.values)
      '${strategy.name}-120',
  };

  static String get videoThumbnailVariant => _videoThumbnailVariant;

  static ThumbnailGenerationStrategy _videoThumbnailStrategy =
      ThumbnailGenerationStrategy.hybrid;
  static double _videoThumbnailFramePosition = 0.12;

  static ThumbnailGenerationStrategy get videoThumbnailStrategy =>
      _videoThumbnailStrategy;
  static double get videoThumbnailFramePosition => _videoThumbnailFramePosition;

  static void setVideoThumbnailSettings(
    ThumbnailGenerationStrategy strategy,
    double framePosition,
  ) {
    _videoThumbnailStrategy = strategy;
    _videoThumbnailFramePosition = framePosition.clamp(0.05, 0.90).toDouble();
    _videoThumbnailVariant =
        '${strategy.name}-${(_videoThumbnailFramePosition * 1000).round()}';
    _knownVideoThumbnailVariants.add(_videoThumbnailVariant);
  }

  static String? _variantForPath(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    return const {
          'mp4',
          'm4v',
          'webm',
          'mov',
          'avi',
          'mkv',
          'mpeg',
          'mpg',
          'flv',
          'ts',
          'wmv',
          '3gp',
          'vob',
          'ogv',
          'divx',
          'f4v',
          'm2ts',
        }.contains(extension)
        ? 'video:$_videoThumbnailVariant'
        : null;
  }

  static String _filePrefix(MountedContainer container, String filePath) {
    final base =
        '${container.volId}:${container.mountedAt.millisecondsSinceEpoch}:$filePath|';
    final variant = _variantForPath(filePath);
    return variant == null ? base : '$base$variant|';
  }

  static String? _findResidentKeyForFile(
    MountedContainer container,
    String filePath,
  ) {
    final prefix = _filePrefix(container, filePath);
    final key = _latestKeyByFile[prefix];
    if (key == null) return null;
    if (_memoryCache.containsKey(key)) return key;
    _latestKeyByFile.remove(prefix);
    return null;
  }

  static void _pruneKeyIndex() {
    _latestKeyByFile.removeWhere((_, key) => !_memoryCache.containsKey(key));
  }

  static void resizeMemoryBudget(int newMaxBytes) =>
      _memoryCache.resize(newMaxBytes);

  static void trimMemoryToFraction(double fraction) =>
      _memoryCache.trimToFraction(fraction);

  // ── AES Key & Root Path Helpers ───────────────────────────────────────────
  static Future<Uint8List>? _keyFuture;
  static Future<Uint8List> getOrFetchKey() =>
      _keyFuture ??= AppCacheEncryption.getEncryptionKey();

  static Future<String>? _appCacheRootFuture;

  static Future<String> _getAppCacheRoot() {
    return _appCacheRootFuture ??= getApplicationSupportDirectory().then(
      (d) => d.path,
    );
  }

  static Future<String> _thumbDir(MountedContainer container) async {
    final root = await _getAppCacheRoot();
    final key = await _encodeKey(container.uri);
    return '$root/thumbs/$key';
  }

  static Future<String> _encodeKey(String value) {
    return _hash.hashBytesMd5(Uint8List.fromList(utf8.encode(value)));
  }

  static String _qualifiedPath(
    String filePath,
    ThumbnailQuality quality, {
    String? videoVariant,
  }) {
    final variant = videoVariant == null
        ? _variantForPath(filePath)
        : 'video:$videoVariant';
    return variant == null
        ? '$filePath|${quality.size}|${quality.quality}'
        : '$filePath|$variant|${quality.size}|${quality.quality}';
  }

  static String _memKey(
    MountedContainer container,
    String filePath,
    ThumbnailQuality quality,
  ) =>
      '${container.volId}:${container.mountedAt.millisecondsSinceEpoch}:'
      '${_qualifiedPath(filePath, quality)}';

  // ── AES-GCM Helpers ────────────────────────────────────────────────────────

  static Future<Uint8List?> _decrypt(Uint8List raw, Uint8List key) async {
    if (raw.length <= _gcmNonceSize + _gcmTagSize) return null;
    try {
      final iv = raw.sublist(0, _gcmNonceSize);
      final ciphertextAndTag = raw.sublist(_gcmNonceSize);
      return await _crypto.aesGcmDecrypt(
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
    final encryptedAndTag = await _crypto.aesGcmEncrypt(
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

  // ── Tier 1: Memory Helpers ────────────────────────────────────────────────

  static Uint8List? getFromMemory(
    MountedContainer container,
    String filePath, [
    ThumbnailQuality quality = ThumbnailQuality.defaultQuality,
  ]) {
    final key = _memKey(container, filePath, quality);
    final stored = _memoryCache[key];
    if (stored != null) {
      if (_looksLikeValidImage(stored)) return stored;
      _memoryCache.remove(key);
    }

    final matchedKey = _findResidentKeyForFile(container, filePath);
    if (matchedKey != null) {
      final alt = _memoryCache[matchedKey];
      if (alt != null) {
        if (_looksLikeValidImage(alt)) return alt;
        _memoryCache.remove(matchedKey);
      }
    }
    return null;
  }

  static (Uint8List bytes, int? width, int? height)? getWithSizeFromMemory(
    MountedContainer container,
    String filePath, [
    ThumbnailQuality quality = ThumbnailQuality.defaultQuality,
  ]) {
    final key = _memKey(container, filePath, quality);
    final stored = _memoryCache[key];
    if (stored != null) {
      if (_looksLikeValidImage(stored)) {
        final size = _sizeCache[key];
        return (stored, size?.$1, size?.$2);
      }
      _memoryCache.remove(key);
    }

    final matchedKey = _findResidentKeyForFile(container, filePath);
    if (matchedKey != null) {
      final alt = _memoryCache[matchedKey];
      if (alt != null) {
        if (_looksLikeValidImage(alt)) {
          final size = _sizeCache[matchedKey];
          return (alt, size?.$1, size?.$2);
        }
        _memoryCache.remove(matchedKey);
      }
    }
    return null;
  }

  static void putInMemory(
    MountedContainer container,
    String filePath,
    Uint8List data, [
    ThumbnailQuality quality = ThumbnailQuality.defaultQuality,
    int? width,
    int? height,
  ]) {
    if (!_looksLikeValidImage(data)) return;

    final key = _memKey(container, filePath, quality);
    _memoryCache[key] = data;
    _latestKeyByFile[_filePrefix(container, filePath)] = key;
    if (_latestKeyByFile.length > 2048 &&
        _latestKeyByFile.length > _memoryCache.length * 4) {
      _pruneKeyIndex();
    }

    if (width != null && height != null && width > 0 && height > 0) {
      _sizeCache[key] = (width, height);
      MediaAspectRatioCache.put(container, filePath, width, height);
    }
  }

  // ── Public: Read ──────────────────────────────────────────────────────────

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

  static Future<(Uint8List bytes, int? width, int? height)?> getWithSize({
    required MountedContainer container,
    required String filePath,
    required ThumbnailCacheMode mode,
    required ThumbnailQuality quality,
  }) async {
    if (mode == ThumbnailCacheMode.disabled) return null;

    // Tier 1: In-memory LRU
    final mem = getWithSizeFromMemory(container, filePath, quality);
    if (mem != null) return mem;

    try {
      if (mode == ThumbnailCacheMode.appCache) {
        final dir = await _thumbDir(container);
        final cacheKey = await _encodeKey(_qualifiedPath(filePath, quality));
        var file = File('$dir/$cacheKey');

        if (!await file.exists() && _variantForPath(filePath) == null) {
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
        if (!_looksLikeValidImage(bytes)) return null;

        final dims = _extractImageDimensions(bytes);
        final width = dims?.$1;
        final height = dims?.$2;

        putInMemory(container, filePath, bytes, quality, width, height);
        return (bytes, width, height);
      } else {
        // Mode: inContainer
        final keyHex = await _encodeKey(_qualifiedPath(filePath, quality));
        final queue = _getPackQueue(container);

        // 1. Anything queued for, or being written to, a pack right now.
        final pending = queue.getPending(keyHex);
        if (pending != null) {
          putInMemory(
            container,
            filePath,
            pending.data,
            quality,
            pending.width,
            pending.height,
          );
          return (pending.data, pending.width, pending.height);
        }

        // 2. The pack index. Null means "couldn't tell right now" (a transient
        //    read failure), which is a miss -- never an excuse to start over.
        final index = await queue.ensureIndex();
        if (index == null) return null;

        final entry = index.entries[keyHex];
        if (entry != null) {
          final chunk = await _fileIo.readFileChunk(
            container,
            '$inContainerDir/${_packFileName(entry.packId)}',
            entry.offset,
            entry.length,
          );
          if (chunk != null &&
              chunk.length == entry.length &&
              _looksLikeValidImage(chunk)) {
            putInMemory(
              container,
              filePath,
              chunk,
              quality,
              entry.width,
              entry.height,
            );
            return (chunk, entry.width, entry.height);
          }
        }

        // 3. Old one-file-per-thumbnail entry. The directory listing taken
        //    when the index loaded says exactly which ones exist, so a miss
        //    costs nothing -- no native read per tile.
        if (index.legacyFiles.containsKey(keyHex)) {
          final stored = await _fileIo.readFileChunk(
            container,
            '$inContainerDir/$keyHex',
            0,
            _inContainerReadCap,
          );
          if (stored != null &&
              stored.isNotEmpty &&
              _looksLikeValidImage(stored)) {
            final dims = _extractImageDimensions(stored);
            final width = dims?.$1;
            final height = dims?.$2;
            putInMemory(container, filePath, stored, quality, width, height);
            // Move it into a pack (which also deletes the loose file) the
            // first time it's used, so the loose files drain away over time.
            unawaited(
              queue.enqueue(
                _PendingPackThumb(
                  keyHex: keyHex,
                  data: stored,
                  width: width ?? 180,
                  height: height ?? 180,
                ),
                _fileIo,
              ),
            );
            return (stored, width, height);
          }
        }
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  // ── Public: Write ─────────────────────────────────────────────────────────

  static Future<void> put({
    required MountedContainer container,
    required String filePath,
    required Uint8List data,
    required ThumbnailCacheMode mode,
    required ThumbnailQuality quality,
    int? width,
    int? height,
  }) {
    if (mode == ThumbnailCacheMode.disabled || data.isEmpty) {
      return Future.value();
    }

    putInMemory(container, filePath, data, quality, width, height);

    if (!_looksLikeValidImage(data)) {
      return Future.value();
    }

    final dedupKey =
        '${mode.name}:${container.volId}:'
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
    try {
      if (mode == ThumbnailCacheMode.appCache) {
        final dirPath = await _thumbDir(container);

        if (!_ensuredThumbDirs.containsKey(dirPath)) {
          _ensuredThumbDirs[dirPath] = Directory(
            dirPath,
          ).create(recursive: true).then((_) {});
        }
        await _ensuredThumbDirs[dirPath];

        final cacheKey = await _encodeKey(_qualifiedPath(filePath, quality));
        final file = File('$dirPath/$cacheKey');
        final key = await getOrFetchKey();

        // Direct write to target file
        final encrypted = await _encrypt(data, key);
        await file.writeAsBytes(encrypted, flush: false);

        if (++_putWriteCount % 25 == 0) {
          unawaited(enforceDiskBudget());
        }
      } else {
        // Mode: inContainer
        final keyHex = await _encodeKey(_qualifiedPath(filePath, quality));
        // Pack index keys are 16-byte digests; anything else can't be indexed.
        if (!_cacheKeyRe.hasMatch(keyHex)) return;
        final resolvedDims =
            (width != null && height != null && width > 0 && height > 0)
            ? (width, height)
            : _extractImageDimensions(data) ?? (180, 180);

        final queue = _getPackQueue(container);
        await queue.enqueue(
          _PendingPackThumb(
            keyHex: keyHex,
            data: data,
            width: resolvedDims.$1,
            height: resolvedDims.$2,
          ),
          _fileIo,
        );

        if (++_inContainerPutWriteCount % 25 == 0) {
          unawaited(enforceInContainerDiskBudget(container));
        }
      }
    } catch (_) {
      // Disposable cache write failure; safe to ignore
    }
  }

  // ── In-Container Pack-File Architecture ────────────────────────────────────
  //
  // Thumbnails are batched into immutable `pack_<n>.bin` files plus one
  // `index.bin` mapping key -> (pack, offset, length, size). The rules that
  // keep a transient failure from costing the whole cache:
  //   * The index is only ever replaced after the pack it points at was
  //     written, and an index that couldn't be READ is never overwritten.
  //   * Every index mutation (flush, invalidate, eviction) runs one at a time
  //     through the container's queue, so two of them can't clobber each other.

  static const String _inContainerIndexName = 'index.bin';
  static final RegExp _packNameRe = RegExp(r'^pack_(\d+)\.bin$');
  static final RegExp _legacyNameRe = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _cacheKeyRe = RegExp(r'^[0-9a-f]{32}$');

  static final Map<String, _InContainerPackIndex> _inContainerIndices = {};
  static final Map<String, _InContainerPackQueue> _inContainerQueues = {};

  static String _packFileName(int id) =>
      'pack_${id.toString().padLeft(4, '0')}.bin';

  /// Numeric id of a pack file name, or null if [name] isn't one. Ids must be
  /// compared as numbers: as strings `pack_10000.bin` sorts before
  /// `pack_9999.bin`.
  static int? _packIdFromName(String name) {
    final m = _packNameRe.firstMatch(name);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static _InContainerPackQueue _getPackQueue(MountedContainer container) {
    return _inContainerQueues.putIfAbsent(
      container.uri.toString(),
      () => _InContainerPackQueue(container),
    );
  }

  /// Lists the cache directory. Null means the listing itself failed (as
  /// opposed to an empty or missing directory, which is an empty list).
  static Future<List<RawEntry>?> _listInContainerDir(
    MountedContainer container,
  ) async {
    try {
      final raw = await _fileIo.listDirectory(container, inContainerDir);
      if (raw == null) return const <RawEntry>[];
      final out = <RawEntry>[];
      for (final line in raw) {
        if (line.startsWith('System:')) continue;
        try {
          out.add(RawEntry.parse(line));
        } on FormatException {
          continue;
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Builds the in-memory index from what is on disk.
  ///
  /// Returns null when the on-disk state can't be determined right now (the
  /// listing failed, or `index.bin` exists but couldn't be read). Callers
  /// must then neither serve from, nor write over, the index: a transient
  /// failure used to be indistinguishable from "no index", and the next
  /// flush would replace a perfectly good index with an empty one, orphaning
  /// every pack.
  static Future<_InContainerPackIndex?> _loadInContainerIndex(
    MountedContainer container,
  ) async {
    final listing = await _listInContainerDir(container);
    if (listing == null) return null;

    var hasIndexFile = false;
    var maxPackId = -1;
    final packNames = <String>[];
    final legacy = <String, ({int size, int modifiedSecs})>{};
    for (final e in listing) {
      if (e.isDir) continue;
      if (e.name == _inContainerIndexName) {
        hasIndexFile = true;
        continue;
      }
      final id = _packIdFromName(e.name);
      if (id != null) {
        packNames.add(e.name);
        if (id > maxPackId) maxPackId = id;
        continue;
      }
      if (_legacyNameRe.hasMatch(e.name)) {
        legacy[e.name] = (size: e.sizeBytes, modifiedSecs: e.modifiedSecs);
      }
    }

    Uint8List? bytes;
    try {
      bytes = await _fileIo.readWholeFile(container, inContainerIndexFile);
    } catch (_) {
      bytes = null;
    }

    if (bytes == null) {
      // Listed but unreadable: unknown, so leave it alone.
      if (hasIndexFile) return null;
      // Genuinely no index yet (fresh cache, or its index never got written).
      // Any packs already present are unreachable but still occupy ids and
      // budget; start numbering past them and let eviction retire them.
      return _InContainerPackIndex(
        nextPackId: maxPackId + 1,
        entries: {},
        legacyFiles: legacy,
      );
    }

    final parsed = _parseIndex(bytes);
    if (parsed == null) {
      // Readable but not a valid index (corrupt, or the pre-release TPK1):
      // everything it described is unreachable, so reclaim the space.
      for (final name in packNames) {
        try {
          await _fileIo.deleteFile(container, '$inContainerDir/$name');
        } catch (e) {
          logSwallowed('_loadInContainerIndex', e, expected: true);
        }
      }
      return _InContainerPackIndex(
        nextPackId: maxPackId + 1,
        entries: {},
        legacyFiles: legacy,
      );
    }

    if (parsed.nextPackId <= maxPackId) parsed.nextPackId = maxPackId + 1;
    parsed.legacyFiles.addAll(legacy);
    return parsed;
  }

  // Index file layout (big-endian). Written as TPK3; TPK2 (16-bit pack ids)
  // is still read so an index from the previous build keeps working.
  //   header 16 B: magic(4) | version u16 | reserved u16 | nextPackId u32 |
  //                entryCount u32
  //   entry  32 B: key(16) | packId u32 | offset u32 | length u32 |
  //                width u16 | height u16
  static const int _indexHeaderSize = 16;
  static const int _indexEntrySize = 32;

  /// Null if [bytes] isn't a complete, well-formed index.
  static _InContainerPackIndex? _parseIndex(Uint8List bytes) {
    if (bytes.length < _indexHeaderSize) return null;
    final bd = ByteData.sublistView(bytes);
    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    final int nextPackId;
    final bool v3;
    if (magic == 'TPK3') {
      v3 = true;
      nextPackId = bd.getUint32(8);
    } else if (magic == 'TPK2') {
      v3 = false;
      nextPackId = bd.getUint16(6);
    } else {
      return null;
    }
    final count = bd.getUint32(12);
    if (bytes.length != _indexHeaderSize + count * _indexEntrySize) return null;

    final entries = <String, _PackEntry>{};
    var o = _indexHeaderSize;
    for (var i = 0; i < count; i++) {
      final key = _bytesToHex(Uint8List.sublistView(bytes, o, o + 16));
      if (v3) {
        entries[key] = _PackEntry(
          packId: bd.getUint32(o + 16),
          offset: bd.getUint32(o + 20),
          length: bd.getUint32(o + 24),
          width: bd.getUint16(o + 28),
          height: bd.getUint16(o + 30),
        );
      } else {
        entries[key] = _PackEntry(
          packId: bd.getUint16(o + 16),
          offset: bd.getUint32(o + 18),
          length: bd.getUint32(o + 22),
          width: bd.getUint16(o + 26),
          height: bd.getUint16(o + 28),
        );
      }
      o += _indexEntrySize;
    }
    return _InContainerPackIndex(
      nextPackId: nextPackId,
      entries: entries,
      legacyFiles: {},
    );
  }

  static Uint8List _serializeIndex(_InContainerPackIndex index) {
    final buffer = Uint8List(
      _indexHeaderSize + index.entries.length * _indexEntrySize,
    );
    final bd = ByteData.sublistView(buffer);

    buffer.setRange(0, 4, utf8.encode('TPK3'));
    bd.setUint16(4, 3); // version
    bd.setUint16(6, 0); // reserved
    bd.setUint32(8, index.nextPackId);
    bd.setUint32(12, index.entries.length);

    var o = _indexHeaderSize;
    for (final entry in index.entries.entries) {
      buffer.setRange(o, o + 16, _hexToBytes(entry.key));
      bd.setUint32(o + 16, entry.value.packId);
      bd.setUint32(o + 20, entry.value.offset);
      bd.setUint32(o + 24, entry.value.length);
      bd.setUint16(o + 28, _u16(entry.value.width));
      bd.setUint16(o + 30, _u16(entry.value.height));
      o += _indexEntrySize;
    }
    return buffer;
  }

  static int _u16(int v) => v < 0 ? 0 : (v > 0xFFFF ? 0xFFFF : v);

  static String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(16);
    for (var i = 0; i < 16 && i * 2 + 2 <= hex.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// Writes any thumbnails still buffered for [container] to its packs and
  /// completes only once they are on disk (or definitively failed). Waits for
  /// a flush that is already running instead of returning early.
  static Future<void> flushInContainerCache(MountedContainer container) =>
      flushInContainerCacheForUri(container.uri.toString());

  /// Same as [flushInContainerCache], by container URI. Used right before a
  /// container is locked, while it is still mounted. No-op (and never
  /// throws) when nothing is buffered.
  static Future<void> flushInContainerCacheForUri(String uri) async {
    final queue = _inContainerQueues[uri];
    if (queue == null) return;
    try {
      await queue.flushNow();
    } catch (e) {
      logSwallowed('flushInContainerCacheForUri', e, expected: true);
    }
  }

  /// Drops all in-container cache state held in memory. For tests.
  @visibleForTesting
  static void resetInContainerStateForTesting() {
    for (final q in _inContainerQueues.values) {
      q.dispose();
    }
    _inContainerQueues.clear();
    _inContainerIndices.clear();
    _ensuredThumbDirs.clear();
    _inFlightPuts.clear();
  }

  // ── Cache Invalidation & Management ────────────────────────────────────────

  static Duration inContainerDebounceDuration = const Duration(
    milliseconds: 2500,
  );

  /// Called on every container lock (F-16). Wipes the decrypted memory tier
  /// and releases this mount's in-container pack state, so the next unlock
  /// reads the index fresh from disk instead of trusting one that a sync may
  /// have replaced while the vault was locked.
  ///
  /// It also flushes whatever is still buffered, but by the time this runs
  /// the volume is usually already unmounted (it is driven by the
  /// container-locked event), so that flush can only succeed for locks that
  /// go through `VaultLifecycleApi.lockContainer`, which now flushes first via
  /// [flushInContainerCacheForUri]. A flush that fails here is detected and
  /// dropped, never half-applied.
  static Future<void> clearAppCacheFor(MountedContainer container) async {
    final uriStr = container.uri.toString();
    final queue = _inContainerQueues[uriStr];
    if (queue != null) {
      try {
        await queue.flushNow();
      } catch (e) {
        logSwallowed('clearAppCacheFor', e, expected: true);
      }
      _inContainerQueues.remove(uriStr)?.dispose();
      _inContainerIndices.remove(uriStr);
      _ensuredThumbDirs.remove(uriStr);
    }
    _memoryCache.removeWhere((key) => key.startsWith('${container.volId}:'));
    _latestKeyByFile.removeWhere(
      (prefix, _) => prefix.startsWith('${container.volId}:'),
    );
    _sizeCache.removeWhere((key, _) => key.startsWith('${container.volId}:'));
  }

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
    } catch (e) {
      logSwallowed('clearAppCacheByUri', e, expected: true);
    }
    _memoryCache.clear();
    _latestKeyByFile.clear();
    _sizeCache.clear();
  }

  static Future<void> clearInContainerCacheByUri(String uri) async {
    _ensuredThumbDirs.remove(uri);
    _inContainerIndices.remove(uri);
    final queue = _inContainerQueues.remove(uri);
    queue?.dispose();
    // A commit that is already running must finish before the files go, or
    // it would recreate them right after.
    if (queue != null) await queue.settle();
    try {
      final entries = await _channel.invokeMethod<List<Object?>>(
        ChannelMethods.listDirectory,
        {'filePath': uri, 'dirPath': inContainerDir},
      );
      if (entries != null) {
        final casted = entries.cast<String>();
        for (final raw in casted) {
          if (raw.startsWith('System:')) continue;
          final name = RawEntry.parse(raw).name;
          await _channel.invokeMethod<bool>(ChannelMethods.deleteFile, {
            'filePath': uri,
            'fileName': '$inContainerDir/$name',
          });
        }
      }
      await _channel.invokeMethod<bool>(ChannelMethods.deleteFile, {
        'filePath': uri,
        'fileName': inContainerDir,
      });
    } catch (_) {
      rethrow;
    }
  }

  static Future<void> clearAllAppCache() async {
    _ensuredThumbDirs.clear();
    try {
      final root = await _getAppCacheRoot();
      final dir = Directory('$root/thumbs');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      logSwallowed('clearAllAppCache', e, expected: true);
    }
    _memoryCache.clear();
    _latestKeyByFile.clear();
    _sizeCache.clear();
  }

  static Future<void> invalidateFile(
    MountedContainer container,
    String filePath, {
    List<ThumbnailQuality> qualities = const [ThumbnailQuality.defaultQuality],
  }) async {
    final prefix =
        '${container.volId}:${container.mountedAt.millisecondsSinceEpoch}:$filePath|';
    _memoryCache.removeWhere((key) => key.startsWith(prefix));
    _sizeCache.removeWhere((key, _) => key.startsWith(prefix));
    _latestKeyByFile.removeWhere((key, _) => key.startsWith(prefix));

    final inContainerKeys = <String>[];
    final videoVariants = _variantForPath(filePath) == null
        ? <String?>[null]
        : _knownVideoThumbnailVariants.toList();
    for (final quality in qualities) {
      for (final variant in videoVariants) {
        try {
          inContainerKeys.add(
            await _encodeKey(
              _qualifiedPath(filePath, quality, videoVariant: variant),
            ),
          );
        } catch (e) {
          logSwallowed('invalidateFile', e, expected: true);
        }
      }
    }

    // App-cache tier (best effort, like everything here).
    try {
      final dir = await _thumbDir(container);
      for (final quality in qualities) {
        for (final variant in videoVariants) {
          try {
            final cacheKey = await _encodeKey(
              _qualifiedPath(filePath, quality, videoVariant: variant),
            );
            final file = File('$dir/$cacheKey');
            if (await file.exists()) await file.delete();
            final metaFile = File('${file.path}.meta');
            if (await metaFile.exists()) await metaFile.delete();
          } catch (e) {
            logSwallowed('invalidateFile', e, expected: true);
          }
        }
      }
      // Remove legacy entries created before strategy-aware video keys.
      if (_variantForPath(filePath) != null) {
        final legacyKey = await _encodeKey(filePath);
        final legacyFile = File('$dir/$legacyKey');
        if (await legacyFile.exists()) await legacyFile.delete();
        final legacyMetaFile = File('${legacyFile.path}.meta');
        if (await legacyMetaFile.exists()) await legacyMetaFile.delete();
      }
    } catch (e) {
      logSwallowed('invalidateFile', e, expected: true);
    }

    // In-container tier, all qualities in one go (one index write). This also
    // drops copies still queued for a pack, and works even if the index
    // hasn't been loaded yet this session -- otherwise the stale pre-edit
    // thumbnail would stay on disk and come back after a restart.
    try {
      await _getPackQueue(container).invalidate(inContainerKeys);
    } catch (e) {
      VeLog.w('ThumbnailCacheService', 'in-container invalidate failed', e);
    }
  }

  // ── Budget Enforcement ─────────────────────────────────────────────────────

  static const int defaultMaxAppCacheBytes = 100 * 1024 * 1024;
  static int _putWriteCount = 0;

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
        } catch (e) {
          logSwallowed('enforceDiskBudget', e, expected: true);
        }
      }

      if (totalBytes <= maxBytes) return;

      final targetBytes = (maxBytes * 0.8).toInt();
      files.sort((a, b) => a.modified.compareTo(b.modified));

      for (final entry in files) {
        if (totalBytes <= targetBytes) break;
        try {
          await entry.file.delete();
          totalBytes -= entry.size;
        } catch (e) {
          logSwallowed('enforceDiskBudget', e, expected: true);
        }
      }
    } catch (e) {
      VeLog.e(
        'ThumbnailCacheService',
        'App-cache disk budget eviction failed',
        e,
      );
    }
  }

  static const int defaultMaxInContainerCacheBytes = 50 * 1024 * 1024;
  static int _inContainerPutWriteCount = 0;

  static Future<void> enforceInContainerDiskBudget(
    MountedContainer container, [
    int maxBytes = defaultMaxInContainerCacheBytes,
  ]) async {
    try {
      final queue = _getPackQueue(container);
      await queue.exclusive(
        () => _evictInContainer(container, queue, maxBytes),
      );
    } catch (e) {
      VeLog.e(
        'ThumbnailCacheService',
        'In-container disk budget eviction failed',
        e,
      );
    }
  }

  /// Runs inside the container queue's exclusive section. Leftover
  /// one-file-per-thumbnail files go first (oldest first); then packs, oldest
  /// first by NUMERIC id. Without the first step, a vault whose old loose
  /// files alone exceed the budget would have every pack deleted on each
  /// pass while the loose files stayed.
  static Future<void> _evictInContainer(
    MountedContainer container,
    _InContainerPackQueue queue,
    int maxBytes,
  ) async {
    final index = await queue.ensureIndex();
    if (index == null) return; // can't tell what is still referenced
    final listing = await _listInContainerDir(container);
    if (listing == null) return;

    var total = 0;
    final packs = <({int id, String name, int size})>[];
    final loose = <RawEntry>[];
    for (final e in listing) {
      if (e.isDir) continue;
      total += e.sizeBytes;
      final id = _packIdFromName(e.name);
      if (id != null) {
        packs.add((id: id, name: e.name, size: e.sizeBytes));
      } else if (_legacyNameRe.hasMatch(e.name)) {
        loose.add(e);
      }
    }
    if (total <= maxBytes) return;
    final target = (maxBytes * 0.8).toInt();

    loose.sort((a, b) => a.modifiedSecs.compareTo(b.modifiedSecs));
    for (final e in loose) {
      if (total <= target) return;
      if (await _fileIo.deleteFile(container, '$inContainerDir/${e.name}')) {
        total -= e.sizeBytes;
        index.legacyFiles.remove(e.name);
      }
    }

    packs.sort((a, b) => a.id.compareTo(b.id));
    final deletedIds = <int>{};
    for (final pack in packs) {
      if (total <= target) break;
      if (await _fileIo.deleteFile(container, '$inContainerDir/${pack.name}')) {
        total -= pack.size;
        deletedIds.add(pack.id);
      }
    }

    // Only touch index.bin if it referenced something that just went away
    // (or an earlier write of it failed); deleting unreferenced packs
    // needs no index write.
    if (deletedIds.isNotEmpty) {
      final before = index.entries.length;
      index.entries.removeWhere((_, e) => deletedIds.contains(e.packId));
      if (index.entries.length != before) index.dirty = true;
    }
    if (index.dirty && await queue.persist(index)) index.dirty = false;
  }

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
          _ensuredThumbDirs.removeWhere((key, _) => key.contains(dirName));
          await e.delete(recursive: true);
        }
      }
    } catch (e) {
      logSwallowed('pruneStaleAppCache', e, expected: true);
    }
  }

  // ── Dimension Parsers ──────────────────────────────────────────────────────

  static (int width, int height)? _extractImageDimensions(Uint8List bytes) {
    if (_isPng(bytes)) return _extractPngDimensions(bytes);
    if (_isWebp(bytes)) return _extractWebpDimensions(bytes);
    return _extractJpegDimensions(bytes);
  }

  static (int width, int height)? _extractPngDimensions(Uint8List bytes) {
    if (bytes.length < 24) return null;
    final width =
        (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final height =
        (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    if (width <= 0 || height <= 0) return null;
    return (width, height);
  }

  static (int width, int height)? _extractWebpDimensions(Uint8List bytes) {
    if (bytes.length < 30) return null;
    final fourCc = String.fromCharCodes(bytes.sublist(12, 16));
    switch (fourCc) {
      case 'VP8 ':
        final width = ((bytes[27] << 8) | bytes[26]) & 0x3FFF;
        final height = ((bytes[29] << 8) | bytes[28]) & 0x3FFF;
        return (width > 0 && height > 0) ? (width, height) : null;
      case 'VP8L':
        final bits =
            bytes[21] |
            (bytes[22] << 8) |
            (bytes[23] << 16) |
            (bytes[24] << 24);
        final width = (bits & 0x3FFF) + 1;
        final height = ((bits >> 14) & 0x3FFF) + 1;
        return (width, height);
      case 'VP8X':
        final width = ((bytes[24] << 16) | (bytes[25] << 8) | bytes[26]) + 1;
        final height = ((bytes[27] << 16) | (bytes[28] << 8) | bytes[29]) + 1;
        return (width, height);
      default:
        return null;
    }
  }

  static (int width, int height)? _extractJpegDimensions(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    var offset = 2;
    while (offset < bytes.length - 8) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      if (marker == 0xFF || marker == 0x00) {
        offset++;
        continue;
      }
      if (marker == 0xD8 ||
          marker == 0xD9 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        offset += 2;
        continue;
      }
      if ((marker >= 0xC0 && marker <= 0xC3) ||
          (marker >= 0xC5 && marker <= 0xC7) ||
          (marker >= 0xC9 && marker <= 0xCB) ||
          (marker >= 0xCD && marker <= 0xCF)) {
        if (offset + 8 < bytes.length) {
          final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
          final width = (bytes[offset + 7] << 8) | bytes[offset + 8];
          if (width > 0 && height > 0) return (width, height);
        }
        return null;
      }
      if (offset + 3 >= bytes.length) break;
      final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (length < 2) break;
      offset += 2 + length;
    }
    return null;
  }

  static bool _looksLikeValidImage(Uint8List bytes) {
    if (_isPng(bytes)) return _looksLikeValidPng(bytes);
    if (_isWebp(bytes)) return _looksLikeValidWebp(bytes);
    return _looksLikeValidJpeg(bytes);
  }

  static bool _looksLikeValidJpeg(Uint8List bytes) {
    if (bytes.length < 4) return false;
    if (bytes[0] != 0xFF || bytes[1] != 0xD8) return false;
    final len = bytes.length;
    return bytes[len - 2] == 0xFF && bytes[len - 1] == 0xD9;
  }

  static const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

  static bool _isPng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    for (var i = 0; i < _pngSignature.length; i++) {
      if (bytes[i] != _pngSignature[i]) return false;
    }
    return true;
  }

  static bool _looksLikeValidPng(Uint8List bytes) {
    if (bytes.length < 20) return false;
    final len = bytes.length;
    return bytes[len - 8] == 0x49 &&
        bytes[len - 7] == 0x45 &&
        bytes[len - 6] == 0x4E &&
        bytes[len - 5] == 0x44;
  }

  static bool _isWebp(Uint8List bytes) {
    if (bytes.length < 12) return false;
    return bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
  }

  static bool _looksLikeValidWebp(Uint8List bytes) {
    if (bytes.length < 16) return false;
    final riffLength =
        bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);
    if (riffLength <= 0) return false;
    return bytes.length >= riffLength + 8;
  }

  static final Map<String, Future<void>> _ensuredThumbDirs = {};
  static final Map<String, Future<void>> _inFlightPuts = {};
}

// ── In-Container Pack Models & Coalescing Queue ─────────────────────────────

class _PackEntry {
  final int packId;
  final int offset;
  final int length;
  final int width;
  final int height;

  const _PackEntry({
    required this.packId,
    required this.offset,
    required this.length,
    required this.width,
    required this.height,
  });
}

class _InContainerPackIndex {
  int nextPackId;
  final Map<String, _PackEntry> entries;

  /// Old one-file-per-thumbnail entries still on disk, by file name. Known
  /// from the one directory listing taken when the index loads, so a lookup
  /// for a key that isn't here never touches native code.
  final Map<String, ({int size, int modifiedSecs})> legacyFiles;

  /// True when the in-memory entries are ahead of `index.bin` (a write
  /// failed, or a deferred invalidation was applied); the next successful
  /// write clears it.
  bool dirty = false;

  _InContainerPackIndex({
    required this.nextPackId,
    required this.entries,
    required this.legacyFiles,
  });
}

class _PendingPackThumb {
  final String keyHex;
  final Uint8List data;
  final int width;
  final int height;
  Completer<void>? completer;

  _PendingPackThumb({
    required this.keyHex,
    required this.data,
    required this.width,
    required this.height,
  });
}

/// Per-container write buffer and the one place that mutates that container's
/// pack set and index. Everything that changes either (flush, invalidate,
/// eviction) goes through [exclusive], so two of them can never interleave
/// and overwrite each other's index.
class _InContainerPackQueue {
  final MountedContainer container;
  final Map<String, _PendingPackThumb> _pending = {};

  /// The batch currently being written, still readable so a lookup during the
  /// write doesn't miss.
  Map<String, _PendingPackThumb> _inFlight = const {};

  /// Invalidations requested while the index couldn't be loaded; applied the
  /// moment it can.
  final Set<String> _deferredInvalidations = {};

  Timer? _debounceTimer;
  Future<void> _tail = Future<void>.value();
  Future<_InContainerPackIndex?>? _loading;
  int _failedCommits = 0;
  DateTime? _pausedUntil;
  bool _disposed = false;

  static const int _maxPendingItems = 40;
  static const int _maxFailedCommits = 3;
  static const Duration _pauseAfterFailures = Duration(minutes: 1);

  _InContainerPackQueue(this.container);

  String get _uri => container.uri.toString();

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _dropPending();
  }

  /// Completes once everything queued on [exclusive] so far has finished.
  Future<void> settle() => _tail;

  _PendingPackThumb? getPending(String keyHex) =>
      _pending[keyHex] ?? _inFlight[keyHex];

  /// Runs [task] after every earlier exclusive task, one at a time.
  Future<T> exclusive<T>(Future<T> Function() task) {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    return previous.then((_) => task()).whenComplete(gate.complete);
  }

  // ── Index access ──────────────────────────────────────────────────────────

  /// The loaded index, loading it once per mount. Null means the on-disk
  /// state couldn't be determined right now; that result is not cached, so
  /// the next call retries.
  Future<_InContainerPackIndex?> ensureIndex() {
    final cached = ThumbnailCacheService._inContainerIndices[_uri];
    if (cached != null) return Future.value(cached);
    return _loading ??= _loadAndPublish().whenComplete(() => _loading = null);
  }

  Future<_InContainerPackIndex?> _loadAndPublish() async {
    final index = await ThumbnailCacheService._loadInContainerIndex(container);
    if (index == null || _disposed) return index;
    ThumbnailCacheService._inContainerIndices[_uri] = index;

    if (_deferredInvalidations.isNotEmpty) {
      var changed = false;
      for (final key in _deferredInvalidations) {
        if (index.entries.remove(key) != null) changed = true;
        index.legacyFiles.remove(key);
      }
      _deferredInvalidations.clear();
      if (changed) {
        index.dirty = true;
        unawaited(flushIndexIfDirty());
      }
    }
    return index;
  }

  Future<bool> persist(_InContainerPackIndex index) =>
      _writeIndex(index, ThumbnailCacheService._fileIo);

  Future<bool> _writeIndex(
    _InContainerPackIndex index,
    VaultFileIoApi io,
  ) async {
    try {
      return await io.writeWholeFile(
        container,
        ThumbnailCacheService.inContainerIndexFile,
        ThumbnailCacheService._serializeIndex(index),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> flushIndexIfDirty() => exclusive(() async {
    final index = ThumbnailCacheService._inContainerIndices[_uri];
    if (index == null || !index.dirty) return;
    if (await persist(index)) index.dirty = false;
  }).catchError((Object _) {});

  // ── Write path ────────────────────────────────────────────────────────────

  Future<void> enqueue(_PendingPackThumb thumb, VaultFileIoApi fileIo) {
    if (_disposed) return Future.value();
    final pausedUntil = _pausedUntil;
    if (pausedUntil != null) {
      if (DateTime.now().isBefore(pausedUntil)) return Future.value();
      _pausedUntil = null;
      _failedCommits = 0;
    }

    final completer = Completer<void>();
    thumb.completer = completer;
    final replaced = _pending[thumb.keyHex];
    if (replaced != null) _complete(replaced);
    _pending[thumb.keyHex] = thumb;

    _debounceTimer?.cancel();
    if (_pending.length >= _maxPendingItems) {
      unawaited(flushNow(fileIo));
    } else {
      _debounceTimer = Timer(
        ThumbnailCacheService.inContainerDebounceDuration,
        () => unawaited(flushNow(fileIo)),
      );
    }
    return completer.future;
  }

  /// Writes everything queued so far. If a flush is already running this
  /// waits for it (and then for whatever it left behind) instead of
  /// returning early. Never throws.
  Future<void> flushNow([VaultFileIoApi? fileIo]) {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    return exclusive(() => _drainLocked(fileIo)).catchError((Object _) {});
  }

  Future<void> _drainLocked(VaultFileIoApi? fileIoOverride) async {
    while (_pending.isNotEmpty) {
      final io = fileIoOverride ?? ThumbnailCacheService._fileIo;
      final batch = _pending.values.toList();
      _pending.clear();
      _inFlight = {for (final t in batch) t.keyHex: t};

      var ok = false;
      try {
        ok = await _commitBatch(batch, io);
      } catch (_) {
        ok = false;
      } finally {
        _inFlight = const {};
      }

      // Thumbnails are disposable: a failed batch is dropped, not retried and
      // not reported, but it is counted so a read-only or failing volume
      // doesn't get hammered forever.
      for (final item in batch) {
        _complete(item);
      }
      if (ok) {
        _failedCommits = 0;
      } else if (++_failedCommits >= _maxFailedCommits) {
        _pausedUntil = DateTime.now().add(_pauseAfterFailures);
        _dropPending();
        return;
      }
    }
  }

  /// Writes [batch] as one new pack and records it in the index.
  ///
  /// Order matters: the pack is written first, the index only after, and the
  /// in-memory index changes only once BOTH succeeded. A failure at any point
  /// leaves the index (on disk and in memory) exactly as it was, with at most
  /// an unreferenced pack that gets deleted or evicted later.
  Future<bool> _commitBatch(
    List<_PendingPackThumb> batch,
    VaultFileIoApi io,
  ) async {
    final index = await ensureIndex();
    if (index == null)
      return false; // unknown on-disk state: never write over it
    if (!await _ensureDir(io)) return false;

    final packId = index.nextPackId;
    final builder = BytesBuilder(copy: false);
    final fresh = <String, _PackEntry>{};
    var offset = 0;
    for (final item in batch) {
      builder.add(item.data);
      fresh[item.keyHex] = _PackEntry(
        packId: packId,
        offset: offset,
        length: item.data.length,
        width: ThumbnailCacheService._u16(item.width),
        height: ThumbnailCacheService._u16(item.height),
      );
      offset += item.data.length;
    }

    final dir = ThumbnailCacheService.inContainerDir;
    final packPath = '$dir/${ThumbnailCacheService._packFileName(packId)}';
    if (!await io.writeWholeFile(container, packPath, builder.takeBytes())) {
      return false;
    }

    final next = _InContainerPackIndex(
      nextPackId: packId + 1,
      entries: {...index.entries, ...fresh},
      legacyFiles: const {},
    );
    if (!await _writeIndex(next, io)) {
      try {
        await io.deleteFile(container, packPath);
      } catch (e) {
        logSwallowed('_commitBatch', e, expected: true);
      }
      return false;
    }

    index.entries.addAll(fresh);
    index.nextPackId = packId + 1;
    index.dirty = false;

    // Anything that now lives in a pack no longer needs its old loose file.
    for (final item in batch) {
      if (index.legacyFiles.remove(item.keyHex) != null) {
        try {
          await io.deleteFile(container, '$dir/${item.keyHex}');
        } catch (e) {
          logSwallowed('_commitBatch', e, expected: true);
        }
      }
    }
    return true;
  }

  Future<bool> _ensureDir(VaultFileIoApi io) async {
    final dirs = ThumbnailCacheService._ensuredThumbDirs;
    var pending = dirs[_uri];
    pending ??= dirs[_uri] = io
        .createDirectory(container, ThumbnailCacheService.inContainerDir)
        .then((_) {});
    try {
      await pending;
      return true;
    } catch (_) {
      dirs.remove(_uri); // don't cache a failure
      return false;
    }
  }

  // ── Invalidation ──────────────────────────────────────────────────────────

  /// Makes every key in [keys] a miss, durably.
  Future<void> invalidate(List<String> keys) {
    if (keys.isEmpty) return Future.value();

    // Queued copies go first and synchronously, so a flush that starts while
    // we wait can't write them out after the file changed.
    for (final key in keys) {
      final queued = _pending.remove(key);
      if (queued != null) _complete(queued);
    }

    return exclusive(() async {
      final index = await ensureIndex();
      if (index == null) {
        // Can't edit what we can't read; apply it as soon as we can.
        _deferredInvalidations.addAll(keys);
        return;
      }

      final io = ThumbnailCacheService._fileIo;
      var changed = false;
      for (final key in keys) {
        if (index.entries.remove(key) != null) changed = true;
        if (index.legacyFiles.remove(key) != null) {
          try {
            await io.deleteFile(
              container,
              '${ThumbnailCacheService.inContainerDir}/$key',
            );
          } catch (e) {
            logSwallowed('invalidate', e, expected: true);
          }
        }
      }
      if (!changed && !index.dirty) return;
      index.dirty = !await persist(index);
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static void _complete(_PendingPackThumb thumb) {
    final c = thumb.completer;
    if (c != null && !c.isCompleted) c.complete();
  }

  void _dropPending() {
    for (final item in _pending.values) {
      _complete(item);
    }
    _pending.clear();
  }
}
