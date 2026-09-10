import 'dart:async';
import 'package:local_auth/local_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'app_settings_controller.g.dart';

class AppSettingsViewState {
  final AppSettings settings;
  final bool loading;
  final bool saving;
  final bool hasAllStorageAccess;
  final int androidSdkInt;
  final DisguiseMode disguiseMode;
  final bool showPwFields;
  final String? pwError;
  final bool biometricAvailable;
  final bool exportBusy;
  final bool importBusy;
  final bool shareTargetEnabled;

  bool get backupBusy => exportBusy || importBusy;

  const AppSettingsViewState({
    required this.settings,
    this.loading = true,
    this.saving = false,
    this.hasAllStorageAccess = false,
    this.androidSdkInt = 34,
    this.disguiseMode = DisguiseMode.vault,
    this.showPwFields = false,
    this.pwError,
    this.biometricAvailable = false,
    this.exportBusy = false,
    this.importBusy = false,
    this.shareTargetEnabled = false,
  });

  AppSettingsViewState _copy({
    AppSettings? settings,
    bool? loading,
    bool? saving,
    bool? hasAllStorageAccess,
    int? androidSdkInt,
    DisguiseMode? disguiseMode,
    bool? showPwFields,
    String? pwError,
    bool clearPwError = false,
    bool? biometricAvailable,
    bool? exportBusy,
    bool? importBusy,
    bool? shareTargetEnabled,
  }) => AppSettingsViewState(
    settings: settings ?? this.settings,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    hasAllStorageAccess: hasAllStorageAccess ?? this.hasAllStorageAccess,
    androidSdkInt: androidSdkInt ?? this.androidSdkInt,
    disguiseMode: disguiseMode ?? this.disguiseMode,
    showPwFields: showPwFields ?? this.showPwFields,
    pwError: clearPwError ? null : (pwError ?? this.pwError),
    biometricAvailable: biometricAvailable ?? this.biometricAvailable,
    exportBusy: exportBusy ?? this.exportBusy,
    importBusy: importBusy ?? this.importBusy,
    shareTargetEnabled: shareTargetEnabled ?? this.shareTargetEnabled,
  );
}

@Riverpod(keepAlive: true)
class AppSettingsController extends _$AppSettingsController {
  final _localAuth = LocalAuthentication();
  Future<void>? _loadFuture;

  @override
  AppSettingsViewState build() {
    final state = AppSettingsViewState(settings: AppSettings());
    Future.microtask(load);
    return state;
  }

  Future<void> load() {
    return _loadFuture ??= _performLoad().whenComplete(() {
      _loadFuture = null;
    });
  }

  Future<void> _performLoad() async {
    final settingsService = ref.read(appSettingsServiceProvider);
    final lifecycle = ref.read(vaultLifecycleApiProvider);

    AppSettings s = state.settings;
    try {
      s = await settingsService.loadSettings();
    } catch (_) {}
    if (!ref.mounted) return;
    VeLog.enabled = s.debugLoggingEnabled;

    bool bioAvail = false;
    try {
      bioAvail =
          await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } catch (e) {
      VeLog.w(
        'AppSettingsController',
        'Biometric availability check failed',
        e,
      );
    }
    if (!ref.mounted) return;

    bool hasAccess = false;
    try {
      hasAccess = await lifecycle.hasAllFilesAccess();
    } catch (_) {}
    if (!ref.mounted) return;

    int sdkInt = 34;
    try {
      sdkInt = await lifecycle.getAndroidSdkInt();
    } catch (_) {}
    if (!ref.mounted) return;

    DisguiseMode disguiseMode = DisguiseMode.vault;
    try {
      disguiseMode = await disguiseModeApi.getMode();
    } catch (_) {}
    if (!ref.mounted) return;

    bool shareTargetEnabled = false;
    try {
      shareTargetEnabled = await lifecycle.isShareTargetEnabled();
    } catch (_) {}
    if (!ref.mounted) return;

    state = state._copy(
      settings: s,
      biometricAvailable: bioAvail,
      hasAllStorageAccess: hasAccess,
      androidSdkInt: sdkInt,
      disguiseMode: disguiseMode,
      shareTargetEnabled: shareTargetEnabled,
      loading: false,
    );
  }

  Future<void> checkStoragePermission() async {
    final hasAccess = await ref
        .read(vaultLifecycleApiProvider)
        .hasAllFilesAccess();
    if (!ref.mounted) return;
    state = state._copy(hasAllStorageAccess: hasAccess);
  }

  Future<void> requestStoragePermission({bool openSettings = false}) async {
    await ref
        .read(vaultLifecycleApiProvider)
        .requestAllFilesAccess(openSettings: openSettings);
    await checkStoragePermission();
  }

  Future<void> updateSettings(
    AppSettings Function(AppSettings current) updater,
  ) async {
    final updated = updater(state.settings);
    state = state._copy(settings: updated);
    try {
      await ref.read(appSettingsServiceProvider).saveSettings(updated);
    } catch (e) {
      VeLog.e('AppSettingsController', 'Failed to persist settings', e);
    }
  }

  void setShowPwFields(bool show) =>
      state = state._copy(showPwFields: show, clearPwError: true);

  void setPwError(String? error) =>
      state = state._copy(pwError: error, clearPwError: error == null);

  void setExportBusy(bool busy) => state = state._copy(exportBusy: busy);

  void setImportBusy(bool busy) => state = state._copy(importBusy: busy);

  void setBackupBusy(bool busy) =>
      state = state._copy(exportBusy: busy, importBusy: busy);

