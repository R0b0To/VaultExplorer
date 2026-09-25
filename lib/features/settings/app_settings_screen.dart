import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/utils/sensitive_clipboard.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/delete_after_import_mode.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/lock/duress_settings_service.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_setup_sheet.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_pin_verify_sheet.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_setup_sheet.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/data/services/settings_backup_service.dart';
import 'package:vaultexplorer/features/dashboard/widgets/quick_password_generator_sheet.dart';
import 'package:vaultexplorer/features/settings/about_screen.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/emergency_settings_screen.dart';
import 'package:vaultexplorer/features/settings/quick_capture_settings_screen.dart';
import 'package:vaultexplorer/features/settings/logcat_screen.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import '../../app/vault_explorer_app.dart';

class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

const _kAndroidSdkR = 30;
const _kAndroidSdkS = 31;

/// The settings hubs shown in the persistent sidebar on wide/landscape
/// layouts. Order and membership mirror the hub tiles used in the narrow,
/// single-column layout.
enum _SettingsSection { security, storage, fileHandling, appearance, advanced, about }

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen>
    with WidgetsBindingObserver {
  // Which hub is shown in the detail pane when the sidebar layout is
  // active. Only used on wide/landscape layouts; the narrow layout
  // navigates with the app's normal Navigator instead.
  _SettingsSection _selectedSection = _SettingsSection.security;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appSettingsControllerProvider.notifier).checkStoragePermission();
    }
  }

   Widget _buildHubTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool selected = false,
    bool showChevron = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      selected: selected,
      selectedTileColor: cs.secondaryContainer.withValues(alpha: 0.4),
      shape: selected
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
          : null,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          : null,
      trailing: showChevron
          ? Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            )
          : null,
      onTap: onTap,
    );
  }

  /// The persistent sidebar shown alongside the detail pane on
  /// wide/landscape layouts -- same hubs as the narrow layout's list, but
  /// selecting one swaps the detail pane in place instead of pushing a
  /// full-screen route.
  Widget _buildSidebar() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      children: [
        SectionCard(
          children: [
            _buildHubTile(
              icon: Icons.shield_rounded,
              iconColor: cs.primary,
              title: context.l10n.sectionSecurityPrivacy,
              subtitle: context.l10n.settingsHubSecuritySubtitle,
              selected: _selectedSection == _SettingsSection.security,
              showChevron: false,
              onTap: () => setState(() => _selectedSection = _SettingsSection.security),
            ),
            _buildHubTile(
              icon: Icons.settings_input_composite_rounded,
              iconColor: cs.secondary,
              title: context.l10n.sectionKeyStorageIntegration,
              subtitle: context.l10n.settingsHubStorageSubtitle,
              selected: _selectedSection == _SettingsSection.storage,
              showChevron: false,
              onTap: () => setState(() => _selectedSection = _SettingsSection.storage),
            ),
            _buildHubTile(
              icon: Icons.folder_copy_rounded,
              iconColor: cs.tertiary,
              title: context.l10n.sectionVaultFileHandling,
              subtitle: context.l10n.settingsHubFileHandlingSubtitle,
              selected: _selectedSection == _SettingsSection.fileHandling,
              showChevron: false,
              onTap: () => setState(() => _selectedSection = _SettingsSection.fileHandling),
            ),
            _buildHubTile(
              icon: Icons.palette_rounded,
              iconColor: Colors.deepPurpleAccent,
              title: context.l10n.sectionAppearanceInterface,
              subtitle: context.l10n.settingsHubAppearanceSubtitle,
              selected: _selectedSection == _SettingsSection.appearance,
              showChevron: false,
              onTap: () => setState(() => _selectedSection = _SettingsSection.appearance),
            ),
            _buildHubTile(
              icon: Icons.terminal_rounded,
              iconColor: Colors.teal,
              title: '${context.l10n.sectionBackupRestore} & ${context.l10n.sectionDebug}',
              subtitle: context.l10n.settingsHubAdvancedSubtitle,
              selected: _selectedSection == _SettingsSection.advanced,
              showChevron: false,
              onTap: () => setState(() => _selectedSection = _SettingsSection.advanced),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          children: [
            _buildHubTile(
              icon: Icons.info_outline_rounded,
              iconColor: cs.primary,
              title: context.l10n.aboutAppTitle,
              subtitle: context.l10n.versionInfoSubtitle(appVersion),
              selected: _selectedSection == _SettingsSection.about,
              showChevron: false,
              onTap: () => setState(() => _selectedSection = _SettingsSection.about),
            ),
          ],
        ),
      ],
    );
  }

  /// The right-hand detail pane on wide/landscape layouts. Wrapped in its
  /// own [Navigator] so a hub that pushes a deeper page (e.g. Security ->
  /// Emergency Panic & Duress) slides in within this pane only, leaving the
  /// sidebar visible -- rather than covering the whole screen. Keying the
  /// Navigator by the selected section resets that inner stack whenever the
  /// sidebar selection changes.
  Widget _buildDetailPane() {
    return Navigator(
      key: ValueKey(_selectedSection),
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => switch (_selectedSection) {
          _SettingsSection.security => const SecuritySettingsScreen(embedded: true),
          _SettingsSection.storage => const StorageServicesSettingsScreen(embedded: true),
          _SettingsSection.fileHandling => const FileHandlingSettingsScreen(embedded: true),
          _SettingsSection.appearance => const AppearanceSettingsScreen(embedded: true),
          _SettingsSection.advanced => const AdvancedSettingsScreen(embedded: true),
          _SettingsSection.about => const AboutScreen(embedded: true),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appSettingsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          context.l10n.appSettingsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: context.screen.useWideLayout
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: context.screen.secondaryPaneWidth(),
                          child: _buildSidebar(),
                        ),
                        const VerticalDivider(width: 0.2),
                        Expanded(child: _buildDetailPane()),
                      ],
                    )
                  : _buildNarrowHubList(cs, textTheme),
            ),
    );
  }

  /// The narrow-layout hub list: unchanged from before the sidebar was
  /// added -- tapping a hub pushes its screen as a full-screen route.
  Widget _buildNarrowHubList(
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            // Grouped Settings Hubs in a single SectionCard
            SectionCard(
              children: [
                _buildHubTile(
                  icon: Icons.shield_rounded,
                  iconColor: cs.primary,
                  title: context.l10n.sectionSecurityPrivacy,
                  subtitle: context.l10n.settingsHubSecuritySubtitle,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SecuritySettingsScreen(),
                    ),
                  ),
                ),
                _buildHubTile(
                  icon: Icons.settings_input_composite_rounded,
                  iconColor: cs.secondary,
                  title: context.l10n.sectionKeyStorageIntegration,
                  subtitle: context.l10n.settingsHubStorageSubtitle,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StorageServicesSettingsScreen(),
                    ),
                  ),
                ),
                _buildHubTile(
                  icon: Icons.folder_copy_rounded,
                  iconColor: cs.tertiary,
                  title: context.l10n.sectionVaultFileHandling,
                  subtitle: context.l10n.settingsHubFileHandlingSubtitle,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FileHandlingSettingsScreen(),
                    ),
                  ),
                ),
                _buildHubTile(
                  icon: Icons.palette_rounded,
                  iconColor: Colors.deepPurpleAccent,
                  title: context.l10n.sectionAppearanceInterface,
                  subtitle: context.l10n.settingsHubAppearanceSubtitle,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AppearanceSettingsScreen(),
                    ),
                  ),
                ),
                _buildHubTile(
                  icon: Icons.terminal_rounded,
                  iconColor: Colors.teal,
                  title: '${context.l10n.sectionBackupRestore} & ${context.l10n.sectionDebug}',
                  subtitle: context.l10n.settingsHubAdvancedSubtitle,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdvancedSettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // About Card in its own matching SectionCard
            SectionCard(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.info_outline_rounded, color: cs.primary, size: 22),
                  ),
                  title: Text(
                    context.l10n.aboutAppTitle,
                    style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    context.l10n.versionInfoSubtitle(appVersion),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AboutScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. SECURITY, PRIVACY & STEALTH SUB-PAGE
// ─────────────────────────────────────────────────────────────────────────────

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  /// True when this screen is embedded in the wide-layout detail pane
  /// (drawn without its own AppBar/back button) rather than pushed as a
  /// full-screen route.
  final bool embedded;

  const SecuritySettingsScreen({super.key, this.embedded = false});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();
  bool _obscurePw = true;
  bool _obscureConfirm = true;
  final _localAuth = LocalAuthentication();
  bool _recentlyCreatedMasterPassword = false;

  @override
  void dispose() {
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _openPasswordGenerator() async {
    final password = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => const QuickPasswordGeneratorSheet(),
    );

    if (password != null && mounted) {
      setState(() {
        _pwCtrl.text = password;
        _pwConfirmCtrl.text = password;
        _obscurePw = false;
        _obscureConfirm = false;
      });
      await ref.read(sensitiveClipboardProvider).copy(password);
    }
  }

  Future<void> _confirmPassword() async {
    final pw = _pwCtrl.text;
    final confirm = _pwConfirmCtrl.text;
    if (pw.isEmpty) {
      ref.read(appSettingsControllerProvider.notifier).setPwError(context.l10n.passwordCannotBeEmpty);
      return;
    }
    if (pw.length < 4) {
      ref.read(appSettingsControllerProvider.notifier).setPwError(context.l10n.atLeast4CharsRequired);
      return;
    }
    if (pw != confirm) {
      ref.read(appSettingsControllerProvider.notifier).setPwError(context.l10n.passwordsDoNotMatch);
      return;
    }

    final isDuress = await ref.read(duressSettingsServiceProvider).verifyPassword(pw);
    if (isDuress) {
      ref.read(appSettingsControllerProvider.notifier).setPwError(
        context.l10n.masterMatchesDuressPasswordError,
      );
      return;
    }

    final ok = await ref
        .read(appSettingsControllerProvider.notifier)
        .saveMasterPassword(pw, context.l10n);

    if (ok && mounted) {
      _recentlyCreatedMasterPassword = true;
      _pwCtrl.clear();
      _pwConfirmCtrl.clear();
      showAppSnackBar(
        context,
        message: context.l10n.masterPasswordSetSnack,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _selectMasterUnlockMethod(MasterUnlockMethod method) async {
    final settingsState = ref.read(appSettingsControllerProvider);
    if (method == settingsState.settings.masterUnlockMethod) return;

    // Skip verification if the user created the master password in this session
    if (!_recentlyCreatedMasterPassword) {
      final verified = await _verifyCurrentUnlockCredential(settingsState);
      if (!verified || !mounted) return;
    }

    final controller = ref.read(appSettingsControllerProvider.notifier);

    if (method == MasterUnlockMethod.biometrics) {
      try {
        final authenticated = await _localAuth.authenticate(
          localizedReason: context.l10n.biometricUnlockTitle,
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
        if (!authenticated) return;
      } catch (e) {
        VeLog.w('SecuritySettingsScreen', 'Biometric auth failed on toggle', e);
        return;
      }
      if (!mounted) return;
      await controller.setMasterUnlockMethod(method);
      _recentlyCreatedMasterPassword = false;
      return;
    }

    if (method == MasterUnlockMethod.pattern) {
      final configured =
          ref.read(appSettingsControllerProvider).settings.masterPatternHash != null;
      if (configured) {
        await controller.setMasterUnlockMethod(method);
        _recentlyCreatedMasterPassword = false;
      } else {
        await _setupMasterPattern();
      }
      return;
    }

    if (method == MasterUnlockMethod.pin) {
      final configured =
          ref.read(appSettingsControllerProvider).settings.masterPinHash != null;
      if (configured) {
        await controller.setMasterUnlockMethod(method);
        _recentlyCreatedMasterPassword = false;
      } else {
        await _setupMasterPin();
      }
      return;
    }

    await controller.setMasterUnlockMethod(method);
    _recentlyCreatedMasterPassword = false;
  }

  Future<bool> _verifyCurrentUnlockCredential(AppSettingsViewState state) async {
    switch (state.settings.masterUnlockMethod) {
      case MasterUnlockMethod.password:
        return _verifyCurrentMasterPassword(
          state,
          title: context.l10n.masterPasswordTitle,
          message: context.l10n.enterMasterPasswordPrompt,
        );
      case MasterUnlockMethod.biometrics:
        try {
          return await _localAuth.authenticate(
            localizedReason: context.l10n.authenticateToModifySettingsPrompt,
            biometricOnly: true,
            persistAcrossBackgrounding: true,
          );
        } catch (e) {
          VeLog.w('SecuritySettingsScreen', 'Biometric verification failed', e);
          return false;
        }
      case MasterUnlockMethod.pattern:
        final hash = state.settings.masterPatternHash;
        if (hash == null || !mounted) return true;
        final result = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (_) => PatternVerifySheet(storedHash: hash),
        );
        return result != null;
      case MasterUnlockMethod.pin:
        final hash = state.settings.masterPinHash;
        if (hash == null || !mounted) return true;
        final result = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (_) => PinVerifySheet(storedHash: hash),
        );
        return result != null;
    }
  }

  Future<void> _setupMasterPattern() async {
    final duressPatternHash = await ref.read(duressSettingsServiceProvider).getPatternHash();
    if (!mounted) return;
    final hash = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PatternSetupSheet(
        disallowedHash: duressPatternHash,
        disallowedMessage: context.l10n.masterMatchesDuressPatternError,
      ),
    );
    if (hash != null && mounted) {
      await ref.read(appSettingsControllerProvider.notifier).saveMasterPattern(hash);
      _recentlyCreatedMasterPassword = false;
    }
  }

  Future<void> _setupMasterPin() async {
    final duressPinHash = await ref.read(duressSettingsServiceProvider).getPinHash();
    if (!mounted) return;
    final hash = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PinSetupSheet(
        disallowedHash: duressPinHash,
        disallowedMessage: context.l10n.masterMatchesDuressPinError,
      ),
    );
    if (hash != null && mounted) {
      await ref.read(appSettingsControllerProvider.notifier).saveMasterPin(hash);
      _recentlyCreatedMasterPassword = false;
    }
  }

  Future<void> _toggleMasterPassword(AppSettingsViewState state, bool enabled) async {
    if (!enabled) {
      _recentlyCreatedMasterPassword = false;
      if (state.settings.masterPasswordHash == null) {
        _pwCtrl.clear();
        _pwConfirmCtrl.clear();
        ref.read(appSettingsControllerProvider.notifier).setShowPwFields(false);
        ref.read(appSettingsControllerProvider.notifier).updateSettings(
              (s) => s.copyWith(useMasterPassword: false),
            );
        return;
      }
      final verified = await _verifyCurrentMasterPassword(state);
      if (!verified) {
        ref
            .read(appSettingsControllerProvider.notifier)
            .updateSettings((s) => s.copyWith(useMasterPassword: true));
        return;
      }
      _pwCtrl.clear();
      _pwConfirmCtrl.clear();
      await ref.read(appSettingsControllerProvider.notifier).clearMasterPassword();
    } else {
      ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings((s) => s.copyWith(useMasterPassword: true));
      ref.read(appSettingsControllerProvider.notifier).setShowPwFields(true);
    }
  }

  Future<bool> _verifyCurrentMasterPassword(
    AppSettingsViewState state, {
    String? title,
    String? message,
  }) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            final ctrl = TextEditingController();
            String? errorMsg;
            return StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                title: Text(title ?? context.l10n.removeMasterPasswordTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message ?? context.l10n.confirmRemoveMasterPasswordMessage),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      obscureText: true,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: context.l10n.masterPasswordTitle,
                        errorText: errorMsg,
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(context.l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final passwordHasher = ref.read(passwordHasherProvider);
                      final isValid = await passwordHasher.verify(
                        candidate: ctrl.text,
                        hash: state.settings.masterPasswordHash,
                        salt: state.settings.masterPasswordSalt,
                      );
                      if (isValid) {
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } else {
                        setDialogState(() => errorMsg = context.l10n.incorrectPassword);
                      }
                    },
                    child: Text(context.l10n.continueButton),
                  ),
                ],
              ),
            );
          },
        ) ??
        false;
  }

  Future<void> _setDiscreteMode(bool enable) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: enable ? context.l10n.enableDiscreteModeTitle : context.l10n.disableDiscreteModeTitle,
      message: enable ? context.l10n.enableDiscreteModeMessage : context.l10n.disableDiscreteModeMessage,
      confirmLabel: enable ? context.l10n.enable : context.l10n.disable,
    );
    if (!confirmed || !context.mounted) return;

    final targetMode = enable ? DisguiseMode.decoy : DisguiseMode.vault;
    final ok = await ref.read(appSettingsControllerProvider.notifier).setDiscreteMode(enable);

    if (ok && context.mounted) {
      applyDisguiseModeTaskSwitcherLabel(targetMode, context.l10n);
      showAppSnackBar(
        context,
        message: enable ? context.l10n.discreteModeEnabledSnack : context.l10n.discreteModeDisabledSnack,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      SystemNavigator.pop();
    } else if (context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.failedToChangeDiscreteMode,
        tone: AppBannerTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appSettingsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final body = SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. App Authentication
                SectionHeader(context.l10n.masterPasswordTitle),
                SectionCard(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          title: Text(
                            context.l10n.masterPasswordTitle,
                            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            state.settings.useMasterPassword &&
                                    state.settings.masterPasswordHash != null
                                ? context.l10n.masterPasswordActiveSubtitle
                                : context.l10n.masterPasswordInactiveSubtitle,
                            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          value: state.settings.useMasterPassword,
                          onChanged: (v) => _toggleMasterPassword(state, v),
                        ),
                        if (state.settings.useMasterPassword &&
                            state.showPwFields &&
                            state.settings.masterPasswordHash == null) ...[
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: AutofillGroup(
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _pwCtrl,
                                    obscureText: _obscurePw,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: cs.surfaceContainerHighest,
                                      labelText: context.l10n.masterPasswordFieldLabel,
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(Icons.auto_awesome_rounded, size: 20, color: cs.primary),
                                            tooltip: context.l10n.generateStrongPasswordTooltip,
                                            onPressed: _openPasswordGenerator,
                                          ),
                                          PasswordVisibilityToggle(
                                            obscured: _obscurePw,
                                            onToggle: () => setState(() => _obscurePw = !_obscurePw),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _pwConfirmCtrl,
                                    obscureText: _obscureConfirm,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: cs.surfaceContainerHighest,
                                      labelText: context.l10n.confirmPasswordLabel,
                                      suffixIcon: PasswordVisibilityToggle(
                                        obscured: _obscureConfirm,
                                        onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                                      ),
                                    ),
                                  ),
                                  if (state.pwError != null) ...[
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        state.pwError!,
                                        style: textTheme.bodySmall?.copyWith(color: cs.error),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: state.saving
                                              ? null
                                              : () {
                                                  _pwCtrl.clear();
                                                  _pwConfirmCtrl.clear();
                                                  ref.read(appSettingsControllerProvider.notifier).setShowPwFields(false);
                                                  ref.read(appSettingsControllerProvider.notifier).updateSettings(
                                                        (s) => s.copyWith(useMasterPassword: false),
                                                      );
                                                },
                                          child: Text(context.l10n.cancel),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: state.saving ? null : _confirmPassword,
                                          child: state.saving
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                )
                                              : Text(context.l10n.setPassword),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (state.settings.useMasterPassword &&
                        state.settings.masterPasswordHash != null &&
                        !state.showPwFields)
                      OptionPickerTile<MasterUnlockMethod>(
                        label: context.l10n.unlockCredentialsLabel,
                        value: state.settings.masterUnlockMethod,
                        subtitle: state.settings.masterUnlockMethod.getLocalizedSubtitle(context.l10n),
                        options: MasterUnlockMethod.values
                            .where(
                              (m) =>
                                  m != MasterUnlockMethod.biometrics ||
                                  state.biometricAvailable ||
                                  state.settings.masterUnlockMethod == m,
                            )
                            .map((m) {
                          final isUnavailableBio = m == MasterUnlockMethod.biometrics && !state.biometricAvailable;
                          return SelectOption(
                            value: m,
                            label: isUnavailableBio
                                ? '${m.getLocalizedLabel(context.l10n)} ${context.l10n.unavailableSuffixLabel}'
                                : m.getLocalizedLabel(context.l10n),
                            subtitle: m.getLocalizedSubtitle(context.l10n),
                          );
                        }).toList(),
                        onChanged: _selectMasterUnlockMethod,
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. App Lock Behavior -- independent of vault auto-lock
                // below: only controls how often the lock gate is re-shown,
                // never whether mounted containers get unmounted.
                if (state.settings.useMasterPassword &&
                    state.settings.masterPasswordHash != null &&
                    !state.showPwFields) ...[
                  SectionHeader(context.l10n.appLockBehaviorTitle),
                  SectionCard(
                    children: [
                      OptionPickerTile<int>(
                        label: context.l10n.autoLockTimeoutLabel,
                        value: state.settings.appLockAfterMins,
                        options: autoLockDurationOptions(
                          context,
                          zeroOption: SelectOption(value: 0, label: context.l10n.immediately),
                          currentMinutes: state.settings.appLockAfterMins,
                        ),
                        onChanged: (v) {
                          if (v == kCustomAutoLockDuration) {
                            pickCustomAutoLockDuration(
                              context,
                              currentMinutes: state.settings.appLockAfterMins,
                              onPicked: (mins) => ref
                                  .read(appSettingsControllerProvider.notifier)
                                  .updateSettings((s) => s.copyWith(appLockAfterMins: mins)),
                            );
                          } else {
                            ref
                                .read(appSettingsControllerProvider.notifier)
                                .updateSettings((s) => s.copyWith(appLockAfterMins: v));
                          }
                        },
                      ),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        title: Text(
                          context.l10n.lockAppOnScreenOffTitle,
                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          context.l10n.lockAppOnScreenOffSubtitle,
                          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        value: state.settings.lockAppOnScreenLock,
                        onChanged: (v) => ref
                            .read(appSettingsControllerProvider.notifier)
                            .updateSettings((s) => s.copyWith(lockAppOnScreenLock: v)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 3. Auto-Lock & Screen Privacy (vault containers)
                SectionHeader(context.l10n.autoLockContainersTitle),
                SectionCard(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.autoLockContainersTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.autoLockContainersSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.settings.lockContainersOnScreenLock,
                      onChanged: (v) => ref.read(appSettingsControllerProvider.notifier).updateSettings(
                            (s) => s.copyWith(
                              lockContainersOnScreenLock: v,
                              autoLockMins: v && s.autoLockMins == 0 ? 5 : (!v ? 0 : s.autoLockMins),
                            ),
                          ),
                    ),
                    if (state.settings.lockContainersOnScreenLock)
                      OptionPickerTile<int>(
                        label: context.l10n.autoLockTimeoutLabel,
                        value: state.settings.autoLockMins,
                        options: autoLockDurationOptions(
                          context,
                          zeroOption: SelectOption(value: 0, label: context.l10n.immediately),
                          currentMinutes: state.settings.autoLockMins,
                        ),
                        onChanged: (v) {
                          if (v == kCustomAutoLockDuration) {
                            pickCustomAutoLockDuration(
                              context,
                              currentMinutes: state.settings.autoLockMins,
                              onPicked: (mins) => ref
                                  .read(appSettingsControllerProvider.notifier)
                                  .updateSettings((s) => s.copyWith(autoLockMins: mins)),
                            );
                          } else {
                            ref
                                .read(appSettingsControllerProvider.notifier)
                                .updateSettings((s) => s.copyWith(autoLockMins: v));
                          }
                        },
                      ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.blockScreenshotsTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.blockScreenshotsSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.settings.blockScreenshots,
                      onChanged: (v) async {
                        await ref.read(secureScreenPolicyProvider).apply(preference: v);
                        await ref
                            .read(appSettingsControllerProvider.notifier)
                            .updateSettings((s) => s.copyWith(blockScreenshots: v));
                      },
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.cacheDerivedKeysTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.cacheDerivedKeysSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.settings.defaultDerivedKeyCacheEnabled,
                      onChanged: (v) => ref.read(appSettingsControllerProvider.notifier).updateSettings(
                            (s) => s.copyWith(defaultDerivedKeyCacheEnabled: v),
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 3a. Mask Mode (disguise the app's identity)
                SectionHeader(context.l10n.sectionMaskMode),
                SectionCard(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.discreteModeTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        state.disguiseMode == DisguiseMode.decoy
                            ? context.l10n.discreteModeActiveSubtitle
                            : context.l10n.discreteModeInactiveSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.disguiseMode == DisguiseMode.decoy,
                      onChanged: _setDiscreteMode,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 3b. Emergency Panic & Duress (its own concept: wipe/duress
                // triggers, separate from disguising the app's identity)
                SectionHeader(context.l10n.emergencyPanicTitle),
                SectionCard(
                  children: [
                    ListTile(
                      leading: Icon(Icons.warning_amber_rounded, color: cs.error),
                      title: Text(
                        context.l10n.emergencyPanicTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.emergencyPanicSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const EmergencySettingsScreen()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 3c. Quick Capture (a productivity shortcut, not a stealth
                // or emergency feature -- its own section)
                SectionHeader(context.l10n.quickCaptureSettingsTitle),
                SectionCard(
                  children: [
                    ListTile(
                      leading: Icon(Icons.bolt_rounded, color: cs.primary),
                      title: Text(
                        context.l10n.quickCaptureSettingsTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.quickCaptureSettingsSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const QuickCaptureSettingsScreen()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

    if (widget.embedded) {
      return Scaffold(body: body);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.sectionSecurityPrivacy,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. STORAGE & SYSTEM INTEGRATION SUB-PAGE
// ─────────────────────────────────────────────────────────────────────────────

class StorageServicesSettingsScreen extends ConsumerWidget {
  /// True when embedded in the wide-layout detail pane instead of pushed
  /// as a full-screen route.
  final bool embedded;

  const StorageServicesSettingsScreen({super.key, this.embedded = false});

  Future<void> _toggleStoragePermission(
    BuildContext context,
    WidgetRef ref,
    AppSettingsViewState state,
    bool enable,
  ) async {
    final isLegacy = state.androidSdkInt < _kAndroidSdkR;
    if (enable) {
      final grant = await showAppConfirmDialog(
        context,
        title: isLegacy
            ? context.l10n.enableStoragePermissionLegacyTitle
            : context.l10n.enableFastStorageAccessTitle,
        message: isLegacy
            ? context.l10n.enableStoragePermissionLegacyMessage
            : context.l10n.enableFastStorageAccessMessage,
        confirmLabel: isLegacy ? context.l10n.continueButton : context.l10n.openSettings,
      );
      if (grant && context.mounted) {
        await ref.read(appSettingsControllerProvider.notifier).requestStoragePermission();
      }
    } else {
      final revoke = await showAppConfirmDialog(
        context,
        title: context.l10n.disableStorageAccessTitle,
        message: isLegacy
            ? context.l10n.disableStoragePermissionLegacyMessage
            : context.l10n.disableStorageAccessMessage,
        confirmLabel: context.l10n.openSettings,
      );
      if (revoke && context.mounted) {
        await ref.read(appSettingsControllerProvider.notifier).requestStoragePermission(openSettings: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appSettingsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                SectionCard(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.fastStorageAccessTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        state.hasAllStorageAccess
                            ? context.l10n.fastStorageAccessGrantedSubtitle
                            : context.l10n.fastStorageAccessNotGrantedSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.hasAllStorageAccess,
                      onChanged: (v) => _toggleStoragePermission(context, ref, state, v),
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.keepVaultsRunningInBackgroundTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.keepVaultsRunningInBackgroundSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.settings.keepVaultsRunningInBackground,
                      onChanged: (v) async {
                        if (v) {
                          final granted = await ref.read(vaultLifecycleApiProvider).requestNotificationPermission();
                          if (!granted && context.mounted) {
                            showAppSnackBar(
                              context,
                              message: context.l10n.notificationPermissionDeniedMessage,
                              tone: AppBannerTone.warning,
                            );
                          }
                        }
                        await ref.read(vaultLifecycleApiProvider).syncBackgroundService(enabled: v);
                        await ref.read(appSettingsControllerProvider.notifier).updateSettings(
                              (s) => s.copyWith(keepVaultsRunningInBackground: v),
                            );
                      },
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.androidFileProviderTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.androidFileProviderSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.settings.defaultDocumentProvider,
                      onChanged: (v) => ref.read(appSettingsControllerProvider.notifier).updateSettings(
                            (s) => s.copyWith(defaultDocumentProvider: v),
                          ),
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.shareSheetIntegrationTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.shareSheetIntegrationSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.shareTargetEnabled,
                      onChanged: (v) async {
                        final ok = await ref.read(appSettingsControllerProvider.notifier).setShareTargetEnabled(v);
                        if (!ok && context.mounted) {
                          showAppSnackBar(
                            context,
                            message: context.l10n.shareSheetIntegrationUpdateErrorMessage,
                            tone: AppBannerTone.warning,
                          );
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.autoLockOnShareImportTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.autoLockOnShareImportSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.settings.autoLockOnShareImport,
                      onChanged: (v) => ref
                          .read(appSettingsControllerProvider.notifier)
                          .updateSettings((s) => s.copyWith(autoLockOnShareImport: v)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

    if (embedded) {
      return Scaffold(body: body);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.sectionKeyStorageIntegration,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. VAULT & FILE HANDLING SUB-PAGE
// ─────────────────────────────────────────────────────────────────────────────

class FileHandlingSettingsScreen extends ConsumerWidget {
  /// True when embedded in the wide-layout detail pane instead of pushed
  /// as a full-screen route.
  final bool embedded;

  const FileHandlingSettingsScreen({super.key, this.embedded = false});

  String _labelForAssociation(BuildContext context, String value) {
    if (value == 'editor') return context.l10n.fileAssocInAppTextEditor;
    if (value == 'media') return context.l10n.fileAssocInAppMediaViewer;
    if (value.startsWith('package:')) {
      return context.l10n.fileAssocAppPrefix(value.substring(8));
    }
    return context.l10n.fileAssocExternalApp;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appSettingsControllerProvider);
    final fmSettingsState = ref.watch(fileManagerToolbarSettingsProvider(null));
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                SectionCard(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.autoOpenOnUnlockTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        state.settings.autoOpenOnUnlock
                            ? context.l10n.autoOpenOnUnlockActiveSubtitle
                            : context.l10n.autoOpenOnUnlockInactiveSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.settings.autoOpenOnUnlock,
                      onChanged: (v) => ref
                          .read(appSettingsControllerProvider.notifier)
                          .updateSettings((s) => s.copyWith(autoOpenOnUnlock: v)),
                    ),
                    OptionPickerTile<DeleteAfterImportMode>(
                      label: context.l10n.deleteAfterImportLabel,
                      value: state.settings.deleteAfterImportMode,
                      subtitle: state.settings.deleteAfterImportMode.getLocalizedLabel(context.l10n),
                      options: DeleteAfterImportMode.values.map((mode) {
                        return SelectOption(
                          value: mode,
                          label: mode.getLocalizedLabel(context.l10n),
                          subtitle: mode.getLocalizedSubtitle(context.l10n),
                        );
                      }).toList(),
                      onChanged: (v) => ref
                          .read(appSettingsControllerProvider.notifier)
                          .updateSettings((s) => s.copyWith(deleteAfterImportMode: v)),
                    ),
                    OptionPickerTile<ThumbnailCacheMode>(
                      label: context.l10n.thumbnailCachingDefaultLabel,
                      value: fmSettingsState.config.defaultThumbnailCacheMode,
                      options: ThumbnailCacheMode.values.map((mode) {
                        return SelectOption(
                          value: mode,
                          label: mode.getLocalizedLabel(context.l10n),
                          subtitle: mode.getLocalizedDescription(context.l10n),
                        );
                      }).toList(),
                      onChanged: (v) => ref
                          .read(fileManagerToolbarSettingsProvider(null).notifier)
                          .setDefaultThumbnailCacheMode(v),
                    ),
                    ThumbnailQualityTile(
                      label: context.l10n.thumbnailQualityDefaultLabel,
                      value: fmSettingsState.config.defaultThumbnailQuality,
                      onChanged: (v) => ref
                          .read(fileManagerToolbarSettingsProvider(null).notifier)
                          .setDefaultThumbnailQuality(v),
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.enableJsHtmlTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        state.settings.htmlEnableJavaScript
                            ? context.l10n.jsEnabledSubtitle
                            : context.l10n.jsDisabledSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.settings.htmlEnableJavaScript,
                      onChanged: (v) => ref
                          .read(appSettingsControllerProvider.notifier)
                          .updateSettings((s) => s.copyWith(htmlEnableJavaScript: v)),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            context.l10n.fileAssociationsHeader,
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (state.settings.extensionPreferences.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            child: Text(
                              context.l10n.noFileAssociationsYet,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                          )
                        else ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                            child: Text(
                              context.l10n.defaultActionsHeader,
                              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                          ...state.settings.extensionPreferences.entries.map((entry) {
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              title: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '.${entry.key.toUpperCase()}',
                                      style: textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _labelForAssociation(context, entry.value),
                                      style: textTheme.bodyMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: cs.error, size: 20),
                                tooltip: context.l10n.removeAssociationTooltip,
                                onPressed: () {
                                  final newPrefs = Map<String, String>.from(
                                    state.settings.extensionPreferences,
                                  )..remove(entry.key);
                                  ref
                                      .read(appSettingsControllerProvider.notifier)
                                      .updateSettings((s) => s.copyWith(extensionPreferences: newPrefs));
                                },
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

    if (embedded) {
      return Scaffold(body: body);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.sectionVaultFileHandling,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. APPEARANCE & DASHBOARD SUB-PAGE
// ─────────────────────────────────────────────────────────────────────────────

class AppearanceSettingsScreen extends ConsumerWidget {
  /// True when embedded in the wide-layout detail pane instead of pushed
  /// as a full-screen route.
  final bool embedded;

  const AppearanceSettingsScreen({super.key, this.embedded = false});

  String _getNativeLanguageName(Locale locale) {
    const nativeNames = {
      'ar': 'العربية',
      'de': 'Deutsch',
      'en': 'English',
      'es': 'Español',
      'fr': 'Français',
      'it': 'Italiano',
      'ja': '日本語',
      'ko': '한국어',
      'pt': 'Português',
      'uk': 'Українська',
      'zh': '中文',
    };
    final code = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    return nativeNames[code] ?? nativeNames[locale.languageCode] ?? code.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appSettingsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Fix language resolution: sanitize null / empty / 'system'
    final currentLang = (state.settings.languageCode == null ||
            state.settings.languageCode!.trim().isEmpty ||
            state.settings.languageCode == 'system')
        ? 'system'
        : state.settings.languageCode!;

    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // Theme & Styling
                SectionHeader(context.l10n.appThemeLabel),
                SectionCard(
                  children: [
                    OptionPickerTile<ThemeMode>(
                      label: context.l10n.appThemeLabel,
                      value: state.settings.themeMode,
                      options: [
                        SelectOption(value: ThemeMode.system, label: context.l10n.systemDefault),
                        SelectOption(value: ThemeMode.light, label: context.l10n.lightTheme),
                        SelectOption(value: ThemeMode.dark, label: context.l10n.darkTheme),
                      ],
                      onChanged: (v) {
                        appThemeModeNotifier.value = v;
                        ref.read(appSettingsControllerProvider.notifier).updateSettings((s) => s.copyWith(themeMode: v));
                      },
                    ),
                    if (state.androidSdkInt >= _kAndroidSdkS)
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        title: Text(
                          context.l10n.useMaterialYouTitle,
                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          context.l10n.useMaterialYouSubtitle,
                          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        value: state.settings.useDynamicColor,
                        onChanged: (v) {
                          appUseDynamicColorNotifier.value = v;
                          ref
                              .read(appSettingsControllerProvider.notifier)
                              .updateSettings((s) => s.copyWith(useDynamicColor: v));
                        },
                      ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.pureBlackThemeTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.pureBlackThemeSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.settings.useOledBlackTheme,
                      onChanged: (v) {
                        appUsePureBlackNotifier.value = v;
                        ref
                            .read(appSettingsControllerProvider.notifier)
                            .updateSettings((s) => s.copyWith(useOledBlackTheme: v));
                      },
                    ),
                    // Language Selection (Bug Fixed)
                    OptionPickerTile<String>(
                      label: context.l10n.languageLabel,
                      value: (state.settings.languageCode != null &&
                              state.settings.languageCode!.isNotEmpty)
                          ? state.settings.languageCode!
                          : 'system',
                      options: [
                        SelectOption(value: 'system', label: context.l10n.systemDefault),
                        ...AppLocalizations.supportedLocales
                            .map((locale) => locale.languageCode)
                            .toSet()
                            .map((code) {
                          final locale = AppLocalizations.supportedLocales
                              .firstWhere((l) => l.languageCode == code);
                          return SelectOption(
                            value: code,
                            label: _getNativeLanguageName(locale),
                          );
                        }),
                      ],
                      onChanged: (v) {
                        final isSystem = v == 'system' || v.trim().isEmpty;
                        final code = isSystem ? null : v;
                        appLocaleNotifier.value = code != null ? Locale(code) : null;
                        ref.read(appSettingsControllerProvider.notifier).updateSettings(
                              (s) => s.copyWith(
                                languageCode: code,
                                clearLanguageCode: isSystem,
                              ),
                            );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Dashboard Layout & Cards (Unified here)
                SectionHeader(context.l10n.navBarVaultsLabel),
                SectionCard(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.showStorageLocationsTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.showStorageLocationsSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.settings.showStorageLocationsInDrawer,
                      onChanged: (v) => ref.read(appSettingsControllerProvider.notifier).updateSettings(
                            (s) => s.copyWith(showStorageLocationsInDrawer: v),
                          ),
                    ),
                    OptionPickerTile<ContainerSortMode>(
                      label: context.l10n.sortContainersByLabel,
                      value: state.settings.containerSortMode,
                      options: ContainerSortMode.values.map((mode) {
                        return SelectOption(value: mode, label: mode.getLocalizedLabel(context.l10n));
                      }).toList(),
                      onChanged: (v) => ref
                          .read(appSettingsControllerProvider.notifier)
                          .updateSettings((s) => s.copyWith(containerSortMode: v)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

    if (embedded) {
      return Scaffold(body: body);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.sectionAppearanceInterface,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. BACKUP & DIAGNOSTICS SUB-PAGE
// ─────────────────────────────────────────────────────────────────────────────

class AdvancedSettingsScreen extends ConsumerWidget {
  /// True when embedded in the wide-layout detail pane instead of pushed
  /// as a full-screen route.
  final bool embedded;

  const AdvancedSettingsScreen({super.key, this.embedded = false});

  Future<void> _exportSettings(BuildContext context, WidgetRef ref, AppSettingsViewState state) async {
    if (state.backupBusy) return;
    ref.read(appSettingsControllerProvider.notifier).setExportBusy(true);
    try {
      final ok = await ref.read(sessionLockControllerProvider).withLockSuppression(
        () => ref.read(settingsBackupServiceProvider).exportToFile(),
      );
      if (!context.mounted) return;
      if (ok) {
        showAppSnackBar(
          context,
          message: context.l10n.exportSettingsSuccessMessage,
          tone: AppBannerTone.success,
        );
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.exportSettingsErrorMessage,
          tone: AppBannerTone.error,
        );
      }
    } finally {
      if (context.mounted) {
        ref.read(appSettingsControllerProvider.notifier).setExportBusy(false);
      }
    }
  }

  Future<void> _importSettings(BuildContext context, WidgetRef ref, AppSettingsViewState state) async {
    if (state.backupBusy) return;
    ref.read(appSettingsControllerProvider.notifier).setImportBusy(true);
    ImportedSettingsBundle? bundle;
    try {
      bundle = await ref.read(sessionLockControllerProvider).withLockSuppression(
        () => ref.read(settingsBackupServiceProvider).pickAndParseFile(),
      );
    } on InvalidSettingsBackupException {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.importSettingsInvalidFileMessage,
          tone: AppBannerTone.error,
        );
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.importSettingsInvalidFileMessage,
          tone: AppBannerTone.error,
        );
      }
    }
    if (!context.mounted) return;
    if (bundle == null) {
      ref.read(appSettingsControllerProvider.notifier).setImportBusy(false);
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.importSettingsConfirmTitle,
      message: context.l10n.importSettingsConfirmMessage,
      confirmLabel: context.l10n.importSettingsTitle,
      isDestructive: true,
    );
    if (!context.mounted) return;
    if (!confirmed) {
      ref.read(appSettingsControllerProvider.notifier).setImportBusy(false);
      return;
    }
    try {
      await ref.read(settingsBackupServiceProvider).applyImportedBundle(bundle);
      if (!context.mounted) return;
      ref.read(appSettingsControllerProvider.notifier).applyImportedSettings(bundle.appSettings);
      ref
          .read(fileManagerToolbarSettingsProvider(null).notifier)
          .applyImportedConfig(bundle.toolbarConfig);
      ref.invalidate(fileManagerToolbarSettingsProvider);

      if (bundle.shareTargetEnabled != null) {
        await ref
            .read(appSettingsControllerProvider.notifier)
            .setShareTargetEnabled(bundle.shareTargetEnabled!);
      }

      VeLog.enabled = bundle.appSettings.debugLoggingEnabled;
      appThemeModeNotifier.value = bundle.appSettings.themeMode;
      appUseDynamicColorNotifier.value = bundle.appSettings.useDynamicColor;
      appUsePureBlackNotifier.value = bundle.appSettings.useOledBlackTheme;
      appLocaleNotifier.value = bundle.appSettings.languageCode != null
          ? Locale(bundle.appSettings.languageCode!)
          : null;
      showAppSnackBar(
        context,
        message: context.l10n.importSettingsSuccessMessage,
        tone: AppBannerTone.success,
      );
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.importSettingsInvalidFileMessage,
          tone: AppBannerTone.error,
        );
      }
    } finally {
      if (context.mounted) {
        ref.read(appSettingsControllerProvider.notifier).setImportBusy(false);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appSettingsControllerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // Backup & Restore
                SectionHeader(context.l10n.sectionBackupRestore),
                SectionCard(
                  children: [
                    ListTile(
                      title: Text(
                        context.l10n.exportSettingsTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.exportSettingsSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      trailing: state.exportBusy
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(cs.primary),
                              ),
                            )
                          : null,
                      enabled: !state.backupBusy,
                      onTap: () => _exportSettings(context, ref, state),
                    ),
                    ListTile(
                      title: Text(
                        context.l10n.importSettingsTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.importSettingsSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      trailing: state.importBusy
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(cs.primary),
                              ),
                            )
                          : null,
                      enabled: !state.backupBusy,
                      onTap: () => _importSettings(context, ref, state),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Debug & Diagnostics
                SectionHeader(context.l10n.sectionDebug),
                SectionCard(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: Text(
                        context.l10n.debugLoggingTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.debugLoggingSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      value: state.settings.debugLoggingEnabled,
                      onChanged: (val) {
                        VeLog.enabled = val;
                        ref
                            .read(appSettingsControllerProvider.notifier)
                            .updateSettings((s) => s.copyWith(debugLoggingEnabled: val));
                      },
                    ),
                    ListTile(
                      title: Text(
                        context.l10n.logcatTitle,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.logcatSubtitle,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LogcatScreen()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

    if (embedded) {
      return Scaffold(body: body);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          '${context.l10n.sectionBackupRestore} & ${context.l10n.sectionDebug}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: body,
    );
  }
}