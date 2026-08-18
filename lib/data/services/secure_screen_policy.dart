import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

class SecureScreenPolicy {
  SecureScreenPolicy._();
  static bool anyContainerMounted = false;

  /// Applies the user's security preference when inside the real Vault app.
  static Future<void> apply({required bool preference}) {
    return Future.wait([
      vaultExplorerApi.setSecureScreen(preference),
      vaultExplorerApi.setRecentsSnapshotBlocked(anyContainerMounted),
    ]);
  }

  /// Forces all screen and task-switcher protections off so Decoy Mode behaves like a normal zip app.
  static Future<void> disableForDecoy() {
    return Future.wait([
      vaultExplorerApi.setSecureScreen(false),
      vaultExplorerApi.setRecentsSnapshotBlocked(false),
    ]);
  }
}