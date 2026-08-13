import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

class SecureScreenPolicy {
  SecureScreenPolicy._();

  static bool anyContainerMounted = false;

  /// Call whenever [anyContainerMounted] changes, or the person's own
  /// `blockScreenshots` [preference] changes (settings load or toggle).
  ///
  /// These two are deliberately protected in different ways:
  ///
  /// - FLAG_SECURE (`setSecureScreen`) follows [preference] alone, full
  ///   stop. It blocks screenshots outright - including the person's own,
  ///   live, intentional ones - so it must never be forced on just
  ///   because a container happens to be mounted, or "block screenshots:
  ///   off" would stop meaning what it says. (Native still also forces it
  ///   on while the app is genuinely backgrounded, in `onPause` - that's
  ///   fine, since a live screenshot is impossible then anyway.)
  /// - The Recents/task-snapshot bitmap (`setRecentsSnapshotBlocked`,
  ///   backed by Android 13+'s `Activity.setRecentsScreenshotEnabled`) is
  ///   a narrower, separate control: it only affects the cached bitmap
  ///   the OS shows in the app switcher and, on some OEM skins, reuses
  ///   for the keyguard-dismiss/unlock transition animation - it has no
  ///   effect on the person's own screenshot button. That one *is* tied
  ///   to [anyContainerMounted] proactively, for as long as anything
  ///   sensitive could be on screen, because unlike FLAG_SECURE there's
  ///   no live-screenshot trade-off that turns "set it early" into a
  ///   problem.
  static Future<void> apply({required bool preference}) {
    return Future.wait([
      vaultExplorerApi.setSecureScreen(preference),
      vaultExplorerApi.setRecentsSnapshotBlocked(anyContainerMounted),
    ]);
  }
}