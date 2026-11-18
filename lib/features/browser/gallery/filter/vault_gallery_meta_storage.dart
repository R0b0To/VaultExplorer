import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

import 'gallery_meta_log_storage.dart';

/// Keeps a vault's gallery index in `/.vaultexplorer`, inside the encrypted
/// vault next to its other per-vault files (see `VaultMediaIndexStorage`):
/// encrypted with the vault, carried with it, and readable only while it is
/// unlocked. Read-only vaults get nothing written.
///
/// Phone storage and other plain locations keep theirs next to the thumbnails
/// in the hidden `.thumbcache` folder, and only when the owner chose that
/// folder as the thumbnail cache ([keepInHiddenFolder]): the same opt-in that
/// already lets thumbnails be written there, so no folder is dropped into
/// storage that did not ask for one. Clearing that thumbnail cache removes the
/// index with it.
///
/// The index is a log of small files (see [GalleryMetaLogStorage]): appending
/// a batch of photos writes one of them instead of rewriting the whole index,
/// which used to take longer with every photo of the library.
class VaultGalleryMetaStorage extends GalleryMetaLogStorage {
  VaultGalleryMetaStorage(
    VaultFileIoApi io,
    MountedContainer? Function(int volId) containerOf, {
    super.allowWrite,
    bool Function(int volId)? keepInHiddenFolder,
  }) : super((volId) {
         final c = containerOf(volId);
         if (c == null) return null;
         if (!c.isLocalStorage) return _VaultMetaFiles(io, c, kVaultMetaDir);
         // Plain storage is neither read nor written unless it opted in.
         return (keepInHiddenFolder?.call(volId) ?? false)
             ? _VaultMetaFiles(io, c, localDir)
             : null;
       });

  /// Where plain storage keeps the index: the folder of its thumbnails.
  static const String localDir = ThumbnailCacheService.inContainerDir;

  /// The base file's name, and where it lives in a vault.
  static const String fileName = GalleryMetaSegmentNames.base;
  static const String filePath = '$kVaultMetaDir/$fileName';
}

class _VaultMetaFiles implements GalleryMetaFiles {
  _VaultMetaFiles(this._io, this._container, this._dir);

  final VaultFileIoApi _io;
  final MountedContainer _container;

  /// The hidden folder the files live in.
  final String _dir;

  @override
  bool get readOnly => _container.readOnly;

  String _path(String name) => '$_dir/$name';

  @override
  Future<List<String>?> listNames() async {
    final raw = await _io.listDirectory(_container, _dir);
    if (raw == null) return null;
    return [
      for (final e in RawEntry.parseAll(raw))
        if (!e.isDir) e.name,
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
