part of 'vault_explorer_api.dart';

/// Open/share methods for real, already-decrypted files on device storage.
///
/// Unlike [_FileIoOps]'s vault-container methods, these never decrypt
/// anything -- they hand a plain absolute file path to the native side,
/// which exposes it via a standard androidx `FileProvider`
/// (`LocalFileHandlers.kt`) rather than the vault's `ContainerDocumentsProvider`.
/// Used exclusively by the decoy's local storage explorer.
mixin _LocalShareOps {
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
      _logSwallowed('openLocalFileWithApp', e);
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
      _logSwallowed('shareLocalFile', e);
      return false;
    }
  }
}
