import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';
import 'package:vaultexplorer/features/unlock/unlock_lockout_throttle.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'usb_unlock_controller.g.dart';

@immutable
class UsbUnlockParams {
  final ContainerRecord? existingRecord;
  final String? prefillPassword;
  final bool documentProvider;
  final List<String> autoMountFolders;
  final List<String> mountedUris;

  const UsbUnlockParams({
    this.existingRecord,
    this.prefillPassword,
    this.documentProvider = false,
    this.autoMountFolders = const [],
    this.mountedUris = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsbUnlockParams &&
          other.existingRecord == existingRecord &&
          other.prefillPassword == prefillPassword &&
          other.documentProvider == documentProvider &&
          listEquals(other.autoMountFolders, autoMountFolders) &&
          listEquals(other.mountedUris, mountedUris);

  @override
  int get hashCode => Object.hash(
        existingRecord,
        prefillPassword,
        documentProvider,
        Object.hashAll(autoMountFolders),
        Object.hashAll(mountedUris),
      );
}

class UsbUnlockState {
  final List<UsbDeviceInfo> devices;
  final UsbDeviceInfo? selected;
  final bool loadingDevices;
  final bool requestingPermission;
  final bool loading;
  final bool readOnly;
  final bool remember;
  final String? error;
  final int cipherId;
  final int hashId;
  final String containerFormat;

  final bool protectHiddenVolume;
  final int hiddenCipherId;
  final int hiddenHashId;

  final List<KeyfileRef> keyfiles;
  final bool pickingKeyfiles;
  final List<KeyfileRef> hiddenKeyfiles;
  final bool pickingHiddenKeyfiles;

  final int? activeVolId;
  final UnlockProgress? progress;

  final ContainerUnlockMethod unlockMethod;
  final bool showPasswordFallback;
  final bool patternError;
  final int patternResetKey;
  final String? storedPatternHash;
  final bool pinError;
  final int pinResetKey;
  final String? storedPinHash;
  final bool loadingAuth;
  final bool reconnectTargetMissing;
  final bool isAuthenticating;

  /// Bumped when the controller determines biometric auth should
  /// auto-fire. Mirrors [UnlockState.biometricAutoTriggerTick] -- see that
  /// field's doc for why the widget, not the controller, calls
  /// `tryBiometric` in response.
  final int biometricAutoTriggerTick;

  final ({
    MountedContainer container,
    ContainerRecord? record,
    String? oldUri,
  })? mountedSuccess;

  const UsbUnlockState({
    this.devices = const [],
    this.selected,
    this.loadingDevices = true,
    this.requestingPermission = false,
    this.loading = false,
    this.readOnly = false,
    this.remember = false,
    this.error,
    this.cipherId = 255,
    this.hashId = 255,
    this.containerFormat = 'veracrypt',
    this.protectHiddenVolume = false,
    this.hiddenCipherId = 255,
    this.hiddenHashId = 255,
    this.keyfiles = const [],
    this.pickingKeyfiles = false,
    this.hiddenKeyfiles = const [],
    this.pickingHiddenKeyfiles = false,
    this.activeVolId,
    this.progress,
    this.unlockMethod = ContainerUnlockMethod.password,
    this.showPasswordFallback = false,
    this.patternError = false,
    this.patternResetKey = 0,
    this.storedPatternHash,
    this.pinError = false,
    this.pinResetKey = 0,
    this.storedPinHash,
    this.loadingAuth = true,
    this.reconnectTargetMissing = false,
    this.isAuthenticating = false,
    this.biometricAutoTriggerTick = 0,
    this.mountedSuccess,
  });

  UsbUnlockState _copy({
    List<UsbDeviceInfo>? devices,
    UsbDeviceInfo? selected,
    bool clearSelected = false,
    bool? loadingDevices,
    bool? requestingPermission,
    bool? loading,
    bool? readOnly,
    bool? remember,
    String? error,
    bool clearError = false,
    int? cipherId,
    int? hashId,
    String? containerFormat,
    bool? protectHiddenVolume,
    int? hiddenCipherId,
    int? hiddenHashId,
    List<KeyfileRef>? keyfiles,
    bool? pickingKeyfiles,
    List<KeyfileRef>? hiddenKeyfiles,
    bool? pickingHiddenKeyfiles,
    int? activeVolId,
    bool clearActiveVolId = false,
    UnlockProgress? progress,
    bool clearProgress = false,
    ContainerUnlockMethod? unlockMethod,
    bool? showPasswordFallback,
    bool? patternError,
    int? patternResetKey,
    String? storedPatternHash,
    bool? pinError,
    int? pinResetKey,
    String? storedPinHash,
    bool? loadingAuth,
    bool? reconnectTargetMissing,
    bool? isAuthenticating,
    int? biometricAutoTriggerTick,
    ({MountedContainer container, ContainerRecord? record, String? oldUri})? mountedSuccess,
  }) => UsbUnlockState(
    devices: devices ?? this.devices,
    selected: clearSelected ? null : (selected ?? this.selected),
    loadingDevices: loadingDevices ?? this.loadingDevices,
    requestingPermission: requestingPermission ?? this.requestingPermission,
    loading: loading ?? this.loading,
    readOnly: readOnly ?? this.readOnly,
    remember: remember ?? this.remember,
    error: clearError ? null : (error ?? this.error),
    cipherId: cipherId ?? this.cipherId,
    hashId: hashId ?? this.hashId,
    containerFormat: containerFormat ?? this.containerFormat,
    protectHiddenVolume: protectHiddenVolume ?? this.protectHiddenVolume,
    hiddenCipherId: hiddenCipherId ?? this.hiddenCipherId,
    hiddenHashId: hiddenHashId ?? this.hiddenHashId,
    keyfiles: keyfiles ?? this.keyfiles,
    pickingKeyfiles: pickingKeyfiles ?? this.pickingKeyfiles,
    hiddenKeyfiles: hiddenKeyfiles ?? this.hiddenKeyfiles,
    pickingHiddenKeyfiles: pickingHiddenKeyfiles ?? this.pickingHiddenKeyfiles,
    activeVolId: clearActiveVolId ? null : (activeVolId ?? this.activeVolId),
    progress: clearProgress ? null : (progress ?? this.progress),
    unlockMethod: unlockMethod ?? this.unlockMethod,
    showPasswordFallback: showPasswordFallback ?? this.showPasswordFallback,
    patternError: patternError ?? this.patternError,
    patternResetKey: patternResetKey ?? this.patternResetKey,
    storedPatternHash: storedPatternHash ?? this.storedPatternHash,
    pinError: pinError ?? this.pinError,
    pinResetKey: pinResetKey ?? this.pinResetKey,
    storedPinHash: storedPinHash ?? this.storedPinHash,
    loadingAuth: loadingAuth ?? this.loadingAuth,
    reconnectTargetMissing: reconnectTargetMissing ?? this.reconnectTargetMissing,
    isAuthenticating: isAuthenticating ?? this.isAuthenticating,
    biometricAutoTriggerTick: biometricAutoTriggerTick ?? this.biometricAutoTriggerTick,
    mountedSuccess: mountedSuccess ?? this.mountedSuccess,
  );
}

@riverpod
class UsbUnlockController extends _$UsbUnlockController {
  late final void Function(int) _onUnlockStarted;
  late final void Function(UnlockProgress) _onUnlockProgress;
  int? _trackedActiveVolId;

  @override
  UsbUnlockState build(UsbUnlockParams params) {
    final record = params.existingRecord;
    final initial = UsbUnlockState(
      cipherId: record?.cipherId ?? 255,
      hashId: record?.hashId ?? 255,
      containerFormat: record?.containerFormat ?? 'veracrypt',
      remember: record != null,
      loadingDevices: true,
      loadingAuth: true,
    );

    final lifecycle = ref.read(vaultLifecycleApiProvider);
    final events = ref.read(vaultEngineEventsProvider);

    _onUnlockStarted = (volId) {
      _trackedActiveVolId = volId;
      if (ref.mounted) state = state._copy(activeVolId: volId);
    };
    _onUnlockProgress = (progress) {
      if (ref.mounted && progress.volId == state.activeVolId) {
        state = state._copy(
          progress: progress,
          containerFormat: (progress.containerFormat.isNotEmpty && progress.containerFormat != 'unknown')
              ? progress.containerFormat
              : state.containerFormat,
        );
      }
    };

    events.addUnlockStartedListener(_onUnlockStarted);
    events.addUnlockProgressListener(_onUnlockProgress);

    ref.onDispose(() {
      if (_trackedActiveVolId != null) {
        lifecycle.cancelUnlock(_trackedActiveVolId!);
      }
      events.removeUnlockStartedListener(_onUnlockStarted);
      events.removeUnlockProgressListener(_onUnlockProgress);
    });

    Future.microtask(() async {
      await loadDevices();
      await _initAuth(params);
    });

    return initial;
  }

  Future<void> loadDevices() async {
    state = state._copy(loadingDevices: true, clearError: true);
    try {
      final devices = await ref.read(vaultLifecycleApiProvider).listUsbDevices();
      if (!ref.mounted) return;

      UsbDeviceInfo? matchedSelected;
      bool targetMissing = false;

      final expected = _expectedDeviceName;
      if (expected != null) {
        final matches = devices.where((d) => d.deviceName == expected);
        matchedSelected = matches.isEmpty ? null : matches.first;
        targetMissing = matches.isEmpty;
      } else if (devices.length == 1) {
        final d = devices.first;
        final isMounted = params.mountedUris.contains('usb:${d.deviceName}');
        matchedSelected = isMounted ? null : d;
      }

      state = state._copy(
        devices: devices,
        selected: matchedSelected,
        reconnectTargetMissing: targetMissing,
        loadingDevices: false,
      );
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(loadingDevices: false, error: '$e');
      }
    }
  }

  String? get _expectedDeviceName {
    final uri = params.existingRecord?.uri;
    if (uri == null || !uri.startsWith('usb:')) return null;
    return uri.substring(4);
  }

  Future<void> _initAuth(UsbUnlockParams params) async {
    final record = params.existingRecord;
    if (record == null) {
      state = state._copy(loadingAuth: false);
      return;
    }

    try {
      final keyfiles = (record.unlockMethod == ContainerUnlockMethod.rememberPassword && record.keyfiles.isNotEmpty)
          ? record.keyfiles.map((k) => (uri: k['uri']!, displayName: k['name']!)).toList()
          : <KeyfileRef>[];

      String? patternHash;
      String? pinHash;
      if (record.unlockMethod == ContainerUnlockMethod.pattern) {
        patternHash = await ref.read(containerRepositoryProvider).getPatternHash(record.uri);
      }
      if (record.unlockMethod == ContainerUnlockMethod.pin) {
        pinHash = await ref.read(containerRepositoryProvider).getPinHash(record.uri);
      }

      if (!ref.mounted) return;
      state = state._copy(
        unlockMethod: record.unlockMethod,
        readOnly: record.readOnly,
        keyfiles: keyfiles,
        storedPatternHash: patternHash,
        storedPinHash: pinHash,
        loadingAuth: false,
      );

      if (record.unlockMethod == ContainerUnlockMethod.biometrics &&
          state.selected != null &&
          !state.reconnectTargetMissing) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (ref.mounted) {
          state = state._copy(biometricAutoTriggerTick: state.biometricAutoTriggerTick + 1);
        }
      }
    } catch (e) {
      VeLog.e('UsbUnlockController', '_initAuth failed', e);
      if (ref.mounted) state = state._copy(loadingAuth: false);
    }
  }

