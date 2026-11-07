import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/index/cover_overrides_codec.dart';
import 'package:vaultexplorer/features/library/index/library_index_codec.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';
import 'package:vaultexplorer/features/library/models/music_config.dart';

/// Where a container's music mode files live. The rule is the same one the
/// bookmarks use, for the same reason: titles and folder names are information
/// about private content, so they must not end up anywhere readable.
enum LibraryLocation {
  /// A writable vault keeps them in its own meta folder, encrypted by the
  /// vault, travelling with it. Only readable while it is unlocked.
  inVault,

  /// Phone and external storage are plain folders, and a read-only vault cannot
  /// be written to. Their files sit in the app's private storage, AES-GCM
  /// encrypted under the same Keystore-backed key as the thumbnail cache. No
  /// hidden folder is ever dropped into the person's own files.
  thisDevice,
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

  Future<Uint8List?> aesGcmEncrypt(Uint8List key, Uint8List iv, Uint8List plaintext);
  Future<Uint8List?> aesGcmDecrypt(Uint8List key, Uint8List iv, Uint8List ciphertextAndTag);

  /// A stable, filename-safe digest of [value].
  Future<String> digest(String value);

  Future<Uint8List?> readAppFile(String path);
  Future<bool> writeAppFile(String path, Uint8List bytes);
  Future<void> deleteAppFile(String path);

  /// Whether [path] exists in the container. Asked before reading so that
  /// "nothing saved yet" is not logged or treated as an error.
  Future<bool> containerFileExists(MountedContainer c, String path);
  Future<Uint8List?> readContainerFile(MountedContainer c, String path);

  /// Writes [path], creating the meta folder first.
  Future<bool> writeContainerFile(MountedContainer c, String path, Uint8List bytes);
  Future<void> deleteContainerFile(MountedContainer c, String path);
}

/// Saves and loads a container's music mode config and track index.
///
/// Nothing here writes plaintext metadata to unencrypted storage. Anything that
/// fails to decrypt or parse is treated as "nothing saved" so the caller just
/// rebuilds it; the index is only ever a cache of what is in the files.
class LibraryIndexStore {
  final LibraryStorePlatform platform;

  LibraryIndexStore(this.platform);

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

  String _vaultPath(String name) => '${platform.metaDir}/$name';

  Future<String> _devicePath(MountedContainer c, String ext) async {
    final root = await platform.appRoot();
    return '$root/library/${await platform.digest(c.uri)}.$ext';
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

  Future<bool> saveConfig(MountedContainer container, MusicConfig config) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(config.toJson())));
      return await _write(container, configName, 'cfg', bytes);
    } catch (_) {
      return false;
    }
  }

  // ── Index ────────────────────────────────────────────────────────────────

  Future<List<LibraryTrack>?> loadIndex(MountedContainer container) async {
    try {
      final blob = await _read(container, indexName, 'idx');
      if (blob == null || blob.isEmpty) return null;
      return await Isolate.run(() => LibraryIndexCodec.decode(blob));
    } catch (_) {
      return null;
    }
  }

  /// Returns whether the index was written.
  Future<bool> saveIndex(MountedContainer container, List<LibraryTrack> tracks) async {
    try {
      final blob = await Isolate.run(() => LibraryIndexCodec.encode(tracks));
      return await _write(container, indexName, 'idx', blob);
    } catch (_) {
      return false;
    }
  }

  /// Deletes the saved index (the config stays).
  Future<void> deleteIndex(MountedContainer container) async {
    try {
      switch (locationFor(container)) {
        case LibraryLocation.thisDevice:
          await platform.deleteAppFile(await _devicePath(container, 'idx'));
        case LibraryLocation.inVault:
          await platform.deleteContainerFile(container, _vaultPath(indexName));
      }
    } catch (_) {
      // Best effort: a failed delete leaves a stale index that the next save
      // overwrites.
    }
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
  Future<bool> saveCovers(MountedContainer container, Map<String, Uint8List> covers) async {
    try {
      if (covers.isEmpty) {
        switch (locationFor(container)) {
          case LibraryLocation.thisDevice:
            await platform.deleteAppFile(await _devicePath(container, 'cvr'));
          case LibraryLocation.inVault:
            await platform.deleteContainerFile(container, _vaultPath(coversName));
        }
        return true;
      }
      return await _write(container, coversName, 'cvr', CoverOverridesCodec.encode(covers));
    } catch (_) {
      return false;
    }
  }

  // ── Location-specific bytes ──────────────────────────────────────────────

  Future<Uint8List?> _read(MountedContainer c, String vaultName, String deviceExt) async {
    switch (locationFor(c)) {
      case LibraryLocation.inVault:
        final path = _vaultPath(vaultName);
        if (!await platform.containerFileExists(c, path)) return null;
        return platform.readContainerFile(c, path);
      case LibraryLocation.thisDevice:
        final raw = await platform.readAppFile(await _devicePath(c, deviceExt));
        if (raw == null) return null;
        return _decrypt(raw);
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
    }
  }

  Future<Uint8List?> _encrypt(Uint8List plain) async {
    final key = await platform.cacheKey();
    final rng = Random.secure();
    final iv = Uint8List.fromList(List.generate(_nonceSize, (_) => rng.nextInt(256)));
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
