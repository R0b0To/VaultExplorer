import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/features/dashboard/widgets/migrate_cryptomator_vault_screen.dart';

/// The Cryptomator row in a vault's settings, driven by the password-free format probe:
///  * [CryptomatorVaultFormat.legacy7]: "Upgrade vault format". Disabled, with a "lock the vault" subtitle,
///    while the vault is unlocked (the upgrade rewrites its key files; the native side refuses anyway).
///  * [CryptomatorVaultFormat.configMissing]: a warning only. vault.cryptomator has not synced yet, and a
///    half-synced format 8 vault must never be "upgraded".
///  * everything else (current, too old, unknown): nothing.
///
/// [onUpgraded] runs after the upgrade screen reports success; the caller re-probes so the row disappears.
class CryptomatorUpgradeTile extends StatelessWidget {
  final String uri;
  final CryptomatorVaultFormat format;
  final bool vaultIsUnlocked;
  final VoidCallback onUpgraded;

  const CryptomatorUpgradeTile({
    super.key,
    required this.uri,
    required this.format,
    required this.vaultIsUnlocked,
    required this.onUpgraded,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    switch (format) {
      case CryptomatorVaultFormat.legacy7:
        final enabled = !vaultIsUnlocked;
        return ListTile(
          enabled: enabled,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Icon(
            Icons.upgrade_rounded,
            color: enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.38),
          ),
          title: Text(
            context.l10n.cryptomatorUpgradeTitle,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            enabled
                ? context.l10n.cryptomatorUpgradeSubtitle
                : context.l10n.cryptomatorUpgradeLockFirst,
            style: textTheme.bodySmall,
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: cs.onSurfaceVariant,
          ),
          onTap: enabled ? () => _open(context) : null,
        );
      case CryptomatorVaultFormat.configMissing:
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Icon(Icons.warning_amber_rounded, color: cs.error),
          title: Text(
            context.l10n.cryptomatorConfigMissingWarning,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        );
      case CryptomatorVaultFormat.current:
      case CryptomatorVaultFormat.tooOld:
      case CryptomatorVaultFormat.unknown:
        return const SizedBox.shrink();
    }
  }

  Future<void> _open(BuildContext context) async {
    final upgraded = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SkinAreaScope(
          area: SkinArea.dashboard,
          child: MigrateCryptomatorVaultScreen(uri: uri),
        ),
      ),
    );
    if (upgraded == true) onUpgraded();
  }
}
