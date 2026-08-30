import 'dart:async';
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
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';
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
      await _initUnlockMethod(params.initialUri!);
    } else {
      state = state._copy(loadingAuth: false);
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
        if (ref.mounted) tryBiometric();
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
        );
        lifecycle.warmContainer(result.uri);
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
      );

      if (state.unlockMethod == ContainerUnlockMethod.biometrics) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (ref.mounted) tryBiometric();
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

  Future<void> tryBiometric() async {
    if (params.initialUri == null) return;
    try {
      state = state._copy(isAuthenticating: true);
      final localAuth = LocalAuthentication();
      final ok = await localAuth.authenticate(
        localizedReason: 'Unlock container',
        persistAcrossBackgrounding: true,
      );
      if (ok && ref.mounted) {
        final password = await ref.read(containerRepositoryProvider).getPassword(params.initialUri!);
        if (password != null) {
          await unlock(passwordOverride: password);
        }
      }
    } catch (_) {
    } finally {
      if (ref.mounted) state = state._copy(isAuthenticating: false);
    }
  }

  Future<void> onPatternComplete(List<int> pattern) async {
    if (state.storedPatternHash == null) return;
    final ok = await verifyPattern(pattern, state.storedPatternHash!);
    if (ok) {
      final password = await ref.read(containerRepositoryProvider).getPassword(params.initialUri!);
      if (password != null) {
        await unlock(passwordOverride: password);
      }
    } else {
      state = state._copy(patternError: true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (ref.mounted) {
          state = state._copy(patternError: false, patternResetKey: state.patternResetKey + 1);
        }
      });
    }
  }

  Future<void> onPinComplete(String pin) async {
    if (state.storedPinHash == null) return;
    final ok = await verifyPin(pin, state.storedPinHash!);
    if (ok) {
      final password = await ref.read(containerRepositoryProvider).getPassword(params.initialUri!);
      if (password != null) {
        await unlock(passwordOverride: password);
      }
    } else {
      state = state._copy(pinError: true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (ref.mounted) {
          state = state._copy(pinError: false, pinResetKey: state.pinResetKey + 1);
        }
      });
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
  }) async {
    final uri = state.selectedUri;
    if (uri == null) return;

    var effectivePassword = (passwordOverride ?? passwordText ?? '').trim();
    final effectiveKeyfiles = keyfilePathsOverride ?? state.keyfiles.map((k) => k.uri).toList();

    state = state._copy(loading: true, clearError: true, clearActiveVolId: true, clearProgress: true);
    final lifecycle = ref.read(vaultLifecycleApiProvider);

    try {
      final isFolder = state.isFolderVault;
      final isCryfs = state.isCryfs;
      final isGocryptfs = state.isGocryptfs;
      final isCryptomator = state.isCryptomator;

      if (isFolder) {
        final name = state.selectedName ?? 'Vault';
        var result = isCryptomator
            ? await lifecycle.unlockCryptomatorVault(
                uri,
                effectivePassword,
                displayName: name,
                documentProvider: params.documentProvider,
                autoMountFolders: params.autoMountFolders,
                readOnly: state.readOnly,
              )
            : isGocryptfs
                ? await lifecycle.unlockGocryptfsVault(
                    uri,
                    effectivePassword,
                    displayName: name,
                    documentProvider: params.documentProvider,
                    autoMountFolders: params.autoMountFolders,
                    readOnly: state.readOnly,
                  )
                : await lifecycle.unlockCryfsVault(
                    uri,
                    effectivePassword,
                    displayName: name,
                    documentProvider: params.documentProvider,
                    autoMountFolders: params.autoMountFolders,
                    readOnly: state.readOnly,
                    cacheDerivedKey: shouldCacheDerivedKeyOverride ?? false,
                  );

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

      final result = await lifecycle.unlockContainer(
        uri,
        effectivePassword,
        pim,
        displayName: name,
        documentProvider: params.documentProvider,
        autoMountFolders: params.autoMountFolders,
        cipherId: state.cipherId,
        hashId: state.hashId,
        preservedKey: preservedKey,
        cacheDerivedKey: shouldCacheDerivedKeyOverride ?? false,
        keyfilePaths: effectiveKeyfiles,
        readOnly: state.readOnly,
        protectHiddenVolume: state.protectHiddenVolume,
        hiddenVolumePassword: hiddenPasswordText,
        hiddenVolumePim: hiddenPim,
        hiddenVolumeCipherId: state.hiddenCipherId,
        hiddenVolumeHashId: state.hiddenHashId,
        hiddenVolumeKeyfilePaths: hiddenKeyfiles,
      );

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