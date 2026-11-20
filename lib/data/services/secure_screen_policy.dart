import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

part 'secure_screen_policy.g.dart';

@Riverpod(keepAlive: true)
SecureScreenPolicy secureScreenPolicy(Ref ref) =>
    SecureScreenPolicy(ref.watch(vaultFileIoApiProvider));

class SecureScreenPolicy {
  final VaultFileIoApi _fileIoApi;

  SecureScreenPolicy(this._fileIoApi);

  /// True while the real vault is on screen because it was revealed from
  /// Mask Mode. The persisted disguise mode stays `decoy` for that whole time
  /// (it is what makes the app return to the decoy on background), so callers
  /// that gate on "mode == decoy" -- the dashboard's `_syncSecureScreen`,
  /// `MainShell._enforceAppLock`, ... -- must not clear FLAG_SECURE while the
  /// vault is visible. [disableForDecoy] honours this.
  bool _vaultRevealed = false;
  bool get isVaultRevealed => _vaultRevealed;

  /// Call when the vault shell is revealed from the decoy.
  void beginRevealedVault() => _vaultRevealed = true;

  /// Call when the revealed vault shell is gone; drops protections again so
  /// the decoy behaves like a normal zip app.
  Future<void> endRevealedVault() {
    _vaultRevealed = false;
    return disableForDecoy();
  }

  /// Applies the user's global security preference in the real Vault app.
  Future<void> apply({required bool preference}) {
    return Future.wait([
      _fileIoApi.setSecureScreen(preference),
      _fileIoApi.setRecentsSnapshotBlocked(preference),
    ]);
  }

  /// Forces all screen and task-switcher protections off so Decoy Mode behaves like a normal zip app.
  ///
  /// A no-op while the real vault is revealed from Mask Mode (see
  /// [beginRevealedVault]); use [endRevealedVault] to leave that state.
  Future<void> disableForDecoy() {
    if (_vaultRevealed) return Future.value();
    return Future.wait([
      _fileIoApi.setSecureScreen(false),
      _fileIoApi.setRecentsSnapshotBlocked(false),
    ]);
  }
}
