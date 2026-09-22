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

/// Arms and fires two independent auto-lock timers:
///
/// - **App lock** ([performAppLock]) re-shows `LockGateScreen` via
///   [_enforceAppLock]. Cheap to reverse -- mounted containers are left
///   alone, so re-entry is just a password/PIN/pattern/biometric check.
///   Gated by [AppSettings.useMasterPassword] (a password must actually be
///   set) plus its own timing settings, [AppSettings.appLockAfterMins]
///   (inactivity) and [AppSettings.lockAppOnScreenLock] (screen-off).
/// - **Vault lock** ([performVaultLock]) unmounts every open container via
///   [_lockAllMountedContainers]. Expensive to reverse -- the user has to
///   re-decrypt. Gated by its own [AppSettings.autoLockMins] (inactivity)
///   and [AppSettings.lockContainersOnScreenLock] (screen-off).
///
/// The two are independent on purpose: a container can keep running while
/// the app still asks for the master password again, or the app gate can
/// stay open while containers unmount on their own shorter timeout.
class SessionLockController {
  AppSettings Function()? _settings;
  Future<void> Function()? _lockAllMountedContainers;
  void Function()? _enforceAppLock;
  DateTime Function() _now;

  Timer? _vaultLockTimer;
  Timer? _appLockTimer;
  DateTime? _pausedAt;
  bool _isAppLocked = false;
  bool _appLockedOnScreenOff = false;
  bool _vaultLockedOnScreenOff = false;
   bool _isMediaPlaying = false;
  int _suppressLockDepth = 0;

  bool get isAppLocked => _isAppLocked;
  bool get isMediaPlaying => _isMediaPlaying;
  bool get isLockSuppressed => _suppressLockDepth > 0;

  /// Temporarily suppresses auto-lock for modal operations like the system file picker.
  void suppressLock() {
    _suppressLockDepth++;
    VeLog.d(_kLogTag, 'suppressLock: depth=$_suppressLockDepth');
  }

  void unsuppressLock() {
    if (_suppressLockDepth > 0) {
      _suppressLockDepth--;
      VeLog.d(_kLogTag, 'unsuppressLock: depth=$_suppressLockDepth');
    }
    if (_suppressLockDepth == 0) {
      _pausedAt = null;
    }
  }

  /// Runs an asynchronous operation (e.g. system file picker) while suppressing auto-lock.
  Future<T> withLockSuppression<T>(Future<T> Function() action) async {
    suppressLock();
    try {
      return await action();
    } finally {
      unsuppressLock();
    }
  }

