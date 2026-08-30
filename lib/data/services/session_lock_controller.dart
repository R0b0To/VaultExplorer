import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

part 'session_lock_controller.g.dart';

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

    if (autoLockMins <= 0) return;
    if (!hasMasterPassword && !lockOnScreenLock) return;

    _autoLockTimer = Timer(
      Duration(minutes: autoLockMins),
      () => performAutoLock(),
    );
  }

  Future<void> performAutoLock() async {
    if (_settings == null) return;
    final settings = _settings!();
    final lockOnScreenLock = settings.lockContainersOnScreenLock;
    final hasMasterPassword =
        settings.useMasterPassword && settings.masterPasswordHash != null;

    if (hasMasterPassword || lockOnScreenLock) {
      _enforceAppLock?.call();
    }
    if (lockOnScreenLock) {
      await _lockAllMountedContainers?.call();
    }
  }

  void handleAppLifecycleState(AppLifecycleState state) {
    if (_settings == null) return;
    if (state == AppLifecycleState.paused) {
      _pausedAt = _now();
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt == null) return;

      final awayDuration = _now().difference(pausedAt);
      final settings = _settings!();
      final autoLockMins = settings.autoLockMins;

      if (autoLockMins > 0 && awayDuration >= Duration(minutes: autoLockMins)) {
        performAutoLock();
      } else {
        scheduleAutoLock();
      }
    }
  }

  void handleScreenOff() {
    if (_settings == null) return;
    final settings = _settings!();
    if (settings.lockContainersOnScreenLock) {
      performAutoLock();
    }
  }
}