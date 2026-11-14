import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

import 'gallery_meta_log_storage.dart';

/// Keeps a vault's gallery index in `/.vaultexplorer`, inside the encrypted
/// vault next to its other per-vault files (see `VaultMediaIndexStorage`):
/// encrypted with the vault, carried with it, and readable only while it is
/// unlocked. The phone's own storage and read-only vaults get nothing written.
///
/// The index is a log of small files (see [GalleryMetaLogStorage]): appending
/// a batch of photos writes one of them instead of rewriting the whole index,
/// which used to take longer with every photo of the library.
class VaultGalleryMetaStorage extends GalleryMetaLogStorage {
  VaultGalleryMetaStorage(
    VaultFileIoApi io,
    MountedContainer? Function(int volId) containerOf, {
    super.allowWrite,
  }) : super((volId) {
         final c = containerOf(volId);
         return c == null || c.isLocalStorage ? null : _VaultMetaFiles(io, c);
       });

  /// The base file's name, and where it lives in a vault.
  static const String fileName = GalleryMetaSegmentNames.base;
  static const String filePath = '$kVaultMetaDir/$fileName';
}

class _VaultMetaFiles implements GalleryMetaFiles {
  _VaultMetaFiles(this._io, this._container);

  final VaultFileIoApi _io;
  final MountedContainer _container;

  @override
  bool get readOnly => _container.readOnly;

  String _path(String name) => '$kVaultMetaDir/$name';

  @override
  Future<List<String>?> listNames() async {
    final raw = await _io.listDirectory(_container, kVaultMetaDir);
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
    await _io.createDirectory(_container, kVaultMetaDir);
    return _io.writeWholeFile(_container, _path(name), bytes);
  }

  @override
  Future<bool> delete(String name) => _io.deleteFile(_container, _path(name));
}
