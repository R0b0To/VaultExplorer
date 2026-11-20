import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

import 'app_gallery_meta_files.dart';
import 'gallery_meta_log_storage.dart';

/// Keeps the gallery index in its independent storage location. Vaults use
/// their encrypted metadata folder, while Local Storage uses a dedicated app
/// storage directory or hidden folder.
class VaultGalleryMetaStorage extends GalleryMetaLogStorage {
  VaultGalleryMetaStorage(
    VaultFileIoApi io,
    MountedContainer? Function(int volId) containerOf, {
    super.allowWrite,
    ThumbnailCacheMode Function(int volId)? metadataCacheMode,
    GalleryMetaFiles? Function(MountedContainer container)? appFilesOf,
  }) : super((volId) {
         final container = containerOf(volId);
         if (container == null) return null;
         return switch (metadataCacheMode?.call(volId)) {
           ThumbnailCacheMode.appCache => appFilesOf?.call(container),
           ThumbnailCacheMode.inContainer => _VaultMetaFiles(
             io,
             container,
             container.isLocalStorage ? localDir : kVaultMetaDir,
           ),
           ThumbnailCacheMode.disabled || null => null,
         };
       });

  /// Local Storage keeps its index in a dedicated hidden folder.
  static const String localDir = '.gallerymeta';

  /// The base file's name, and where it lives in a vault.
  static const String fileName = GalleryMetaSegmentNames.base;
  static const String filePath = '$kVaultMetaDir/$fileName';

  /// Clears both possible persisted copies. The app-storage copy can be
  /// removed while the vault is locked; an in-vault/hidden-folder copy needs a
  /// mounted, writable container.
  static Future<({bool appStorageCleared, bool containerStorageCleared})>
  clearPersistedIndexCopies({
    required String uri,
    required VaultCryptoApi crypto,
    required VaultFileIoApi io,
    MountedContainer? container,
  }) async {
    final appStorageCleared = await AppGalleryMetaFiles.forUri(
      uri: uri,
      crypto: crypto,
    ).clearSegments();

    var containerStorageCleared = false;
    if (container != null) {
      final storage = VaultGalleryMetaStorage(
        io,
        (_) => container,
        metadataCacheMode: (_) => ThumbnailCacheMode.inContainer,
      );
      containerStorageCleared = await storage.clearStoredIndex(container.volId);
    }
    return (
      appStorageCleared: appStorageCleared,
      containerStorageCleared: containerStorageCleared,
    );
  }
}

class _VaultMetaFiles implements GalleryMetaFiles {
  _VaultMetaFiles(this._io, this._container, this._dir);

  final VaultFileIoApi _io;
  final MountedContainer _container;

  /// The folder the files live in.
  final String _dir;

  @override
  bool get readOnly => _container.readOnly;

  String _path(String name) => '$_dir/$name';

  @override
  Future<List<String>?> listNames() async {
    final raw = await _io.listDirectory(_container, _dir);
    if (raw == null) {
      final slash = _dir.lastIndexOf('/');
      final parentPath = slash < 0 ? '' : _dir.substring(0, slash);
      final dirName = slash < 0 ? _dir : _dir.substring(slash + 1);
      final parent = await _io.listDirectory(_container, parentPath);
      if (parent == null) return null;
      final exists = RawEntry.parseAll(
        parent,
      ).any((entry) => entry.isDir && entry.name == dirName);
      return exists ? null : const [];
    }
    return [
      for (final entry in RawEntry.parseAll(raw))
        if (!entry.isDir) entry.name,
    ];
  }

  @override
  Future<Uint8List?> read(String name) =>
      _io.readWholeFile(_container, _path(name));

  @override
  Future<bool> write(String name, Uint8List bytes) async {
    await _io.createDirectory(_container, _dir);
    return _io.writeWholeFile(_container, _path(name), bytes);
  }

  @override
  Future<bool> delete(String name) => _io.deleteFile(_container, _path(name));
}