  void selectDevice(UsbDeviceInfo device) => state = state._copy(selected: device);

  void setReadOnly(bool val) => state = state._copy(readOnly: val);

  void setRemember(bool val) => state = state._copy(remember: val);

  void setProtectHiddenVolume(bool val) => state = state._copy(protectHiddenVolume: val);

  void setCipherId(int id) => state = state._copy(cipherId: id);

  void setHashId(int id) => state = state._copy(hashId: id);

  void setHiddenCipherId(int id) => state = state._copy(hiddenCipherId: id);

  void setHiddenHashId(int id) => state = state._copy(hiddenHashId: id);

  void setShowPasswordFallback(bool show) => state = state._copy(showPasswordFallback: show);

  Future<void> pickKeyfiles() async {
    state = state._copy(pickingKeyfiles: true);
    try {
      final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
      if (!ref.mounted) return;
      if (picked.isNotEmpty) {
        final existing = state.keyfiles.map((k) => k.uri).toSet();
        final newKeyfiles = List<KeyfileRef>.from(state.keyfiles);
        for (final k in picked) {
          if (existing.add(k.uri)) newKeyfiles.add(k);
        }
        state = state._copy(keyfiles: newKeyfiles, pickingKeyfiles: false);
      } else {
        state = state._copy(pickingKeyfiles: false);
      }
    } catch (_) {
      if (ref.mounted) state = state._copy(pickingKeyfiles: false);
    }
  }

