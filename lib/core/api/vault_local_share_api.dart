// Extracted from vault_explorer_api_local_share.dart (old _LocalShareOps
// mixin) as part of the Riverpod migration, Phase 2.
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

import 'vault_engine_types.dart';

/// Open/share methods for real, already-decrypted files on device storage.
///
/// Unlike [_FileIoOps]'s vault-container methods, these never decrypt
/// anything -- they hand a plain absolute file path to the native side,
/// which exposes it via a standard androidx `FileProvider`
/// (`LocalFileHandlers.kt`) rather than the vault's `ContainerDocumentsProvider`.
/// Used exclusively by the decoy's local storage explorer.

class VaultLocalShareApi {
  final MethodChannel _channel;
  const VaultLocalShareApi(this._channel);

  /// Opens [filePath] with whichever app the user picks from the system
  /// chooser. [mimeType] overrides the extension-based guess when the
  /// caller already knows it.
  Future<bool> openLocalFileWithApp(String filePath, {String? mimeType}) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        ChannelMethods.openLocalFileWithApp,
        {
          'filePath': filePath,
          if (mimeType != null) 'mimeType': mimeType,
        },
      );
      return ok ?? false;
    } catch (e) {
      logSwallowed('openLocalFileWithApp', e);
      return false;
    }
  }

  /// Shares one or more real files via the system share sheet.
  Future<bool> shareLocalFiles(List<String> filePaths) async {
    if (filePaths.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        ChannelMethods.shareLocalFile,
        {'filePaths': filePaths},
      );
      return ok ?? false;
    } catch (e) {
      logSwallowed('shareLocalFile', e);
      return false;
    }
  }

  /// Returns the FileProvider content URI (content://...localfiles/...) for a real on-disk file.
  Future<String?> getLocalFileUri(String filePath) async {
    try {
      final uri = await _channel.invokeMethod<String>(
        ChannelMethods.getLocalFileUri,
        {'filePath': filePath},
      );
      return uri;
    } catch (e) {
      logSwallowed('getLocalFileUri', e);
      return null;
    }
  }
}
