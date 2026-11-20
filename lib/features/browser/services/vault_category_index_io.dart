import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/services/vault_category_index_store.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

/// [CategoryIndexStorage] over one unlocked vault's file API.
class _VaultIndexStorage implements CategoryIndexStorage {
  _VaultIndexStorage(this._io, this._vault);

  final VaultFileIoApi _io;
  final MountedContainer _vault;

  @override
  Future<bool> fileExists(String dir, String name) async {
    final raw = await _io.listDirectory(_vault, dir);
    if (raw == null) return false;
    return RawEntry.parseAll(raw).any((e) => !e.isDir && e.name == name);
  }

  @override
  Future<Uint8List?> read(String path) => _io.readWholeFile(_vault, path);

  @override
  Future<bool> write(String dir, String path, Uint8List bytes) async {
    if (_vault.readOnly) return false;
    // Fails harmlessly if the folder already exists.
    await _io.createDirectory(_vault, dir);
    return _io.writeWholeFile(_vault, path, bytes);
  }

  @override
  Future<bool> delete(String path) async {
    if (_vault.readOnly) return false;
    return _io.deleteFile(_vault, path);
  }
}

/// The category-index store of [container], or null when it cannot hold one.
///
/// Only vaults do. Phone storage and storage locations are the person's own
/// folders; the app does not drop a hidden file into them.
VaultCategoryIndexStore? categoryIndexStoreFor(
  VaultFileIoApi io,
  MountedContainer container,
) {
  if (container.isLocalStorage) return null;
  return VaultCategoryIndexStore(
    _VaultIndexStorage(io, container),
    metaDir: kVaultMetaDir,
  );
}
