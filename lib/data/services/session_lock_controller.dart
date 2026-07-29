import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

class SessionLockController {
  SessionLockController({
    required this._settings,
    required this._lockAllMountedContainers,
    required this._enforceAppLock,
  });

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

  void handleScreenOff() {
    final s = _settings();
    final mins = s.autoLockMins;
    if ((s.lockContainersOnScreenLock || _hasMasterPassword) && mins == 0) {
      performAutoLock();
    }
  }

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
    if (s.lockContainersOnScreenLock || _hasMasterPassword) {
      _enforceAppLock();
    }
    if (s.lockContainersOnScreenLock) {
      await _lockAllMountedContainers();
    }
  }
}