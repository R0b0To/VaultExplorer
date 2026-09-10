import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_panic_api.dart';
import 'package:vaultexplorer/data/services/password_hasher.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/lock/duress_settings_service.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_setup_sheet.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_setup_sheet.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

class EmergencySettingsScreen extends ConsumerStatefulWidget {
  const EmergencySettingsScreen({super.key});

  @override
  ConsumerState<EmergencySettingsScreen> createState() =>
      _EmergencySettingsScreenState();
}

class _EmergencySettingsScreenState
    extends ConsumerState<EmergencySettingsScreen> {
  bool _loading = true;
  PanicSettingsSnapshot? _panicSettings;
  PanicKitStatus? _panicKitStatus;
  DuressConfig? _duressConfig;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final panicApi = ref.read(vaultPanicApiProvider);
    final duressService = ref.read(duressSettingsServiceProvider);

    final panic = await panicApi.getPanicSettings();
    final kit = await panicApi.getPanicKitStatus();
    final duress = await duressService.getConfig();

    if (mounted) {
      setState(() {
        _panicSettings = panic;
        _panicKitStatus = kit;
        _duressConfig = duress;
        _loading = false;
      });
    }
  }

  Future<void> _triggerPanic() async {
    final tier = _panicSettings?.configuredTier ?? PanicTier.sessionPurge;
    final tierLabel = switch (tier) {
      PanicTier.sessionPurge => context.l10n.panicTierSessionLabel,
      PanicTier.credentialPurge => context.l10n.panicTierCredentialLabel,
      PanicTier.nuclearWipe => context.l10n.panicTierNuclearLabel,
    };

    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.triggerPanicConfirmTitle,
      message: context.l10n.triggerPanicConfirmMessage(tierLabel),
      confirmLabel: context.l10n.triggerPanicButton,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final outcome = await ref.read(vaultPanicApiProvider).triggerPanic(tier: tier);
    if (mounted && outcome.success) {
      showAppSnackBar(
        context,
        message: 'Panic purge completed (${outcome.containersLocked} locked).',
        tone: AppBannerTone.success,
      );
      await _load();
    }
  }

  // ── Duress Password Setup ──────────────────────────────────────────────────

  Future<void> _setupDuressPassword() async {
    final ctrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          String? errorMsg;
          return AlertDialog(
            title: Text(context.l10n.duressPasswordTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.passwordFieldLabel,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.confirmPasswordLabel,
                    errorText: errorMsg,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () async {
                  if (ctrl.text.isEmpty) {
                    setDialogState(() => errorMsg = context.l10n.passwordCannotBeEmpty);
                    return;
                  }
                  if (ctrl.text != confirmCtrl.text) {
                    setDialogState(() => errorMsg = context.l10n.passwordsDoNotMatch);
                    return;
                  }
                  final masterSettings = ref.read(appSettingsControllerProvider).settings;
                  if (masterSettings.masterPasswordHash != null) {
                    final isMaster = await ref.read(passwordHasherProvider).verify(
                      candidate: ctrl.text,
                      hash: masterSettings.masterPasswordHash,
                      salt: masterSettings.masterPasswordSalt,
                    );
                    if (isMaster) {
                      setDialogState(() => errorMsg = context.l10n.duressMatchesMasterPasswordError);
                      return;
                    }
                  }
                  if (ctx.mounted) Navigator.pop(ctx, ctrl.text);
                },
                child: Text(context.l10n.confirm),
              ),
            ],
          );
        },
      ),
    );

    if (entered != null && mounted) {
      await ref.read(duressSettingsServiceProvider).setDuressPassword(entered);
      await _load();
      showAppSnackBar(
        context,
        message: context.l10n.duressPasswordSetSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _clearDuressPassword() async {
    await ref.read(duressSettingsServiceProvider).clearDuressPassword();
    await _load();
    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.duressPasswordRemovedSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  // ── Duress PIN Setup ───────────────────────────────────────────────────────

  Future<void> _setupDuressPin() async {
    final masterPinHash = ref.read(appSettingsControllerProvider).settings.masterPinHash;
    final hash = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PinSetupSheet(
        disallowedHash: masterPinHash,
        disallowedMessage: context.l10n.duressMatchesMasterPinError,
      ),
    );
    if (hash != null && mounted) {
      await ref.read(duressSettingsServiceProvider).setDuressPinHash(hash);
      await _load();
      showAppSnackBar(
        context,
        message: context.l10n.duressPinSetSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _clearDuressPin() async {
    await ref.read(duressSettingsServiceProvider).clearDuressPin();
    await _load();
    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.duressPinRemovedSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  // ── Duress Pattern Setup ───────────────────────────────────────────────────

  Future<void> _setupDuressPattern() async {
    final masterPatternHash = ref.read(appSettingsControllerProvider).settings.masterPatternHash;
    final hash = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PatternSetupSheet(
        disallowedHash: masterPatternHash,
        disallowedMessage: context.l10n.duressMatchesMasterPatternError,
      ),
    );
    if (hash != null && mounted) {
      await ref.read(duressSettingsServiceProvider).setDuressPattern(hash);
      await _load();
      showAppSnackBar(
        context,
        message: context.l10n.duressPatternSetSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _clearDuressPattern() async {
    await ref.read(duressSettingsServiceProvider).clearDuressPattern();
    await _load();
    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.duressPatternRemovedSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  

  Future<void> _unpairTrigger() async {
    final ok = await ref.read(vaultPanicApiProvider).unpairPanicKit();
    if (ok && mounted) {
      await _load();
      showAppSnackBar(
        context,
        message: context.l10n.panicKitUnpairSuccess,
        tone: AppBannerTone.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appSettingsState = ref.watch(appSettingsControllerProvider);

    final configuredTier = _panicSettings?.configuredTier ?? PanicTier.sessionPurge;
    final tierSubtitle = switch (configuredTier) {
      PanicTier.sessionPurge => context.l10n.panicTierSessionSubtitle,
      PanicTier.credentialPurge => context.l10n.panicTierCredentialSubtitle,
      PanicTier.nuclearWipe => context.l10n.panicTierNuclearSubtitle,
    };

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.emergencyPanicTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    children: [
                      // 1. PANIC PURGE TIERS
                      SectionHeader(context.l10n.sectionPanicTiers),
                      SectionCard(
                        children: [
                          OptionPickerTile<PanicTier>(
                            label: context.l10n.sectionPanicTiers,
                            value: configuredTier,
                            subtitle: tierSubtitle,
                            options: [
                              SelectOption(
                                value: PanicTier.sessionPurge,
                                label: context.l10n.panicTierSessionLabel,
                                subtitle: context.l10n.panicTierSessionSubtitle,
                              ),
                              SelectOption(
                                value: PanicTier.credentialPurge,
                                label: context.l10n.panicTierCredentialLabel,
                                subtitle:
                                    context.l10n.panicTierCredentialSubtitle,
                              ),
                              SelectOption(
                                value: PanicTier.nuclearWipe,
                                label: context.l10n.panicTierNuclearLabel,
                                subtitle: context.l10n.panicTierNuclearSubtitle,
                              ),
                            ],
                            onChanged: (tier) async {
                              final ok = await ref
                                  .read(vaultPanicApiProvider)
                                  .setPanicTier(tier);
                              if (ok && mounted) await _load();
                            },
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            title: Text(
                              context.l10n.panicQuickTileTitle,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              context.l10n.panicQuickTileSubtitle,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            value: _panicSettings?.quickTileEnabled ?? false,
                            onChanged: (val) async {
                              final ok = await ref
                                  .read(vaultPanicApiProvider)
                                  .setQuickTileEnabled(val);
                              if (ok && mounted) await _load();
                            },
                          ),
                          ListTile(
                            leading: Icon(
                              Icons.dangerous_outlined,
                              color: cs.error,
                            ),
                            title: Text(
                              context.l10n.triggerPanicNowTitle,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.error,
                              ),
                            ),
                            subtitle: Text(
                              context.l10n.triggerPanicNowSubtitle,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: _triggerPanic,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 2. PANICKIT INTEGRATION
                      SectionHeader(context.l10n.sectionPanicKit),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            title: Text(
                              context.l10n.panicKitEnableTitle,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              context.l10n.panicKitEnableSubtitle,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            value: _panicKitStatus?.responderEnabled ?? false,
                            onChanged: (val) async {
                              final ok = await ref
                                  .read(vaultPanicApiProvider)
                                  .setPanicKitEnabled(val);
                              if (ok && mounted) await _load();
                            },
                          ),
                          if (_panicKitStatus?.responderEnabled == true) ...[
                            SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              title: Text(
                                context.l10n.panicKitEnforcePairingTitle,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                context.l10n.panicKitEnforcePairingSubtitle,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              value: _panicKitStatus
                                      ?.pairingEnforcementEnabled ??
                                  true,
                              onChanged: (val) async {
                                final ok = await ref
                                    .read(vaultPanicApiProvider)
                                    .setPanicKitPairingEnforcement(val);
                                if (ok && mounted) await _load();
                              },
                            ),
                            ListTile(
                              title: Text(
                                context.l10n.panicKitPairedAppLabel,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                _panicKitStatus?.trustedPackage ??
                                    context.l10n.panicKitNoAppPaired,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              trailing: _panicKitStatus?.trustedPackage != null
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.link_off_rounded,
                                        color: cs.error,
                                      ),
                                      tooltip: context.l10n.panicKitUnpairButton,
                                      onPressed: _unpairTrigger,
                                    )
                                  : null,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 3. MASTER LOCK SCREEN DURESS
                      SectionHeader(context.l10n.sectionDuressUnlock),
                      SectionCard(
                        children: [
                          if (!appSettingsState.settings.useMasterPassword ||
                              appSettingsState.settings.masterPasswordHash ==
                                  null)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                context.l10n.duressMasterPasswordRequired,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: cs.error,
                                ),
                              ),
                            )
                          else ...[
                            // 3a. Duress Password
                            ListTile(
                              title: Text(
                                context.l10n.duressPasswordTitle,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                _duressConfig?.hasPassword == true
                                    ? context.l10n.duressPasswordConfiguredSubtitle
                                    : context.l10n.duressPasswordNotConfiguredSubtitle,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              trailing: _duressConfig?.hasPassword == true
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        color: cs.error,
                                      ),
                                      tooltip: context.l10n.removeDuressPasswordButton,
                                      onPressed: _clearDuressPassword,
                                    )
                                  : const Icon(Icons.chevron_right_rounded),
                              onTap: _setupDuressPassword,
                            ),

                            // 3b. Duress PIN
                            ListTile(
                              title: Text(
                                context.l10n.duressPinConfiguredTitle,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                _duressConfig?.hasPin == true
                                    ? context.l10n.duressPinConfiguredSubtitle
                                    : context.l10n.duressPinNotConfiguredSubtitle,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              trailing: _duressConfig?.hasPin == true
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        color: cs.error,
                                      ),
                                      tooltip: context.l10n.removeDuressPinButton,
                                      onPressed: _clearDuressPin,
                                    )
                                  : const Icon(Icons.chevron_right_rounded),
                              onTap: _setupDuressPin,
                            ),

                            // 3c. Duress Pattern
                            ListTile(
                              title: Text(
                                context.l10n.duressPatternTitle,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                _duressConfig?.hasPattern == true
                                    ? context.l10n.duressPatternConfiguredSubtitle
                                    : context.l10n.duressPatternNotConfiguredSubtitle,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              trailing: _duressConfig?.hasPattern == true
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        color: cs.error,
                                      ),
                                      tooltip: context.l10n.removeDuressPatternButton,
                                      onPressed: _clearDuressPattern,
                                    )
                                  : const Icon(Icons.chevron_right_rounded),
                              onTap: _setupDuressPattern,
                            ),

                            // 3d. Active Action Indicator
                            if (_duressConfig?.configured == true)
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.shield_outlined,
                                  color: cs.primary,
                                ),
                                title: Text(
                                  switch (configuredTier) {
                                    PanicTier.sessionPurge =>
                                      context.l10n.panicTierSessionLabel,
                                    PanicTier.credentialPurge =>
                                      context.l10n.panicTierCredentialLabel,
                                    PanicTier.nuclearWipe =>
                                      context.l10n.panicTierNuclearLabel,
                                  },
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                  ),
                                ),
                                subtitle: Text(
                                  tierSubtitle,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}