import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

class SecureScreenPolicy {
  SecureScreenPolicy._();

  static bool anyContainerMounted = false;

  /// Call whenever [anyContainerMounted] changes, or the person's own
  /// `blockScreenshots` [preference] changes (settings load or toggle).
  static Future<void> apply({required bool preference}) {
    return vaultExplorerApi.setSecureScreen(anyContainerMounted || preference);
  }
}
