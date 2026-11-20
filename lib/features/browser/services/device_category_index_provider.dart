import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/services/app_cache_encryption.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/browser/services/category_media_index_api.dart';
import 'package:vaultexplorer/features/browser/services/device_category_index.dart';
import 'package:vaultexplorer/features/browser/services/device_category_index_store.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

const _gcmNonceSize = 12;
const _gcmTagSize = 16;

/// The app-wide [DeviceCategoryIndex]: one instance for the life of the app,
/// so what a category scan of phone storage found is still there when a view
/// is closed and opened again (gallery mode, a category tab, the drawer).
///
/// Its results are written, encrypted with the same key as the thumbnail
/// cache, under the app's private support folder; wiping that key makes them
/// unreadable.
final deviceCategoryIndexProvider = Provider<DeviceCategoryIndex>((ref) {
  final channel = ref.watch(vaultEngineChannelProvider);
  final crypto = ref.watch(vaultCryptoApiProvider);
  return DeviceCategoryIndex(
    // The platform's file index is Android's MediaStore.
    media: Platform.isAndroid
        ? CategoryMediaIndexApi(
            (method, arguments) =>
                channel.invokeMethod<Object?>(method, arguments),
          )
        : null,
    store: DeviceCategoryIndexStore(
      directory: () async => Directory(
        '${(await getApplicationSupportDirectory()).path}/device_category_index',
      ),
      encrypt: (data) => _seal(crypto, data),
      decrypt: (data) => _open(crypto, data),
    ),
  );
});

/// The file extensions (lower-case, no dot) that make a name belong to
/// [category]: what the platform's file index is asked for. They come from the
/// same sets `matchesFilter` uses, so the index and the category agree.
List<String> categoryFileExtensions(FileCategory category) =>
    switch (category) {
      FileCategory.images => MediaViewerConstants.imageExtensions,
      FileCategory.videos => MediaViewerConstants.videoExtensions,
      FileCategory.audio => MediaViewerConstants.audioExtensions,
      FileCategory.documents => kBrowserFilterDocumentExtensions.toList(
        growable: false,
      ),
      FileCategory.gallery => [
        ...MediaViewerConstants.imageExtensions,
        ...MediaViewerConstants.videoExtensions,
      ],
    };

/// AES-256-GCM with a fresh random nonce, laid out as nonce + ciphertext + tag
/// (the thumbnail cache's layout).
Future<Uint8List?> _seal(VaultCryptoApi crypto, Uint8List data) async {
  final key = await AppCacheEncryption.getEncryptionKey();
  final random = Random.secure();
  final iv = Uint8List(_gcmNonceSize);
  for (var i = 0; i < iv.length; i++) {
    iv[i] = random.nextInt(256);
  }
  final sealed = await crypto.aesGcmEncrypt(key: key, iv: iv, plaintext: data);
  if (sealed == null) return null;
  final out = Uint8List(_gcmNonceSize + sealed.length)
    ..setRange(0, _gcmNonceSize, iv)
    ..setRange(_gcmNonceSize, _gcmNonceSize + sealed.length, sealed);
  return out;
}

Future<Uint8List?> _open(VaultCryptoApi crypto, Uint8List raw) async {
  if (raw.length <= _gcmNonceSize + _gcmTagSize) return null;
  try {
    final key = await AppCacheEncryption.getEncryptionKey();
    return await crypto.aesGcmDecrypt(
      key: key,
      iv: raw.sublist(0, _gcmNonceSize),
      ciphertextAndTag: raw.sublist(_gcmNonceSize),
    );
  } catch (_) {
    // A file written under a key that no longer exists: unreadable, which the
    // store treats as "nothing stored".
    return null;
  }
}
