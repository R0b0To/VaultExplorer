import 'dart:async';
import 'package:local_auth/local_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/biometric_enrollment_guard.dart';
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
  final bool usbAttachPromptEnabled;

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
    this.usbAttachPromptEnabled = true,
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
    bool? usbAttachPromptEnabled,
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
    usbAttachPromptEnabled:
        usbAttachPromptEnabled ?? this.usbAttachPromptEnabled,
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
    } catch (e) {
      VeLog.w('AppSettingsController', 'Failed to load settings', e);
    }
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
    } catch (e) {
      VeLog.w('AppSettingsController', 'All-files-access check failed', e);
    }
    if (!ref.mounted) return;

    int sdkInt = 34;
    try {
      sdkInt = await lifecycle.getAndroidSdkInt();
    } catch (e) {
      VeLog.w('AppSettingsController', 'Android SDK version check failed', e);
    }
    if (!ref.mounted) return;

    DisguiseMode disguiseMode = DisguiseMode.vault;
    try {
      disguiseMode = await disguiseModeApi.getMode();
    } catch (e) {
      VeLog.w('AppSettingsController', 'Disguise mode lookup failed', e);
    }
    if (!ref.mounted) return;

    bool shareTargetEnabled = false;
    try {
      shareTargetEnabled = await lifecycle.isShareTargetEnabled();
    } catch (e) {
      VeLog.w('AppSettingsController', 'Share-target-enabled check failed', e);
    }
    if (!ref.mounted) return;

    bool usbAttachPromptEnabled = true;
    try {
      usbAttachPromptEnabled = await lifecycle.isUsbAttachPromptEnabled();
    } catch (e) {
      VeLog.w('AppSettingsController', 'USB attach handler lookup failed', e);
    }
    if (!ref.mounted) return;

    state = state._copy(
      settings: s,
      biometricAvailable: bioAvail,
      hasAllStorageAccess: hasAccess,
      androidSdkInt: sdkInt,
      disguiseMode: disguiseMode,
      shareTargetEnabled: shareTargetEnabled,
      usbAttachPromptEnabled: usbAttachPromptEnabled,
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
    final languageChanged = updated.languageCode != state.settings.languageCode;
    state = state._copy(settings: updated);
    if (languageChanged) {
      await ref
          .read(vaultLifecycleApiProvider)
          .setNotificationLocale(updated.languageCode);
    }
    try {
      final persisted = await ref
          .read(appSettingsServiceProvider)
          .updateSettings(updater);
      if (ref.mounted) state = state._copy(settings: persisted);
    } catch (e) {
      VeLog.e('AppSettingsController', 'Failed to persist settings', e);
    }
  }

  /// Explicit, deliberate way to change the app-wide fallback layout mode --
  /// the one folders use when they have no per-folder override (or, with
  /// "Remember Per-Folder Layout" off, the one every folder uses). Kept as
  /// its own method rather than folded into a folder-scoped change, since
  /// this is meant to be an intentional settings action, not an incidental
  /// side effect of browsing (see file_browser_screen.dart's
  /// _onLayoutModeChanged for why that distinction matters).
  Future<void> setDefaultLayoutMode(BrowserLayoutMode mode) =>
      updateSettings((s) => s.copyWith(defaultLayoutMode: mode));

  void setShowPwFields(bool show) =>
      state = state._copy(showPwFields: show, clearPwError: true);

  void setPwError(String? error) =>
      state = state._copy(pwError: error, clearPwError: error == null);

  void setExportBusy(bool busy) => state = state._copy(exportBusy: busy);

  void setImportBusy(bool busy) => state = state._copy(importBusy: busy);

  void setBackupBusy(bool busy) =>
      state = state._copy(exportBusy: busy, importBusy: busy);

  /// Turns the whole master lock off: wipes the password, PIN and pattern
  /// together and drops the biometric sentinel if biometrics were in use.
  Future<void> clearMasterPassword() async {
    if (state.settings.masterUnlockMethod == MasterUnlockMethod.biometrics) {
      await ref.read(biometricEnrollmentGuardProvider).forgetMaster();
      if (!ref.mounted) return;
    }
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

  /// Switches the lock gate's active method. Password, PIN and pattern are
  /// independent credentials, so nothing is wiped on the way: the previously
  /// active one simply stays stored and can be switched back to.
  ///
  /// Returns false, changing nothing, when [method] cannot be used yet: a
  /// credential that is not set, biometrics with no credential behind them,
  /// or biometrics Android refuses to create the sentinel key for (no
  /// biometric enrolled, no secure lock screen).
  ///
  /// Choosing biometrics sets up the sentinel key that lets the gate notice a
  /// later fingerprint/face enrollment (see [BiometricEnrollmentGuard]).
  Future<bool> setMasterUnlockMethod(MasterUnlockMethod method) async {
    final settings = state.settings;
    if (method == settings.masterUnlockMethod) return true;
    if (method == MasterUnlockMethod.biometrics) {
      // Biometrics only ever sit in front of another credential.
      if (!settings.hasMasterCredential) return false;
      if (!await ref.read(biometricEnrollmentGuardProvider).enableMaster()) {
        return false;
      }
    } else if (!settings.hasMasterCredentialFor(method)) {
      return false;
    }
    if (!ref.mounted) return false;
    await _forgetBiometricsIfLeavingFor(method);
    if (!ref.mounted) return false;
    await ref
        .read(appSettingsServiceProvider)
        .setMasterUnlockMethod(state.settings, method);
    if (!ref.mounted) return false;
    state = state._copy();
    return true;
  }

  /// The biometric sentinel belongs to the biometric method: drop it when the
  /// active method moves to something else.
  Future<void> _forgetBiometricsIfLeavingFor(MasterUnlockMethod next) async {
    if (next != MasterUnlockMethod.biometrics &&
        state.settings.masterUnlockMethod == MasterUnlockMethod.biometrics) {
      await ref.read(biometricEnrollmentGuardProvider).forgetMaster();
    }
  }

  /// Persists a freshly-drawn pattern (already hashed by [PatternSetupSheet])
  /// as one of the master lock's credentials. With [makeActive] it is also the
  /// method the gate shows first; without, it is set or changed while the
  /// active method stays as it is. Any other credential is left alone.
  Future<bool> saveMasterPattern(String hash, {bool makeActive = true}) async {
    try {
      if (makeActive) {
        await _forgetBiometricsIfLeavingFor(MasterUnlockMethod.pattern);
        if (!ref.mounted) return false;
      }
      await ref
          .read(appSettingsServiceProvider)
          .saveMasterPattern(state.settings, hash, makeActive: makeActive);
      if (ref.mounted) state = state._copy();
      return true;
    } catch (e) {
      VeLog.e('AppSettingsController', 'Failed to persist master pattern', e);
      return false;
    }
  }

  /// Persists a freshly-entered PIN (already hashed by [PinSetupSheet]) as one
  /// of the master lock's credentials; [makeActive] works as for
  /// [saveMasterPattern].
  Future<bool> saveMasterPin(String hash, {bool makeActive = true}) async {
    try {
      if (makeActive) {
        await _forgetBiometricsIfLeavingFor(MasterUnlockMethod.pin);
        if (!ref.mounted) return false;
      }
      await ref
          .read(appSettingsServiceProvider)
          .saveMasterPin(state.settings, hash, makeActive: makeActive);
      if (ref.mounted) state = state._copy();
      return true;
    } catch (e) {
      VeLog.e('AppSettingsController', 'Failed to persist master PIN', e);
      return false;
    }
  }

  /// Removes one credential and keeps the lock on. Refused (false) when it is
  /// the only one left -- turn the lock off with [clearMasterPassword]
  /// instead, otherwise the gate would be left with nothing to unlock it.
  /// If the removed credential was the active method, the first remaining
  /// credential takes over; biometrics, if active, stay active.
  Future<bool> removeMasterCredential(MasterUnlockMethod method) async {
    final settings = state.settings;
    if (!method.isCredential) return false;
    if (!settings.hasMasterCredentialFor(method)) return true;
    final remaining = [
      for (final m in settings.configuredMasterCredentials)
        if (m != method) m,
    ];
    if (remaining.isEmpty) return false;
    final service = ref.read(appSettingsServiceProvider);
    switch (method) {
      case MasterUnlockMethod.password:
        await service.clearMasterPasswordCredential(settings);
      case MasterUnlockMethod.pin:
        await service.clearMasterPin(settings);
      case MasterUnlockMethod.pattern:
        await service.clearMasterPattern(settings);
      case MasterUnlockMethod.biometrics:
        return false;
    }
    if (!ref.mounted) return false;
    if (settings.masterUnlockMethod == method) {
      await service.setMasterUnlockMethod(state.settings, remaining.first);
      if (!ref.mounted) return false;
    }
    state = state._copy();
    return true;
  }

  /// Persists the master password. [makeActive] works as for
  /// [saveMasterPattern].
  Future<bool> saveMasterPassword(
    String pw,
    AppLocalizations l10n, {
    bool makeActive = true,
  }) async {
    state = state._copy(saving: true, clearPwError: true);
    try {
      final passwordHasher = ref.read(passwordHasherProvider);
      final (:hash, :salt) = await passwordHasher.deriveHash(pw);
      if (!ref.mounted) return false;
      if (makeActive) {
        await _forgetBiometricsIfLeavingFor(MasterUnlockMethod.password);
        if (!ref.mounted) return false;
      }
      await ref
          .read(appSettingsServiceProvider)
          .saveMasterPassword(
            state.settings,
            hash,
            salt,
            makeActive: makeActive,
          );
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

  Future<bool> setUsbAttachPromptEnabled(bool enable) async {
    try {
      final lifecycle = ref.read(vaultLifecycleApiProvider);
      await lifecycle.setUsbAttachPromptEnabled(enable);
      if (!ref.mounted) return false;
      final actual = await lifecycle.isUsbAttachPromptEnabled();
      if (!ref.mounted) return false;
      state = state._copy(usbAttachPromptEnabled: actual);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> applyImportedSettings(AppSettings imported) async {
    if (imported.languageCode != state.settings.languageCode) {
      await ref
          .read(vaultLifecycleApiProvider)
          .setNotificationLocale(imported.languageCode);
    }
    state = state._copy(settings: imported);
  }
}
