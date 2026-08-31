import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/dashboard/widgets/automation_settings_screen.dart';
import 'package:vaultexplorer/features/dashboard/widgets/change_password_screen.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/pattern_pin_verify_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/real_password_gate_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_info_screen.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_setup_sheet.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_lock_view.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_setup_sheet.dart';

part 'container_config_dialogs.dart';

class ContainerConfigScreen extends ConsumerStatefulWidget {
  final String uri;
  final String currentLabel;
  final ContainerRecord? existingRecord;
  final void Function(ContainerRecord record) onSaved;
  final AppSettings? appSettings;
  final MountedContainer? mountedContainer;

  const ContainerConfigScreen({
    super.key,
    required this.uri,
    required this.currentLabel,
    this.existingRecord,
    required this.onSaved,
    this.appSettings,
    this.mountedContainer,
  });

  @override
  ConsumerState<ContainerConfigScreen> createState() => _ContainerConfigScreenState();
}

class _ContainerConfigScreenState extends ConsumerState<ContainerConfigScreen> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _passwordCtrl;
  bool _showPassword = false;

  static const _autoCloseOptions = [0, 1, 2, 5, 10, 15, 30, 60];

  String get _containerFormat =>
      widget.existingRecord?.containerFormat ??
      widget.mountedContainer?.containerFormat ??
      'veracrypt';

  bool get _isCryptomator => ContainerFormat.isCryptomatorWire(_containerFormat);
  bool get _isGocryptfs => ContainerFormat.isGocryptfsWire(_containerFormat);
  bool get _isCryfs => ContainerFormat.isCryfsWire(_containerFormat);
  bool get _isBitlocker => ContainerFormat.isBitlockerWire(_containerFormat);

  ContainerConfigParams get _params => ContainerConfigParams(
        uri: widget.uri,
        currentLabel: widget.currentLabel,
        containerFormat: _containerFormat,
      );

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(
      text: widget.existingRecord?.label.isNotEmpty == true
          ? widget.existingRecord!.label
          : widget.currentLabel,
    );
    _passwordCtrl = TextEditingController();
    _labelCtrl.addListener(() => setState(() {}));

    Future.microtask(() {
      ref.read(containerConfigControllerProvider(_params).notifier).initializeFromRecord(
            rec: widget.existingRecord,
            appSettings: widget.appSettings,
            mountedContainer: widget.mountedContainer,
          );
    });
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _clearThumbnailCache() async {
    final confirm = await showAppConfirmDialog(
      context,
      title: context.l10n.clearThumbnailCacheDialogTitle,
      message: context.l10n.clearThumbnailCacheDialogMessage,
      confirmLabel: context.l10n.clearCacheButton,
      isDestructive: true,
    );
    if (!confirm || !mounted) return;

    final result = await ref
        .read(containerConfigControllerProvider(_params).notifier)
        .clearThumbnailCache();

    if (!mounted) return;
    if (result.isLocked) {
      showAppSnackBar(
        context,
        message: context.l10n.appCacheClearedUnlockMessage,
        tone: AppBannerTone.warning,
      );
    } else if (result.appCacheCleared && result.containerCacheCleared) {
      showAppSnackBar(
        context,
        message: context.l10n.allThumbnailCachesClearedMessage,
        tone: AppBannerTone.success,
      );
    } else if (result.appCacheCleared) {
      showAppSnackBar(
        context,
        message: context.l10n.appCacheClearedContainerFailedMessage,
        tone: AppBannerTone.warning,
      );
    } else {
      showAppSnackBar(
        context,
        message: context.l10n.failedToClearThumbnailCachesMessage,
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _save(ContainerConfigState state) async {
    if (state.needsPatternSetup) {
      showAppSnackBar(
        context,
        message: context.l10n.patternSetupRequiredBeforeSaving,
        tone: AppBannerTone.warning,
      );
      return;
    }
    if (state.needsPinSetup) {
      showAppSnackBar(
        context,
        message: context.l10n.pinSetupRequiredBeforeSaving,
        tone: AppBannerTone.warning,
      );
      return;
    }

    final record = await ref
        .read(containerConfigControllerProvider(_params).notifier)
        .saveContainer(
          passwordText: _passwordCtrl.text,
          labelText: _labelCtrl.text,
          existingRecord: widget.existingRecord,
        );

    if (record != null && mounted) {
      widget.onSaved(record);
      Navigator.pop(context);
    }
  }

  Future<void> _setupPattern() async {
    final hash = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PatternSetupSheet(),
    );
    if (hash != null && mounted) {
      ref.read(containerConfigControllerProvider(_params).notifier).setPatternHash(hash);
    }
  }

  Future<void> _setupPin() async {
    final hash = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PinSetupSheet(),
    );
    if (hash != null && mounted) {
      ref.read(containerConfigControllerProvider(_params).notifier).setPinHash(hash);
    }
  }

  Future<void> _authenticateSettings(ContainerConfigState state) async {
    final record = widget.existingRecord;
    if (record == null) return;

    if (record.unlockMethod == ContainerUnlockMethod.biometrics) {
      try {
        final localAuth = LocalAuthentication();
        final ok = await localAuth.authenticate(
          localizedReason: context.l10n.authenticateToModifySettingsPrompt,
          persistAcrossBackgrounding: true,
        );
        if (ok && mounted) {
          final savedPassword =
              await ref.read(containerRepositoryProvider).getPassword(widget.uri);
          ref.read(containerConfigControllerProvider(_params).notifier).unlockSettings();
          if (savedPassword != null && mounted) _passwordCtrl.text = savedPassword;
        }
      } catch (_) {}
    } else if (record.unlockMethod == ContainerUnlockMethod.pattern) {
      if (state.patternHash == null) {
        ref.read(containerConfigControllerProvider(_params).notifier).unlockSettings();
        return;
      }
      final hash = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _PatternVerifySheet(storedHash: state.patternHash!),
      );
      if (hash != null && mounted) {
        final savedPassword =
            await ref.read(containerRepositoryProvider).getPassword(widget.uri);
        ref.read(containerConfigControllerProvider(_params).notifier).unlockSettings();
        if (savedPassword != null && mounted) _passwordCtrl.text = savedPassword;
      }
    } else if (record.unlockMethod == ContainerUnlockMethod.pin) {
      if (state.pinHash == null) {
        ref.read(containerConfigControllerProvider(_params).notifier).unlockSettings();
        return;
      }
      final hash = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _PinVerifySheet(storedHash: state.pinHash!),
      );
      if (hash != null && mounted) {
        final savedPassword =
            await ref.read(containerRepositoryProvider).getPassword(widget.uri);
        ref.read(containerConfigControllerProvider(_params).notifier).unlockSettings();
        if (savedPassword != null && mounted) _passwordCtrl.text = savedPassword;
      }
    } else {
      final savedPassword =
          await ref.read(containerRepositoryProvider).getPassword(widget.uri);
      if (!mounted) return;
      final verified = await showDialog<
          ({String password, List<KeyfileRef> keyfiles, int cipherId, int hashId})>(
        context: context,
        builder: (context) => _RealPasswordGateDialog(
          uri: widget.uri,
          cipherId: record.cipherId,
          hashId: record.hashId,
          documentProvider: state.documentProvider,
          cacheDerivedKey: state.cacheDerivedKey,
          containerFormat: record.containerFormat,
          initialKeyfiles: record.keyfiles,
          initialPassword: savedPassword,
        ),
      );
      if (verified != null && mounted) {
        ref.read(containerConfigControllerProvider(_params).notifier).unlockSettings(
              verifiedPassword: verified.password,
              verifiedKeyfiles: verified.keyfiles,
              verifiedCipherId: verified.cipherId,
              verifiedHashId: verified.hashId,
            );
        _passwordCtrl.text = verified.password;
      }
    }
  }

  Future<void> _editDisplayName() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _DisplayNameDialog(
        initialText: _labelCtrl.text,
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      _labelCtrl.text = result.trim();
      ref.read(containerConfigControllerProvider(_params).notifier).setLabel(result.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(containerConfigControllerProvider(_params));
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final wideLayout = context.screen.useWideLayout;

    // Apply auto-loaded temp password if text field is empty
    if (state.tempPassword != null &&
        state.tempPassword!.isNotEmpty &&
        _passwordCtrl.text.isEmpty) {
      _passwordCtrl.text = state.tempPassword!;
    }

    final generalSection = _buildGeneralSection(context);
    final securitySection = _buildSecuritySection(context, state, cs, textTheme);
    final systemSection = _buildSystemIntegrationSection(context, state, textTheme);
    final thumbnailSection = _buildThumbnailSection(context, state, textTheme, cs);
    final vaultInfoSection = _buildVaultInfoSection(context, cs, textTheme);
    final automationSection = _buildAutomationSection(context, cs, textTheme);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.uri.startsWith('usb:')
                  ? context.l10n.usbVaultSettingsTitle
                  : context.l10n.vaultSettingsTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              _containerFormat.toUpperCase(),
              style: textTheme.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wideLayout ? 1100 : 800),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: wideLayout
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              generalSection,
                              const SizedBox(height: 16),
                              securitySection,
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              systemSection,
                              const SizedBox(height: 16),
                              thumbnailSection,
                              const SizedBox(height: 16),
                              vaultInfoSection,
                              const SizedBox(height: 16),
                              automationSection,
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        generalSection,
                        const SizedBox(height: 16),
                        securitySection,
                        const SizedBox(height: 16),
                        systemSection,
                        const SizedBox(height: 16),
                        thumbnailSection,
                        const SizedBox(height: 16),
                        vaultInfoSection,
                        const SizedBox(height: 16),
                        automationSection,
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomSaveBar(state),
    );
  }

  Widget _buildGeneralSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.generalSectionHeader),
        SectionCard(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Text(_labelCtrl.text.trim()),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: context.l10n.renameTooltip,
                onPressed: _editDisplayName,
              ),
              onTap: _editDisplayName,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSecuritySection(
    BuildContext context,
    ContainerConfigState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.securityCredentialsSectionHeader),
        SectionCard(
          children: [
            if (state.settingsLocked) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        context.l10n.securityOptionsLockedTitle,
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.authenticateOriginalCredentialsMessage,
                        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _authenticateSettings(state),
                        icon: const Icon(Icons.lock_open_rounded, size: 18),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        label: Text(context.l10n.unlockSettingsButton),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              OptionPickerTile<ContainerUnlockMethod>(
                label: context.l10n.unlockCredentialsLabel,
                value: state.unlockMethod,
                subtitle: state.unlockMethod.getLocalizedSubtitle(context.l10n),
                options: ContainerUnlockMethod.values
                    .where((m) =>
                        m != ContainerUnlockMethod.biometrics ||
                        state.biometricAvailable ||
                        state.unlockMethod == m)
                    .map((m) {
                  final isUnavailableBio =
                      m == ContainerUnlockMethod.biometrics && !state.biometricAvailable;
                  return SelectOption(
                    value: m,
                    label: isUnavailableBio
                        ? '${m.getLocalizedLabel(context.l10n)} ${context.l10n.unavailableSuffixLabel}'
                        : m.getLocalizedLabel(context.l10n),
                    subtitle: m.getLocalizedSubtitle(context.l10n),
                  );
                }).toList(),
                onChanged: (v) {
                  ref.read(containerConfigControllerProvider(_params).notifier).setUnlockMethod(v);
                  if (v == ContainerUnlockMethod.password) {
                    _passwordCtrl.clear();
                  }
                },
              ),
              if (widget.existingRecord != null &&
                  widget.existingRecord!.unlockMethod != ContainerUnlockMethod.password &&
                  state.unlockMethod != ContainerUnlockMethod.password &&
                  !state.changePassword) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: FilledButton.tonalIcon(
                    onPressed: () => ref
                        .read(containerConfigControllerProvider(_params).notifier)
                        .setChangePassword(true),
                    icon: const Icon(Icons.key_rounded, size: 18),
                    label: Text(context.l10n.updateSavedCredentialsButton),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: cs.surfaceContainerHighest,
                      foregroundColor: cs.primary,
                    ),
                  ),
                ),
              ],
              if (state.unlockMethod != ContainerUnlockMethod.password &&
                  (widget.existingRecord == null ||
                      widget.existingRecord!.unlockMethod == ContainerUnlockMethod.password ||
                      state.changePassword)) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: !_showPassword,
                        autofillHints: null,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          labelText: context.l10n.containerPasswordOptionalLabel,
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PasswordVisibilityToggle(
                                obscured: !_showPassword,
                                onToggle: () => setState(() => _showPassword = !_showPassword),
                              ),
                              if (widget.existingRecord != null &&
                                  widget.existingRecord!.unlockMethod !=
                                      ContainerUnlockMethod.password)
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 20),
                                  tooltip: context.l10n.cancelUpdatingPasswordTooltip,
                                  onPressed: () {
                                    ref
                                        .read(containerConfigControllerProvider(_params).notifier)
                                        .setChangePassword(false);
                                    _passwordCtrl.clear();
                                  },
                                ),
                            ],
                          ),
                          hintText: context.l10n.passwordHintContainer,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          context.l10n.passwordKeystoreEncryptedHelperText,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isCryptomator && !_isGocryptfs && !_isCryfs && !_isBitlocker) ...[
                  KeyfilesPicker(
                    keyfiles: state.keyfiles,
                    picking: state.pickingKeyfiles,
                    onPick: () =>
                        ref.read(containerConfigControllerProvider(_params).notifier).pickKeyfiles(),
                    onRemove: (k) => ref
                        .read(containerConfigControllerProvider(_params).notifier)
                        .removeKeyfile(k),
                  ),
                ],
              ],
              if (state.unlockMethod == ContainerUnlockMethod.pattern) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: OutlinedButton(
                    onPressed: _setupPattern,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(state.patternHash != null
                        ? context.l10n.changePatternButton
                        : context.l10n.setPatternButton),
                  ),
                ),
              ],
              if (state.unlockMethod == ContainerUnlockMethod.pin) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: OutlinedButton(
                    onPressed: _setupPin,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(state.pinHash != null
                        ? context.l10n.changePinButton
                        : context.l10n.setPinButton),
                  ),
                ),
              ],
              if (!_isCryptomator && !_isGocryptfs && !_isBitlocker) ...[
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(
                    context.l10n.cacheDerivedKeyLabel,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _isCryfs
                        ? context.l10n.cryfsSkipScryptKdfSubtitle
                        : context.l10n.reuseKeyMaterialKeystoreSubtitle,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  value: state.cacheDerivedKey,
                  onChanged: (v) => ref
                      .read(containerConfigControllerProvider(_params).notifier)
                      .setCacheDerivedKey(v),
                ),
                if (!_isCryfs)
                  AdvancedParamsPanel(
                    cipherId: state.cipherId,
                    hashId: state.hashId,
                    subtitle: context.l10n.pinAlgorithmSkipAutoDetectSubtitle,
                    onCipherChanged: (val) => ref
                        .read(containerConfigControllerProvider(_params).notifier)
                        .setCipherId(val),
                    onHashChanged: (val) => ref
                        .read(containerConfigControllerProvider(_params).notifier)
                        .setHashId(val),
                  ),
              ],
            ],
            if (widget.existingRecord != null) ...[
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Icon(Icons.key_rounded, color: cs.primary),
                title: Text(
                  context.l10n.changeContainerPasswordTitle,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                onTap: () async {
                  final fmt = widget.existingRecord?.containerFormat;
                  if (fmt == 'bitlocker') {
                    showAppSnackBar(
                      context,
                      message: context.l10n.bitlockerCredentialsChangeNotSupportedMessage,
                      tone: AppBannerTone.warning,
                    );
                  } else {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChangePasswordScreen(
                          uri: widget.uri,
                          initialCipherId: widget.existingRecord!.cipherId,
                          initialHashId: widget.existingRecord!.hashId,
                          containerFormat: fmt ?? 'veracrypt',
                        ),
                      ),
                    );
                    if (result is List<KeyfileRef> && mounted) {
                      ref
                          .read(containerConfigControllerProvider(_params).notifier)
                          .setKeyfiles(result);
                    }
                  }
                },
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSystemIntegrationSection(
    BuildContext context,
    ContainerConfigState state,
    TextTheme textTheme,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.systemIntegrationSectionHeader),
        SectionCard(
          children: [
            OptionPickerTile<int>(
              label: context.l10n.autoLockDurationLabel,
              value: state.autoCloseMins,
              options: _autoCloseOptions.map((mins) {
                final label = mins == 0
                    ? context.l10n.neverAutoLockOption
                    : context.l10n.nMinutes(mins);
                return SelectOption(value: mins, label: label);
              }).toList(),
              onChanged: (v) =>
                  ref.read(containerConfigControllerProvider(_params).notifier).setAutoCloseMins(v),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(
                context.l10n.androidFileProviderTitle,
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                context.l10n.exposeContentToFilePickerSubtitle,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              value: state.documentProvider,
              onChanged: (v) => ref
                  .read(containerConfigControllerProvider(_params).notifier)
                  .setDocumentProvider(v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThumbnailSection(
    BuildContext context,
    ContainerConfigState state,
    TextTheme textTheme,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.thumbnailStorageSectionHeader),
        SectionCard(
          children: [
            if (state.loadingPassword)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              OptionPickerTile<ThumbnailCacheMode>(
                label: context.l10n.cacheModeLabel,
                value: state.thumbnailCacheMode ?? ThumbnailCacheMode.appCache,
                subtitle: state.thumbnailCacheMode?.getLocalizedLabel(context.l10n) ??
                    context.l10n.useGlobalDefaultSubtitle,
                options: ThumbnailCacheMode.values.map((mode) {
                  return SelectOption(
                    value: mode,
                    label: mode.getLocalizedLabel(context.l10n),
                    subtitle: mode.getLocalizedDescription(context.l10n),
                  );
                }).toList(),
                onChanged: (v) => ref
                    .read(containerConfigControllerProvider(_params).notifier)
                    .setThumbnailCacheMode(v),
              ),
              ThumbnailQualityTile(
                label: context.l10n.thumbnailQualityLabel,
                value: state.thumbnailQuality ?? ThumbnailQuality.defaultQuality,
                onChanged: (v) => ref
                    .read(containerConfigControllerProvider(_params).notifier)
                    .setThumbnailQuality(v),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(
                  context.l10n.clearThumbnailCacheTitle,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  context.l10n.removeCachedThumbnailsSubtitle,
                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: state.clearingCache
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                onTap: state.clearingCache ? null : _clearThumbnailCache,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildVaultInfoSection(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.vaultInformationSectionHeader),
        SectionCard(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Icon(Icons.info_outline_rounded, color: cs.primary),
              title: Text(
                context.l10n.vaultInformationTileTitle,
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                context.l10n.vaultInformationTileSubtitle,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VaultInfoScreen(
                    uri: widget.uri,
                    containerFormat: _containerFormat,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAutomationSection(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.automationSectionHeader),
        SectionCard(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Icon(Icons.bolt_rounded, color: cs.primary),
              title: Text(
                context.l10n.automationTileTitle,
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                context.l10n.automationTileSubtitle,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AutomationSettingsScreen(
                    uri: widget.uri,
                    containerFormat: _containerFormat,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomSaveBar(ContainerConfigState state) {
    final isModified = state.isModified(_passwordCtrl.text, _labelCtrl.text);
    final canSave = state.canSave(_passwordCtrl.text);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: !isModified
          ? const SizedBox(width: double.infinity, height: 0)
          : Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border(
                  top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
                ),
              ),
              child: SafeArea(
                minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!canSave) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: cs.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              state.needsPatternSetup
                                  ? context.l10n.patternSetupRequiredAboveBeforeSaving
                                  : state.needsPinSetup
                                      ? context.l10n.pinSetupRequiredAboveBeforeSaving
                                      : context.l10n.passwordOrCacheDerivedKeyRequiredMessage,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    FilledButton(
                      onPressed: (state.saving || !canSave) ? null : () => _save(state),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: const StadiumBorder(),
                      ),
                      child: state.saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              context.l10n.saveConfigurationButton,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}