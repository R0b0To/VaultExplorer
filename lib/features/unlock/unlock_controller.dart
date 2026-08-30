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
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';
import 'package:vaultexplorer/features/unlock/unlock_lockout_throttle.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'unlock_controller.g.dart';

@immutable
class UnlockParams {
  final String? initialUri;
  final String? initialName;
  final String? prefillPassword;
  final bool documentProvider;
  final List<String> autoMountFolders;
  final List<String> mountedUris;

  const UnlockParams({
    this.initialUri,
    this.initialName,
    this.prefillPassword,
    this.documentProvider = false,
    this.autoMountFolders = const [],
    this.mountedUris = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnlockParams &&
          other.initialUri == initialUri &&
          other.initialName == initialName &&
          other.prefillPassword == prefillPassword &&
          other.documentProvider == documentProvider &&
          listEquals(other.autoMountFolders, autoMountFolders) &&
          listEquals(other.mountedUris, mountedUris);

  @override
  int get hashCode => Object.hash(
        initialUri,
        initialName,
        prefillPassword,
        documentProvider,
        Object.hashAll(autoMountFolders),
        Object.hashAll(mountedUris),
      );
}

class UnlockState {
  final String? selectedUri;
  final String? selectedName;
  final String containerFormat;
  final bool loading;
  final bool remember;
  final bool readOnly;
  final bool hasAllStorageAccess;
  final String? error;
  final int cipherId;
  final int hashId;

  /// Set once vaultLifecycleApiProvider's detectsAsPlainDiskImage() comes
  /// back true for selectedUri -- see UnlockController._checkPlainDiskImage.
  /// Only ever meaningful for a raw disk-image container (picked via
  /// pickContainer(), never the folder-vault pickers): the unlock button
  /// itself was never gated on the password being non-empty, so this
  /// doesn't change what unlock() can submit, just how honestly the
  /// password field represents what it actually needs.
  final bool isPlainDiskImage;

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
  final bool containerMissing;
  final bool isAuthenticating;

  /// Bumped whenever the controller determines biometric auth should
  /// auto-fire (mirrors `LockGateController.navigateTick`'s pattern for
  /// notifier-can't-own-BuildContext one-shot effects). The widget's
  /// `ref.listen` calls `tryBiometric(context.l10n)` in response --
  /// `tryBiometric` itself needs a real `AppLocalizations` for its error
  /// strings, which only the widget layer can provide.
  final int biometricAutoTriggerTick;

  final ({MountedContainer container, ContainerRecord? record})? mountedSuccess;

  bool get isLuks => ContainerFormat.isLuksWire(containerFormat);
  bool get isCryptomator => ContainerFormat.isCryptomatorWire(containerFormat);
  bool get isGocryptfs => ContainerFormat.isGocryptfsWire(containerFormat);
  bool get isCryfs => ContainerFormat.isCryfsWire(containerFormat);
  bool get isBitlocker => ContainerFormat.isBitlockerWire(containerFormat);
  bool get isFolderVault => ContainerFormat.isFolderVaultWire(containerFormat);
  bool get isVeraCrypt => !isLuks && !isFolderVault && !isBitlocker;
  bool get hasAdvancedSettings => isVeraCrypt || isLuks;

  const UnlockState({
    this.selectedUri,
    this.selectedName,
    this.containerFormat = 'container',
    this.loading = false,
    this.remember = false,
    this.readOnly = false,
    this.hasAllStorageAccess = false,
    this.error,
    this.cipherId = 255,
    this.hashId = 255,
    this.isPlainDiskImage = false,
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
    this.containerMissing = false,
    this.isAuthenticating = false,
    this.biometricAutoTriggerTick = 0,
    this.mountedSuccess,
  });

  UnlockState _copy({
    String? selectedUri,
    bool clearSelectedUri = false,
    String? selectedName,
    bool clearSelectedName = false,
    String? containerFormat,
    bool? loading,
    bool? remember,
    bool? readOnly,
    bool? hasAllStorageAccess,
    String? error,
    bool clearError = false,
    int? cipherId,
    int? hashId,
    bool? isPlainDiskImage,
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
    bool? containerMissing,
    bool? isAuthenticating,
    int? biometricAutoTriggerTick,
    ({MountedContainer container, ContainerRecord? record})? mountedSuccess,
  }) => UnlockState(
    selectedUri: clearSelectedUri ? null : (selectedUri ?? this.selectedUri),
    selectedName: clearSelectedName ? null : (selectedName ?? this.selectedName),
    containerFormat: containerFormat ?? this.containerFormat,
    loading: loading ?? this.loading,
    remember: remember ?? this.remember,
    readOnly: readOnly ?? this.readOnly,
    hasAllStorageAccess: hasAllStorageAccess ?? this.hasAllStorageAccess,
    error: clearError ? null : (error ?? this.error),
    cipherId: cipherId ?? this.cipherId,
    hashId: hashId ?? this.hashId,
    isPlainDiskImage: isPlainDiskImage ?? this.isPlainDiskImage,
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
    containerMissing: containerMissing ?? this.containerMissing,
    isAuthenticating: isAuthenticating ?? this.isAuthenticating,
    biometricAutoTriggerTick: biometricAutoTriggerTick ?? this.biometricAutoTriggerTick,
    mountedSuccess: mountedSuccess ?? this.mountedSuccess,
  );
}

@riverpod
class UnlockController extends _$UnlockController {
  late final void Function(int) _onUnlockStarted;
  late final void Function(UnlockProgress) _onUnlockProgress;
  int? _trackedActiveVolId;

  @override
  UnlockState build(UnlockParams params) {
    final initialUri = params.initialUri;
    final initial = UnlockState(
      selectedUri: initialUri,
      selectedName: params.initialName,
      remember: initialUri != null,
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

    Future.microtask(() => _init(params));
    return initial;
  }

  Future<void> _init(UnlockParams params) async {
    final lifecycle = ref.read(vaultLifecycleApiProvider);
    final hasAccess = await lifecycle.hasAllFilesAccess();
    state = state._copy(hasAllStorageAccess: hasAccess);

    if (params.initialUri != null) {
      lifecycle.warmContainer(params.initialUri!);
      unawaited(_checkPlainDiskImage(params.initialUri!));
      await _initUnlockMethod(params.initialUri!);
    } else {
      state = state._copy(loadingAuth: false);
    }
  }

  /// Cheap, read-only pre-check run right after a file is selected
  /// (freshly picked, or reopened via a saved [UnlockParams.initialUri]),
  /// before the person ever needs to type a password: true only if [uri]
  /// is a VHD/VHDX whose virtual disk (or a partition within it) carries a
  /// directly-recognizable, unencrypted filesystem -- see
  /// detectsAsPlainDiskImage's doc comment in session_prepare.cpp for the
  /// exact scope. Guards against a stale result landing after the
  /// selection has since changed (or been cleared) while the
  /// platform-channel round trip was in flight; errors already resolve to
  /// false inside detectsAsPlainDiskImage itself, so there's nothing else
  /// to catch here.
  Future<void> _checkPlainDiskImage(String uri) async {
    final isPlain = await ref.read(vaultLifecycleApiProvider).detectsAsPlainDiskImage(uri);
    if (ref.mounted && state.selectedUri == uri) {
      state = state._copy(isPlainDiskImage: isPlain);
    }
  }

  Future<void> _initUnlockMethod(String uri) async {
    try {
      final records = await ref.read(containerRepositoryProvider).loadAll();
      final record = records[uri];
      if (record == null) {
        if (ref.mounted) state = state._copy(loadingAuth: false);
        return;
      }

      final keyfileList = (record.unlockMethod == ContainerUnlockMethod.rememberPassword && record.keyfiles.isNotEmpty)
          ? record.keyfiles.map((k) => (uri: k['uri']!, displayName: k['name']!)).toList()
          : <KeyfileRef>[];

      bool exists = true;
      try {
        exists = await ref.read(vaultLifecycleApiProvider).documentExists(uri);
      } catch (_) {
        exists = true;
      }

      if (!exists) {
        if (ref.mounted) {
          state = state._copy(containerMissing: true, loadingAuth: false);
        }
        return;
      }

      String? patternHash;
      String? pinHash;
      if (record.unlockMethod == ContainerUnlockMethod.pattern) {
        patternHash = await ref.read(containerRepositoryProvider).getPatternHash(uri);
      }
      if (record.unlockMethod == ContainerUnlockMethod.pin) {
        pinHash = await ref.read(containerRepositoryProvider).getPinHash(uri);
      }

      if (!ref.mounted) return;
      state = state._copy(
        containerFormat: record.containerFormat,
        keyfiles: keyfileList,
        unlockMethod: record.unlockMethod,
        cipherId: record.cipherId,
        hashId: record.hashId,
        readOnly: record.readOnly,
        storedPatternHash: patternHash,
        storedPinHash: pinHash,
        loadingAuth: false,
      );

      if (record.unlockMethod == ContainerUnlockMethod.biometrics) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (ref.mounted) {
          state = state._copy(biometricAutoTriggerTick: state.biometricAutoTriggerTick + 1);
        }
      }
    } catch (e) {
      VeLog.e('UnlockController', '_initUnlockMethod failed with error', e);
      if (ref.mounted) state = state._copy(loadingAuth: false);
    }
  }

  Future<void> checkStoragePermission() async {
    final hasAccess = await ref.read(vaultLifecycleApiProvider).hasAllFilesAccess();
    if (ref.mounted) state = state._copy(hasAllStorageAccess: hasAccess);
  }

  Future<void> requestStoragePermission() async {
    await ref.read(vaultLifecycleApiProvider).requestAllFilesAccess();
    await checkStoragePermission();
  }

  void setSelectedVaultKind(String kind) {
    state = state._copy(
      containerFormat: kind,
      clearSelectedUri: true,
      clearSelectedName: true,
      clearError: true,
    );
  }

  void setReadOnly(bool val) => state = state._copy(
        readOnly: val,
        protectHiddenVolume: val ? false : state.protectHiddenVolume,
      );

  void setRemember(bool val) => state = state._copy(remember: val);

  void setProtectHiddenVolume(bool val) => state = state._copy(protectHiddenVolume: val);

  void setCipherId(int id) => state = state._copy(cipherId: id);

  void setHashId(int id) => state = state._copy(hashId: id);

  void setHiddenCipherId(int id) => state = state._copy(hiddenCipherId: id);

  void setHiddenHashId(int id) => state = state._copy(hiddenHashId: id);

  void setShowPasswordFallback(bool show) => state = state._copy(showPasswordFallback: show);

  void clearSelection() {
    state = state._copy(
      clearSelectedUri: true,
      clearSelectedName: true,
      containerFormat: state.isFolderVault ? 'directory_vault' : 'container',
      isPlainDiskImage: false,
    );
  }

  Future<void> pickFile(AppLocalizations l10n) async {
    final lifecycle = ref.read(vaultLifecycleApiProvider);
    try {
      if (state.isFolderVault) {
        final result = await lifecycle.pickCryptomatorVault();
        if (result == null) return;
        if (params.mountedUris.contains(result.uri)) {
          state = state._copy(
            error: l10n.containerAlreadyMounted,
            clearSelectedUri: true,
            clearSelectedName: true,
          );
          return;
        }
        final detectedFormat = result.format;
        if (detectedFormat == null) {
          state = state._copy(
            error: l10n.noVaultFolderFormatDetected,
            clearSelectedUri: true,
            clearSelectedName: true,
          );
          return;
        }
        state = state._copy(
          selectedUri: result.uri,
          selectedName: result.displayName,
          containerFormat: detectedFormat,
          clearError: true,
          isPlainDiskImage: false, // folder vaults always need a password
        );
        return;
      }

      final result = await lifecycle.pickContainer();
      if (result != null) {
        if (params.mountedUris.contains(result.uri)) {
          state = state._copy(
            error: l10n.containerAlreadyMounted,
            clearSelectedUri: true,
            clearSelectedName: true,
          );
          return;
        }
        state = state._copy(
          selectedUri: result.uri,
          selectedName: result.displayName,
          containerFormat: 'container',
          clearError: true,
          isPlainDiskImage: false, // re-checked below; don't carry over a stale true
        );
        lifecycle.warmContainer(result.uri);
        unawaited(_checkPlainDiskImage(result.uri));
      }
    } catch (e) {
      state = state._copy(error: l10n.filePickerFailed(e.toString()));
    }
  }

  Future<void> relocateContainer(AppLocalizations l10n) async {
    final oldUri = params.initialUri;
    if (oldUri == null) return;
    final lifecycle = ref.read(vaultLifecycleApiProvider);
    try {
      String newUri;
      String newDisplayName;
      String detectedFormat = state.containerFormat;

      if (state.isFolderVault) {
        final picked = await lifecycle.pickCryptomatorVault();
        if (picked == null || !ref.mounted) return;
        final format = picked.format;
        if (format == null) {
          state = state._copy(error: l10n.noVaultFolderFormatDetected);
          return;
        }
        detectedFormat = format;
        newUri = picked.uri;
        newDisplayName = picked.displayName;
      } else {
        final picked = await lifecycle.pickContainer();
        if (picked == null || !ref.mounted) return;
        newUri = picked.uri;
        newDisplayName = picked.displayName;
      }

      state = state._copy(loadingAuth: true);
      final repo = ref.read(containerRepositoryProvider);
      final records = await repo.loadAll();
      final existing = records[oldUri];
      if (existing == null) {
        if (ref.mounted) {
          state = state._copy(loadingAuth: false, error: l10n.savedContainerSettingsNotFound);
        }
        return;
      }

      final savedPassword = await repo.getPassword(oldUri);
      final savedPatternHash = await repo.getPatternHash(oldUri);
      final savedPinHash = await repo.getPinHash(oldUri);
      await repo.remove(oldUri);

      final migrated = ContainerRecord(
        uri: newUri,
        label: existing.label,
        rememberPassword: existing.rememberPassword,
        unlockMethod: existing.unlockMethod,
        autoCloseMins: existing.autoCloseMins,
        documentProvider: existing.documentProvider,
        documentProviderFolders: existing.documentProviderFolders,
        thumbnailCacheMode: existing.thumbnailCacheMode,
        cacheDerivedKey: existing.cacheDerivedKey,
        pendingPassword: savedPassword,
        pendingPatternHash: savedPatternHash,
        pendingPinHash: savedPinHash,
        cipherId: existing.cipherId,
        hashId: existing.hashId,
        containerFormat: detectedFormat,
        keyfiles: existing.keyfiles,
      );

      await repo.save(migrated);
      if (!ref.mounted) return;
      state = state._copy(
        selectedUri: migrated.uri,
        selectedName: newDisplayName,
        unlockMethod: migrated.unlockMethod,
        cipherId: migrated.cipherId,
        hashId: migrated.hashId,
        containerFormat: migrated.containerFormat,
        storedPatternHash: savedPatternHash,
        storedPinHash: savedPinHash,
        containerMissing: false,
        loadingAuth: false,
        isPlainDiskImage: false, // re-checked below; don't carry over a stale true
      );
      unawaited(_checkPlainDiskImage(migrated.uri));

      if (state.unlockMethod == ContainerUnlockMethod.biometrics) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (ref.mounted) {
          state = state._copy(biometricAutoTriggerTick: state.biometricAutoTriggerTick + 1);
        }
      }
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(
          loadingAuth: false,
          error: l10n.couldNotUpdateContainerLocation(e.toString()),
        );
      }
    }
  }

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

