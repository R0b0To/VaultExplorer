import 'package:meta/meta.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';

/// In-memory shadow of one throttle's counters, used only while secure storage
/// is failing (a Keystore error, or a write the native side reports as not
/// persisted).
///
/// Before this existed, a storage failure meant `recordFailure` counted
/// nothing and `currentLockout` reported "not locked", so anything that could
/// make storage fail also gave unlimited attempts. The throttles still fail
/// *open* on the persisted side -- a storage glitch must never lock someone
/// out of their own vault -- but attempts made during the outage now count
/// towards the same schedule for the life of the process. Process death
/// clears this state; that is the accepted limit of an in-memory fallback.
///
/// Populated only on the failure path, so with healthy storage it stays empty.
/// Each throttle owns its own instance, keeping the two lockout paths'
/// state separate as their class docs require.
class _ThrottleOutageState {
  final Map<String, int> attempts = {};
  final Map<String, int> lockedUntilMs = {};

  void clear(String uri) {
    attempts.remove(uri);
    lockedUntilMs.remove(uri);
  }
}

int? _laterOf(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a > b ? a : b;
}

/// Per-container, persisted exponential-backoff lockout for pattern-unlock
/// attempts. Mirrors `LockGateScreen`'s master-password lockout (same
/// thresholds/schedule) because a correct pattern here grants the same
/// access to the vault's derived key that a correct master password does
/// -- it deserves the same brute-force protection. Keyed by container URI
/// so each vault's lockout state is independent of the others'.
///
/// Not private (was `_PatternUnlockThrottle`): Dart's per-file privacy
/// meant a leading underscore made this unreachable from any test file --
/// see pattern_unlock_throttle_test.dart, which is the reason for this
/// rename. @visibleForTesting marks the intent: this stays an
/// implementation detail of the unlock controllers above, not a
/// general-purpose export.
///
/// Extracted (unchanged) from the former unlock_biometric_mixin.dart when
/// that mixin was deleted as dead code -- it was no longer mixed into
/// UnlockSheet/UsbUnlockSheet's State classes after they moved to
/// ConsumerStatefulWidget/Riverpod controllers, and its own
/// onPatternComplete/onPinComplete (the only call sites for this class)
/// went with it. UnlockController/UsbUnlockController's Riverpod
/// onPatternComplete/onPinComplete now call this directly instead.
@visibleForTesting
class PatternUnlockThrottle {
  static const _secure = AppSecureStorage.instance;

  static String _attemptsKey(String uri) => 'pattern_unlock_failed_attempts_v1:$uri';
  static String _lockedUntilKey(String uri) => 'pattern_unlock_locked_until_ms_v1:$uri';

  static const _tag = 'PatternUnlockThrottle';
  static final _outage = _ThrottleOutageState();

  /// Writes [value] and reports whether it was really persisted.
  static Future<bool> _persist(String key, String value) async {
    try {
      return await _secure.writeVerified(key: key, value: value);
    } catch (e) {
      VeLog.e(_tag, 'secure storage write failed; keeping state in memory only', e);
      return false;
    }
  }

  /// Returns the remaining lockout duration for [uri], or null if it isn't
  /// currently locked out.
  static Future<Duration?> currentLockout(String uri) async {
    int? storedUntilMs;
    try {
      final raw = await _secure.read(key: _lockedUntilKey(uri));
      storedUntilMs = raw == null ? null : int.tryParse(raw);
    } catch (e) {
      // Don't lock the user out of their own vault over a storage glitch:
      // fail open on the persisted side, but still honour anything this
      // process already recorded in memory.
      VeLog.e(_tag, 'currentLockout: secure storage read failed; using in-memory state', e);
    }
    final untilMs = _laterOf(storedUntilMs, _outage.lockedUntilMs[uri]);
    if (untilMs == null) return null;
    final remaining = DateTime.fromMillisecondsSinceEpoch(untilMs).difference(DateTime.now());
    if (remaining.isNegative) {
      _outage.lockedUntilMs.remove(uri);
      if (storedUntilMs != null) {
        try {
          await _secure.delete(key: _lockedUntilKey(uri));
        } catch (e) {
          VeLog.e(_tag, 'currentLockout: could not clear an expired lockout', e);
        }
      }
      return null;
    }
    return remaining;
  }

  /// Records a failed attempt for [uri] and applies the same schedule as
  /// LockGateScreen: 30s at the 5th failure, +30s per additional failure,
  /// capped at 300s (reached at the 14th). Returns the new lockout duration
  /// once one is triggered, else null.
  ///
  /// If secure storage can't be read or written, the count and the lockout
  /// deadline are kept in memory instead (see [_ThrottleOutageState]).
  static Future<Duration?> recordFailure(String uri) async {
    var persistedAttempts = 0;
    var storageOk = true;
    try {
      persistedAttempts = int.tryParse(await _secure.read(key: _attemptsKey(uri)) ?? '') ?? 0;
    } catch (e) {
      storageOk = false;
      VeLog.e(_tag, 'recordFailure: secure storage read failed; counting in memory', e);
    }
    final carried = _outage.attempts[uri] ?? 0;
    final attempts = (persistedAttempts > carried ? persistedAttempts : carried) + 1;
    if (storageOk) storageOk = await _persist(_attemptsKey(uri), attempts.toString());
    if (storageOk) {
      _outage.attempts.remove(uri);
    } else {
      _outage.attempts[uri] = attempts;
    }

    if (attempts >= 5) {
      final excess = attempts - 4;
      final seconds = (30 * excess).clamp(30, 300);
      final untilMs = DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch;
      if (await _persist(_lockedUntilKey(uri), untilMs.toString())) {
        _outage.lockedUntilMs.remove(uri);
      } else {
        _outage.lockedUntilMs[uri] = untilMs;
      }
      return Duration(seconds: seconds);
    }
    return null;
  }

