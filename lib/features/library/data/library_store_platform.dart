import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_cache_encryption.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

/// [LibraryStorePlatform] backed by the real engine APIs, the app-private
/// directory and the encrypted-cache key shared with the thumbnail cache.
class VaultLibraryStorePlatform implements LibraryStorePlatform {
  final VaultFileIoApi _fileIo;
  final VaultCryptoApi _crypto;
  final VaultHashApi _hash;

  VaultLibraryStorePlatform({
    required this._fileIo,
    required this._crypto,
    required this._hash,
  });

  Future<String>? _root;

  @override
  String get metaDir => kVaultMetaDir;

  @override
  Future<String> appRoot() =>
      _root ??= getApplicationSupportDirectory().then((d) => d.path);

  @override
  Future<Uint8List> cacheKey() => AppCacheEncryption.getEncryptionKey();

  @override
  Future<Uint8List?> aesGcmEncrypt(
    Uint8List key,
    Uint8List iv,
    Uint8List plaintext,
  ) =>
      _crypto.aesGcmEncrypt(key: key, iv: iv, plaintext: plaintext);

  @override
  Future<Uint8List?> aesGcmDecrypt(
    Uint8List key,
    Uint8List iv,
    Uint8List ciphertextAndTag,
  ) =>
      _crypto.aesGcmDecrypt(key: key, iv: iv, ciphertextAndTag: ciphertextAndTag);

  @override
  Future<String> digest(String value) =>
      _hash.hashBytesMd5(Uint8List.fromList(utf8.encode(value)));

  @override
  Future<Uint8List?> readAppFile(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  @override
  Future<bool> writeAppFile(String path, Uint8List bytes) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    // Write beside the target and rename, so a crash mid-write cannot leave a
    // half-written index that later decrypts to garbage.
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
    return true;
  }

  @override
  Future<void> deleteAppFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<bool> containerFileExists(MountedContainer c, String path) async {
    // Ask the listing instead of probing the path: "missing" is normal and
    // should not look like a read error.
    final slash = path.lastIndexOf('/');
    final dir = slash < 0 ? '' : path.substring(0, slash);
    final name = slash < 0 ? path : path.substring(slash + 1);
    final raw = await _fileIo.listDirectory(c, dir, refresh: true);
    if (raw == null) return false;
    return RawEntry.parseAll(raw).any((e) => !e.isDir && e.name == name);
  }

  @override
  Future<Uint8List?> readContainerFile(MountedContainer c, String path) =>
      _fileIo.readWholeFile(c, path);

  @override
  Future<bool> writeContainerFile(
    MountedContainer c,
    String path,
    Uint8List bytes,
  ) async {
    // Returns false when the folder already exists; that is fine.
    await _fileIo.createDirectory(c, metaDir);
    return _fileIo.writeWholeFile(c, path, bytes);
  }

  @override
  Future<void> deleteContainerFile(MountedContainer c, String path) async {
    await _fileIo.deleteFile(c, path);
  }
}
