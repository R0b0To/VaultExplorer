// AutomationSettingsScreen was a plain StatefulWidget holding all of this
// vault's automation config (tier, stored-password flag, capture opt-in,
// stored keyfiles/PIM, token visibility) directly as State fields, loaded
// once in initState. The password field's TextEditingController and the
// obscure-text toggle stay local in the widget -- genuinely ephemeral, same
// reasoning as every other converted screen with a password field. The PIM
// field's TextEditingController also stays local (it's Flutter-controller-
// bound UI), but its *initial* value comes from the load, so the widget
// applies it via `ref.listen` on the null->non-null transition of
// [AutomationSettingsState.loadedPimText] -- same pattern as
// TextEditorScreen's `loadedText`.
//
// Family-keyed by (uri, containerFormat): a fresh screen instance is pushed
// per vault being configured, same scoping as ChangePasswordScreen.
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_automation_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/features/camera/vault_camera_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'automation_settings_controller.g.dart';

class AutomationSettingsState {
  final bool loading;
  final String? token;
  final AutomationTier tier;
  final bool hasStoredPassword;
  final bool captureEnabled;
  final bool tokenVisible;
  final bool savingTier;
  final bool savingPassword;
  final bool savingCapture;
  final List<KeyfileRef> automationKeyfiles;
  final bool pickingAutomationKeyfiles;
  final bool savingAutomationKeyfiles;
  final bool savingAutomationPim;

  /// Null until the initial load completes; the widget applies this into
  /// its PIM TextEditingController exactly once on the null->non-null
  /// transition. A plain empty string can't be used as the "not loaded
  /// yet" sentinel since '' is also the legitimate "no PIM stored" value.
  final String? loadedPimText;

  const AutomationSettingsState({
    this.loading = true,
    this.token,
    this.tier = AutomationTier.none,
    this.hasStoredPassword = false,
    this.captureEnabled = false,
    this.tokenVisible = false,
    this.savingTier = false,
    this.savingPassword = false,
    this.savingCapture = false,
    this.automationKeyfiles = const [],
    this.pickingAutomationKeyfiles = false,
    this.savingAutomationKeyfiles = false,
    this.savingAutomationPim = false,
    this.loadedPimText,
  });

  AutomationSettingsState _copy({
    bool? loading,
    String? token,
    AutomationTier? tier,
    bool? hasStoredPassword,
    bool? captureEnabled,
    bool? tokenVisible,
    bool? savingTier,
    bool? savingPassword,
    bool? savingCapture,
    List<KeyfileRef>? automationKeyfiles,
    bool? pickingAutomationKeyfiles,
    bool? savingAutomationKeyfiles,
    bool? savingAutomationPim,
    String? loadedPimText,
  }) => AutomationSettingsState(
    loading: loading ?? this.loading,
    token: token ?? this.token,
    tier: tier ?? this.tier,
    hasStoredPassword: hasStoredPassword ?? this.hasStoredPassword,
    captureEnabled: captureEnabled ?? this.captureEnabled,
    tokenVisible: tokenVisible ?? this.tokenVisible,
    savingTier: savingTier ?? this.savingTier,
    savingPassword: savingPassword ?? this.savingPassword,
    savingCapture: savingCapture ?? this.savingCapture,
    automationKeyfiles: automationKeyfiles ?? this.automationKeyfiles,
    pickingAutomationKeyfiles:
        pickingAutomationKeyfiles ?? this.pickingAutomationKeyfiles,
    savingAutomationKeyfiles:
        savingAutomationKeyfiles ?? this.savingAutomationKeyfiles,
    savingAutomationPim: savingAutomationPim ?? this.savingAutomationPim,
    loadedPimText: loadedPimText ?? this.loadedPimText,
  );
}

/// Outcome of [AutomationSettings.saveAutomationPim]: the widget reflects
/// [pim] back into its TextEditingController on success only, mirroring the
/// original's setState that wrote the clamped value back after saving.
typedef PimSaveResult = ({bool ok, int? pim});

@riverpod
class AutomationSettings extends _$AutomationSettings {
  @override
  AutomationSettingsState build(String uri, String containerFormat) {
    _load();
    return const AutomationSettingsState();
  }

  bool get _isVeraCryptOrLuks {
    final fmt = ContainerFormat.fromWire(containerFormat);
    return fmt == ContainerFormat.veracrypt || fmt.isLuks;
  }

  String? get _formatForAutomation {
    final fmt = ContainerFormat.fromWire(containerFormat);
    return fmt.isFolderVault ? containerFormat : null;
  }

  /// getAutomationKeyfiles only returns the raw stored URI/path strings,
  /// not a resolved display name (see AutomationSettingsHandlers.kt --
  /// AutomationSettings has never needed to persist one), so a friendly
  /// label for a previously-saved keyfile is derived here rather than
  /// shown as the full URI.
  String _displayNameForKeyfileUri(String uri) {
    final segments = Uri.tryParse(uri)?.pathSegments ?? const <String>[];
    final last = segments.isNotEmpty ? segments.last : '';
    if (last.isEmpty) return uri;
    try {
      return Uri.decodeComponent(last);
    } catch (_) {
      return last;
    }
  }

  Future<void> _load() async {
    final api = ref.read(vaultAutomationApiProvider);
    final token = await api.getAutomationToken();
    final config = await api.getAutomationVaultConfig(uri);
    // Skipped entirely for formats that can't use them so a folder vault
    // doesn't fire a call whose result would just be discarded.
    final storedKeyfiles = _isVeraCryptOrLuks
        ? await api.getAutomationKeyfiles(uri)
        : null;
    final storedPim = _isVeraCryptOrLuks
        ? await api.getAutomationPim(uri)
        : null;
    if (!ref.mounted) return;
    state = state._copy(
      token: token,
      tier: config.tier,
      hasStoredPassword: config.hasStoredPassword,
      captureEnabled: config.captureEnabled,
      automationKeyfiles: (storedKeyfiles ?? const [])
          .map((k) => (uri: k, displayName: _displayNameForKeyfileUri(k)))
          .toList(),
      loadedPimText: (storedPim != null && storedPim > 0)
          ? storedPim.toString()
          : '',
      loading: false,
    );
  }

