import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

part 'session_lock_controller.g.dart';

const _kLogTag = 'SessionLockController';
const _kPausedAtStorageKey = 'session_lock_paused_at_v1';

@Riverpod(keepAlive: true)
SessionLockController sessionLockController(Ref ref) {
  final secureStorage = ref.read(appSecureStorageProvider);
  final controller = SessionLockController(
    readPausedAt: () async {
      final raw = await secureStorage.read(key: _kPausedAtStorageKey);
      final milliseconds = int.tryParse(raw ?? '');
      if (milliseconds == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    },
    writePausedAt: (pausedAt) => secureStorage.write(
      key: _kPausedAtStorageKey,
      value: pausedAt?.millisecondsSinceEpoch.toString(),
    ),
  );
  ref.onDispose(controller.dispose);
  return controller;
}

/// Arms and fires two independent auto-lock timers, plus two direct actions:
///
/// - **App lock** ([performAppLock]) re-shows `LockGateScreen` via
///   [_enforceAppLock]. Cheap to reverse -- mounted containers are left
///   alone, so re-entry is just a password/PIN/pattern/biometric check.
///   Gated by [AppSettings.useMasterPassword] (a password must actually be
///   set) plus its own timing settings, [AppSettings.appLockAfterMins]
///   (inactivity) and [AppSettings.lockAppOnScreenLock] (screen-off).
///   [AppSettings.appLockScreenLockOnly] switches this from an inactivity
///   timer to reacting only to a genuine screen-off signal (ignoring plain
///   backgrounding, and independent of [AppSettings.lockAppOnScreenLock]) --
///   see [handleScreenOff]/[handleAppLifecycleState]'s use of it.
/// - **Vault lock** ([performVaultLock]) unmounts every open container via
///   [_lockAllMountedContainers]. Expensive to reverse -- the user has to
///   re-decrypt. Gated by its own [AppSettings.autoLockMins] (inactivity)
///   and [AppSettings.lockContainersOnScreenLock] (screen-off).
///   [AppSettings.autoLockScreenLockOnly] switches this from an inactivity
///   timer to reacting only to a genuine screen-off signal -- see
///   [handleScreenOff]/[handleAppLifecycleState]'s use of it.
/// - **Immediate overrides** ([_lockImmediateOverrides]) unmounts only the
///   containers explicitly configured to "Immediately"
///   (`ContainerRecord.autoCloseImmediately`), on every real screen-off or
///   backgrounding event, regardless of either toggle above -- a stronger,
///   per-container choice that isn't gated by the app-wide vault-lock
///   settings any more than an explicit per-container duration is.
/// - **Screen-lock-only overrides** ([_lockScreenLockOnlyOverrides])
///   unmounts only the containers explicitly configured to "Screen Lock
///   Only" (`ContainerRecord.autoCloseScreenLockOnly`), but ONLY on a
///   genuine screen-off signal ([handleScreenOff]) -- deliberately never on
///   mere backgrounding ([handleAppLifecycleState]'s resumed branch), which
///   is exactly the case this mode exists to ignore.
///
/// The two timers are independent on purpose: a container can keep running
/// while the app still asks for the master password again, or the app gate
/// can stay open while containers unmount on their own shorter timeout.
class SessionLockController {
  AppSettings Function()? _settings;
  Future<void> Function()? _lockAllMountedContainers;
  Future<void> Function()? _lockImmediateOverrideContainers;
  Future<void> Function()? _lockScreenLockOnlyContainers;
  void Function()? _enforceAppLock;
  DateTime Function() _now;
  final Future<DateTime?> Function()? _readPausedAt;
  final Future<void> Function(DateTime? pausedAt)? _writePausedAt;

  Timer? _vaultLockTimer;
  Timer? _appLockTimer;
  DateTime? _pausedAt;
  bool _isAppLocked = false;
  bool _appLockedOnScreenOff = false;
  bool _vaultLockedOnScreenOff = false;
   bool _isMediaPlaying = false;
  bool _ignoreBackgroundUntilResume = false;
  int _suppressLockDepth = 0;
  int _vaultAutoLockPauseDepth = 0;

  /// When the last [pauseVaultAutoLock] hold was released while the app was
  /// in the background (e.g. a recording stopped from its notification).
  /// The vault was in use right up to that moment, so the timed vault lock
  /// measures its "time away" from here instead of from when the app was
  /// backgrounded -- see the resumed branch of [handleAppLifecycleState].
  DateTime? _vaultAutoLockReleasedAt;

  bool get isAppLocked => _isAppLocked;
  bool get isMediaPlaying => _isMediaPlaying;
  bool get isLockSuppressed => _suppressLockDepth > 0;
  bool get isVaultAutoLockPaused => _vaultAutoLockPauseDepth > 0;

  /// Holds off every *automatic* vault lock while a recording (video or
  /// audio) is in progress, so nothing unmounts the vault under it and forces
  /// the recording to stop. While at least one hold is active:
  ///
  /// - the inactivity timer is cancelled and not re-armed;
  /// - [performVaultLock] does nothing, which covers the "away for longer
  ///   than [AppSettings.autoLockMins]" check on return from the background,
  ///   "Immediately" (`autoLockMins == 0`) and screen-off locking;
  /// - the per-container "Immediately" and "Screen Lock Only" overrides
  ///   ([_lockImmediateOverrides], [_lockScreenLockOnlyOverrides]) do nothing.
  ///
  /// A trigger skipped this way is dropped, not replayed once the recording
  /// ends: the inactivity timer starts fresh and any later trigger applies as
  /// usual. Not affected: the app-lock gate (it leaves mounted containers,
  /// and so the recording, alone) and explicit user actions such as tapping
  /// Lock, which still stop and save the recording through
  /// `ActiveRecordingRegistry`.
  ///
  /// Calls nest: automatic locking resumes only once every hold has been
  /// released.
  void pauseVaultAutoLock() {
    _vaultAutoLockPauseDepth++;
    if (_vaultAutoLockPauseDepth == 1) {
      VeLog.d(_kLogTag, 'pauseVaultAutoLock: cancelling vault inactivity timer');
      _vaultLockTimer?.cancel();
      _vaultLockTimer = null;
    }
  }

  void resumeVaultAutoLock() {
    if (_vaultAutoLockPauseDepth == 0) return;
    _vaultAutoLockPauseDepth--;
    if (_vaultAutoLockPauseDepth == 0) {
      // Released while the app is backgrounded: the idle clock starts now, not
      // when the app left the foreground (which was during the recording).
      if (_pausedAt != null) _vaultAutoLockReleasedAt = _now();
      VeLog.d(_kLogTag, 'resumeVaultAutoLock: rearming vault inactivity timer');
      _scheduleVaultLockTimer();
    }
  }

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
      _persistPausedAt(null);
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

  /// Suppresses inactivity timers while media is actively playing -- in the
  /// foreground, or in the background (background playback keeps going with
  /// the app minimized or the screen off). See also the resumed branch of
  /// [handleAppLifecycleState], which treats playback that is still running
  /// on return as activity rather than as time spent away.
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

  SessionLockController({
    DateTime Function()? now,
    this._readPausedAt,
    this._writePausedAt,
  }) : _now = now ?? DateTime.now;

  bool get isConfigured => _settings != null;

  void configure({
    required AppSettings Function() settings,
    required Future<void> Function() lockAllMountedContainers,
    required void Function() enforceAppLock,
    Future<void> Function()? lockImmediateOverrideContainers,
    Future<void> Function()? lockScreenLockOnlyContainers,
    DateTime Function()? now,
  }) {
    _settings = settings;
    _lockAllMountedContainers = lockAllMountedContainers;
    _lockImmediateOverrideContainers = lockImmediateOverrideContainers;
    _lockScreenLockOnlyContainers = lockScreenLockOnlyContainers;
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

  /// Locks any mounted container explicitly configured to "Immediately"
  /// (`ContainerRecord.autoCloseImmediately`), regardless of
  /// [AppSettings.lockContainersOnScreenLock] or [AppSettings.autoLockMins]
  /// -- like an explicit per-container duration, this is a stronger choice
  /// than the app-wide default and isn't gated by it. Deliberately separate
  /// from [performVaultLock]/[_lockAllMountedContainers] (the app-wide
  /// sweep already skips these containers -- see
  /// [ContainerRecord.isExemptFromGlobalLock]) and from the per-container
  /// inactivity timer (`VaultDashboardController.scheduleAutoClose`, which
  /// also skips them): a 0-minute foreground idle timer would re-lock the
  /// container almost instantly after every tap, since that timer re-arms
  /// on every interaction app-wide. Only called from real
  /// backgrounding/screen-off signals below, never from foreground activity.
  void _lockImmediateOverrides() {
    if (_lockImmediateOverrideContainers == null) return;
    if (isVaultAutoLockPaused) {
      VeLog.d(_kLogTag, '_lockImmediateOverrides: recording active, skipping');
      return;
    }
    VeLog.i(_kLogTag, '_lockImmediateOverrides: locking any Immediately-configured containers');
    unawaited(_lockImmediateOverrideContainers!.call());
  }

  /// Locks any mounted container explicitly configured to "Screen Lock
  /// Only" (`ContainerRecord.autoCloseScreenLockOnly`), regardless of
  /// [AppSettings.lockContainersOnScreenLock] -- same reasoning as
  /// [_lockImmediateOverrides]: a stronger, per-container choice that isn't
  /// gated by the app-wide toggle. Unlike [_lockImmediateOverrides],
  /// deliberately only ever called from [handleScreenOff] below, never from
  /// [handleAppLifecycleState]'s resumed-after-backgrounding branch -- a
  /// container in this mode must NOT lock just because the app was
  /// backgrounded (switching to another app while the screen stayed on);
  /// only a genuine screen-off signal should trigger it. Also deliberately
  /// separate from the per-container inactivity timer
  /// (`VaultDashboardController.scheduleAutoClose`), for the same reason
  /// [_lockImmediateOverrides] is: there's no inactivity duration in this
  /// mode at all, foreground or otherwise.
  void _lockScreenLockOnlyOverrides() {
    if (_lockScreenLockOnlyContainers == null) return;
    if (isVaultAutoLockPaused) {
      VeLog.d(_kLogTag, '_lockScreenLockOnlyOverrides: recording active, skipping');
      return;
    }
    VeLog.i(_kLogTag, '_lockScreenLockOnlyOverrides: locking any Screen-Lock-Only containers');
    unawaited(_lockScreenLockOnlyContainers!.call());
  }

  /// Re-arms both inactivity timers from current settings, measured from
  /// now. Called on every user interaction (pointer-down on the dashboard)
  /// and after data loads, so idle time resets on real activity.
 void scheduleAutoLock() {
    if (_isMediaPlaying) return;
    _scheduleVaultLockTimer();
    _scheduleAppLockTimer();
  }

  void _scheduleVaultLockTimer() {
    if (_settings == null || _isMediaPlaying || isVaultAutoLockPaused) return;
    _vaultLockTimer?.cancel();
    final settings = _settings!();
    final mins = settings.autoLockMins;

    if (!settings.lockContainersOnScreenLock || settings.autoLockScreenLockOnly || mins <= 0) {
      VeLog.d(
        _kLogTag,
        '_scheduleVaultLockTimer: skipped '
        '(lockContainersOnScreenLock=${settings.lockContainersOnScreenLock}, '
        'autoLockScreenLockOnly=${settings.autoLockScreenLockOnly}, autoLockMins=$mins)',
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

    if (!hasMasterPassword || settings.appLockScreenLockOnly || mins <= 0) {
      VeLog.d(
        _kLogTag,
        '_scheduleAppLockTimer: skipped '
        '(hasMasterPassword=$hasMasterPassword, '
        'appLockScreenLockOnly=${settings.appLockScreenLockOnly}, appLockAfterMins=$mins)',
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
  /// not touch `LockGateScreen`. Does nothing while a recording holds
  /// [pauseVaultAutoLock]; every automatic trigger (inactivity timer, return
  /// from the background, screen-off) funnels through here.
  Future<void> performVaultLock() async {
    if (_settings == null) return;
    if (isVaultAutoLockPaused) {
      VeLog.i(_kLogTag, 'performVaultLock: recording active, skipping vault lock');
      return;
    }
    VeLog.i(_kLogTag, 'performVaultLock: invoking lockAllMountedContainers()');
    await _lockAllMountedContainers?.call();
  }

  /// Re-shows `LockGateScreen`, if a master password is actually configured.
  /// Independent of [performVaultLock] -- does not touch mounted containers.
 /// Called when the user successfully authenticates and dismisses the lock gate.
  /// Called when the user successfully authenticates and enters the dashboard.
  void notifyAppUnlocked({bool preserveBackgroundState = false}) {
    VeLog.i(_kLogTag, 'notifyAppUnlocked: app gate unlocked, resetting lock state');
    _isAppLocked = false;
    if (!preserveBackgroundState) {
      _pausedAt = null;
      _persistPausedAt(null);
    }
    _appLockedOnScreenOff = false;
    scheduleAutoLock();
  }

  /// Clears elapsed background state when the Activity is intentionally
  /// closed to switch between normal and decoy identities. That transition
  /// is not user absence and must not trigger auto-lock in the next identity.
  Future<void> prepareForModeSwitchExit() async {
    _pausedAt = null;
    _ignoreBackgroundUntilResume = true;
    try {
      await _writePausedAt?.call(null);
    } catch (e) {
      VeLog.w(_kLogTag, 'Failed to clear background timestamp for mode switch', e);
    }
  }

  /// Retains a background event received while a mode-specific screen is
  /// still loading its settings and lock callbacks.
  void recordBackgroundedAt(DateTime pausedAt) {
    _pausedAt ??= pausedAt;
    _persistPausedAt(_pausedAt);
  }

  /// Applies a background interval saved by a previous Flutter engine. This
  /// covers app/task recreation, where an in-memory lifecycle timestamp is
  /// lost but native vault sessions can still be mounted.
  Future<void> resumeFromPersistedBackgroundState({
    bool evaluateAppLock = true,
  }) async {
    if (_settings == null) return;
    if (_pausedAt == null && _readPausedAt != null) {
      try {
        final restored = await _readPausedAt.call();
        // A new pause may have arrived while storage was being read. Keep it.
        _pausedAt ??= restored;
      } catch (e) {
        VeLog.w(_kLogTag, 'Failed to restore background timestamp', e);
      }
    }
    if (_pausedAt == null) return;
    handleAppLifecycleState(
      AppLifecycleState.resumed,
      evaluateAppLock: evaluateAppLock,
    );
  }

  void _persistPausedAt(DateTime? pausedAt) {
    final write = _writePausedAt;
    if (write == null) return;
    unawaited(
      write(pausedAt).catchError((Object error) {
        VeLog.w(_kLogTag, 'Failed to persist background timestamp', error);
      }),
    );
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

  void handleAppLifecycleState(AppLifecycleState state, {bool evaluateAppLock = true}) {
    if (_settings == null) return;
    VeLog.d(
      _kLogTag,
      'handleAppLifecycleState: $state (pausedAt=$_pausedAt, isAppLocked=$_isAppLocked, isLockSuppressed=$isLockSuppressed)',
    );

    // Only count actual backgrounding (hidden or paused).
    // 'inactive' occurs during transient foreground overlays like the system biometric
    // prompt, permission dialogs, or notification shade, where the app has NOT left the screen.
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      if (_ignoreBackgroundUntilResume) {
        VeLog.d(_kLogTag, 'handleAppLifecycleState: ignoring background during identity switch');
        return;
      }
      if (isLockSuppressed) {
        VeLog.d(_kLogTag, 'handleAppLifecycleState: hidden/paused while lock suppressed, ignoring');
        return;
      }
      if (_pausedAt == null) {
        _pausedAt = _now();
        _persistPausedAt(_pausedAt);
      }
      _cancelTimers();
    } else if (state == AppLifecycleState.resumed) {
      _ignoreBackgroundUntilResume = false;
      if (isLockSuppressed) {
        VeLog.d(_kLogTag, 'handleAppLifecycleState: resumed while lock suppressed, ignoring');
        _pausedAt = null;
        _persistPausedAt(null);
        return;
      }
      final pausedAt = _pausedAt;
      if (pausedAt == null && _readPausedAt != null) {
        unawaited(resumeFromPersistedBackgroundState(evaluateAppLock: evaluateAppLock));
        return;
      }
      final vaultHoldReleasedAt = _vaultAutoLockReleasedAt;
      if (pausedAt != null) _cancelTimers();
      _pausedAt = null;
      _vaultAutoLockReleasedAt = null;
      _persistPausedAt(null);
      final lockedAppOnScreenOff = _appLockedOnScreenOff;
      final lockedVaultOnScreenOff = _vaultLockedOnScreenOff;
      _appLockedOnScreenOff = false;
      _vaultLockedOnScreenOff = false;

      if (pausedAt == null) {
        VeLog.d(_kLogTag, 'handleAppLifecycleState: resumed with no prior background state, ignoring');
        return;
      }

      // A genuine background period just ended -- independent of
      // lockContainersOnScreenLock, see _lockImmediateOverrides.
      _lockImmediateOverrides();

      final awayDuration = _now().difference(pausedAt);
      // How long the *vault* has been idle. Normally the same as
      // awayDuration, but if a pauseVaultAutoLock hold (a recording) ended
      // while the app was still in the background, the vault was in use until
      // then, so idle time only counts from that moment. The app-lock gate
      // keeps using the real awayDuration. (A hold that is still active here
      // needs no special case: performVaultLock skips while it is held.)
      final vaultIdleSince =
          (vaultHoldReleasedAt != null && vaultHoldReleasedAt.isAfter(pausedAt))
              ? vaultHoldReleasedAt
              : pausedAt;
      final vaultAwayDuration = _now().difference(vaultIdleSince);
      final settings = _settings!();
      final hasMasterPassword = _hasMasterPassword(settings);

      VeLog.i(
        _kLogTag,
        'handleAppLifecycleState: resumed after awayDuration=$awayDuration '
        '(hasMasterPassword=$hasMasterPassword, isAppLocked=$_isAppLocked, '
        'appLockAfterMins=${settings.appLockAfterMins}, autoLockMins=${settings.autoLockMins})',
      );

      if (!evaluateAppLock) {
        _scheduleAppLockTimer();
      } else if (hasMasterPassword && !_isAppLocked && !lockedAppOnScreenOff) {
        if (settings.appLockScreenLockOnly) {
          // This mode ignores mere backgrounding entirely -- only a genuine
          // screen-off signal (handleScreenOff) should re-show the lock
          // gate. If the screen actually turned off during this background
          // period, handleScreenOff already handled it independently, and
          // lockedAppOnScreenOff above would be true in that case anyway.
          VeLog.d(
            _kLogTag,
            'handleAppLifecycleState: appLockScreenLockOnly is set, ignoring mere backgrounding',
          );
        } else {
          final shouldLock = settings.appLockAfterMins == 0 ||
              (settings.appLockAfterMins > 0 &&
                  awayDuration >= Duration(minutes: settings.appLockAfterMins));
          if (shouldLock) {
            VeLog.i(_kLogTag, 'handleAppLifecycleState: away timeout reached -> performAppLock');
            performAppLock();
          } else {
            _scheduleAppLockTimer();
          }
        }
      } else if (!_isAppLocked) {
        _scheduleAppLockTimer();
      }

      if (_isMediaPlaying && settings.autoLockMins > 0) {
        // Media kept playing from the unlocked vault the whole time the app
        // was in the background (background playback). That is the vault
        // being used, not sitting idle, so the time away must not count
        // towards a *timed* inactivity lock -- otherwise returning to the
        // app after a long listen would lock the vault and cut the playback
        // off. Same rule foreground playback already gets (see
        // setMediaPlaying); the timers re-arm normally once playback stops.
        // Deliberately not applied to autoLockMins == 0 ("Immediately"),
        // which is an explicit instruction to lock on return, nor to a
        // genuine screen-off lock, per-container "Immediately", or the
        // app-lock gate: those are separate paths and unaffected.
        VeLog.d(
          _kLogTag,
          'handleAppLifecycleState: media still playing on resume, '
          'not counting awayDuration=$awayDuration towards vault lock',
        );
      } else if (settings.lockContainersOnScreenLock &&
          !lockedVaultOnScreenOff) {
        if (settings.autoLockScreenLockOnly) {
          // This mode ignores mere backgrounding entirely -- only a genuine
          // screen-off signal (handleScreenOff) should lock the vault. If
          // the screen actually turned off during this background period,
          // handleScreenOff already handled it independently, and
          // lockedVaultOnScreenOff above would be true in that case anyway.
          VeLog.d(
            _kLogTag,
            'handleAppLifecycleState: autoLockScreenLockOnly is set, ignoring mere backgrounding',
          );
        } else {
          final shouldLockVault = settings.autoLockMins == 0 ||
              (settings.autoLockMins > 0 &&
                  vaultAwayDuration >= Duration(minutes: settings.autoLockMins));
          if (shouldLockVault) {
            VeLog.i(_kLogTag, 'handleAppLifecycleState: away >= autoLockMins -> performVaultLock');
            performVaultLock();
          } else {
            _scheduleVaultLockTimer();
          }
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

    // Independent of both toggles above -- see _lockImmediateOverrides and
    // _lockScreenLockOnlyOverrides.
    _lockImmediateOverrides();
    _lockScreenLockOnlyOverrides();

     // appLockScreenLockOnly implies screen-off locking, so it applies
     // regardless of lockAppOnScreenLock -- see AppSettings.appLockScreenLockOnly.
     if (hasMasterPassword && (settings.appLockScreenLockOnly || settings.lockAppOnScreenLock)) {
      if (settings.appLockScreenLockOnly || settings.appLockAfterMins <= 0) {
        // "Screen Lock Only" or "Immediately" is selected -- lock the app
        // gate as soon as the screen goes off.
        VeLog.i(
          _kLogTag,
          'handleScreenOff: appLockScreenLockOnly=${settings.appLockScreenLockOnly}, '
          'appLockAfterMins=${settings.appLockAfterMins} -> performAppLock immediately',
        );
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
      if (settings.autoLockScreenLockOnly || settings.autoLockMins <= 0) {
        VeLog.i(
          _kLogTag,
          'handleScreenOff: autoLockScreenLockOnly=${settings.autoLockScreenLockOnly}, '
          'autoLockMins=${settings.autoLockMins} -> performVaultLock immediately',
        );
        // Only record the screen-off lock as done if it will actually
        // happen: while a recording holds the vault open it is skipped, and
        // the flag would otherwise make the next resume skip its own check.
        if (!isVaultAutoLockPaused) _vaultLockedOnScreenOff = true;
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
