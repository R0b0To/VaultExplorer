import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/features/library/index/cover_overrides_codec.dart';
import 'package:vaultexplorer/features/library/index/library_index_codec.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';
import 'package:vaultexplorer/features/library/models/music_config.dart';

/// Where a container's music mode config and custom covers live. The music
/// index has its own setting and can be disabled independently.
enum LibraryLocation {
  /// A writable vault keeps them in its own meta folder, encrypted by the
  /// vault, travelling with it. Only readable while it is unlocked.
  inVault,

  /// The default for plain storage and read-only vaults. Files sit in the app's
  /// private storage, AES-GCM encrypted under the same Keystore-backed key as
  /// the thumbnail cache.
  thisDevice,

  /// Local Storage's explicitly selected hidden folder. This is not encrypted.
  hiddenFolder,

  /// The saved music index is disabled; only the in-memory scan is kept.
  disabled,

  /// The user selected container storage, but this container cannot be written.
  readOnly,
}

/// The platform pieces the store needs, so its decisions (which location,
/// what happens on damage) can be tested without a device.
abstract class LibraryStorePlatform {
  /// The meta folder inside a vault (`.vaultexplorer`).
  String get metaDir;

  /// Private app directory that holds `library/` (device location).
  Future<String> appRoot();

  /// The persistent app-cache AES-256 key.
  Future<Uint8List> cacheKey();

  Future<Uint8List?> aesGcmEncrypt(
    Uint8List key,
    Uint8List iv,
    Uint8List plaintext,
  );
  Future<Uint8List?> aesGcmDecrypt(
    Uint8List key,
    Uint8List iv,
    Uint8List ciphertextAndTag,
  );

  /// A stable, filename-safe digest of [value].
  Future<String> digest(String value);

  Future<Uint8List?> readAppFile(String path);
  Future<bool> writeAppFile(String path, Uint8List bytes);
  Future<void> deleteAppFile(String path);

  /// Whether [path] exists in the container. Asked before reading so that
  /// "nothing saved yet" is not logged or treated as an error.
  Future<bool> containerFileExists(MountedContainer c, String path);
  Future<Uint8List?> readContainerFile(MountedContainer c, String path);

  /// Writes [path], creating its parent folder first.
  Future<bool> writeContainerFile(
    MountedContainer c,
    String path,
    Uint8List bytes,
  );
  Future<void> deleteContainerFile(MountedContainer c, String path);
}

/// Saves and loads a container's music mode config, track index and covers.
///
/// App-storage files are encrypted. A Local Storage hidden-folder index is
/// plaintext only when the user explicitly selects that location. Anything
/// that fails to decrypt or parse is treated as "nothing saved" so the caller
/// rebuilds it; the index is only ever a cache of what is in the files.
class LibraryIndexStore {
  final LibraryStorePlatform platform;
  final Future<ThumbnailCacheMode> Function(MountedContainer container)?
  musicIndexCacheModeFor;
  final Map<String, ThumbnailCacheMode> _resolvedIndexModes = {};

  LibraryIndexStore(this.platform, {this.musicIndexCacheModeFor});

  static const String configName = 'music.json';
  static const String indexName = 'music-index.bin';
  static const String coversName = 'music-covers.bin';
  static const int _nonceSize = 12;
  static const int _tagSize = 16;

  static LibraryLocation locationFor(MountedContainer container) {
    if (container.isLocalStorage || container.readOnly) {
      return LibraryLocation.thisDevice;
    }
    return LibraryLocation.inVault;
  }

  /// The effective saved-index location, after applying the user's choice.
  /// Until the first index operation resolves settings, this reports the
  /// existing behavior for that container type.
  LibraryLocation indexLocationFor(MountedContainer container) {
    final mode =
        _resolvedIndexModes[container.uri] ??
        (container.isLocalStorage || container.readOnly
            ? ThumbnailCacheMode.appCache
            : ThumbnailCacheMode.inContainer);
    return switch (mode) {
      ThumbnailCacheMode.disabled => LibraryLocation.disabled,
      ThumbnailCacheMode.appCache => LibraryLocation.thisDevice,
      ThumbnailCacheMode.inContainer when container.readOnly =>
        LibraryLocation.readOnly,
      ThumbnailCacheMode.inContainer when container.isLocalStorage =>
        LibraryLocation.hiddenFolder,
      ThumbnailCacheMode.inContainer => LibraryLocation.inVault,
    };
  }

