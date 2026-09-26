import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/authenticator/authenticator_registry_controller.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/password_interchange/password_interchange_screen.dart';

class AuthenticatorSettingsScreen extends ConsumerWidget {
  const AuthenticatorSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(appSettingsControllerProvider);
    final settings = settingsState.settings;
    final notifier = ref.read(appSettingsControllerProvider.notifier);
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.authenticatorSettingsTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            // General / Scanning performance
            SectionHeader(l10n.generalSectionHeader),
            SectionCard(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(
                    l10n.authenticatorEnableTitle,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    l10n.authenticatorEnableSubtitle,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  value: settings.enableAuthenticator,
                  onChanged: (v) async {
                    await notifier.updateSettings((s) => s.copyWith(enableAuthenticator: v));
                    if (v) {
                      await ref.read(authenticatorRegistryProvider.notifier).refreshAll();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Display
            SectionHeader(l10n.sectionAppearanceInterface),
            SectionCard(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(
                    l10n.authenticatorShowCodesTitle,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    l10n.authenticatorShowCodesSubtitle,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  value: settings.authenticatorShowNumbers,
                  onChanged: (v) =>
                      notifier.updateSettings((s) => s.copyWith(authenticatorShowNumbers: v)),
                ),
                OptionPickerTile<AuthenticatorSearchPlacement>(
                  label: l10n.authenticatorSearchPlacementLabel,
                  value: settings.authenticatorSearchPlacement,
                  options: [
                    SelectOption(
                      value: AuthenticatorSearchPlacement.bottom,
                      label: l10n.authenticatorPlacementBottom,
                    ),
                    SelectOption(
                      value: AuthenticatorSearchPlacement.top,
                      label: l10n.authenticatorPlacementTop,
                    ),
                  ],
                  onChanged: (v) =>
                      notifier.updateSettings((s) => s.copyWith(authenticatorSearchPlacement: v)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Interchange
            SectionHeader(l10n.authenticatorInterchangeSection),
            SectionCard(
              children: [
                ListTile(
                  leading: Icon(Icons.sync_alt_rounded, color: cs.primary),
                  title: Text(
                    l10n.toolPasswordInterchangeTitle,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    l10n.toolPasswordInterchangeSubtitle,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    final mounted = ref.read(vaultDashboardControllerProvider).mounted;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PasswordInterchangeScreen(
                          mountedContainers: ValueNotifier(mounted),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}