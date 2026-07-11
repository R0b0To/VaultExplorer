import 'dart:async';
import 'package:flutter/widgets.dart';
import 'app_settings_service.dart';

/// Owns the "when should we auto-lock" policy that used to live directly on
/// [VaultDashboard]'s State: the auto-lock timer, the paused/resumed
/// lifecycle tracking, and the screen-off shortcut.
///
/// It knows nothing about `MountedContainer`, `vaultExplorerApi`, or
/// `Navigator` — it only decides *when* locking should happen and reports
/// that decision back through two injected callbacks. That keeps it free of
/// `BuildContext` and easy to unit test with fake settings + a couple of
/// completers, no widget tree required:
///
/// ```dart
/// final calls = <String>[];
/// final controller = SessionLockController(
///   settings: () => AppSettings(autoLockMins: 1, useMasterPassword: true, ...),
///   lockAllMountedContainers: () async => calls.add('locked'),
///   enforceAppLock: () => calls.add('enforced'),
/// );
/// controller.scheduleAutoLock();
/// // ...advance a fake clock / use fake_async and assert on `calls`.
/// ```
class SessionLockController {
  SessionLockController({
    required AppSettings Function() settings,
    required Future<void> Function() lockAllMountedContainers,
    required VoidCallback enforceAppLock,
  })  : _settings = settings,
        _lockAllMountedContainers = lockAllMountedContainers,
        _enforceAppLock = enforceAppLock;

  final AppSettings Function() _settings;
  final Future<void> Function() _lockAllMountedContainers;
  final VoidCallback _enforceAppLock;

  Timer? _autoLockTimer;
  DateTime? _pausedAt;

  bool get _hasMasterPassword {
    final s = _settings();
    return s.useMasterPassword && s.masterPasswordHash != null;
  }

  void dispose() {
    _autoLockTimer?.cancel();
  }

  /// Call this from the widget's `didChangeAppLifecycleState`.
  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;

      final mins = _settings().autoLockMins;
      final wasAwayTooLong = pausedAt != null &&
          mins > 0 &&
          DateTime.now().difference(pausedAt) >= Duration(minutes: mins);

      if (wasAwayTooLong) {
        performAutoLock();
      } else {
        scheduleAutoLock();
      }
    } else if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    }
  }

  /// Call this from `VaultExplorerApi`'s screen-off listener.
  void handleScreenOff() {
    final s = _settings();
    if (s.lockContainersOnScreenLock && s.autoLockMins == 0) {
      performAutoLock();
    }
  }

  /// Call this any time user activity should push the auto-lock deadline
  /// out (app resume, pointer-down on the dashboard, settings changed,
  /// after `_loadAll`, etc).
  void scheduleAutoLock() {
    _autoLockTimer?.cancel();
    final s = _settings();
    final mins = s.autoLockMins;
    if (mins <= 0 || (!_hasMasterPassword && !s.lockContainersOnScreenLock)) {
      return;
    }
    _autoLockTimer = Timer(Duration(minutes: mins), performAutoLock);
  }

  Future<void> performAutoLock() async {
    _autoLockTimer?.cancel();
    final s = _settings();
    if (s.lockContainersOnScreenLock) {
      await _lockAllMountedContainers();
    }
    if (s.lockContainersOnScreenLock || _hasMasterPassword) {
      _enforceAppLock();
    }
  }
}