  Future<void> clearMasterPassword() async {
    await ref
        .read(appSettingsServiceProvider)
        .clearMasterPassword(state.settings);
    await updateSettings(
      (s) => s.copyWith(
        useMasterPassword: false,
        masterUnlockMethod: MasterUnlockMethod.password,
      ),
    );
    state = state._copy(showPwFields: false, clearPwError: true);
  }

  /// Switches the lock gate's quick-unlock method. If the outgoing method is
  /// pattern or PIN, its stored hash is wiped first -- mirroring
  /// [ContainerRepository]'s behaviour of dropping a container's unused
  /// unlock credential whenever its [ContainerUnlockMethod] changes, so no
  /// stale hash lingers in the Keystore for a method that's no longer active.
  Future<void> setMasterUnlockMethod(MasterUnlockMethod method) async {
    if (method == state.settings.masterUnlockMethod) return;
    await _clearHashesExcept(method);
    if (!ref.mounted) return;
    await ref
        .read(appSettingsServiceProvider)
        .setMasterUnlockMethod(state.settings, method);
    if (!ref.mounted) return;
    state = state._copy();
  }

  /// Wipes any pattern/PIN hash that doesn't belong to [keep], so at most
  /// one quick-unlock credential ever exists in storage at a time. Called
  /// before *every* method change -- both a plain switch (setMasterUnlockMethod)
  /// and a fresh setup (saveMasterPattern/saveMasterPin) -- because a fresh
  /// setup can itself be how a switch happens (e.g. pattern was active, PIN
  /// wasn't configured yet, so picking PIN goes straight to PinSetupSheet
  /// rather than through setMasterUnlockMethod). Without this, the outgoing
  /// pattern hash would never get cleared on that path, and switching back
  /// to pattern later would silently reactivate the old one instead of
  /// asking for a new one.
  Future<void> _clearHashesExcept(MasterUnlockMethod keep) async {
    final service = ref.read(appSettingsServiceProvider);
    if (keep != MasterUnlockMethod.pattern &&
        state.settings.masterPatternHash != null) {
      await service.clearMasterPattern(state.settings);
    }
    if (!ref.mounted) return;
    if (keep != MasterUnlockMethod.pin && state.settings.masterPinHash != null) {
      await service.clearMasterPin(state.settings);
    }
  }

  /// Persists a freshly-drawn pattern (already hashed by [PatternSetupSheet])
  /// as the master gate's unlock credential and makes it the active method.
  Future<bool> saveMasterPattern(String hash) async {
    try {
      await _clearHashesExcept(MasterUnlockMethod.pattern);
      if (!ref.mounted) return false;
      await ref
          .read(appSettingsServiceProvider)
          .saveMasterPattern(state.settings, hash);
      if (ref.mounted) state = state._copy();
      return true;
    } catch (e) {
      VeLog.e('AppSettingsController', 'Failed to persist master pattern', e);
      return false;
    }
  }

  /// Persists a freshly-entered PIN (already hashed by [PinSetupSheet]) as
  /// the master gate's unlock credential and makes it the active method.
  Future<bool> saveMasterPin(String hash) async {
    try {
      await _clearHashesExcept(MasterUnlockMethod.pin);
      if (!ref.mounted) return false;
      await ref
          .read(appSettingsServiceProvider)
          .saveMasterPin(state.settings, hash);
      if (ref.mounted) state = state._copy();
      return true;
    } catch (e) {
      VeLog.e('AppSettingsController', 'Failed to persist master PIN', e);
      return false;
    }
  }

  Future<bool> saveMasterPassword(String pw, AppLocalizations l10n) async {
    state = state._copy(saving: true, clearPwError: true);
    try {
      final passwordHasher = ref.read(passwordHasherProvider);
      final (:hash, :salt) = await passwordHasher.deriveHash(pw);
      if (!ref.mounted) return false;
      await ref
          .read(appSettingsServiceProvider)
          .saveMasterPassword(state.settings, hash, salt);
      state = state._copy(showPwFields: false, saving: false);
      return true;
    } catch (e) {
      if (ref.mounted) {
        state = state._copy(pwError: l10n.failedToHashPassword, saving: false);
      }
      return false;
    }
  }

  Future<bool> setDiscreteMode(bool enable) async {
    final targetMode = enable ? DisguiseMode.decoy : DisguiseMode.vault;
    try {
      await disguiseModeApi.setMode(targetMode);
      final secureScreenPolicy = ref.read(secureScreenPolicyProvider);
      if (enable) {
        await secureScreenPolicy.disableForDecoy();
      } else {
        await secureScreenPolicy.apply(
          preference: state.settings.blockScreenshots,
        );
      }
      if (!ref.mounted) return false;
      state = state._copy(disguiseMode: targetMode);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// See [VaultLifecycleApi.setShareTargetEnabled]'s doc comment for why
  /// this re-reads PackageManager's own state on success instead of just
  /// trusting [enable] -- belt-and-suspenders against this ever drifting
  /// from the real, OS-level truth the way a plain `shareTargetEnabled:
  /// enable` optimistic update could.
  Future<bool> setShareTargetEnabled(bool enable) async {
    try {
      final lifecycle = ref.read(vaultLifecycleApiProvider);
      await lifecycle.setShareTargetEnabled(enable);
      if (!ref.mounted) return false;
      final actual = await lifecycle.isShareTargetEnabled();
      if (!ref.mounted) return false;
      state = state._copy(shareTargetEnabled: actual);
      return true;
    } catch (_) {
      return false;
    }
  }

  void applyImportedSettings(AppSettings imported) {
    state = state._copy(settings: imported);
  }
}