  Future<ThumbnailCacheMode> _indexCacheMode(MountedContainer container) async {
    final mode =
        await musicIndexCacheModeFor?.call(container) ??
        (container.isLocalStorage || container.readOnly
            ? ThumbnailCacheMode.appCache
            : ThumbnailCacheMode.inContainer);
    _resolvedIndexModes[container.uri] = mode;
    return mode;
  }

  String _vaultPath(String name) => '${platform.metaDir}/$name';

  static const String localIndexPath = '.musicindex/music-index.bin';

  Future<String> _devicePath(MountedContainer c, String ext) async {
    return _devicePathForUri(c.uri, ext);
  }

  Future<String> _devicePathForUri(String uri, String ext) async {
    final root = await platform.appRoot();
    return '$root/library/${await platform.digest(uri)}.$ext';
  }

  Future<Uint8List?> _readIndex(
    MountedContainer container,
    ThumbnailCacheMode mode,
  ) async {
    if (mode == ThumbnailCacheMode.disabled) return null;
    if (mode == ThumbnailCacheMode.appCache) {
      final raw = await platform.readAppFile(
        await _devicePath(container, 'idx'),
      );
      if (raw == null) return null;
      return _decrypt(raw);
    }

    final path = container.isLocalStorage
        ? localIndexPath
        : _vaultPath(indexName);
    if (!await platform.containerFileExists(container, path)) return null;
    return platform.readContainerFile(container, path);
  }

  Future<bool> _writeIndex(
    MountedContainer container,
    ThumbnailCacheMode mode,
    Uint8List bytes,
  ) async {
    if (mode == ThumbnailCacheMode.disabled) return true;
    if (mode == ThumbnailCacheMode.appCache) {
      final sealed = await _encrypt(bytes);
      if (sealed == null) return false;
      return platform.writeAppFile(await _devicePath(container, 'idx'), sealed);
    }

    // Respect an explicit in-container choice. A read-only vault may still
    // supply its existing index, but must not silently write a device copy.
    if (container.readOnly) return false;

    final path = container.isLocalStorage
        ? localIndexPath
        : _vaultPath(indexName);
    return platform.writeContainerFile(container, path, bytes);
  }

  // ── Config ───────────────────────────────────────────────────────────────

  /// The saved config, or [MusicConfig.off] when there is none (or it is
  /// unreadable: music mode simply starts off again).
  Future<MusicConfig> loadConfig(MountedContainer container) async {
    try {
      final bytes = await _read(container, configName, 'cfg');
      if (bytes == null) return MusicConfig.off;
      return MusicConfig.fromJson(jsonDecode(utf8.decode(bytes)));
    } catch (_) {
      return MusicConfig.off;
    }
  }

  Future<bool> saveConfig(
    MountedContainer container,
    MusicConfig config,
  ) async {
    try {
      final bytes = Uint8List.fromList(
        utf8.encode(jsonEncode(config.toJson())),
      );
      return await _write(container, configName, 'cfg', bytes);
    } catch (_) {
      return false;
    }
  }

  // ── Index ────────────────────────────────────────────────────────────────

  Future<List<LibraryTrack>?> loadIndex(MountedContainer container) async {
    try {
      final mode = await _indexCacheMode(container);
      final blob = await _readIndex(container, mode);
      if (blob == null || blob.isEmpty) return null;
      return await Isolate.run(() => LibraryIndexCodec.decode(blob));
    } catch (_) {
      return null;
    }
  }

  /// Returns whether the index was written.
  Future<bool> saveIndex(
    MountedContainer container,
    List<LibraryTrack> tracks,
  ) async {
    try {
      final mode = await _indexCacheMode(container);
      if (mode == ThumbnailCacheMode.disabled) return true;
      final blob = await Isolate.run(() => LibraryIndexCodec.encode(tracks));
      return await _writeIndex(container, mode, blob);
    } catch (_) {
      return false;
    }
  }

  /// Deletes the saved index (the config stays).
  Future<void> deleteIndex(MountedContainer container) async {
    await deleteIndexCopies(container.uri, container: container);
  }

