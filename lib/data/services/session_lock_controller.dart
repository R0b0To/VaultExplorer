import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

part 'session_lock_controller.g.dart';

/// Was constructed directly by VaultDashboardState (with the 3 callbacks
/// passed to its constructor); a @riverpod keepAlive function provider
/// can't take widget-owned closures as construction params (they aren't
/// `==`-stable across rebuilds, which breaks Riverpod's caching), so the
/// callbacks are now supplied once via [configure] from the owning
/// screen's `initState` instead. Everything else -- the timer/lifecycle
/// logic itself -- is unchanged from the pre-Riverpod version.
@Riverpod(keepAlive: true)
SessionLockController sessionLockController(Ref ref) {
  final controller = SessionLockController();
  ref.onDispose(controller.dispose);
  return controller;
}

class SessionLockController {
  AppSettings Function()? _settings;
  Future<void> Function()? _lockAllMountedContainers;
  VoidCallback? _enforceAppLock;
  DateTime Function() _now = DateTime.now;

  Timer? _autoLockTimer;
  DateTime? _pausedAt;

  /// Must be called once (from the owning screen's `initState`) before any
  /// other method is used -- mirrors the parameters the old constructor
  /// took.
  void configure({
    required AppSettings Function() settings,
    required Future<void> Function() lockAllMountedContainers,
    required VoidCallback enforceAppLock,
    DateTime Function()? now,
  }) {
    _settings = settings;
    _lockAllMountedContainers = lockAllMountedContainers;
    _enforceAppLock = enforceAppLock;
    if (now != null) _now = now;
  }

  bool get _hasMasterPassword {
    final s = _settings!();
    return s.useMasterPassword && s.masterPasswordHash != null;
  }

  void dispose() {
    _autoLockTimer?.cancel();
  }

  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      final mins = _settings!().autoLockMins;
      final wasAwayTooLong = pausedAt != null &&
          mins > 0 &&
          _now().difference(pausedAt) >= Duration(minutes: mins);
      if (wasAwayTooLong) {
        performAutoLock();
      } else {
        scheduleAutoLock();
      }
    } else if (state == AppLifecycleState.paused) {
      _pausedAt = _now();
    }
  }

  void handleScreenOff() {
    final s = _settings!();
    if (s.lockContainersOnScreenLock) {
      performAutoLock();
    }
  }

  void scheduleAutoLock() {
    _autoLockTimer?.cancel();
    final s = _settings!();
    final mins = s.autoLockMins;
    if (mins <= 0 || (!_hasMasterPassword && !s.lockContainersOnScreenLock)) {
      return;
    }
    _autoLockTimer = Timer(Duration(minutes: mins), performAutoLock);
  }

  Future<void> performAutoLock() async {
    _autoLockTimer?.cancel();
    final s = _settings!();
    if (s.lockContainersOnScreenLock || _hasMasterPassword) {
      _enforceAppLock!();
    }
    if (s.lockContainersOnScreenLock) {
      await _lockAllMountedContainers!();
    }
  }
}
