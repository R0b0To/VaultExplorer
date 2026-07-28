import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/core/services/privacy_curtain.dart';

/// Owns the "when should we auto-lock" policy that used to live directly on
/// [VaultDashboard]'s State: the auto-lock timer, the paused/resumed
/// lifecycle tracking, and the screen-off shortcut.
///
/// It knows nothing about `MountedContainer`, `vaultExplorerApi`, or
/// `Navigator` — it only decides *when* locking (and covering) should
/// happen and reports that decision back through two injected callbacks and
/// [PrivacyCurtain]. That keeps it free of `BuildContext` and easy to unit
/// test with fake settings + a couple of completers, no widget tree
/// required:
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
    required this._settings,
    required this._lockAllMountedContainers,
    required this._enforceAppLock,
  });

  final AppSettings Function() _settings;
  final Future<void> Function() _lockAllMountedContainers;
  final VoidCallback _enforceAppLock;

  Timer? _autoLockTimer;
  DateTime? _pausedAt;

  /// The in-flight [performAutoLock] call triggered by [handleScreenOff],
  /// if any. Tracked so a resume that races an already-running
  /// screen-off-triggered lock (`autoLockMins == 0`) waits for *that same*
  /// lock/navigate sequence — and only lowers [PrivacyCurtain] once it
  /// actually finishes — instead of assuming there's nothing to wait for
  /// just because [handleAppLifecycleState]'s own timeout wasn't reached.
  /// See ADR-020.
  Future<void>? _pendingLock;

  bool get _hasMasterPassword {
    final s = _settings();
    return s.useMasterPassword && s.masterPasswordHash != null;
  }

  void dispose() {
    _autoLockTimer?.cancel();
  }

  /// Call this from the widget's `didChangeAppLifecycleState`.
  ///
  /// FIX (flash-of-last-session-on-unlock, ADR-020): raises [PrivacyCurtain]
  /// on `inactive` — the earliest cross-platform signal that the app is
  /// about to lose the foreground — synchronously and before anything
  /// async runs. Previously the only defense was `performAutoLock`
  /// `await`ing container-unmount before ever touching the UI, which raced
  /// Android's own resume/repaint of the Activity: if the user dismissed
  /// the keyguard before that native round trip finished, the still-open
  /// container screen was what got painted. Covering first — regardless of
  /// how long the actual lock takes — removes the race entirely.
  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      if (_curtainRelevant()) PrivacyCurtain.show();
    } else if (state == AppLifecycleState.paused) {
      // Belt-and-suspenders in case a platform/Flutter version transitions
      // straight to `paused` without an `inactive` step first.
      if (_curtainRelevant()) PrivacyCurtain.show();
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;

      final mins = _settings().autoLockMins;
      final wasAwayTooLong = pausedAt != null &&
          mins > 0 &&
          DateTime.now().difference(pausedAt) >= Duration(minutes: mins);

      final inFlight = _pendingLock;
      if (wasAwayTooLong) {
        performAutoLock().whenComplete(PrivacyCurtain.hide);
      } else if (inFlight != null) {
        // A screen-off-triggered lock (autoLockMins == 0) started while we
        // were backgrounded and hasn't finished yet — wait for *it* rather
        // than assuming there's nothing to do, and only then reveal.
        inFlight.whenComplete(PrivacyCurtain.hide);
      } else {
        PrivacyCurtain.hide();
        scheduleAutoLock();
      }
    }
  }

  /// True if some auto-lock policy that could leave sensitive content
  /// behind is actually configured — i.e. there's something worth covering
  /// for. Avoids flickering the curtain on every incidental `inactive`
  /// (e.g. a system permission dialog) when the person hasn't opted into
  /// any auto-lock behavior at all.
  bool _curtainRelevant() {
    final s = _settings();
    return s.lockContainersOnScreenLock || _hasMasterPassword;
  }

  /// Call this from `VaultExplorerApi`'s screen-off listener.
  ///
  /// FIX (ADR-020): covers synchronously *before* kicking off the lock, not
  /// after it completes — see [handleAppLifecycleState] doc.
  void handleScreenOff() {
    final s = _settings();
    if (s.lockContainersOnScreenLock && s.autoLockMins == 0) {
      PrivacyCurtain.show();
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
    _autoLockTimer = Timer(Duration(minutes: mins), () {
      // Same fix as ADR-020: cover before the (possibly slow) unmount, not
      // after — this timer can also fire while the dashboard/viewer is
      // still the visible route (idle timeout with the screen still on).
      PrivacyCurtain.show();
      performAutoLock().whenComplete(PrivacyCurtain.hide);
    });
  }

  Future<void> performAutoLock() {
    final future = _performAutoLock();
    _pendingLock = future;
    // Clear the slot once *this* call finishes, but only if nothing newer
    // has already replaced it (defensive; in practice performAutoLock
    // isn't re-entered while one is already running).
    future.whenComplete(() {
      if (identical(_pendingLock, future)) _pendingLock = null;
    });
    return future;
  }

  Future<void> _performAutoLock() async {
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