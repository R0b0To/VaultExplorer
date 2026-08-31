import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';

part 'container_config_controller.g.dart';

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

  bool get unlockMethodNeedsPassword => unlockMethod != ContainerUnlockMethod.password;

  bool get needsPatternSetup =>
      unlockMethod == ContainerUnlockMethod.pattern && patternHash == null;

  bool get needsPinSetup =>
      unlockMethod == ContainerUnlockMethod.pin && pinHash == null;

  bool isModified(String currentPasswordText, String currentLabelText) {
    if (currentLabelText.trim() != initialLabel) return true;
    if (unlockMethod != initialUnlockMethod) return true;
    if (autoCloseMins != initialAutoCloseMins) return true;
    if (documentProvider != initialDocumentProvider) return true;
    if (thumbnailCacheMode != initialThumbnailCacheMode) return true;
    if (thumbnailQuality != initialThumbnailQuality) return true;
    if (cacheDerivedKey != initialCacheDerivedKey) return true;
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
      autoCloseMins: 0,
      documentProvider: false,
      cacheDerivedKey: false,
      settingsLocked: false,
      isMounted: false,
      initialLabel: initialLabel,
      initialUnlockMethod: ContainerUnlockMethod.password,
      initialAutoCloseMins: 0,
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
    final initialAutoCloseMins = rec?.autoCloseMins ?? 0;
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

  Future<void> _initAsync(ContainerRecord? rec, AppSettings? appSettings) async {
    String? tempPw;
    try {
      tempPw = await AppSecureStorage.instance.read(key: 'temp_pw_${params.uri}');
    } catch (_) {}

    bool biometricAvailable = false;
    try {
      final localAuth = LocalAuthentication();
      biometricAvailable = await localAuth.canCheckBiometrics && await localAuth.isDeviceSupported();
    } catch (_) {}

    ThumbnailCacheMode? thumbMode = state.thumbnailCacheMode;
    ThumbnailQuality? thumbQuality = state.thumbnailQuality;
    bool derivedKey = state.cacheDerivedKey;

    try {
      final settings = appSettings ?? await ref.read(appSettingsServiceProvider).loadSettings();
      thumbMode ??= settings.defaultThumbnailCacheMode;
      thumbQuality ??= settings.defaultThumbnailQuality;
      if (appSettings == null && rec == null) {
        derivedKey = settings.defaultDerivedKeyCacheEnabled;
      }
    } catch (_) {
      thumbMode ??= ThumbnailCacheMode.appCache;
    }

    String? patternHash;
    String? pinHash;
    if (state.unlockMethod == ContainerUnlockMethod.pattern) {
      patternHash = await ref.read(containerRepositoryProvider).getPatternHash(params.uri);
    }
    if (state.unlockMethod == ContainerUnlockMethod.pin) {
      pinHash = await ref.read(containerRepositoryProvider).getPinHash(params.uri);
    }

    if (!ref.mounted) return;
    state = state._copy(
      tempPassword: tempPw,
      biometricAvailable: biometricAvailable,
      thumbnailCacheMode: thumbMode,
      thumbnailQuality: thumbQuality,
      cacheDerivedKey: derivedKey,
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
    } catch (_) {
    } finally {
      if (ref.mounted) state = state._copy(clearingCache: false);
    }
    return (
      appCacheCleared: appCacheCleared,
      containerCacheCleared: containerCacheCleared,
      isLocked: isLocked,
    );
  }

  Future<ContainerRecord?> saveContainer({
    required String passwordText,
    required String labelText,
    required ContainerRecord? existingRecord,
  }) async {
    state = state._copy(saving: true);
    final label = labelText.trim().isEmpty ? params.currentLabel : labelText.trim();
    final needsPassword = state.unlockMethodNeedsPassword;
    final shouldSavePassword = needsPassword && (state.wasPasswordless || state.changePassword);

    final record = ContainerRecord(
      uri: params.uri,
      label: label,
      rememberPassword: needsPassword,
      unlockMethod: state.unlockMethod,
      autoCloseMins: state.autoCloseMins,
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
    );

    await ref.read(containerRepositoryProvider).save(record);
    if (!state.isMounted && !state.cacheDerivedKey) {
      try {
        await ref.read(vaultLifecycleApiProvider).lockContainer(params.uri);
      } catch (_) {}
    }
    if (ref.mounted) state = state._copy(saving: false);
    return record;
  }
}