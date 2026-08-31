import 'package:vaultexplorer/core/api/vault_file_io_api.dart';

class SecureScreenPolicy {
  final VaultFileIoApi _fileIoApi;

  bool anyContainerMounted = false;

  SecureScreenPolicy(this._fileIoApi);

  /// Applies the user's security preference when inside the real Vault app.
  Future<void> apply({required bool preference}) {
    return Future.wait([
      _fileIoApi.setSecureScreen(preference),
      _fileIoApi.setRecentsSnapshotBlocked(anyContainerMounted),
    ]);
  }

  /// Forces all screen and task-switcher protections off so Decoy Mode behaves like a normal zip app.
  Future<void> disableForDecoy() {
    return Future.wait([
      _fileIoApi.setSecureScreen(false),
      _fileIoApi.setRecentsSnapshotBlocked(false),
    ]);
  }
}
