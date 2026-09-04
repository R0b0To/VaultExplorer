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
  final bool backupBusy;

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
    this.backupBusy = false,
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
    bool? backupBusy,
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
    backupBusy: backupBusy ?? this.backupBusy,
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

    state = state._copy(
      settings: s,
      biometricAvailable: bioAvail,
      hasAllStorageAccess: hasAccess,
      androidSdkInt: sdkInt,
      disguiseMode: disguiseMode,
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

  void setBackupBusy(bool busy) => state = state._copy(backupBusy: busy);

  Future<void> clearMasterPassword() async {
    await ref
        .read(appSettingsServiceProvider)
        .clearMasterPassword(state.settings);
    await updateSettings(
      (s) => s.copyWith(
        useMasterPassword: false,
        masterPasswordIsFingerprint: false,
      ),
    );
    state = state._copy(showPwFields: false, clearPwError: true);
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

  void applyImportedSettings(AppSettings imported) {
    state = state._copy(settings: imported);
  }
}
