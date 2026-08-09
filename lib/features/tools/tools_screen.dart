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
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/tool_card.dart';

/// The "Tools" tab: utility workflows for standalone file/container
/// operations, grouped by category, as laid out in the Tools-page design
/// (Container Utilities / File Cryptography / Storage & Diagnostics).
///
/// Lives alongside [VaultDashboard] as the second [MainShell] tab. Doesn't
/// track its own mounted-volume state — [mountedContainers] is fed down
/// from [MainShell], which is in turn fed by [VaultDashboard.mountedNotifier],
/// so Storage Analyzer's target picker and Repair's "choose mounted
/// volume" option see the same live list the Vaults tab shows.
class ToolsScreen extends StatelessWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;

  const ToolsScreen({super.key, required this.mountedContainers});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.colors.surfaceContainerHigh,
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
          _ToolGrid(
            cards: [
              ToolCard(
                icon: Icons.content_cut_rounded,
                title: context.l10n.toolContainerSplitterTitle,
                subtitle: context.l10n.toolContainerSplitterSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ContainerSplitterSheet(),
                  ),
                ),
              ),
              ToolCard(
                icon: Icons.build_rounded,
                title: context.l10n.toolContainerRepairTitle,
                subtitle: context.l10n.toolContainerRepairSubtitle,
                iconColor: context.colors.tertiary,
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
          _ToolGrid(
            cards: [
              ToolCard(
                icon: Icons.enhanced_encryption_rounded,
                title: context.l10n.toolSingleFileCryptoTitle,
                subtitle: context.l10n.toolSingleFileCryptoSubtitle,
                iconColor: context.colors.secondary,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SingleFileCryptoSheet(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(context.l10n.toolsSectionStorageDiagnostics),
          _ToolGrid(
            cards: [
              ToolCard(
                icon: Icons.pie_chart_rounded,
                title: context.l10n.toolStorageAnalyzerTitle,
                subtitle: context.l10n.toolStorageAnalyzerSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StorageAnalyzerScreen(
                      mountedContainers: mountedContainers,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fixed two-column grid for a section's [ToolCard]s. A single leftover
/// card in an odd-count section spans the row rather than leaving an
/// awkward empty cell.
class _ToolGrid extends StatelessWidget {
  final List<Widget> cards;
  const _ToolGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    if (cards.length == 1) return cards.first;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.25,
      children: cards,
    );
  }
}