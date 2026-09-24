import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/inputs/auto_lock_duration_options.dart'
    show kInheritAutoLockDuration;
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

part 'container_config_controller.g.dart';

/// [ContainerConfigState.derivedKeyLifetimeDays] value meaning "no expiry":
/// the cached key stays until caching is switched off.
const int kNoDerivedKeyExpiry = 0;

/// Picker-only sentinel meaning "leave the expiry that is already stored
/// alone". Never stored in state; see [ContainerConfigController.setDerivedKeyLifetimeDays].
const int kKeepDerivedKeyExpiry = -1;

/// Lifetimes offered for a cached derived key, in days.
const List<int> kDerivedKeyLifetimePresetDays = [1, 7, 30, 90];

@immutable
class ContainerConfigParams {
  final String uri;
  final String currentLabel;
  final String containerFormat;

  const ContainerConfigParams({
    required this.uri,
    required this.currentLabel,
    required this.containerFormat,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContainerConfigParams &&
          other.uri == uri &&
          other.currentLabel == currentLabel &&
          other.containerFormat == containerFormat;

  @override
  int get hashCode => Object.hash(uri, currentLabel, containerFormat);
}

class ContainerConfigState {
  final String label;
  final ContainerUnlockMethod unlockMethod;
  final int autoCloseMins;
  final bool documentProvider;
  final ThumbnailCacheMode? thumbnailCacheMode;
  final ThumbnailQuality? thumbnailQuality;
  final bool cacheDerivedKey;

  /// The expiry currently stored for this container's cached key, loaded from
  /// the platform layer. Null means none.
  final DateTime? derivedKeyExpiresAt;

  /// A lifetime picked in this session, applied when saving: [kNoDerivedKeyExpiry]
  /// for none, or a number of days counted from the moment of saving. Null means
  /// the picker was not touched and [derivedKeyExpiresAt] stays as it is -- the
  /// expiry is an absolute date and is only overwritten by an explicit choice.
  final int? derivedKeyLifetimeDays;
  final int cipherId;
  final int hashId;
  final List<KeyfileRef> keyfiles;
  final bool pickingKeyfiles;
  final String? patternHash;
  final String? pinHash;
  final bool biometricAvailable;
  final bool settingsLocked;
  final bool changePassword;
  final bool saving;
  final bool loadingPassword;
  final bool clearingCache;
  final String? tempPassword;
  final String? tempPim;
  final bool isMounted;

  // Baseline initial state for change detection
  final String initialLabel;
  final ContainerUnlockMethod initialUnlockMethod;
  final int initialAutoCloseMins;
  final bool initialDocumentProvider;
  final int initialCipherId;
  final int initialHashId;
  final ThumbnailCacheMode? initialThumbnailCacheMode;
  final ThumbnailQuality? initialThumbnailQuality;
  final bool? initialCacheDerivedKey;
  final String? initialPatternHash;
  final String? initialPinHash;
  final List<KeyfileRef> initialKeyfiles;

  const ContainerConfigState({
    required this.label,
    required this.unlockMethod,
    required this.autoCloseMins,
    required this.documentProvider,
    this.thumbnailCacheMode,
    this.thumbnailQuality,
    required this.cacheDerivedKey,
    this.derivedKeyExpiresAt,
    this.derivedKeyLifetimeDays,
    this.cipherId = 255,
    this.hashId = 255,
    this.keyfiles = const [],
    this.pickingKeyfiles = false,
    this.patternHash,
    this.pinHash,
    this.biometricAvailable = false,
    required this.settingsLocked,
    this.changePassword = false,
    this.saving = false,
    this.loadingPassword = true,
    this.clearingCache = false,
    this.tempPassword,
    this.tempPim,
    this.isMounted = false,
    required this.initialLabel,
    required this.initialUnlockMethod,
    required this.initialAutoCloseMins,
    required this.initialDocumentProvider,
    required this.initialCipherId,
    required this.initialHashId,
    this.initialThumbnailCacheMode,
    this.initialThumbnailQuality,
    this.initialCacheDerivedKey,
    this.initialPatternHash,
    this.initialPinHash,
    this.initialKeyfiles = const [],
  });

  bool get wasPasswordless => initialUnlockMethod == ContainerUnlockMethod.password;

  /// The expiry the cached key will have once this is saved: the stored one if
  /// the lifetime was not touched, none for [kNoDerivedKeyExpiry], otherwise
  /// [derivedKeyLifetimeDays] days from [now] (the moment of saving).
  DateTime? effectiveDerivedKeyExpiry([DateTime? now]) {
    final days = derivedKeyLifetimeDays;
    if (days == null) return derivedKeyExpiresAt;
    if (days == kNoDerivedKeyExpiry) return null;
    return (now ?? DateTime.now()).add(Duration(days: days));
  }

  bool get unlockMethodNeedsPassword => unlockMethod != ContainerUnlockMethod.password;

  bool get needsPatternSetup =>
      unlockMethod == ContainerUnlockMethod.pattern && patternHash == null;

  bool get needsPinSetup =>
      unlockMethod == ContainerUnlockMethod.pin && pinHash == null;

  bool isModified(String currentPasswordText, String currentLabelText, [String? currentPimText]) {
    if (currentLabelText.trim() != initialLabel) return true;
    if (currentPimText != null && currentPimText.trim() != (tempPim ?? '')) return true;
    if (unlockMethod != initialUnlockMethod) return true;
    if (autoCloseMins != initialAutoCloseMins) return true;
    if (documentProvider != initialDocumentProvider) return true;
    if (thumbnailCacheMode != initialThumbnailCacheMode) return true;
    if (thumbnailQuality != initialThumbnailQuality) return true;
    if (cacheDerivedKey != initialCacheDerivedKey) return true;
    if (cacheDerivedKey && derivedKeyLifetimeDays != null) return true;
    if (cipherId != initialCipherId) return true;
    if (hashId != initialHashId) return true;
    if (changePassword) return true;
    if (patternHash != initialPatternHash) return true;
    if (pinHash != initialPinHash) return true;

    final initialKeyfilesCount = (initialUnlockMethod != ContainerUnlockMethod.password)
        ? initialKeyfiles.length
        : 0;
    final currentKeyfilesCount = (unlockMethod != ContainerUnlockMethod.password)
        ? keyfiles.length
        : 0;
    if (currentKeyfilesCount != initialKeyfilesCount) return true;

    if (unlockMethod != ContainerUnlockMethod.password && initialKeyfilesCount > 0) {
      final initialUris = initialKeyfiles.map((k) => k.uri).toSet();
      final currentUris = keyfiles.map((k) => k.uri).toSet();
      if (initialUris.difference(currentUris).isNotEmpty ||
          currentUris.difference(initialUris).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  bool canSave(String currentPasswordText) {
    if (needsPatternSetup || needsPinSetup) return false;
    if (unlockMethodNeedsPassword && (wasPasswordless || changePassword)) {
      if (currentPasswordText.isEmpty && !cacheDerivedKey && keyfiles.isEmpty) {
        return false;
      }
    }
    return true;
  }

  ContainerConfigState _copy({
    String? label,
    ContainerUnlockMethod? unlockMethod,
    int? autoCloseMins,
    bool? documentProvider,
    ThumbnailCacheMode? thumbnailCacheMode,
    ThumbnailQuality? thumbnailQuality,
    bool? cacheDerivedKey,
    DateTime? derivedKeyExpiresAt,
    int? derivedKeyLifetimeDays,
    bool clearDerivedKeyLifetimeDays = false,
    int? cipherId,
    int? hashId,
    List<KeyfileRef>? keyfiles,
    bool? pickingKeyfiles,
    String? patternHash,
    bool clearPatternHash = false,
    String? pinHash,
    bool clearPinHash = false,
    bool? biometricAvailable,
    bool? settingsLocked,
    bool? changePassword,
    bool? saving,
    bool? loadingPassword,
    bool? clearingCache,
    String? tempPassword,
    String? tempPim,
    bool? isMounted,
    ThumbnailCacheMode? initialThumbnailCacheMode,
    ThumbnailQuality? initialThumbnailQuality,
    bool? initialCacheDerivedKey,
    String? initialPatternHash,
    String? initialPinHash,
  }) => ContainerConfigState(
    label: label ?? this.label,
    unlockMethod: unlockMethod ?? this.unlockMethod,
    autoCloseMins: autoCloseMins ?? this.autoCloseMins,
    documentProvider: documentProvider ?? this.documentProvider,
    thumbnailCacheMode: thumbnailCacheMode ?? this.thumbnailCacheMode,
    thumbnailQuality: thumbnailQuality ?? this.thumbnailQuality,
    cacheDerivedKey: cacheDerivedKey ?? this.cacheDerivedKey,
    derivedKeyExpiresAt: derivedKeyExpiresAt ?? this.derivedKeyExpiresAt,
    derivedKeyLifetimeDays: clearDerivedKeyLifetimeDays
        ? null
        : (derivedKeyLifetimeDays ?? this.derivedKeyLifetimeDays),
    cipherId: cipherId ?? this.cipherId,
    hashId: hashId ?? this.hashId,
    keyfiles: keyfiles ?? this.keyfiles,
    pickingKeyfiles: pickingKeyfiles ?? this.pickingKeyfiles,
    patternHash: clearPatternHash ? null : (patternHash ?? this.patternHash),
    pinHash: clearPinHash ? null : (pinHash ?? this.pinHash),
    biometricAvailable: biometricAvailable ?? this.biometricAvailable,
    settingsLocked: settingsLocked ?? this.settingsLocked,
    changePassword: changePassword ?? this.changePassword,
    saving: saving ?? this.saving,
    loadingPassword: loadingPassword ?? this.loadingPassword,
    clearingCache: clearingCache ?? this.clearingCache,
    tempPassword: tempPassword ?? this.tempPassword,
    tempPim: tempPim ?? this.tempPim,
    isMounted: isMounted ?? this.isMounted,
    initialLabel: initialLabel,
    initialUnlockMethod: initialUnlockMethod,
    initialAutoCloseMins: initialAutoCloseMins,
    initialDocumentProvider: initialDocumentProvider,
    initialCipherId: initialCipherId,
    initialHashId: initialHashId,
    initialThumbnailCacheMode: initialThumbnailCacheMode ?? this.initialThumbnailCacheMode,
    initialThumbnailQuality: initialThumbnailQuality ?? this.initialThumbnailQuality,
    initialCacheDerivedKey: initialCacheDerivedKey ?? this.initialCacheDerivedKey,
    initialPatternHash: initialPatternHash ?? this.initialPatternHash,
    initialPinHash: initialPinHash ?? this.initialPinHash,
    initialKeyfiles: initialKeyfiles,
  );
}

@riverpod
class ContainerConfigController extends _$ContainerConfigController {
  @override
  ContainerConfigState build(ContainerConfigParams params) {
    final initialLabel = params.currentLabel;
    final state = ContainerConfigState(
      label: initialLabel,
      unlockMethod: ContainerUnlockMethod.password,
      autoCloseMins: kInheritAutoLockDuration,
      documentProvider: false,
      cacheDerivedKey: false,
      settingsLocked: false,
      isMounted: false,
      initialLabel: initialLabel,
      initialUnlockMethod: ContainerUnlockMethod.password,
      initialAutoCloseMins: kInheritAutoLockDuration,
      initialDocumentProvider: false,
      initialCipherId: 255,
      initialHashId: 255,
    );
    return state;
  }

  void initializeFromRecord({
    required ContainerRecord? rec,
    required AppSettings? appSettings,
    required MountedContainer? mountedContainer,
  }) {
    final initialKeyfiles = (rec != null &&
            rec.unlockMethod != ContainerUnlockMethod.password &&
            rec.keyfiles.isNotEmpty)
        ? rec.keyfiles.map((k) => (uri: k['uri']!, displayName: k['name']!)).toList()
        : <KeyfileRef>[];

    final initialLabel = (rec?.label.isNotEmpty == true) ? rec!.label : state.initialLabel;
    final initialUnlockMethod = rec?.unlockMethod ?? ContainerUnlockMethod.password;
    final initialAutoCloseMins = _resolveInitialAutoCloseMins(rec);
    final initialDocumentProvider =
        rec?.documentProvider ?? appSettings?.defaultDocumentProvider ?? false;
    final initialCipherId = rec?.cipherId ?? 255;
    final initialHashId = rec?.hashId ?? 255;
    final initialCacheDerivedKey = rec?.cacheDerivedKey;

    final recentlyUnlocked = mountedContainer != null &&
        DateTime.now().difference(mountedContainer.mountedAt) < const Duration(seconds: 30);
    final settingsLocked = rec != null && !recentlyUnlocked;

    state = ContainerConfigState(
      label: initialLabel,
      unlockMethod: initialUnlockMethod,
      autoCloseMins: initialAutoCloseMins,
      documentProvider: initialDocumentProvider,
      thumbnailCacheMode: rec?.thumbnailCacheMode,
      thumbnailQuality: rec?.thumbnailQuality,
      cacheDerivedKey: rec?.cacheDerivedKey ?? appSettings?.defaultDerivedKeyCacheEnabled ?? false,
      cipherId: initialCipherId,
      hashId: initialHashId,
      keyfiles: List.unmodifiable(initialKeyfiles),
      settingsLocked: settingsLocked,
      loadingPassword: true,
      isMounted: mountedContainer != null,
      initialLabel: initialLabel,
      initialUnlockMethod: initialUnlockMethod,
      initialAutoCloseMins: initialAutoCloseMins,
      initialDocumentProvider: initialDocumentProvider,
      initialCipherId: initialCipherId,
      initialHashId: initialHashId,
      initialThumbnailCacheMode: rec?.thumbnailCacheMode,
      initialThumbnailQuality: rec?.thumbnailQuality,
      initialCacheDerivedKey: initialCacheDerivedKey,
      initialKeyfiles: List.unmodifiable(initialKeyfiles),
    );

    _initAsync(rec, appSettings);
  }

  /// Maps a record's two persisted auto-close fields onto the single
  /// UI-level int the picker in [ContainerConfigState.autoCloseMins] works
  /// with: an explicit duration (>0), 0 for an explicit "Never"
  /// (`autoCloseNever`), or [kInheritAutoLockDuration] ("App Default") for
  /// a brand-new container or one that predates `autoCloseNever` and was
  /// just left at its default.
  static int _resolveInitialAutoCloseMins(ContainerRecord? rec) {
    if (rec == null) return kInheritAutoLockDuration;
    if (rec.autoCloseNever) return 0;
    if (rec.autoCloseMins > 0) return rec.autoCloseMins;
    return kInheritAutoLockDuration;
  }

  Future<void> _initAsync(ContainerRecord? rec, AppSettings? appSettings) async {
    String? tempPw;
    String? tempPim;
    try {
      tempPw = await ref.read(appSecureStorageProvider).read(key: 'temp_pw_${params.uri}');
      tempPim = await ref.read(appSecureStorageProvider).read(key: 'temp_pim_${params.uri}');
      tempPim ??= await ref.read(appSecureStorageProvider).read(key: 'pim_${params.uri}');
    } catch (e) {
      VeLog.w('ContainerConfigController', 'Temp credentials read failed', e);
    }
    if (!ref.mounted) return;

    bool biometricAvailable = false;
    try {
      final localAuth = LocalAuthentication();
      biometricAvailable = await localAuth.canCheckBiometrics && await localAuth.isDeviceSupported();
    } catch (e) {
      VeLog.w('ContainerConfigController', 'Biometric availability check failed', e);
    }
    if (!ref.mounted) return;

    ThumbnailCacheMode? thumbMode = state.thumbnailCacheMode;
    ThumbnailQuality? thumbQuality = state.thumbnailQuality;
    bool derivedKey = state.cacheDerivedKey;

    DateTime? derivedKeyExpiresAt;
    try {
      derivedKeyExpiresAt = await ref
          .read(vaultCryptoApiProvider)
          .getDerivedKeyExpiry(derivedKeyPathForUri(params.uri));
    } catch (e) {
      VeLog.w('ContainerConfigController', 'Derived key expiry read failed', e);
    }
    if (!ref.mounted) return;

    try {
      final toolbarConfig =
          await ref.read(fileManagerToolbarServiceProvider).load();
      thumbMode ??= toolbarConfig.defaultThumbnailCacheMode;
      thumbQuality ??= toolbarConfig.defaultThumbnailQuality;
    } catch (_) {
      thumbMode ??= ThumbnailCacheMode.disabled;
    }
    if (!ref.mounted) return;

    try {
      final settings = appSettings ??
          await ref.read(appSettingsServiceProvider).loadSettings();
      if (appSettings == null && rec == null) {
        derivedKey = settings.defaultDerivedKeyCacheEnabled;
      }
    } catch (e) {
      VeLog.w('ContainerConfigController', 'Settings load failed', e);
    }
    if (!ref.mounted) return;

    String? patternHash;
    String? pinHash;
    if (state.unlockMethod == ContainerUnlockMethod.pattern) {
      patternHash = await ref.read(containerRepositoryProvider).getPatternHash(params.uri);
    }
    if (!ref.mounted) return;
    if (state.unlockMethod == ContainerUnlockMethod.pin) {
      pinHash = await ref.read(containerRepositoryProvider).getPinHash(params.uri);
    }

    if (!ref.mounted) return;
    state = state._copy(
      tempPassword: tempPw,
      tempPim: tempPim,
      biometricAvailable: biometricAvailable,
      thumbnailCacheMode: thumbMode,
      thumbnailQuality: thumbQuality,
      cacheDerivedKey: derivedKey,
      derivedKeyExpiresAt: derivedKeyExpiresAt,
      initialThumbnailCacheMode: thumbMode,
      initialThumbnailQuality: thumbQuality,
      initialCacheDerivedKey: state.initialCacheDerivedKey ?? derivedKey,
      patternHash: patternHash,
      initialPatternHash: patternHash,
      pinHash: pinHash,
      initialPinHash: pinHash,
      loadingPassword: false,
    );
  }

  void setLabel(String label) => state = state._copy(label: label);

  void setUnlockMethod(ContainerUnlockMethod method) {
    state = state._copy(
      unlockMethod: method,
      keyfiles: method == ContainerUnlockMethod.password ? const [] : state.keyfiles,
    );
  }

  void setAutoCloseMins(int mins) => state = state._copy(autoCloseMins: mins);

  void setDocumentProvider(bool val) => state = state._copy(documentProvider: val);

  void setThumbnailCacheMode(ThumbnailCacheMode mode) =>
      state = state._copy(thumbnailCacheMode: mode);

  void setThumbnailQuality(ThumbnailQuality quality) =>
      state = state._copy(thumbnailQuality: quality);

  void setCacheDerivedKey(bool val) => state = state._copy(cacheDerivedKey: val);

  /// Picks how long the cached derived key may live: [kNoDerivedKeyExpiry],
  /// a number of days from saving, or [kKeepDerivedKeyExpiry] to go back to
  /// the expiry already stored. Choosing "none" when none is stored is a no-op
  /// choice and is not tracked as a pending change.
  void setDerivedKeyLifetimeDays(int days) {
    final isNoOp =
        days == kKeepDerivedKeyExpiry ||
        (days == kNoDerivedKeyExpiry && state.derivedKeyExpiresAt == null);
    state = isNoOp
        ? state._copy(clearDerivedKeyLifetimeDays: true)
        : state._copy(derivedKeyLifetimeDays: days);
  }

  void setCipherId(int cipherId) => state = state._copy(cipherId: cipherId);

  void setHashId(int hashId) => state = state._copy(hashId: hashId);

  void setChangePassword(bool val) => state = state._copy(changePassword: val);

  void setPatternHash(String? hash) => state = state._copy(patternHash: hash);

  void setPinHash(String? hash) => state = state._copy(pinHash: hash);

  void unlockSettings({
    String? verifiedPassword,
    List<KeyfileRef>? verifiedKeyfiles,
    int? verifiedCipherId,
    int? verifiedHashId,
  }) {
    state = state._copy(
      settingsLocked: false,
      keyfiles: verifiedKeyfiles ?? state.keyfiles,
      cipherId: verifiedCipherId ?? state.cipherId,
      hashId: verifiedHashId ?? state.hashId,
    );
  }

  Future<void> pickKeyfiles() async {
    state = state._copy(pickingKeyfiles: true);
    try {
      final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
      if (!ref.mounted) return;
      if (picked.isNotEmpty) {
        final existingUris = state.keyfiles.map((k) => k.uri).toSet();
        final newKeyfiles = List<KeyfileRef>.from(state.keyfiles);
        for (final k in picked) {
          if (existingUris.add(k.uri)) newKeyfiles.add(k);
        }
        state = state._copy(keyfiles: newKeyfiles, pickingKeyfiles: false);
      } else {
        state = state._copy(pickingKeyfiles: false);
      }
    } catch (_) {
      if (ref.mounted) state = state._copy(pickingKeyfiles: false);
    }
  }

  void removeKeyfile(KeyfileRef refItem) {
    final newKeyfiles = state.keyfiles.where((k) => k != refItem).toList();
    state = state._copy(keyfiles: newKeyfiles);
  }

  void setKeyfiles(List<KeyfileRef> items) {
    state = state._copy(keyfiles: List.unmodifiable(items));
  }

  Future<({bool appCacheCleared, bool containerCacheCleared, bool isLocked})> clearThumbnailCache() async {
    state = state._copy(clearingCache: true);
    bool appCacheCleared = false;
    bool containerCacheCleared = false;
    bool isLocked = false;
    try {
      final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
      await thumbnailCache.clearAppCacheForUri(params.uri);
      appCacheCleared = true;
      await thumbnailCache.clearInContainerCacheForUri(params.uri);
      containerCacheCleared = true;
    } on PlatformException catch (e) {
      if (e.code == 'NOT_MOUNTED') isLocked = true;
    } catch (e) {
      VeLog.e('ContainerConfigController', 'Thumbnail cache clear failed', e);
    } finally {
      if (ref.mounted) state = state._copy(clearingCache: false);
    }
    return (
      appCacheCleared: appCacheCleared,
      containerCacheCleared: containerCacheCleared,
      isLocked: isLocked,
    );
  }

  /// Hands the derived-key lifetime choice to the platform layer, which owns
  /// the cached key and enforces the expiry -- the expiry is not part of the
  /// container record.
  ///
  /// Switching caching off in this save also removes whatever key is still
  /// cached, along with any expiry, so nothing lingers in the Keystore for a
  /// vault that no longer uses it.
  Future<void> _applyDerivedKeyLifetime() async {
    final keyPath = derivedKeyPathForUri(params.uri);
    try {
      final crypto = ref.read(vaultCryptoApiProvider);
      if (!state.cacheDerivedKey) {
        if (state.initialCacheDerivedKey == true) {
          await crypto.clearDerivedKey(keyPath, removeExpiry: true);
        }
      } else if (state.derivedKeyLifetimeDays != null) {
        await crypto.setDerivedKeyExpiry(
          keyPath,
          state.effectiveDerivedKeyExpiry(),
        );
      }
    } catch (e) {
      VeLog.e(
        'ContainerConfigController',
        'Applying derived key lifetime failed for uri=${VeLog.censorUri(params.uri)}',
        e,
      );
    }
  }

  Future<ContainerRecord?> saveContainer({
    required String passwordText,
    String? pimText,
    required String labelText,
    required ContainerRecord? existingRecord,
  }) async {
    state = state._copy(saving: true);
    final label = labelText.trim().isEmpty ? params.currentLabel : labelText.trim();
    final needsPassword = state.unlockMethodNeedsPassword;
    final shouldSavePassword = needsPassword && (state.wasPasswordless || state.changePassword);

    if (shouldSavePassword && pimText != null) {
      final trimmedPim = pimText.trim();
      if (trimmedPim.isNotEmpty && trimmedPim != '0') {
        await ref.read(appSecureStorageProvider).write(
          key: 'pim_${params.uri}',
          value: trimmedPim,
        );
      } else {
        await ref.read(appSecureStorageProvider).delete(key: 'pim_${params.uri}');
      }
    } else if (!needsPassword) {
      await ref.read(appSecureStorageProvider).delete(key: 'pim_${params.uri}');
    }

    final record = ContainerRecord(
      uri: params.uri,
      label: label,
      rememberPassword: needsPassword,
      unlockMethod: state.unlockMethod,
      // state.autoCloseMins is the picker's UI-level value: 0 = "Never"
      // (explicit exemption), a positive number = an explicit duration, and
      // kInheritAutoLockDuration (or anything else non-positive) = "App
      // Default" / not configured -- stored as autoCloseMins: 0 with
      // autoCloseNever: false, same as a never-touched container.
      autoCloseMins: state.autoCloseMins > 0 ? state.autoCloseMins : 0,
      autoCloseNever: state.autoCloseMins == 0,
      documentProvider: state.documentProvider,
      documentProviderFolders: existingRecord?.documentProviderFolders ?? const [],
      thumbnailCacheMode: state.thumbnailCacheMode,
      thumbnailQuality: state.thumbnailQuality,
      cacheDerivedKey: state.cacheDerivedKey,
      pendingPassword: shouldSavePassword ? passwordText : null,
      pendingPatternHash: state.unlockMethod == ContainerUnlockMethod.pattern ? state.patternHash : null,
      pendingPinHash: state.unlockMethod == ContainerUnlockMethod.pin ? state.pinHash : null,
      cipherId: state.cipherId,
      hashId: state.hashId,
      containerFormat: params.containerFormat,
      keyfiles: needsPassword
          ? state.keyfiles.map((k) => {'uri': k.uri, 'name': k.displayName}).toList()
          : const [],
      compositeCarriers: existingRecord?.compositeCarriers ?? const [],
      pinnedPaths: existingRecord?.pinnedPaths ?? const [],
      bookmarkPaths: existingRecord?.bookmarkPaths ?? const [],
    );

    await ref.read(containerRepositoryProvider).save(record);
    await _applyDerivedKeyLifetime();
    if (!ref.mounted) return record;
    if (!state.isMounted && !state.cacheDerivedKey) {
      try {
        await ref.read(vaultLifecycleApiProvider).lockContainer(params.uri);
      } catch (e) {
        VeLog.e('ContainerConfigController', 'Post-save lock failed for uri=${VeLog.censorUri(params.uri)}', e);
      }
    }
    if (ref.mounted) state = state._copy(saving: false);
    return record;
  }
}