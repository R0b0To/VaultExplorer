import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

/// Tells the app's [SessionLockController] how to read the lock settings, what
/// to lock, and what [enforceAppLock] does when the app lock is due.
///
/// `MainShell` calls this when the vault shell comes up. While the main window
/// is closed and file manager windows keep the app running, `DesktopSessionKeeper`
/// calls it too, with its own [enforceAppLock]; the rest is the same either way,
/// which is why it lives here and not in either of them.
///
/// Everything goes through [container] and not a widget's `ref`, so the
/// callbacks stay safe after the widget that set them up is gone.
///
/// [settings] defaults to the live app settings. The decoy file manager passes
/// its own, with the app-password gate switched off.
void configureSessionLock(
  ProviderContainer container, {
  required void Function() enforceAppLock,
  AppSettings Function()? settings,
}) {
  container
      .read(sessionLockControllerProvider)
      .configure(
        settings:
            settings ??
            () => container.read(appSettingsControllerProvider).settings,
        lockAllMountedContainers: () => container
            .read(vaultDashboardControllerProvider.notifier)
            .lockAllMountedContainersForAutoLock(),
        // Containers set to "Immediately", locked on real background/screen-off
        // events independently of the app-wide sweep (see SessionLockController).
        lockImmediateOverrideContainers: () => container
            .read(vaultDashboardControllerProvider.notifier)
            .lockImmediatelyConfiguredContainers(),
        // Containers set to "Screen Lock Only"; SessionLockController only
        // calls this from handleScreenOff, never for mere backgrounding.
        lockScreenLockOnlyContainers: () => container
            .read(vaultDashboardControllerProvider.notifier)
            .lockScreenLockOnlyConfiguredContainers(),
        enforceAppLock: enforceAppLock,
      );
}
