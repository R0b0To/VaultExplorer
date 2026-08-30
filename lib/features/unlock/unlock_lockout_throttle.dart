import 'package:meta/meta.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';

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

  /// Returns the remaining lockout duration for [uri], or null if it isn't
  /// currently locked out.
  static Future<Duration?> currentLockout(String uri) async {
    try {
      final storedUntilMs = await _secure.read(key: _lockedUntilKey(uri));
      if (storedUntilMs == null) return null;
      final ms = int.tryParse(storedUntilMs);
      if (ms == null) return null;
      final remaining = DateTime.fromMillisecondsSinceEpoch(ms).difference(DateTime.now());
      if (remaining.isNegative) {
        await _secure.delete(key: _lockedUntilKey(uri));
        return null;
      }
      return remaining;
    } catch (_) {
      // If secure storage read fails, don't lock the user out of their own
      // vault over a storage glitch -- fail open on this side only.
      return null;
    }
  }

  /// Records a failed attempt for [uri] and applies the same schedule as
  /// LockGateScreen: 30s at the 5th failure, +30s per additional failure,
  /// capped at 300s (reached at the 14th). Returns the new lockout
  /// duration once one is triggered, else null.
  static Future<Duration?> recordFailure(String uri) async {
    try {
      final stored = await _secure.read(key: _attemptsKey(uri));
      final attempts = (int.tryParse(stored ?? '') ?? 0) + 1;
      await _secure.write(key: _attemptsKey(uri), value: attempts.toString());

      if (attempts >= 5) {
        final excess = attempts - 4;
        final seconds = (30 * excess).clamp(30, 300);
        final until = DateTime.now().add(Duration(seconds: seconds));
        await _secure.write(
          key: _lockedUntilKey(uri),
          value: until.millisecondsSinceEpoch.toString(),
        );
        return Duration(seconds: seconds);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Clears persisted lockout state for [uri] after a successful unlock.
  static Future<void> clear(String uri) async {
    try {
      await _secure.delete(key: _attemptsKey(uri));
      await _secure.delete(key: _lockedUntilKey(uri));
    } catch (_) {
      // Best-effort, same reasoning as LockGateScreen._clearLockoutState():
      // a leftover stale entry here just self-corrects the next time
      // recordFailure()/clear() successfully writes.
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

  /// Returns the remaining lockout duration for [uri], or null if it isn't
  /// currently locked out.
  static Future<Duration?> currentLockout(String uri) async {
    try {
      final storedUntilMs = await _secure.read(key: _lockedUntilKey(uri));
      if (storedUntilMs == null) return null;
      final ms = int.tryParse(storedUntilMs);
      if (ms == null) return null;
      final remaining = DateTime.fromMillisecondsSinceEpoch(ms).difference(DateTime.now());
      if (remaining.isNegative) {
        await _secure.delete(key: _lockedUntilKey(uri));
        return null;
      }
      return remaining;
    } catch (_) {
      // If secure storage read fails, don't lock the user out of their own
      // vault over a storage glitch -- fail open on this side only.
      return null;
    }
  }

  /// Records a failed attempt for [uri] and applies the same schedule as
  /// [PatternUnlockThrottle]/LockGateScreen: 30s at the 5th failure, +30s
  /// per additional failure, capped at 300s (reached at the 14th). Returns
  /// the new lockout duration once one is triggered, else null.
  static Future<Duration?> recordFailure(String uri) async {
    try {
      final stored = await _secure.read(key: _attemptsKey(uri));
      final attempts = (int.tryParse(stored ?? '') ?? 0) + 1;
      await _secure.write(key: _attemptsKey(uri), value: attempts.toString());

      if (attempts >= 5) {
        final excess = attempts - 4;
        final seconds = (30 * excess).clamp(30, 300);
        final until = DateTime.now().add(Duration(seconds: seconds));
        await _secure.write(
          key: _lockedUntilKey(uri),
          value: until.millisecondsSinceEpoch.toString(),
        );
        return Duration(seconds: seconds);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Clears persisted lockout state for [uri] after a successful unlock.
  static Future<void> clear(String uri) async {
    try {
      await _secure.delete(key: _attemptsKey(uri));
      await _secure.delete(key: _lockedUntilKey(uri));
    } catch (_) {
      // Same reasoning as PatternUnlockThrottle.clear() above.
    }
  }
}