  Future<void> pickHiddenKeyfiles() async {
    state = state._copy(pickingHiddenKeyfiles: true);
    try {
      final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
      if (!ref.mounted) return;
      if (picked.isNotEmpty) {
        final existing = state.hiddenKeyfiles.map((k) => k.uri).toSet();
        final newKeyfiles = List<KeyfileRef>.from(state.hiddenKeyfiles);
        for (final k in picked) {
          if (existing.add(k.uri)) newKeyfiles.add(k);
        }
        state = state._copy(hiddenKeyfiles: newKeyfiles, pickingHiddenKeyfiles: false);
      } else {
        state = state._copy(pickingHiddenKeyfiles: false);
      }
    } catch (_) {
      if (ref.mounted) state = state._copy(pickingHiddenKeyfiles: false);
    }
  }

  void removeHiddenKeyfile(KeyfileRef k) {
    final newKeyfiles = state.hiddenKeyfiles.where((item) => item != k).toList();
    state = state._copy(hiddenKeyfiles: newKeyfiles);
  }

  Future<void> cancelUnlock() async {
    if (_trackedActiveVolId != null) {
      await ref.read(vaultLifecycleApiProvider).cancelUnlock(_trackedActiveVolId!);
    }
    _trackedActiveVolId = null;
    state = state._copy(loading: false, clearActiveVolId: true, clearProgress: true);
  }

