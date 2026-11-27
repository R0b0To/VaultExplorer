import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vaultexplorer/app/session_lock_wiring.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/windowing/app_windows.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/browser/file_manager_environment.dart';
import 'package:vaultexplorer/features/browser/file_manager_window.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

/// Keeps the app running correctly when the main window is closed while file
/// manager windows stay open (Linux and Windows).
///
/// `MainShell` is more than a page. While it is on screen it is also what
/// answers the file manager windows' questions (`FileManagerEnvironment`),
/// what hands app lifecycle changes to the auto-lock, and what carries out the
/// app lock. All of that goes with it when its window closes, and the file
/// manager windows would be left with empty answers and no auto-lock, which for
/// a vault app is the one thing that must not happen.
///
/// So when the shell goes away and independent windows remain, this takes over
/// the same three jobs, from the app's providers and not from widget state:
///
/// * it answers the file manager windows' environment,
/// * it forwards lifecycle changes to the [SessionLockController], and
/// * it carries out the app lock, which means closing every window and
///   bringing the main window back, because the lock gate is drawn there.
///
/// It lets go again when that lock happens: the main window that comes back is
/// a new one, and its `MainShell` wires everything up itself once the person
/// has unlocked.
class DesktopSessionKeeper with WidgetsBindingObserver {
  DesktopSessionKeeper._();

  static final DesktopSessionKeeper instance = DesktopSessionKeeper._();

  ProviderContainer? _container;
  MountedContainer? _localStorage;
  bool _enforcing = false;

  /// Whether the keeper is doing the shell's jobs right now.
  bool get isActive => _container != null;

  /// Called by `MainShell` as it goes away. Takes over only if it is the main
  /// window being closed (and not, say, the app locking, where the shell is
  /// replaced by the lock gate in a main window that stays open) and a window
  /// that can stand on its own is still open.
  ///
  /// [localStorage] is the device-storage container the shell was showing; it
  /// has no source other than the shell, so the keeper keeps the last one.
  void takeOverIfNeeded({
    required ProviderContainer container,
    required MountedContainer? localStorage,
  }) {
    if (isActive) return;
    // Cheapest first: off desktop there are no windows, and nothing else runs.
    if (!SecondaryWindows.instance.hasIndependentWindows) return;
    if (AppWindows.instance.isMainWindowOpen) return;

    _container = container;
    _localStorage = localStorage;
    FileManagerEnvironment.instance.attach(
      resolveContainer: _resolveContainer,
      mountedContainers: () =>
          container.read(vaultDashboardControllerProvider).mounted,
      primaryLocalContainer: () => _localStorage,
      openWindow: (target, initialPath) =>
          openFileManagerWindow(container: target, initialPath: initialPath),
      openVaultsWindow: (title) => openFileManagerWindow(title: title),
      openTabWindow: openFileManagerWindowForTab,
    );
    WidgetsBinding.instance.addObserver(this);
    configureSessionLock(container, enforceAppLock: _enforceAppLock);
  }

  /// Stops doing the shell's jobs.
  void release() {
    if (_container == null) return;
    FileManagerEnvironment.instance.detach();
    WidgetsBinding.instance.removeObserver(this);
    _container = null;
    _localStorage = null;
  }

  // The sources the shell used, minus its widget state: mounted vaults and
  // external storage come from providers, device storage from the snapshot.
  MountedContainer? _resolveContainer(int volId) {
    final container = _container;
    if (container == null) return null;
    for (final c in container.read(vaultDashboardControllerProvider).mounted) {
      if (c.volId == volId) return c;
    }
    if (volId <= kExternalStorageBaseVolId) {
      final external = container
          .read(externalStorageLocationsProvider.notifier)
          .resolveContainer(volId);
      if (external != null) return external;
    }
    final local = _localStorage;
    return local?.volId == volId ? local : null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final container = _container;
    if (container == null) return;
    // As in MainShell: background/resume locking is driven from one place for
    // the whole app, whichever window the person is in.
    container
        .read(sessionLockControllerProvider)
        .handleAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      container
          .read(externalStorageLocationsProvider.notifier)
          .refreshSystemVolumes();
    }
  }

  // The shell's version (MainShell._enforceAppLock) pops its own navigator to
  // the lock gate. There is no shell here: closing the windows and bringing the
  // main window back is the whole job, since a new main window starts at the
  // lock gate (or goes straight to the vaults when no master lock is set).
  Future<void> _enforceAppLock() async {
    final container = _container;
    if (container == null || _enforcing) return;
    _enforcing = true;
    try {
      final settings = container.read(appSettingsControllerProvider).settings;
      // Closes the windows first: nothing from a vault may stay on screen.
      release();
      AppWindows.instance.lockRequested();
      // Background audio must not outlive the app lock.
      if (settings.masterLockActive) {
        unawaited(BackgroundPlaybackHost.instance.closeAndWait());
      }
    } finally {
      _enforcing = false;
    }
  }
}