  Future<bool> setTier(AutomationTier tier) async {
    state = state._copy(savingTier: true);
    final ok = await ref
        .read(vaultAutomationApiProvider)
        .setAutomationTier(uri, tier, format: _formatForAutomation);
    if (!ref.mounted) return false;
    state = state._copy(
      savingTier: false,
      tier: ok ? tier : null,
      // Kotlin clears the stored capture opt-in server-side any time the
      // vault leaves full tier (see AutomationSettings.setTier's doc
      // comment) -- mirror that here so the switch doesn't keep showing
      // "on" for a moment after dropping to lifecycle-only.
      captureEnabled: (ok && tier != AutomationTier.full) ? false : null,
    );
    return ok;
  }

  /// Turning this on lets a headless automation trigger open the camera
  /// with no Activity/UI on screen -- unlike the in-app capture flow,
  /// there's no later moment where CAMERA/RECORD_AUDIO would naturally get
  /// requested, so this has to request permissions itself before the
  /// opt-in is persisted. Returns an error message to show via snackbar,
  /// or null on success.
  Future<String?> setCaptureEnabled(bool enabled, AppLocalizations l10n) async {
    state = state._copy(savingCapture: true);
    if (enabled) {
      final hasPerms = await VaultCameraController.hasPermissions();
      if (!hasPerms) {
        final granted = await VaultCameraController(
          ref.read(vaultEngineEventsProvider),
        ).requestPermissions();
        if (!ref.mounted) return null;
        if (!granted) {
          state = state._copy(savingCapture: false);
          return l10n.cameraPermissionsRequiredMessage;
        }
      }
    }
    final ok = await ref
        .read(vaultAutomationApiProvider)
        .setAutomationCaptureEnabled(uri, enabled);
    if (!ref.mounted) return null;
    state = state._copy(
      savingCapture: false,
      captureEnabled: ok ? enabled : null,
    );
    return ok ? null : l10n.automationUpdateSettingsFailedMessage;
  }

  /// [password] empty clears the stored password. Returns whether the save
  /// succeeded; the widget derives its own "clearing vs. saving" snackbar
  /// text from the same emptiness check it used before calling this.
  Future<bool> savePassword(String password) async {
    final clearing = password.isEmpty;
    state = state._copy(savingPassword: true);
    final ok = await ref
        .read(vaultAutomationApiProvider)
        .setAutomationPassword(uri, clearing ? null : password);
    if (!ref.mounted) return false;
    state = state._copy(
      savingPassword: false,
      hasStoredPassword: ok ? !clearing : null,
    );
    return ok;
  }

  /// Returns an error message to show via snackbar, or null on success.
  Future<String?> pickAutomationKeyfiles(AppLocalizations l10n) async {
    state = state._copy(pickingAutomationKeyfiles: true);
    try {
      final picked = await ref.read(vaultLifecycleApiProvider).pickKeyfiles();
      if (!ref.mounted) return null;
      final merged = [...state.automationKeyfiles];
      for (final k in picked) {
        if (!merged.any((existing) => existing.uri == k.uri)) merged.add(k);
      }
      state = state._copy(automationKeyfiles: merged);
      return await _saveAutomationKeyfiles(l10n);
    } on PlatformException catch (e) {
      return e.message ?? l10n.couldNotPickKeyfiles;
    } finally {
      if (ref.mounted) {
        state = state._copy(pickingAutomationKeyfiles: false);
      }
    }
  }

  /// Returns an error message to show via snackbar, or null on success.
  Future<String?> removeAutomationKeyfile(
    KeyfileRef keyfile,
    AppLocalizations l10n,
  ) async {
    state = state._copy(
      automationKeyfiles: state.automationKeyfiles
          .where((k) => k.uri != keyfile.uri)
          .toList(),
    );
    return _saveAutomationKeyfiles(l10n);
  }

  Future<String?> _saveAutomationKeyfiles(AppLocalizations l10n) async {
    state = state._copy(savingAutomationKeyfiles: true);
    final paths = state.automationKeyfiles.map((k) => k.uri).toList();
    final ok = await ref
        .read(vaultAutomationApiProvider)
        .setAutomationKeyfiles(uri, paths.isEmpty ? null : paths);
    if (!ref.mounted) return null;
    state = state._copy(savingAutomationKeyfiles: false);
    return ok ? null : l10n.automationUpdateSettingsFailedMessage;
  }

  Future<PimSaveResult> saveAutomationPim(String rawText) async {
    state = state._copy(savingAutomationPim: true);
    final raw = rawText.trim();
    final pim = raw.isEmpty ? null : clampPim(int.tryParse(raw) ?? 0);
    final ok = await ref
        .read(vaultAutomationApiProvider)
        .setAutomationPim(uri, pim);
    if (ref.mounted) state = state._copy(savingAutomationPim: false);
    return (ok: ok, pim: pim);
  }

  Future<bool> regenerateToken() async {
    final newToken = await ref
        .read(vaultAutomationApiProvider)
        .regenerateAutomationToken();
    if (!ref.mounted) return false;
    if (newToken == null) return false;
    state = state._copy(token: newToken, tokenVisible: true);
    return true;
  }

  void toggleTokenVisible() =>
      state = state._copy(tokenVisible: !state.tokenVisible);
}
