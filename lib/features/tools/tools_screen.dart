import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/activity/app_bar_clipboard_chip.dart';
import 'package:vaultexplorer/core/widgets/layout/section_card.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/widgets/container_repair_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/container_splitter_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/duplicate_finder_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/hash_verifier_sheet.dart';
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
        actions: const [
          AppBarClipboardButton(),
          SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: isLandscape
            ? _buildLandscapeBody(context)
            : _buildPortraitBody(context),
      ),
    );
  }

  // ── PORTRAIT MODE ──────────────────────────────────────────────────────────

  Widget _buildPortraitBody(BuildContext context) {
    final cs = context.colors;
    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        // 1. File Cryptography & Keys
        SectionHeader(context.l10n.toolsSectionFileCryptography),
        SectionCard(
          children: [
            _buildKeyfileGeneratorRow(context, cs, isCompact: false),
            _buildSingleFileCryptoRow(context, cs, isCompact: false),
            _buildHashVerifierRow(context, cs, isCompact: false),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // 2. Backup & Sync
        SectionHeader(context.l10n.toolsSectionBackupSync),
        SectionCard(
          children: [
            _buildVaultSyncRow(context, cs, isCompact: false),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // 3. Storage Diagnostics
        SectionHeader(context.l10n.toolsSectionStorageDiagnostics),
        SectionCard(
          children: [
            _buildStorageAnalyzerRow(context, cs, isCompact: false),
            _buildDuplicateFinderRow(context, cs, isCompact: false),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // 4. Container Utilities
        SectionHeader(context.l10n.toolsSectionContainerUtilities),
        SectionCard(
          children: [
            _buildContainerSplitterRow(context, cs, isCompact: false),
            _buildContainerRepairRow(context, cs, isCompact: false),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  // ── LANDSCAPE MODE (ALIGNED & ZERO-SCROLL FIT) ────────────────────────────

  Widget _buildLandscapeBody(BuildContext context) {
    final cs = context.colors;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left Column: Cryptography & Sync (4 items total) ──────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(context.l10n.toolsSectionFileCryptography),
                SectionCard(
                  children: [
                    _buildKeyfileGeneratorRow(context, cs, isCompact: true),
                    _buildSingleFileCryptoRow(context, cs, isCompact: true),
                    _buildHashVerifierRow(context, cs, isCompact: true),
                    _buildVaultSyncRow(context, cs, isCompact: true),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // ── Right Column: Diagnostics & Utilities (4 items total) ──────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(context.l10n.toolsSectionStorageDiagnostics),
                SectionCard(
                  children: [
                    _buildStorageAnalyzerRow(context, cs, isCompact: true),
                    _buildDuplicateFinderRow(context, cs, isCompact: true),
                    _buildContainerSplitterRow(context, cs, isCompact: true),
                    _buildContainerRepairRow(context, cs, isCompact: true),
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

  Widget _buildKeyfileGeneratorRow(BuildContext context, ColorScheme cs, {required bool isCompact}) {
    return _ToolRow(
      icon: Icons.key_rounded,
      title: context.l10n.keyfilePassphraseGeneratorTitle,
      subtitle: context.l10n.keyfilePassphraseGeneratorSubtitle,
      iconColor: cs.primary,
      isCompact: isCompact,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => KeyfilePassphraseGeneratorScreen(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildSingleFileCryptoRow(BuildContext context, ColorScheme cs, {required bool isCompact}) {
    return _ToolRow(
      icon: Icons.enhanced_encryption_rounded,
      title: context.l10n.toolSingleFileCryptoTitle,
      subtitle: context.l10n.toolSingleFileCryptoSubtitle,
      iconColor: cs.secondary,
      isCompact: isCompact,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SingleFileCryptoSheet(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildHashVerifierRow(BuildContext context, ColorScheme cs, {required bool isCompact}) {
    return _ToolRow(
      icon: Icons.verified_rounded,
      title: context.l10n.toolHashVerifierTitle,
      subtitle: context.l10n.toolHashVerifierSubtitle,
      iconColor: cs.secondary,
      isCompact: isCompact,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => HashVerifierSheet(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildVaultSyncRow(BuildContext context, ColorScheme cs, {required bool isCompact}) {
    return _ToolRow(
      icon: Icons.sync_alt_rounded,
      title: context.l10n.toolVaultSyncTitle,
      subtitle: context.l10n.toolVaultSyncSubtitle,
      iconColor: cs.secondary,
      isCompact: isCompact,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VaultSyncScreen(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildStorageAnalyzerRow(BuildContext context, ColorScheme cs, {required bool isCompact}) {
    return _ToolRow(
      icon: Icons.pie_chart_rounded,
      title: context.l10n.toolStorageAnalyzerTitle,
      subtitle: context.l10n.toolStorageAnalyzerSubtitle,
      iconColor: cs.tertiary,
      isCompact: isCompact,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StorageAnalyzerScreen(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildDuplicateFinderRow(BuildContext context, ColorScheme cs, {required bool isCompact}) {
    return _ToolRow(
      icon: Icons.difference_rounded,
      title: context.l10n.toolDuplicateFinderTitle,
      subtitle: context.l10n.toolDuplicateFinderSubtitle,
      iconColor: cs.primary,
      isCompact: isCompact,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DuplicateFinderScreen(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }

  Widget _buildContainerSplitterRow(BuildContext context, ColorScheme cs, {required bool isCompact}) {
    return _ToolRow(
      icon: Icons.content_cut_rounded,
      title: context.l10n.toolContainerSplitterTitle,
      subtitle: context.l10n.toolContainerSplitterSubtitle,
      iconColor: cs.primary,
      isCompact: isCompact,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ContainerSplitterSheet(),
        ),
      ),
    );
  }

  Widget _buildContainerRepairRow(BuildContext context, ColorScheme cs, {required bool isCompact}) {
    return _ToolRow(
      icon: Icons.build_rounded,
      title: context.l10n.toolContainerRepairTitle,
      subtitle: context.l10n.toolContainerRepairSubtitle,
      iconColor: cs.tertiary,
      isCompact: isCompact,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContainerRepairSheet(
            mountedContainers: mountedContainers,
          ),
        ),
      ),
    );
  }
}

// ── REUSABLE TOOL ROW ────────────────────────────────────────────────────────

class _ToolRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool isCompact;

  const _ToolRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final accent = iconColor ?? cs.primary;

    final iconContainerSize = isCompact ? 36.0 : 42.0;
    final iconGlyphSize = isCompact ? 18.0 : AppIconSize.small;
    final verticalPadding = isCompact ? 2.0 : 4.0;
    final horizontalPadding = isCompact ? 12.0 : 16.0;

    return ListTile(
      dense: isCompact,
      contentPadding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      leading: Container(
        width: iconContainerSize,
        height: iconContainerSize,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: iconGlyphSize, color: accent),
      ),
      title: Text(
        title,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: isCompact ? 18.0 : 22.0,
        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      onTap: onTap,
    );
  }
}