import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

part 'session_lock_controller.g.dart';

const _kLogTag = 'SessionLockController';

@Riverpod(keepAlive: true)
SessionLockController sessionLockController(Ref ref) {
  final controller = SessionLockController();
  ref.onDispose(controller.dispose);
  return controller;
}

class SessionLockController {
  AppSettings Function()? _settings;
  Future<void> Function()? _lockAllMountedContainers;
  void Function()? _enforceAppLock;
  DateTime Function() _now;

  Timer? _autoLockTimer;
  DateTime? _pausedAt;

  SessionLockController({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  bool get isConfigured => _settings != null;

  void configure({
    required AppSettings Function() settings,
    required Future<void> Function() lockAllMountedContainers,
    required void Function() enforceAppLock,
    DateTime Function()? now,
  }) {
    _settings = settings;
    _lockAllMountedContainers = lockAllMountedContainers;
    _enforceAppLock = enforceAppLock;
    if (now != null) _now = now;
  }

  void dispose() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
  }

  void scheduleAutoLock() {
    if (_settings == null) return;
    _autoLockTimer?.cancel();
    final settings = _settings!();
    final autoLockMins = settings.autoLockMins;
    final lockOnScreenLock = settings.lockContainersOnScreenLock;
    final hasMasterPassword =
        settings.useMasterPassword && settings.masterPasswordHash != null;

    if (autoLockMins <= 0) {
      VeLog.d(_kLogTag, 'scheduleAutoLock: skipped (autoLockMins=$autoLockMins)');
      return;
    }
    if (!hasMasterPassword && !lockOnScreenLock) {
      VeLog.d(
        _kLogTag,
        'scheduleAutoLock: skipped (no masterPassword and lockOnScreenLock=false)',
      );
      return;
    }

    VeLog.d(
      _kLogTag,
      'scheduleAutoLock: arming timer for ${autoLockMins}m '
      '(hasMasterPassword=$hasMasterPassword, lockOnScreenLock=$lockOnScreenLock)',
    );
    _autoLockTimer = Timer(
      Duration(minutes: autoLockMins),
      () {
        VeLog.i(_kLogTag, 'scheduleAutoLock: timer fired after ${autoLockMins}m -> performAutoLock');
        performAutoLock();
      },
    );
  }

  Future<void> performAutoLock() async {
    if (_settings == null) return;
    final settings = _settings!();
    final lockOnScreenLock = settings.lockContainersOnScreenLock;
    final hasMasterPassword =
        settings.useMasterPassword && settings.masterPasswordHash != null;

    VeLog.i(
      _kLogTag,
      'performAutoLock: called (hasMasterPassword=$hasMasterPassword, '
      'lockOnScreenLock=$lockOnScreenLock) at ${_now()}',
    );

    if (hasMasterPassword || lockOnScreenLock) {
      VeLog.i(_kLogTag, 'performAutoLock: invoking enforceAppLock()');
      _enforceAppLock?.call();
    }
    if (lockOnScreenLock) {
      VeLog.i(_kLogTag, 'performAutoLock: invoking lockAllMountedContainers()');
      await _lockAllMountedContainers?.call();
    }
  }

  void handleAppLifecycleState(AppLifecycleState state) {
    if (_settings == null) return;
    VeLog.d(_kLogTag, 'handleAppLifecycleState: $state (pausedAt=$_pausedAt)');
    if (state == AppLifecycleState.paused) {
      _pausedAt = _now();
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt == null) {
        VeLog.d(_kLogTag, 'handleAppLifecycleState: resumed with no prior pausedAt, ignoring');
        return;
      }

      final awayDuration = _now().difference(pausedAt);
      final settings = _settings!();
      final autoLockMins = settings.autoLockMins;

      VeLog.i(
        _kLogTag,
        'handleAppLifecycleState: resumed after awayDuration=$awayDuration '
        '(autoLockMins=$autoLockMins, pausedAt=$pausedAt)',
      );

      if (autoLockMins > 0 && awayDuration >= Duration(minutes: autoLockMins)) {
        VeLog.i(_kLogTag, 'handleAppLifecycleState: away >= autoLockMins -> performAutoLock');
        performAutoLock();
      } else {
        VeLog.d(_kLogTag, 'handleAppLifecycleState: away < autoLockMins -> rescheduling');
        scheduleAutoLock();
      }
    }
  }

  void handleScreenOff() {
    if (_settings == null) return;
    final settings = _settings!();
    VeLog.d(
      _kLogTag,
      'handleScreenOff: received (lockContainersOnScreenLock=${settings.lockContainersOnScreenLock})',
    );
    if (settings.lockContainersOnScreenLock) {
      VeLog.i(_kLogTag, 'handleScreenOff: lockContainersOnScreenLock=true -> performAutoLock');
      performAutoLock();
    }
  }
}