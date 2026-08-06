import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

import 'unlock_biometric_source.dart';

/// Shared biometric/pattern-unlock logic for `UnlockSheet` and
/// `UsbUnlockSheet`, extracted per docs/td7-unlock-flow-design.md.
///
/// Deliberately narrow: only `_dismissKeyboard`, `_tryBiometric`, and
/// `_onPatternComplete` moved here. `_unlock()` and `_initUnlockMethod()`
/// stay in each host file untouched -- both have enough non-shared logic
/// (format branching; document-existence/relocation vs.
/// device-load/reconnect-gating, respectively) that merging them risked
/// exactly the kind of subtle slip this extraction is trying to avoid. See
/// the design doc for the full reasoning.
///
/// The get/set pairs below exist because Dart's privacy is per-library: a
/// mixin declared in its own file cannot read or write a private field
/// (`_error`, `_isAuthenticating`, etc.) declared in `unlock_sheet.dart` or
/// `usb_unlock_sheet.dart`'s own library, even once mixed in. Each host
/// keeps its existing private fields exactly as they were -- used for many
/// things beyond biometric/pattern unlock -- and forwards to them here
/// explicitly, rather than this mixin owning new fields of its own that
/// would then need to be kept in sync with the host's.
mixin UnlockBiometricMixin<T extends StatefulWidget> on State<T> {
  UnlockBiometricSource get unlockSource;

  bool get isAuthenticating;
  set isAuthenticating(bool value);

  String? get unlockError;
  set unlockError(String? value);

  bool get showPasswordFallback;
  set showPasswordFallback(bool value);

  bool get patternError;
  set patternError(bool value);

  int get patternResetKey;
  set patternResetKey(int value);

  String? get storedPatternHash;

  TextEditingController get passwordCtrl;

  /// Forwards to the host's own (unmerged, format-specific) `_unlock()`.
  Future<void> performUnlock({
    Uint8List? preservedKey,
    bool? shouldCacheDerivedKeyOverride,
    String? passwordOverride,
    List<String>? keyfilePathsOverride,
  });

  /// Dismisses the on-screen keyboard (ADR-020). Called whenever the user
  /// interacts with a control other than the password/PIM text fields —
  /// read-only, remember-container/drive, the advanced-parameters header,
  /// or a tap on empty space — while one of those fields still has focus.
  /// Cheap no-op if nothing is focused, so every call site can invoke it
  /// unconditionally rather than checking focus state first.
  void dismissKeyboard() => FocusScope.of(context).unfocus();

  Future<void> tryBiometric() async {
    if (isAuthenticating) return;
    isAuthenticating = true;
    final source = unlockSource;
    final readiness = source.preAuthReadiness;
    if (!readiness.ready) {
      isAuthenticating = false;
      if (readiness.blockMessage != null && mounted) {
        setState(() => unlockError = readiness.blockMessage);
      }
      return;
    }

    try {
      final localAuth = LocalAuthentication();
      final canCheck = await localAuth.canCheckBiometrics;
      final isSupported = await localAuth.isDeviceSupported();

      if (!canCheck || !isSupported) {
        if (mounted) {
          setState(() {
            unlockError = context.l10n.biometricNotAvailable;
            showPasswordFallback = true;
          });
        }
        return;
      }

      final ok = await localAuth.authenticate(
        localizedReason: 'Authenticate to unlock ${source.biometricPromptSubject}',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (ok && mounted) {
        final record = await source.resolveRecord();

        final appSettings = await AppSettingsService.loadSettings();
        final shouldCacheGoingForward =
            (record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled;
        final shouldPreloadCachedKey = record?.cacheDerivedKey ?? false;

        final deriveId = source.derivedKeyIdentifier;
        final cachedKey = shouldPreloadCachedKey && deriveId != null
            ? await vaultExplorerApi.loadDerivedKey(deriveId)
            : null;

        debugPrint(
          '${source.debugLogTag}: biometric cached-key present='
          '${cachedKey != null && cachedKey.isNotEmpty} for ${source.containerUri}',
        );

        if (cachedKey != null && cachedKey.isNotEmpty) {
          await performUnlock(
            preservedKey: cachedKey,
            shouldCacheDerivedKeyOverride: shouldCacheGoingForward,
          );
          return;
        }

        final pw = await ContainerRepository.instance.getPassword(source.containerUri);
        final savedKeyfiles = record?.keyfiles ?? [];
        final savedKeyfilePaths = savedKeyfiles.map((k) => k['uri']!).toList();
        if (pw != null || savedKeyfilePaths.isNotEmpty) {
          passwordCtrl.text = pw ?? '';
          await performUnlock(
            shouldCacheDerivedKeyOverride: shouldCacheGoingForward,
            passwordOverride: pw ?? '',
            keyfilePathsOverride: savedKeyfilePaths,
          );
        } else {
          setState(() {
            unlockError = source.noSavedCredentialsForBiometricMessage;
            showPasswordFallback = true;
          });
        }
      }
    } on LocalAuthException catch (e) {
      final desc = e.description?.toLowerCase() ?? '';
      if (e.code.name.toLowerCase().contains('progress') || desc.contains('progress')) {
        return;
      }
      if (mounted) {
        setState(() {
          unlockError = context.l10n.biometricErrorWithCode(e.code.name);
          showPasswordFallback = true;
        });
      }
    } on PlatformException catch (e) {
      if (e.code == 'auth_in_progress' ||
          e.code == 'AuthenticationInProgress' ||
          (e.message?.contains('Authentication in progress') ?? false)) {
        return;
      }
      if (mounted) {
        setState(() {
          unlockError = context.l10n.biometricErrorWithCode(e.message ?? '');
          showPasswordFallback = true;
        });
      }
    } finally {
      isAuthenticating = false;
    }
  }

  Future<void> onPatternComplete(List<int> pattern) async {
    final source = unlockSource;
    if (!source.isReadyForPattern) return;

if (storedPatternHash == null) {
      setState(() {
        unlockError = context.l10n.noPatternConfiguredMessage;
        showPasswordFallback = true;
      });
      return;
    }
    final lockout = await _PatternUnlockThrottle.currentLockout(source.containerUri);
    if (lockout != null) {
      setState(() {
        unlockError = context.l10n.tooManyFailedAttempts(lockout.inSeconds);
        patternError = true;
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            patternError = false;
            patternResetKey = patternResetKey + 1;
          });
        }
      });
      return;
    }

    final matched = await verifyPattern(pattern, storedPatternHash);
    if (matched) {
      await _PatternUnlockThrottle.clear(source.containerUri);
      final record = await source.resolveRecord();

      final appSettings = await AppSettingsService.loadSettings();
      final shouldCacheGoingForward =
          (record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled;
      final shouldPreloadCachedKey = record?.cacheDerivedKey ?? false;

      final deriveId = source.derivedKeyIdentifier;
      final cachedKey = shouldPreloadCachedKey && deriveId != null
          ? await vaultExplorerApi.loadDerivedKey(deriveId)
          : null;

      debugPrint(
        '${source.debugLogTag}: pattern cached-key present='
        '${cachedKey != null && cachedKey.isNotEmpty} for ${source.containerUri}',
      );

      if (cachedKey != null && cachedKey.isNotEmpty) {
        await performUnlock(preservedKey: cachedKey, shouldCacheDerivedKeyOverride: shouldCacheGoingForward);
        return;
      }

      final pw = await ContainerRepository.instance.getPassword(source.containerUri);
      final savedKeyfiles = record?.keyfiles ?? [];
      final savedKeyfilePaths = savedKeyfiles.map((k) => k['uri']!).toList();
      if (pw != null || savedKeyfilePaths.isNotEmpty) {
        passwordCtrl.text = pw ?? '';
        await performUnlock(
          shouldCacheDerivedKeyOverride: shouldCacheGoingForward,
          passwordOverride: pw ?? '',
          keyfilePathsOverride: savedKeyfilePaths,
        );
      } else {
        setState(() {
          unlockError = source.noSavedCredentialsForPatternMessage;
          showPasswordFallback = true;
        });
      }
    } else {
      final newLockout = await _PatternUnlockThrottle.recordFailure(source.containerUri);
      setState(() {
        patternError = true;
        if (newLockout != null) {
          unlockError = context.l10n.patternLockedForSeconds(newLockout.inSeconds);
        }
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            patternError = false;
            patternResetKey = patternResetKey + 1;
          });
        }
      });
    }
  }
}

/// Per-container, persisted exponential-backoff lockout for pattern-unlock
/// attempts. Mirrors `LockGateScreen`'s master-password lockout (same
/// thresholds/schedule) because a correct pattern here grants the same
/// access to the vault's derived key that a correct master password does
/// -- it deserves the same brute-force protection. Keyed by container URI
/// so each vault's lockout state is independent of the others'.
class _PatternUnlockThrottle {
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
  /// LockGateScreen: 5 failures -> 30s, 6 -> 60s, 7 -> 120s, 8+ -> 300s.
  /// Returns the new lockout duration once one is triggered, else null.
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
    } catch (_) {}
  }
}