  void removeKeyfile(KeyfileRef k) {
    final newKeyfiles = state.keyfiles.where((item) => item != k).toList();
    state = state._copy(keyfiles: newKeyfiles);
  }

  Future<void> cancelUnlock() async {
    if (_trackedActiveVolId != null) {
      await ref.read(vaultLifecycleApiProvider).cancelUnlock(_trackedActiveVolId!);
    }
    _trackedActiveVolId = null;
    state = state._copy(loading: false, clearActiveVolId: true, clearProgress: true);
  }

  Future<T?> _unlockSwallowingStaleAuthFail<T>(Future<T> Function() attempt) async {
    try {
      return await attempt();
    } on PlatformException catch (e) {
      if (e.code == 'AUTH_FAIL') return null;
      rethrow;
    }
  }

  Future<void> tryBiometric(AppLocalizations l10n) async {
    if (params.existingRecord == null) return;
    if (state.selected == null) {
      state = state._copy(error: l10n.selectUsbDriveFirst);
      return;
    }
    if (state.isAuthenticating) return;
    try {
      state = state._copy(isAuthenticating: true);
      final localAuth = LocalAuthentication();
      final canCheck = await localAuth.canCheckBiometrics;
      final isSupported = await localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) {
        if (ref.mounted) {
          state = state._copy(error: l10n.biometricNotAvailable, showPasswordFallback: true);
        }
        return;
      }

      final ok = await localAuth.authenticate(
        localizedReason: 'Authenticate to unlock ${l10n.biometricSubjectUsbDrive}',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (ok && ref.mounted) {
        final record = params.existingRecord!;
        final deviceName = _expectedDeviceName;

        final appSettings = await ref.read(appSettingsServiceProvider).loadSettings();
        final shouldCacheGoingForward =
            (record.cacheDerivedKey) || appSettings.defaultDerivedKeyCacheEnabled;
        final shouldPreloadCachedKey = record.cacheDerivedKey;

        final cachedKey = shouldPreloadCachedKey && deviceName != null
            ? await ref.read(vaultCryptoApiProvider).loadDerivedKey(deviceName)
            : null;

        if (!ref.mounted) return;

        if (cachedKey != null && cachedKey.isNotEmpty) {
          await unlock(l10n: l10n, preservedKey: cachedKey, shouldCacheDerivedKeyOverride: shouldCacheGoingForward);
          return;
        }

        final pw = await ref.read(containerRepositoryProvider).getPassword(record.uri);
        final savedKeyfiles = record.keyfiles;
        final savedKeyfilePaths = savedKeyfiles.map((k) => k['uri']!).toList();
        if (pw != null || savedKeyfilePaths.isNotEmpty) {
          await unlock(
            l10n: l10n,
            shouldCacheDerivedKeyOverride: shouldCacheGoingForward,
            passwordOverride: pw ?? '',
            keyfilePathsOverride: savedKeyfilePaths,
          );
        } else {
          state = state._copy(error: l10n.usbNoSavedCredentialsMessage, showPasswordFallback: true);
        }
      }
    } on LocalAuthException catch (e) {
      final desc = e.description?.toLowerCase() ?? '';
      if (e.code.name.toLowerCase().contains('progress') || desc.contains('progress')) {
        return;
      }
      if (ref.mounted) {
        state = state._copy(
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
        state = state._copy(
          error: l10n.biometricErrorWithCode(e.message ?? ''),
          showPasswordFallback: true,
        );
      }
    } catch (_) {
    } finally {
      if (ref.mounted) state = state._copy(isAuthenticating: false);
    }
  }

  Future<void> onPatternComplete(List<int> pattern, AppLocalizations l10n) async {
    if (params.existingRecord == null) return;
    final uri = params.existingRecord!.uri;
    if (state.storedPatternHash == null) {
      state = state._copy(error: l10n.noPatternConfiguredMessage, showPasswordFallback: true);
      return;
    }
    final lockout = await PatternUnlockThrottle.currentLockout(uri);
    if (lockout != null) {
      state = state._copy(error: l10n.tooManyFailedAttempts(lockout.inSeconds), patternError: true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (ref.mounted) {
          state = state._copy(patternError: false, patternResetKey: state.patternResetKey + 1);
        }
      });
      return;
    }

    final ok = await verifyPattern(pattern, state.storedPatternHash!);
    if (ok) {
      await PatternUnlockThrottle.clear(uri);
      if (!ref.mounted) return;
      await _cachedKeyThenSavedCredentials(l10n: l10n);
    } else {
      final newLockout = await PatternUnlockThrottle.recordFailure(uri);
      state = newLockout != null
          ? state._copy(patternError: true, error: l10n.patternLockedForSeconds(newLockout.inSeconds))
          : state._copy(patternError: true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (ref.mounted) {
          state = state._copy(patternError: false, patternResetKey: state.patternResetKey + 1);
        }
      });
    }
  }

  Future<void> onPinComplete(String pin, AppLocalizations l10n) async {
    if (params.existingRecord == null) return;
    final uri = params.existingRecord!.uri;
    if (state.storedPinHash == null) {
      state = state._copy(error: l10n.noPinConfiguredMessage, showPasswordFallback: true);
      return;
    }
    final lockout = await PinUnlockThrottle.currentLockout(uri);
    if (lockout != null) {
      state = state._copy(error: l10n.tooManyFailedAttempts(lockout.inSeconds), pinError: true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (ref.mounted) {
          state = state._copy(pinError: false, pinResetKey: state.pinResetKey + 1);
        }
      });
      return;
    }

    final ok = await verifyPin(pin, state.storedPinHash!);
    if (ok) {
      await PinUnlockThrottle.clear(uri);
      if (!ref.mounted) return;
      await _cachedKeyThenSavedCredentials(l10n: l10n);
    } else {
      final newLockout = await PinUnlockThrottle.recordFailure(uri);
      state = newLockout != null
          ? state._copy(pinError: true, error: l10n.pinLockedForSeconds(newLockout.inSeconds))
          : state._copy(pinError: true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (ref.mounted) {
          state = state._copy(pinError: false, pinResetKey: state.pinResetKey + 1);
        }
      });
    }
  }

  /// Shared by [onPatternComplete]/[onPinComplete]'s auth-success branch --
  /// same three-step cached-key/saved-credentials/error sequence as
  /// [tryBiometric], and identical in shape to
  /// [UnlockController._cachedKeyThenSavedCredentials]. USB uses one
  /// shared "no saved credentials" message for every auth method (unlike
  /// local's three distinct strings), matching the original
  /// `UnlockBiometricSource` asymmetry.
  Future<void> _cachedKeyThenSavedCredentials({required AppLocalizations l10n}) async {
    final record = params.existingRecord!;
    final deviceName = _expectedDeviceName;

    final appSettings = await ref.read(appSettingsServiceProvider).loadSettings();
    final shouldCacheGoingForward = record.cacheDerivedKey || appSettings.defaultDerivedKeyCacheEnabled;
    final shouldPreloadCachedKey = record.cacheDerivedKey;

    final cachedKey = shouldPreloadCachedKey && deviceName != null
        ? await ref.read(vaultCryptoApiProvider).loadDerivedKey(deviceName)
        : null;

    if (!ref.mounted) return;

    if (cachedKey != null && cachedKey.isNotEmpty) {
      await unlock(l10n: l10n, preservedKey: cachedKey, shouldCacheDerivedKeyOverride: shouldCacheGoingForward);
      return;
    }

    final pw = await ref.read(containerRepositoryProvider).getPassword(record.uri);
    final savedKeyfilePaths = record.keyfiles.map((k) => k['uri']!).toList();
    if (pw != null || savedKeyfilePaths.isNotEmpty) {
      await unlock(
        l10n: l10n,
        shouldCacheDerivedKeyOverride: shouldCacheGoingForward,
        passwordOverride: pw ?? '',
        keyfilePathsOverride: savedKeyfilePaths,
      );
    } else {
      state = state._copy(error: l10n.usbNoSavedCredentialsMessage, showPasswordFallback: true);
    }
  }

  Future<void> unlock({
    String? passwordText,
    String? pimText,
    String? hiddenPasswordText,
    String? hiddenPimText,
    String? passwordOverride,
    Uint8List? preservedKey,
    bool? shouldCacheDerivedKeyOverride,
    List<String>? keyfilePathsOverride,
    AppLocalizations? l10n,
    bool passwordPrefilled = false,
  }) async {
    final device = state.selected;
    if (device == null) return;

    final newUri = 'usb:${device.deviceName}';
    var effectivePassword = (passwordOverride ?? passwordText ?? '').trim();
    final effectiveKeyfiles = keyfilePathsOverride ?? state.keyfiles.map((k) => k.uri).toList();

    state = state._copy(loading: true, clearError: true, clearActiveVolId: true, clearProgress: true);
    final lifecycle = ref.read(vaultLifecycleApiProvider);
    final crypto = ref.read(vaultCryptoApiProvider);

    try {
      if (!device.hasPermission) {
        state = state._copy(requestingPermission: true);
        final granted = await lifecycle.requestUsbPermission(device.deviceName);
        state = state._copy(requestingPermission: false);
        if (!granted) {
          state = state._copy(loading: false, error: 'USB permission required');
          return;
        }
      }

      final pim = clampPim(pimText != null && pimText.isNotEmpty ? int.tryParse(pimText) ?? 0 : 0);
      final hiddenPim =
          clampPim(hiddenPimText != null && hiddenPimText.isNotEmpty ? int.tryParse(hiddenPimText) ?? 0 : 0);
      final hiddenKeyfiles = state.hiddenKeyfiles.map((k) => k.uri).toList();
      final displayName = params.existingRecord?.label ?? device.productName;

      final isReconnect = params.existingRecord != null;
      final appSettings = await ref.read(appSettingsServiceProvider).loadSettings();
      final shouldCacheDerivedKey = shouldCacheDerivedKeyOverride ??
          ((isReconnect || state.remember) &&
              ((params.existingRecord?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled));
      final shouldPreloadCachedKey = preservedKey == null &&
          state.unlockMethod == ContainerUnlockMethod.rememberPassword &&
          passwordPrefilled &&
          (params.existingRecord?.cacheDerivedKey ?? false);
      final resolvedPreservedKey = preservedKey ??
          (shouldPreloadCachedKey ? await crypto.loadDerivedKey(device.deviceName) : null);

      var result = resolvedPreservedKey == null
          ? await lifecycle.unlockUsbContainer(
              device.deviceName,
              effectivePassword,
              pim,
              displayName: displayName,
              documentProvider: params.documentProvider,
              autoMountFolders: params.autoMountFolders,
              cipherId: state.cipherId,
              hashId: state.hashId,
              preservedKey: resolvedPreservedKey,
              cacheDerivedKey: shouldCacheDerivedKey,
              keyfilePaths: effectiveKeyfiles,
              readOnly: state.readOnly,
              protectHiddenVolume: state.protectHiddenVolume,
              hiddenVolumePassword: hiddenPasswordText,
              hiddenVolumePim: hiddenPim,
              hiddenVolumeCipherId: state.hiddenCipherId,
              hiddenVolumeHashId: state.hiddenHashId,
              hiddenVolumeKeyfilePaths: hiddenKeyfiles,
            )
          : await _unlockSwallowingStaleAuthFail(() => lifecycle.unlockUsbContainer(
                device.deviceName,
                effectivePassword,
                pim,
                displayName: displayName,
                documentProvider: params.documentProvider,
                autoMountFolders: params.autoMountFolders,
                cipherId: state.cipherId,
                hashId: state.hashId,
                preservedKey: resolvedPreservedKey,
                cacheDerivedKey: shouldCacheDerivedKey,
                keyfilePaths: effectiveKeyfiles,
                readOnly: state.readOnly,
                protectHiddenVolume: state.protectHiddenVolume,
                hiddenVolumePassword: hiddenPasswordText,
                hiddenVolumePim: hiddenPim,
                hiddenVolumeCipherId: state.hiddenCipherId,
                hiddenVolumeHashId: state.hiddenHashId,
                hiddenVolumeKeyfilePaths: hiddenKeyfiles,
              ));

      if (result == null && resolvedPreservedKey != null) {
        // Cached key was stale/invalid -- purge it and silently retry with
        // the real credentials before surfacing anything to the UI.
        await crypto.clearDerivedKey(device.deviceName);
        if (effectivePassword.isEmpty && params.existingRecord != null) {
          effectivePassword =
              (await ref.read(containerRepositoryProvider).getPassword(params.existingRecord!.uri))?.trim() ?? '';
        }
        if (effectivePassword.isNotEmpty || effectiveKeyfiles.isNotEmpty) {
          result = await lifecycle.unlockUsbContainer(
            device.deviceName,
            effectivePassword,
            pim,
            displayName: displayName,
            documentProvider: params.documentProvider,
            autoMountFolders: params.autoMountFolders,
            cipherId: state.cipherId,
            hashId: state.hashId,
            preservedKey: null,
            cacheDerivedKey: shouldCacheDerivedKey,
            keyfilePaths: effectiveKeyfiles,
            readOnly: state.readOnly,
            protectHiddenVolume: state.protectHiddenVolume,
            hiddenVolumePassword: hiddenPasswordText,
            hiddenVolumePim: hiddenPim,
            hiddenVolumeCipherId: state.hiddenCipherId,
            hiddenVolumeHashId: state.hiddenHashId,
            hiddenVolumeKeyfilePaths: hiddenKeyfiles,
          );
        }
      }

      if (result == null) {
        if (ref.mounted) state = state._copy(loading: false, error: 'Incorrect credentials');
        return;
      }

      await AppSecureStorage.instance.write(key: 'temp_pw_$newUri', value: effectivePassword);
      final tempContainer = MountedContainer(
        uri: newUri,
        displayName: displayName,
        volId: result.volId,
        rootFiles: result.files,
        mountedAt: DateTime.now(),
        totalSpace: 0,
        freeSpace: 0,
        readOnly: state.readOnly,
        containerFormat: result.containerFormat,
      );

      final space = await ref.read(vaultFileIoApiProvider).getSpaceInfo(tempContainer);
      final total = (space != null && space.isNotEmpty) ? space[0] : 0;
      final free = (space != null && space.length > 1) ? space[1] : 0;
      final finalContainer = tempContainer.copyWith(totalSpace: total, freeSpace: free);

      ContainerRecord? savedRecord = params.existingRecord;
      if (params.existingRecord == null && state.remember) {
        savedRecord = ContainerRecord(
          uri: newUri,
          label: displayName,
          rememberPassword: false,
          unlockMethod: ContainerUnlockMethod.password,
          autoCloseMins: 0,
          documentProvider: params.documentProvider,
          documentProviderFolders: const [],
          cacheDerivedKey: shouldCacheDerivedKey,
          readOnly: state.readOnly,
          cipherId: state.cipherId,
          hashId: state.hashId,
          containerFormat: result.containerFormat,
          keyfiles: state.keyfiles.map((k) => {'uri': k.uri, 'name': k.displayName}).toList(),
        );
        await ref.read(containerRepositoryProvider).save(savedRecord);
      }

      if (ref.mounted) {
        state = state._copy(
          loading: false,
          mountedSuccess: (
            container: finalContainer,
            record: savedRecord,
            oldUri: params.existingRecord?.uri != newUri ? params.existingRecord?.uri : null,
          ),
        );
      }
    } on PlatformException catch (e) {
      if (ref.mounted && e.code != 'CANCELLED') {
        state = state._copy(loading: false, error: e.message ?? '$e');
      }
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(loading: false, error: '$e');
      }
    }
  }
}