  /// Swallows a stale-cached-key auth failure so the caller can fall back
  /// to real credentials, matching the pre-Riverpod
  /// `_unlockSwallowingStaleAuthFail`. Any other PlatformException
  /// (wrong password, corrupt container, etc.) still propagates.
Future<T?> _unlockSwallowingStaleAuthFail<T>(Future<T?> Function() attempt) async {
  try {
    return await attempt();
  } on PlatformException catch (e) {
    if (e.code == 'AUTH_FAIL') return null;
    rethrow;
  }
}

  Future<void> tryBiometric(AppLocalizations l10n) async {
    if (params.initialUri == null) return;
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
        localizedReason: 'Authenticate to unlock ${l10n.biometricSubjectContainer}',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (ok && ref.mounted) {
        final uri = params.initialUri!;
        final records = await ref.read(containerRepositoryProvider).loadAll();
        final record = records[uri];

        final appSettings = await AppSettingsService.instance.loadSettings();
        final shouldCacheGoingForward =
            (record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled;
        final shouldPreloadCachedKey = record?.cacheDerivedKey ?? false;

        final cachedKey = shouldPreloadCachedKey
            ? await ref.read(vaultCryptoApiProvider).loadDerivedKey(uri)
            : null;

        if (!ref.mounted) return;

        if (cachedKey != null && cachedKey.isNotEmpty) {
          await unlock(
            l10n: l10n,
            preservedKey: cachedKey,
            shouldCacheDerivedKeyOverride: shouldCacheGoingForward,
          );
          return;
        }

        final pw = await ref.read(containerRepositoryProvider).getPassword(uri);
        final savedKeyfiles = record?.keyfiles ?? [];
        final savedKeyfilePaths = savedKeyfiles.map((k) => k['uri']!).toList();
        if (pw != null || savedKeyfilePaths.isNotEmpty) {
          await unlock(
            l10n: l10n,
            shouldCacheDerivedKeyOverride: shouldCacheGoingForward,
            passwordOverride: pw ?? '',
            keyfilePathsOverride: savedKeyfilePaths,
          );
        } else {
          state = state._copy(
            error: l10n.initSecureCredsBiometricMessage,
            showPasswordFallback: true,
          );
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
    } finally {
      if (ref.mounted) state = state._copy(isAuthenticating: false);
    }
  }

  Future<void> onPatternComplete(List<int> pattern, AppLocalizations l10n) async {
    final uri = params.initialUri;
    if (uri == null) return;
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
      await _cachedKeyThenSavedCredentials(
        uri: uri,
        l10n: l10n,
        noSavedCredentialsMessage: l10n.initSecureCredsPatternMessage,
      );
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
    final uri = params.initialUri;
    if (uri == null) return;
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
      await _cachedKeyThenSavedCredentials(
        uri: uri,
        l10n: l10n,
        noSavedCredentialsMessage: l10n.initSecureCredsPinMessage,
      );
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

  /// Shared by [onPatternComplete]/[onPinComplete]'s auth-success branch:
  /// check for a cached derived key first, unlock with it if present,
  /// otherwise fall back to a saved password/keyfiles, otherwise show
  /// [noSavedCredentialsMessage]. Identical in shape to the equivalent
  /// block in [tryBiometric] -- kept as its own helper here since it's the
  /// same three-step sequence twice more, once per auth method.
  Future<void> _cachedKeyThenSavedCredentials({
    required String uri,
    required AppLocalizations l10n,
    required String noSavedCredentialsMessage,
  }) async {
    final records = await ref.read(containerRepositoryProvider).loadAll();
    final record = records[uri];

    final appSettings = await AppSettingsService.instance.loadSettings();
    final shouldCacheGoingForward =
        (record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled;
    final shouldPreloadCachedKey = record?.cacheDerivedKey ?? false;

    final cachedKey =
        shouldPreloadCachedKey ? await ref.read(vaultCryptoApiProvider).loadDerivedKey(uri) : null;

    if (!ref.mounted) return;

    if (cachedKey != null && cachedKey.isNotEmpty) {
      await unlock(l10n: l10n, preservedKey: cachedKey, shouldCacheDerivedKeyOverride: shouldCacheGoingForward);
      return;
    }

    final pw = await ref.read(containerRepositoryProvider).getPassword(uri);
    final savedKeyfiles = record?.keyfiles ?? [];
    final savedKeyfilePaths = savedKeyfiles.map((k) => k['uri']!).toList();
    if (pw != null || savedKeyfilePaths.isNotEmpty) {
      await unlock(
        l10n: l10n,
        shouldCacheDerivedKeyOverride: shouldCacheGoingForward,
        passwordOverride: pw ?? '',
        keyfilePathsOverride: savedKeyfilePaths,
      );
    } else {
      state = state._copy(error: noSavedCredentialsMessage, showPasswordFallback: true);
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
    final uri = state.selectedUri;
    if (uri == null) return;

    var effectivePassword = (passwordOverride ?? passwordText ?? '').trim();
    final effectiveKeyfiles = keyfilePathsOverride ?? state.keyfiles.map((k) => k.uri).toList();

    state = state._copy(loading: true, clearError: true, clearActiveVolId: true, clearProgress: true);
    final lifecycle = ref.read(vaultLifecycleApiProvider);
    final crypto = ref.read(vaultCryptoApiProvider);

    try {
      final isFolder = state.isFolderVault;
      final isCryfs = state.isCryfs;
      final isGocryptfs = state.isGocryptfs;
      final isCryptomator = state.isCryptomator;

      if (isFolder) {
        final name = state.selectedName ?? 'Vault';
        ({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?
            result;
        if (isCryptomator) {
          result = await lifecycle.unlockCryptomatorVault(
            uri,
            effectivePassword,
            displayName: name,
            documentProvider: params.documentProvider,
            autoMountFolders: params.autoMountFolders,
            readOnly: state.readOnly,
          );
        } else if (isGocryptfs) {
          result = await lifecycle.unlockGocryptfsVault(
            uri,
            effectivePassword,
            displayName: name,
            documentProvider: params.documentProvider,
            autoMountFolders: params.autoMountFolders,
            readOnly: state.readOnly,
          );
        } else {
          // CryFS: the only folder-vault format that supports derived-key
          // caching, mirroring the pre-migration branch exactly.
          final records = await ref.read(containerRepositoryProvider).loadAll();
          final cryfsRecord = records[uri];
          final appSettings = await AppSettingsService.instance.loadSettings();
          final isKnownRecord = cryfsRecord != null;
          final shouldCacheDerivedKey = shouldCacheDerivedKeyOverride ??
              ((isKnownRecord || state.remember) &&
                  ((cryfsRecord?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled));
          final shouldPreloadCachedKey = preservedKey == null &&
              state.unlockMethod == ContainerUnlockMethod.rememberPassword &&
              passwordPrefilled &&
              (cryfsRecord?.cacheDerivedKey ?? false);
          final resolvedPreservedKey =
              preservedKey ?? (shouldPreloadCachedKey ? await crypto.loadDerivedKey(uri) : null);

          result = resolvedPreservedKey == null
              ? await lifecycle.unlockCryfsVault(
                  uri,
                  effectivePassword,
                  displayName: name,
                  documentProvider: params.documentProvider,
                  autoMountFolders: params.autoMountFolders,
                  readOnly: state.readOnly,
                  cacheDerivedKey: shouldCacheDerivedKey,
                )
              : await _unlockSwallowingStaleAuthFail(() => lifecycle.unlockCryfsVault(
                    uri,
                    effectivePassword,
                    displayName: name,
                    documentProvider: params.documentProvider,
                    autoMountFolders: params.autoMountFolders,
                    readOnly: state.readOnly,
                    preservedKey: resolvedPreservedKey,
                    cacheDerivedKey: shouldCacheDerivedKey,
                  ));

          if (result == null && resolvedPreservedKey != null) {
            // Cached key was stale/invalid -- purge it and silently retry
            // with the real saved password before surfacing an error.
            await crypto.clearDerivedKey(uri);
            if (effectivePassword.isEmpty) {
              effectivePassword =
                  (await ref.read(containerRepositoryProvider).getPassword(uri))?.trim() ?? '';
            }
            if (effectivePassword.isNotEmpty) {
              result = await lifecycle.unlockCryfsVault(
                uri,
                effectivePassword,
                displayName: name,
                documentProvider: params.documentProvider,
                autoMountFolders: params.autoMountFolders,
                readOnly: state.readOnly,
                cacheDerivedKey: shouldCacheDerivedKey,
              );
            }
          }
        }

        if (result == null) {
          if (ref.mounted) state = state._copy(loading: false, error: 'Incorrect password or invalid vault');
          return;
        }

        await AppSecureStorage.instance.write(key: 'temp_pw_$uri', value: effectivePassword);
        final mountedContainer = MountedContainer(
          uri: uri,
          displayName: name,
          volId: result.volId,
          rootFiles: result.files,
          mountedAt: DateTime.now(),
          totalSpace: 0,
          freeSpace: 0,
          readOnly: state.readOnly,
          containerFormat: result.containerFormat,
        );

        if (ref.mounted) {
          state = state._copy(
            loading: false,
            mountedSuccess: (container: mountedContainer, record: null),
          );
        }
        return;
      }

      final pim = clampPim(pimText != null && pimText.isNotEmpty ? int.tryParse(pimText) ?? 0 : 0);
      final hiddenPim =
          clampPim(hiddenPimText != null && hiddenPimText.isNotEmpty ? int.tryParse(hiddenPimText) ?? 0 : 0);
      final hiddenKeyfiles = state.hiddenKeyfiles.map((k) => k.uri).toList();
      final name = state.selectedName ?? 'Container';

      final records = await ref.read(containerRepositoryProvider).loadAll();
      final record = records[uri];
      final appSettings = await AppSettingsService.instance.loadSettings();
      final isKnownRecord = record != null;
      final shouldCacheDerivedKey = shouldCacheDerivedKeyOverride ??
          ((isKnownRecord || state.remember) &&
              ((record?.cacheDerivedKey ?? false) || appSettings.defaultDerivedKeyCacheEnabled));
      final shouldPreloadCachedKey = preservedKey == null &&
          state.unlockMethod == ContainerUnlockMethod.rememberPassword &&
          passwordPrefilled &&
          (record?.cacheDerivedKey ?? false);
      final resolvedPreservedKey =
          preservedKey ?? (shouldPreloadCachedKey ? await crypto.loadDerivedKey(uri) : null);

      var result = resolvedPreservedKey == null
          ? await lifecycle.unlockContainer(
              uri,
              effectivePassword,
              pim,
              displayName: name,
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
          : await _unlockSwallowingStaleAuthFail(() => lifecycle.unlockContainer(
                uri,
                effectivePassword,
                pim,
                displayName: name,
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
        await crypto.clearDerivedKey(uri);
        if (effectivePassword.isEmpty) {
          effectivePassword = (await ref.read(containerRepositoryProvider).getPassword(uri))?.trim() ?? '';
        }
        if (effectivePassword.isNotEmpty || effectiveKeyfiles.isNotEmpty) {
          result = await lifecycle.unlockContainer(
            uri,
            effectivePassword,
            pim,
            displayName: name,
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
        if (ref.mounted) state = state._copy(loading: false, error: 'Incorrect credentials or invalid container');
        return;
      }

      await AppSecureStorage.instance.write(key: 'temp_pw_$uri', value: effectivePassword);
      final mountedContainer = MountedContainer(
        uri: uri,
        displayName: name,
        volId: result.volId,
        rootFiles: result.files,
        mountedAt: DateTime.now(),
        totalSpace: 0,
        freeSpace: 0,
        readOnly: state.readOnly,
        containerFormat: result.containerFormat,
      );

      if (ref.mounted) {
        state = state._copy(
          loading: false,
          mountedSuccess: (container: mountedContainer, record: null),
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