import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/utils/md5_hex.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_cache_encryption.dart';

import 'gallery_meta_log_storage.dart';

const _nonceSize = 12;
const _tagSize = 16;

/// Gallery metadata index segments in app storage.
///
/// Files live in a dedicated per-container directory, separate from
/// thumbnails. Each segment is encrypted with the app-cache key.
class AppGalleryMetaFiles implements GalleryMetaFiles {
  AppGalleryMetaFiles({
    required MountedContainer container,
    required VaultCryptoApi crypto,
  }) : this.forUri(uri: container.uri, crypto: crypto);

  AppGalleryMetaFiles.forUri({
    required String uri,
    required VaultCryptoApi crypto,
  }) : _uri = uri,
       _crypto = crypto;

  final String _uri;
  final VaultCryptoApi _crypto;
  Future<Directory>? _directory;

  Future<Directory> _getDirectory() => _directory ??= () async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/gallery_meta/${md5HexOfString(_uri)}');
  }();

  @override
  bool get readOnly => false;

  @override
  Future<List<String>?> listNames() async {
    try {
      final dir = await _getDirectory();
      if (!await dir.exists()) return const [];
      final names = <String>[];
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is File) {
          names.add(entry.path.split(Platform.pathSeparator).last);
        }
      }
      return names;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> read(String name) async {
    try {
      final file = File('${(await _getDirectory()).path}/$name');
      if (!await file.exists()) return null;
      final raw = await file.readAsBytes();
      if (raw.length <= _nonceSize + _tagSize) return null;
      final key = await AppCacheEncryption.getEncryptionKey();
      return await _crypto.aesGcmDecrypt(
        key: key,
        iv: Uint8List.sublistView(raw, 0, _nonceSize),
        ciphertextAndTag: Uint8List.sublistView(raw, _nonceSize),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> write(String name, Uint8List bytes) async {
    try {
      final key = await AppCacheEncryption.getEncryptionKey();
      final random = Random.secure();
      final iv = Uint8List.fromList(
        List<int>.generate(_nonceSize, (_) => random.nextInt(256)),
      );
      final sealed = await _crypto.aesGcmEncrypt(
        key: key,
        iv: iv,
        plaintext: bytes,
      );
      if (sealed == null) return false;

      final dir = await _getDirectory();
      await dir.create(recursive: true);
      final file = File('${dir.path}/$name');
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(
        Uint8List.fromList([...iv, ...sealed]),
        flush: true,
      );
      await temp.rename(file.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> delete(String name) async {
    try {
      final file = File('${(await _getDirectory()).path}/$name');
      if (!await file.exists()) return false;
      await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes every stored segment for this container.
  Future<bool> clearSegments() async {
    final names = await listNames();
    if (names == null) return false;
    var cleared = true;
    for (final name in names) {
      if (!GalleryMetaSegmentNames.isSegmentOrTemp(name)) continue;
      if (!await delete(name)) cleared = false;
    }
    return cleared;
  }
}
