import 'dart:typed_data';

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

import 'media_index_service.dart';

/// Keeps a container's media index in `/.vaultexplorer/media_index.bin`, inside
/// the encrypted vault, the same place (and for the same reasons) as
/// `marks.json` (see `VaultMarksStore`).
class VaultMediaIndexStorage implements MediaIndexStorage {
  VaultMediaIndexStorage(this._io);

  static const String fileName = 'media_index.bin';
  static const String filePath = '$kVaultMetaDir/$fileName';

  final VaultFileIoApi _io;

  @override
  Future<Uint8List?> read(MountedContainer container) async {
    // Ask the directory listing instead of trusting getFileSize on a path that
    // may not exist: "missing" is normal, "unreadable" is not.
    final raw = await _io.listDirectory(container, kVaultMetaDir);
    if (raw == null) return null;
    final exists = RawEntry.parseAll(
      raw,
    ).any((e) => !e.isDir && e.name == fileName);
    if (!exists) return null;
    final bytes = await _io.readWholeFile(container, filePath);
    if (bytes == null) {
      throw StateError('$filePath exists but could not be read');
    }
    return bytes;
  }

  @override
  Future<bool> write(MountedContainer container, Uint8List bytes) async {
    if (container.readOnly) return false;
    // Fails harmlessly if the folder already exists.
    await _io.createDirectory(container, kVaultMetaDir);
    return _io.writeWholeFile(container, filePath, bytes);
  }
}
