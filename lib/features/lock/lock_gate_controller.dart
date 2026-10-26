import 'dart:async';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/biometric_auth_utils.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/biometric_enrollment_guard.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/features/lock/duress_settings_service.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'lock_gate_controller.g.dart';

const _kLogTag = 'LockGateController';

typedef _UnlockResult = ({
  int volId,
  List<String> files,
  int matchedCipherId,
  int matchedHashId,
  String containerFormat,
});

const _kDuressPurgeErrorMessage =
    'Decryption failed: Invalid credential. 2 attempts remaining.';

class LockGateState {
  final AppSettings? settings;
  final bool loading;
  final bool checking;
  final String? error;
  final DateTime? lockedUntil;

  final int navigateTick;
  final bool showPasswordFallback;

  final bool patternError;
  final int patternResetKey;
  final bool pinError;
  final int pinResetKey;

  final MountedContainer? decoyContainer;
  final int decoyNavigateTick;

  /// True when the gate had to switch biometric unlock off because the
  /// device's biometrics changed. The screen turns it into a message (it has
  /// the localizations; this controller's [LockGate._init] does not).
  final bool biometricsChanged;

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
    this.decoyContainer,
    this.decoyNavigateTick = 0,
    this.biometricsChanged = false,
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
    MountedContainer? decoyContainer,
    int? decoyNavigateTick,
    bool? biometricsChanged,
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
    decoyContainer: decoyContainer ?? state.decoyContainer,
    decoyNavigateTick: decoyNavigateTick ?? state.decoyNavigateTick,
    biometricsChanged: biometricsChanged ?? state.biometricsChanged,
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
    } catch (e) {
      VeLog.e(_kLogTag, 'Failed to load persisted lockout state', e);
    }
    if (ref.mounted && lockedUntil != null) {
      state = _copy(lockedUntil: lockedUntil);
    }
  }

  Future<void> _init() async {
    await _loadPersistedLockoutState();
    if (!ref.mounted) return;
    final s = await ref.read(appSettingsServiceProvider).loadSettings();
    if (!ref.mounted) return;

    await ref.read(secureScreenPolicyProvider).apply(
          preference: s.blockScreenshots,
        );

    if (!ref.mounted) return;
    if (!s.useMasterPassword) {
      _requestNavigateToDashboard();
      return;
    }
    if (s.masterPasswordHash == null) {
      // Defensive fallback: useMasterPassword is true but masterPasswordHash was purged.
      // Reset useMasterPassword to false and proceed.
      final reset = s.copyWith(useMasterPassword: false);
      await ref.read(appSettingsServiceProvider).saveSettings(reset);
      if (!ref.mounted) return;
      _requestNavigateToDashboard();
      return;
    }

    // A new fingerprint/face must never be able to reach the gate's biometric
    // prompt. Decide before the settings are published: the screen starts the
    // prompt on its own the moment it sees biometrics as the method, so by
    // then a changed device has to look like a password-only gate already.
    var gateSettings = s;
    var biometricsChanged = false;
    var passwordFallback = false;
    if (s.masterUnlockMethod == MasterUnlockMethod.biometrics) {
      final check = await _checkBiometricGuard();
      if (!ref.mounted) return;
      switch (check) {
        case BiometricGuardResult.ok:
          break;
        case BiometricGuardResult.reverted:
          biometricsChanged = true;
          gateSettings = await ref
              .read(appSettingsServiceProvider)
              .loadSettings();
          if (!ref.mounted) return;
        case BiometricGuardResult.unavailable:
          passwordFallback = true;
      }
    }
    state = _copy(
      settings: gateSettings,
      loading: false,
      biometricsChanged: biometricsChanged,
      showPasswordFallback: passwordFallback ? true : null,
    );
  }

  /// Asks the guard whether the master lock's biometric unlock may be used.
  /// A failure to ask counts as [BiometricGuardResult.unavailable] so the
  /// gate fails closed.
  Future<BiometricGuardResult> _checkBiometricGuard() async {
    try {
      return await ref.read(biometricEnrollmentGuardProvider).checkMaster();
    } catch (e) {
      VeLog.e(_kLogTag, 'Biometric enrollment check failed', e);
      return BiometricGuardResult.unavailable;
    }
  }

  /// Shows why the gate now asks for the password. Called by the screen when
  /// [LockGateState.biometricsChanged] turns on.
  void showBiometricsChangedNotice(AppLocalizations l10n) {
    if (!ref.mounted) return;
    state = _copy(error: l10n.biometricsChangedFallbackMessage);
  }

  /// Handles a non-ok guard result for [tryBiometric]: refreshes the gate to
  /// the password (reverted) or just offers it (unavailable). Returns true when
  /// biometrics may go ahead.
  Future<bool> _biometricsAllowed(AppLocalizations l10n) async {
    final check = await _checkBiometricGuard();
    if (!ref.mounted) return false;
    switch (check) {
      case BiometricGuardResult.ok:
        return true;
      case BiometricGuardResult.reverted:
        final refreshed = await ref
            .read(appSettingsServiceProvider)
            .loadSettings();
        if (!ref.mounted) return false;
        state = _copy(
          settings: refreshed,
          showPasswordFallback: true,
          biometricsChanged: true,
          error: l10n.biometricsChangedFallbackMessage,
        );
        return false;
      case BiometricGuardResult.unavailable:
        state = _copy(
          error: l10n.biometricNotAvailable,
          showPasswordFallback: true,
        );
        return false;
    }
  }

  Future<void> tryBiometric(AppLocalizations l10n) async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;
    try {
      if (!await _biometricsAllowed(l10n)) return;
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
      // Checked again after the prompt: only a gate whose biometrics are
      // still the ones it was set up with may open.
      if (ok && ref.mounted && await _biometricsAllowed(l10n)) {
        _requestNavigateToDashboard();
      }
    } on LocalAuthException catch (e) {
      final desc = e.description?.toLowerCase() ?? '';
      if (isBiometricCancellation(e.code.name, e.description)) return;
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
      if (isBiometricCancellation(e.code, e.message)) return;
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
    } catch (e) {
      VeLog.e(_kLogTag, 'Failed to persist lockout state', e);
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
    } catch (e) {
      VeLog.e(_kLogTag, 'Failed to clear persisted lockout state', e);
    }
    if (ref.mounted) {
      state = _copy(clearLockedUntil: true);
    }
  }

  Future<void> _runDuressPurge() async {
    final panicSettings =
        await ref.read(vaultPanicApiProvider).getPanicSettings();
    unawaited(
      ref
          .read(vaultPanicApiProvider)
          .triggerPanic(tier: panicSettings.configuredTier),
    );
    await Future<void>.delayed(const Duration(milliseconds: 3000));
  }

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
      _requestNavigateToDashboard();
      return false;
    }

    final duressService = ref.read(duressSettingsServiceProvider);
    if (await duressService.verifyPassword(pw)) {
      if (!ref.mounted) return false;
      await _runDuressPurge();
      if (!ref.mounted) return false;
      state = _copy(checking: false, error: _kDuressPurgeErrorMessage);
      return true;
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

    final duressService = ref.read(duressSettingsServiceProvider);
    if (await duressService.verifyPattern(pattern)) {
      if (!ref.mounted) return;
      await _runDuressPurge();
      if (!ref.mounted) return;
      state = _copy(patternError: true, error: _kDuressPurgeErrorMessage);
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

    final duressService = ref.read(duressSettingsServiceProvider);
    if (await duressService.verifyPin(pin)) {
      if (!ref.mounted) return;
      await _runDuressPurge();
      if (!ref.mounted) return;
      state = _copy(pinError: true, error: _kDuressPurgeErrorMessage);
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
