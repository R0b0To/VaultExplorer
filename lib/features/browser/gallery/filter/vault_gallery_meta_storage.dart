import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

import 'gallery_meta_log_storage.dart';

/// Keeps a vault's gallery index in its encrypted meta folder. Local storage
/// uses the selected thumbnail-cache location: encrypted app storage for
/// app-cache mode, or the .thumbcache hidden folder for in-container mode.
/// Disabled caching has no persistent gallery metadata store.
class VaultGalleryMetaStorage extends GalleryMetaLogStorage {
  VaultGalleryMetaStorage(
    VaultFileIoApi io,
    MountedContainer? Function(int volId) containerOf, {
    super.allowWrite,
    ThumbnailCacheMode Function(int volId)? localCacheMode,
    GalleryMetaFiles? Function(MountedContainer container)? appFilesOf,
  }) : super((volId) {
         final container = containerOf(volId);
         if (container == null) return null;
         if (!container.isLocalStorage) {
           return _VaultMetaFiles(io, container, kVaultMetaDir);
         }

         return switch (localCacheMode?.call(volId)) {
           ThumbnailCacheMode.appCache => appFilesOf?.call(container),
           ThumbnailCacheMode.inContainer => _VaultMetaFiles(
             io,
             container,
             localDir,
           ),
           ThumbnailCacheMode.disabled || null => null,
         };
       });

  /// Where plain storage keeps the index when hidden-folder mode is chosen.
  static const String localDir = ThumbnailCacheService.inContainerDir;

  /// The base file's name, and where it lives in a vault.
  static const String fileName = GalleryMetaSegmentNames.base;
  static const String filePath = '$kVaultMetaDir/$fileName';
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
    if (raw == null) return null;
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
