// LockGateScreen was a plain StatefulWidget holding domain/async state
// (settings, lockout counters, password verification, biometric auth)
// directly as State fields -- exactly what Guardrail #1 says to eliminate.
// TextEditingController + the obscure-text toggle stay as local State in
// the screen itself (genuinely ephemeral UI state, and a
// TextEditingController must be owned/disposed by a widget regardless).
//
// Navigation is the one thing this Notifier can't do directly (no
// BuildContext) -- `navigateTick` increments whenever the screen should
// move to the dashboard, and the widget reacts via `ref.listen` in
// `build()`, per the plan's "UI side-effects are driven by ref.listen()"
// rule. The same `ref.listen` also fires the one-time auto-biometric-
// prompt (when settings load with masterUnlockMethod == biometrics) --
// that needs an AppLocalizations, which the Notifier has no way to obtain
// on its own.
//
// Password, pattern, and PIN all share one lockout counter below rather
// than each getting their own (unlike ContainerRepository's per-uri
// PatternUnlockThrottle/PinUnlockThrottle) -- there's only ever one app,
// so a wrong attempt on any quick-unlock method should count against the
// same cooldown as a wrong master password.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_panic_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/features/lock/duress_settings_service.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'lock_gate_controller.g.dart';

const _kLogTag = 'LockGateController';

/// Shape shared by every VaultLifecycleApi unlock* method (unlockContainer,
/// unlockCryptomatorVault, unlockGocryptfsVault, unlockCryfsVault) --
/// declared once here so [LockGate._unlockDecoyContainer] doesn't have to
/// repeat it per format branch.
typedef _UnlockResult = ({
  int volId,
  List<String> files,
  int matchedCipherId,
  int matchedHashId,
  String containerFormat,
});

/// Authentication error shown after a Tier 2 duress purge -- deliberately
/// worded like a generic decryption failure rather than reusing this
/// screen's normal l10n wrong-password copy (see LockGateController's
/// `_handleDuressPurge`): the whole point is that it reads as *some*
/// unremarkable failure, not specifically as this app's own familiar
/// "incorrect password" message, to someone who may already recognize that
/// phrasing from earlier, genuine attempts in the same coerced session.
const _kDuressPurgeErrorMessage =
    'Decryption failed: Invalid PIN. 2 attempts remaining.';

class LockGateState {
  final AppSettings? settings;
  final bool loading;
  final bool checking;
  final String? error;
  final DateTime? lockedUntil;

  /// Bumped whenever the screen should navigate to the dashboard; the
  /// widget's `ref.listen` fires on any increase.
  final int navigateTick;

  /// True once the person has tapped "use password instead" while the
  /// configured method is biometrics/pattern/pin. One-directional for the
  /// lifetime of this gate, mirroring UnlockState.showPasswordFallback.
  final bool showPasswordFallback;

  final bool patternError;
  final int patternResetKey;
  final bool pinError;
  final int pinResetKey;

  const LockGateState({
    this.settings,
    this.loading = true,
    this.checking = false,
    this.error,
    this.lockedUntil,
    this.navigateTick = 0,
    this.showPasswordFallback = false,
    this.patternError = false,
    this.patternResetKey = 0,
    this.pinError = false,
    this.pinResetKey = 0,
  });

  Duration? get lockoutRemaining {
    final until = lockedUntil;
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  bool get isLockedOut => lockoutRemaining != null;
}

@riverpod
class LockGate extends _$LockGate {
  AppSecureStorage get _secure => ref.read(appSecureStorageProvider);
  static const _kFailedAttempts = 'lock_gate_failed_attempts_v1';
  static const _kLockedUntilMs = 'lock_gate_locked_until_ms_v1';

  final _localAuth = LocalAuthentication();
  bool _isAuthenticating = false;
  int _failedAttempts = 0;

  @override
  LockGateState build() {
    _init();
    return const LockGateState();
  }

  LockGateState _copy({
    AppSettings? settings,
    bool? loading,
    bool? checking,
    String? error,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
    int? navigateTick,
    bool? showPasswordFallback,
    bool? patternError,
    int? patternResetKey,
    bool? pinError,
    int? pinResetKey,
  }) => LockGateState(
    settings: settings ?? state.settings,
    loading: loading ?? state.loading,
    checking: checking ?? state.checking,
    error: error,
    lockedUntil: clearLockedUntil ? null : (lockedUntil ?? state.lockedUntil),
    navigateTick: navigateTick ?? state.navigateTick,
    showPasswordFallback: showPasswordFallback ?? state.showPasswordFallback,
    patternError: patternError ?? state.patternError,
    patternResetKey: patternResetKey ?? state.patternResetKey,
    pinError: pinError ?? state.pinError,
    pinResetKey: pinResetKey ?? state.pinResetKey,
  );

  void _requestNavigateToDashboard() {
    state = _copy(navigateTick: state.navigateTick + 1);
  }

  void setShowPasswordFallback(bool show) =>
      state = _copy(showPasswordFallback: show);

