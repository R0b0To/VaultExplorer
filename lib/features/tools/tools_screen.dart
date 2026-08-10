import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_clipboard_chip.dart';
import 'package:vaultexplorer/core/widgets/layout/section_card.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/container_repair_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/container_splitter_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/single_file_crypto_sheet.dart';

/// The "Tools" tab: utility workflows for standalone file/container
/// operations, grouped by category, as laid out in the Tools-page design
/// (Container Utilities / File Cryptography / Storage & Diagnostics).
///
/// Rows use the same [SectionHeader]/[SectionCard] grouped-list look as
/// App Settings, File Manager Settings, and About, rather than a bespoke
/// card grid, so the Tools tab reads as the same app as the rest of the
/// settings-style screens.
///
/// Lives alongside [VaultDashboard] as the second [MainShell] tab. Doesn't
/// track its own mounted-volume state — [mountedContainers] is fed down
/// from [MainShell], which is in turn fed by [VaultDashboard.mountedNotifier],
/// so Repair's "choose mounted volume" option sees the same live list the
/// Vaults tab shows.
class ToolsScreen extends StatelessWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;

  // Storage Analyzer is temporarily hidden from the Tools tab -- flip
  // this back on to restore its section once it's ready again. Left as
  // a single switch rather than deleting the section below so re-enabling
  // it is a one-line change.
  static const bool _showStorageDiagnostics = false;

  const ToolsScreen({super.key, required this.mountedContainers});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.toolsScreenTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          const AppBarClipboardButton(),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: context.l10n.settingsTooltip,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          SectionHeader(context.l10n.toolsSectionContainerUtilities),
          SectionCard(
            children: [
              _ToolRow(
                icon: Icons.content_cut_rounded,
                title: context.l10n.toolContainerSplitterTitle,
                subtitle: context.l10n.toolContainerSplitterSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ContainerSplitterSheet(),
                  ),
                ),
              ),
              _ToolRow(
                icon: Icons.build_rounded,
                title: context.l10n.toolContainerRepairTitle,
                subtitle: context.l10n.toolContainerRepairSubtitle,
                iconColor: cs.tertiary,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ContainerRepairSheet(mountedContainers: mountedContainers),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(context.l10n.toolsSectionFileCryptography),
          SectionCard(
            children: [
              _ToolRow(
                icon: Icons.enhanced_encryption_rounded,
                title: context.l10n.toolSingleFileCryptoTitle,
                subtitle: context.l10n.toolSingleFileCryptoSubtitle,
                iconColor: cs.secondary,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SingleFileCryptoSheet(),
                  ),
                ),
              ),
            ],
          ),
          if (_showStorageDiagnostics) ...[
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(context.l10n.toolsSectionStorageDiagnostics),
            SectionCard(
              children: [
                _ToolRow(
                  icon: Icons.pie_chart_rounded,
                  title: context.l10n.toolStorageAnalyzerTitle,
                  subtitle: context.l10n.toolStorageAnalyzerSubtitle,
                  onTap: () {
                    // Intentionally unreachable while
                    // _showStorageDiagnostics is false -- see its doc
                    // comment. Left wired up so bringing this section back
                    // only needs that switch flipped, not new code.
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One tappable tool entry, styled to match the rest of the app's
/// grouped-list rows (tinted icon chip, title, subtitle, chevron) -- see
/// e.g. `file_manager_toolbar_settings_screen.dart`'s reorder rows for the
/// same leading-icon treatment.
class _ToolRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  const _ToolRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final accent = iconColor ?? cs.primary;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, size: AppIconSize.small, color: accent),
      ),
      title: Text(
        title,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      onTap: onTap,
    );
  }
}