  /// Suppresses inactivity timers while media is actively playing in the foreground.
  void setMediaPlaying(bool isPlaying) {
    if (_isMediaPlaying == isPlaying) return;
    _isMediaPlaying = isPlaying;
    VeLog.d(_kLogTag, 'setMediaPlaying: isPlaying=$isPlaying');
    if (isPlaying) {
      _cancelTimers();
    } else {
      scheduleAutoLock();
    }
  }

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
    _cancelTimers();
  }

  void _cancelTimers() {
    _vaultLockTimer?.cancel();
    _vaultLockTimer = null;
    _appLockTimer?.cancel();
    _appLockTimer = null;
  }

  bool _hasMasterPassword(AppSettings settings) =>
      settings.useMasterPassword && settings.masterPasswordHash != null;

  /// Re-arms both inactivity timers from current settings, measured from
  /// now. Called on every user interaction (pointer-down on the dashboard)
  /// and after data loads, so idle time resets on real activity.
 void scheduleAutoLock() {
    if (_isMediaPlaying) return;
    _scheduleVaultLockTimer();
    _scheduleAppLockTimer();
  }

  void _scheduleVaultLockTimer() {
    if (_settings == null || _isMediaPlaying) return;
    _vaultLockTimer?.cancel();
    final settings = _settings!();
    final mins = settings.autoLockMins;

    if (!settings.lockContainersOnScreenLock || mins <= 0) {
      VeLog.d(
        _kLogTag,
        '_scheduleVaultLockTimer: skipped '
        '(lockContainersOnScreenLock=${settings.lockContainersOnScreenLock}, autoLockMins=$mins)',
      );
      return;
    }

    VeLog.d(_kLogTag, '_scheduleVaultLockTimer: arming timer for ${mins}m');
    _vaultLockTimer = Timer(
      Duration(minutes: mins),
      () {
        VeLog.i(_kLogTag, '_scheduleVaultLockTimer: timer fired after ${mins}m -> performVaultLock');
        performVaultLock();
      },
    );
  }

  void _scheduleAppLockTimer() {
    if (_settings == null || _isMediaPlaying) return;
    _appLockTimer?.cancel();
    final settings = _settings!();
    final hasMasterPassword = _hasMasterPassword(settings);
    final mins = settings.appLockAfterMins;

    if (!hasMasterPassword || mins <= 0) {
      VeLog.d(
        _kLogTag,
        '_scheduleAppLockTimer: skipped '
        '(hasMasterPassword=$hasMasterPassword, appLockAfterMins=$mins)',
      );
      return;
    }

    VeLog.d(_kLogTag, '_scheduleAppLockTimer: arming timer for ${mins}m');
    _appLockTimer = Timer(
      Duration(minutes: mins),
      () {
        VeLog.i(_kLogTag, '_scheduleAppLockTimer: timer fired after ${mins}m -> performAppLock');
        performAppLock();
      },
    );
  }

  /// Unmounts every open container. Independent of [performAppLock] -- does
  /// not touch `LockGateScreen`.
  Future<void> performVaultLock() async {
    if (_settings == null) return;
    VeLog.i(_kLogTag, 'performVaultLock: invoking lockAllMountedContainers()');
    await _lockAllMountedContainers?.call();
  }

  /// Re-shows `LockGateScreen`, if a master password is actually configured.
  /// Independent of [performVaultLock] -- does not touch mounted containers.
 /// Called when the user successfully authenticates and dismisses the lock gate.
  /// Called when the user successfully authenticates and enters the dashboard.
  void notifyAppUnlocked() {
    VeLog.i(_kLogTag, 'notifyAppUnlocked: app gate unlocked, resetting lock state');
    _isAppLocked = false;
    _pausedAt = null;
    _appLockedOnScreenOff = false;
    scheduleAutoLock();
  }

  void performAppLock() {
    if (_settings == null) return;
    final settings = _settings!();
    final hasMasterPassword = _hasMasterPassword(settings);
    VeLog.i(
      _kLogTag,
      'performAppLock: called (hasMasterPassword=$hasMasterPassword, isAppLocked=$_isAppLocked)',
    );
    if (hasMasterPassword) {
      if (_isAppLocked) {
        VeLog.d(_kLogTag, 'performAppLock: app gate is already armed/locked, skipping duplicate');
        return;
      }
      _isAppLocked = true;
      _cancelTimers();
      _pausedAt = null;
      VeLog.i(_kLogTag, 'performAppLock: invoking enforceAppLock()');
      _enforceAppLock?.call();
    }
  }

  /// Fires both locks right now, each still independently gated by its own
  /// settings. Kept as a single entry point for callers that want to
  /// evaluate "lock everything that's due" in one call.
  Future<void> performAutoLock() async {
    performAppLock();
    await performVaultLock();
  }

  void handleAppLifecycleState(AppLifecycleState state) {
    if (_settings == null) return;
    VeLog.d(
      _kLogTag,
      'handleAppLifecycleState: $state (pausedAt=$_pausedAt, isAppLocked=$_isAppLocked, isLockSuppressed=$isLockSuppressed)',
    );

    // Only count actual backgrounding (hidden or paused).
    // 'inactive' occurs during transient foreground overlays like the system biometric
    // prompt, permission dialogs, or notification shade, where the app has NOT left the screen.
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      if (isLockSuppressed) {
        VeLog.d(_kLogTag, 'handleAppLifecycleState: hidden/paused while lock suppressed, ignoring');
        return;
      }
      _pausedAt ??= _now();
      _cancelTimers();
    } else if (state == AppLifecycleState.resumed) {
      if (isLockSuppressed) {
        VeLog.d(_kLogTag, 'handleAppLifecycleState: resumed while lock suppressed, ignoring');
        _pausedAt = null;
        return;
      }
      final pausedAt = _pausedAt;
      _pausedAt = null;
      final lockedAppOnScreenOff = _appLockedOnScreenOff;
      final lockedVaultOnScreenOff = _vaultLockedOnScreenOff;
      _appLockedOnScreenOff = false;
      _vaultLockedOnScreenOff = false;

      if (pausedAt == null) {
        VeLog.d(_kLogTag, 'handleAppLifecycleState: resumed with no prior background state, ignoring');
        return;
      }

      final awayDuration = _now().difference(pausedAt);
      final settings = _settings!();
      final hasMasterPassword = _hasMasterPassword(settings);

      VeLog.i(
        _kLogTag,
        'handleAppLifecycleState: resumed after awayDuration=$awayDuration '
        '(hasMasterPassword=$hasMasterPassword, isAppLocked=$_isAppLocked, '
        'appLockAfterMins=${settings.appLockAfterMins}, autoLockMins=${settings.autoLockMins})',
      );

      if (hasMasterPassword && !_isAppLocked && !lockedAppOnScreenOff) {
        final shouldLock = settings.appLockAfterMins == 0 ||
            (settings.appLockAfterMins > 0 &&
                awayDuration >= Duration(minutes: settings.appLockAfterMins));
        if (shouldLock) {
          VeLog.i(_kLogTag, 'handleAppLifecycleState: away timeout reached -> performAppLock');
          performAppLock();
        } else {
          _scheduleAppLockTimer();
        }
      } else if (!_isAppLocked) {
        _scheduleAppLockTimer();
      }

      if (settings.lockContainersOnScreenLock && !lockedVaultOnScreenOff) {
        final shouldLockVault = settings.autoLockMins == 0 ||
            (settings.autoLockMins > 0 &&
                awayDuration >= Duration(minutes: settings.autoLockMins));
        if (shouldLockVault) {
          VeLog.i(_kLogTag, 'handleAppLifecycleState: away >= autoLockMins -> performVaultLock');
          performVaultLock();
        } else {
          _scheduleVaultLockTimer();
        }
      } else {
        _scheduleVaultLockTimer();
      }
    }
  }

   void handleScreenOff() {
    if (_settings == null || isLockSuppressed) return;
    final settings = _settings!();
    final hasMasterPassword = _hasMasterPassword(settings);
    VeLog.d(
      _kLogTag,
      'handleScreenOff: received (hasMasterPassword=$hasMasterPassword, '
      'lockAppOnScreenLock=${settings.lockAppOnScreenLock}, appLockAfterMins=${settings.appLockAfterMins}, '
      'lockContainersOnScreenLock=${settings.lockContainersOnScreenLock}, autoLockMins=${settings.autoLockMins})',
    );

     if (hasMasterPassword && settings.lockAppOnScreenLock) {
      if (settings.appLockAfterMins <= 0) {
        // "Immediately" is selected -- lock the app gate as soon as the
        // screen goes off.
        VeLog.i(_kLogTag, 'handleScreenOff: appLockAfterMins<=0 -> performAppLock immediately');
        _appLockedOnScreenOff = true;
        performAppLock();
      } else {
        // A real timeout is configured: don't lock on the spot, (re)arm the
        // countdown from now so the app stays unlocked until the screen has
        // been off for the configured duration, same as the inactivity timer.
        VeLog.i(
          _kLogTag,
          'handleScreenOff: appLockAfterMins=${settings.appLockAfterMins} -> arming app-lock countdown instead of locking immediately',
        );
        _scheduleAppLockTimer();
      }
    }

    if (settings.lockContainersOnScreenLock) {
      if (settings.autoLockMins <= 0) {
        VeLog.i(_kLogTag, 'handleScreenOff: autoLockMins<=0 -> performVaultLock immediately');
        _vaultLockedOnScreenOff = true;
        performVaultLock();
      } else {
        VeLog.i(
          _kLogTag,
          'handleScreenOff: autoLockMins=${settings.autoLockMins} -> arming vault-lock countdown instead of locking immediately',
        );
        _scheduleVaultLockTimer();
      }
    }
  }
}