  Future<void> _loadPersistedLockoutState() async {
    DateTime? lockedUntil;
    try {
      final storedAttempts = await _secure.read(key: _kFailedAttempts);
      final storedUntilMs = await _secure.read(key: _kLockedUntilMs);
      _failedAttempts = int.tryParse(storedAttempts ?? '') ?? 0;
      if (storedUntilMs != null) {
        final ms = int.tryParse(storedUntilMs);
        if (ms != null) {
          lockedUntil = DateTime.fromMillisecondsSinceEpoch(ms);
          if (lockedUntil.isBefore(DateTime.now())) {
            lockedUntil = null;
            await _secure.delete(key: _kLockedUntilMs);
          }
        }
      }
    } catch (_) {
      // Fails open: if secure storage can't be read, lockout state stays at
      // its in-memory defaults (0 failed attempts, no active lockout)
      // rather than blocking the unlock screen from loading.
    }
    if (ref.mounted && lockedUntil != null) {
      state = _copy(lockedUntil: lockedUntil);
    }
  }

  Future<void> _init() async {
    await _loadPersistedLockoutState();
    final s = await ref.read(appSettingsServiceProvider).loadSettings();

    // Re-apply screenshot policy when entering the lock gate.
    await ref.read(secureScreenPolicyProvider).apply(
          preference: s.blockScreenshots,
        );

    if (!ref.mounted) return;
    if (!s.useMasterPassword || s.masterPasswordHash == null) {
      // Stay in `loading: true` (the widget shows the spinner) until the
      // navigate-away actually happens -- there's no settings to render a
      // password field for on this path.
      _requestNavigateToDashboard();
      return;
    }
    state = _copy(settings: s, loading: false);
  }