  /// Deletes app-storage and any in-container copies. The app-storage copy can
  /// be cleared while the container is locked; an in-container copy needs a
  /// mounted, writable container.
  Future<({bool appStorageCleared, bool containerStorageCleared})>
  deleteIndexCopies(String uri, {MountedContainer? container}) async {
    var appStorageCleared = false;
    try {
      await platform.deleteAppFile(await _devicePathForUri(uri, 'idx'));
      appStorageCleared = true;
    } catch (_) {
      // Best effort; the inside-container copy may still be removable.
    }
    var containerStorageCleared = false;
    if (container != null && !container.readOnly) {
      final containerPath = container.isLocalStorage
          ? localIndexPath
          : _vaultPath(indexName);
      try {
        if (await platform.containerFileExists(container, containerPath)) {
          await platform.deleteContainerFile(container, containerPath);
        }
        containerStorageCleared = true;
      } catch (_) {
        // Best effort: a failed delete leaves only an unused stale cache.
      }
    }
    return (
      appStorageCleared: appStorageCleared,
      containerStorageCleared: containerStorageCleared,
    );
  }

  // ── Covers chosen by hand ────────────────────────────────────────────────

  /// The covers a person set for albums and artists in this container (key ->
  /// image bytes), empty when there are none or the file is unreadable.
  Future<Map<String, Uint8List>> loadCovers(MountedContainer container) async {
    try {
      final blob = await _read(container, coversName, 'cvr');
      if (blob == null || blob.isEmpty) return {};
      return CoverOverridesCodec.decode(blob);
    } catch (_) {
      return {};
    }
  }

  /// Saves the full set of custom covers (an empty map removes the file).
  Future<bool> saveCovers(
    MountedContainer container,
    Map<String, Uint8List> covers,
  ) async {
    try {
      if (covers.isEmpty) {
        switch (locationFor(container)) {
          case LibraryLocation.thisDevice:
            await platform.deleteAppFile(await _devicePath(container, 'cvr'));
          case LibraryLocation.inVault:
            await platform.deleteContainerFile(
              container,
              _vaultPath(coversName),
            );
          case LibraryLocation.hiddenFolder:
          case LibraryLocation.disabled:
          case LibraryLocation.readOnly:
            break;
        }
        return true;
      }
      return await _write(
        container,
        coversName,
        'cvr',
        CoverOverridesCodec.encode(covers),
      );
    } catch (_) {
      return false;
    }
  }

  // ── Location-specific bytes ──────────────────────────────────────────────

  Future<Uint8List?> _read(
    MountedContainer c,
    String vaultName,
    String deviceExt,
  ) async {
    switch (locationFor(c)) {
      case LibraryLocation.inVault:
        final path = _vaultPath(vaultName);
        if (!await platform.containerFileExists(c, path)) return null;
        return platform.readContainerFile(c, path);
      case LibraryLocation.thisDevice:
        final raw = await platform.readAppFile(await _devicePath(c, deviceExt));
        if (raw == null) return null;
        return _decrypt(raw);
      case LibraryLocation.hiddenFolder:
      case LibraryLocation.disabled:
      case LibraryLocation.readOnly:
        return null;
    }
  }

  Future<bool> _write(
    MountedContainer c,
    String vaultName,
    String deviceExt,
    Uint8List bytes,
  ) async {
    switch (locationFor(c)) {
      case LibraryLocation.inVault:
        return platform.writeContainerFile(c, _vaultPath(vaultName), bytes);
      case LibraryLocation.thisDevice:
        final sealed = await _encrypt(bytes);
        if (sealed == null) return false;
        return platform.writeAppFile(await _devicePath(c, deviceExt), sealed);
      case LibraryLocation.hiddenFolder:
      case LibraryLocation.disabled:
      case LibraryLocation.readOnly:
        return false;
    }
  }

  Future<Uint8List?> _encrypt(Uint8List plain) async {
    final key = await platform.cacheKey();
    final rng = Random.secure();
    final iv = Uint8List.fromList(
      List.generate(_nonceSize, (_) => rng.nextInt(256)),
    );
    final sealed = await platform.aesGcmEncrypt(key, iv, plain);
    if (sealed == null) return null;
    return Uint8List.fromList([...iv, ...sealed]);
  }

  Future<Uint8List?> _decrypt(Uint8List raw) async {
    if (raw.length <= _nonceSize + _tagSize) return null;
    final key = await platform.cacheKey();
    return platform.aesGcmDecrypt(
      key,
      Uint8List.sublistView(raw, 0, _nonceSize),
      Uint8List.sublistView(raw, _nonceSize),
    );
  }
}
