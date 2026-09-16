import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_clipboard_chip.dart';
import 'package:vaultexplorer/core/widgets/layout/section_card.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/composite/presentation/composite_create_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/container_repair_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/container_splitter_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/duplicate_finder_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/hash_verifier_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/header_backup_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/keyfile_passphrase_generator_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/single_file_crypto_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_screen.dart';

class ToolsScreen extends StatelessWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;

  const ToolsScreen({super.key, required this.mountedContainers});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final isLandscape = context.screen.useWideLayout;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.toolsScreenTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: isLandscape
                ? _buildLandscapeBody(context)
                : _buildPortraitBody(context),
          ),
        ),
      ),
    );
  }

  // ── PORTRAIT BODY ──────────────────────────────────────────────────────────

  Widget _buildPortraitBody(BuildContext context) {
    final cs = context.colors;
    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        SectionHeader(context.l10n.toolsSectionFileCryptography),
        SectionCard(
          children: [
            _buildKeyfileGeneratorRow(context, cs),
            _buildSingleFileCryptoRow(context, cs),
            _buildHashVerifierRow(context, cs),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        SectionHeader(context.l10n.toolsSectionBackupSync),
        SectionCard(
          children: [
            _buildVaultSyncRow(context, cs),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        SectionHeader(context.l10n.toolsSectionStorageDiagnostics),
        SectionCard(
          children: [
            _buildStorageAnalyzerRow(context, cs),
            _buildDuplicateFinderRow(context, cs),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        SectionHeader(context.l10n.toolsSectionContainerUtilities),
        SectionCard(
          children: [
            _buildContainerSplitterRow(context, cs),
            _buildCompositeContainerRow(context, cs),
            _buildContainerRepairRow(context, cs),
            _buildHeaderBackupRow(context, cs),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  // ── LANDSCAPE BODY (TWO BALANCED, COHESIVE COLUMNS) ───────────────────────

  Widget _buildLandscapeBody(BuildContext context) {
    final cs = context.colors;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left Column: Cryptography & Keys + Backup & Sync ───────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(context.l10n.toolsSectionFileCryptography),
                SectionCard(
                  children: [
                    _buildKeyfileGeneratorRow(context, cs),
                    _buildSingleFileCryptoRow(context, cs),
                    _buildHashVerifierRow(context, cs),
                  ],
                ),
                const SizedBox(height: 16),
                SectionHeader(context.l10n.toolsSectionBackupSync),
                SectionCard(
                  children: [
                    _buildVaultSyncRow(context, cs),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),

          // ── Right Column: Storage Diagnostics + Container Utilities ────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(context.l10n.toolsSectionStorageDiagnostics),
                SectionCard(
                  children: [
                    _buildStorageAnalyzerRow(context, cs),
                    _buildDuplicateFinderRow(context, cs),
                  ],
                ),
                const SizedBox(height: 16),
                SectionHeader(context.l10n.toolsSectionContainerUtilities),
                SectionCard(
                  children: [
                    _buildContainerSplitterRow(context, cs),
                    _buildCompositeContainerRow(context, cs),
                    _buildContainerRepairRow(context, cs),
                    _buildHeaderBackupRow(context, cs),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TOOL BUILDERS ──────────────────────────────────────────────────────────

  Widget _buildKeyfileGeneratorRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.key_rounded,
      title: context.l10n.keyfilePassphraseGeneratorTitle,
      subtitle: context.l10n.keyfilePassphraseGeneratorSubtitle,
      iconColor: cs.primary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => KeyfilePassphraseGeneratorScreen(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildSingleFileCryptoRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.enhanced_encryption_rounded,
      title: context.l10n.toolSingleFileCryptoTitle,
      subtitle: context.l10n.toolSingleFileCryptoSubtitle,
      iconColor: cs.secondary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SingleFileCryptoSheet(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildHashVerifierRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.verified_rounded,
      title: context.l10n.toolHashVerifierTitle,
      subtitle: context.l10n.toolHashVerifierSubtitle,
      iconColor: cs.secondary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HashVerifierSheet(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildVaultSyncRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.sync_alt_rounded,
      title: context.l10n.toolVaultSyncTitle,
      subtitle: context.l10n.toolVaultSyncSubtitle,
      iconColor: cs.tertiary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VaultSyncScreen(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildStorageAnalyzerRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.pie_chart_rounded,
      title: context.l10n.toolStorageAnalyzerTitle,
      subtitle: context.l10n.toolStorageAnalyzerSubtitle,
      iconColor: cs.tertiary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StorageAnalyzerScreen(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildDuplicateFinderRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.difference_rounded,
      title: context.l10n.toolDuplicateFinderTitle,
      subtitle: context.l10n.toolDuplicateFinderSubtitle,
      iconColor: cs.primary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DuplicateFinderScreen(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildContainerSplitterRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.content_cut_rounded,
      title: context.l10n.toolContainerSplitterTitle,
      subtitle: context.l10n.toolContainerSplitterSubtitle,
      iconColor: cs.primary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ContainerSplitterSheet(),
        ),
      ),
    );
  }

  Widget _buildCompositeContainerRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.layers_rounded,
      title: context.l10n.toolCompositeContainerTitle,
      subtitle: context.l10n.toolCompositeContainerSubtitle,
      iconColor: cs.primary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const CompositeCreateSheet(),
        ),
      ),
    );
  }

  Widget _buildContainerRepairRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.build_rounded,
      title: context.l10n.toolContainerRepairTitle,
      subtitle: context.l10n.toolContainerRepairSubtitle,
      iconColor: cs.tertiary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContainerRepairSheet(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBackupRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.settings_backup_restore_rounded,
      title: context.l10n.toolHeaderBackupTitle,
      subtitle: context.l10n.toolHeaderBackupSubtitle,
      iconColor: cs.secondary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const HeaderBackupSheet(),
        ),
      ),
    );
  }
}

// ── REUSABLE TOOL ROW WITH REFINED M3 AFFORDANCE ─────────────────────────────

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
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: accent),
      ),
      title: Text(
        title,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.25,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
      ),
      onTap: onTap,
    );
  }
}