  Future<void> tryBiometric(AppLocalizations l10n) async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) {
        if (ref.mounted) {
          state = _copy(
            error: l10n.biometricNotAvailable,
            showPasswordFallback: true,
          );
        }
        return;
      }
      final ok = await _localAuth.authenticate(
        localizedReason: l10n.unlockVaultExplorerReason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (ok && ref.mounted) _requestNavigateToDashboard();
    } on LocalAuthException catch (e) {
      final desc = e.description?.toLowerCase() ?? '';
      if (e.code.name.toLowerCase().contains('progress') ||
          desc.contains('progress')) {
        return;
      }
      if (ref.mounted) {
        state = _copy(
          error: l10n.biometricErrorWithCode(e.code.name),
          showPasswordFallback: true,
        );
      }
    } on PlatformException catch (e) {
      if (e.code == 'auth_in_progress' ||
          e.code == 'AuthenticationInProgress' ||
          (e.message?.contains('Authentication in progress') ?? false)) {
        return;
      }
      if (ref.mounted) {
        state = _copy(
          error: l10n.biometricErrorWithCode(e.message ?? ''),
          showPasswordFallback: true,
        );
      }
    } finally {
      _isAuthenticating = false;
    }
  }

  Future<void> _recordFailure() async {
    _failedAttempts++;
    DateTime? lockedUntil = state.lockedUntil;
    if (_failedAttempts >= 5) {
      final excess = _failedAttempts - 4;
      final seconds = (30 * excess).clamp(30, 300);
      lockedUntil = DateTime.now().add(Duration(seconds: seconds));
    }
    try {
      await _secure.write(
        key: _kFailedAttempts,
        value: _failedAttempts.toString(),
      );
      if (lockedUntil != null) {
        await _secure.write(
          key: _kLockedUntilMs,
          value: lockedUntil.millisecondsSinceEpoch.toString(),
        );
      }
    } catch (_) {
      // Best-effort persistence: the in-memory counters above already took
      // effect for this session even if the write fails.
    }
    if (ref.mounted) {
      state = _copy(lockedUntil: lockedUntil);
    }
  }

  Future<void> _clearLockoutState() async {
    _failedAttempts = 0;
    try {
      await _secure.delete(key: _kFailedAttempts);
      await _secure.delete(key: _kLockedUntilMs);
    } catch (_) {
      // Best-effort: in-memory state is already cleared.
    }
    if (ref.mounted) {
      state = _copy(clearLockedUntil: true);
    }
  }

  void _upgradeMasterPasswordHashInBackground(AppSettings s, String pw) {
    // Resolved eagerly (while `ref` is still live) rather than inside the
    // `.then()` below -- this callback can fire after the notifier itself
    // is disposed (user navigated off the lock gate mid-hash-upgrade), and
    // `ref.read` throws once that happens. `AppSettingsService` holds no
    // state of its own, so capturing it now and using it later is safe.
    final appSettingsService = ref.read(appSettingsServiceProvider);
    final passwordHasher = ref.read(passwordHasherProvider);
    passwordHasher
        .deriveHash(pw)
        .then((result) async {
          await appSettingsService.saveMasterPassword(
            s,
            result.hash,
            result.salt,
          );
        })
        .catchError((_) {});
  }

  /// Returns true only when the password was actually wrong (i.e. the
  /// widget should clear the password field) -- false for every other
  /// path (locked out, empty field, or success-and-navigating-away),
  /// exactly matching the pre-Riverpod screen's `_pwCtrl.clear()` calls.
  Future<bool> checkPassword(String pw, AppLocalizations l10n) async {
    final s = state.settings;
    if (s == null) return false;
    final lockout = state.lockoutRemaining;
    if (lockout != null) {
      state = _copy(error: l10n.tooManyFailedAttempts(lockout.inSeconds));
      return false;
    }
    if (pw.isEmpty) {
      state = _copy(error: l10n.enterMasterPasswordPrompt);
      return false;
    }
    final passwordHasher = ref.read(passwordHasherProvider);
    state = _copy(checking: true, error: null);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!ref.mounted) return false;
    final ok = await passwordHasher.verify(
      candidate: pw,
      hash: s.masterPasswordHash,
      salt: s.masterPasswordSalt,
    );
    if (!ref.mounted) return false;
    if (ok) {
      await _clearLockoutState();
      if (s.needsHashUpgrade) {
        _upgradeMasterPasswordHashInBackground(s, pw);
      }
      _requestNavigateToDashboard();
      return false;
    }
    HapticFeedback.heavyImpact();
    await _recordFailure();
    if (!ref.mounted) return false;
    final newLockout = state.lockoutRemaining;
    state = _copy(
      checking: false,
      error: newLockout != null
          ? l10n.incorrectPasswordLockedFor(
              newLockout.inSeconds,
              _failedAttempts,
            )
          : l10n.incorrectPasswordAttempts(_failedAttempts),
    );
    return true;
  }

  /// Verifies a drawn pattern against [AppSettings.masterPatternHash]. On
  /// success this bypasses the real master password entirely -- same
  /// relationship [tryBiometric] already has to it -- and shares this
  /// gate's single lockout counter with the password and PIN paths.
  Future<void> onPatternComplete(List<int> pattern, AppLocalizations l10n) async {
    final s = state.settings;
    if (s == null) return;
    if (s.masterPatternHash == null) {
      state = _copy(
        error: l10n.noPatternConfiguredMessage,
        showPasswordFallback: true,
      );
      return;
    }
    final lockout = state.lockoutRemaining;
    if (lockout != null) {
      state = _copy(
        error: l10n.tooManyFailedAttempts(lockout.inSeconds),
        patternError: true,
      );
      Future.delayed(const Duration(milliseconds: 800), () {
        if (ref.mounted) {
          state = _copy(
            patternError: false,
            patternResetKey: state.patternResetKey + 1,
          );
        }
      });
      return;
    }

    final cryptoApi = ref.read(vaultCryptoApiProvider);
    final ok = await verifyPattern(cryptoApi, pattern, s.masterPatternHash);
    if (!ref.mounted) return;
    if (ok) {
      await _clearLockoutState();
      if (!ref.mounted) return;
      _requestNavigateToDashboard();
      return;
    }
    HapticFeedback.heavyImpact();
    await _recordFailure();
    if (!ref.mounted) return;
    final newLockout = state.lockoutRemaining;
    state = newLockout != null
        ? _copy(
            patternError: true,
            error: l10n.tooManyFailedAttempts(newLockout.inSeconds),
          )
        : _copy(patternError: true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (ref.mounted) {
        state = _copy(
          patternError: false,
          patternResetKey: state.patternResetKey + 1,
        );
      }
    });
  }

  /// Verifies a PIN against [AppSettings.masterPinHash]; mirrors
  /// [onPatternComplete] exactly, one credential type over.
  Future<void> onPinComplete(String pin, AppLocalizations l10n) async {
    final s = state.settings;
    if (s == null) return;
    if (s.masterPinHash == null) {
      state = _copy(
        error: l10n.noPinConfiguredMessage,
        showPasswordFallback: true,
      );
      return;
    }
    final lockout = state.lockoutRemaining;
    if (lockout != null) {
      state = _copy(
        error: l10n.tooManyFailedAttempts(lockout.inSeconds),
        pinError: true,
      );
      Future.delayed(const Duration(milliseconds: 800), () {
        if (ref.mounted) {
          state = _copy(
            pinError: false,
            pinResetKey: state.pinResetKey + 1,
          );
        }
      });
      return;
    }

    final cryptoApi = ref.read(vaultCryptoApiProvider);
    final ok = await verifyPin(cryptoApi, pin, s.masterPinHash);
    if (!ref.mounted) return;
    if (ok) {
      await _clearLockoutState();
      if (!ref.mounted) return;
      _requestNavigateToDashboard();
      return;
    }
    HapticFeedback.heavyImpact();
    await _recordFailure();
    if (!ref.mounted) return;
    final newLockout = state.lockoutRemaining;
    state = newLockout != null
        ? _copy(
            pinError: true,
            error: l10n.tooManyFailedAttempts(newLockout.inSeconds),
          )
        : _copy(pinError: true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (ref.mounted) {
        state = _copy(
          pinError: false,
          pinResetKey: state.pinResetKey + 1,
        );
      }
    });
  }
}