  /// Clears persisted lockout state for [uri] after a successful unlock.
  static Future<void> clear(String uri) async {
    _outage.clear(uri);
    for (final key in [_attemptsKey(uri), _lockedUntilKey(uri)]) {
      try {
        await _secure.delete(key: key);
      } catch (e) {
        // Best-effort, same reasoning as LockGateScreen._clearLockoutState():
        // a leftover stale entry here just self-corrects the next time
        // recordFailure()/clear() successfully writes.
        VeLog.e(_tag, 'clear: could not delete a persisted lockout entry', e);
      }
    }
  }
}

/// Per-container, persisted exponential-backoff lockout for PIN-unlock
/// attempts. Mirrors [PatternUnlockThrottle] exactly (same
/// thresholds/schedule, same fail-open-on-storage-error behavior) --
/// deliberately kept as a separate class rather than parameterizing
/// [PatternUnlockThrottle] by a "kind" string, so a bug in one lockout
/// path can't silently corrupt the other's stored counters.
@visibleForTesting
class PinUnlockThrottle {
  static const _secure = AppSecureStorage.instance;

  static String _attemptsKey(String uri) => 'pin_unlock_failed_attempts_v1:$uri';
  static String _lockedUntilKey(String uri) => 'pin_unlock_locked_until_ms_v1:$uri';

  static const _tag = 'PinUnlockThrottle';
  static final _outage = _ThrottleOutageState();

  /// Writes [value] and reports whether it was really persisted.
  static Future<bool> _persist(String key, String value) async {
    try {
      return await _secure.writeVerified(key: key, value: value);
    } catch (e) {
      VeLog.e(_tag, 'secure storage write failed; keeping state in memory only', e);
      return false;
    }
  }

  /// Returns the remaining lockout duration for [uri], or null if it isn't
  /// currently locked out.
  static Future<Duration?> currentLockout(String uri) async {
    int? storedUntilMs;
    try {
      final raw = await _secure.read(key: _lockedUntilKey(uri));
      storedUntilMs = raw == null ? null : int.tryParse(raw);
    } catch (e) {
      // Don't lock the user out of their own vault over a storage glitch:
      // fail open on the persisted side, but still honour anything this
      // process already recorded in memory.
      VeLog.e(_tag, 'currentLockout: secure storage read failed; using in-memory state', e);
    }
    final untilMs = _laterOf(storedUntilMs, _outage.lockedUntilMs[uri]);
    if (untilMs == null) return null;
    final remaining = DateTime.fromMillisecondsSinceEpoch(untilMs).difference(DateTime.now());
    if (remaining.isNegative) {
      _outage.lockedUntilMs.remove(uri);
      if (storedUntilMs != null) {
        try {
          await _secure.delete(key: _lockedUntilKey(uri));
        } catch (e) {
          VeLog.e(_tag, 'currentLockout: could not clear an expired lockout', e);
        }
      }
      return null;
    }
    return remaining;
  }

  /// Records a failed attempt for [uri] and applies the same schedule as
  /// [PatternUnlockThrottle]/LockGateScreen: 30s at the 5th failure, +30s per additional failure,
  /// capped at 300s (reached at the 14th). Returns the new lockout duration
  /// once one is triggered, else null.
  ///
  /// If secure storage can't be read or written, the count and the lockout
  /// deadline are kept in memory instead (see [_ThrottleOutageState]).
  static Future<Duration?> recordFailure(String uri) async {
    var persistedAttempts = 0;
    var storageOk = true;
    try {
      persistedAttempts = int.tryParse(await _secure.read(key: _attemptsKey(uri)) ?? '') ?? 0;
    } catch (e) {
      storageOk = false;
      VeLog.e(_tag, 'recordFailure: secure storage read failed; counting in memory', e);
    }
    final carried = _outage.attempts[uri] ?? 0;
    final attempts = (persistedAttempts > carried ? persistedAttempts : carried) + 1;
    if (storageOk) storageOk = await _persist(_attemptsKey(uri), attempts.toString());
    if (storageOk) {
      _outage.attempts.remove(uri);
    } else {
      _outage.attempts[uri] = attempts;
    }

    if (attempts >= 5) {
      final excess = attempts - 4;
      final seconds = (30 * excess).clamp(30, 300);
      final untilMs = DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch;
      if (await _persist(_lockedUntilKey(uri), untilMs.toString())) {
        _outage.lockedUntilMs.remove(uri);
      } else {
        _outage.lockedUntilMs[uri] = untilMs;
      }
      return Duration(seconds: seconds);
    }
    return null;
  }

  /// Clears persisted lockout state for [uri] after a successful unlock.
  static Future<void> clear(String uri) async {
    _outage.clear(uri);
    for (final key in [_attemptsKey(uri), _lockedUntilKey(uri)]) {
      try {
        await _secure.delete(key: key);
      } catch (e) {
        // Best-effort, same reasoning as LockGateScreen._clearLockoutState():
        // a leftover stale entry here just self-corrects the next time
        // recordFailure()/clear() successfully writes.
        VeLog.e(_tag, 'clear: could not delete a persisted lockout entry', e);
      }
    }
  }
}
